import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/features/auth/application/auth_service.dart';
import 'package:matheasy/features/auth/domain/app_user.dart';
import 'package:matheasy/features/auth/domain/auth_failure.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sample Google-backed user for tests.
AppUser googleTestUser() => AppUser(
      id: 'google-uid-1',
      provider: AuthProviderType.google,
      isGuest: false,
      createdAt: DateTime(2024),
      displayName: 'Sarah Lee',
      email: 'sarah@example.com',
    );

/// A sample Apple-backed user for tests.
AppUser appleTestUser() => AppUser(
      id: 'apple-uid-1',
      provider: AuthProviderType.apple,
      isGuest: false,
      createdAt: DateTime(2024),
      displayName: 'Alex Kim',
      email: 'alex@example.com',
    );

/// A freshly-created account with NO profile name yet (e.g. an Apple relay that
/// hides the name) — exercises the honest 'Learner' fallback + empty first-day
/// dashboard.
AppUser newAccountUser() => AppUser(
      id: 'new-uid-1',
      provider: AuthProviderType.apple,
      isGuest: false,
      createdAt: DateTime(2024),
    );

/// An in-memory [AuthService] double — no Firebase, fully deterministic.
///
/// Mirrors the real service's contract: [authStateChanges] restores
/// [initialUser] on listen (like Firebase restoring a session), and successful
/// sign-ins both return the user and push it onto the stream.
class FakeAuthService implements AuthService {
  FakeAuthService({
    AppUser? initialUser,
    AppUser? googleResult,
    AppUser? appleResult,
    this.googleError,
    this.appleError,
  })  : _current = initialUser,
        _googleResult = googleResult,
        _appleResult = appleResult;

  AppUser? _current;
  final AppUser? _googleResult;
  final AppUser? _appleResult;
  final AuthFailure? googleError;
  final AuthFailure? appleError;

  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  int signOutCount = 0;
  int deleteCount = 0;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => _current;

  @override
  Future<AppUser> signInWithGoogle() async {
    if (googleError != null) throw googleError!;
    final user = _googleResult ?? googleTestUser();
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AppUser> signInWithApple() async {
    if (appleError != null) throw appleError!;
    final user = _appleResult ?? appleTestUser();
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> deleteSession() async {
    deleteCount++;
    _current = null;
    _controller.add(null);
  }

  void dispose() => _controller.close();
}

/// Builds a [ProviderContainer] a full-session test needs: seeded local
/// preferences plus a fake auth backend. Callers own disposal
/// (`addTearDown(container.dispose)`).
Future<ProviderContainer> sessionContainer({
  bool onboarded = false,
  bool guest = false,
  AuthService? authService,
  AppUser? signedInUser,
}) async {
  SharedPreferences.setMockInitialValues({
    if (onboarded) 'session.onboarding_complete': true,
    if (guest) 'session.guest_mode': true,
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authServiceProvider.overrideWithValue(
        authService ?? FakeAuthService(initialUser: signedInUser),
      ),
    ],
  );
}
