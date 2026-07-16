// Regression tests for the "Larger text" accessibility toggle
// (`_AccessibilityScope.largerTextScaler` in lib/app.dart).
//
// Two invariants, both learned the hard way:
//   1. The toggle must never render text SMALLER than the OS already asks for —
//      the original bug replaced the OS scaler with a flat 1.15x, shrinking text
//      for a learner at 2.0x system scale.
//   2. The scaler it produces must COMPOSE with a descendant that caps text
//      scaling (the tab bar clamps its micro-labels to 1.3x). A min-floored
//      `clamp` did not: clamping [0, 1.3] onto an inherited [floor, ∞] yields
//      [floor, 1.3], and Flutter's `_ClampedTextScaler` asserts `max > min`, so
//      any learner at OS scale ≥ ~1.13 crashed the tab bar on every build.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/app.dart';

void main() {
  const factor = 1.15; // AccessibilitySettings.textScale when largerText is on

  double effective(TextScaler s) => s.scale(16) / 16;

  group('largerTextScaler never shrinks text below the OS scale', () {
    for (final os in <double>[0.85, 1.0, 1.15, 1.3, 2.0, 3.0]) {
      test('OS ${os}x → at least ${os}x', () {
        final scaled = AccessibilityScope.largerTextScaler(
          TextScaler.linear(os),
          factor,
        );
        expect(
          effective(scaled),
          greaterThanOrEqualTo(os - 1e-9),
          reason: 'the toggle must never make text smaller than the OS asks',
        );
        // ...and it genuinely enlarges.
        expect(effective(scaled), closeTo(os * factor, 1e-9));
      });
    }
  });

  group('the produced scaler composes with a descendant text cap', () {
    // Mirrors app_tab_bar.dart: MediaQuery.withClampedTextScaling(max: 1.3)
    // ultimately calls inherited.clamp(minScaleFactor: 0, maxScaleFactor: 1.3).
    // Before the fix this threw for OS ≥ ~1.13.
    for (final os in <double>[0.85, 1.0, 1.15, 1.3, 2.0, 3.0]) {
      testWidgets('OS ${os}x under a 1.3x cap does not assert', (tester) async {
        final rootScaler = AccessibilityScope.largerTextScaler(
          TextScaler.linear(os),
          factor,
        );
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: rootScaler),
            child: Builder(
              builder: (context) => MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: const Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('label'),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'a capped descendant must not throw at OS ${os}x',
        );
      });
    }

    test('the composed result honours the cap (never overflows it)', () {
      // At OS 2.0x the root wants 2.3x, but a 1.3x-capped descendant must land
      // at 1.3x — not silently defeat the cap (the release-mode failure mode).
      final root = AccessibilityScope.largerTextScaler(
        const TextScaler.linear(2.0),
        factor,
      );
      final capped = root.clamp(maxScaleFactor: 1.3);
      expect(effective(capped), closeTo(1.3, 1e-9));
    });
  });
}
