import 'package:flutter/material.dart';

import '../../scan/domain/detected_equation.dart';

/// High-level classification of a solved problem.
enum ResultType {
  linear('Linear Equation'),
  quadratic('Quadratic Equation'),
  fraction('Fraction Arithmetic'),
  expression('Arithmetic Expression'),
  trigonometry('Trigonometry');

  const ResultType(this.label);

  final String label;
}

/// Estimated difficulty of a problem / practice item.
enum Difficulty {
  easy('Easy'),
  medium('Medium'),
  hard('Hard');

  const Difficulty(this.label);

  final String label;
}

/// The register an explanation is written in.
enum ExplanationMode {
  simple('Simple', Icons.lightbulb_outline_rounded),
  teacher('Teacher', Icons.school_rounded),
  exam('Exam', Icons.assignment_rounded);

  const ExplanationMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// A single step in the worked solution.
@immutable
class SolutionStep {
  const SolutionStep({
    required this.title,
    required this.resultLatex,
    required this.detail,
    this.operationLabel,
  });

  /// Short instruction, e.g. "Subtract 5 from both sides".
  final String title;

  /// The equation state after this step, as LaTeX (e.g. `2x = 8`).
  final String resultLatex;

  /// The "why" shown when the step is expanded.
  final String detail;

  /// Optional operation chip, e.g. `− 5`.
  final String? operationLabel;
}

/// One explanation register (Simple / Teacher / Exam).
@immutable
class Explanation {
  const Explanation({
    required this.mode,
    required this.body,
    required this.points,
  });

  final ExplanationMode mode;
  final String body;
  final List<String> points;
}

/// One way of solving the problem.
@immutable
class MethodSolution {
  const MethodSolution({
    required this.name,
    required this.subtitle,
    required this.description,
    required this.advantages,
    required this.whenToUse,
    required this.steps,
    this.recommended = false,
  });

  final String name;
  final String subtitle;
  final String description;
  final List<String> advantages;
  final String whenToUse;
  final List<String> steps;
  final bool recommended;
}

/// A recommended similar practice question.
@immutable
class PracticeQuestion {
  const PracticeQuestion({
    required this.questionLatex,
    required this.difficulty,
    required this.xpReward,
  });

  final String questionLatex;
  final Difficulty difficulty;
  final int xpReward;
}

/// The full solved-problem payload rendered by the Scan Result screen.
///
/// STAGE 5 fills this from [MockSolverService]. Because the UI depends only on
/// this shape, a Stage 6 AI solver produces the same object and nothing in the
/// presentation layer changes.
@immutable
class ResultData {
  const ResultData({
    required this.equation,
    required this.type,
    required this.difficulty,
    required this.answerLatex,
    required this.steps,
    required this.verifyText,
    required this.explanations,
    required this.methods,
    required this.practice,
    required this.tutorIntro,
  });

  final DetectedEquation equation;
  final ResultType type;
  final Difficulty difficulty;
  final String answerLatex;
  final List<SolutionStep> steps;

  /// A "check" line, e.g. "2(4) + 5 = 13 ✓".
  final String verifyText;

  final List<Explanation> explanations;
  final List<MethodSolution> methods;
  final List<PracticeQuestion> practice;
  final String tutorIntro;

  String get questionLatex => equation.latex;
}
