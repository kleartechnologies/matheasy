// Step 9 (§10) client-side cost/safety: the auto-capture steadiness logic and
// the rate-limit-vs-quota distinction that keeps a throttled user off the
// paywall. (Server rate limiter / moderation / solve-cache are tested in
// functions/test/hardening.test.ts.)

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/backend/functions_client.dart';
import 'package:matheasy/features/scan/application/steadiness_detector.dart';

void main() {
  group('SteadinessDetector — auto-capture trigger', () {
    test('fires only after the phone is still for the steady window', () {
      final d = SteadinessDetector();
      // Still, but not long enough yet.
      expect(d.isReadyToCapture(0.1, 1000), isFalse);
      expect(d.isReadyToCapture(0.1, 1400), isFalse);
      // Crossed 800ms of stillness → ready.
      expect(d.isReadyToCapture(0.1, 1850), isTrue);
    });

    test('fires once, then needs a move to re-arm (no machine-gunning)', () {
      final d = SteadinessDetector();
      d.isReadyToCapture(0.1, 0);
      expect(d.isReadyToCapture(0.1, 900), isTrue);
      d.disarm(); // caller fired the shutter

      // Holding still after firing must NOT keep triggering.
      expect(d.isReadyToCapture(0.1, 1000), isFalse);
      expect(d.isReadyToCapture(0.1, 2000), isFalse);

      // A deliberate move (spike over moveThreshold) re-arms; then stillness
      // fires again.
      expect(d.isReadyToCapture(3.0, 2100), isFalse); // the re-aim
      d.isReadyToCapture(0.1, 2200);
      expect(d.isReadyToCapture(0.1, 3100), isTrue);
    });

    test('drift restarts the stillness clock (no premature fire)', () {
      final d = SteadinessDetector();
      d.isReadyToCapture(0.1, 0);
      // A wobble below the move spike but above "still" resets the timer.
      expect(d.isReadyToCapture(0.6, 400), isFalse);
      expect(d.isReadyToCapture(0.1, 500), isFalse); // clock restarted at 500
      expect(d.isReadyToCapture(0.1, 900), isFalse); // only 400ms still
      expect(d.isReadyToCapture(0.1, 1350), isTrue); // now 850ms still
    });

    test('progress ramps 0→1 across the window', () {
      final d = SteadinessDetector();
      d.isReadyToCapture(0.1, 0);
      expect(d.progress(0), closeTo(0.0, 0.01));
      expect(d.progress(400), closeTo(0.5, 0.01));
      expect(d.progress(800), closeTo(1.0, 0.01));
      d.isReadyToCapture(5.0, 900); // a move zeroes progress
      expect(d.progress(900), 0);
    });
  });

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
