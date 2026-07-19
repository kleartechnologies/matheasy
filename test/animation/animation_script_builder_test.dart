import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/application/animation/animation_script_builder.dart';
import 'package:matheasy/features/result/domain/animation/animation_primitive.dart';
import 'package:matheasy/features/result/domain/animation/animation_script.dart';
import 'package:matheasy/features/result/domain/animation/scene_spec.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

DetectedEquation _eq(String latex) => DetectedEquation(
      latex: latex,
      confidence: 1,
      source: ScanSource.camera,
      kind: EquationKind.linear,
    );

ResultData _linear() => ResultData(
      equation: _eq('3x + 5 = 20'),
      type: ResultType.linear,
      difficulty: Difficulty.easy,
      answerLatex: 'x = 5',
      steps: const [
        SolutionStep(
            title: 'Subtract 5', resultLatex: '3x = 20 - 5', detail: 'move it'),
        SolutionStep(
            title: 'Simplify', resultLatex: '3x = 15', detail: 'combine'),
        SolutionStep(
            title: 'Divide by 3',
            resultLatex: 'x = 5',
            detail: 'isolate x',
            pivotal: true),
      ],
      verifyText: '3(5) + 5 = 20',
      explanations: const [],
      methods: const [
        MethodSolution(
          name: 'Balance method',
          subtitle: '',
          description: '',
          advantages: [],
          whenToUse: '',
          steps: [],
          recommended: true,
        ),
      ],
      practice: const [],
      tutorIntro: '',
    );

void main() {
  group('AnimationScriptBuilder', () {
    test('builds a phased, morphing script from verified linear steps', () {
      final s = AnimationScriptBuilder.build(_linear());
      expect(s.isEmpty, isFalse);

      // Opens with an Understand beat and no morph.
      expect(s.steps.first.phase, LearningPhase.understand);
      expect(s.steps.first.morph.isEmpty, isTrue);

      // A term crossing the '=' is detected as MoveTermAcrossEquals.
      expect(
        s.steps.any((x) => x.primitive == AnimationPrimitive.moveTermAcrossEquals),
        isTrue,
      );
      // Combining `20 - 5 → 15` is a merge.
      expect(
        s.steps.any((x) => x.primitive == AnimationPrimitive.mergeTerms),
        isTrue,
      );

      // Exactly one answer beat, in the answer phase.
      final answers = s.steps.where((x) => x.isAnswer).toList();
      expect(answers, hasLength(1));
      expect(answers.first.phase, LearningPhase.answer);
      expect(answers.first.afterLatex, 'x = 5');

      // A verify epilogue carries the solver's check.
      final verify =
          s.steps.where((x) => x.phase == LearningPhase.verify).toList();
      expect(verify, hasLength(1));
      expect(verify.first.explanation, contains('3(5)'));

      // Linear problems get a balance-scale visual object.
      expect(s.scene.kind, SceneObjectKind.balanceScale);
      expect(s.answerLatex, 'x = 5');
      expect(s.methodName, 'Balance method');
    });

    test('golden rule: every after-token traces to a verified step LaTeX', () {
      final result = _linear();
      final verified = {
        result.equation.latex.replaceAll(' ', ''),
        for (final st in result.steps) st.resultLatex.replaceAll(' ', ''),
      };
      final s = AnimationScriptBuilder.build(result);
      for (final step in s.steps) {
        // The after-expression of every beat is one of the verified states —
        // the engine never fabricates an equation the solver didn't produce.
        expect(
          verified.contains(step.afterLatex.replaceAll(' ', '')) ||
              step.afterLatex == step.beforeLatex,
          isTrue,
          reason: 'unexpected afterLatex: ${step.afterLatex}',
        );
      }
    });

    test('returns an empty script when there are no steps to animate', () {
      final barren = ResultData(
        equation: _eq('x = 5'),
        type: ResultType.linear,
        difficulty: Difficulty.easy,
        answerLatex: 'x = 5',
        steps: const [],
        verifyText: '',
        explanations: const [],
        methods: const [],
        practice: const [],
        tutorIntro: '',
      );
      expect(AnimationScriptBuilder.build(barren).isEmpty, isTrue);
    });
  });
}
