import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/power_root.dart';
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

List<String?> _callouts(PowerRoot p) => p.steps.map((s) => s.callout).toList();

void main() {
  test('2^5 → 32: expands to repeated multiplication with a running product', () {
    final p = PowerRoot.tryBuild(_r('2^5', '32'))!;
    expect(p.steps.first.caption, '2 to the power of 5');
    expect(p.steps[1].latex, r'2 \times 2 \times 2 \times 2 \times 2');
    expect(_callouts(p), contains('2 → 4 → 8 → 16 → 32'));
    expect(p.steps.last.latex, '2^{5} = 32');
  });

  test('5^2 → 25: a square shows the single multiplication, not a chain', () {
    final p = PowerRoot.tryBuild(_r('5^2', '25'))!;
    expect(_callouts(p), contains('5 × 5 = 25'));
    expect(_callouts(p), isNot(contains('5 → 25')));
    expect(p.steps.last.latex, '5^{2} = 25');
  });

  test('√144 → 12: asks what times itself is 144', () {
    final p = PowerRoot.tryBuild(_r(r'\sqrt{144}', '12'))!;
    expect(p.steps.first.caption, 'The square root of 144');
    expect(p.steps[1].latex, r'12 \times 12 = 144');
    expect(p.steps.last.latex, r'\sqrt{144} = 12');
  });

  test('cube root ∛27 → 3', () {
    final p = PowerRoot.tryBuild(_r(r'\sqrt[3]{27}', '3'))!;
    expect(p.steps.first.caption, 'The cube root of 27');
    expect(p.steps[1].latex, '3^{3} = 27');
  });

  test('GOLDEN RULE: bails when the value ≠ the verified answer', () {
    expect(PowerRoot.tryBuild(_r('2^5', '30')), isNull);
  });

  test('bails on a non-perfect square root', () {
    expect(PowerRoot.tryBuild(_r(r'\sqrt{150}', '12')), isNull);
  });
}
