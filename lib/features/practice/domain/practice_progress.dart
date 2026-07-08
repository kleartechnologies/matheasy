import 'package:flutter/foundation.dart';

import 'mastery.dart';
import 'practice_session.dart';
import 'practice_topic.dart';
import 'xp_level.dart';

/// Per-topic mastery + accuracy stats.
@immutable
class TopicProgress {
  const TopicProgress({
    required this.topic,
    this.masteryPoints = 0,
    this.answered = 0,
    this.correct = 0,
  });

  final PracticeTopic topic;

  /// 0–100 mastery score.
  final int masteryPoints;
  final int answered;
  final int correct;

  MasteryLevel get level => MasteryLevel.forPoints(masteryPoints);
  double get levelProgress => level.progressToNext(masteryPoints);
  double get accuracy => answered == 0 ? 0 : correct / answered;

  TopicProgress copyWith({int? masteryPoints, int? answered, int? correct}) {
    return TopicProgress(
      topic: topic,
      masteryPoints: masteryPoints ?? this.masteryPoints,
      answered: answered ?? this.answered,
      correct: correct ?? this.correct,
    );
  }
}

/// The learner's whole practice state — persisted locally (see
/// `PracticeRepository`), cloud-synced in a later stage. Pure/immutable: the
/// repository owns (de)serialization so the domain has no storage dependency.
@immutable
class PracticeProgress {
  const PracticeProgress({
    this.totalXp = 0,
    this.streakCurrent = 0,
    this.streakBest = 0,
    this.lastPracticedEpochDay,
    this.lastDailyChallengeEpochDay,
    this.topics = const {},
    this.lastRequest,
  });

  static const PracticeProgress empty = PracticeProgress();

  final int totalXp;
  final int streakCurrent;
  final int streakBest;

  /// Day of the last practice (days since the Unix epoch), for streak math.
  final int? lastPracticedEpochDay;

  /// Day the daily-challenge bonus was last awarded, so it's granted at most
  /// once per calendar day.
  final int? lastDailyChallengeEpochDay;

  final Map<PracticeTopic, TopicProgress> topics;

  /// The last session's request, powering "Continue practice".
  final PracticeRequest? lastRequest;

  XpLevel get xpLevel => XpLevel.fromTotalXp(totalXp);

  /// Progress for [topic], defaulting to a fresh (Beginner) entry.
  TopicProgress topic(PracticeTopic topic) =>
      topics[topic] ?? TopicProgress(topic: topic);

  bool get hasHistory => totalXp > 0 || topics.isNotEmpty;

  PracticeProgress copyWith({
    int? totalXp,
    int? streakCurrent,
    int? streakBest,
    int? lastPracticedEpochDay,
    int? lastDailyChallengeEpochDay,
    Map<PracticeTopic, TopicProgress>? topics,
    PracticeRequest? lastRequest,
  }) {
    return PracticeProgress(
      totalXp: totalXp ?? this.totalXp,
      streakCurrent: streakCurrent ?? this.streakCurrent,
      streakBest: streakBest ?? this.streakBest,
      lastPracticedEpochDay:
          lastPracticedEpochDay ?? this.lastPracticedEpochDay,
      lastDailyChallengeEpochDay:
          lastDailyChallengeEpochDay ?? this.lastDailyChallengeEpochDay,
      topics: topics ?? this.topics,
      lastRequest: lastRequest ?? this.lastRequest,
    );
  }
}
