import 'package:flutter/foundation.dart';

import 'adaptive_recommendation.dart';
import 'mastery.dart';
import 'practice_session.dart';
import 'practice_topic.dart';

/// The outcome shown on the session-complete screen.
///
/// EPHEMERAL by design: rendered once at session end, never serialized or
/// synced (the durable aggregates live in `PracticeProgress`). A synced
/// session-history domain is a documented follow-up, not part of V5.
@immutable
class PracticeResult {
  const PracticeResult({
    required this.request,
    required this.total,
    required this.correct,
    required this.xpEarned,
    required this.masteryBefore,
    required this.masteryAfter,
    required this.masteryPointsAfter,
    this.timeSpentSeconds = 0,
    this.hintsUsedTotal = 0,
    this.strongSkills = const [],
    this.weakSkills = const [],
    this.recommendedNext,
  });

  final PracticeRequest request;
  final int total;
  final int correct;

  /// Total XP earned this session (per-question XP + any daily-challenge bonus).
  final int xpEarned;

  final MasteryLevel masteryBefore;
  final MasteryLevel masteryAfter;

  /// The topic's 0–100 mastery score after this session.
  final int masteryPointsAfter;

  /// Wall-clock seconds spent answering, summed across the session's answers.
  final int timeSpentSeconds;

  /// Hint rungs taken across the whole session (a level-3 answer counts 3).
  final int hintsUsedTotal;

  /// Skill labels the student nailed this session (accuracy ≥ 0.8).
  final List<String> strongSkills;

  /// Skill labels to review (accuracy < 0.5) — the "concepts to review" list.
  final List<String> weakSkills;

  /// The engine's "practice this next" (Pro; null without signal).
  final AdaptiveRecommendation? recommendedNext;

  PracticeTopic get topic => request.topic;

  double get accuracy => total == 0 ? 0 : correct / total;
  int get accuracyPercent => (accuracy * 100).round();

  /// Whether the session pushed the learner into a higher mastery level.
  bool get leveledUp => masteryAfter.index > masteryBefore.index;

  /// Progress (0–1) within the (new) mastery level, for the results ring.
  double get masteryProgress => masteryAfter.progressToNext(masteryPointsAfter);

  bool get isPerfect => total > 0 && correct == total;
}
