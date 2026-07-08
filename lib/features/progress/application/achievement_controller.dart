import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../practice/application/practice_progress_controller.dart';
import '../../practice/domain/mastery.dart';
import '../../practice/domain/practice_progress.dart';
import '../domain/achievement.dart';
import '../domain/achievement_progress.dart';
import '../domain/progress_stats.dart';
import 'achievement_repository.dart';
import 'achievement_service.dart';
import 'stats_controller.dart';

part 'achievement_controller.g.dart';

/// Immutable snapshot the UI renders + a queue of freshly-unlocked achievements
/// awaiting their celebration.
@immutable
class AchievementState {
  const AchievementState({
    this.views = const [],
    this.unlocks = const {},
    this.pending = const [],
  });

  /// Every achievement with its current progress + unlock date.
  final List<AchievementView> views;

  /// Persisted unlock dates keyed by id.
  final Map<AchievementId, DateTime> unlocks;

  /// Newly-unlocked achievements queued for celebration (shown one at a time).
  final List<Achievement> pending;

  int get unlockedCount => unlocks.length;
  int get total => views.length;

  List<AchievementView> get unlocked =>
      views.where((v) => v.isUnlocked).toList();

  AchievementState copyWith({
    List<AchievementView>? views,
    Map<AchievementId, DateTime>? unlocks,
    List<Achievement>? pending,
  }) {
    return AchievementState(
      views: views ?? this.views,
      unlocks: unlocks ?? this.unlocks,
      pending: pending ?? this.pending,
    );
  }
}

/// The achievement engine — the single orchestrator.
///
/// Observes practice progress + analytics, re-evaluates the catalog on any
/// change, unlocks newly-earned achievements (awarding their XP into the Stage-8
/// XP ledger), persists them, logs activity/milestones, and queues celebrations.
/// Kept alive for the whole app so unlocks are caught wherever they happen.
@Riverpod(keepAlive: true)
class AchievementController extends _$AchievementController {
  bool _evaluating = false;

  @override
  AchievementState build() {
    final unlocks = ref.read(achievementRepositoryProvider).load();

    // Re-evaluate whenever progress or analytics change.
    ref.listen(practiceProgressControllerProvider, _onProgressChanged);
    ref.listen(statsControllerProvider, (_, _) => _evaluate());

    // Catch any already-earned-but-unpersisted achievements after first build
    // (side effects are forbidden during build).
    Future.microtask(_evaluate);

    final service = ref.read(achievementServiceProvider);
    return AchievementState(
      views: service.evaluate(_buildContext(), unlocks),
      unlocks: unlocks,
    );
  }

  /// Removes the front celebration once it's been shown.
  void dismissCelebration() {
    if (state.pending.isEmpty) return;
    state = state.copyWith(pending: state.pending.sublist(1));
  }

  void _onProgressChanged(PracticeProgress? prev, PracticeProgress next) {
    if (prev != null) _logMilestones(prev, next);
    _evaluate();
  }

  void _evaluate() {
    if (_evaluating) return;
    _evaluating = true;
    try {
      final service = ref.read(achievementServiceProvider);
      final context = _buildContext();
      final pending = service.pendingUnlocks(context, state.unlocks);

      if (pending.isEmpty) {
        state = state.copyWith(views: service.evaluate(context, state.unlocks));
        return;
      }

      final now = ref.read(clockProvider)();
      final unlocks = {
        ...state.unlocks,
        for (final achievement in pending) achievement.id: now,
      };

      // Persist the unlock set BEFORE awarding its XP. The two writes hit the
      // (FIFO) prefs channel in this order, so a crash mid-flight can only
      // under-grant (the unlock is recorded, XP re-awarded never) — not
      // double-grant (XP kept, unlock lost → re-award on next launch).
      unawaited(ref.read(achievementRepositoryProvider).save(unlocks));

      // Reward XP into the single Stage-8 XP ledger.
      final bonusXp = pending.fold(0, (sum, a) => sum + a.reward.xp);
      if (bonusXp > 0) {
        ref.read(practiceProgressControllerProvider.notifier).awardXp(bonusXp);
      }

      final stats = ref.read(statsControllerProvider.notifier);
      for (final achievement in pending) {
        stats.logActivity(
          LearningActivity(
            type: LearningActivityType.achievement,
            title: 'Unlocked “${achievement.badge.name}”',
            subtitle: achievement.description,
            epochMillis: now.millisecondsSinceEpoch,
            emoji: achievement.badge.emoji,
          ),
        );
      }

      state = state.copyWith(
        views: service.evaluate(context, unlocks),
        unlocks: unlocks,
        pending: [...state.pending, ...pending],
      );
    } finally {
      _evaluating = false;
    }
  }

  void _logMilestones(PracticeProgress prev, PracticeProgress next) {
    final stats = ref.read(statsControllerProvider.notifier);
    final now = ref.read(clockProvider)();
    final millis = now.millisecondsSinceEpoch;

    if (next.sessionsCompleted > prev.sessionsCompleted) {
      final topic = next.lastRequest?.topic;
      stats.logActivity(
        LearningActivity(
          type: LearningActivityType.practice,
          title: topic != null
              ? 'Practiced ${topic.label}'
              : 'Completed a practice session',
          subtitle: 'Nice work — session complete!',
          epochMillis: millis,
        ),
      );
    }

    if (next.xpLevel.level > prev.xpLevel.level) {
      stats.logActivity(
        LearningActivity(
          type: LearningActivityType.milestone,
          title: 'Reached Level ${next.xpLevel.level}',
          subtitle: 'Your XP keeps climbing!',
          epochMillis: millis,
        ),
      );
    }

    for (final entry in next.topics.entries) {
      final before = prev.topics[entry.key];
      final becameMastered = entry.value.level == MasteryLevel.mastered &&
          (before == null || before.level != MasteryLevel.mastered);
      if (becameMastered) {
        stats.logActivity(
          LearningActivity(
            type: LearningActivityType.milestone,
            title: 'Mastered ${entry.key.label}',
            subtitle: 'You reached full mastery!',
            epochMillis: millis,
          ),
        );
      }
    }
  }

  AchievementContext _buildContext() {
    final progress = ref.read(practiceProgressControllerProvider);
    final stats = ref.read(statsControllerProvider);
    final topics = progress.topics.values;

    return AchievementContext(
      scans: stats.scans,
      practiceSessions: progress.sessionsCompleted,
      correctAnswers: topics.fold(0, (sum, t) => sum + t.correct),
      questionsSolved: topics.fold(0, (sum, t) => sum + t.answered),
      // Best streak so an earned streak achievement never regresses.
      streakDays: progress.streakBest,
      topicsMastered:
          topics.where((t) => t.level == MasteryLevel.mastered).length,
      tutorUses: stats.tutorUses,
      dailyChallenges: progress.dailyChallengesCompleted,
      distinctTopics: topics.where((t) => t.answered > 0).length,
    );
  }
}

/// The celebration queue only — so the global overlay host rebuilds solely when
/// a badge is unlocked, not on every progress refresh.
final Provider<List<Achievement>> pendingCelebrationsProvider =
    Provider<List<Achievement>>(
  (ref) => ref.watch(achievementControllerProvider).pending,
);
