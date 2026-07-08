import 'package:flutter/foundation.dart';

import 'mastery.dart';
import 'practice_session.dart';
import 'practice_topic.dart';
import 'xp_level.dart';

/// A topic the learner is weaker in (shown on the dashboard).
@immutable
class WeakTopicView {
  const WeakTopicView({
    required this.topic,
    required this.accuracy,
    required this.note,
  });

  final PracticeTopic topic;

  /// Accuracy percentage (0–100).
  final int accuracy;
  final String note;
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
    required this.numiMessage,
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
  final String numiMessage;
}
