import 'package:flutter/material.dart';

import '../../onboarding/domain/onboarding_models.dart';
import '../../result/domain/result_models.dart';

/// A practiceable math topic. The **glyph** is what distinguishes topics; the
/// accent is the brand emerald for every one of them.
///
/// There is deliberately no `color` here. It used to vary per topic and had
/// drifted into a rainbow — emerald / indigo / amber / coral / indigo-light,
/// with trigonometry and wordProblems colliding on the same coral, which is what
/// proved it was drift rather than a designed scale. It read as a game rather
/// than a tutor.
///
/// It is gone rather than unified because a *brightness-agnostic constant on a
/// domain enum cannot be correct*: whatever it held would be AA as text on one
/// theme and fail on the other (`primaryAction` is 4.78:1 on white but 3.58:1 on
/// the dark surface). Topic color is a presentation decision and must be made
/// where the theme is known — every surface now renders topics through
/// `PracticeTopicIcon`, which pulls theme-aware emerald from `context.colors`.
enum PracticeTopic {
  algebra('Algebra', Icons.functions_rounded),
  fractions('Fractions', Icons.pie_chart_outline_rounded),
  geometry('Geometry', Icons.change_history_rounded),
  trigonometry('Trigonometry', Icons.architecture_rounded),
  calculus('Calculus', Icons.show_chart_rounded),
  statistics('Statistics', Icons.bar_chart_rounded),
  wordProblems('Word Problems', Icons.menu_book_rounded);

  const PracticeTopic(this.label, this.icon);

  final String label;
  final IconData icon;

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

  /// Maps a solved-problem [ResultType] onto the practice topic to drill — the
  /// single source of truth for "scan → topic" (Result screen + the Practice
  /// dashboard's scan-history-driven "Strengthen these").
  static PracticeTopic fromResultType(ResultType type) => switch (type) {
        ResultType.linear ||
        ResultType.quadratic ||
        ResultType.expression ||
        ResultType.system =>
          PracticeTopic.algebra,
        ResultType.fraction => PracticeTopic.fractions,
        ResultType.trigonometry => PracticeTopic.trigonometry,
        ResultType.geometry => PracticeTopic.geometry,
      };

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
