import 'package:flutter/foundation.dart';

import 'question_fingerprint.dart';

/// The rolling record of recently-generated questions, powering anti-repetition.
///
/// Holds the most recent [QuestionFingerprint.value]s (newest last), capped at
/// [maxEntries] so it never grows unbounded. The engine consults it before
/// accepting a freshly-generated question and appends the accepted ones.
///
/// Immutable + storage-agnostic: `PracticeHistoryStore` owns (de)serialization,
/// mirroring the `PracticeRepository` pattern.
@immutable
class PracticeHistory {
  const PracticeHistory({this.recent = const []});

  static const PracticeHistory empty = PracticeHistory();

  /// How many fingerprints to remember. Large enough to make repeats rare
  /// across many sessions, small enough to stay cheap to persist.
  static const int maxEntries = 300;

  /// Fingerprint values, oldest first / newest last.
  final List<String> recent;

  bool get isEmpty => recent.isEmpty;

  /// Whether an identical question (same skill + parameters) was generated
  /// recently.
  bool containsExact(QuestionFingerprint fingerprint) =>
      recent.contains(fingerprint.value);

  /// A new history with [fingerprints] appended, trimmed to [maxEntries].
  PracticeHistory withAll(Iterable<QuestionFingerprint> fingerprints) {
    if (fingerprints.isEmpty) return this;
    final next = [...recent, for (final f in fingerprints) f.value];
    final trimmed = next.length <= maxEntries
        ? next
        : next.sublist(next.length - maxEntries);
    return PracticeHistory(recent: trimmed);
  }

  @override
  bool operator ==(Object other) =>
      other is PracticeHistory && listEquals(other.recent, recent);

  @override
  int get hashCode => Object.hashAll(recent);
}
