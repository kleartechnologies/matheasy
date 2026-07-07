import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../persistence/preferences_store.dart';

part 'app_session.g.dart';

/// Coarse authentication status of the current app session.
///
/// The rich auth state (user, provider, failures) lives in the auth feature;
/// this enum is the routing-facing projection the pure [RouteGuard] consumes,
/// exposed to the router via `authStatusProvider`. It lives in core so the
/// guard (also core) has no dependency on any feature.
enum AuthStatus { unknown, authenticated, unauthenticated }

/// Whether the user has completed onboarding.
///
/// STAGE 7: persisted locally via [PreferencesStore] and hydrated on launch, so
/// returning users skip straight past onboarding.
@riverpod
class OnboardingController extends _$OnboardingController {
  @override
  bool build() => ref.watch(preferencesStoreProvider).onboardingComplete;

  void complete() {
    unawaited(
      ref.read(preferencesStoreProvider).setOnboardingComplete(value: true),
    );
    state = true;
  }

  void reset() {
    unawaited(
      ref.read(preferencesStoreProvider).setOnboardingComplete(value: false),
    );
    state = false;
  }
}

/// Whether the user holds the `premium` entitlement.
///
/// STAGE 1 PLACEHOLDER: defaults to `false`. Stage 11 sources this from
/// RevenueCat entitlements.
@riverpod
class PremiumController extends _$PremiumController {
  @override
  bool build() => false;

  void setPremium({required bool value}) => state = value;
}
