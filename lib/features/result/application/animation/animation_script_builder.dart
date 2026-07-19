import '../../domain/animation/animation_copy.dart';
import '../../domain/animation/animation_primitive.dart';
import '../../domain/animation/animation_script.dart';
import '../../domain/animation/morph_op.dart';
import '../../domain/animation/scene_spec.dart';
import '../../domain/result_models.dart';
import '../../domain/visual_models.dart';
import 'equation_diff.dart';
import 'equation_tokenizer.dart';
import 'scene_builders.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — builds an [AnimationScript] from the
/// VERIFIED solve payload ([ResultData]) entirely on device.
///
/// This is the golden-rule spine of the engine: it NEVER computes math. It reads
/// the solver's frozen step LaTeX (`SolutionStep.resultLatex`, each already
/// back-substitution-verified), pairs consecutive states into before→after
/// morphs via the token-diff, maps them onto the learning phases, and attaches a
/// deterministically-built visual object. If there aren't enough steps to
/// animate, it returns an empty script and the caller falls back to the existing
/// Visual tiers — it never invents a walkthrough.
class AnimationScriptBuilder {
  const AnimationScriptBuilder._();

  /// Build the script, or an empty one (→ caller falls back) when the payload
  /// can't be animated.
  static AnimationScript build(
    ResultData result, {
    AnimationCopy copy = AnimationCopy.fallback,
  }) {
    final original = result.equation.latex.trim();
    final solverSteps =
        result.steps.where((s) => s.resultLatex.trim().isNotEmpty).toList();

    // Need at least one transform to have anything to morph.
    if (original.isEmpty || solverSteps.isEmpty) {
      return const AnimationScript(
        categoryLabel: '',
        answerLatex: '',
        intro: '',
        steps: [],
      );
    }

    final steps = <AnimationStep>[];

    // 1) Understand — a calm opening beat that just shows the problem.
    steps.add(AnimationStep(
      title: copy.understandTitle,
      phase: LearningPhase.understand,
      primitive: AnimationPrimitive.highlightTerm,
      beforeLatex: original,
      afterLatex: original,
      morph: StepMorph.empty,
      explanation: _understandDetail(result, copy),
    ));

    // 2) Transform beats — each pairs the previous state with this step's state.
    final n = solverSteps.length;
    for (var j = 0; j < n; j++) {
      final before = j == 0 ? original : solverSteps[j - 1].resultLatex.trim();
      final after = solverSteps[j].resultLatex.trim();
      final morph =
          EquationDiff.diff(EquationTokenizer.tokenize(before), EquationTokenizer.tokenize(after));
      final isLast = j == n - 1;
      steps.add(AnimationStep(
        title: solverSteps[j].title.isEmpty
            ? (isLast ? copy.answerTitle : 'Step ${j + 1}')
            : solverSteps[j].title,
        phase: _phaseFor(j, n, solverSteps[j].pivotal, isLast),
        primitive: _primitiveFor(morph, result.type, isLast),
        beforeLatex: before,
        afterLatex: after,
        morph: morph,
        explanation: solverSteps[j].detail,
        operationLabel: solverSteps[j].operationLabel,
        hint: solverSteps[j].commonMistake,
        isAnswer: isLast,
      ));
    }

    // 3) Verify — an epilogue confirming the answer, when the solver gave a check.
    final answerLine = solverSteps.last.resultLatex.trim();
    if (result.verified && result.verifyText.trim().isNotEmpty) {
      steps.add(AnimationStep(
        title: copy.verifyTitle,
        phase: LearningPhase.verify,
        primitive: AnimationPrimitive.highlightTerm,
        beforeLatex: answerLine,
        afterLatex: answerLine,
        morph: StepMorph.empty,
        explanation: result.verifyText.trim(),
      ));
    }

    return AnimationScript(
      categoryLabel: result.type.label,
      answerLatex:
          result.answerLatex.trim().isEmpty ? answerLine : result.answerLatex.trim(),
      intro: copy.intro,
      steps: steps,
      scene: _sceneFor(result) ?? SceneObject.none,
      keyIdeas: _keyIdeas(result),
      methodName: _methodName(result),
    );
  }

  /// Build a script from an LLM-authored [VisualSolution] (the practice seam,
  /// which has no full solve payload). The before/after LaTeX is answer-anchored
  /// server-side; the morph still only re-positions those existing tokens. No
  /// visual object is attached here — the symbol morph stands alone.
  static AnimationScript fromVisual(
    VisualSolution visual, {
    AnimationCopy copy = AnimationCopy.fallback,
  }) {
    final vSteps = visual.steps
        .where((s) => s.afterLatex.trim().isNotEmpty)
        .toList();
    if (vSteps.isEmpty) {
      return const AnimationScript(
          categoryLabel: '', answerLatex: '', intro: '', steps: []);
    }

    final steps = <AnimationStep>[
      AnimationStep(
        title: copy.understandTitle,
        phase: LearningPhase.understand,
        primitive: AnimationPrimitive.highlightTerm,
        beforeLatex: vSteps.first.beforeLatex,
        afterLatex: vSteps.first.beforeLatex,
        morph: StepMorph.empty,
        explanation: copy.understandDetail,
      ),
    ];

    final n = vSteps.length;
    for (var j = 0; j < n; j++) {
      final s = vSteps[j];
      final morph = EquationDiff.diff(
        EquationTokenizer.tokenize(s.beforeLatex),
        EquationTokenizer.tokenize(s.afterLatex),
      );
      final isLast = j == n - 1;
      steps.add(AnimationStep(
        title: s.title.isEmpty ? (isLast ? copy.answerTitle : 'Step ${j + 1}') : s.title,
        phase: _phaseFor(j, n, false, isLast),
        primitive: _primitiveFor(morph, ResultType.expression, isLast),
        beforeLatex: s.beforeLatex,
        afterLatex: s.afterLatex,
        morph: morph,
        explanation: s.explanation,
        operationLabel: s.operationLabel,
        hint: s.hint?.text,
        isAnswer: isLast,
      ));
    }

    return AnimationScript(
      categoryLabel: visual.category.label,
      answerLatex: visual.answerLatex,
      intro: visual.intro.isEmpty ? copy.intro : visual.intro,
      steps: steps,
      keyIdeas: visual.explanation?.keyIdeas.take(3).toList() ?? const [],
      methodName: visual.method?.name,
    );
  }

  // ---- phase mapping --------------------------------------------------------

  static LearningPhase _phaseFor(int index, int total, bool pivotal, bool isLast) {
    if (isLast) return LearningPhase.answer;
    if (pivotal) return LearningPhase.apply;
    // First half applies the rule; second half tidies up.
    return index < (total - 1) / 2 ? LearningPhase.apply : LearningPhase.simplify;
  }

  // ---- primitive selection --------------------------------------------------

  static AnimationPrimitive _primitiveFor(
    StepMorph morph,
    ResultType type,
    bool isLast,
  ) {
    if (morph.crossedRelation) return AnimationPrimitive.moveTermAcrossEquals;
    if (morph.split) {
      return type == ResultType.quadratic
          ? AnimationPrimitive.factorExpression
          : AnimationPrimitive.splitExpression;
    }
    if (morph.merged) return AnimationPrimitive.mergeTerms;
    if (!morph.confident) return AnimationPrimitive.equationMorph;
    return AnimationPrimitive.equationMorph;
  }

  // ---- scene selection ------------------------------------------------------

  static SceneObject? _sceneFor(ResultData result) {
    switch (result.type) {
      case ResultType.linear:
        return SceneBuilders.balanceScale(
          equationLatex: result.equation.latex,
          answerLatex: result.answerLatex,
        );
      case ResultType.quadratic:
        return SceneBuilders.graph(graph: result.graph, type: result.type);
      case ResultType.fraction:
        return SceneBuilders.fractionBar(
          problemLatex: result.equation.latex,
          answerLatex: result.answerLatex,
        );
      case ResultType.expression:
      case ResultType.trigonometry:
      case ResultType.geometry:
      case ResultType.system:
        // A graph if the solver produced one, else the morph stands alone.
        return SceneBuilders.graph(graph: result.graph, type: result.type);
    }
  }

  // ---- takeaways / method ---------------------------------------------------

  static List<String> _keyIdeas(ResultData result) {
    final teaching = result.teaching;
    final ideas = <String>[];
    if (teaching != null && teaching.keyTakeaway.headline.isNotEmpty) {
      ideas.add(teaching.keyTakeaway.headline);
      final detail = teaching.keyTakeaway.detail;
      if (detail != null && detail.isNotEmpty) ideas.add(detail);
    }
    if (ideas.isEmpty && result.explanations.isNotEmpty) {
      ideas.addAll(result.explanations.first.points.take(2));
    }
    return ideas.take(3).toList();
  }

  static String? _methodName(ResultData result) {
    for (final m in result.methods) {
      if (m.recommended) return m.name;
    }
    return result.methods.isNotEmpty ? result.methods.first.name : null;
  }

  static String _understandDetail(ResultData result, AnimationCopy copy) {
    final asked = result.teaching?.overview.asked;
    if (asked != null && asked.isNotEmpty) return asked;
    return copy.understandDetail;
  }
}
