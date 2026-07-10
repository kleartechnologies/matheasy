import 'package:flutter/foundation.dart';

import 'practice_difficulty.dart';
import 'practice_skill.dart';
import 'practice_topic.dart';

/// Why the adaptive engine is recommending a particular practice next.
enum AdaptiveReason {
  /// Reinforcing a skill the learner just got wrong / just learned.
  reinforcement('Reinforcing what you just learned'),

  /// Targeting a measured weakness (low accuracy / low mastery).
  weakness('Targeting your weak spots'),

  /// Pushing toward mastery on a skill that's close.
  mastery('Pushing you toward mastery'),

  /// A fresh start — not enough history yet, so build fundamentals.
  freshStart('Building your fundamentals'),

  /// A specific topic the learner chose.
  chosen('Your selected topic');

  const AdaptiveReason(this.label);

  final String label;
}

/// A single "practice this next" recommendation produced by the adaptive engine
/// — a skill + a target difficulty + the reason, so the UI can explain *why*.
@immutable
class AdaptiveRecommendation {
  const AdaptiveRecommendation({
    required this.skill,
    required this.difficulty,
    required this.reason,
  });

  final PracticeSkill skill;
  final PracticeDifficulty difficulty;
  final AdaptiveReason reason;

  PracticeTopic get topic => skill.topic;

  @override
  bool operator ==(Object other) =>
      other is AdaptiveRecommendation &&
      other.skill == skill &&
      other.difficulty == difficulty &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(skill, difficulty, reason);
}
