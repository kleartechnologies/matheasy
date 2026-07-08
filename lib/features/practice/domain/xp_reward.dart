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

  /// The XP a correct answer at [difficulty] earns.
  static int forCorrect(PracticeDifficulty difficulty) => difficulty.baseXp;
}
