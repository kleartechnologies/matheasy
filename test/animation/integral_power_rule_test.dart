import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/integral_power_rule.dart';
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

List<String> _latex(IntegralPowerRule i) => i.steps.map((s) => s.latex).toList();

void main() {
  test('∫(3x^2 + 4x - 5) dx → x^3 + 2x^2 - 5x + C (integer-coeff answer)', () {
    final i = IntegralPowerRule.tryBuild(
        _r(r'\int(3x^2+4x-5)dx', 'x^3+2x^2-5x+C'))!;
    expect(i.steps.first.callout, r'\int x^n\,dx=\frac{x^{n+1}}{n+1}+C');
    expect(_latex(i), contains(r'x^{3}+2x^{2}-5x+C'));
    expect(i.steps.last.latex,
        r'\int\left(3x^{2}+4x-5\right)\,dx=x^{3}+2x^{2}-5x+C');
  });

  test('∫x^2 dx → x^3/3 + C (fraction answer, \\frac{x^3}{3})', () {
    final i =
        IntegralPowerRule.tryBuild(_r(r'\int x^2 dx', r'\frac{x^3}{3}+C'))!;
    expect(_latex(i), contains(r'\frac{x^{3}}{3}+C'));
  });

  test('accepts the \\frac{1}{3}x^3 answer form too', () {
    expect(
      IntegralPowerRule.tryBuild(_r(r'\int x^2 dx', r'\frac{1}{3}x^3+C')),
      isNotNull,
    );
  });

  test('variable r: ∫r^2 dr → r^3/3 + C (does not corrupt \\frac in the answer)',
      () {
    final i =
        IntegralPowerRule.tryBuild(_r(r'\int r^2 dr', r'\frac{r^3}{3}+C'))!;
    expect(_latex(i), contains(r'\frac{r^{3}}{3}+C'));
    expect(i.steps.first.latex, contains(r'r^{2}'));
  });

  test('GOLDEN RULE: bails when the antiderivative ≠ the verified answer', () {
    expect(
      IntegralPowerRule.tryBuild(_r(r'\int(3x^2+4x-5)dx', 'x^3+2x^2+C')),
      isNull,
    );
  });

  test('bails without an \\int operator', () {
    expect(IntegralPowerRule.tryBuild(_r('3x^2+4x-5', 'irrelevant')), isNull);
  });
}
