import '../../domain/practice_history.dart';
import '../../domain/question_fingerprint.dart';

/// The anti-repetition decision-maker: given a freshly-generated question's
/// fingerprint and what the learner has recently seen, decides whether the
/// question is too repetitive to serve.
///
/// Three signals, strongest first:
///  1. Exact repeat within the current session (same skill + parameters).
///  2. Exact repeat within persisted [PracticeHistory] (across past sessions).
///  3. Same skill + same *answer* within the current session — catches
///     "different numbers, identical answer" questions that feel like copies.
///
/// Pure and stateless — the orchestrator owns the session-scoped sets and the
/// persisted history.
class SimilarityEngine {
  const SimilarityEngine();

  bool isTooSimilar(
    QuestionFingerprint candidate, {
    required PracticeHistory history,
    required Set<String> sessionValues,
    required Set<String> sessionAnswerSignatures,
  }) {
    if (sessionValues.contains(candidate.value)) return true;
    if (history.containsExact(candidate)) return true;
    if (sessionAnswerSignatures.contains(candidate.answerSignature)) {
      return true;
    }
    return false;
  }
}
