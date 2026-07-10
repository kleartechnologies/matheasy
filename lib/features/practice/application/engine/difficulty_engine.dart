import '../../domain/mastery.dart';
import '../../domain/practice_difficulty.dart';
import '../../domain/skill_mastery.dart';

/// Chooses the difficulty of the next question from a learner's per-skill
/// mastery — the "adaptive difficulty" half of the engine.
///
/// Two ideas combine:
///  * a *centre* difficulty from the skill's mastery level (beginner→easy …
///    mastered→expert), and
///  * a gentle *within-session ramp* so a set opens a notch easier and closes a
///    notch harder rather than being monotone.
///
/// The free tier is always clamped to [PracticeDifficulty.hard] — [expert] is
/// Pro-only.
class DifficultyEngine {
  const DifficultyEngine();

  /// The hardest difficulty a tier may see.
  PracticeDifficulty ceilingFor({required bool isPro}) =>
      isPro ? PracticeDifficulty.expert : PracticeDifficulty.hard;

  /// The centre difficulty implied by [mastery] (before any session ramp).
  PracticeDifficulty centreFor(SkillMastery mastery, {required bool isPro}) {
    if (!mastery.hasHistory) return PracticeDifficulty.easy; // cold start easy
    final base = switch (mastery.level) {
      MasteryLevel.beginner => PracticeDifficulty.easy,
      MasteryLevel.developing => PracticeDifficulty.medium,
      MasteryLevel.proficient => PracticeDifficulty.hard,
      MasteryLevel.mastered =>
        isPro ? PracticeDifficulty.expert : PracticeDifficulty.hard,
    };
    // A recently-shaky skill (low accuracy despite some mastery) is eased back
    // one notch so the learner rebuilds confidence.
    if (mastery.attempts >= 3 && mastery.accuracy < 0.5) {
      return base.easier ?? base;
    }
    return base;
  }

  /// The adaptive target for question [slotIndex] of [slots], for [mastery].
  PracticeDifficulty targetFor({
    required SkillMastery mastery,
    required bool isPro,
    required int slotIndex,
    required int slots,
  }) {
    var index = centreFor(mastery, isPro: isPro).index;
    if (slots > 1) {
      final position = slotIndex / (slots - 1); // 0..1 across the session
      if (position < 0.34) {
        index -= 1;
      } else if (position > 0.66) {
        index += 1;
      }
    }
    final ceiling = ceilingFor(isPro: isPro).index;
    return PracticeDifficulty.values[index.clamp(0, ceiling)];
  }

  /// Clamps a caller-chosen [difficulty] to what the tier is allowed to see.
  PracticeDifficulty clampToTier(
    PracticeDifficulty difficulty, {
    required bool isPro,
  }) {
    final ceiling = ceilingFor(isPro: isPro).index;
    return PracticeDifficulty.values[difficulty.index.clamp(0, ceiling)];
  }
}
