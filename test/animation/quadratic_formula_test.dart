import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/quadratic_formula.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

ResultData _r(String latex, String answer, {bool verified = true}) => ResultData(
      equation: DetectedEquation(
        latex: latex,
        confidence: 1,
        source: ScanSource.manual,
        kind: EquationKind.quadratic,
      ),
      type: ResultType.quadratic,
      difficulty: Difficulty.medium,
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

List<String?> _callouts(QuadraticFormula q) =>
    q.steps.map((s) => s.callout).toList();

void main() {
  test('x^2 - 5x + 6 = 0 → identifies a,b,c, discriminant, roots 2 and 3', () {
    final q = QuadraticFormula.tryBuild(_r('x^2-5x+6=0', 'x = 2 or x = 3'))!;
    expect(_callouts(q), contains('a=1,\\ b=-5,\\ c=6'));
    expect(_callouts(q), contains('b^2-4ac=1'));
    // Roots 3 and 2 (order: -b+d first).
    expect(q.steps.last.latex, r'x=3 \quad\text{or}\quad x=2');
  });

  test('handles a leading coefficient: 2x^2 - 7x + 3 = 0 → roots 3 and 1/2… '
      '(non-integer root declines)', () {
    // 2x^2-7x+3 has roots 3 and 1/2 — 1/2 is not integer, so it declines.
    expect(QuadraticFormula.tryBuild(_r('2x^2-7x+3=0', 'x = 3 or x = 1/2')),
        isNull);
  });

  test('GOLDEN RULE: bails when a root is absent from the verified answer', () {
    expect(QuadraticFormula.tryBuild(_r('x^2-5x+6=0', 'x = 2 or x = 9')), isNull);
  });

  test('bails on a complex-root quadratic (negative discriminant)', () {
    expect(QuadraticFormula.tryBuild(_r('x^2+x+1=0', 'no real solutions')),
        isNull);
  });

  test('bails on a non-quadratic', () {
    expect(QuadraticFormula.tryBuild(_r('2x+3=7', 'x = 2')), isNull);
  });
}
