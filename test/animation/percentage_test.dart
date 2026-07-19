import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/percentage.dart';
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

List<String?> _callouts(Percentage p) => p.steps.map((s) => s.callout).toList();

void main() {
  test('15% of 80 → 12: rewrites as a fraction of 100 and multiplies', () {
    final model = Percentage.tryBuild(_r(r'15\% \text{ of } 80', '12'))!;
    expect(model.steps.first.caption, "Percent means 'out of 100'");
    expect(_callouts(model), contains('15% → 15/100'));
    expect(_callouts(model), contains('(15 × 80) ÷ 100 = 12'));
    expect(model.steps.last.latex, r'15\% \text{ of } 80 = 12');
  });

  test('accepts the "× " form and a non-integer result (15% of 70 → 10.5)', () {
    expect(Percentage.tryBuild(_r(r'15\%\times80', '12')), isNotNull);
    final p = Percentage.tryBuild(_r(r'15\% \text{ of } 70', '10.5'))!;
    expect(_callouts(p), contains('(15 × 70) ÷ 100 = 10.5'));
  });

  test('GOLDEN RULE: bails when the value ≠ the verified answer', () {
    expect(Percentage.tryBuild(_r(r'15\% \text{ of } 80', '13')), isNull);
  });

  test('bails on a plain expression with no percent', () {
    expect(Percentage.tryBuild(_r(r'15\times80', '1200')), isNull);
  });
}
