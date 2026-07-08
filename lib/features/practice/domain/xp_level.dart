import 'package:flutter/foundation.dart';

/// The learner's XP level, derived from their cumulative XP.
///
/// Uses a gently increasing curve so early levels come quickly and later ones
/// take longer (level `n` → `n+1` costs `100 + (n-1)·50` XP).
@immutable
class XpLevel {
  const XpLevel({
    required this.level,
    required this.totalXp,
    required this.xpIntoLevel,
    required this.xpForLevel,
  });

  /// 1-based level number.
  final int level;

  /// Total cumulative XP earned.
  final int totalXp;

  /// XP earned within the current level.
  final int xpIntoLevel;

  /// XP required to advance from the current level to the next.
  final int xpForLevel;

  /// Fraction (0–1) toward the next level.
  double get progress => xpForLevel == 0 ? 0 : xpIntoLevel / xpForLevel;

  int get xpToNext => (xpForLevel - xpIntoLevel).clamp(0, xpForLevel);

  /// XP needed to advance out of [level] (level → level + 1).
  static int costForLevel(int level) => 100 + (level - 1) * 50;

  factory XpLevel.fromTotalXp(int totalXp) {
    var level = 1;
    var remaining = totalXp < 0 ? 0 : totalXp;
    var cost = costForLevel(level);
    while (remaining >= cost) {
      remaining -= cost;
      level++;
      cost = costForLevel(level);
    }
    return XpLevel(
      level: level,
      totalXp: totalXp < 0 ? 0 : totalXp,
      xpIntoLevel: remaining,
      xpForLevel: cost,
    );
  }
}
