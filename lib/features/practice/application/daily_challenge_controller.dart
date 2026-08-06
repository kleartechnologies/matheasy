import 'dart:async';
import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../onboarding/domain/onboarding_models.dart';
import '../../progress/application/trusted_clock.dart';
import '../../settings/application/settings_controller.dart';
import '../../subscription/application/subscription_controller.dart';
import '../domain/daily_challenge.dart';
import '../domain/practice_difficulty.dart';
import '../domain/practice_progress.dart';
import '../domain/practice_session.dart';
import '../domain/practice_skill.dart';
import '../domain/practice_topic.dart';
import 'daily_challenge_repository.dart';
import 'practice_progress_controller.dart';

part 'daily_challenge_controller.g.dart';

/// Owns the daily challenge: exactly one challenge per user per calendar day.
///
/// **The invariants** (the Duolingo contract):
///  * A challenge is planned once per local calendar day and persisted as a
///    `(dayKey, topic, seed)` spec — reopening the app re-derives the SAME
///    questions from the seed; it never regenerates a different set.
///  * At the first check after local midnight (app start, foreground resume, or
///    challenge launch — see [ensureToday]) the old day is archived and a new
///    challenge is planned automatically. No refresh button, no reinstall.
///  * Topic rotation is seeded and weighted: never yesterday's topic (the
///    recent-window exclusion guarantees it), weak topics favoured, and the
///    tier/level gates keep a primary-schooler out of calculus.
///  * Completion state (not started → in progress → completed/perfect) persists
///    for the whole day; finishing is terminal until midnight, so replays can't
///    reset or re-earn it.
///
/// The clock is [trustedClockProvider]: local device time, corrected only when
/// it disagrees wildly with the last observed server time (anti-farming).
@Riverpod(keepAlive: true)
class DailyChallengeController extends _$DailyChallengeController {
  @override
  DailyChallengeState build() {
    final loaded = ref.read(dailyChallengeRepositoryProvider).load();
    final ensured = _ensuredToday(loaded);
    if (!identical(ensured, loaded)) _persist(ensured);
    return ensured;
  }

  // ---- Public API ----------------------------------------------------------

  /// Re-checks that the stored challenge is for TODAY, planning a new one if
  /// the calendar day has changed. Called on app start (via [build]), on
  /// foreground resume (the shell listens to the app lifecycle), and before
  /// every challenge launch — the three moments a stale day could be visible.
  void ensureToday() {
    final ensured = _ensuredToday(state);
    if (identical(ensured, state)) return;
    state = ensured;
    _persist(ensured);
  }

  /// Today's launchable request. Always canonical: whatever stale daily request
  /// a caller holds (a persisted "Continue" card, a card rendered pre-midnight),
  /// sessions must start from THIS.
  PracticeRequest todaysRequest() {
    ensureToday();
    // ensureToday guarantees a planned challenge, so request is non-null.
    return state.request!;
  }

  /// Marks today's challenge opened. Restarting mid-day resets the in-session
  /// tallies (the questions are identical anyway); a COMPLETED day is terminal
  /// until midnight — replaying can't demote it.
  void markStarted() {
    ensureToday();
    if (state.status.isDone) return;
    final updated = state.copyWith(
      status: DailyChallengeStatus.inProgress,
      answered: 0,
      correct: 0,
    );
    state = updated;
    _persist(updated);
  }

  /// Records one finally-resolved answer (correct, or finalized incorrect).
  void recordAnswer({required bool isCorrect}) {
    if (state.status != DailyChallengeStatus.inProgress) return;
    if (state.answered >= state.questionCount) return;
    final updated = state.copyWith(
      answered: state.answered + 1,
      correct: state.correct + (isCorrect ? 1 : 0),
    );
    state = updated;
    _persist(updated);
  }

  /// Marks today's challenge finished. [request] guards against a stale
  /// session: a session generated for a PREVIOUS day (started before midnight,
  /// finished after) must not complete TODAY's untouched challenge.
  void markCompleted({
    required PracticeRequest request,
    required int correct,
    required int total,
  }) {
    ensureToday();
    if (state.status.isDone) return;
    if (request.seed != state.seed || request.topic != state.topic) return;
    final updated = state.copyWith(
      status: total > 0 && correct >= total
          ? DailyChallengeStatus.perfect
          : DailyChallengeStatus.completed,
      answered: state.questionCount,
      correct: correct.clamp(0, state.questionCount),
      completedAtMs: _now().millisecondsSinceEpoch,
    );
    state = updated;
    _persist(updated);
  }

  /// Re-reads persisted state (after a cloud sync merged a change from another
  /// device) and re-ensures it is current.
  void reload() {
    final loaded = ref.read(dailyChallengeRepositoryProvider).load();
    final ensured = _ensuredToday(loaded);
    if (!identical(ensured, loaded)) _persist(ensured);
    state = ensured;
  }

  // ---- Planning ------------------------------------------------------------

  DateTime _now() => ref.read(trustedClockProvider)();

  DailyChallengeState _ensuredToday(DailyChallengeState current) {
    final today = PracticeProgress.epochDay(_now());
    if (current.dayKey == today && current.topic != null) return current;
    // Salt is generated ONCE per install (synced: the merge keeps one side's),
    // then reused so every future day stays deterministic.
    final salt = current.salt != 0 ? current.salt : _newSalt();
    return DailyChallengePlanner.rollover(
      current,
      dayKey: today,
      salt: salt,
      candidates: _candidateTopics(),
      weights: _topicWeights(),
    );
  }

  static int _newSalt() {
    final salt = Random().nextInt(1 << 31);
    return salt == 0 ? 1 : salt;
  }

  /// The topics this learner may be served, honouring the tier gates (free
  /// users only get topics with free skills — same rule as the dashboard) and
  /// the adaptive-difficulty requirement (calculus is AI-tier university
  /// material: only for Pro learners who chose Hard+ or study at SAT level or
  /// above — an easy-level learner must never meet it).
  List<PracticeTopic> _candidateTopics() {
    final isPro = ref.read(isProProvider);
    final topics = PracticeTopic.values
        .where((t) => isPro || PracticeSkill.topicHasFreeSkills(t))
        .toList();
    if (topics.contains(PracticeTopic.calculus)) {
      final learning = ref.read(settingsControllerProvider).learning;
      final advancedLevel = switch (learning.gradeLevel) {
        StudyLevel.sat || StudyLevel.college || StudyLevel.university => true,
        _ => false,
      };
      final advancedDifficulty =
          learning.difficulty.index >= PracticeDifficulty.hard.index;
      if (!advancedLevel && !advancedDifficulty) {
        topics.remove(PracticeTopic.calculus);
      }
    }
    return topics;
  }

  /// Adaptive rotation bias from REAL mastery: weak topics (measured accuracy
  /// under 75% with enough attempts) are 3× as likely, unpracticed topics 1.5×,
  /// so the challenge leans where practice pays most — without ever repeating
  /// within the recent window.
  Map<PracticeTopic, double> _topicWeights() {
    final progress = ref.read(practiceProgressControllerProvider);
    final weights = <PracticeTopic, double>{};
    for (final topic in PracticeTopic.values) {
      final t = progress.topic(topic);
      if (t.answered >= 3 && t.accuracy < 0.75) {
        weights[topic] = 3.0;
      } else if (t.answered == 0) {
        weights[topic] = 1.5;
      }
    }
    return weights;
  }

  void _persist(DailyChallengeState value) =>
      unawaited(ref.read(dailyChallengeRepositoryProvider).save(value));
}
