import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/animation/logarithm.dart';
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
      difficulty: Difficulty.medium,
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

List<String?> _callouts(Logarithm l) => l.steps.map((s) => s.callout).toList();

void main() {
  test('log_2(8) → 3: what power of 2 gives 8', () {
    final l = Logarithm.tryBuild(_r(r'\log_2(8)', '3'))!;
    expect(_callouts(l), contains('Which power of 2 gives 8?'));
    expect(l.steps[1].latex, '2^{3}=8');
    expect(l.steps.last.latex, r'\log_{2}(8)=3');
  });

  test('base-10 log(1000) → 3', () {
    final l = Logarithm.tryBuild(_r(r'\log(1000)', '3'))!;
    expect(l.steps.first.caption, 'A logarithm (base 10) asks: what power?');
    expect(l.steps[1].latex, '10^{3}=1000');
  });

  test('log_2(1) → 0', () {
    final l = Logarithm.tryBuild(_r(r'\log_{2}(1)', '0'))!;
    expect(l.steps[1].latex, '2^{0}=1');
  });

  test('GOLDEN RULE: bails when base^answer ≠ argument', () {
    // log_2(10) is not an integer; a wrong "3" must not build (2^3=8≠10).
    expect(Logarithm.tryBuild(_r(r'\log_2(10)', '3')), isNull);
  });

  test('bails on a non-log expression', () {
    expect(Logarithm.tryBuild(_r('2+3', '5')), isNull);
  });
}
