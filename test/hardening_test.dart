// Step 9 (§10) client-side cost/safety: the rate-limit-vs-quota distinction
// that keeps a throttled user off the paywall. (Server rate limiter /
// moderation / solve-cache are tested in functions/test/hardening.test.ts.)

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/backend/functions_client.dart';

void main() {
  group('BackendException — rate-limit vs quota (paywall) distinction', () {
    test('a rate limit is NOT a quota → never routes to the paywall', () {
      const e = BackendException(
        "You're going too fast.",
        code: 'resource-exhausted',
        details: {'rateLimited': true, 'retryAfterSeconds': 30},
      );
      expect(e.isRateLimited, isTrue);
      expect(e.isQuotaExceeded, isFalse); // must not paywall a throttled user
    });

    test('a free-tier quota (no rateLimited flag) still routes to the paywall',
        () {
      const e = BackendException(
        'Free-tier limit reached.',
        code: 'resource-exhausted',
      );
      expect(e.isQuotaExceeded, isTrue);
      expect(e.isRateLimited, isFalse);
    });

    test('an explicit rateLimited:false is a quota', () {
      const e = BackendException(
        'Free-tier limit reached.',
        code: 'resource-exhausted',
        details: {'rateLimited': false},
      );
      expect(e.isQuotaExceeded, isTrue);
      expect(e.isRateLimited, isFalse);
    });
  });
}
