/// The actions the client-side [RateLimitService] guards (a foundation for
/// abuse prevention; authoritative enforcement is server-side).
enum RateLimitedAction {
  scan('scan'),
  tutorMessage('tutor_message'),
  practiceGeneration('practice_generation'),
  visualGeneration('visual_generation');

  const RateLimitedAction(this.key);

  final String key;
}

/// The outcome of a rate-limit check.
class RateLimitResult {
  const RateLimitResult.allowed()
      : allowed = true,
        retryAfter = null,
        reason = null;

  const RateLimitResult.limited({required this.retryAfter, this.reason})
      : allowed = false;

  final bool allowed;

  /// How long the caller should wait before retrying (only when [allowed] is
  /// false).
  final Duration? retryAfter;

  /// A short, user-safe explanation.
  final String? reason;

  bool get isLimited => !allowed;
}
