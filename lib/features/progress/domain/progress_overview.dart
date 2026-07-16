import 'package:flutter/foundation.dart';

import '../../practice/domain/practice_dashboard.dart' show CategoryView;
import '../../practice/domain/xp_level.dart';
import 'progress_stats.dart';

/// Everything the Progress dashboard renders — assembled from practice progress,
/// local analytics, achievements and the signed-in user.
@immutable
class ProgressOverview {
  const ProgressOverview({
    required this.userName,
    required this.isGuest,
    required this.photoUrl,
    required this.xpLevel,
    required this.streakCurrent,
    required this.streakBest,
    required this.questionsSolved,
    required this.correctAnswers,
    required this.sessionsCompleted,
    required this.topicsPracticed,
    required this.learningDays,
    required this.mastery,
    required this.topicsMastered,
    required this.achievementsUnlocked,
    required this.achievementsTotal,
    required this.recentActivity,
    required this.matheasyInsight,
  });

  // ---- Profile ----
  final String userName;
  final bool isGuest;
  final String? photoUrl;

  // ---- XP / streak ----
  final XpLevel xpLevel;
  final int streakCurrent;
  final int streakBest;

  // ---- Lifetime totals ----
  // Counted, never estimated: every one of these is a real tally. (A
  // `estimatedMinutes` "time learning" figure used to live here, extrapolated
  // from a guessed 45s per question and rendered as if measured — it was
  // removed rather than shown as fact. Reinstate only behind a real timer.)
  final int questionsSolved;
  final int correctAnswers;
  final int sessionsCompleted;
  final int topicsPracticed;
  final int learningDays;

  // ---- Mastery ----
  final List<CategoryView> mastery;
  final int topicsMastered;

  // ---- Achievements summary ----
  final int achievementsUnlocked;
  final int achievementsTotal;

  // ---- Activity + Matheasy ----
  final List<LearningActivity> recentActivity;
  final String matheasyInsight;
}
