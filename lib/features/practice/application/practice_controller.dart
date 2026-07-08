import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/haptics_service.dart';
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
  Future<void> start(PracticeRequest request) async {
    state = const PracticeSessionState(phase: PracticePhase.loading);
    try {
      final session =
          await ref.read(practiceServiceProvider).createSession(request);
      state = session.questions.isEmpty
          ? const PracticeSessionState(phase: PracticePhase.error)
          : PracticeSessionState(
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
