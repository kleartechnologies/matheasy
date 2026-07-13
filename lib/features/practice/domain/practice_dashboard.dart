import 'package:flutter/foundation.dart';

import 'mastery.dart';
import 'practice_session.dart';
import 'practice_topic.dart';
import 'xp_level.dart';

/// A topic to strengthen, derived from the learner's REAL scan history — never
/// a placeholder. Carries the raw counts (not a fabricated accuracy %): how many
/// problems in this topic were scanned, and how many of those verified.
@immutable
class WeakTopicView {
  const WeakTopicView({
    required this.topic,
    required this.solvedCount,
    required this.correctCount,
  });

  final PracticeTopic topic;

  /// Problems scanned in this topic.
  final int solvedCount;

  /// Of those, how many produced a verified solution.
  final int correctCount;

  /// Verified-solve rate in [0, 1] — used to rank weakest-first, not displayed.
  double get accuracy => solvedCount == 0 ? 0 : correctCount / solvedCount;
}

/// A topic category tile with its current mastery.
@immutable
class CategoryView {
  const CategoryView({
    required this.topic,
    required this.level,
    required this.progress,
    required this.masteryPoints,
  });

  final PracticeTopic topic;
  final MasteryLevel level;

  /// Progress (0–1) within the current mastery level.
  final double progress;
  final int masteryPoints;
}

/// The daily challenge card's data.
@immutable
class DailyChallengeView {
  const DailyChallengeView({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.target,
    required this.bonusXp,
    required this.request,
  });

  final String title;
  final String subtitle;
  final int done;
  final int target;
  final int bonusXp;
  final PracticeRequest request;

  double get progress => target == 0 ? 0 : (done / target).clamp(0.0, 1.0);
}

/// Everything the Practice dashboard renders — assembled from persisted progress
/// and onboarding answers.
@immutable
class PracticeDashboardData {
  const PracticeDashboardData({
    required this.xpLevel,
    required this.streakCurrent,
    required this.streakBest,
    required this.continueRequest,
    required this.recommendedTopics,
    required this.weakTopics,
    required this.dailyChallenge,
    required this.categories,
    required this.tutorMessage,
  });

  final XpLevel xpLevel;
  final int streakCurrent;
  final int streakBest;

  /// The last session's request, for "Continue practice" (null if none yet).
  final PracticeRequest? continueRequest;

  final List<PracticeTopic> recommendedTopics;
  final List<WeakTopicView> weakTopics;
  final DailyChallengeView dailyChallenge;
  final List<CategoryView> categories;
  final String tutorMessage;
}
