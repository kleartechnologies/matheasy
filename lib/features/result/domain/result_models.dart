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

  Map<String, dynamic> toJson() => {
        'title': title,
        'resultLatex': resultLatex,
        'detail': detail,
        if (operationLabel != null) 'operationLabel': operationLabel,
      };

  factory SolutionStep.fromJson(Map<String, dynamic> j) => SolutionStep(
        title: j['title'] as String? ?? '',
        resultLatex: j['resultLatex'] as String? ?? '',
        detail: j['detail'] as String? ?? '',
        operationLabel: j['operationLabel'] as String?,
      );
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

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'body': body,
        'points': points,
      };

  factory Explanation.fromJson(Map<String, dynamic> j) => Explanation(
        mode: ExplanationMode.values.firstWhere(
          (m) => m.name == j['mode'],
          orElse: () => ExplanationMode.simple,
        ),
        body: j['body'] as String? ?? '',
        points: (j['points'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
      );
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
    this.stepperSteps = const [],
  });

  final String name;
  final String subtitle;
  final String description;
  final List<String> advantages;
  final String whenToUse;

  /// Each step's resulting expression as plain text (the Methods comparison tab).
  final List<String> steps;
  final bool recommended;

  /// Structured steps (expression + operation + why) for this method's own
  /// stepper (spec §5 method switcher). Populated from the §4 schema; empty for
  /// the offline mock, where the Solution tab derives from [steps] instead.
  final List<SolutionStep> stepperSteps;

  Map<String, dynamic> toJson() => {
        'name': name,
        'subtitle': subtitle,
        'description': description,
        'advantages': advantages,
        'whenToUse': whenToUse,
        'steps': steps,
        'recommended': recommended,
        'stepperSteps': stepperSteps.map((s) => s.toJson()).toList(),
      };

  factory MethodSolution.fromJson(Map<String, dynamic> j) => MethodSolution(
        name: j['name'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        description: j['description'] as String? ?? '',
        advantages: (j['advantages'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        whenToUse: j['whenToUse'] as String? ?? '',
        steps: (j['steps'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        recommended: j['recommended'] as bool? ?? false,
        stepperSteps: (j['stepperSteps'] as List<dynamic>? ?? const [])
            .map((e) => SolutionStep.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A labeled point on the solution graph (root, intercept, vertex …).
@immutable
class GraphKeyPoint {
  const GraphKeyPoint({
    required this.label,
    required this.x,
    required this.y,
  });

  final String label;
  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'label': label, 'x': x, 'y': y};

  factory GraphKeyPoint.fromJson(Map<String, dynamic> j) => GraphKeyPoint(
        label: j['label'] as String? ?? '',
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
      );
}

/// A plottable function returned with a solution (spec §4 / §7). `null` when the
/// problem isn't a plottable function.
@immutable
class GraphData {
  const GraphData({
    required this.kind,
    required this.expression,
    required this.keyPoints,
    this.curve = const [],
  });

  /// Currently always `"function"`.
  final String kind;

  /// The plotted expression as delimiter-free LaTeX, e.g. `5x^2 + 3x - 2`.
  final String expression;

  final List<GraphKeyPoint> keyPoints;

  /// Deterministic samples of the (verified) expression the client draws as the
  /// curve — computed server-side so no LaTeX is evaluated on-device (spec §7).
  final List<Offset> curve;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'expression': expression,
        'keyPoints': keyPoints.map((k) => k.toJson()).toList(),
        'curve': curve.map((o) => {'x': o.dx, 'y': o.dy}).toList(),
      };

  factory GraphData.fromJson(Map<String, dynamic> j) => GraphData(
        kind: j['kind'] as String? ?? 'function',
        expression: j['expression'] as String? ?? '',
        keyPoints: (j['keyPoints'] as List<dynamic>? ?? const [])
            .map((e) => GraphKeyPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        curve: (j['curve'] as List<dynamic>? ?? const [])
            .map((e) => Offset(
                  ((e as Map<String, dynamic>)['x'] as num).toDouble(),
                  (e['y'] as num).toDouble(),
                ))
            .toList(),
      );
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

  Map<String, dynamic> toJson() => {
        'questionLatex': questionLatex,
        'difficulty': difficulty.name,
        'xpReward': xpReward,
      };

  factory PracticeQuestion.fromJson(Map<String, dynamic> j) => PracticeQuestion(
        questionLatex: j['questionLatex'] as String? ?? '',
        difficulty: Difficulty.values.firstWhere(
          (d) => d.name == j['difficulty'],
          orElse: () => Difficulty.medium,
        ),
        xpReward: (j['xpReward'] as num?)?.toInt() ?? 0,
      );
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
    this.verified = true,
    this.answerPlain = '',
    this.graph,
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

  /// Whether the server proved the answer by substituting it back (spec §1.1).
  /// When `false`, [answerLatex] is empty and the UI should show the honest
  /// "couldn't verify — try re-scanning" state rather than a confident answer.
  final bool verified;

  /// The answer in plain text (screen-reader / copy), e.g. `x = -1 or x = 2/5`.
  final String answerPlain;

  /// The plottable function for this problem, or `null`.
  final GraphData? graph;

  String get questionLatex => equation.latex;

  Map<String, dynamic> toJson() => {
        'equation': equation.toJson(),
        'type': type.name,
        'difficulty': difficulty.name,
        'answerLatex': answerLatex,
        'answerPlain': answerPlain,
        'steps': steps.map((s) => s.toJson()).toList(),
        'verifyText': verifyText,
        'verified': verified,
        'explanations': explanations.map((e) => e.toJson()).toList(),
        'methods': methods.map((m) => m.toJson()).toList(),
        'practice': practice.map((p) => p.toJson()).toList(),
        'tutorIntro': tutorIntro,
        if (graph != null) 'graph': graph!.toJson(),
      };

  factory ResultData.fromJson(Map<String, dynamic> j) => ResultData(
        equation:
            DetectedEquation.fromJson(j['equation'] as Map<String, dynamic>),
        type: ResultType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => ResultType.expression,
        ),
        difficulty: Difficulty.values.firstWhere(
          (d) => d.name == j['difficulty'],
          orElse: () => Difficulty.medium,
        ),
        answerLatex: j['answerLatex'] as String? ?? '',
        answerPlain: j['answerPlain'] as String? ?? '',
        steps: (j['steps'] as List<dynamic>? ?? const [])
            .map((e) => SolutionStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        verifyText: j['verifyText'] as String? ?? '',
        verified: j['verified'] as bool? ?? true,
        explanations: (j['explanations'] as List<dynamic>? ?? const [])
            .map((e) => Explanation.fromJson(e as Map<String, dynamic>))
            .toList(),
        methods: (j['methods'] as List<dynamic>? ?? const [])
            .map((e) => MethodSolution.fromJson(e as Map<String, dynamic>))
            .toList(),
        practice: (j['practice'] as List<dynamic>? ?? const [])
            .map((e) => PracticeQuestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        tutorIntro: j['tutorIntro'] as String? ?? '',
        graph: j['graph'] == null
            ? null
            : GraphData.fromJson(j['graph'] as Map<String, dynamic>),
      );
}
