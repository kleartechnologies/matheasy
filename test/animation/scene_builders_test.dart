import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/application/animation/scene_builders.dart';
import 'package:matheasy/features/result/domain/animation/scene_spec.dart';
import 'package:matheasy/features/result/domain/result_models.dart';

void main() {
  group('SceneBuilders.fractionBar (golden rule)', () {
    test('builds a bar for a proper, non-negative fraction answer', () {
      final s = SceneBuilders.fractionBar(
          problemLatex: r'\frac{1}{4} + \frac{1}{2}', answerLatex: r'\frac{3}{4}');
      expect(s, isNotNull);
      expect(s!.kind, SceneObjectKind.fractionBar);
      expect(s.param('numerator'), 3);
      expect(s.param('denominator'), 4);
    });

    test('refuses a NEGATIVE answer rather than paint a positive bar', () {
      // Both LaTeX forms of a negative fraction must degrade to the morph.
      expect(
          SceneBuilders.fractionBar(
              problemLatex: '', answerLatex: r'-\frac{3}{4}'),
          isNull);
      expect(
          SceneBuilders.fractionBar(
              problemLatex: '', answerLatex: r'\frac{-3}{4}'),
          isNull);
    });

    test('refuses an improper fraction answer', () {
      expect(
          SceneBuilders.fractionBar(problemLatex: '', answerLatex: r'\frac{5}{4}'),
          isNull);
    });

    test('never falls back to a PROBLEM operand when the answer is whole', () {
      // 1/2 + 1/2 = 1: the answer has no fraction, so no bar is shown (a "1/2"
      // bar from a problem operand would contradict the verified answer of 1).
      expect(
          SceneBuilders.fractionBar(
              problemLatex: r'\frac{1}{2} + \frac{1}{2}', answerLatex: '1'),
          isNull);
    });
  });

  group('SceneBuilders.balanceScale', () {
    test('builds the two sides from a linear equation', () {
      final s = SceneBuilders.balanceScale(
          equationLatex: '3x + 5 = 20', answerLatex: 'x = 5');
      expect(s, isNotNull);
      expect(s!.kind, SceneObjectKind.balanceScale);
      expect(s.labels['left'], contains('3x'));
      expect(s.labels['right'], contains('20'));
    });

    test('returns null when there is no relation to balance', () {
      expect(
          SceneBuilders.balanceScale(equationLatex: '3x + 5', answerLatex: ''),
          isNull);
    });
  });

  group('SceneBuilders.graph', () {
    test('returns null without enough sampled curve points', () {
      expect(SceneBuilders.graph(graph: null, type: ResultType.quadratic),
          isNull);
    });
  });
}
