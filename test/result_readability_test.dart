// Readability guard for the Solution screen. Pumps the real result flow at a
// narrow phone width so a RenderFlex/overflow would fail the test, and asserts
// the Photomath-style sizing: the answer/problem/steps size ADAPTIVELY to their
// content and fit the width (no forced 60px, no sideways scrolling).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/result_screen.dart';
import 'package:matheasy/features/result/presentation/widgets/math_text.dart';
import 'package:matheasy/features/result/presentation/widgets/play_solution_overlay.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

const _linear = DetectedEquation(
  latex: r'2x + 5 = 13',
  confidence: 0.99,
  source: ScanSource.camera,
  kind: EquationKind.linear,
);

List<MathText> _maths(WidgetTester tester) =>
    tester.widgetList<MathText>(find.byType(MathText)).toList();

List<AdaptiveMath> _adaptive(WidgetTester tester) =>
    tester.widgetList<AdaptiveMath>(find.byType(AdaptiveMath)).toList();

void main() {
  // A narrow, tall phone: narrow width stresses the layout (an overflow throws),
  // tall keeps every step + control on-screen and findable.
  Future<void> pumpSolved(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ResultScreen(equation: _linear),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // solve delay
  }

  testWidgets('answer + problem size adaptively and never scroll sideways',
      (tester) async {
    await pumpSolved(tester);

    final adaptive = _adaptive(tester);
    // The answer band: up to 56 (short answers), never the old forced 60; the
    // floor is 34 so a long answer stays readable.
    final answer = adaptive.firstWhere((a) => a.maxFontSize == 56);
    expect(answer.minFontSize, 34);
    // The problem band: up to 40.
    expect(adaptive.any((a) => a.maxFontSize == 40), isTrue);

    // Nothing on the screen scrolls sideways — every rendered MathText fits.
    final maths = _maths(tester);
    expect(maths.every((m) => m.fit == MathFit.scaleDown), isTrue);

    // A short answer ("x = 4") takes the full 56 — adaptive sizing gives short
    // answers the big size instead of shrinking everything uniformly.
    expect(maths.any((m) => m.style.fontSize == 56), isTrue);

    expect(find.text('FINAL ANSWER'), findsOneWidget);
  });

  testWidgets('steps size adaptively (≤30) and never scroll once revealed',
      (tester) async {
    await pumpSolved(tester);
    await tester.tap(find.text('Reveal all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final adaptive = _adaptive(tester);
    // Step maths band is 22–30 (down from the previous fixed 30-and-scroll).
    expect(
      adaptive.any((a) => a.maxFontSize == 30 && a.minFontSize == 22),
      isTrue,
    );

    // Still nothing scrolls sideways, and no step is oversized.
    final maths = _maths(tester);
    expect(maths.every((m) => m.fit == MathFit.scaleDown), isTrue);
    expect(maths.every((m) => (m.style.fontSize ?? 0) <= 56), isTrue);
  });

  testWidgets('AdaptiveMath degrades gracefully on truncated LaTeX (no crash)',
      (tester) async {
    // Truncated OCR/vision fractions must render as plain text via the fallback,
    // not throw a FormatException out of the sizing LayoutBuilder and blank the
    // subtree with an ErrorWidget.
    for (final bad in [r'\frac{1}{2', r'\frac{\sqrt{2}}{3', r'x = \frac{1}{']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AdaptiveMath(
                bad,
                minFontSize: 34,
                maxFontSize: 56,
                style: const TextStyle(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: bad);
      expect(find.byType(ErrorWidget), findsNothing, reason: bad);
    }
  });

  testWidgets('Play walkthrough modal scrolls instead of overflowing on a '
      'tiny screen', (tester) async {
    // The one non-scrolling surface in the flow. Squeeze it: a small screen, a
    // wide fraction step at the enlarged size, long narration + verify text.
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const steps = [
      SolutionStep(
        title: 'Combine the fractions over a common denominator',
        resultLatex: r'\frac{3x + 5}{2x - 7} = \frac{11}{4}',
        detail: 'Multiply both sides by the denominators, then simplify the '
            'resulting linear equation carefully so the signs stay correct.',
        operationLabel: '× (2x - 7)',
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlaySolutionOverlay(
            steps: steps,
            verifyText: 'Substituting the answer back reproduces the original '
                'equation, so it checks out.',
            autoPlay: false,
          ),
        ),
      ),
    );
    await tester.pump();

    // A RenderFlex overflow would surface here as a caught exception; its
    // absence proves the modal scrolls its content vertically instead.
    expect(tester.takeException(), isNull);
    expect(find.byType(PlaySolutionOverlay), findsOneWidget);
  });
}
