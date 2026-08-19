import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/persistence/preferences_store.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../auth/application/auth_controller.dart';
import '../../practice/application/practice_progress_controller.dart';
import '../../progress/application/achievement_controller.dart';
import '../../progress/application/progress_controller.dart';
import '../../progress/application/stats_controller.dart';
import '../../settings/application/settings_controller.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../subscription/application/subscription_service.dart';
import '../../subscription/application/usage_controller.dart';
import '../../sync/application/sync_service.dart';
import '../domain/editable_profile.dart';
import '../domain/profile_avatar.dart';
import '../domain/profile_view.dart';
import 'editable_profile_controller.dart';

part 'profile_controller.g.dart';

/// Assembles the [ProfileView] the Profile screen renders — identity (auth),
/// editable fields (name + avatar) and headline stats (progress) — and owns the
/// profile-scoped account actions (edit, sign out, delete).
///
/// Reactive: rebuilds when the signed-in user, aggregated progress, or the
/// saved editable profile changes (the editable slice is WATCHED via
/// [editableProfileControllerProvider], so every rename propagates here and
/// to every other watcher — the Progress screen included).
@Riverpod(keepAlive: true)
class ProfileController extends _$ProfileController {
  @override
  ProfileView build() {
    final user = ref.watch(currentUserProvider);
    final overview = ref.watch(progressControllerProvider);
    final editable = ref.watch(editableProfileControllerProvider);
    return ProfileView.assemble(
      user: user,
      overview: overview,
      editable: editable,
    );
  }

  void _updateEditable(EditableProfile next) {
    // The shared controller persists and notifies; our `watch` rebuilds this
    // snapshot (and the Progress overview) from it.
    ref.read(editableProfileControllerProvider.notifier).save(next);
    unawaited(ref
        .read(analyticsServiceProvider)
        .logEvent(AnalyticsEvent.profileEdited()));
  }

  /// Saves the editable profile from the edit form (name override + avatar).
  /// A blank name clears the override so the account name shows through.
  void saveProfile({String? displayName, required ProfileAvatar avatar}) {
    final trimmed = displayName?.trim();
    final hasName = trimmed != null && trimmed.isNotEmpty;
    _updateEditable(
      EditableProfile(displayName: hasName ? trimmed : null, avatar: avatar),
    );
  }

  /// Ends the session (keeps the account). The router redirects to `/auth`.
  Future<void> signOut() => ref.read(authControllerProvider.notifier).signOut();

  /// Permanently deletes the account (or ends the guest session) AND wipes every
  /// on-device learning artifact, then rebuilds the local controllers so nothing
  /// stale survives. Integrates with the Stage 7 auth services.
  Future<void> deleteAccount() async {
    // Wipe cloud data first, while still authenticated (Firestore rules require
    // the matching uid). Uses the sync *service* directly — not the sync
    // controller, which observes this controller — to avoid a provider cycle.
    // Best-effort: local deletion proceeds even if the cloud wipe fails.
    final user = ref.read(currentUserProvider);
    if (user != null && !user.isGuest) {
      // Re-prove identity FIRST. Firebase refuses to delete an account behind a
      // stale session, and discovering that after the wipe would leave the
      // account — and its PII — alive with the learning data already gone.
      // Throws (including a silent cancel) if the user can't or won't confirm,
      // which aborts the whole deletion with nothing yet destroyed.
      await ref.read(authControllerProvider.notifier).ensureRecentLogin();
      try {
        await ref.read(syncServiceProvider).wipe(user.id);
      } catch (_) {
        // Offline / already-signed-out — local deletion still proceeds.
      }
    }
    await ref.read(authControllerProvider.notifier).deleteSession();
    await ref.read(preferencesStoreProvider).clearLearningData();
    ref
      ..invalidate(practiceProgressControllerProvider)
      ..invalidate(statsControllerProvider)
      ..invalidate(achievementControllerProvider)
      ..invalidate(settingsControllerProvider)
      ..invalidate(usageControllerProvider)
      // Rebuild the subscription service + controller from the now-wiped cache
      // so the in-memory entitlement matches disk (the offline fallback would
      // otherwise leak a locally-granted Pro to the next in-session guest; a
      // real RevenueCat entitlement simply re-syncs from the store).
      ..invalidate(subscriptionServiceProvider)
      ..invalidate(subscriptionControllerProvider)
      // The editable profile lives in its own shared controller now — rebuild
      // it from the wiped store so the next user never sees this name.
      ..invalidate(editableProfileControllerProvider)
      ..invalidateSelf();
  }
}
