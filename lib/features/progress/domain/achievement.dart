import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Color;

/// Stable identity for every achievement (used as the persistence key).
enum AchievementId {
  firstScan,
  firstPractice,
  firstCorrect,
  streak3,
  streak7,
  streak30,
  solved10,
  solved50,
  solved100,
  solved500,
  mastered1,
  mastered3,
  mastered5,
  useMatheasy,
  dailyChallenge,
  explore3Topics,
}

/// The theme an achievement belongs to (drives grouping on the achievements
/// screen).
enum AchievementCategory {
  starter('Getting Started'),
  consistency('Consistency'),
  practice('Practice'),
  learning('Mastery'),
  exploration('Exploration');

  const AchievementCategory(this.label);

  final String label;
}

/// A measurable learning metric an achievement tracks. The engine reads these
/// off an [AchievementContext], so adding a metric-based achievement never
/// touches the evaluation logic — the framework stays reusable.
enum AchievementMetric {
  scans,
  practiceSessions,
  correctAnswers,
  questionsSolved,
  streakDays,
  topicsMastered,
  tutorUses,
  dailyChallenges,
  distinctTopics,
}

/// The condition for unlocking: reach [target] on a [metric].
@immutable
class AchievementRequirement {
  const AchievementRequirement(this.metric, this.target);

  final AchievementMetric metric;
  final int target;
}

/// A visual badge (emoji + name + accent color). Emoji keeps badges colorful
/// and instantly recognizable without bundling art.
@immutable
class Badge {
  const Badge({required this.emoji, required this.name, required this.color});

  final String emoji;
  final String name;

  /// Decorative only — the medallion's tint and ring, both at low alpha.
  ///
  /// Never render it as text or as a meaning-bearing icon: the set spans
  /// [AppColors.gold] (1.63:1 on a light surface) and [AppColors.primary]
  /// (2.97:1), so it cannot carry contrast in both themes.
  final Color color;
}

/// What unlocking an achievement grants. [title] and future cosmetic rewards are
/// scaffolded now; only [xp] is wired into the XP system this stage.
@immutable
class AchievementReward {
  const AchievementReward({required this.xp, this.title});

  final int xp;

  /// An optional cosmetic title (infrastructure for a later stage).
  final String? title;
}

/// A single achievement definition (immutable catalog entry).
@immutable
class Achievement {
  const Achievement({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.requirement,
    required this.reward,
    required this.badge,
  });

  final AchievementId id;
  final AchievementCategory category;
  final String title;
  final String description;
  final AchievementRequirement requirement;
  final AchievementReward reward;
  final Badge badge;
}
