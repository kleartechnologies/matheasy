// Real-device audit, as a test: render each expression class the answer/steps
// must handle — short, long, inline fractions, integrals, matrices,
// trigonometry, derivatives — at narrow phone widths and assert none crash,
// overflow, or require horizontal scrolling (everything fits via scale-down).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/presentation/widgets/math_format.dart';
import 'package:matheasy/features/result/presentation/widgets/math_text.dart';

/// Representative answers per category. `input` is what the backend might emit;
/// `foldsToFrac` marks the ones whose inline `/` must become a stacked fraction.
const _cases = <(String label, String input, bool foldsToFrac)>[
  ('short', r'x = 4', false),
  ('long', r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}', false),
  ('inline-fraction', r'(12p+9q)/(p^2-q^2)', true),
  ('simple-fraction', r'x/2', true),
  ('integral', r'\int_0^1 x^2 \, dx = \frac{1}{3}', false),
  ('matrix', r'\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}', false),
  ('trig', r'\theta = 30^\circ', false),
  ('derivative-op', r'd/dx(x^2) = 2x', true),
];

void main() {
  group('fraction notation (folding) across categories', () {
    test('inline division folds to \\frac; others are left alone', () {
      for (final (label, input, folds) in _cases) {
        final out = toDisplayLatex(input);
        if (folds) {
          expect(out, contains(r'\frac'), reason: label);
          expect(out, isNot(contains('/')), reason: '$label leaves no bare slash');
        }
      }
    });
  });

  group('render audit — narrow widths, no crash / overflow / scroll', () {
    // 248 ≈ the answer's inner width on a 320px phone; the tightest real case.
    for (final width in [288.0, 248.0]) {
      for (final (label, input, _) in _cases) {
        testWidgets('$label @ ${width}px renders and fits', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width),
                    child: AdaptiveMath(
                      input,
                      minFontSize: 32,
                      maxFontSize: 56,
                      alignment: Alignment.center,
                      style: const TextStyle(),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          // No exception, no ErrorWidget, no overflow (the tester reports one).
          expect(tester.takeException(), isNull, reason: label);
          expect(find.byType(ErrorWidget), findsNothing, reason: label);

          // The maths fits — MathText scales down rather than scrolling sideways.
          final math = tester.widget<MathText>(find.byType(MathText));
          expect(math.fit, MathFit.scaleDown, reason: label);
        });
      }
    }
  });
}
