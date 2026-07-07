import 'package:flutter/material.dart';

/// Time-of-day greeting used by the header. Pure so it's unit-testable.
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// A course/topic the learner has in progress.
@immutable
class CourseProgress {
  const CourseProgress({
    required this.title,
    required this.icon,
    required this.color,
    required this.completed,
    required this.total,
    required this.estMinutes,
  });

  final String title;
  final IconData icon;
  final Color color;
  final int completed;
  final int total;
  final int estMinutes;

  double get fraction => total == 0 ? 0 : completed / total;
  int get remaining => total - completed;
}

/// The daily study goal + today's progress toward it.
@immutable
class DailyGoalInfo {
  const DailyGoalInfo({
    required this.minutesStudied,
    required this.minutesTarget,
    required this.lessonsDone,
    required this.lessonsTarget,
  });

  final int minutesStudied;
  final int minutesTarget;
  final int lessonsDone;
  final int lessonsTarget;

  double get minutesFraction =>
      minutesTarget == 0 ? 0 : (minutesStudied / minutesTarget).clamp(0, 1);
  double get lessonsFraction =>
      lessonsTarget == 0 ? 0 : (lessonsDone / lessonsTarget).clamp(0, 1);
  bool get isComplete => lessonsDone >= lessonsTarget && lessonsTarget > 0;
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

/// An achievement badge (locked or unlocked, with optional progress).
@immutable
class AchievementBadge {
  const AchievementBadge({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.unlocked = false,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool unlocked;
  final double? progress;
}

/// A topic the learner is weak in.
@immutable
class WeakTopic {
  const WeakTopic({
    required this.label,
    required this.icon,
    required this.accuracy,
    required this.note,
    required this.color,
  });

  final String label;
  final IconData icon;
  final int accuracy;
  final String note;
  final Color color;
}

/// Difficulty of a practice item. The widget maps this to theme-aware colors,
/// so pills read correctly in both light and dark mode.
enum Difficulty {
  easy('Easy'),
  medium('Medium'),
  hard('Hard');

  const Difficulty(this.label);

  final String label;
}

/// A recommended practice question.
@immutable
class PracticeRecommendation {
  const PracticeRecommendation({
    required this.question,
    required this.difficulty,
  });

  final String question;
  final Difficulty difficulty;
}

/// Everything the Home dashboard renders. Assembled by the (mock) home
/// controller — never empty: a first-day user still gets starter content.
@immutable
class HomeData {
  const HomeData({
    required this.userName,
    required this.streak,
    required this.dailyGoal,
    required this.continueCourses,
    required this.todayChallenge,
    required this.achievements,
    required this.weakTopics,
    required this.recommendations,
    required this.numiMessage,
    required this.isFirstDay,
  });

  final String userName;
  final StreakInfo streak;
  final DailyGoalInfo dailyGoal;
  final List<CourseProgress> continueCourses;
  final TodayChallenge? todayChallenge;
  final List<AchievementBadge> achievements;
  final List<WeakTopic> weakTopics;
  final List<PracticeRecommendation> recommendations;
  final String numiMessage;
  final bool isFirstDay;
}
