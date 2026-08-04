import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/app_user.dart';
import '../domain/auth_failure.dart';
import 'auth_service.dart';

/// Real [AuthService] backed by Firebase Auth + Google Sign-In + Sign in with
/// Apple. Federated credentials (Google id-token / Apple id-token) are exchanged
/// for a Firebase session; Firebase persists and restores that session across
/// launches automatically.
///
/// All provider/SDK exceptions are funnelled through [_mapError] into typed
/// [AuthFailure]s so the controller/UI never see a raw platform exception.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _google = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  /// How long a sign-in counts as "recent" for a destructive operation. Firebase
  /// doesn't publish the exact threshold; this is deliberately shorter than any
  /// observed window, so we re-authenticate a little too eagerly rather than
  /// discover the session was stale after the data is already gone.
  static const Duration _recentLoginWindow = Duration(minutes: 2);

  /// google_sign_in v7 requires a one-time [GoogleSignIn.initialize]; cache the
  /// future so concurrent taps don't double-initialize.
  Future<void>? _googleInit;

  /// The anonymous uid held immediately before the last interactive sign-in.
  String? _lastAnonymousUid;

  /// De-duplicates concurrent [ensureAnonymousSession] calls (launch + a retry).
  Future<String?>? _anonymousSignIn;

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  String? get lastAnonymousUid => _lastAnonymousUid;

  @override
  Future<String?> ensureAnonymousSession() async {
    final existing = _auth.currentUser;
    if (existing != null) return existing.uid;
    final future = _anonymousSignIn ??= _signInAnonymously();
    try {
      return await future;
    } finally {
      // Drop the cached future either way so a later launch can retry rather
      // than re-await a permanently-settled one.
      _anonymousSignIn = null;
    }
  }

  Future<String?> _signInAnonymously() async {
    try {
      final result = await _auth.signInAnonymously();
      return result.user?.uid;
    } catch (error, stack) {
      // Best-effort by design: without an anonymous session the app behaves
      // exactly as it did before this layer existed — the user signs in and is
      // metered on their account. Never surface this; nothing asked for it.
      AppLogger.error(
        'Anonymous session unavailable',
        error: error,
        stackTrace: stack,
      );
      return null;
    }
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    _rememberAnonymousUid();
    try {
      final credential = await _googleCredential();
      final result = await _auth.signInWithCredential(credential);
      return _requireUser(result, AuthProviderType.google);
    } catch (error, stack) {
      throw _mapError(error, stack, AuthProviderType.google);
    }
  }

  @override
  Future<AppUser> signInWithApple() async {
    _rememberAnonymousUid();
    try {
      final (credential, apple) = await _appleCredential();
      final result = await _auth.signInWithCredential(credential);
      final user = await _applyAppleName(result, apple);
      return _requireUser(result, AuthProviderType.apple, override: user);
    } catch (error, stack) {
      throw _mapError(error, stack, AuthProviderType.apple);
    }
  }

  @override
  Future<void> ensureRecentLogin() async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;

    // Firebase only accepts a destructive operation behind a "recent" login.
    // The window it enforces is a few minutes; re-proving identity early — and
    // BEFORE the caller destroys anything — is what stops a delete from failing
    // half-way through, with the data already gone and the account still alive.
    final lastSignIn = user.metadata.lastSignInTime;
    if (lastSignIn != null &&
        DateTime.now().difference(lastSignIn) < _recentLoginWindow) {
      return;
    }
    await _reauthenticate(user);
  }

  /// Re-proves identity with whichever provider the account was created with.
  /// Surfaces a typed [AuthFailure] (including a silent `cancelled`) so the
  /// caller can abort cleanly rather than guess.
  Future<void> _reauthenticate(User user) async {
    final provider = _providerOf(user);
    try {
      final credential = switch (provider) {
        AuthProviderType.apple => (await _appleCredential()).$1,
        _ => await _googleCredential(),
      };
      await user.reauthenticateWithCredential(credential);
    } catch (error, stack) {
      throw _mapError(error, stack, provider);
    }
  }

  Future<AuthCredential> _googleCredential() async {
    await _ensureGoogleInit();
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw const AuthFailure.google();
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Returns the Firebase credential plus the raw Apple credential — the latter
  /// carries the name, which Apple only ever sends on the FIRST authorization.
  Future<(AuthCredential, AuthorizationCredentialAppleID)>
      _appleCredential() async {
    // A nonce binds this request to the returned id-token, mitigating replay.
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256(rawNonce);

    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    return (
      OAuthProvider('apple.com').credential(
        idToken: apple.identityToken,
        rawNonce: rawNonce,
        accessToken: apple.authorizationCode,
      ),
      apple,
    );
  }

  @override
  Future<void> signOut() async {
    await _signOutGoogle();
    await _auth.signOut();
  }

  @override
  Future<void> deleteSession() async {
    final user = _auth.currentUser;
    if (user == null) {
      await _signOutGoogle();
      return;
    }
    try {
      try {
        await user.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code != 'requires-recent-login') rethrow;
        // The session went stale between [ensureRecentLogin] and here (or the
        // caller skipped it). Re-prove identity and delete for real — signing
        // out instead would end the session while leaving the account, and its
        // PII, alive on a "delete my account" tap.
        await _reauthenticate(user);
        await (_auth.currentUser ?? user).delete();
      }
    } finally {
      // Always drop the local Google session, deleted or not, so a failed
      // delete doesn't leave a half-signed-in state behind.
      await _signOutGoogle();
    }
  }

  // ---- Helpers ----

  /// google_sign_in v7 needs a one-time [GoogleSignIn.initialize]. Cache the
  /// future to de-duplicate concurrent taps, but drop it on failure so a later
  /// attempt can retry instead of re-awaiting a permanently-rejected future.
  Future<void> _ensureGoogleInit() async {
    final future = _googleInit ??= _google.initialize();
    try {
      await future;
    } catch (_) {
      _googleInit = null;
      rethrow;
    }
  }

  Future<void> _signOutGoogle() async {
    try {
      await _ensureGoogleInit();
      await _google.signOut();
    } catch (error) {
      // Best-effort: never let a Google sign-out hiccup block the Firebase one.
      AppLogger.info('Google sign-out failed (ignored): $error');
    }
  }

  /// Captures the uid of the anonymous session (if that is what we're holding)
  /// just before a credential exchange replaces it, so the controller can ask
  /// the server to fold its usage into the account that is about to appear.
  void _rememberAnonymousUid() {
    final user = _auth.currentUser;
    _lastAnonymousUid = (user != null && user.isAnonymous) ? user.uid : null;
  }

  /// An ANONYMOUS Firebase user is not a user as far as this app is concerned.
  ///
  /// It exists only so the device has a server identity to register and meter
  /// against; mapping it to `null` keeps the whole app — the router's sign-in
  /// wall, `aiBackendReadyProvider`, the RevenueCat `logIn(uid)` binding —
  /// behaving byte-identically to before the anti-abuse layer was added. The
  /// anonymous uid is reachable only through [lastAnonymousUid], which exists
  /// for exactly one caller.
  AppUser? _toAppUser(User? user) => user == null || user.isAnonymous
      ? null
      : _mapUser(user, _providerOf(user));

  /// Maps a Firebase [User] onto the vendor-free [AppUser]. Lives here (not in
  /// the domain) so `app_user.dart` never imports firebase_auth.
  AppUser _mapUser(User user, AuthProviderType provider) => AppUser(
        id: user.uid,
        provider: provider,
        isGuest: false,
        createdAt: user.metadata.creationTime ??
            DateTime.fromMillisecondsSinceEpoch(0),
        displayName: (user.displayName?.trim().isEmpty ?? true)
            ? null
            : user.displayName,
        email: user.email,
        photoUrl: user.photoURL,
      );

  AuthProviderType _providerOf(User user) {
    for (final info in user.providerData) {
      switch (info.providerId) {
        case 'google.com':
          return AuthProviderType.google;
        case 'apple.com':
          return AuthProviderType.apple;
      }
    }
    return AuthProviderType.google;
  }

  AppUser _requireUser(
    UserCredential result,
    AuthProviderType provider, {
    User? override,
  }) {
    final user = override ?? result.user;
    if (user == null) throw const AuthFailure.unknown();
    return _mapUser(user, provider);
  }

  /// Apple only returns the user's name on the FIRST sign-in, and Firebase
  /// doesn't capture it automatically — persist it to the Firebase profile.
  Future<User?> _applyAppleName(
    UserCredential result,
    AuthorizationCredentialAppleID apple,
  ) async {
    final user = result.user;
    final hasName = user?.displayName?.trim().isNotEmpty ?? false;
    final given = apple.givenName?.trim() ?? '';
    final family = apple.familyName?.trim() ?? '';
    final appleName = [given, family].where((s) => s.isNotEmpty).join(' ');

    if (user == null || hasName || appleName.isEmpty) return user;

    await user.updateDisplayName(appleName);
    await user.reload();
    return _auth.currentUser ?? user;
  }

  AuthFailure _mapError(
    Object error,
    StackTrace stack,
    AuthProviderType provider,
  ) {
    if (error is AuthFailure) return error;

    if (error is GoogleSignInException) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        return const AuthFailure.cancelled();
      }
      return const AuthFailure.google();
    }

    if (error is SignInWithAppleAuthorizationException) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return const AuthFailure.cancelled();
      }
      return const AuthFailure.apple();
    }

    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'network-request-failed':
          return const AuthFailure.network();
        case 'user-disabled':
        case 'user-token-expired':
        case 'invalid-user-token':
          return const AuthFailure.expired();
        case 'canceled':
        case 'web-context-canceled':
          return const AuthFailure.cancelled();
      }
    }

    AppLogger.error('Auth failed ($provider)', error: error, stackTrace: stack);
    return provider == AuthProviderType.apple
        ? const AuthFailure.apple()
        : const AuthFailure.google();
  }

  static const String _nonceCharset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

  String _generateNonce([int length = 32]) {
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => _nonceCharset[random.nextInt(_nonceCharset.length)],
    ).join();
  }

  String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}
