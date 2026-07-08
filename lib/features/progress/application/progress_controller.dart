import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/application/auth_controller.dart';
import '../../practice/application/practice_progress_controller.dart';
import '../../practice/domain/mastery.dart';
import '../../practice/domain/practice_dashboard.dart' show CategoryView;
import '../../practice/domain/practice_progress.dart';
import '../../practice/domain/practice_topic.dart';
import '../domain/progress_overview.dart';
import '../domain/progress_stats.dart';
import 'achievement_controller.dart';
import 'stats_controller.dart';

part 'progress_controller.g.dart';

/// Assembles the Progress dashboard from practice progress, local analytics,
/// achievements and the signed-in user. Recomputes whenever any of those change.
@Riverpod(keepAlive: true)
class ProgressController extends _$ProgressController {
  @override
  ProgressOverview build() {
    final progress = ref.watch(practiceProgressControllerProvider);
    final stats = ref.watch(statsControllerProvider);
    final achievements = ref.watch(achievementControllerProvider);
    final user = ref.watch(currentUserProvider);

    final topics = progress.topics.values;
    final questionsSolved = topics.fold(0, (sum, t) => sum + t.answered);
    final correctAnswers = topics.fold(0, (sum, t) => sum + t.correct);
    final mastered =
        topics.where((t) => t.level == MasteryLevel.mastered).length;
    final distinct = topics.where((t) => t.answered > 0).length;

    final mastery = [
      for (final topic in PracticeTopic.values)
        CategoryView(
          topic: topic,
          level: progress.topic(topic).level,
          progress: progress.topic(topic).levelProgress,
          masteryPoints: progress.topic(topic).masteryPoints,
        ),
    ];

    final name = user == null
        ? 'Learner'
        : (user.displayName ??
            (user.isGuest ? 'Guest' : (user.email?.split('@').first ?? 'Learner')));

    return ProgressOverview(
      userName: name,
      isGuest: user?.isGuest ?? true,
      photoUrl: user?.photoUrl,
      xpLevel: progress.xpLevel,
      streakCurrent: progress.streakCurrent,
      streakBest: progress.streakBest,
      questionsSolved: questionsSolved,
      correctAnswers: correctAnswers,
      sessionsCompleted: progress.sessionsCompleted,
      topicsPracticed: distinct,
      learningDays: stats.learningDayCount,
      // A light estimate (~45s per question) — the timer arrives in a later stage.
      estimatedMinutes: (questionsSolved * 0.75).round(),
      mastery: mastery,
      topicsMastered: mastered,
      achievementsUnlocked: achievements.unlockedCount,
      achievementsTotal: achievements.total,
      recentActivity: stats.recentActivity,
      numiInsight: _insight(progress, stats, mastered),
    );
  }

  String _insight(PracticeProgress progress, ProgressStats stats, int mastered) {
    if (!progress.hasHistory && stats.scans == 0) {
      return "Let's begin! Scan a problem or try a quick practice to start "
          'earning XP.';
    }
    if (progress.streakCurrent >= 3) {
      return "You're on a ${progress.streakCurrent}-day streak — incredible "
          'consistency! Keep the momentum going. 🔥';
    }
    if (mastered > 0) {
      return "You've mastered $mastered "
          '${mastered == 1 ? 'topic' : 'topics'}. Numi is proud — ready for the '
          'next one?';
    }
    return "You've earned ${progress.totalXp} XP so far. A little practice each "
        'day adds up fast!';
  }
}
