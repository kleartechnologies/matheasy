import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/column_arithmetic.dart';
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

List<String> _callouts(ColumnArithmetic c) =>
    c.steps.map((s) => s.callout).whereType<String>().toList();

void main() {
  group('multiplication (integer × single digit)', () {
    test('72 × 6 → 432', () {
      final c = ColumnArithmetic.tryBuild(_r(r'72 \times 6', '432'))!;
      expect(c.op, ColumnOp.multiply);
      expect(c.operatorSymbol, '×');
      expect(c.topDigits, [7, 2]);
      expect(c.bottomDigits, [6]);
      expect(_callouts(c), containsAllInOrder(['6 × 2 = 12', '6 × 7 = 42', '42 + 1 = 43']));
      expect(c.steps.last.resultDigits, [2, 3, 4]);
    });

    test('bails when the product ≠ the verified answer', () {
      expect(ColumnArithmetic.tryBuild(_r(r'72 \times 6', '999')), isNull);
    });

    test('bails when both factors are multi-digit', () {
      expect(ColumnArithmetic.tryBuild(_r(r'12 \times 34', '408')), isNull);
    });
  });

  group('addition', () {
    test('348 + 275 → 623 with carries', () {
      final c = ColumnArithmetic.tryBuild(_r('348 + 275', '623'))!;
      expect(c.op, ColumnOp.add);
      expect(c.operatorSymbol, '+');
      // ones 8+5=13, tens 4+7+1=12, hundreds 3+2+1=6.
      expect(_callouts(c),
          containsAllInOrder(['8 + 5 = 13', '4 + 7 + 1 = 12', '3 + 2 + 1 = 6']));
      expect(c.steps.last.resultDigits, [3, 2, 6]); // 623
    });

    test('a carry into a new leading column widens the answer (95 + 12 → 107)', () {
      final c = ColumnArithmetic.tryBuild(_r('95 + 12', '107'))!;
      expect(c.resultWidth, 3);
      expect(c.steps.last.resultDigits, [7, 0, 1]); // 107
    });

    test('bails when the sum ≠ the verified answer', () {
      expect(ColumnArithmetic.tryBuild(_r('348 + 275', '600')), isNull);
    });
  });

  group('subtraction (a ≥ b)', () {
    test('52 − 27 → 25 with a borrow', () {
      final c = ColumnArithmetic.tryBuild(_r('52 - 27', '25'))!;
      expect(c.op, ColumnOp.subtract);
      expect(c.operatorSymbol, '−');
      // ones: borrow → 12 − 7 = 5; tens: 4 − 2 = 2.
      expect(_callouts(c), containsAllInOrder(['12 − 7 = 5', '4 − 2 = 2']));
      expect(c.steps.last.resultDigits, [5, 2]); // 25
      // The borrowed-from tens column is struck + shows its reduced value.
      final borrowStep = c.steps.firstWhere((s) => s.struckTop.isNotEmpty);
      expect(borrowStep.struckTop, contains(1));
      expect(borrowStep.borrowDigits[1], 4);
    });

    test('no-borrow subtraction (58 − 23 → 35)', () {
      final c = ColumnArithmetic.tryBuild(_r('58 - 23', '35'))!;
      expect(c.steps.every((s) => s.struckTop.isEmpty), isTrue);
      expect(c.steps.last.resultDigits, [5, 3]); // 35
    });

    test('bails on a negative result (a < b)', () {
      expect(ColumnArithmetic.tryBuild(_r('27 - 52', '-25')), isNull);
    });

    test('declines a chained borrow across a zero (100 − 1)', () {
      expect(ColumnArithmetic.tryBuild(_r('100 - 1', '99')), isNull);
    });
  });

  test('bails on a non two-operand expression', () {
    expect(ColumnArithmetic.tryBuild(_r('2 + 3 + 4', '9')), isNull);
    expect(ColumnArithmetic.tryBuild(_r(r'\sqrt{9}', '3')), isNull);
  });
}
