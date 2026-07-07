import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_user.dart';
import '../domain/auth_failure.dart';
import 'firebase_auth_service.dart';

/// The authentication provider — the one seam a real backend plugs into.
///
/// Mirrors [ScannerService]/[SolverService]/[TutorService]: the controller and
/// UI depend only on this interface and the domain models, so the backing
/// implementation ([FirebaseAuthService], a test fake, or a future provider)
/// can be swapped by overriding [authServiceProvider] with zero UI churn.
///
/// Guest mode is intentionally NOT here — it is a purely local concept owned by
/// [AuthRepository]. This interface is only the cloud identity layer.
abstract interface class AuthService {
  /// Emits the current cloud user (or `null`) and every subsequent change.
  /// Firebase restores a persisted session automatically, so this fires with
  /// the restored user on launch.
  Stream<AppUser?> authStateChanges();

  /// The currently cached cloud user, if any (synchronous).
  AppUser? get currentUser;

  /// Interactive Google sign-in. Throws [AuthFailure] on cancel/failure.
  Future<AppUser> signInWithGoogle();

  /// Interactive Apple sign-in. Throws [AuthFailure] on cancel/failure.
  Future<AppUser> signInWithApple();

  /// Ends the cloud session (keeps the account).
  Future<void> signOut();

  /// Permanently deletes the cloud account and ends the session.
  Future<void> deleteSession();
}

/// Whether Firebase initialized successfully this launch. Overridden in
/// `bootstrap` with the real result; defaults to `false` so tests and a
/// not-yet-provisioned checkout resolve to the guest-only path.
final Provider<bool> firebaseReadyProvider = Provider<bool>((ref) => false);

/// Provides the active [AuthService]. When Firebase is ready this is the real
/// [FirebaseAuthService]; otherwise a guest-only fallback keeps the app fully
/// usable (Guest mode) while cloud sign-in is unavailable.
final Provider<AuthService> authServiceProvider = Provider<AuthService>((ref) {
  return ref.watch(firebaseReadyProvider)
      ? FirebaseAuthService()
      : const UnconfiguredAuthService();
});

/// Guest-only fallback used before Firebase is provisioned (placeholder config)
/// or if initialization failed. Cloud sign-in reports [AuthFailure.notConfigured];
/// the app still runs fully as a guest.
class UnconfiguredAuthService implements AuthService {
  const UnconfiguredAuthService();

  @override
  Stream<AppUser?> authStateChanges() => Stream<AppUser?>.value(null);

  @override
  AppUser? get currentUser => null;

  @override
  Future<AppUser> signInWithGoogle() async =>
      throw const AuthFailure.notConfigured();

  @override
  Future<AppUser> signInWithApple() async =>
      throw const AuthFailure.notConfigured();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteSession() async {}
}
