import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/app_user.dart';
import 'auth_service.dart';

/// Orchestrates the cloud identity layer ([AuthService]) with the local-only
/// guest session ([PreferencesStore]) and exposes a single merged user stream.
///
/// Resolution order per emission: a signed-in cloud user wins; otherwise a
/// persisted guest; otherwise `null` (signed out). Guest is never sent to the
/// cloud — it exists only as a local flag, so guest data stays on-device.
class AuthRepository {
  AuthRepository({
    required AuthService authService,
    required PreferencesStore preferences,
    required DateTime Function() clock,
  })  : _service = authService,
        _prefs = preferences,
        _clock = clock {
    _cloudSub = _service.authStateChanges().listen((cloudUser) {
      _cloudUser = cloudUser;
      _emit();
    });
  }

  final AuthService _service;
  final PreferencesStore _prefs;
  final DateTime Function() _clock;

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

  AppUser? _resolve() {
    if (_cloudUser != null) return _cloudUser;
    if (_prefs.guestMode) return AppUser.guest(createdAt: _clock());
    return null;
  }

  Future<AppUser> signInWithGoogle() async {
    final user = await _service.signInWithGoogle();
    await _prefs.setGuestMode(value: false); // upgraded away from guest
    return user;
  }

  Future<AppUser> signInWithApple() async {
    final user = await _service.signInWithApple();
    await _prefs.setGuestMode(value: false);
    return user;
  }

  /// Starts a local, cloud-free guest session and persists it across launches.
  AppUser continueAsGuest() {
    unawaited(_prefs.setGuestMode(value: true));
    _cloudUser = null;
    final guest = AppUser.guest(createdAt: _clock());
    _emit();
    return guest;
  }

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
    clock: DateTime.now,
  );
  ref.onDispose(repository.dispose);
  return repository;
});
