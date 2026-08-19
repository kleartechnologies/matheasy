import 'package:flutter/foundation.dart';

import 'practice_difficulty.dart';

/// An XP award — a [base] amount (from question difficulty) plus an optional
/// [bonus] (e.g. the daily-challenge bonus).
@immutable
class XpReward {
  const XpReward({required this.base, this.bonus = 0});

  final int base;
  final int bonus;

  int get total => base + bonus;

  /// Bonus XP granted for completing the daily challenge (spec: +100 XP).
  static const int dailyChallengeBonus = 100;

  /// Bonus XP for finishing a whole practice set (every question answered).
  static const int setCompletionBonus = 25;

  /// The XP a correct answer at [difficulty] earns.
  static int forCorrect(PracticeDifficulty difficulty) => difficulty.baseXp;

  /// V5 "XP for learning": a correct answer still earns at every assistance
  /// level, scaled by how independently the student got there —
  /// 1.0× first-try clean, 0.7× after a hint or a retry, 0.5× after seeing
  /// the solution (or riding the hint ladder all the way to it).
  static double multiplierFor({
    required int attempts,
    required int hintLevelUsed,
    required bool viewedSolution,
  }) {
    if (viewedSolution || hintLevelUsed >= 4) return 0.5;
    if (hintLevelUsed >= 1 || attempts > 1) return 0.7;
    return 1.0;
  }

  /// The XP a CORRECT final answer earns, given the journey behind it.
  static int forOutcome(
    PracticeDifficulty difficulty, {
    required int attempts,
    required int hintLevelUsed,
    required bool viewedSolution,
  }) =>
      (difficulty.baseXp *
              multiplierFor(
                attempts: attempts,
                hintLevelUsed: hintLevelUsed,
                viewedSolution: viewedSolution,
              ))
          .round();
}
