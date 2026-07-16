import 'package:flutter/material.dart';

/// Time-of-day greeting used by the header. Pure so it's unit-testable.
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// A course/topic the learner has in progress.
///
/// No real course/lesson-count source exists yet, so [HomeData.continueCourses]
/// is always empty and the continue card stays hidden. Do NOT populate these
/// fields with samples to make the card appear — a fabricated "8 / 11 lessons"
/// is the exact bug this model's emptiness is protecting against.
@immutable
class CourseProgress {
  const CourseProgress({
    required this.title,
    required this.icon,
    required this.completed,
    required this.total,
    required this.estMinutes,
  });

  final String title;
  final IconData icon;
  final int completed;
  final int total;
  final int estMinutes;

  double get fraction => total == 0 ? 0 : completed / total;
  int get remaining => total - completed;
}

/// A featured daily challenge with an XP reward.
@immutable
class TodayChallenge {
  const TodayChallenge({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.target,
    required this.xpReward,
  });

  final String title;
  final String subtitle;
  final int done;
  final int target;
  final int xpReward;

  double get fraction => target == 0 ? 0 : (done / target).clamp(0, 1);
}

/// Current + best streak.
@immutable
class StreakInfo {
  const StreakInfo({required this.current, required this.best});

  final int current;
  final int best;

  bool get isActive => current > 0;
}

/// A topic the learner is weak in — measured, never assumed. [accuracy] is a
/// real per-topic percentage; a learner with too few attempts produces no
/// [WeakTopic] at all rather than a guessed one.
@immutable
class WeakTopic {
  const WeakTopic({
    required this.label,
    required this.icon,
    required this.accuracy,
  });

  final String label;
  final IconData icon;
  final int accuracy;
}

/// Everything the Home screen renders, assembled from REAL per-user state.
///
/// Every collection here can be empty and every card is hidden when its source
/// is: a first-day learner sees the hero and the daily challenge, never a
/// fabricated streak, course or accuracy. This type deliberately holds nothing
/// Home cannot source honestly — if a field has no real provider behind it, it
/// does not belong here.
@immutable
class HomeData {
  const HomeData({
    required this.userName,
    required this.streak,
    required this.continueCourses,
    required this.todayChallenge,
    required this.weakTopics,
    required this.isFirstDay,
  });

  final String userName;
  final StreakInfo streak;
  final List<CourseProgress> continueCourses;
  final TodayChallenge? todayChallenge;
  final List<WeakTopic> weakTopics;
  final bool isFirstDay;
}
