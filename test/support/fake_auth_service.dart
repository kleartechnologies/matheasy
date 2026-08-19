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

/// A sample email/password-backed user for tests.
AppUser emailTestUser() => AppUser(
  id: 'email-uid-1',
  provider: AuthProviderType.email,
  isGuest: false,
  createdAt: DateTime(2024),
  displayName: 'Maya Chen',
  email: 'maya@example.com',
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
    AppUser? emailResult,
    this.googleError,
    this.appleError,
    this.emailError,
  }) : _current = initialUser,
       _googleResult = googleResult,
       _appleResult = appleResult,
       _emailResult = emailResult;

  AppUser? _current;
  final AppUser? _googleResult;
  final AppUser? _appleResult;
  final AppUser? _emailResult;
  final AuthFailure? googleError;
  final AuthFailure? appleError;
  final AuthFailure? emailError;

  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  int signOutCount = 0;
  int deleteCount = 0;
  int anonymousSessionCount = 0;
  int recentLoginCount = 0;
  int passwordReauthCount = 0;

  /// Every address handed to [sendPasswordReset], in call order.
  final List<String> passwordResetEmails = [];

  /// Set to make [sendPasswordReset] fail (e.g. `AuthFailure.network()`).
  AuthFailure? passwordResetError;

  /// Set to make [reauthenticateWithPassword] fail (wrong password, etc.).
  AuthFailure? passwordReauthError;

  /// Set to model the user cancelling (or failing) the re-authentication sheet
  /// that guards account deletion. When non-null [ensureRecentLogin] throws it,
  /// which must abort the delete with nothing destroyed.
  AuthFailure? recentLoginError;

  /// The uid [ensureAnonymousSession] hands back, and what a subsequent sign-in
  /// reports as [lastAnonymousUid]. `null` models a device that couldn't get an
  /// anonymous session at all.
  String? anonymousUid = 'anon-uid-1';

  String? _lastAnonymousUid;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => _current;

  @override
  String? get lastAnonymousUid => _lastAnonymousUid;

  @override
  Future<String?> ensureAnonymousSession() async {
    if (_current != null) return _current!.id;
    anonymousSessionCount++;
    return anonymousUid;
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    if (googleError != null) throw googleError!;
    final user = _googleResult ?? googleTestUser();
    _lastAnonymousUid = _current == null ? anonymousUid : null;
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AppUser> signInWithApple() async {
    if (appleError != null) throw appleError!;
    final user = _appleResult ?? appleTestUser();
    _lastAnonymousUid = _current == null ? anonymousUid : null;
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (emailError != null) throw emailError!;
    final user = _emailResult ?? emailTestUser();
    _lastAnonymousUid = _current == null ? anonymousUid : null;
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AppUser> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    if (emailError != null) throw emailError!;
    final user = (_emailResult ?? emailTestUser()).copyWith(displayName: name);
    _lastAnonymousUid = _current == null ? anonymousUid : null;
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetEmails.add(email);
    final error = passwordResetError;
    if (error != null) throw error;
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    passwordReauthCount++;
    final error = passwordReauthError;
    if (error != null) throw error;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> ensureRecentLogin() async {
    recentLoginCount++;
    final error = recentLoginError;
    if (error != null) throw error;
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
///
/// [ageConfirmed] seeds an adult birth year so `AdConsentGate` treats the test
/// user as someone who already answered the COPPA age prompt. Without it the
/// gate puts its (deliberately non-dismissible) dialog over the shell and every
/// navigation assertion below it fails. Pass `false` to exercise the gate.
Future<ProviderContainer> sessionContainer({
  bool onboarded = false,
  bool guest = false,
  bool ageConfirmed = true,
  AuthService? authService,
  AppUser? signedInUser,
}) async {
  SharedPreferences.setMockInitialValues({
    if (onboarded) 'session.onboarding_complete': true,
    if (guest) 'session.guest_mode': true,
    if (ageConfirmed) ...{
      'privacy.birth_year': DateTime.now().year - 25,
      'privacy.ad_consent_prompted': true,
    },
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
