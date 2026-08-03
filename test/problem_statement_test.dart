// The one rule this component exists to keep: a student never sees LaTeX.
//
// The reported bug was a scan whose instruction and equation arrived as one
// string — `\text{Solve the equation} \\ 9^{4x-3} = ...`. flutter_math can't
// typeset a top-level `\\`, so the whole line fell through to the error
// fallback and the source was printed on the screen. These tests pump the real
// widgets and assert that nothing on screen carries a backslash.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/widgets/math_format.dart';
import 'package:matheasy/features/result/presentation/widgets/math_text.dart';
import 'package:matheasy/features/result/presentation/widgets/problem_card.dart';
import 'package:matheasy/features/result/presentation/widgets/problem_statement.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

/// The exact string from the bug report.
const _reported =
    r'\text{Solve the equation} \\ 9^{4x-3} =\frac{1}{3\sqrt{3}}';

ResultData _result(String latex) => ResultData(
      equation: DetectedEquation(
        latex: latex,
        confidence: 0.85,
        source: ScanSource.camera,
        kind: EquationKind.expression,
      ),
      type: ResultType.expression,
      difficulty: Difficulty.medium,
      answerLatex: r'x = \frac{5}{8}',
      verifyText: 'Checked ✓',
      tutorIntro: '',
      steps: const [],
      explanations: const [],
      methods: const [],
      practice: const [],
    );

/// Every string the widget tree would actually paint.
List<String> _onScreen(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .toList();

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the reported scan: instruction as prose, equation typeset',
      (tester) async {
    await _pump(tester, const ProblemStatement(latex: _reported));

    // The instruction reads as a sentence — not as `\text{...}`.
    expect(find.text('Solve the equation'), findsOneWidget);
    // And the maths is handed to the typesetter on its own, without the `\\`
    // that made the whole line unrenderable.
    final maths = tester.widgetList<AdaptiveMath>(find.byType(AdaptiveMath));
    expect(maths, hasLength(1));
    expect(maths.single.latex, r'9^{4x-3} =\frac{1}{3\sqrt{3}}');

    for (final s in _onScreen(tester)) {
      expect(s, isNot(contains(r'\')), reason: 'LaTeX on screen: $s');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the problem card shows the read, never its source',
      (tester) async {
    await _pump(
      tester,
      ProblemCard(result: _result(_reported), onRescan: () {}, onEdit: () {}),
    );

    expect(find.text('Solve the equation'), findsOneWidget);
    expect(find.text('Medium confidence'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    for (final s in _onScreen(tester)) {
      expect(s, isNot(contains(r'\')), reason: 'LaTeX on screen: $s');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('unrenderable maths falls back to readable maths, not source',
      (tester) async {
    // Malformed enough that no typesetter will take it — the fallback path.
    const broken = r'\frac{1}{3\sqrt{3}';
    await _pump(
      tester,
      const MathText(broken, style: TextStyle(fontSize: 20)),
    );

    expect(find.text(toReadableMath(broken)), findsOneWidget);
    for (final s in _onScreen(tester)) {
      expect(s, isNot(contains(r'\')), reason: 'LaTeX on screen: $s');
    }
  });

  testWidgets('a matrix keeps its rows — a row break is not a line break',
      (tester) async {
    const matrix = r'\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}';
    await _pump(tester, const ProblemStatement(latex: matrix));

    final maths = tester.widgetList<AdaptiveMath>(find.byType(AdaptiveMath));
    expect(maths, hasLength(1));
    expect(maths.single.latex, matrix);
    expect(tester.takeException(), isNull);
  });
}
