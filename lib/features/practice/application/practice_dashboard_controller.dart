import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../onboarding/application/onboarding_controller.dart';
import '../domain/practice_dashboard.dart';
import '../domain/practice_progress.dart';
import '../domain/practice_session.dart';
import '../domain/practice_topic.dart';
import '../domain/xp_reward.dart';
import 'practice_progress_controller.dart';

part 'practice_dashboard_controller.g.dart';

/// Assembles the Practice dashboard from persisted [PracticeProgress] and the
/// learner's onboarding answers. Recomputes whenever progress changes (e.g.
/// after a session records XP/mastery).
@riverpod
PracticeDashboardData practiceDashboard(Ref ref) {
  final progress = ref.watch(practiceProgressControllerProvider);
  final onboarding = ref.watch(onboardingFlowControllerProvider);

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
    weakTopics: _weakTopics(progress, recommended),
    dailyChallenge: DailyChallengeView(
      title: 'Daily Challenge',
      subtitle: 'Solve 5 algebra questions',
      done: 0,
      target: 5,
      bonusXp: XpReward.dailyChallengeBonus,
      request: PracticeRequest.dailyChallenge(),
    ),
    categories: categories,
    numiMessage: _numiMessage(progress),
  );
}

/// Weak topics from real progress (lowest accuracy, still practiced) when
/// available, otherwise a friendly starter pair drawn from recommendations.
List<WeakTopicView> _weakTopics(
  PracticeProgress progress,
  List<PracticeTopic> recommended,
) {
  final practiced = progress.topics.values
      .where((t) => t.answered >= 3 && t.accuracy < 0.75)
      .toList()
    ..sort((a, b) => a.accuracy.compareTo(b.accuracy));

  if (practiced.isNotEmpty) {
    return [
      for (final t in practiced.take(2))
        WeakTopicView(
          topic: t.topic,
          accuracy: (t.accuracy * 100).round(),
          note: t.accuracy < 0.6 ? 'needs work' : 'improving',
        ),
    ];
  }

  // Starter placeholders until we've seen enough answers to judge.
  const starters = [
    (PracticeTopic.wordProblems, 54, 'needs work'),
    (PracticeTopic.trigonometry, 61, 'improving'),
  ];
  return [
    for (final (topic, accuracy, note) in starters)
      WeakTopicView(topic: topic, accuracy: accuracy, note: note),
  ];
}

String _numiMessage(PracticeProgress progress) {
  if (progress.streakCurrent > 1) {
    return "You're on a ${progress.streakCurrent}-day streak — keep it going! 🔥";
  }
  if (progress.totalXp > 0) {
    return "Level ${progress.xpLevel.level} and climbing. Let's earn more XP!";
  }
  return "Ready to earn your first XP? Let's practice together! 💪";
}
