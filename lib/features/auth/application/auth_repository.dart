import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/app_user.dart';
import 'auth_service.dart';

/// Exposes the cloud identity layer ([AuthService]) as a single merged user
/// stream. There is no guest mode: a signed-in cloud user is emitted, otherwise
/// `null` (signed out) — the router then requires sign-in.
class AuthRepository {
  AuthRepository({
    required AuthService authService,
    required PreferencesStore preferences,
  })  : _service = authService,
        _prefs = preferences {
    _cloudSub = _service.authStateChanges().listen((cloudUser) {
      _cloudUser = cloudUser;
      _emit();
    });
  }

  final AuthService _service;
  final PreferencesStore _prefs;

  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();
  StreamSubscription<AppUser?>? _cloudSub;
  AppUser? _cloudUser;

  /// The merged user stream the controller listens to.
  Stream<AppUser?> watchUser() => _controller.stream;

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(_resolve());
  }

  AppUser? _resolve() => _cloudUser;

  /// See [AuthService.ensureAnonymousSession] — the device's initial identity.
  /// It never reaches [watchUser]: an anonymous session still resolves to a
  /// `null` user, so the sign-in wall is unchanged.
  Future<String?> ensureAnonymousSession() => _service.ensureAnonymousSession();

  /// See [AuthService.lastAnonymousUid] — read straight after a sign-in.
  String? get lastAnonymousUid => _service.lastAnonymousUid;

  Future<AppUser> signInWithGoogle() => _service.signInWithGoogle();

  Future<AppUser> signInWithApple() => _service.signInWithApple();

  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) =>
      _service.signInWithEmail(email: email, password: password);

  Future<AppUser> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) =>
      _service.signUpWithEmail(name: name, email: email, password: password);

  Future<void> sendPasswordReset(String email) =>
      _service.sendPasswordReset(email);

  Future<void> reauthenticateWithPassword(String password) =>
      _service.reauthenticateWithPassword(password);

  Future<void> signOut() async {
    await _service.signOut();
    await _prefs.clearSession();
    _cloudUser = null;
    _emit();
  }

  Future<void> ensureRecentLogin() => _service.ensureRecentLogin();

  Future<void> deleteSession() async {
    await _service.deleteSession();
    await _prefs.clearSession();
    _cloudUser = null;
    _emit();
  }

  void dispose() {
    _cloudSub?.cancel();
    _controller.close();
  }
}

/// Provides the [AuthRepository], wired to the active [AuthService] and the
/// local [PreferencesStore].
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((ref) {
  final repository = AuthRepository(
    authService: ref.watch(authServiceProvider),
    preferences: ref.watch(preferencesStoreProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
