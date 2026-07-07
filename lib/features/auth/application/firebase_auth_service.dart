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

  /// google_sign_in v7 requires a one-time [GoogleSignIn.initialize]; cache the
  /// future so concurrent taps don't double-initialize.
  Future<void>? _googleInit;

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  Future<AppUser> signInWithGoogle() async {
    try {
      await _ensureGoogleInit();
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AuthFailure.google();

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await _auth.signInWithCredential(credential);
      return _requireUser(result, AuthProviderType.google);
    } catch (error, stack) {
      throw _mapError(error, stack, AuthProviderType.google);
    }
  }

  @override
  Future<AppUser> signInWithApple() async {
    try {
      // A nonce binds this request to the returned id-token, mitigating replay.
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      final result = await _auth.signInWithCredential(oauthCredential);
      final user = await _applyAppleName(result, appleCredential);
      return _requireUser(result, AuthProviderType.apple, override: user);
    } catch (error, stack) {
      throw _mapError(error, stack, AuthProviderType.apple);
    }
  }

  @override
  Future<void> signOut() async {
    await _signOutGoogle();
    await _auth.signOut();
  }

  @override
  Future<void> deleteSession() async {
    final user = _auth.currentUser;
    await _signOutGoogle();
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      // Deleting an old session requires a fresh login; fall back to sign-out
      // so the local session still ends cleanly.
      if (e.code == 'requires-recent-login') {
        await _auth.signOut();
        return;
      }
      rethrow;
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

  AppUser? _toAppUser(User? user) =>
      user == null ? null : _mapUser(user, _providerOf(user));

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
