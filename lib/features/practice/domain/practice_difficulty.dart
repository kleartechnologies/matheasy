/// Difficulty of a practice question, carrying its own XP and mastery weights.
///
/// This is the practice engine's canonical difficulty. Integration points (Home,
/// Result, Tutor) map their own difficulty labels onto it via [fromLabel], so
/// the engine stays self-contained.
enum PracticeDifficulty {
  easy('Easy', 10, 2),
  medium('Medium', 20, 3),
  hard('Hard', 40, 5);

  const PracticeDifficulty(this.label, this.baseXp, this.masteryPoints);

  final String label;

  /// XP awarded for a correct answer at this difficulty (spec: 10 / 20 / 40).
  final int baseXp;

  /// Mastery points a correct answer contributes toward a topic's 0–100 score.
  final int masteryPoints;

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
