import 'package:flutter/foundation.dart';

import '../../../core/session/app_session.dart' show AuthStatus;
import 'app_user.dart';
import 'auth_failure.dart';

/// Immutable snapshot of the authentication session.
///
/// [status] is the coarse gate the router reads (via a derived provider), while
/// [user] carries the full identity and [failure] the last surfaced error. A
/// guest is [AuthStatus.authenticated] for routing purposes but `user.isGuest`.
///
/// [busy] marks an in-flight interactive sign-in so the UI can show spinners
/// without changing the coarse [status] (which still reflects the last settled
/// session).
@immutable
class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.failure,
    this.busy = false,
  });

  const AuthState.unknown()
      : status = AuthStatus.unknown,
        user = null,
        failure = null,
        busy = false;

  const AuthState.unauthenticated({this.failure})
      : status = AuthStatus.unauthenticated,
        user = null,
        busy = false;

  const AuthState.authenticated(AppUser this.user)
      : status = AuthStatus.authenticated,
        failure = null,
        busy = false;

  final AuthStatus status;
  final AppUser? user;
  final AuthFailure? failure;
  final bool busy;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isUnknown => status == AuthStatus.unknown;
  bool get isGuest => user?.isGuest ?? false;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    AuthFailure? failure,
    bool clearFailure = false,
    bool? busy,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      failure: clearFailure ? null : (failure ?? this.failure),
      busy: busy ?? this.busy,
    );
  }
}
