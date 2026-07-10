import 'package:flutter/foundation.dart';

import 'mastery.dart';

/// Per-skill mastery — the fine-grained signal the adaptive engine learns from.
///
/// [TopicProgress] tracks mastery per coarse [PracticeTopic]; this tracks it per
/// [PracticeSkill], so "struggles with fractions" can be as specific as
/// "struggles with adding unlike fractions" and the engine can target that
/// exact weakness. Purely additive to the existing progress model — persisted
/// alongside it and ignored by everything that doesn't opt in.
@immutable
class SkillMastery {
  const SkillMastery({
    required this.skillId,
    this.masteryPoints = 0,
    this.attempts = 0,
    this.correct = 0,
    this.lastSeenEpochDay,
  });

  /// The [PracticeSkill.id] this record is for.
  final String skillId;

  /// 0–100 mastery score for this skill (grows with correct answers, weighted
  /// by difficulty — same scale as [TopicProgress.masteryPoints]).
  final int masteryPoints;

  final int attempts;
  final int correct;

  /// The epoch-day this skill was last practiced (for recency-aware weakness
  /// scoring + spacing).
  final int? lastSeenEpochDay;

  MasteryLevel get level => MasteryLevel.forPoints(masteryPoints);

  double get accuracy => attempts == 0 ? 0 : correct / attempts;

  bool get hasHistory => attempts > 0;

  /// Applies one graded attempt: bumps [attempts]/[correct], and (when correct)
  /// adds [masteryGain] toward the 0–100 score.
  SkillMastery record({
    required bool isCorrect,
    required int masteryGain,
    required int epochDay,
  }) {
    return SkillMastery(
      skillId: skillId,
      masteryPoints: isCorrect
          ? (masteryPoints + masteryGain).clamp(0, 100)
          : masteryPoints,
      attempts: attempts + 1,
      correct: correct + (isCorrect ? 1 : 0),
      lastSeenEpochDay: epochDay,
    );
  }

  SkillMastery copyWith({
    int? masteryPoints,
    int? attempts,
    int? correct,
    int? lastSeenEpochDay,
  }) {
    return SkillMastery(
      skillId: skillId,
      masteryPoints: masteryPoints ?? this.masteryPoints,
      attempts: attempts ?? this.attempts,
      correct: correct ?? this.correct,
      lastSeenEpochDay: lastSeenEpochDay ?? this.lastSeenEpochDay,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SkillMastery &&
      other.skillId == skillId &&
      other.masteryPoints == masteryPoints &&
      other.attempts == attempts &&
      other.correct == correct &&
      other.lastSeenEpochDay == lastSeenEpochDay;

  @override
  int get hashCode =>
      Object.hash(skillId, masteryPoints, attempts, correct, lastSeenEpochDay);
}
