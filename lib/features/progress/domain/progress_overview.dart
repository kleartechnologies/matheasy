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
    required this.estimatedMinutes,
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

  // ---- Learning overview ----
  final int questionsSolved;
  final int correctAnswers;
  final int sessionsCompleted;
  final int topicsPracticed;
  final int learningDays;
  final int estimatedMinutes;

  // ---- Mastery ----
  final List<CategoryView> mastery;
  final int topicsMastered;

  // ---- Achievements summary ----
  final int achievementsUnlocked;
  final int achievementsTotal;

  // ---- Activity + Matheasy ----
  final List<LearningActivity> recentActivity;
  final String matheasyInsight;

  /// A friendly, rounded "time learning" label.
  String get timeLearningLabel {
    if (estimatedMinutes < 60) return '${estimatedMinutes}m';
    final hours = estimatedMinutes ~/ 60;
    final minutes = estimatedMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
}
