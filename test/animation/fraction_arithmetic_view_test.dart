import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/animation/fraction_arithmetic.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/engine/fraction_arithmetic_view.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

ResultData _r(String latex, String answer) => ResultData(
      equation: DetectedEquation(
        latex: latex,
        confidence: 1,
        source: ScanSource.manual,
        kind: EquationKind.fraction,
      ),
      type: ResultType.fraction,
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
  testWidgets('renders the fraction walkthrough and steps to the answer',
      (tester) async {
    final model =
        FractionArithmetic.tryBuild(_r(r'\frac{1}{2}+\frac{1}{3}', '5/6'))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: FractionArithmeticView(model: model),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF ${model.steps.length}'), findsOneWidget);
    expect(find.text('Start with the two fractions'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Step 2 introduces the common denominator.
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Find a common denominator'), findsOneWidget);

    for (var i = 2; i < model.steps.length; i++) {
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
    }
    expect(find.text('The result is 5/6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
