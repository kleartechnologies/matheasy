import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/column_multiplication.dart';
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
  group('ColumnMultiplication.tryBuild', () {
    test('72 × 6 builds the standard short-multiplication walkthrough', () {
      final cm = ColumnMultiplication.tryBuild(_r(r'72 \times 6', '432'));
      expect(cm, isNotNull);
      expect(cm!.top, 72);
      expect(cm.multiplier, 6);
      expect(cm.product, 432);
      expect(cm.topDigits, [7, 2]);
      expect(cm.resultWidth, 3);

      final callouts = cm.steps.map((s) => s.callout).whereType<String>().toList();
      expect(callouts, containsAllInOrder(['6 × 2 = 12', '6 × 7 = 42', '42 + 1 = 43']));

      final last = cm.steps.last;
      expect(last.caption, 'The result is 432');
      // Answer digits by column: ones=2, tens=3, hundreds=4 → 432.
      expect(last.resultDigits, [2, 3, 4]);
    });

    test('accepts the unicode × and puts the single digit on the bottom', () {
      final cm = ColumnMultiplication.tryBuild(_r('6 × 72', '432'));
      expect(cm, isNotNull);
      expect(cm!.top, 72); // the multi-digit factor moves to the top
      expect(cm.multiplier, 6);
      expect(cm.product, 432);
    });

    test('GOLDEN RULE: bails when the product ≠ the verified answer', () {
      expect(ColumnMultiplication.tryBuild(_r(r'72 \times 6', '999')), isNull);
    });

    test('bails on an unverified result', () {
      expect(
        ColumnMultiplication.tryBuild(_r(r'72 \times 6', '432', verified: false)),
        isNull,
      );
    });

    test('bails when both factors are multi-digit (long multiplication)', () {
      expect(ColumnMultiplication.tryBuild(_r(r'12 \times 34', '408')), isNull);
    });

    test('bails on a non-multiplication problem', () {
      expect(ColumnMultiplication.tryBuild(_r('2 + 3', '5')), isNull);
    });

    test('a carry that spills into a new leading column is written', () {
      // 25 × 8 = 200: 8×5=40 (write 0, carry 4), 8×2=16, +4=20 (write 0, carry 2).
      final cm = ColumnMultiplication.tryBuild(_r(r'25 \times 8', '200'));
      expect(cm, isNotNull);
      expect(cm!.steps.last.resultDigits, [0, 0, 2]); // ones,tens,hundreds → 200
    });
  });
}
