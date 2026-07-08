import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/progress/application/achievement_service.dart'
    show clockProvider;
import 'rate_limit_result.dart';

/// A sliding-window quota for one action.
class _RateLimitRule {
  const _RateLimitRule({required this.maxRequests, required this.window});

  final int maxRequests;
  final Duration window;
}

/// Client-side, in-memory rate limiter — a foundation for abuse prevention.
///
/// It coalesces rapid bursts (e.g. a stuck retry loop or an automated abuser)
/// per action using a sliding window. Limits are generous so normal use is never
/// affected; this is a *foundation*, not the authoritative control — real
/// enforcement is server-side (see the server-validation seam).
class RateLimitService {
  RateLimitService(this._now);

  final DateTime Function() _now;

  /// Per-action windows. Deliberately generous vs. human interaction rates.
  static const Map<RateLimitedAction, _RateLimitRule> _rules = {
    RateLimitedAction.scan:
        _RateLimitRule(maxRequests: 20, window: Duration(minutes: 1)),
    RateLimitedAction.tutorMessage:
        _RateLimitRule(maxRequests: 30, window: Duration(minutes: 1)),
    RateLimitedAction.practiceGeneration:
        _RateLimitRule(maxRequests: 20, window: Duration(minutes: 1)),
  };

  final Map<RateLimitedAction, Queue<DateTime>> _hits = {};

  /// Records an attempt of [action] and returns whether it is allowed under the
  /// current window. Call this at the point the action is initiated.
  RateLimitResult check(RateLimitedAction action) {
    final rule = _rules[action]!;
    final now = _now();
    final windowStart = now.subtract(rule.window);
    final hits = _hits.putIfAbsent(action, Queue<DateTime>.new);

    // Drop timestamps that have aged out of the window.
    while (hits.isNotEmpty && hits.first.isBefore(windowStart)) {
      hits.removeFirst();
    }

    if (hits.length >= rule.maxRequests) {
      final retryAfter = hits.first.add(rule.window).difference(now);
      return RateLimitResult.limited(
        retryAfter: retryAfter.isNegative ? Duration.zero : retryAfter,
        reason: "You're doing that too fast — please wait a moment.",
      );
    }

    hits.addLast(now);
    return const RateLimitResult.allowed();
  }

  /// Clears all recorded hits (tests / sign-out).
  void reset() => _hits.clear();
}

/// Provides the app-wide [RateLimitService].
final Provider<RateLimitService> rateLimitServiceProvider =
    Provider<RateLimitService>(
  (ref) => RateLimitService(ref.watch(clockProvider)),
);
