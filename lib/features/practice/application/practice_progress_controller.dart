import 'dart:async';
import 'dart:math' as math;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../subscription/application/subscription_controller.dart';
import '../domain/practice_progress.dart';
import '../domain/practice_question.dart';
import '../domain/practice_result.dart';
import '../domain/practice_session.dart';
import '../domain/skill_mastery.dart';
import '../domain/xp_level.dart';
import '../domain/xp_reward.dart';
import 'engine/adaptive_engine.dart';
import 'practice_repository.dart';

part 'practice_progress_controller.g.dart';

/// The learner's persisted practice state (XP, streak, per-topic mastery, last
/// session). Kept alive for the whole app; hydrates from the repository on
/// build and writes back on every recorded session.
///
/// This is the single mutator of [PracticeProgress]; the session and XP layers
/// read from it.
@Riverpod(keepAlive: true)
class PracticeProgressController extends _$PracticeProgressController {
  @override
  PracticeProgress build() => ref.read(practiceRepositoryProvider).load();

  /// Applies a completed [session], persists the new progress, and returns the
  /// [PracticeResult] to display. [now] is injected for deterministic streaks.
  PracticeResult recordSession(PracticeSession session, {required DateTime now}) {
    final topic = session.topic;
    final before = state.topic(topic);
    final beforeLevel = before.level;

    // Mastery grows with each correct answer, weighted by difficulty.
    final questionsById = {for (final q in session.questions) q.id: q};
    var masteryGain = 0;
    for (final answer in session.answers) {
      if (answer.isCorrect) {
        masteryGain += questionsById[answer.questionId]?.difficulty.masteryPoints ?? 0;
      }
    }

    // The daily-challenge bonus is granted at most once per calendar day, and
    // MONOTONICALLY: `< today` (not `!= today`) means winding the device clock
    // backwards after completing today's challenge can't re-arm the bonus for
    // the days in between.
    final today = _epochDay(now);
    final lastDaily = state.lastDailyChallengeEpochDay;
    final awardDaily = session.request.isDailyChallenge &&
        (lastDaily == null || lastDaily < today);
    // Finishing a whole set earns a flat completion bonus — persistence pays
    // even on a rough set (V5 "XP for learning", spec: reward completing).
    final awardCompletion = session.isComplete;
    final sessionXp = session.xpSoFar +
        (awardDaily ? XpReward.dailyChallengeBonus : 0) +
        (awardCompletion ? XpReward.setCompletionBonus : 0);

    final afterTopic = before.copyWith(
      masteryPoints: (before.masteryPoints + masteryGain).clamp(0, 100),
      answered: before.answered + session.total,
      correct: before.correct + session.correctCount,
    );

    // Fine-grained per-skill mastery (Stage 15) — the adaptive engine's signal.
    // Only skill-tagged questions (engine-generated) contribute; hand-authored
    // bank questions have no skillId and are ignored here (topic mastery above
    // still covers them).
    final updatedSkills = _recordSkills(session, questionsById, today);

    final (streakCurrent, streakBest) = _updatedStreak(now);

    final updated = state.copyWith(
      totalXp: state.totalXp + sessionXp,
      streakCurrent: streakCurrent,
      streakBest: streakBest,
      sessionsCompleted: state.sessionsCompleted + 1,
      // Counted only when the once-per-day bonus is earned, so replaying the
      // challenge can't inflate the achievement counter.
      dailyChallengesCompleted:
          state.dailyChallengesCompleted + (awardDaily ? 1 : 0),
      // Monotonic: a rolled-back clock must not rewind the last-practiced day
      // (that would both corrupt the streak and re-arm daily rewards).
      lastPracticedEpochDay: math.max(today, state.lastPracticedEpochDay ?? today),
      lastDailyChallengeEpochDay:
          awardDaily ? today : state.lastDailyChallengeEpochDay,
      topics: {...state.topics, topic: afterTopic},
      skills: updatedSkills,
      lastRequest: session.request,
    );

    state = updated;
    unawaited(ref.read(practiceRepositoryProvider).save(updated));

    final (strong, weak) = _sessionSkillSplit(session, questionsById);
    return PracticeResult(
      request: session.request,
      total: session.total,
      correct: session.correctCount,
      xpEarned: sessionXp,
      masteryBefore: beforeLevel,
      masteryAfter: afterTopic.level,
      masteryPointsAfter: afterTopic.masteryPoints,
      timeSpentSeconds:
          session.answers.fold(0, (sum, a) => sum + a.timeSpentSeconds),
      hintsUsedTotal:
          session.answers.fold(0, (sum, a) => sum + a.hintLevelUsed),
      strongSkills: strong,
      weakSkills: weak,
      // "Practice this next", computed against the UPDATED skills so the
      // session that just ended counts (Pro; null without signal).
      recommendedNext: const AdaptiveEngine().nextRecommendation(
        updated,
        isPro: ref.read(isProProvider),
      ),
    );
  }

  /// Splits the session's skill-tagged work into nailed (accuracy ≥ 0.8) and
  /// needs-review (< 0.5) labels, by THIS session's answers only.
  (List<String>, List<String>) _sessionSkillSplit(
    PracticeSession session,
    Map<String, PracticeQuestion> questionsById,
  ) {
    final attempts = <String, int>{};
    final corrects = <String, int>{};
    for (final answer in session.answers) {
      final question = questionsById[answer.questionId];
      final label = question?.subtopicLabel;
      if (question == null || label == null) continue;
      attempts[label] = (attempts[label] ?? 0) + 1;
      if (answer.isCorrect) corrects[label] = (corrects[label] ?? 0) + 1;
    }
    final strong = <String>[];
    final weak = <String>[];
    for (final entry in attempts.entries) {
      final accuracy = (corrects[entry.key] ?? 0) / entry.value;
      if (accuracy >= 0.8) {
        strong.add(entry.key);
      } else if (accuracy < 0.5) {
        weak.add(entry.key);
      }
    }
    return (strong..sort(), weak..sort());
  }

  /// Folds a session's skill-tagged answers into per-skill mastery. Returns a
  /// new `skills` map (unchanged if the session had no skill-tagged questions).
  Map<String, SkillMastery> _recordSkills(
    PracticeSession session,
    Map<String, PracticeQuestion> questionsById,
    int today,
  ) {
    Map<String, SkillMastery>? next;
    for (final answer in session.answers) {
      final question = questionsById[answer.questionId];
      final skillId = question?.skillId;
      if (question == null || skillId == null) continue;
      next ??= {...state.skills};
      final current = next[skillId] ?? SkillMastery(skillId: skillId);
      next[skillId] = current.record(
        isCorrect: answer.isCorrect,
        masteryGain: question.difficulty.masteryPoints,
        epochDay: today,
      );
    }
    return next ?? state.skills;
  }

  /// Adds bonus XP outside a session (e.g. achievement rewards). This is the
  /// single XP ledger, so achievement XP flows into the same level/total.
  void awardXp(int amount) {
    if (amount <= 0) return;
    final updated = state.copyWith(totalXp: state.totalXp + amount);
    state = updated;
    unawaited(ref.read(practiceRepositoryProvider).save(updated));
  }

  /// Clears all local progress (used by tests / a future "reset progress").
  void reset() {
    state = PracticeProgress.empty;
    unawaited(ref.read(practiceRepositoryProvider).save(PracticeProgress.empty));
  }

  (int current, int best) _updatedStreak(DateTime now) {
    final today = _epochDay(now);
    final last = state.lastPracticedEpochDay;
    final int current;
    if (last == null) {
      current = 1;
    } else if (last >= today) {
      // Already counted today — or the device clock was wound backwards (last
      // is in the "future"). Either way, keep the streak instead of resetting
      // it; the monotonic lastPracticedEpochDay prevents any double-count.
      current = math.max(state.streakCurrent, 1);
    } else if (last == today - 1) {
      current = state.streakCurrent + 1; // consecutive day
    } else {
      current = 1; // streak broken
    }
    return (current, math.max(current, state.streakBest));
  }

  static int _epochDay(DateTime dt) => PracticeProgress.epochDay(dt);
}

/// The learner's XP level, projected from [PracticeProgressController].
///
/// Read-only: XP is awarded through `recordSession`. Satisfies the "XPController"
/// role as the XP-domain projection.
@Riverpod(keepAlive: true)
class XpController extends _$XpController {
  @override
  XpLevel build() =>
      ref.watch(practiceProgressControllerProvider).xpLevel;
}
