import '../../scan/domain/detected_equation.dart';
import '../domain/animation/animation_script.dart';
import '../domain/geometry_models.dart';
import '../domain/result_models.dart';
import '../domain/visual_models.dart';

/// Builds everything the Visual Learning Engine sends off-device.
///
/// The *system* prompt (the schema contract) lives server-side in
/// `functions/src/proxy/visual.ts`, matching the solver/tutor convention that
/// prompts never ship in the app bundle. This builder owns the client half:
/// the request payload for the `generateVisualSolution` callable, and the
/// compact step-context strings handed to Matheasy so the tutor can answer
/// "why divide by 2?" about the exact step on screen.
class VisualPromptBuilder {
  const VisualPromptBuilder._();

  /// The [VisualRequest] for a solved problem — carries the solver's answer
  /// and type so the visual walkthrough agrees with the Solution tab.
  static VisualRequest request(
    DetectedEquation equation, {
    ResultData? result,
  }) {
    return VisualRequest(
      latex: equation.latex,
      answerLatex: result?.answerLatex,
      typeHint: result?.type.name,
    );
  }

  /// The callable payload for `generateVisualSolution`.
  static Map<String, dynamic> requestPayload(VisualRequest request) => {
        'latex': request.latex,
        if (request.answerLatex != null && request.answerLatex!.isNotEmpty)
          'answerLatex': request.answerLatex,
        if (request.typeHint != null && request.typeHint!.isNotEmpty)
          'problemType': request.typeHint,
      };

  /// A compact, plain-text description of the step the student is looking at,
  /// passed to Matheasy as `TutorLaunchContext.visualStepSummary`. Kept to one
  /// string so the whole tutor pipeline (session storage, callable payload,
  /// server system message) carries it unchanged.
  static String tutorStepContext(VisualSolution solution, int stepIndex) {
    final total = solution.steps.length;
    if (stepIndex < 0 || stepIndex >= total) {
      return 'The visual solution of the problem, answered ${solution.answerLatex}.';
    }
    final step = solution.steps[stepIndex];
    final operation = step.operationLabel;
    final buffer = StringBuffer()
      ..write('Step ${stepIndex + 1} of $total — "${step.title}"')
      ..write(operation == null ? '' : ' (operation: $operation)')
      ..write(': ${step.beforeLatex} becomes ${step.afterLatex}.')
      ..write(' Why: ${step.explanation}');
    return buffer.toString();
  }

  /// The tutor context for a beat of the **Animated Learning Engine** player.
  /// The player emits an index into [AnimationScript.steps] (an Understand beat +
  /// the verified transforms + a Verify beat) — a different list from
  /// [VisualSolution.steps], so it needs its own summariser (reusing
  /// [tutorStepContext] would hand the tutor a mismatched, off-by-one step).
  static String tutorAnimationStepContext(AnimationScript script, int beatIndex) {
    final total = script.steps.length;
    if (beatIndex < 0 || beatIndex >= total) {
      return 'The animated solution of the problem, answered ${script.answerLatex}.';
    }
    final step = script.steps[beatIndex];
    final op = step.operationLabel;
    final buffer = StringBuffer()
      ..write('Beat ${beatIndex + 1} of $total — "${step.title}"')
      ..write(op == null || op.isEmpty ? '' : ' (operation: $op)')
      ..write(step.beforeLatex == step.afterLatex
          ? ': ${step.afterLatex}.'
          : ': ${step.beforeLatex} becomes ${step.afterLatex}.')
      ..write(step.explanation.isEmpty ? '' : ' Why: ${step.explanation}');
    return buffer.toString();
  }

  /// The tutor context for a step of the **geometry** player. The player emits
  /// an index into [GeometryScene.steps] (the four canonical beats), which is a
  /// different list from [VisualSolution.steps] — so geometry needs its own
  /// summariser rather than reusing [tutorStepContext] (which would read the
  /// wrong list and hand the tutor mismatched or empty context).
  static String tutorGeometryStepContext(GeometryScene scene, int stepIndex) {
    final total = scene.steps.length;
    if (stepIndex < 0 || stepIndex >= total) {
      return 'The geometry problem, solved: ${scene.answerLatex}. '
          'Rule: ${scene.ruleName}.';
    }
    final step = scene.steps[stepIndex];
    final buffer = StringBuffer()
      ..write('Step ${stepIndex + 1} of $total — "${step.title}"')
      ..write(': ${step.detail}')
      ..write(step.equationLatex == null ? '' : ' (${step.equationLatex})')
      ..write(' Rule: ${scene.ruleName}. Answer: ${scene.answerLatex}.');
    return buffer.toString();
  }
}
