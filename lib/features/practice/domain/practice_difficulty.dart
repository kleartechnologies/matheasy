import 'difficulty_spec.dart';

/// Difficulty of a practice question, carrying its own XP + mastery weights and
/// the strict [DifficultySpec] that deterministically controls generation.
///
/// This is the practice engine's canonical difficulty. Integration points (Home,
/// Result, Tutor) map their own difficulty labels onto it via [fromLabel], so
/// the engine stays self-contained.
///
/// Five levels, primary → university. Difficulty is the USER's choice and is held
/// CONSTANT for a whole session — the engine never derives it from mastery once
/// the user has picked one, and adaptive only reorders topics, never difficulty.
///
/// Monetization: [hard] and [expert] are Pro-exclusive ([isPro]); the free tier
/// tops out at [medium].
enum PracticeDifficulty {
  veryEasy('Very Easy', 5, 1, kVeryEasySpec),
  easy('Easy', 10, 2, kEasySpec),
  medium('Medium', 20, 3, kMediumSpec),
  hard('Hard', 40, 5, kHardSpec),
  expert('Expert', 75, 7, kExpertSpec);

  const PracticeDifficulty(
    this.label,
    this.baseXp,
    this.masteryPoints,
    this.spec,
  );

  final String label;

  /// XP awarded for a correct answer at this difficulty (5 / 10 / 20 / 40 / 75).
  final int baseXp;

  /// Mastery points a correct answer contributes toward a topic's 0–100 score.
  final int masteryPoints;

  /// The strict generation rules for this level (ranges, steps, concepts, grade).
  final DifficultySpec spec;

  /// Whether this difficulty is Pro-exclusive. Free tops out at [medium];
  /// [hard] (A-Level) and [expert] (university) are Pro.
  bool get isPro => index >= PracticeDifficulty.hard.index;

  /// The next difficulty up, or `null` if already the hardest.
  PracticeDifficulty? get harder {
    final i = index;
    return i + 1 < values.length ? values[i + 1] : null;
  }

  /// The next difficulty down, or `null` if already the easiest.
  PracticeDifficulty? get easier => index > 0 ? values[index - 1] : null;

  /// The harder of two difficulties (by [index]).
  PracticeDifficulty atLeast(PracticeDifficulty floor) =>
      index >= floor.index ? this : floor;

  /// Maps a human difficulty label (from Home / Result / Tutor) onto the engine
  /// difficulty, defaulting to [medium] for anything unrecognized.
  static PracticeDifficulty fromLabel(String label) {
    final normalized = label.trim().toLowerCase();
    return values.firstWhere(
      (d) => d.label.toLowerCase() == normalized,
      orElse: () => PracticeDifficulty.medium,
    );
  }
}
