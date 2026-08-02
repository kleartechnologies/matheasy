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
      // How the problem was READ, so Numi can question the transcription rather
      // than defend an answer to a problem the student never wrote.
      ocrLatex: _ocrString(result, 'latex'),
      ocrConfidence: _ocrConfidence(result),
      ocrUncertain: _ocrUncertain(result),
      // The practice the app has already generated and checked for this problem.
      practice: [
        for (final q in result.practice.take(maxPractice))
          if (q.questionLatex.isNotEmpty)
            '${q.questionLatex} (${q.difficulty.name})',
      ],
      // The page itself. Sent on the opening turn only — the server drops it on
      // every turn after that (see `openingScanImage` in `tutor.ts`).
      scanImageBytes: result.equation.imageBytes,
      // …and the map of that page, which rides along on every turn instead. The
      // photo is what Numi reads once; the anchors are what Numi points at for
      // the rest of the conversation.
      anchors: result.equation.anchors,
    );
  }

  /// How many practice questions to name. Enough for "give me another one" to
  /// have somewhere to point; not so many that the prompt turns into a worksheet.
  static const int maxPractice = 5;

  /// How many doubtful marks to carry. The server caps again at 6.
  static const int maxUncertain = 6;

  static String? _ocrString(ResultData result, String key) {
    final value = result.equation.ocr?[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _ocrConfidence(ResultData result) {
    final value = result.equation.ocr?['confidence'];
    return value is num ? value.toDouble().clamp(0.0, 1.0) : null;
  }

  static List<String> _ocrUncertain(ResultData result) {
    final value = result.equation.ocr?['uncertain'];
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ].take(maxUncertain).toList();
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
