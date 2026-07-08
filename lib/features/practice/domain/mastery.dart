/// A learner's mastery of a topic, derived from a 0–100 mastery score.
///
/// Local-only for now; the same model backs a future cloud-synced version.
enum MasteryLevel {
  beginner('Beginner', 0),
  developing('Developing', 30),
  proficient('Proficient', 70),
  mastered('Mastered', 100);

  const MasteryLevel(this.label, this.threshold);

  final String label;

  /// Minimum mastery score (0–100) to be at this level.
  final int threshold;

  /// The highest level whose [threshold] the [points] score has reached.
  static MasteryLevel forPoints(int points) {
    final clamped = points.clamp(0, 100);
    var level = MasteryLevel.beginner;
    for (final candidate in MasteryLevel.values) {
      if (clamped >= candidate.threshold) level = candidate;
    }
    return level;
  }

  /// The next level up, or `null` if already [mastered].
  MasteryLevel? get next {
    final i = index;
    return i + 1 < MasteryLevel.values.length
        ? MasteryLevel.values[i + 1]
        : null;
  }

  /// Progress (0–1) from this level toward the [next] one for a [points] score.
  double progressToNext(int points) {
    final upper = next;
    if (upper == null) return 1;
    final span = upper.threshold - threshold;
    if (span <= 0) return 1;
    return ((points.clamp(0, 100) - threshold) / span).clamp(0.0, 1.0);
  }
}
