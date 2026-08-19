import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../history/application/history_controller.dart';
import '../../history/domain/history_entry.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../domain/daily_challenge.dart';
import '../domain/practice_dashboard.dart';
import '../domain/practice_progress.dart';
import '../domain/practice_session.dart';
import '../domain/practice_topic.dart';
import '../domain/xp_reward.dart';
import 'daily_challenge_controller.dart';
import 'practice_progress_controller.dart';

part 'practice_dashboard_controller.g.dart';

/// Assembles the Practice dashboard from persisted [PracticeProgress] and the
/// learner's onboarding answers. Recomputes whenever progress changes (e.g.
/// after a session records XP/mastery).
@riverpod
PracticeDashboardData practiceDashboard(Ref ref) {
  final progress = ref.watch(practiceProgressControllerProvider);
  final onboarding = ref.watch(onboardingFlowControllerProvider);
  final history = ref.watch(historyControllerProvider);
  final daily = ref.watch(dailyChallengeControllerProvider);

  final recommended = onboarding.topics.isEmpty
      ? const [
          PracticeTopic.algebra,
          PracticeTopic.fractions,
          PracticeTopic.geometry,
        ]
      : onboarding.topics.map(PracticeTopic.fromMathTopic).toList();

  final categories = [
    for (final topic in PracticeTopic.values)
      CategoryView(
        topic: topic,
        level: progress.topic(topic).level,
        progress: progress.topic(topic).levelProgress,
        masteryPoints: progress.topic(topic).masteryPoints,
      ),
  ];

  return PracticeDashboardData(
    xpLevel: progress.xpLevel,
    streakCurrent: progress.streakCurrent,
    streakBest: progress.streakBest,
    continueRequest: progress.lastRequest,
    recommendedTopics: recommended,
    weakTopics: _weakTopics(history),
    dailyChallenge: _dailyChallenge(daily),
    categories: categories,
    tutorMessage: _tutorMessage(progress),
  );
}

/// Today's challenge, reported from the persisted per-day [DailyChallengeState]:
/// real topic-of-the-day, live answered count while in progress, and a sticky
/// completed/perfect state that survives until the next local midnight.
DailyChallengeView _dailyChallenge(DailyChallengeState daily) {
  final request = daily.request ?? PracticeRequest.dailyChallenge();
  final target = request.questionCount;
  final done = daily.status.isDone ? target : daily.answered.clamp(0, target);
  final topicLabel = request.topic.label.toLowerCase();
  final subtitle = switch (daily.status) {
    DailyChallengeStatus.perfect =>
      'Perfect! All $target correct — come back tomorrow',
    DailyChallengeStatus.completed => 'Done for today — come back tomorrow',
    DailyChallengeStatus.inProgress =>
      'Keep going — $done of $target $topicLabel questions done',
    DailyChallengeStatus.notStarted => 'Solve $target $topicLabel questions',
  };
  return DailyChallengeView(
    title: 'Daily Challenge',
    subtitle: subtitle,
    done: done,
    target: target,
    bonusXp: XpReward.dailyChallengeBonus,
    request: request,
  );
}

/// "Strengthen these" — built ENTIRELY from the learner's real scan history,
/// never placeholders. Each scanned problem is aggregated into its topic (total
/// solved + how many verified); topics are ranked weakest-first. Returns empty
/// when there's no scan history, so the section hides itself for a new user.
List<WeakTopicView> _weakTopics(List<HistoryEntry> history) {
  final solved = <PracticeTopic, int>{};
  final correct = <PracticeTopic, int>{};
  for (final entry in history) {
    final topic = PracticeTopic.fromResultType(entry.result.type);
    solved[topic] = (solved[topic] ?? 0) + 1;
    if (entry.result.verified) correct[topic] = (correct[topic] ?? 0) + 1;
  }

  return [
    for (final topic in solved.keys)
      WeakTopicView(
        topic: topic,
        solvedCount: solved[topic]!,
        correctCount: correct[topic] ?? 0,
      ),
  ]..sort((a, b) {
      // Weakest first: lowest verified-rate, then fewest solved (matches the
      // spec example — Fractions[1] before Algebra[2] when both fully verified).
      final byAccuracy = a.accuracy.compareTo(b.accuracy);
      return byAccuracy != 0
          ? byAccuracy
          : a.solvedCount.compareTo(b.solvedCount);
    });
}

String _tutorMessage(PracticeProgress progress) {
  if (progress.streakCurrent > 1) {
    return "You're on a ${progress.streakCurrent}-day streak — keep it going! 🔥";
  }
  if (progress.totalXp > 0) {
    return "Level ${progress.xpLevel.level} and climbing. Let's earn more XP!";
  }
  return "Ready to earn your first XP? Let's practice together! 💪";
}
