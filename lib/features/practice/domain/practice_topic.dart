import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../onboarding/domain/onboarding_models.dart';

/// A practiceable math topic. Carries its own icon + brand color (matching the
/// codebase convention where content enums bundle presentation hints, e.g.
/// [MathTopic]).
enum PracticeTopic {
  algebra('Algebra', Icons.functions_rounded, AppColors.primary),
  fractions('Fractions', Icons.pie_chart_outline_rounded, AppColors.secondary),
  geometry('Geometry', Icons.change_history_rounded, AppColors.success),
  trigonometry('Trigonometry', Icons.architecture_rounded, AppColors.pink),
  calculus('Calculus', Icons.show_chart_rounded, AppColors.warning),
  statistics('Statistics', Icons.bar_chart_rounded, AppColors.primaryDeep),
  wordProblems('Word Problems', Icons.menu_book_rounded, AppColors.amber);

  const PracticeTopic(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// Maps an onboarding [MathTopic] onto a practice topic.
  static PracticeTopic fromMathTopic(MathTopic topic) {
    return switch (topic) {
      MathTopic.algebra => PracticeTopic.algebra,
      MathTopic.fractions => PracticeTopic.fractions,
      MathTopic.geometry => PracticeTopic.geometry,
      MathTopic.trigonometry => PracticeTopic.trigonometry,
      MathTopic.calculus => PracticeTopic.calculus,
      MathTopic.wordProblems => PracticeTopic.wordProblems,
    };
  }

  /// Resolves a topic from a human label (from Home weak-topics / Result type),
  /// defaulting to [algebra] when unrecognized.
  static PracticeTopic fromLabel(String label) {
    final normalized = label.trim().toLowerCase();
    return values.firstWhere(
      (t) => t.label.toLowerCase() == normalized,
      orElse: () => PracticeTopic.algebra,
    );
  }
}
