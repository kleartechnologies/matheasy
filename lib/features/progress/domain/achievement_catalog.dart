import '../../../core/theme/app_colors.dart';
import 'achievement.dart';

/// The full, static achievement catalog. Adding an achievement is a one-line
/// entry here — the metric-based engine handles evaluation, unlock, reward and
/// display automatically.
class Achievements {
  const Achievements._();

  static const List<Achievement> all = [
    // ---- Getting started ----
    Achievement(
      id: AchievementId.firstScan,
      category: AchievementCategory.starter,
      title: 'First Scan',
      description: 'Scan your first math problem.',
      requirement: AchievementRequirement(AchievementMetric.scans, 1),
      reward: AchievementReward(xp: 20),
      badge: Badge(emoji: '📷', name: 'First Scan', color: AppColors.primary),
    ),
    Achievement(
      id: AchievementId.firstPractice,
      category: AchievementCategory.starter,
      title: 'First Steps',
      description: 'Complete your first practice session.',
      requirement: AchievementRequirement(AchievementMetric.practiceSessions, 1),
      reward: AchievementReward(xp: 25),
      badge: Badge(emoji: '🌟', name: 'First Steps', color: AppColors.primary),
    ),
    Achievement(
      id: AchievementId.firstCorrect,
      category: AchievementCategory.starter,
      title: 'Nailed It',
      description: 'Answer your first question correctly.',
      requirement: AchievementRequirement(AchievementMetric.correctAnswers, 1),
      reward: AchievementReward(xp: 15),
      badge: Badge(emoji: '✅', name: 'Nailed It', color: AppColors.accentAmber),
    ),

    // ---- Consistency ----
    Achievement(
      id: AchievementId.streak3,
      category: AchievementCategory.consistency,
      title: 'On Fire',
      description: 'Practice 3 days in a row.',
      requirement: AchievementRequirement(AchievementMetric.streakDays, 3),
      reward: AchievementReward(xp: 50),
      badge: Badge(emoji: '🔥', name: 'On Fire', color: AppColors.streak),
    ),
    Achievement(
      id: AchievementId.streak7,
      category: AchievementCategory.consistency,
      title: 'Week Warrior',
      description: 'Practice 7 days in a row.',
      requirement: AchievementRequirement(AchievementMetric.streakDays, 7),
      reward: AchievementReward(xp: 100),
      badge: Badge(emoji: '🔥', name: 'Week Warrior', color: AppColors.warning),
    ),
    Achievement(
      id: AchievementId.streak30,
      category: AchievementCategory.consistency,
      title: 'Unstoppable',
      description: 'Practice 30 days in a row.',
      requirement: AchievementRequirement(AchievementMetric.streakDays, 30),
      reward: AchievementReward(xp: 300),
      badge: Badge(emoji: '🏆', name: 'Unstoppable', color: AppColors.gold),
    ),

    // ---- Practice volume ----
    Achievement(
      id: AchievementId.solved10,
      category: AchievementCategory.practice,
      title: 'Problem Solver',
      description: 'Answer 10 practice questions.',
      requirement: AchievementRequirement(AchievementMetric.questionsSolved, 10),
      reward: AchievementReward(xp: 30),
      badge: Badge(emoji: '🧠', name: 'Problem Solver', color: AppColors.secondary),
    ),
    Achievement(
      id: AchievementId.solved50,
      category: AchievementCategory.practice,
      title: 'Getting Strong',
      description: 'Answer 50 practice questions.',
      requirement: AchievementRequirement(AchievementMetric.questionsSolved, 50),
      reward: AchievementReward(xp: 75),
      badge:
          Badge(emoji: '💪', name: 'Getting Strong', color: AppColors.secondary),
    ),
    Achievement(
      id: AchievementId.solved100,
      category: AchievementCategory.practice,
      title: 'Century',
      description: 'Answer 100 practice questions.',
      requirement:
          AchievementRequirement(AchievementMetric.questionsSolved, 100),
      reward: AchievementReward(xp: 150),
      badge: Badge(emoji: '💯', name: 'Century', color: AppColors.secondary),
    ),
    Achievement(
      id: AchievementId.solved500,
      category: AchievementCategory.practice,
      title: 'Math Royalty',
      description: 'Answer 500 practice questions.',
      requirement:
          AchievementRequirement(AchievementMetric.questionsSolved, 500),
      reward: AchievementReward(xp: 500, title: 'Math Royalty'),
      badge: Badge(emoji: '👑', name: 'Math Royalty', color: AppColors.gold),
    ),

    // ---- Mastery ----
    Achievement(
      id: AchievementId.mastered1,
      category: AchievementCategory.learning,
      title: 'Topic Master',
      description: 'Fully master your first topic.',
      requirement: AchievementRequirement(AchievementMetric.topicsMastered, 1),
      reward: AchievementReward(xp: 150),
      badge: Badge(emoji: '🎓', name: 'Topic Master', color: AppColors.accentAmber),
    ),
    Achievement(
      id: AchievementId.mastered3,
      category: AchievementCategory.learning,
      title: 'Math Explorer',
      description: 'Master 3 different topics.',
      requirement: AchievementRequirement(AchievementMetric.topicsMastered, 3),
      reward: AchievementReward(xp: 300),
      badge: Badge(emoji: '📚', name: 'Math Explorer', color: AppColors.accentAmber),
    ),
    Achievement(
      id: AchievementId.mastered5,
      category: AchievementCategory.learning,
      title: 'Grand Master',
      description: 'Master 5 different topics.',
      requirement: AchievementRequirement(AchievementMetric.topicsMastered, 5),
      reward: AchievementReward(xp: 500, title: 'Grand Master'),
      badge: Badge(emoji: '🏆', name: 'Grand Master', color: AppColors.gold),
    ),

    // ---- Exploration ----
    Achievement(
      id: AchievementId.useMatheasy,
      category: AchievementCategory.exploration,
      title: 'Met Matheasy',
      description: 'Chat with Matheasy, your AI tutor.',
      requirement: AchievementRequirement(AchievementMetric.tutorUses, 1),
      reward: AchievementReward(xp: 20),
      badge: Badge(emoji: '💬', name: 'Met Matheasy', color: AppColors.primary),
    ),
    Achievement(
      id: AchievementId.dailyChallenge,
      category: AchievementCategory.exploration,
      title: 'Challenger',
      description: 'Complete a daily challenge.',
      requirement: AchievementRequirement(AchievementMetric.dailyChallenges, 1),
      reward: AchievementReward(xp: 50),
      badge: Badge(emoji: '⚡', name: 'Challenger', color: AppColors.amber),
    ),
    Achievement(
      id: AchievementId.explore3Topics,
      category: AchievementCategory.exploration,
      title: 'Explorer',
      description: 'Practice 3 different topics.',
      requirement: AchievementRequirement(AchievementMetric.distinctTopics, 3),
      reward: AchievementReward(xp: 75),
      badge: Badge(emoji: '🗺️', name: 'Explorer', color: AppColors.pink),
    ),
  ];

  static Achievement byId(AchievementId id) =>
      all.firstWhere((a) => a.id == id);
}
