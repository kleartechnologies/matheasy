import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../practice/application/daily_challenge_controller.dart';
import '../../practice/application/practice_progress_controller.dart';
import '../../practice/domain/daily_challenge.dart';
import '../../practice/domain/practice_progress.dart';
import '../../practice/domain/practice_session.dart';
import '../../practice/domain/xp_reward.dart';
import '../../profile/application/profile_controller.dart';
import '../domain/home_models.dart';

part 'home_controller.g.dart';

/// Supplies Home's data — derived entirely from REAL per-user state, never a
/// mock.
///
/// Identity comes from [profileControllerProvider] (the SAME source the greeting
/// avatar reads, so name + avatar always agree). Because that provider
/// transitively watches `currentUserProvider`, Home rebuilds across the
/// sign-in / sign-up boundary — that reactive dependency is the whole fix for
/// "Home shows the previous/demo user after signup".
///
/// Learning state (streak, weak topics, daily-challenge completion, first-day)
/// comes from [practiceProgressControllerProvider]. A brand-new account gets an
/// HONEST first-day Home — 'Learner', zeros, hidden cards — never a fabricated
/// streak or accuracy.
@riverpod
class HomeController extends _$HomeController {
  @override
  HomeData build() {
    final profile = ref.watch(profileControllerProvider);
    final progress = ref.watch(practiceProgressControllerProvider);
    final daily = ref.watch(dailyChallengeControllerProvider);

    return HomeData(
      userName: profile.displayName,
      isFirstDay: !progress.hasHistory,
      streak: StreakInfo(
        current: progress.streakCurrent,
        best: progress.streakBest,
      ),
      // No real course/lesson-count source exists → empty, so the continue card
      // is hidden (never fabricated "8 / 11 lessons").
      continueCourses: const [],
      todayChallenge: _dailyChallenge(daily),
      weakTopics: _weakTopics(progress),
    );
  }

  /// The real, launchable daily-challenge CTA, built from the persisted per-day
  /// [DailyChallengeState]: today's actual topic, a live answered count while in
  /// progress, and the full target once completed — honest, never a fake
  /// partial.
  static TodayChallenge _dailyChallenge(DailyChallengeState daily) {
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
    return TodayChallenge(
      title: request.displayTitle,
      subtitle: subtitle,
      done: done,
      target: target,
      xpReward: XpReward.dailyChallengeBonus,
    );
  }

  /// Weak topics from REAL measured accuracy only: topics with enough attempts
  /// (≥3) and accuracy below 75%, weakest first. An unpracticed learner has
  /// none, so the recommendation card is hidden — never a fabricated accuracy.
  static List<WeakTopic> _weakTopics(PracticeProgress progress) {
    final weak = progress.topics.entries
        .where((e) => e.value.answered >= 3 && e.value.accuracy < 0.75)
        .toList()
      ..sort((a, b) => a.value.accuracy.compareTo(b.value.accuracy));
    return [
      for (final entry in weak)
        WeakTopic(
          label: entry.key.label,
          icon: entry.key.icon,
          accuracy: (entry.value.accuracy * 100).round(),
        ),
    ];
  }
}
