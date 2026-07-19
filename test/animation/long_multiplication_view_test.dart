import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/animation/long_multiplication.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/engine/long_multiplication_view.dart';
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
  testWidgets('renders the long-multiplication walkthrough to the product',
      (tester) async {
    final model = LongMultiplication.tryBuild(_r(r'34 \times 27', '918'))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: LongMultiplicationView(model: model),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF ${model.steps.length}'), findsOneWidget);
    expect(find.text('34 × 7 = 238'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (var i = 1; i < model.steps.length; i++) {
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
    }
    expect(find.text('The result is 918'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
