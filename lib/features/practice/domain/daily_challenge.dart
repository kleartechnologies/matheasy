import 'dart:math';

import 'package:flutter/foundation.dart';

import 'practice_session.dart';
import 'practice_topic.dart';

/// Where today's challenge stands. Ordered by "how finished" so sync conflicts
/// can resolve by rank ([DailyChallengeStatus.index]).
enum DailyChallengeStatus {
  /// Generated but not yet opened today.
  notStarted,

  /// The learner opened today's session and is partway through.
  inProgress,

  /// All questions answered.
  completed,

  /// All questions answered, all correct.
  perfect;

  /// Whether the challenge is finished for the day (completed or perfect).
  /// A finished challenge stays finished until midnight — reopening the app
  /// must never reset or regenerate it.
  bool get isDone => index >= completed.index;

  static DailyChallengeStatus fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => DailyChallengeStatus.notStarted,
      );
}

/// One archived day — what topic ran and how it ended. Kept as a short rolling
/// window so topic rotation can avoid recent repeats and sync can union
/// histories across devices.
@immutable
class DailyChallengeRecord {
  const DailyChallengeRecord({
    required this.dayKey,
    required this.topicName,
    required this.statusName,
  });

  /// The challenge's calendar day (days since the Unix epoch, local calendar —
  /// see `PracticeProgress.epochDay`).
  final int dayKey;

  /// [PracticeTopic.name], stored as a string so an archived topic removed in a
  /// later version still round-trips.
  final String topicName;

  /// [DailyChallengeStatus.name], same forward-compatibility reasoning.
  final String statusName;

  PracticeTopic? get topic {
    for (final t in PracticeTopic.values) {
      if (t.name == topicName) return t;
    }
    return null;
  }

  DailyChallengeStatus get status => DailyChallengeStatus.fromName(statusName);
}

/// The learner's whole daily-challenge state: the per-install [salt], TODAY's
/// challenge spec `(dayKey, topic, seed)`, its live completion state, and the
/// recent-day archive.
///
/// The spec is the heart of the fix for "same challenge every day": the day's
/// questions are not cached, they are **re-derived** — `seed` feeds the
/// generation engine's `Random`, so the same spec always rebuilds the identical
/// question set (reopen the app: same challenge), while a new `dayKey` yields a
/// new seed and topic (new day: new challenge). No question codec needed.
@immutable
class DailyChallengeState {
  const DailyChallengeState({
    this.salt = 0,
    this.dayKey,
    this.topic,
    this.seed = 0,
    this.questionCount = defaultQuestionCount,
    this.status = DailyChallengeStatus.notStarted,
    this.answered = 0,
    this.correct = 0,
    this.completedAtMs,
    this.recent = const [],
  });

  static const int defaultQuestionCount = 5;

  /// Archive cap — enough for rotation windows and cross-device merges without
  /// unbounded growth.
  static const int maxRecent = 30;

  /// The pre-first-run state: no salt, no challenge yet.
  static const DailyChallengeState empty = DailyChallengeState();

  /// Per-user random salt, generated once (never 0 once set). It decorrelates
  /// users — everyone shares the same `dayKey`, so without a salt every learner
  /// worldwide would get the same topic and numbers each day.
  final int salt;

  /// Today's calendar day (days since epoch, local calendar), or `null` before
  /// the first challenge is planned.
  final int? dayKey;

  /// Today's topic, or `null` before the first challenge is planned.
  final PracticeTopic? topic;

  /// The deterministic generation seed for today's questions.
  final int seed;

  final int questionCount;
  final DailyChallengeStatus status;

  /// Questions resolved so far today (final outcomes only, capped at
  /// [questionCount]).
  final int answered;

  /// Of [answered], how many were correct.
  final int correct;

  /// When today's challenge was completed (epoch ms), or `null`.
  final int? completedAtMs;

  /// Archived recent days, newest first.
  final List<DailyChallengeRecord> recent;

  /// Whether a concrete challenge has been planned (post-first-run).
  bool get hasChallenge => dayKey != null && topic != null;

  /// The launchable request for today's challenge, or `null` before planning.
  /// Carrying [seed] is what makes every rebuild of the session identical.
  PracticeRequest? get request => !hasChallenge
      ? null
      : PracticeRequest.dailyChallenge(
          topic: topic!,
          seed: seed,
          questionCount: questionCount,
        );

  DailyChallengeState copyWith({
    int? salt,
    DailyChallengeStatus? status,
    int? answered,
    int? correct,
    int? completedAtMs,
    List<DailyChallengeRecord>? recent,
  }) {
    return DailyChallengeState(
      salt: salt ?? this.salt,
      dayKey: dayKey,
      topic: topic,
      seed: seed,
      questionCount: questionCount,
      status: status ?? this.status,
      answered: answered ?? this.answered,
      correct: correct ?? this.correct,
      completedAtMs: completedAtMs ?? this.completedAtMs,
      recent: recent ?? this.recent,
    );
  }
}

/// Pure planning logic: rolls the state over to a new day — archives the old
/// challenge, picks the new topic (seeded, weighted, avoiding recent repeats)
/// and derives the new generation seed. No providers, no clock: everything is
/// injected, so it's deterministic and directly unit-testable.
class DailyChallengePlanner {
  const DailyChallengePlanner._();

  /// How many most-recent topics to exclude when picking today's (bounded by
  /// the candidate pool so a small pool can still rotate).
  static const int _avoidWindow = 3;

  /// Plans the challenge for [dayKey].
  ///
  /// [candidates] must be non-empty: the tier/level-appropriate topics for this
  /// learner. [weights] biases the pick (weak topics up, mastered topics down);
  /// missing topics default to 1.0. [salt] must be non-zero.
  static DailyChallengeState rollover(
    DailyChallengeState previous, {
    required int dayKey,
    required int salt,
    required List<PracticeTopic> candidates,
    Map<PracticeTopic, double> weights = const {},
  }) {
    assert(salt != 0, 'salt must be generated before planning');
    assert(candidates.isNotEmpty, 'candidates must not be empty');

    // Archive the outgoing challenge (if any) before planning the new one.
    var archive = previous.recent;
    if (previous.hasChallenge) {
      archive = [
        DailyChallengeRecord(
          dayKey: previous.dayKey!,
          topicName: previous.topic!.name,
          statusName: previous.status.name,
        ),
        ...previous.recent.where((r) => r.dayKey != previous.dayKey),
      ];
      if (archive.length > DailyChallengeState.maxRecent) {
        archive = archive.sublist(0, DailyChallengeState.maxRecent);
      }
    }

    final topic = _pickTopic(
      salt: salt,
      dayKey: dayKey,
      candidates: candidates,
      archive: archive,
      weights: weights,
    );

    return DailyChallengeState(
      salt: salt,
      dayKey: dayKey,
      topic: topic,
      seed: mix(salt, dayKey, topic.index + 1),
      recent: archive,
    );
  }

  static PracticeTopic _pickTopic({
    required int salt,
    required int dayKey,
    required List<PracticeTopic> candidates,
    required List<DailyChallengeRecord> archive,
    required Map<PracticeTopic, double> weights,
  }) {
    // Exclude the last few days' topics — structurally guarantees today's
    // differs from yesterday's whenever the pool allows it.
    final window = min(_avoidWindow, candidates.length - 1);
    final avoid = <PracticeTopic>{};
    for (final record in archive) {
      if (avoid.length >= window) break;
      final topic = record.topic;
      if (topic != null) avoid.add(topic);
    }
    var pool = candidates.where((t) => !avoid.contains(t)).toList();
    if (pool.isEmpty) {
      // The pool shrank below the avoid window (e.g. tier change) — fall back
      // to only avoiding the single most recent topic, then to everything.
      final lastTopic = archive.isEmpty ? null : archive.first.topic;
      pool = candidates.where((t) => t != lastTopic).toList();
      if (pool.isEmpty) pool = candidates;
    }

    // Seeded weighted pick: deterministic for (salt, dayKey), so replanning the
    // same day always lands on the same topic.
    final random = Random(mix(salt, dayKey));
    var total = 0.0;
    for (final topic in pool) {
      total += weights[topic] ?? 1.0;
    }
    var roll = random.nextDouble() * total;
    for (final topic in pool) {
      roll -= weights[topic] ?? 1.0;
      if (roll < 0) return topic;
    }
    return pool.last;
  }

  /// A small deterministic 32-bit hash mix — spreads `(salt, dayKey, topic)`
  /// into well-distributed positive seeds. Stable across platforms (masked to
  /// 32 bits, so web/VM agree).
  static int mix(int a, int b, [int c = 0]) {
    var h = 0x9E3779B9;
    for (final v in [a, b, c]) {
      h ^= v & 0xFFFFFFFF;
      h = (h * 0x85EBCA6B) & 0xFFFFFFFF;
      h ^= h >>> 13;
    }
    h = (h * 0xC2B2AE35) & 0xFFFFFFFF;
    h ^= h >>> 16;
    return h & 0x7FFFFFFF;
  }
}
