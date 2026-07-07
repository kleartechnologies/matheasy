import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/session/app_session.dart' show AuthStatus;
import '../../onboarding/application/onboarding_controller.dart';
import '../domain/app_user.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_state.dart';
import '../domain/user_profile.dart';
import 'auth_repository.dart';

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

  /// Enters a local, cloud-free guest session.
  void continueAsGuest() {
    final guest = ref.read(authRepositoryProvider).continueAsGuest();
    state = AuthState.authenticated(guest);
  }

  /// Ends the session (keeps any cloud account).
  Future<void> signOut() => ref.read(authRepositoryProvider).signOut();

  /// Permanently deletes the cloud account (or ends a guest session).
  Future<void> deleteSession() =>
      ref.read(authRepositoryProvider).deleteSession();

  /// Dismisses a surfaced failure (e.g. after the snackbar is shown).
  void clearFailure() => state = state.copyWith(clearFailure: true, busy: false);

  Future<void> _runSignIn(Future<AppUser> Function() action) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearFailure: true);
    try {
      final user = await action();
      state = AuthState.authenticated(user);
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
