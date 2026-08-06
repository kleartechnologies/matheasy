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

  /// Establishes an ANONYMOUS Firebase session if this installation has no
  /// session at all, and returns the resulting uid (`null` if unavailable).
  ///
  /// This is layer 2 of the free-usage identity chain: a fresh install gets a
  /// server identity immediately, before anyone signs in, so the installation
  /// can be registered and any usage it accrues has somewhere to land. It is
  /// deliberately invisible to the rest of the app — an anonymous Firebase user
  /// maps to a `null` [AppUser] (see [FirebaseAuthService]), so the router still
  /// requires a real sign-in exactly as before. Nothing about the sign-in wall,
  /// routing or the paywall changes.
  ///
  /// Never throws; a device that can't get one is simply metered on its account
  /// and installation ledgers instead.
  Future<String?> ensureAnonymousSession();

  /// The anonymous uid this device was carrying immediately before the most
  /// recent successful interactive sign-in, or `null`.
  ///
  /// The controller hands it to the `linkIdentity` callable so the anonymous
  /// session's spent usage is absorbed by the account rather than abandoned —
  /// "anonymous usage should merge into the signed-in account".
  String? get lastAnonymousUid;

  /// Interactive Google sign-in. Throws [AuthFailure] on cancel/failure.
  Future<AppUser> signInWithGoogle();

  /// Interactive Apple sign-in. Throws [AuthFailure] on cancel/failure.
  Future<AppUser> signInWithApple();

  /// Email/password sign-in. Throws [AuthFailure] on failure
  /// (`invalidCredentials`, `invalidEmail`, `tooManyAttempts`, …).
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  });

  /// Email/password account creation. [name] becomes the display name so the
  /// app can greet the learner like it does for Google/Apple accounts.
  /// Throws [AuthFailure] on failure (`emailInUse`, `weakPassword`, …).
  Future<AppUser> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  });

  /// Sends a password-reset email. Deliberately succeeds for unknown addresses
  /// (no account enumeration); throws [AuthFailure] only for invalid input or
  /// transport problems.
  Future<void> sendPasswordReset(String email);

  /// Re-proves an email account's identity with its password. The counterpart
  /// of the federated re-auth inside [ensureRecentLogin], which cannot mint an
  /// email credential on its own — the UI collects the password and calls this.
  Future<void> reauthenticateWithPassword(String password);

  /// Ends the cloud session (keeps the account).
  Future<void> signOut();

  /// Re-proves the user's identity with their original provider if the cached
  /// session is too old for a destructive operation; a no-op when it is fresh
  /// (and for guest/anonymous sessions, which have nothing to re-prove).
  ///
  /// Call this BEFORE destroying anything. Firebase refuses to delete an account
  /// behind a stale session, and finding that out afterwards leaves the account
  /// alive with its data already wiped. Throws [AuthFailure] — including a silent
  /// `cancelled` — if the user backs out, so the caller can abort untouched.
  Future<void> ensureRecentLogin();

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
  Future<String?> ensureAnonymousSession() async => null;

  @override
  String? get lastAnonymousUid => null;

  @override
  Future<AppUser> signInWithGoogle() async =>
      throw const AuthFailure.notConfigured();

  @override
  Future<AppUser> signInWithApple() async =>
      throw const AuthFailure.notConfigured();

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async =>
      throw const AuthFailure.notConfigured();

  @override
  Future<AppUser> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async =>
      throw const AuthFailure.notConfigured();

  @override
  Future<void> sendPasswordReset(String email) async =>
      throw const AuthFailure.notConfigured();

  @override
  Future<void> reauthenticateWithPassword(String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> ensureRecentLogin() async {}

  @override
  Future<void> deleteSession() async {}
}
