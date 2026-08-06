import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/monitoring/logging_service.dart';
import '../../../core/security/rate_limit_result.dart';
import '../../../core/security/rate_limit_service.dart';
import '../../../core/services/haptics_service.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../practice_set/application/practice_set_controller.dart';
import '../../progress/application/achievement_service.dart' show clockProvider;
import '../../subscription/application/subscription_controller.dart';
import '../../subscription/application/usage_controller.dart';
import '../domain/practice_difficulty.dart';
import '../domain/practice_mistake.dart';
import '../domain/practice_question.dart';
import '../domain/practice_result.dart';
import '../domain/practice_session.dart';
import '../domain/xp_reward.dart';
import 'engine/difficulty_engine.dart';
import 'engine/session_adaptation.dart';
import 'practice_difficulty_preference.dart';
import 'practice_progress_controller.dart';
import 'practice_service.dart';

part 'practice_controller.g.dart';

/// How a "Challenge Me" request ended.
enum ChallengeOutcome {
  /// A harder question was inserted and is now on screen.
  inserted,

  /// The free-tier practice allowance is exhausted — surface the upsell.
  locked,

  /// The engine couldn't build one right now — carry on, no harm done.
  unavailable,
}

/// The lifecycle of a practice session.
enum PracticePhase {
  /// Nothing started yet.
  idle,

  /// Building the session.
  loading,

  /// Awaiting the current question's answer.
  answering,

  /// The last submission was incorrect but the question is NOT final — the
  /// student can try again, take a hint, open the solution, or ask Numi.
  retry,

  /// The current question is RESOLVED (correct, or finalized incorrect) —
  /// showing feedback + explanation.
  revealed,

  /// All questions answered — showing results.
  complete,

  /// The session couldn't be built.
  error,

  /// The free-tier practice-generation limit is reached — the screen surfaces
  /// the paywall instead of building a session.
  locked,
}

/// Immutable snapshot of the active session, exposed by [PracticeController].
@immutable
class PracticeSessionState {
  const PracticeSessionState({
    this.phase = PracticePhase.idle,
    this.session,
    this.lastAnswer,
    this.result,
    this.attempt,
  });

  final PracticePhase phase;
  final PracticeSession? session;

  /// The answer just submitted (drives the feedback panel while [revealed]).
  final PracticeAnswer? lastAnswer;

  /// The final result once [complete].
  final PracticeResult? result;

  /// Live progress on the CURRENT question (attempts / hint level / timing).
  /// Non-null whenever a question is on screen; reset per question.
  final QuestionAttempt? attempt;

  bool get isLoading => phase == PracticePhase.loading;
  bool get isAnswering => phase == PracticePhase.answering;
  bool get isRetry => phase == PracticePhase.retry;
  bool get isRevealed => phase == PracticePhase.revealed;
  bool get isComplete => phase == PracticePhase.complete;
  bool get lastWasCorrect => lastAnswer?.isCorrect ?? false;

  /// The hint level the student has requested on the current question (0–4).
  int get hintLevel => attempt?.hintLevel ?? 0;

  /// The mistake in play (for "Your answer: X", the Numi hand-off and the
  /// Visual walkthrough) — the not-yet-final wrong submission while [retry],
  /// or the finalized incorrect answer while [revealed].
  PracticeMistake? get mistake {
    final current = session;
    if (current == null) return null;
    if (phase == PracticePhase.retry) {
      final submitted = attempt?.lastSubmitted;
      if (submitted == null) return null;
      return PracticeMistake(
        question: current.currentQuestion,
        submittedAnswer: submitted,
      );
    }
    final answer = lastAnswer;
    if (answer == null || answer.isCorrect) return null;
    return PracticeMistake(
      question: current.currentQuestion,
      submittedAnswer: answer.submitted,
    );
  }
}

/// Drives a practice session: build → answer → feedback → next → results.
///
/// Kept alive so a session survives navigation within the flow; [start] resets
/// it for each launch. On completion it records the outcome into
/// [PracticeProgressController] (XP / mastery / streak).
@Riverpod(keepAlive: true)
class PracticeController extends _$PracticeController {
  @override
  PracticeSessionState build() => const PracticeSessionState();

  /// Builds and begins a session for [request].
  ///
  /// Gates before generating: a free user out of practice questions is moved to
  /// [PracticePhase.locked] (the screen surfaces the paywall) rather than being
  /// interrupted mid-session. On success, the freshly generated questions are
  /// counted against the free-tier quota.
  Future<void> start(PracticeRequest rawRequest) async {
    // The learner's saved level is the AUTHORITY, whatever launched the session
    // (see [_atChosenDifficulty]).
    final request = _atChosenDifficulty(rawRequest);
    if (!ref.read(usageSnapshotProvider).canGeneratePractice) {
      state = const PracticeSessionState(phase: PracticePhase.locked);
      return;
    }
    // Client-side abuse guard (server enforcement is authoritative).
    final limit = ref
        .read(rateLimitServiceProvider)
        .check(RateLimitedAction.practiceGeneration);
    if (limit.isLimited) {
      LoggingService.warning('Practice generation rate-limited: ${limit.reason}');
      state = const PracticeSessionState(phase: PracticePhase.error);
      return;
    }
    state = const PracticeSessionState(phase: PracticePhase.loading);
    try {
      final session =
          await ref.read(practiceServiceProvider).createSession(request);
      if (session.questions.isEmpty) {
        state = const PracticeSessionState(phase: PracticePhase.error);
        return;
      }
      ref
          .read(usageControllerProvider.notifier)
          .recordPracticeGenerated(session.questions.length);
      final analytics = ref.read(analyticsServiceProvider);
      unawaited(analytics
          .logEvent(AnalyticsEvent.practiceStarted(topic: request.topic.name)));
      unawaited(analytics.logEvent(AnalyticsEvent.questionGenerated(
        topic: request.topic.name,
        difficulty: request.difficulty?.name ?? 'adaptive',
        count: session.questions.length,
      )));
      // The engine may have had to serve below the chosen level (a topic whose
      // hardest concept sits under it, or an exhausted tier falling back to the
      // bank). Log it rather than let the mismatch pass silently — this is the
      // signal for "I picked Hard and got an easy question".
      final served = session.questions.map((q) => q.difficulty).toSet();
      if (request.difficulty != null &&
          served.any((d) => d != request.difficulty)) {
        LoggingService.warning(
          'Practice served ${served.map((d) => d.name).join("/")} for a '
          'requested ${request.difficulty!.name} ${request.topic.name} session',
        );
      }
      // Adaptive, weakness-targeted sessions are a Pro capability — track uptake.
      if (request.adaptive && ref.read(isProProvider)) {
        unawaited(analytics.logEvent(
            AnalyticsEvent.adaptiveRecommendationUsed(topic: request.topic.name)));
      }
      state = PracticeSessionState(
        phase: PracticePhase.answering,
        session: session,
        attempt: _freshAttempt(),
      );
    } catch (_) {
      state = const PracticeSessionState(phase: PracticePhase.error);
    }
  }

  DateTime _now() => ref.read(clockProvider)();

  QuestionAttempt _freshAttempt() =>
      QuestionAttempt(startedAtMillis: _now().millisecondsSinceEpoch);

  int _elapsedSeconds(QuestionAttempt attempt) {
    final seconds =
        (_now().millisecondsSinceEpoch - attempt.startedAtMillis) ~/ 1000;
    return seconds < 0 ? 0 : seconds;
  }

  /// Stamps [request] with the learner's chosen practice difficulty.
  ///
  /// The level is a SETTING (Settings → Learning preferences → Practice
  /// difficulty), not a per-launch choice, so it has to apply to every way a
  /// session can start — the daily challenge, "practice this" off a solved
  /// problem, a Numi practice card, a resumed session — not only the topic cards
  /// on the Practice tab, which were previously the ONLY caller that passed it.
  /// Every other entry point sent `difficulty: null`, which the engine reads as
  /// "derive it from mastery", and a learner with little history cold-starts at
  /// easy — so choosing Hard genuinely produced easy questions.
  ///
  /// A persisted `lastRequest` (the Continue card) is re-stamped for the same
  /// reason: it carries whatever level was current when it was saved, which is
  /// stale the moment the setting changes.
  PracticeRequest _atChosenDifficulty(PracticeRequest request) {
    final chosen = ref.read(selectedPracticeDifficultyProvider);
    if (request.difficulty == chosen) return request;
    return request.copyWith(difficulty: chosen);
  }

  /// Grades a submitted answer (an option's text, or typed input).
  ///
  /// Correct → the question resolves ([PracticePhase.revealed]) and the FINAL
  /// answer is recorded with its journey metadata (attempts, hint level,
  /// solution views, time) and journey-scaled XP. Incorrect → nothing is
  /// recorded yet; the session moves to [PracticePhase.retry] so the student
  /// can try again, take a hint, open the solution, or ask Numi.
  void submit(String submitted) {
    final session = state.session;
    if (session == null ||
        (state.phase != PracticePhase.answering &&
            state.phase != PracticePhase.retry)) {
      return;
    }

    final question = session.currentQuestion;
    final isCorrect = question.evaluate(submitted);
    isCorrect ? HapticsService.success() : HapticsService.warning();

    final attempt = (state.attempt ?? _freshAttempt()).copyWith(
      attempts: (state.attempt?.attempts ?? 0) + 1,
      lastSubmitted: submitted,
    );

    final analytics = ref.read(analyticsServiceProvider);
    unawaited(analytics.logEvent(isCorrect
        ? AnalyticsEvent.questionCorrect(
            topic: question.topic.name, difficulty: question.difficulty.name)
        : AnalyticsEvent.questionIncorrect(
            topic: question.topic.name, difficulty: question.difficulty.name)));

    if (!isCorrect) {
      state = PracticeSessionState(
        phase: PracticePhase.retry,
        session: session,
        attempt: attempt,
      );
      return;
    }

    final answer = PracticeAnswer(
      questionId: question.id,
      submitted: submitted,
      isCorrect: true,
      xpEarned: XpReward.forOutcome(
        question.difficulty,
        attempts: attempt.attempts,
        hintLevelUsed: attempt.hintLevel,
        viewedSolution: attempt.viewedSolution,
      ),
      attempts: attempt.attempts,
      hintLevelUsed: attempt.hintLevel,
      viewedSolution: attempt.viewedSolution,
      timeSpentSeconds: _elapsedSeconds(attempt),
    );

    state = PracticeSessionState(
      phase: PracticePhase.revealed,
      session: session.recordAnswer(answer),
      lastAnswer: answer,
      attempt: attempt,
    );
  }

  /// Back from [PracticePhase.retry] to answering — same question, same
  /// attempt state (the retry itself already counted on the next submit).
  void tryAgain() {
    if (state.phase != PracticePhase.retry) return;
    unawaited(
        ref.read(analyticsServiceProvider).logEvent(AnalyticsEvent.practiceRetry()));
    state = PracticeSessionState(
      phase: PracticePhase.answering,
      session: state.session,
      attempt: state.attempt,
    );
  }

  /// Escalates the hint ladder one level (1 nudge → 2 method → 3 first step →
  /// 4 guided solution), capped at 4. Allowed while the question is open.
  void requestHint() {
    if (state.phase != PracticePhase.answering &&
        state.phase != PracticePhase.retry) {
      return;
    }
    final attempt = state.attempt ?? _freshAttempt();
    if (attempt.hintLevel >= 4) return;
    final level = attempt.hintLevel + 1;
    unawaited(ref
        .read(analyticsServiceProvider)
        .logEvent(AnalyticsEvent.practiceHintRequested(level: level)));
    state = PracticeSessionState(
      phase: state.phase,
      session: state.session,
      attempt: attempt.copyWith(hintLevel: level),
    );
  }

  /// Marks that the student opened the full solution while the question was
  /// still open — a later correct answer then earns at the 0.5× tier.
  void markSolutionViewed() {
    final attempt = state.attempt;
    if (attempt == null || attempt.viewedSolution) return;
    if (state.phase != PracticePhase.answering &&
        state.phase != PracticePhase.retry) {
      return;
    }
    state = PracticeSessionState(
      phase: state.phase,
      session: state.session,
      attempt: attempt.copyWith(viewedSolution: true),
    );
  }

  /// Finalizes the current question as INCORRECT and reveals it — the
  /// "show me the solution and move on" path out of [PracticePhase.retry].
  void giveUp() {
    final session = state.session;
    if (session == null || state.phase != PracticePhase.retry) return;
    final attempt = state.attempt ?? _freshAttempt();
    final answer = PracticeAnswer(
      questionId: session.currentQuestion.id,
      submitted: attempt.lastSubmitted ?? '',
      isCorrect: false,
      xpEarned: 0,
      attempts: attempt.attempts,
      hintLevelUsed: attempt.hintLevel,
      viewedSolution: attempt.viewedSolution,
      timeSpentSeconds: _elapsedSeconds(attempt),
    );
    state = PracticeSessionState(
      phase: PracticePhase.revealed,
      session: session.recordAnswer(answer),
      lastAnswer: answer,
      attempt: attempt,
    );
  }

  /// Advances to the next question, or finishes the session (recording it).
  void next() {
    final session = state.session;
    if (session == null || state.phase != PracticePhase.revealed) return;

    if (session.isLastQuestion) {
      final result = ref
          .read(practiceProgressControllerProvider.notifier)
          .recordSession(session, now: _now());
      final analytics = ref.read(analyticsServiceProvider);
      unawaited(analytics.logEvent(AnalyticsEvent.practiceCompleted(
          correct: result.correct, total: result.total)));
      if (result.leveledUp) {
        unawaited(analytics.logEvent(AnalyticsEvent.masteryIncreased(
          topic: result.topic.name,
          level: result.masteryAfter.index,
        )));
      }
      if (session.request.isDailyChallenge) {
        unawaited(
            analytics.logEvent(AnalyticsEvent.dailyChallengeCompleted()));
      }
      // A session launched as a practice set's MIXED REVIEW reports back to the
      // set's journey (unlock progress toward the mastered state).
      final sourceKey = session.request.practiceSetSourceKey;
      if (sourceKey != null) {
        ref
            .read(practiceSetControllerProvider.notifier)
            .markMixedReviewCompleted(sourceKey);
      }
      state = PracticeSessionState(
        phase: PracticePhase.complete,
        session: session,
        result: result,
      );
    } else {
      final advanced = session.advance();
      state = PracticeSessionState(
        phase: PracticePhase.answering,
        session: advanced,
        attempt: _freshAttempt(),
      );
      // Momentum-based difficulty adaptation for the slot AFTER this one —
      // fire-and-forget, never blocks, failure keeps the original question.
      _maybeAdaptUpcoming(advanced);
    }
  }

  /// V5 mid-session adaptation: three first-try clean corrects in a row raise
  /// the next upcoming question a notch; two struggled finals lower it —
  /// always within ±1 of the learner's chosen centre and the tier ceiling.
  void _maybeAdaptUpcoming(PracticeSession session) {
    final upcomingIndex = session.currentIndex + 1;
    if (upcomingIndex >= session.questions.length) return;
    final upcoming = session.questions[upcomingIndex];
    final centre = session.request.difficulty ??
        ref.read(selectedPracticeDifficultyProvider) ??
        upcoming.difficulty;
    final shift = const SessionAdaptation().decide(
      answers: session.answers,
      current: upcoming.difficulty,
      centre: centre,
      isPro: ref.read(isProProvider),
    );
    if (shift == SessionShift.hold) return;
    final target = shift == SessionShift.raise
        ? upcoming.difficulty.harder
        : upcoming.difficulty.easier;
    if (target == null) return;
    unawaited(_swapUpcoming(upcomingIndex, upcoming, target));
  }

  Future<void> _swapUpcoming(
    int index,
    PracticeQuestion original,
    PracticeDifficulty target,
  ) async {
    try {
      final generated = await ref.read(practiceServiceProvider).generateOne(
            topic: original.topic,
            difficulty: target,
            skillId: original.skillId,
          );
      if (generated == null) return;
      final session = state.session;
      // Only swap while that slot still holds the question we planned to
      // replace — the student may have raced ahead or left the session.
      if (session == null ||
          index >= session.questions.length ||
          session.questions[index].id != original.id) {
        return;
      }
      unawaited(ref.read(analyticsServiceProvider).logEvent(
          AnalyticsEvent.practiceDifficultyAdapted(
              direction: target.index > original.difficulty.index
                  ? 'raise'
                  : 'lower')));
      state = PracticeSessionState(
        phase: state.phase,
        session: session.replaceUpcoming(index, generated),
        lastAnswer: state.lastAnswer,
        result: state.result,
        attempt: state.attempt,
      );
    } catch (_) {
      // Keep the original question — adaptation is best-effort by design.
    }
  }

  /// "Challenge Me" (V5): inserts one harder question on the same skill right
  /// after the one just solved, and moves onto it. Only offered on a correct,
  /// resolved answer.
  Future<ChallengeOutcome> challengeMe() async {
    final session = state.session;
    if (session == null ||
        state.phase != PracticePhase.revealed ||
        !state.lastWasCorrect) {
      return ChallengeOutcome.unavailable;
    }
    if (!ref.read(usageSnapshotProvider).canGeneratePractice) {
      return ChallengeOutcome.locked;
    }
    final question = session.currentQuestion;
    final target = const DifficultyEngine().clampToTier(
      question.difficulty.harder ?? question.difficulty,
      isPro: ref.read(isProProvider),
    );
    try {
      final generated = await ref.read(practiceServiceProvider).generateOne(
            topic: question.topic,
            difficulty: target,
            skillId: question.skillId,
          );
      if (generated == null) return ChallengeOutcome.unavailable;
      final current = state.session;
      if (current == null || state.phase != PracticePhase.revealed) {
        return ChallengeOutcome.unavailable;
      }
      ref.read(usageControllerProvider.notifier).recordPracticeGenerated(1);
      unawaited(ref.read(analyticsServiceProvider).logEvent(
          AnalyticsEvent.practiceChallengeAccepted(
              topic: question.topic.name)));
      state = PracticeSessionState(
        phase: PracticePhase.answering,
        session: current.insertNext(generated).advance(),
        attempt: _freshAttempt(),
      );
      return ChallengeOutcome.inserted;
    } catch (_) {
      return ChallengeOutcome.unavailable;
    }
  }

  /// Clears the session (leaving the flow).
  void reset() => state = const PracticeSessionState();
}
