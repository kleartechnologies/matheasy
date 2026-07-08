import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/persistence/preferences_store.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../practice/application/practice_progress_controller.dart';
import '../../profile/application/profile_controller.dart';
import '../../progress/application/achievement_controller.dart';
import '../../progress/application/achievement_service.dart' show clockProvider;
import '../../progress/application/stats_controller.dart';
import '../../settings/application/settings_controller.dart';
import '../../subscription/application/usage_controller.dart';
import '../domain/sync_domain.dart';
import '../domain/sync_metadata.dart';
import '../domain/sync_result.dart';
import '../domain/sync_state.dart';
import '../domain/sync_status.dart';
import 'sync_service.dart';
import 'sync_store.dart';

part 'sync_controller.g.dart';

/// Timings for background sync.
class SyncTimings {
  const SyncTimings._();

  /// How long to wait after the last local edit before pushing — coalesces a
  /// burst of edits into one upload.
  static const Duration debounce = Duration(seconds: 2);
}

/// The offline-first sync orchestrator.
///
/// Keeps the local store as the source of truth and mirrors it to the cloud:
/// * observes every synced controller and, on a *real* local change, debounces
///   an upload (authenticated users only — guests stay local);
/// * on sign-in / launch, runs a full reconcile (download → merge → upload) and
///   refreshes the controllers whose local copy changed;
/// * exposes a manual "sync now" and a cloud wipe for account deletion.
///
/// Controllers are never modified — they don't know the cloud exists.
@Riverpod(keepAlive: true)
class SyncController extends _$SyncController {
  Timer? _debounce;
  bool _disposed = false;
  final Set<SyncDomain> _dirty = {};

  /// The raw JSON last known to agree with the cloud, per domain. Lets us tell a
  /// genuine local edit from the echo of a just-applied download (which must not
  /// bounce straight back up).
  final Map<SyncDomain, String?> _syncedRaw = {};

  @override
  SyncState build() {
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
    });

    // React to sign-in / sign-out.
    ref.listen<AppUser?>(currentUserProvider, _onUserChanged);

    // Observe each synced domain for local edits.
    ref.listen(profileControllerProvider,
        (_, _) => _onLocalChange(SyncDomain.profile));
    ref.listen(settingsControllerProvider,
        (_, _) => _onLocalChange(SyncDomain.settings));
    ref.listen(practiceProgressControllerProvider,
        (_, _) => _onLocalChange(SyncDomain.progress));
    ref.listen(achievementControllerProvider,
        (_, _) => _onLocalChange(SyncDomain.achievements));
    ref.listen(usageControllerProvider,
        (_, _) => _onLocalChange(SyncDomain.usage));
    ref.listen(statsControllerProvider,
        (_, _) => _onLocalChange(SyncDomain.analytics));

    final store = ref.read(syncStoreProvider);
    _seedBaseline(store);

    final user = ref.read(currentUserProvider);
    final lastSynced = store.lastSyncedAt;
    if (_isCloudUser(user)) {
      // Launch background sync for an already-signed-in (restored) session.
      Future.microtask(() => _runFullSync(user!.id));
      return SyncState(status: SyncStatus.notSynced, lastSyncedAt: lastSynced);
    }
    return SyncState(lastSyncedAt: lastSynced); // disabled by default
  }

  // ---- Public API ----

  /// Manually triggers a full reconcile. No-op for guests.
  Future<SyncResult> syncNow() {
    final user = ref.read(currentUserProvider);
    if (!_isCloudUser(user)) return Future.value(SyncResult.skipped());
    return _runFullSync(user!.id);
  }

  // ---- Auth transitions ----

  void _onUserChanged(AppUser? prev, AppUser? next) =>
      unawaited(_handleUserChange(prev, next));

  Future<void> _handleUserChange(AppUser? prev, AppUser? next) async {
    final prevCloud = _isCloudUser(prev);
    final nextCloud = _isCloudUser(next);
    final sameUser = prevCloud && nextCloud && prev!.id == next!.id;
    if (sameUser) return; // just profile churn, not an account boundary

    // A real account's local session is ending (sign-out, or switching to a
    // different account / guest). Its data is safely in the cloud, so wipe the
    // on-device footprint — otherwise the NEXT account inherits it (a privacy
    // leak) on a shared device. Guest sign-out is intentionally NOT cleared:
    // guest progress is meant to persist locally.
    if (prevCloud) {
      _debounce?.cancel();
      _dirty.clear();
      await _clearLocalAccountData();
      if (_disposed) return;
    }

    if (!nextCloud) {
      state = const SyncState(); // disabled, no last-sync for this device
      return;
    }

    // Sign-in → reconcile (download → merge → upload). This performs the
    // guest→account migration.
    final store = ref.read(syncStoreProvider);
    _syncedRaw.clear();
    _seedBaseline(store);
    // Guest edits never stamped metadata (the observer skips guests), so their
    // local records look epoch-old and would lose newest-wins to a pre-existing
    // cloud copy. Stamp any un-stamped local data "now" so the migrating user's
    // latest profile/settings actually win.
    await _stampUnsyncedLocalData(store);
    if (_disposed) return;
    unawaited(_runFullSync(next!.id));
  }

  /// Wipes this device's learning data + sync metadata and refreshes the
  /// controllers, so a departing real account leaves nothing behind.
  Future<void> _clearLocalAccountData() async {
    await ref.read(preferencesStoreProvider).clearLearningData();
    _refreshControllers(SyncDomain.values.toSet());
    _seedBaseline(ref.read(syncStoreProvider));
  }

  /// Stamps local domains that have data but no metadata (guest edits) with a
  /// real timestamp, so the migration treats them as the newest edits.
  Future<void> _stampUnsyncedLocalData(SyncStore store) async {
    final now = ref.read(clockProvider)();
    var metadata = store.readMetadata();
    var changed = false;
    for (final domain in SyncDomain.values) {
      final hasLocal = store.readRaw(domain) != null;
      if (hasLocal && metadata.metaFor(domain).version == 0) {
        metadata = metadata.withMeta(domain, RecordMeta(lastModified: now));
        changed = true;
      }
    }
    if (changed) await store.writeMetadata(metadata);
  }

  // ---- Local edit observation ----

  void _onLocalChange(SyncDomain domain) {
    final user = ref.read(currentUserProvider);
    if (!_isCloudUser(user)) return;

    final store = ref.read(syncStoreProvider);
    final raw = store.readRaw(domain);
    if (raw == _syncedRaw[domain]) return; // no real change / download echo

    // A genuine local edit — stamp new metadata and schedule an upload.
    final now = ref.read(clockProvider)();
    final metadata = store.readMetadata();
    final bumped = metadata.metaFor(domain).bumped(now);
    unawaited(store.writeMetadata(metadata.withMeta(domain, bumped)));

    _dirty.add(domain);
    _debounce?.cancel();
    _debounce = Timer(SyncTimings.debounce, () => unawaited(_flush(user!.id)));
  }

  Future<void> _flush(String uid) async {
    if (_dirty.isEmpty || _disposed) return;
    final domains = {..._dirty};
    _dirty.clear();
    state = state.copyWith(status: SyncStatus.syncing, clearMessage: true);

    final store = ref.read(syncStoreProvider);
    final service = ref.read(syncServiceProvider);
    var offline = false;
    var failed = false;

    for (final domain in domains) {
      final result = await service.pushDomain(uid, domain);
      if (_disposed) return;
      if (result.ok) {
        _syncedRaw[domain] = store.readRaw(domain);
      } else {
        _dirty.add(domain); // retry on the next trigger / launch sync
        result.offline ? offline = true : failed = true;
      }
    }

    if (offline) {
      state = state.copyWith(
        status: SyncStatus.offline,
        message: 'Offline — changes will sync when you reconnect.',
      );
    } else if (failed) {
      state = state.copyWith(
        status: SyncStatus.error,
        message: 'Sync failed. Your data is safe on this device.',
      );
    } else {
      final now = ref.read(clockProvider)();
      await store.setLastSyncedAt(now);
      if (_disposed) return;
      state = state.copyWith(
        status: SyncStatus.synced,
        lastSyncedAt: now,
        clearMessage: true,
      );
    }
  }

  // ---- Full reconcile ----

  Future<SyncResult> _runFullSync(String uid) async {
    if (state.status == SyncStatus.syncing) return SyncResult.skipped();
    state = state.copyWith(status: SyncStatus.syncing, clearMessage: true);

    final result = await ref.read(syncServiceProvider).syncAll(uid);
    if (_disposed) return result;

    // Rebaseline against what's now local (merged), so the download echo from
    // refreshing controllers doesn't bounce back up.
    _seedBaseline(ref.read(syncStoreProvider));

    if (result.ok) {
      final store = ref.read(syncStoreProvider);
      state = state.copyWith(
        status: SyncStatus.synced,
        lastSyncedAt: store.lastSyncedAt ?? ref.read(clockProvider)(),
        clearMessage: true,
      );
      unawaited(ref.read(analyticsServiceProvider).logEvent(
          AnalyticsEvent.syncCompleted(
              downloaded: result.downloaded.length,
              uploaded: result.uploaded.length)));
      if (result.changedLocal) _refreshControllers(result.downloaded);
    } else if (result.offline) {
      state = state.copyWith(
        status: SyncStatus.offline,
        message: 'Offline — will sync when you reconnect.',
      );
    } else {
      state = state.copyWith(
        status: SyncStatus.error,
        message: result.error ?? 'Sync failed.',
      );
    }
    return result;
  }

  /// Re-hydrates the controllers whose local copy was replaced by cloud data, so
  /// the UI reflects the merged result. They re-read from the (now updated)
  /// local store on rebuild.
  void _refreshControllers(Set<SyncDomain> domains) {
    for (final domain in domains) {
      switch (domain) {
        case SyncDomain.profile:
          ref.invalidate(profileControllerProvider);
        case SyncDomain.settings:
          ref.invalidate(settingsControllerProvider);
        case SyncDomain.progress:
          ref.invalidate(practiceProgressControllerProvider);
        case SyncDomain.achievements:
          ref.invalidate(achievementControllerProvider);
        case SyncDomain.usage:
          ref.invalidate(usageControllerProvider);
        case SyncDomain.analytics:
          ref.invalidate(statsControllerProvider);
      }
    }
  }

  void _seedBaseline(SyncStore store) {
    for (final domain in SyncDomain.values) {
      _syncedRaw[domain] = store.readRaw(domain);
    }
  }

  bool _isCloudUser(AppUser? user) => user != null && !user.isGuest;
}
