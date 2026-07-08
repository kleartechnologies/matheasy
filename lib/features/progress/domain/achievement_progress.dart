import 'package:flutter/foundation.dart';

import 'achievement.dart';

/// Where an achievement stands for the current learner.
enum AchievementStatus { locked, inProgress, unlocked }

/// Progress toward an achievement's target.
@immutable
class AchievementProgress {
  const AchievementProgress({required this.current, required this.target});

  final int current;
  final int target;

  double get fraction => target == 0 ? 0 : (current / target).clamp(0.0, 1.0);
  bool get isComplete => current >= target;
}

/// An achievement paired with the learner's progress + unlock date — the shape
/// the UI renders.
@immutable
class AchievementView {
  const AchievementView({
    required this.achievement,
    required this.progress,
    this.unlockedAt,
  });

  final Achievement achievement;
  final AchievementProgress progress;

  /// Non-null once unlocked.
  final DateTime? unlockedAt;

  bool get isUnlocked => unlockedAt != null;

  AchievementStatus get status {
    if (isUnlocked) return AchievementStatus.unlocked;
    return progress.current > 0
        ? AchievementStatus.inProgress
        : AchievementStatus.locked;
  }
}

/// A snapshot of every metric the achievement engine evaluates against.
/// Assembled from practice progress + local analytics; the engine reads metrics
/// through [value] so it never depends on where a number came from.
@immutable
class AchievementContext {
  const AchievementContext({
    this.scans = 0,
    this.practiceSessions = 0,
    this.correctAnswers = 0,
    this.questionsSolved = 0,
    this.streakDays = 0,
    this.topicsMastered = 0,
    this.tutorUses = 0,
    this.dailyChallenges = 0,
    this.distinctTopics = 0,
  });

  final int scans;
  final int practiceSessions;
  final int correctAnswers;
  final int questionsSolved;
  final int streakDays;
  final int topicsMastered;
  final int tutorUses;
  final int dailyChallenges;
  final int distinctTopics;

  int value(AchievementMetric metric) => switch (metric) {
        AchievementMetric.scans => scans,
        AchievementMetric.practiceSessions => practiceSessions,
        AchievementMetric.correctAnswers => correctAnswers,
        AchievementMetric.questionsSolved => questionsSolved,
        AchievementMetric.streakDays => streakDays,
        AchievementMetric.topicsMastered => topicsMastered,
        AchievementMetric.tutorUses => tutorUses,
        AchievementMetric.dailyChallenges => dailyChallenges,
        AchievementMetric.distinctTopics => distinctTopics,
      };
}
