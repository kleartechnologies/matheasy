import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/matrix_determinant.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

ResultData _r(String latex, String answer, {bool verified = true}) => ResultData(
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
      verified: verified,
      steps: const [],
      verifyText: '',
      explanations: const [],
      methods: const [],
      practice: const [],
      tutorIntro: '',
    );

List<String> _latex(MatrixDeterminant m) => m.steps.map((s) => s.latex).toList();

void main() {
  test('|1 2; 3 4| → -2: main diagonal minus anti-diagonal', () {
    final m = MatrixDeterminant.tryBuild(
        _r(r'\begin{vmatrix}1&2\\3&4\end{vmatrix}', '-2'))!;
    expect(_latex(m), contains('(1)(4)-(2)(3)'));
    // 1×4=4, 2×3=6 → 4 - 6.
    expect(_latex(m), contains('4-6'));
    expect(m.steps.last.latex, '-2');
  });

  test('handles \\det with a pmatrix and a negative product', () {
    // det[[3,1],[-2,4]] = 12 - (-2) = 14 → "12+2".
    final m = MatrixDeterminant.tryBuild(
        _r(r'\det\begin{pmatrix}3&1\\-2&4\end{pmatrix}', '14'))!;
    expect(_latex(m), contains('12+2'));
    expect(m.steps.last.latex, '14');
  });

  test('GOLDEN RULE: bails when the determinant ≠ the verified answer', () {
    expect(
      MatrixDeterminant.tryBuild(
          _r(r'\begin{vmatrix}1&2\\3&4\end{vmatrix}', '5')),
      isNull,
    );
  });

  test('bails on a non-matrix expression', () {
    expect(MatrixDeterminant.tryBuild(_r('2+3', '5')), isNull);
  });
}
