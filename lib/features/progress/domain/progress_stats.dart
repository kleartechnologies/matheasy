import 'package:flutter/foundation.dart';

/// The kind of a logged learning activity (drives its icon/accent).
enum LearningActivityType { practice, achievement, milestone, scan, tutor }

/// One entry in the recent-activity feed.
@immutable
class LearningActivity {
  const LearningActivity({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.epochMillis,
    this.emoji,
  });

  final LearningActivityType type;
  final String title;
  final String subtitle;

  /// When it happened (ms since epoch), for ordering + serialization.
  final int epochMillis;

  /// Optional badge emoji (for achievement activities).
  final String? emoji;
}

/// Local analytics NOT already captured by practice progress — scans, tutor
/// usage, distinct active days, and the recent-activity feed.
///
/// Practice-derived numbers (XP, streak, mastery, questions) live in
/// `PracticeProgress`; this holds only what the progress feature owns.
@immutable
class ProgressStats {
  const ProgressStats({
    this.scans = 0,
    this.tutorUses = 0,
    this.learningDays = const {},
    this.recentActivity = const [],
  });

  static const ProgressStats empty = ProgressStats();

  /// Newest an activity feed keeps.
  static const int maxActivity = 20;

  final int scans;
  final int tutorUses;

  /// Epoch-days on which the learner did anything (for "learning days").
  final Set<int> learningDays;

  /// Recent activity, newest first, bounded to [maxActivity].
  final List<LearningActivity> recentActivity;

  int get learningDayCount => learningDays.length;

  ProgressStats copyWith({
    int? scans,
    int? tutorUses,
    Set<int>? learningDays,
    List<LearningActivity>? recentActivity,
  }) {
    return ProgressStats(
      scans: scans ?? this.scans,
      tutorUses: tutorUses ?? this.tutorUses,
      learningDays: learningDays ?? this.learningDays,
      recentActivity: recentActivity ?? this.recentActivity,
    );
  }
}
