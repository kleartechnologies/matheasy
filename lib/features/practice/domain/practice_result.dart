import 'package:flutter/foundation.dart';

import 'mastery.dart';
import 'practice_session.dart';
import 'practice_topic.dart';

/// The outcome shown on the session-complete screen.
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

  PracticeTopic get topic => request.topic;

  double get accuracy => total == 0 ? 0 : correct / total;
  int get accuracyPercent => (accuracy * 100).round();

  /// Whether the session pushed the learner into a higher mastery level.
  bool get leveledUp => masteryAfter.index > masteryBefore.index;

  /// Progress (0–1) within the (new) mastery level, for the results ring.
  double get masteryProgress => masteryAfter.progressToNext(masteryPointsAfter);

  bool get isPerfect => total > 0 && correct == total;
}
