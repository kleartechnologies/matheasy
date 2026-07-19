import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/long_division.dart';
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
  test('156 ÷ 4 → 39: quotient, products, differences and captions', () {
    final d = LongDivision.tryBuild(_r(r'156 \div 4', '39'))!;
    expect(d.quotient, 39);
    expect(d.divisor, 4);
    expect(d.cols, 3);

    // Quotient digits land above cols 1 and 2 (the leading "1" gives no digit).
    final quot = d.marks.where((m) => m.kind == DivMarkKind.quotient).toList();
    expect(quot.map((m) => m.digits.single).toList(), [3, 9]);
    expect(quot.map((m) => m.rightCol).toList(), [1, 2]);

    final captions = d.steps.map((s) => s.caption).toList();
    expect(captions, contains('4 goes into 15 — 3 times'));
    expect(captions, contains('Bring down the 6'));
    expect(captions, contains('4 goes into 36 — 9 times'));
    expect(captions.last, 'The answer is 39');

    // Every mark reveals within the walkthrough.
    for (final mk in d.marks) {
      expect(mk.revealAt, lessThan(d.steps.length));
    }
  });

  test('bails on a non-exact division (remainder ≠ 0)', () {
    expect(LongDivision.tryBuild(_r(r'100 \div 7', '14')), isNull);
  });

  test('GOLDEN RULE: bails when the quotient ≠ the verified answer', () {
    expect(LongDivision.tryBuild(_r(r'156 \div 4', '40')), isNull);
  });

  test('does not fire on multiplication or a bare fraction', () {
    expect(LongDivision.tryBuild(_r(r'34 \times 27', '918')), isNull);
    expect(LongDivision.tryBuild(_r(r'\frac{1}{2}', '0.5')), isNull);
  });
}
