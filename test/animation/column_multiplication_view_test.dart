import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/animation/column_multiplication.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/engine/column_multiplication_view.dart';
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

void main() {
  testWidgets('renders the grid + first step and advances without crashing',
      (tester) async {
    final model = ColumnMultiplication.tryBuild(_r(r'72 \times 6', '432'))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ColumnMultiplicationView(model: model),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The grid shows the operands and operator.
    expect(find.text('×'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // Step 1: multiply, with the sub-calculation callout.
    expect(find.text('STEP 1 OF ${model.steps.length}'), findsOneWidget);
    expect(find.text('Multiply the digits'), findsOneWidget);
    expect(find.text('6 × 2 = 12'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Advancing works.
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('STEP 2 OF ${model.steps.length}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('steps all the way to the final answer', (tester) async {
    final model = ColumnMultiplication.tryBuild(_r(r'72 \times 6', '432'))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ColumnMultiplicationView(model: model),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 1; i < model.steps.length; i++) {
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
    }
    expect(find.text('The result is 432'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
