import 'package:flutter/foundation.dart';

/// A compact, comparable signature of a generated question — the core of the
/// anti-repetition system.
///
/// Two questions with the same [value] are the *same* question (same skill,
/// same parameters), even if their surface wording differs. [answerKey] adds a
/// softer signal: two different-parameter questions that nonetheless resolve to
/// the same answer for the same skill "feel" repetitive to a learner, so the
/// [SimilarityEngine] can suppress those too.
@immutable
class QuestionFingerprint {
  const QuestionFingerprint({
    required this.skillId,
    required this.signature,
    required this.answerKey,
  });

  /// The [PracticeSkill.id] this question was generated for.
  final String skillId;

  /// A deterministic encoding of the question's structure/parameters, unique
  /// within a skill (e.g. the coefficient tuple `2|5|13`).
  final String signature;

  /// The normalized correct answer (lowercased, whitespace/symbol-stripped).
  final String answerKey;

  /// The exact-identity key — same skill + same parameters.
  String get value => '$skillId#$signature';

  /// A per-skill answer key — same skill + same answer (a weaker "feels the
  /// same" signal than [value]).
  String get answerSignature => '$skillId=$answerKey';

  @override
  bool operator ==(Object other) =>
      other is QuestionFingerprint &&
      other.skillId == skillId &&
      other.signature == signature &&
      other.answerKey == answerKey;

  @override
  int get hashCode => Object.hash(skillId, signature, answerKey);

  @override
  String toString() => 'QuestionFingerprint($value)';
}
