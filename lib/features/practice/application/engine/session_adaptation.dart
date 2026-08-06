import '../../domain/practice_difficulty.dart';
import '../../domain/practice_session.dart';
import 'difficulty_engine.dart';

/// What the mid-session adaptation decided for the next upcoming slot.
enum SessionShift { raise, lower, hold }

/// The V5 mid-session difficulty adaptation — pure and clock-free.
///
/// The learner's Settings difficulty stays the CENTRE (the session starts
/// there and serving never drifts more than one notch either side of it);
/// within a session, momentum moves the next question:
///
/// * **raise** — the last 3 final answers were all first-try clean corrects,
///   and one notch up stays within centre+1 and the tier ceiling (free tops
///   out at medium, exactly as everywhere else).
/// * **lower** — the last 2 final answers were both struggles (incorrect, or
///   needing hint level ≥ 2), and one notch down stays within centre−1.
///   Lower difficulty is the "simpler numbers" of the spec; more hints and
///   guided help are already on every question.
/// * **hold** — anything else.
class SessionAdaptation {
  const SessionAdaptation({this.difficulty = const DifficultyEngine()});

  final DifficultyEngine difficulty;

  /// Consecutive first-try clean corrects needed to raise.
  static const int raiseStreak = 3;

  /// Consecutive struggled finals needed to lower.
  static const int lowerStreak = 2;

  /// Serving never drifts further than this from the chosen centre.
  static const int maxDrift = 1;

  SessionShift decide({
    required List<PracticeAnswer> answers,
    required PracticeDifficulty current,
    required PracticeDifficulty centre,
    required bool isPro,
  }) {
    if (_streak(answers, raiseStreak, (a) => a.isCorrect && a.isFirstTryClean)) {
      final raised = current.harder;
      if (raised != null &&
          raised.index <= centre.index + maxDrift &&
          difficulty.clampToTier(raised, isPro: isPro) == raised) {
        return SessionShift.raise;
      }
    }
    if (_streak(answers, lowerStreak, _struggled)) {
      final lowered = current.easier;
      if (lowered != null && lowered.index >= centre.index - maxDrift) {
        return SessionShift.lower;
      }
    }
    return SessionShift.hold;
  }

  static bool _struggled(PracticeAnswer a) => !a.isCorrect || a.hintLevelUsed >= 2;

  /// Whether the trailing [count] answers all satisfy [test].
  static bool _streak(
    List<PracticeAnswer> answers,
    int count,
    bool Function(PracticeAnswer) test,
  ) {
    if (answers.length < count) return false;
    for (var i = answers.length - count; i < answers.length; i++) {
      if (!test(answers[i])) return false;
    }
    return true;
  }
}
