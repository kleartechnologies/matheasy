import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/decimal_arithmetic.dart';
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

List<String?> _callouts(DecimalArithmetic d) =>
    d.steps.map((s) => s.callout).toList();

void main() {
  test('3.2 + 1.45 → 4.65: aligns and pads the decimals', () {
    final d = DecimalArithmetic.tryBuild(_r('3.2+1.45', '4.65'))!;
    expect(d.steps.first.caption, 'Line up the decimal points');
    // Pads 3.2 → 3.20 so both have two decimals.
    expect(d.steps[1].latex, '3.20 + 1.45');
    expect(_callouts(d), contains('3.20 + 1.45 = 4.65'));
    expect(d.steps.last.latex, '3.2 + 1.45 = 4.65');
  });

  test('0.5 × 4 → 2: multiply as whole numbers, then place the point', () {
    final d = DecimalArithmetic.tryBuild(_r(r'0.5\times4', '2'))!;
    expect(_callouts(d), contains('Multiply 5 × 4'));
    expect(d.steps[1].latex, r'5 \times 4 = 20');
    expect(_callouts(d), contains('1 + 0 = 1 decimal place'));
    expect(d.steps.last.latex, r'0.5 \times 4 = 2');
  });

  test('7.5 - 2.3 → 5.2', () {
    final d = DecimalArithmetic.tryBuild(_r('7.5-2.3', '5.2'))!;
    expect(d.steps.last.latex, '7.5 - 2.3 = 5.2');
  });

  test('GOLDEN RULE: bails when the value ≠ the verified answer', () {
    expect(DecimalArithmetic.tryBuild(_r('3.2+1.45', '4.7')), isNull);
  });

  test('bails on plain integer arithmetic (no decimal point)', () {
    expect(DecimalArithmetic.tryBuild(_r('3+4', '7')), isNull);
  });
}
