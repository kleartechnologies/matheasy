import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/animation/long_division.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/engine/long_division_view.dart';
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
  testWidgets('renders the long-division worksheet through to the answer',
      (tester) async {
    final model = LongDivision.tryBuild(_r(r'156 \div 4', '39'))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: LongDivisionView(model: model),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF ${model.steps.length}'), findsOneWidget);
    expect(find.text('4 goes into 15 — 3 times'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (var i = 1; i < model.steps.length; i++) {
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
    }
    expect(find.text('The answer is 39'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
