/// Difficulty of a practice question, carrying its own XP and mastery weights.
///
/// This is the practice engine's canonical difficulty. Integration points (Home,
/// Result, Tutor) map their own difficulty labels onto it via [fromLabel], so
/// the engine stays self-contained.
///
/// [expert] is the Stage 15 advanced tier — Pro-only (the free tier never
/// generates it) and reserved for harder, multi-step and AI-generated content.
enum PracticeDifficulty {
  easy('Easy', 10, 2),
  medium('Medium', 20, 3),
  hard('Hard', 40, 5),
  expert('Expert', 75, 7);

  const PracticeDifficulty(this.label, this.baseXp, this.masteryPoints);

  final String label;

  /// XP awarded for a correct answer at this difficulty (spec: 10 / 20 / 40 /
  /// 75).
  final int baseXp;

  /// Mastery points a correct answer contributes toward a topic's 0–100 score.
  final int masteryPoints;

  /// Whether this difficulty is a Pro-exclusive advanced level.
  bool get isPro => this == PracticeDifficulty.expert;

  /// The next difficulty up, or `null` if already the hardest.
  PracticeDifficulty? get harder {
    final i = index;
    return i + 1 < values.length ? values[i + 1] : null;
  }

  /// The next difficulty down, or `null` if already the easiest.
  PracticeDifficulty? get easier => index > 0 ? values[index - 1] : null;

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
