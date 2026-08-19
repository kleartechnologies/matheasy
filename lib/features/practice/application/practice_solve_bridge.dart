import '../../scan/domain/detected_equation.dart';
import '../../scan/domain/scan_source.dart';
import '../domain/practice_question.dart';
import '../domain/practice_topic.dart';

/// Bridges a practice question into the verified solve pipeline.
///
/// This is how V5 keeps "one engine, one teaching style": hint level 3 (the
/// first step), Show Solution and Review My Solution all reuse
/// `resultControllerProvider(DetectedEquation)` — the same deterministic
/// solve + substitution verification + teaching layer as the scanner — by
/// expressing the question as a [DetectedEquation]. Nothing here computes
/// math; it only reshapes the already-generated question.
///
/// Solving is LAZY: callers watch the provider only once the student asks
/// for deep help, so no quota-relevant call happens for students who never
/// need it. Caching is inherited from the provider family (its equality
/// ignores transient fields) and the server's solve cache.
abstract final class PracticeSolveBridge {
  /// The [DetectedEquation] for [question], or `null` when the question can't
  /// ride the solve pipeline — no LaTeX form, a geometry figure (the figure's
  /// facts aren't in the LaTeX), or a choice-style question. Callers fall
  /// back to the question's own deterministic explanation.
  static DetectedEquation? equationFor(PracticeQuestion question) {
    final latex = question.promptLatex;
    if (latex == null || latex.trim().isEmpty) return null;
    if (question.figure != null) return null;
    if (question.type != PracticeQuestionType.equation &&
        question.type != PracticeQuestionType.input) {
      return null;
    }
    return DetectedEquation(
      latex: latex,
      confidence: 1.0, // authored, not recognized — there is nothing to doubt
      source: ScanSource.practice,
      kind: kindFor(question.topic),
    );
  }

  /// Best-effort [EquationKind] for a practice topic (a display/classification
  /// hint only — the solver classifies for itself).
  static EquationKind kindFor(PracticeTopic topic) => switch (topic) {
        PracticeTopic.algebra => EquationKind.linear,
        PracticeTopic.fractions => EquationKind.fraction,
        PracticeTopic.geometry => EquationKind.geometry,
        PracticeTopic.trigonometry => EquationKind.trigonometry,
        PracticeTopic.calculus ||
        PracticeTopic.statistics ||
        PracticeTopic.wordProblems =>
          EquationKind.expression,
      };
}
