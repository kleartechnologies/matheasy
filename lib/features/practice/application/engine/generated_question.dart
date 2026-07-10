import '../../domain/practice_question.dart';
import '../../domain/question_fingerprint.dart';

/// A freshly-generated question plus its [QuestionFingerprint] — the unit the
/// generators emit and the orchestrator dedupes on.
class GeneratedQuestion {
  const GeneratedQuestion({required this.question, required this.fingerprint});

  final PracticeQuestion question;
  final QuestionFingerprint fingerprint;

  /// Builds a [GeneratedQuestion], deriving the fingerprint from the question's
  /// [skillId], a caller-supplied [signature] (its parameter tuple) and its
  /// canonical answer. [skillId] must be set on [question].
  factory GeneratedQuestion.of(
    PracticeQuestion question, {
    required String signature,
  }) {
    return GeneratedQuestion(
      question: question,
      fingerprint: QuestionFingerprint(
        skillId: question.skillId ?? question.topic.name,
        signature: signature,
        answerKey: normalizeAnswer(question.correctAnswerText),
      ),
    );
  }

  /// Builds a [GeneratedQuestion] for a free-form question (e.g. AI-generated)
  /// whose parameters aren't structured — the signature is derived from the
  /// normalized prompt + answer, so distinct wordings still dedupe.
  factory GeneratedQuestion.content(PracticeQuestion question) {
    final source = question.promptLatex ?? question.prompt;
    final signature =
        source.toLowerCase().replaceAll(RegExp(r'\s+'), '').replaceAll(
              RegExp(r'[^a-z0-9=+\-*/^().]'),
              '',
            );
    return GeneratedQuestion.of(question, signature: signature);
  }

  /// Normalizes an answer for fingerprint comparison — lowercased, whitespace
  /// and grouping/currency symbols stripped, a leading `x =` dropped. Mirrors
  /// [PracticeQuestion]'s own answer normalization so "x = 4" and "4" collapse.
  static String normalizeAnswer(String raw) {
    var value = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s$,£€]'), '');
    final eq = value.indexOf('=');
    if (eq >= 0) value = value.substring(eq + 1);
    return value;
  }
}
