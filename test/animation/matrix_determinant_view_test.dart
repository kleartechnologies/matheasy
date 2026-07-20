import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/animation/matrix_determinant.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/engine/matrix_determinant_view.dart';
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
      difficulty: Difficulty.hard,
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
  testWidgets('renders the determinant walkthrough (incl. \\begin{vmatrix}) '
      'without error', (tester) async {
    final model = MatrixDeterminant.tryBuild(
        _r(r'\begin{vmatrix}1&2\\3&4\end{vmatrix}', '-2'))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatrixDeterminantView(model: model),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF ${model.steps.length}'), findsOneWidget);
    expect(find.text('Determinant of a 2×2 matrix'), findsOneWidget);
    // The matrix LaTeX must not throw in flutter_math.
    expect(tester.takeException(), isNull);

    for (var i = 1; i < model.steps.length; i++) {
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
    }
    expect(find.text('The determinant is -2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
