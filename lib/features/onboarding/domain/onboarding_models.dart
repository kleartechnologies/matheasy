import 'package:flutter/material.dart';

/// What the learner is studying — drives content difficulty & exam framing.
enum StudyLevel {
  primary('Primary School', Icons.backpack_rounded),
  secondary('Secondary School', Icons.school_rounded),
  spm('SPM', Icons.flag_rounded),
  igcse('IGCSE', Icons.public_rounded),
  gcse('GCSE', Icons.language_rounded),
  sat('SAT', Icons.edit_note_rounded),
  university('University', Icons.account_balance_rounded);

  const StudyLevel(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Topics the learner finds hardest — seeds the "strengthen these" experience.
enum MathTopic {
  algebra('Algebra', Icons.functions_rounded),
  fractions('Fractions', Icons.percent_rounded),
  geometry('Geometry', Icons.change_history_rounded),
  wordProblems('Word Problems', Icons.menu_book_rounded),
  calculus('Calculus', Icons.show_chart_rounded),
  trigonometry('Trigonometry', Icons.architecture_rounded);

  const MathTopic(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Daily study commitment — drives goal + reminder cadence.
enum DailyGoal {
  min5('5 minutes', 5, 'Casual'),
  min10('10 minutes', 10, 'Popular'),
  min15('15 minutes', 15, 'Serious'),
  min30('30 minutes', 30, 'Intense');

  const DailyGoal(this.label, this.minutes, this.tag);

  final String label;
  final int minutes;
  final String tag;
}

/// Immutable snapshot of everything collected during onboarding.
///
/// STAGE 2: kept purely in memory (the flow controller). A later stage persists
/// it (Isar / Firestore) and uses it to personalize Home, Practice and exam
/// framing.
@immutable
class OnboardingData {
  const OnboardingData({
    this.level,
    this.topics = const <MathTopic>{},
    this.goal,
  });

  final StudyLevel? level;
  final Set<MathTopic> topics;
  final DailyGoal? goal;

  bool get hasLevel => level != null;
  bool get hasTopics => topics.isNotEmpty;
  bool get hasGoal => goal != null;

  OnboardingData copyWith({
    StudyLevel? level,
    Set<MathTopic>? topics,
    DailyGoal? goal,
  }) {
    return OnboardingData(
      level: level ?? this.level,
      topics: topics ?? this.topics,
      goal: goal ?? this.goal,
    );
  }

  @override
  String toString() =>
      'OnboardingData(level: $level, topics: $topics, goal: $goal)';
}
