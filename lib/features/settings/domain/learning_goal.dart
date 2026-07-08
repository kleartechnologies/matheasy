import 'package:flutter/material.dart';

/// Why the learner is using Matheasy — shapes tone and future recommendations.
///
/// Distinct from `DailyGoal` (a daily time commitment): this captures intent.
enum LearningGoal {
  improveGrades('Improve my grades', Icons.trending_up_rounded),
  examPrep('Prepare for an exam', Icons.flag_rounded),
  keepUp('Keep up in class', Icons.menu_book_rounded),
  getAhead('Get ahead of class', Icons.rocket_launch_rounded),
  buildConfidence('Build my confidence', Icons.favorite_rounded);

  const LearningGoal(this.label, this.icon);

  final String label;
  final IconData icon;
}
