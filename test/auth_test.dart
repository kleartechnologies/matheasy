// Stage 7 tests — Authentication & user foundation.
//
// Covers the AuthController session loop (restore / guest / sign-in / sign-out /
// delete), typed error handling, the derived router status, guest-only fallback
// and the local persistence store. Auth is exercised through a fake AuthService
// (no Firebase), so these are deterministic and offline.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/router/app_routes.dart';
import 'package:matheasy/core/router/route_guard.dart';
import 'package:matheasy/core/session/app_session.dart';
import 'package:matheasy/features/auth/application/auth_controller.dart';
import 'package:matheasy/features/auth/application/auth_service.dart';
import 'package:matheasy/features/auth/domain/app_user.dart';
import 'package:matheasy/features/auth/domain/auth_failure.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';

/// Lets the auth stream's first (async) event and any pending writes settle.
Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// Instantiates the auth chain and keeps it alive for the test.
void _activate(ProviderContainer container) {
  final sub = container.listen(authControllerProvider, (_, _) {});
  addTearDown(sub.close);
}

void main() {
  group('AuthController — session lifecycle', () {
    test('resolves to unauthenticated when there is no session', () async {
      final container = await sessionContainer();
      addTearDown(container.dispose);
      _activate(container);
      await _settle();

      expect(container.read(authControllerProvider).status,
          AuthStatus.unauthenticated);
    });

    test('guest mode is removed: a persisted guest_mode flag no longer '
        'creates a session — sign-in is required', () async {
      final container = await sessionContainer(guest: true);
      addTearDown(container.dispose);
      _activate(container);
      await _settle();

      expect(container.read(authControllerProvider).status,
          AuthStatus.unauthenticated);
    });

    test('restores a persisted cloud session on launch', () async {
      final container = await sessionContainer(signedInUser: googleTestUser());
      addTearDown(container.dispose);
      _activate(container);
      await _settle();

      final state = container.read(authControllerProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.isGuest, isFalse);
      expect(state.user!.provider, AuthProviderType.google);
    });

    test('Google sign-in produces a non-guest authenticated user', () async {
      final container = await sessionContainer(authService: FakeAuthService());
      addTearDown(container.dispose);
      _activate(container);
      await _settle();

      await container.read(authControllerProvider.notifier).signInWithGoogle();
      final state = container.read(authControllerProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.isGuest, isFalse);
      expect(state.user!.provider, AuthProviderType.google);
      expect(state.busy, isFalse);
    });

    test('Apple sign-in produces a non-guest authenticated user', () async {
      final container = await sessionContainer(authService: FakeAuthService());
      addTearDown(container.dispose);
      _activate(container);
      await _settle();

      await container.read(authControllerProvider.notifier).signInWithApple();
      final state = container.read(authControllerProvider);
      expect(state.user!.provider, AuthProviderType.apple);
      expect(state.isAuthenticated, isTrue);
    });

    test('delete session ends the account session', () async {
      final fake = FakeAuthService(initialUser: googleTestUser());
      final container = await sessionContainer(authService: fake);
      addTearDown(container.dispose);
      _activate(container);
      await _settle();

      await container.read(authControllerProvider.notifier).deleteSession();
      await _settle();

      expect(container.read(authControllerProvider).status,
          AuthStatus.unauthenticated);
      expect(fake.deleteCount, 1);
    });
  });

  group('AuthController — error handling', () {
    test('a provider failure surfaces (non-silent) and keeps status', () async {
      final fake = FakeAuthService(googleError: const AuthFailure.google());
      final container = await sessionContainer(authService: fake);
      addTearDown(container.dispose);
      _activate(container);
      await _settle();

      await container.read(authControllerProvider.notifier).signInWithGoogle();
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.failure?.type, AuthFailureType.googleFailed);
      expect(state.failure!.isSilent, isFalse);
      expect(state.busy, isFalse);
    });

    test('a cancelled sign-in is silent', () async {
      final fake = FakeAuthService(appleError: const AuthFailure.cancelled());
      final container = await sessionContainer(authService: fake);
      addTearDown(container.dispose);
      _activate(container);
      await _settle();

      await container.read(authControllerProvider.notifier).signInWithApple();
      final state = container.read(authControllerProvider);
      expect(state.failure?.type, AuthFailureType.cancelled);
      expect(state.failure!.isSilent, isTrue);
      expect(state.status, AuthStatus.unauthenticated);
    });

    test('clearFailure removes a surfaced error', () async {
      final fake = FakeAuthService(googleError: const AuthFailure.network());
      final container = await sessionContainer(authService: fake);
      addTearDown(container.dispose);
      _activate(container);
      await _settle();

      await container.read(authControllerProvider.notifier).signInWithGoogle();
      expect(container.read(authControllerProvider).failure, isNotNull);

      container.read(authControllerProvider.notifier).clearFailure();
      expect(container.read(authControllerProvider).failure, isNull);
    });
  });

  group('Unconfigured Firebase fallback', () {
    test('cloud sign-in reports notConfigured; stream is signed-out', () async {
      const service = UnconfiguredAuthService();
      expect(
        () => service.signInWithGoogle(),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.type,
            'type',
            AuthFailureType.notConfigured,
          ),
        ),
      );
      expect(await service.authStateChanges().first, isNull);
    });
  });

  group('Router status projection', () {
    test('guard sends an unauthenticated user to /auth after onboarding', () {
      final target = RouteGuard.evaluate(
        matchedLocation: AppRoutes.home,
        uri: Uri.parse(AppRoutes.home),
        authStatus: AuthStatus.unauthenticated,
        onboardingComplete: true,
        isPremium: false,
      );
      expect(target, AppRoutes.auth);
    });

    test('guard bounces an authenticated user away from /auth', () {
      final target = RouteGuard.evaluate(
        matchedLocation: AppRoutes.auth,
        uri: Uri.parse(AppRoutes.auth),
        authStatus: AuthStatus.authenticated,
        onboardingComplete: true,
        isPremium: false,
      );
      expect(target, AppRoutes.home);
    });
  });

  group('PreferencesStore — persistence foundation', () {
    test('round-trips onboarding + guest flags; clearSession is scoped',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferencesStore(await SharedPreferences.getInstance());

      expect(store.onboardingComplete, isFalse);
      expect(store.guestMode, isFalse);

      await store.setOnboardingComplete(value: true);
      await store.setGuestMode(value: true);
      expect(store.onboardingComplete, isTrue);
      expect(store.guestMode, isTrue);

      await store.clearSession();
      expect(store.guestMode, isFalse); // guest cleared…
      expect(store.onboardingComplete, isTrue); // …onboarding preserved
    });
  });
}
