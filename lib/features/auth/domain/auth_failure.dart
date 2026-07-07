import 'package:flutter/foundation.dart';

/// The category of an authentication failure, used to drive user-facing copy
/// and decide whether a failure is worth surfacing at all (cancellations are
/// silent).
enum AuthFailureType {
  /// The user backed out of the provider sheet — not a real error.
  cancelled,

  /// No / flaky connectivity.
  network,

  /// Apple Sign In failed (misconfiguration, revoked, or provider error).
  appleFailed,

  /// Google Sign In failed (misconfiguration, revoked, or provider error).
  googleFailed,

  /// The Firebase session expired or the credential is no longer valid.
  expiredSession,

  /// Firebase isn't configured yet (placeholder config) — sign-in unavailable.
  notConfigured,

  /// Anything we didn't specifically classify.
  unknown,
}

/// A domain-level authentication failure with a friendly, non-technical
/// [message] suitable to show the user directly.
@immutable
class AuthFailure implements Exception {
  const AuthFailure(this.type, this.message);

  final AuthFailureType type;
  final String message;

  /// Cancellations are intentional user actions — the UI stays silent for them.
  bool get isSilent => type == AuthFailureType.cancelled;

  const AuthFailure.cancelled()
      : type = AuthFailureType.cancelled,
        message = 'Sign-in cancelled.';

  const AuthFailure.network()
      : type = AuthFailureType.network,
        message =
            "You're offline. Check your connection and try again.";

  const AuthFailure.apple()
      : type = AuthFailureType.appleFailed,
        message = "Apple Sign-In didn't complete. Please try again.";

  const AuthFailure.google()
      : type = AuthFailureType.googleFailed,
        message = "Google Sign-In didn't complete. Please try again.";

  const AuthFailure.expired()
      : type = AuthFailureType.expiredSession,
        message = 'Your session expired. Please sign in again.';

  const AuthFailure.notConfigured()
      : type = AuthFailureType.notConfigured,
        message =
            'Sign-in isn’t available yet. You can continue as a guest.';

  const AuthFailure.unknown()
      : type = AuthFailureType.unknown,
        message = 'Something went wrong. Please try again.';

  @override
  String toString() => 'AuthFailure(${type.name}): $message';
}
