import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/animation/column_arithmetic.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/engine/column_arithmetic_view.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

ResultData _r(String latex, String answer) => ResultData(
      equation: DetectedEquation(
        latex: latex,
        confidence: 1,
        source: ScanSource.manual,
        kind: EquationKind.linear,
      ),
      type: ResultType.expression,
      difficulty: Difficulty.easy,
      answerLatex: answer,
      answerPlain: answer,
      steps: const [],
      verifyText: '',
      explanations: const [],
      methods: const [],
      practice: const [],
      tutorIntro: '',
    );

Future<void> _pump(WidgetTester tester, ColumnArithmetic model) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(child: ColumnArithmeticView(model: model)),
        ),
      ),
    );

Future<void> _stepToEnd(WidgetTester tester, ColumnArithmetic model) async {
  for (var i = 1; i < model.steps.length; i++) {
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('multiplication renders and steps to the answer', (tester) async {
    final model = ColumnArithmetic.tryBuild(_r(r'72 \times 6', '432'))!;
    await _pump(tester, model);
    await tester.pumpAndSettle();
    expect(find.text('×'), findsOneWidget);
    expect(find.text('6 × 2 = 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _stepToEnd(tester, model);
    expect(find.text('The result is 432'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('addition renders the + operator and steps to the answer',
      (tester) async {
    final model = ColumnArithmetic.tryBuild(_r('348 + 275', '623'))!;
    await _pump(tester, model);
    await tester.pumpAndSettle();
    expect(find.text('+'), findsOneWidget);
    expect(find.text('8 + 5 = 13'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _stepToEnd(tester, model);
    expect(find.text('The result is 623'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subtraction renders the − operator and steps to the answer',
      (tester) async {
    final model = ColumnArithmetic.tryBuild(_r('52 - 27', '25'))!;
    await _pump(tester, model);
    await tester.pumpAndSettle();
    expect(find.text('−'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _stepToEnd(tester, model);
    expect(find.text('The result is 25'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
