import 'package:flutter/foundation.dart';

import 'mastery.dart';
import 'practice_session.dart';
import 'practice_skill.dart';
import 'practice_topic.dart';
import 'skill_mastery.dart';
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
    this.sessionsCompleted = 0,
    this.dailyChallengesCompleted = 0,
    this.lastPracticedEpochDay,
    this.lastDailyChallengeEpochDay,
    this.topics = const {},
    this.skills = const {},
    this.lastRequest,
  });

  static const PracticeProgress empty = PracticeProgress();

  /// The calendar day [dt] falls on, as days since the Unix epoch — the unit
  /// every `*EpochDay` field below is stored in.
  ///
  /// Anchored to a UTC calendar date so no timezone offset enters the division;
  /// otherwise DST transitions in GMT-crossing zones make consecutive days
  /// differ by 0 or 2 epoch-days and corrupt the streak.
  static int epochDay(DateTime dt) =>
      DateTime.utc(dt.year, dt.month, dt.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;

  final int totalXp;
  final int streakCurrent;
  final int streakBest;

  /// Total practice sessions finished (for achievements + stats).
  final int sessionsCompleted;

  /// Total daily challenges finished.
  final int dailyChallengesCompleted;

  /// Day of the last practice (days since the Unix epoch), for streak math.
  final int? lastPracticedEpochDay;

  /// Day the daily-challenge bonus was last awarded, so it's granted at most
  /// once per calendar day.
  final int? lastDailyChallengeEpochDay;

  final Map<PracticeTopic, TopicProgress> topics;

  /// Per-skill mastery, keyed by [PracticeSkill.id] — the fine-grained adaptive
  /// signal (Stage 15). Empty for pre-Stage-15 progress; populated as the
  /// engine records skill-tagged answers.
  final Map<String, SkillMastery> skills;

  /// The last session's request, powering "Continue practice".
  final PracticeRequest? lastRequest;

  XpLevel get xpLevel => XpLevel.fromTotalXp(totalXp);

  /// Progress for [topic], defaulting to a fresh (Beginner) entry.
  TopicProgress topic(PracticeTopic topic) =>
      topics[topic] ?? TopicProgress(topic: topic);

  /// Mastery for [skill], defaulting to a fresh (unattempted) entry.
  SkillMastery skill(PracticeSkill skill) =>
      skills[skill.id] ?? SkillMastery(skillId: skill.id);

  bool get hasHistory => totalXp > 0 || topics.isNotEmpty;

  PracticeProgress copyWith({
    int? totalXp,
    int? streakCurrent,
    int? streakBest,
    int? sessionsCompleted,
    int? dailyChallengesCompleted,
    int? lastPracticedEpochDay,
    int? lastDailyChallengeEpochDay,
    Map<PracticeTopic, TopicProgress>? topics,
    Map<String, SkillMastery>? skills,
    PracticeRequest? lastRequest,
  }) {
    return PracticeProgress(
      totalXp: totalXp ?? this.totalXp,
      streakCurrent: streakCurrent ?? this.streakCurrent,
      streakBest: streakBest ?? this.streakBest,
      sessionsCompleted: sessionsCompleted ?? this.sessionsCompleted,
      dailyChallengesCompleted:
          dailyChallengesCompleted ?? this.dailyChallengesCompleted,
      lastPracticedEpochDay:
          lastPracticedEpochDay ?? this.lastPracticedEpochDay,
      lastDailyChallengeEpochDay:
          lastDailyChallengeEpochDay ?? this.lastDailyChallengeEpochDay,
      topics: topics ?? this.topics,
      skills: skills ?? this.skills,
      lastRequest: lastRequest ?? this.lastRequest,
    );
  }
}
