import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/fraction_arithmetic.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

ResultData _r(String latex, String answer, {bool verified = true}) => ResultData(
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
      verified: verified,
      steps: const [],
      verifyText: '',
      explanations: const [],
      methods: const [],
      practice: const [],
      tutorIntro: '',
    );

List<String> _captions(FractionArithmetic f) => f.steps.map((s) => s.caption).toList();
List<String> _callouts(FractionArithmetic f) =>
    f.steps.map((s) => s.callout).whereType<String>().toList();

void main() {
  test('1/2 + 1/3 → 5/6: finds the LCD, converts, combines', () {
    final f = FractionArithmetic.tryBuild(_r(r'\frac{1}{2}+\frac{1}{3}', '5/6'))!;
    expect(_captions(f), contains('Find a common denominator'));
    expect(_callouts(f), contains('LCD of 2 and 3 = 6'));
    expect(_callouts(f), contains('3 + 2 = 5'));
    expect(f.steps.last.latex, r'\frac{5}{6}');
  });

  test('1/4 + 1/4 → 1/2: same denominator, no LCD step, then simplify', () {
    final f = FractionArithmetic.tryBuild(_r(r'\frac{1}{4}+\frac{1}{4}', '1/2'))!;
    expect(_captions(f), isNot(contains('Find a common denominator')));
    expect(_captions(f), contains('Simplify the fraction'));
    expect(f.steps.last.latex, r'\frac{1}{2}');
  });

  test('2/3 × 3/4 → 1/2: multiply across then simplify', () {
    final f = FractionArithmetic.tryBuild(_r(r'\frac{2}{3}\times\frac{3}{4}', '1/2'))!;
    expect(_callouts(f), contains('2 × 3 = 6,  3 × 4 = 12'));
    expect(f.steps.last.latex, r'\frac{1}{2}');
  });

  test('1/2 ÷ 3/4 → 2/3: flip and multiply', () {
    final f = FractionArithmetic.tryBuild(_r(r'\frac{1}{2}\div\frac{3}{4}', '2/3'))!;
    expect(_captions(f), contains('Flip the second fraction and multiply'));
    expect(f.steps.last.latex, r'\frac{2}{3}');
  });

  test('GOLDEN RULE: bails when the result ≠ the verified answer', () {
    expect(FractionArithmetic.tryBuild(_r(r'\frac{1}{2}+\frac{1}{3}', '1')), isNull);
  });

  test('bails on plain integer arithmetic (no fraction)', () {
    expect(FractionArithmetic.tryBuild(_r('2+3', '5')), isNull);
  });
}
