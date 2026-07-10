import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/monitoring/logging_service.dart';
import '../../../core/security/rate_limit_result.dart';
import '../../../core/security/rate_limit_service.dart';
import '../../../core/services/haptics_service.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../subscription/application/usage_controller.dart';
import '../domain/practice_mistake.dart';
import '../domain/practice_result.dart';
import '../domain/practice_session.dart';
import 'practice_progress_controller.dart';
import 'practice_service.dart';

part 'practice_controller.g.dart';

/// The lifecycle of a practice session.
enum PracticePhase {
  /// Nothing started yet.
  idle,

  /// Building the session.
  loading,

  /// Awaiting the current question's answer.
  answering,

  /// The current answer has been graded — showing feedback + explanation.
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
  });

  final PracticePhase phase;
  final PracticeSession? session;

  /// The answer just submitted (drives the feedback panel while [revealed]).
  final PracticeAnswer? lastAnswer;

  /// The final result once [complete].
  final PracticeResult? result;

  bool get isLoading => phase == PracticePhase.loading;
  bool get isAnswering => phase == PracticePhase.answering;
  bool get isRevealed => phase == PracticePhase.revealed;
  bool get isComplete => phase == PracticePhase.complete;
  bool get lastWasCorrect => lastAnswer?.isCorrect ?? false;

  /// The mistake just revealed (for the Matheasy "why is this wrong?" and Visual
  /// walkthrough hand-offs) — `null` unless the last answer was incorrect.
  PracticeMistake? get mistake {
    final answer = lastAnswer;
    final current = session;
    if (answer == null || current == null || answer.isCorrect) return null;
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
  Future<void> start(PracticeRequest request) async {
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
      // Adaptive, weakness-targeted sessions are a Pro capability — track uptake.
      if (request.adaptive && ref.read(isProProvider)) {
        unawaited(analytics.logEvent(
            AnalyticsEvent.adaptiveRecommendationUsed(topic: request.topic.name)));
      }
      state = PracticeSessionState(
        phase: PracticePhase.answering,
        session: session,
      );
    } catch (_) {
      state = const PracticeSessionState(phase: PracticePhase.error);
    }
  }

  /// Grades a submitted answer (an option's text, or typed input) and reveals
  /// feedback. Ignored unless a question is currently awaiting an answer.
  void submit(String submitted) {
    final session = state.session;
    if (session == null || state.phase != PracticePhase.answering) return;

    final question = session.currentQuestion;
    final isCorrect = question.evaluate(submitted);
    isCorrect ? HapticsService.success() : HapticsService.warning();

    final answer = PracticeAnswer(
      questionId: question.id,
      submitted: submitted,
      isCorrect: isCorrect,
      xpEarned: isCorrect ? question.xpReward : 0,
    );

    final analytics = ref.read(analyticsServiceProvider);
    unawaited(analytics.logEvent(isCorrect
        ? AnalyticsEvent.questionCorrect(
            topic: question.topic.name, difficulty: question.difficulty.name)
        : AnalyticsEvent.questionIncorrect(
            topic: question.topic.name, difficulty: question.difficulty.name)));

    state = PracticeSessionState(
      phase: PracticePhase.revealed,
      session: session.recordAnswer(answer),
      lastAnswer: answer,
    );
  }

  /// Advances to the next question, or finishes the session (recording it).
  void next() {
    final session = state.session;
    if (session == null || state.phase != PracticePhase.revealed) return;

    if (session.isLastQuestion) {
      final result = ref
          .read(practiceProgressControllerProvider.notifier)
          .recordSession(session, now: DateTime.now());
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
      state = PracticeSessionState(
        phase: PracticePhase.complete,
        session: session,
        result: result,
      );
    } else {
      state = PracticeSessionState(
        phase: PracticePhase.answering,
        session: session.advance(),
      );
    }
  }

  /// Clears the session (leaving the flow).
  void reset() => state = const PracticeSessionState();
}
