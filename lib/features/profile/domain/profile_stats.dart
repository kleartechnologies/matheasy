import 'package:flutter/foundation.dart';

import '../../progress/domain/progress_overview.dart';

/// The headline learning metrics shown on the Profile screen, projected from the
/// assembled [ProgressOverview] (which itself aggregates XP, streak, achievements
/// and mastery from Practice + Progress).
@immutable
class ProfileStats {
  const ProfileStats({
    required this.xp,
    required this.level,
    required this.levelProgress,
    required this.xpToNext,
    required this.streak,
    required this.achievementsUnlocked,
    required this.achievementsTotal,
    required this.topicsMastered,
    required this.learningDays,
  });

  /// Zero state — used before any progress exists.
  static const ProfileStats empty = ProfileStats(
    xp: 0,
    level: 1,
    levelProgress: 0,
    xpToNext: 0,
    streak: 0,
    achievementsUnlocked: 0,
    achievementsTotal: 0,
    topicsMastered: 0,
    learningDays: 0,
  );

  factory ProfileStats.fromOverview(ProgressOverview overview) {
    final xp = overview.xpLevel;
    return ProfileStats(
      xp: xp.totalXp,
      level: xp.level,
      levelProgress: xp.progress,
      xpToNext: xp.xpToNext,
      streak: overview.streakCurrent,
      achievementsUnlocked: overview.achievementsUnlocked,
      achievementsTotal: overview.achievementsTotal,
      topicsMastered: overview.topicsMastered,
      learningDays: overview.learningDays,
    );
  }

  final int xp;
  final int level;
  final double levelProgress;
  final int xpToNext;
  final int streak;
  final int achievementsUnlocked;
  final int achievementsTotal;
  final int topicsMastered;
  final int learningDays;
}
