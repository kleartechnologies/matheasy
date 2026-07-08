import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_logger.dart';
import '../../progress/application/achievement_service.dart' show clockProvider;
import '../domain/cloud_record.dart';
import '../domain/sync_domain.dart';
import '../domain/sync_metadata.dart';
import '../domain/sync_result.dart';
import 'cloud_repositories.dart';
import 'cloud_store.dart';
import 'sync_merge.dart';
import 'sync_store.dart';

/// The sync engine — orchestrates the offline-first exchange between the local
/// [SyncStore] and the remote [CloudStore], resolving conflicts via [SyncMerge].
///
/// It never touches controllers or UI: it moves already-serialized JSON and
/// reports which domains changed. The [SyncController] drives it and refreshes
/// the affected controllers.
abstract interface class SyncService {
  /// Full two-way reconcile for [uid]: download → merge (newest-wins / additive)
  /// → upload. Idempotent — re-running with no changes is a no-op.
  Future<SyncResult> syncAll(String uid);

  /// Uploads a single domain's current local copy (used by the debounced push
  /// after a local edit).
  Future<SyncResult> pushDomain(String uid, SyncDomain domain);

  /// Deletes every cloud document for [uid] (account deletion).
  Future<void> wipe(String uid);
}

/// Firestore-backed [SyncService]. Works against any [CloudStore], so tests use
/// the in-memory one and the app uses Firestore.
class FirestoreSyncService implements SyncService {
  FirestoreSyncService({
    required this.store,
    required this.cloudStore,
    required this.cloudRepositories,
    required this.clock,
  });

  final SyncStore store;
  final CloudStore cloudStore;
  final Map<SyncDomain, CloudRepository> cloudRepositories;
  final DateTime Function() clock;

  @override
  Future<SyncResult> syncAll(String uid) async {
    final now = clock();
    var metadata = store.readMetadata();
    final downloaded = <SyncDomain>{};
    final uploaded = <SyncDomain>{};

    try {
      final cloud = await cloudStore.fetchAll(uid);

      for (final domain in SyncDomain.values) {
        final localPayload = store.readPayload(domain);
        final localMeta = metadata.metaFor(domain);
        final cloudRecord = cloud[domain];

        if (cloudRecord == null && localPayload == null) {
          continue; // nothing anywhere
        }

        if (cloudRecord == null) {
          // Local-only → upload (guest → account migration path).
          final meta = _seedMeta(localMeta, now);
          await _push(uid, domain, localPayload!, meta);
          metadata = metadata.withMeta(domain, meta);
          uploaded.add(domain);
          continue;
        }

        if (localPayload == null) {
          // Cloud-only → download (returning user on a fresh device).
          await store.writePayload(domain, cloudRecord.payload);
          metadata = metadata.withMeta(domain, cloudRecord.meta);
          downloaded.add(domain);
          continue;
        }

        // Both present → merge and converge both sides.
        final remoteNewer = cloudRecord.meta.isNewerThan(localMeta);
        final merged = SyncMerge.merge(
          domain,
          local: localPayload,
          remote: cloudRecord.payload,
          remoteNewer: remoteNewer,
        );
        final changedLocal = !_jsonEquals(merged, localPayload);
        final changedCloud = !_jsonEquals(merged, cloudRecord.payload);
        final mergedMeta = RecordMeta(
          lastModified: _latest(localMeta.lastModified, cloudRecord.updatedAt),
          version: (localMeta.version > cloudRecord.version
                  ? localMeta.version
                  : cloudRecord.version) +
              (changedCloud ? 1 : 0),
        );

        if (changedLocal) {
          await store.writePayload(domain, merged);
          downloaded.add(domain);
        }
        if (changedCloud) {
          await _push(uid, domain, merged, mergedMeta);
          uploaded.add(domain);
        }
        metadata = metadata.withMeta(domain, mergedMeta);
      }

      await store.writeMetadata(metadata);
      await store.setLastSyncedAt(now);
      return SyncResult.success(downloaded: downloaded, uploaded: uploaded);
    } on CloudException catch (error) {
      if (error.isOffline) return SyncResult.offline();
      AppLogger.error('Cloud sync failed', error: error);
      return SyncResult.failure('Sync failed. Your data is safe on this device.');
    }
  }

  @override
  Future<SyncResult> pushDomain(String uid, SyncDomain domain) async {
    final payload = store.readPayload(domain);
    if (payload == null) return SyncResult.success();
    final meta = _seedMeta(store.readMetadata().metaFor(domain), clock());
    try {
      await _push(uid, domain, payload, meta);
      return SyncResult.success(uploaded: {domain});
    } on CloudException catch (error) {
      if (error.isOffline) return SyncResult.offline();
      AppLogger.error('Cloud push failed', error: error);
      return SyncResult.failure('Sync failed. Your data is safe on this device.');
    }
  }

  @override
  Future<void> wipe(String uid) => cloudStore.wipe(uid);

  Future<void> _push(
    String uid,
    SyncDomain domain,
    Map<String, dynamic> payload,
    RecordMeta meta,
  ) {
    final repo = cloudRepositories[domain]!;
    return repo.push(
      uid,
      CloudRecord(
        payload: payload,
        updatedAt: meta.lastModified,
        version: meta.version,
      ),
    );
  }

  /// Ensures a record about to be uploaded carries a real timestamp — a
  /// never-synced local record ([RecordMeta.zero]) is stamped `now`.
  RecordMeta _seedMeta(RecordMeta meta, DateTime now) =>
      meta.version == 0 ? RecordMeta(lastModified: now) : meta;

  static DateTime _latest(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  /// Order-independent deep equality for JSON payloads (used only to decide
  /// whether a write is needed — a false "changed" just costs an extra write).
  static bool _jsonEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}

/// Provides the active [SyncService].
final Provider<SyncService> syncServiceProvider = Provider<SyncService>((ref) {
  return FirestoreSyncService(
    store: ref.watch(syncStoreProvider),
    cloudStore: ref.watch(cloudStoreProvider),
    cloudRepositories: ref.watch(cloudRepositoriesProvider),
    clock: ref.watch(clockProvider),
  );
});
