import '../../result/domain/result_models.dart';
import '../../scan/domain/scan_source.dart';
import 'tutor_models.dart';

/// Assembles the full solve context Numi opens with (spec Part 1).
///
/// Everything here is already-verified state the app computed itself — the
/// problem, the checked answer, the checked steps, the traps for this problem
/// type. Nothing is solved or inferred here, so handing Numi more context can
/// never weaken the golden rule; it only stops Numi from having to ask "which
/// equation do you mean?".
///
/// Pure and widget-free so it can be unit-tested and reused from every launch
/// point (result, visual step, practice).
class TutorContextBuilder {
  const TutorContextBuilder._();

  /// How many steps to carry. The server caps again at 14; this keeps the
  /// request small for problems with long working.
  static const int maxSteps = 14;

  /// Build the context for a solved problem.
  ///
  /// [source] describes where the problem came from ("scan", "typed",
  /// "practice") — Numi uses it to pitch its opening line.
  static TutorProblemContext fromResult(ResultData result, {String? source}) {
    return TutorProblemContext(
      questionLatex: result.questionLatex,
      problemType: result.type.label,
      topic: result.type.label,
      difficulty: result.difficulty.label,
      // An unverified result has no answer to stand behind — `answerLatex` is
      // empty in that state, so send nothing rather than an empty assertion.
      finalAnswer: result.verified && result.answerLatex.isNotEmpty
          ? result.answerLatex
          : null,
      verified: result.verified,
      verifyText: result.verified && result.verifyText.isNotEmpty
          ? result.verifyText
          : null,
      steps: _steps(result),
      commonMistakes: _commonMistakes(result),
      source: source ?? _source(result),
    );
  }

  static List<TutorContextStep> _steps(ResultData result) {
    final steps = result.steps.length > maxSteps
        ? result.steps.sublist(0, maxSteps)
        : result.steps;
    return [
      for (final step in steps)
        TutorContextStep(
          title: step.title,
          resultLatex: step.resultLatex,
          // Prefer the deeper v2 "what changed" when the teaching layer filled
          // it in; fall back to the always-present detail.
          detail: step.explanation ?? step.detail,
          rule: step.rule,
        ),
    ];
  }

  /// The traps for this problem — from the teaching layer when present, else the
  /// per-step `commonMistake` hints the solver attached.
  static List<String> _commonMistakes(ResultData result) {
    final teaching = result.teaching;
    if (teaching != null && teaching.commonMistakes.isNotEmpty) {
      return [
        for (final m in teaching.commonMistakes.take(5))
          m.fix.isEmpty ? m.mistake : '${m.mistake} — instead: ${m.fix}',
      ];
    }
    final fromSteps = <String>[
      for (final step in result.steps)
        if (step.commonMistake != null && step.commonMistake!.isNotEmpty)
          step.commonMistake!,
    ];
    return fromSteps.length > 5 ? fromSteps.sublist(0, 5) : fromSteps;
  }

  static String _source(ResultData result) =>
      result.equation.source == ScanSource.manual ? 'typed' : 'scan';
}
