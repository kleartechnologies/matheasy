import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/animation/power_root.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/engine/power_root_view.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

ResultData _r(String latex, String answer) => ResultData(
      equation: DetectedEquation(
        latex: latex,
        confidence: 1,
        source: ScanSource.manual,
        kind: EquationKind.expression,
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
  testWidgets('renders the power walkthrough through to the value',
      (tester) async {
    final model = PowerRoot.tryBuild(_r('2^5', '32'))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(child: PowerRootView(model: model)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF ${model.steps.length}'), findsOneWidget);
    expect(find.text('2 to the power of 5'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (var i = 1; i < model.steps.length; i++) {
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
    }
    expect(find.text('So 2 to the power of 5 is 32'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
