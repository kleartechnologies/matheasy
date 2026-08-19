import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/session/app_session.dart' show AuthStatus;
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../domain/app_user.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_state.dart';
import '../domain/user_profile.dart';
import 'auth_repository.dart';
import 'identity_controller.dart';

part 'auth_controller.g.dart';

/// The single source of truth for the auth session.
///
/// Subscribes to the [AuthRepository]'s merged user stream (cloud + guest) and
/// projects it into an [AuthState]. Kept alive for the whole app so the session
/// survives navigation, and so a returning user's restored session is observed
/// exactly once on launch.
@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  StreamSubscription<AppUser?>? _sub;

  @override
  AuthState build() {
    final repository = ref.watch(authRepositoryProvider);
    _sub = repository.watchUser().listen(_onUserChanged);
    ref.onDispose(() => _sub?.cancel());
    return const AuthState.unknown();
  }

  void _onUserChanged(AppUser? user) {
    state = user == null
        ? const AuthState.unauthenticated()
        : AuthState.authenticated(user);
  }

  /// Interactive Google sign-in.
  Future<void> signInWithGoogle() =>
      _runSignIn(() => ref.read(authRepositoryProvider).signInWithGoogle());

  /// Interactive Apple sign-in.
  Future<void> signInWithApple() =>
      _runSignIn(() => ref.read(authRepositoryProvider).signInWithApple());

  /// Email/password sign-in. Same pipeline as the federated providers, so the
  /// anonymous-usage merge and the account-created analytics fire identically.
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) =>
      _runSignIn(() => ref
          .read(authRepositoryProvider)
          .signInWithEmail(email: email, password: password));

  /// Email/password account creation (with the learner's display name).
  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) =>
      _runSignIn(() => ref
          .read(authRepositoryProvider)
          .signUpWithEmail(name: name, email: email, password: password));

  /// Sends a password-reset email. Not a sign-in: no busy/failure state churn
  /// here — the caller owns its own progress UI and error surface.
  Future<void> sendPasswordReset(String email) =>
      ref.read(authRepositoryProvider).sendPasswordReset(email);

  /// Re-proves an email account's identity before a destructive action; the
  /// password-prompt counterpart of [ensureRecentLogin].
  Future<void> reauthenticateWithPassword(String password) =>
      ref.read(authRepositoryProvider).reauthenticateWithPassword(password);

  /// Ends the session (keeps any cloud account).
  Future<void> signOut() => ref.read(authRepositoryProvider).signOut();

  /// Re-proves identity before a destructive action, if the session is stale.
  Future<void> ensureRecentLogin() =>
      ref.read(authRepositoryProvider).ensureRecentLogin();

  /// Permanently deletes the cloud account.
  Future<void> deleteSession() =>
      ref.read(authRepositoryProvider).deleteSession();

  /// Dismisses a surfaced failure (e.g. after the snackbar is shown).
  void clearFailure() => state = state.copyWith(clearFailure: true, busy: false);

  Future<void> _runSignIn(Future<AppUser> Function() action) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearFailure: true);
    try {
      final user = await action();
      // Read BEFORE anything else awaits: this is the anonymous uid the device
      // was carrying a moment ago, and the sign-in that just happened replaced
      // it. Handing it to the server folds its spent usage into this account —
      // free usage is lifetime, so signing in must never hand out a fresh one.
      final previousUid = ref.read(authRepositoryProvider).lastAnonymousUid;
      state = AuthState.authenticated(user);
      // Fire-and-forget: identity bookkeeping must never delay or fail a
      // sign-in. Nothing depends on it client-side — the server re-derives
      // every allowance from the database on the next metered request.
      unawaited(
        ref.read(identityControllerProvider.notifier).linkAfterSignIn(previousUid),
      );
      // Interactive sign-in only — a silent session restore comes through the
      // stream, not here, so it isn't counted as a new account.
      unawaited(ref.read(analyticsServiceProvider).logEvent(
          AnalyticsEvent.accountCreated(provider: user.provider.name)));
    } on AuthFailure catch (failure) {
      // Keep the prior status; just surface the failure and stop the spinner.
      state = state.copyWith(busy: false, failure: failure);
    } catch (_) {
      state = state.copyWith(busy: false, failure: const AuthFailure.unknown());
    }
  }
}

/// The coarse session gate the router reads. Guest counts as authenticated so
/// guests can browse the whole app. Only notifies when the [AuthStatus] value
/// actually changes (busy/failure churn on [AuthState] is filtered out).
@Riverpod(keepAlive: true)
AuthStatus authStatus(Ref ref) => ref.watch(authControllerProvider).status;

/// The current [AppUser] (real or guest), or `null` when signed out.
@Riverpod(keepAlive: true)
AppUser? currentUser(Ref ref) => ref.watch(authControllerProvider).user;

/// The assembled [UserProfile] (identity + onboarding-derived preferences), or
/// `null` when signed out.
@riverpod
UserProfile? userProfile(Ref ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final onboarding = ref.watch(onboardingFlowControllerProvider);
  return UserProfile.from(user, onboarding);
}
