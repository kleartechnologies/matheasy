import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../practice/application/practice_progress_controller.dart';
import '../../practice/domain/practice_progress.dart';
import '../../practice/domain/practice_session.dart';
import '../../practice/domain/xp_reward.dart';
import '../../profile/application/profile_controller.dart';
import '../../progress/application/achievement_service.dart';
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
    final now = ref.watch(clockProvider)();

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
      todayChallenge: _dailyChallenge(progress, now),
      weakTopics: _weakTopics(progress),
    );
  }

  /// The real, launchable daily-challenge CTA — its title / size / XP come from
  /// [PracticeRequest.dailyChallenge]. `done` is HONEST: 0, or the full target
  /// only when today's challenge has actually been completed. No fake partial.
  static TodayChallenge _dailyChallenge(PracticeProgress progress, DateTime now) {
    final request = PracticeRequest.dailyChallenge();
    final doneToday = progress.lastDailyChallengeEpochDay == _epochDay(now);
    return TodayChallenge(
      title: request.displayTitle,
      subtitle:
          'Solve ${request.questionCount} ${request.topic.label.toLowerCase()} questions',
      done: doneToday ? request.questionCount : 0,
      target: request.questionCount,
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

  /// UTC-anchored epoch day, matching `PracticeProgressController`'s streak/daily
  /// bookkeeping so the "done today?" comparison lines up exactly.
  static int _epochDay(DateTime dt) =>
      DateTime.utc(dt.year, dt.month, dt.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;
}
