import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/session/app_session.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../progress/application/achievement_controller.dart';
import '../../progress/domain/achievement.dart';
import '../../subscription/application/subscription_controller.dart';
import '../domain/analytics_event.dart';
import 'analytics_service.dart';

part 'analytics_controller.g.dart';

/// Emits the analytics events derivable purely from app state, so no widget has
/// to. Kept alive from the app root ([MatheasyApp]) — NOT the shell — so it is
/// observing during onboarding and auth, before the tab shell mounts.
///
/// Observes: app open (once), onboarding completed, achievements unlocked, and
/// keeps the analytics user id + subscription tier in sync. `account_created`
/// is emitted from the interactive sign-in path in [AuthController] (a session
/// *restore* must not count as a new account), and the action/lifecycle events
/// (scan, tutor, practice, paywall, purchase, profile, sync) are emitted by
/// their own controllers via [analyticsServiceProvider].
@Riverpod(keepAlive: true)
class AnalyticsController extends _$AnalyticsController {
  final Set<AchievementId> _seenAchievements = {};

  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  @override
  void build() {
    unawaited(_analytics.logEvent(AnalyticsEvent.appOpened()));

    // Seed from current state so we don't re-emit history and so a returning,
    // already-signed-in user gets their id/tier set (ref.listen only fires on
    // future changes).
    final user = ref.read(currentUserProvider);
    unawaited(_analytics.setUserId(_cloudId(user)));
    _seenAchievements
        .addAll(ref.read(achievementControllerProvider).unlocks.keys);
    unawaited(_syncTier(ref.read(subscriptionControllerProvider).isPro));

    ref.listen(onboardingControllerProvider, (prev, next) {
      if (prev == false && next == true) {
        unawaited(_analytics.logEvent(AnalyticsEvent.onboardingCompleted()));
      }
    });
    ref.listen<AppUser?>(
      currentUserProvider,
      (_, next) => unawaited(_analytics.setUserId(_cloudId(next))),
    );
    ref.listen(subscriptionControllerProvider, (prev, next) {
      if (prev?.isPro != next.isPro) unawaited(_syncTier(next.isPro));
    });
    ref.listen(achievementControllerProvider, (_, next) {
      for (final id in next.unlocks.keys) {
        if (_seenAchievements.add(id)) {
          unawaited(
            _analytics.logEvent(AnalyticsEvent.achievementUnlocked(id: id.name)),
          );
        }
      }
    });
  }

  Future<void> _syncTier(bool isPro) =>
      _analytics.setUserProperty('subscription_tier', isPro ? 'pro' : 'free');

  /// The analytics user id for a signed-in cloud user, or `null` for guests /
  /// signed-out (which also clears it).
  String? _cloudId(AppUser? user) =>
      user != null && !user.isGuest ? user.id : null;
}
