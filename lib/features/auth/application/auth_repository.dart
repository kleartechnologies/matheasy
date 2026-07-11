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

  Future<AppUser> signInWithGoogle() => _service.signInWithGoogle();

  Future<AppUser> signInWithApple() => _service.signInWithApple();

  Future<void> signOut() async {
    await _service.signOut();
    await _prefs.clearSession();
    _cloudUser = null;
    _emit();
  }

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
