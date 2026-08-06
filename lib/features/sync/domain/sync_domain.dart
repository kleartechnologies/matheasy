/// The independent data domains synced to the cloud, one Firestore document
/// each. Kept as small, separate documents (per the "keep documents small"
/// rule) so a write to one never rewrites the others.
///
/// Each domain maps 1:1 to an existing local repository / prefs key; the sync
/// layer moves the already-serialized JSON for that key, so it needs no
/// per-model codecs.
enum SyncDomain {
  /// Editable profile — display-name override + avatar.
  profile('profile'),

  /// App settings — theme, notifications, accessibility, learning preferences.
  settings('settings'),

  /// Practice progress — XP, streak, per-topic mastery, last session.
  progress('progress'),

  /// Unlocked achievements (id → unlock date).
  achievements('achievements'),

  /// Free-tier usage counters (scans / AI tutor / practice).
  usage('usage'),

  /// Learning analytics — scan/tutor counts, learning days, activity feed.
  analytics('analytics'),

  /// Solved-problem history — the cache of past solutions (LaTeX + solution
  /// JSON, never images) that re-opens instantly, offline and free.
  history('history'),

  /// Practice sets — the easier/similar/harder(/challenge) problems generated
  /// from each solved problem, with the learner's completion state.
  practiceSets('practiceSets'),

  /// Daily challenge — today's `(dayKey, topic, seed)` plan, its completion
  /// status and the recent-day archive, so the same challenge (and its
  /// done-state) follows the learner across devices.
  dailyChallenge('dailyChallenge');

  const SyncDomain(this.docId);

  /// The Firestore document id under `users/{uid}/state/{docId}`.
  final String docId;

  static SyncDomain? fromDocId(String id) {
    for (final domain in SyncDomain.values) {
      if (domain.docId == id) return domain;
    }
    return null;
  }
}
