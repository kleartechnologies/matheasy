import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/long_multiplication.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

ResultData _r(String latex, String answer, {bool verified = true}) => ResultData(
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
      verified: verified,
      steps: const [],
      verifyText: '',
      explanations: const [],
      methods: const [],
      practice: const [],
      tutorIntro: '',
    );

void main() {
  test('34 × 27 → 918: partial products 238 and 68(shift 1)', () {
    final lm = LongMultiplication.tryBuild(_r(r'34 \times 27', '918'))!;
    expect(lm.product, 918);
    expect(lm.partials, hasLength(2));
    expect(lm.partials[0].value, 238); // 34 × 7
    expect(lm.partials[0].shift, 0);
    expect(lm.partials[1].value, 68); // 34 × 2
    expect(lm.partials[1].shift, 1);
    final callouts = lm.steps.map((s) => s.callout).whereType<String>().toList();
    expect(callouts, contains('34 × 7 = 238'));
    expect(callouts, contains('34 × 2 = 68'));
    expect(callouts, contains('238 + 680 = 918'));
  });

  test('bails on a single-digit multiplier (that is column multiplication)', () {
    expect(LongMultiplication.tryBuild(_r(r'72 \times 6', '432')), isNull);
  });

  test('GOLDEN RULE: bails when the product ≠ the verified answer', () {
    expect(LongMultiplication.tryBuild(_r(r'34 \times 27', '900')), isNull);
  });
}
