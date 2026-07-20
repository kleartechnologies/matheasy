import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/derivative_power_rule.dart';
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

List<String> _latex(DerivativePowerRule d) => d.steps.map((s) => s.latex).toList();

void main() {
  test('d/dx(x^3 + 2x^2 - 5x + 1) → 3x^2 + 4x - 5', () {
    final d = DerivativePowerRule.tryBuild(
        _r(r'\frac{d}{dx}(x^3+2x^2-5x+1)', '3x^2+4x-5'))!;
    expect(_latex(d), contains(r'3x^{2}+4x-5'));
    // The expanded "bring the power down" line.
    expect(_latex(d), contains(r'1\cdot3\,x^{2}+2\cdot2\,x-5\cdot1\,'));
    expect(d.steps.last.caption, 'The derivative');
  });

  test('renders in the STUDENT variable: d/dt(t^2) → 2t, never x', () {
    final d = DerivativePowerRule.tryBuild(_r(r'\frac{d}{dt}(t^2)', '2t'))!;
    expect(_latex(d).first, r'\frac{d}{dt}\left(t^{2}\right)');
    expect(_latex(d), contains('2t'));
    // No step is silently rewritten into x.
    expect(_latex(d).any((s) => s.contains('x')), isFalse);
    expect(d.steps.last.latex, r'\frac{d}{dt}\left(t^{2}\right)=2t');
  });

  test('accepts \\left(\\right) wrappers and x^{n} braces', () {
    expect(
      DerivativePowerRule.tryBuild(
          _r(r'\frac{d}{dx}\left(x^{2}\right)', '2x')),
      isNotNull,
    );
  });

  test('GOLDEN RULE: bails when the derivative ≠ the verified answer', () {
    expect(
      DerivativePowerRule.tryBuild(_r(r'\frac{d}{dx}(x^3+2x^2-5x+1)', '3x^2+4x')),
      isNull,
    );
  });

  test('bails without the d/dx operator', () {
    expect(DerivativePowerRule.tryBuild(_r('x^3+2x^2', 'irrelevant')), isNull);
  });
}
