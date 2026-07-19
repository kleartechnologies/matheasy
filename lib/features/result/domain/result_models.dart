import 'package:flutter/material.dart';

import '../../scan/domain/detected_equation.dart';
import 'animation_schema.dart';
import 'teaching_models.dart';

/// Total string coercion — a non-String (number/list/null) degrades instead of
/// throwing, so a foreign / hand-edited / older cached blob can't crash a
/// `fromJson` (history round-trip). `_s` returns '', `_sn` returns null.
String _s(Object? v) => v is String ? v : '';
String? _sn(Object? v) => v is String ? v : null;

/// High-level classification of a solved problem.
enum ResultType {
  linear('Linear Equation'),
  quadratic('Quadratic Equation'),
  fraction('Fraction Arithmetic'),
  expression('Arithmetic Expression'),
  trigonometry('Trigonometry'),
  geometry('Geometry'),
  system('Simultaneous Equations');

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
///
/// The v1 fields ([title], [resultLatex], [detail], [operationLabel]) are always
/// present. The v2 teaching fields ([explanation], [commonMistake], [rule],
/// [selfExplainPrompt], [pivotal]) ride along ONLY when the server attached a
/// teaching layer; they default to null/false so a v1 payload parses unchanged
/// and the current UI is byte-identical until a renderer opts into them (Phase 3).
@immutable
class SolutionStep {
  const SolutionStep({
    required this.title,
    required this.resultLatex,
    required this.detail,
    this.operationLabel,
    this.explanation,
    this.commonMistake,
    this.rule,
    this.selfExplainPrompt,
    this.pivotal = false,
  });

  /// Short instruction, e.g. "Subtract 5 from both sides".
  final String title;

  /// The equation state after this step, as LaTeX (e.g. `2x = 8`).
  final String resultLatex;

  /// The "why" shown when the step is expanded.
  final String detail;

  /// Optional operation chip, e.g. `− 5` (the transform symbol when enriched).
  final String? operationLabel;

  /// v2 — plain "what changed" (Pro depth), revealed on demand.
  final String? explanation;

  /// v2 — the trap at this step (Pro depth), revealed on demand.
  final String? commonMistake;

  /// v2 — a named property label, e.g. "Zero-product property" (Pro depth).
  final String? rule;

  /// v2 — an elicited QUESTION for the pivotal step (answered before `why`).
  final String? selfExplainPrompt;

  /// v2 — the pivotal transformation the learning journey points at.
  final bool pivotal;

  Map<String, dynamic> toJson() => {
        'title': title,
        'resultLatex': resultLatex,
        'detail': detail,
        if (operationLabel != null) 'operationLabel': operationLabel,
        if (explanation != null) 'explanation': explanation,
        if (commonMistake != null) 'commonMistake': commonMistake,
        if (rule != null) 'rule': rule,
        if (selfExplainPrompt != null) 'selfExplainPrompt': selfExplainPrompt,
        if (pivotal) 'pivotal': true,
      };

  factory SolutionStep.fromJson(Map<String, dynamic> j) => SolutionStep(
        title: _s(j['title']),
        resultLatex: _s(j['resultLatex']),
        detail: _s(j['detail']),
        operationLabel: _sn(j['operationLabel']),
        explanation: _sn(j['explanation']),
        commonMistake: _sn(j['commonMistake']),
        rule: _sn(j['rule']),
        selfExplainPrompt: _sn(j['selfExplainPrompt']),
        pivotal: j['pivotal'] == true,
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

/// WHY a problem was routed to the tutor instead of the verify-gate solver.
/// Drives honest copy on the invite — a solvable-looking system of equations
/// must not be presented as "a proof-style problem".
enum TutorRouteReason {
  /// A proof / abstract-algebra / real-analysis prompt — nothing to compute.
  proof,

  /// A system of equations whose full solution set the engine can't prove
  /// complete/unique (non-linear beyond the deterministic paths, or
  /// under/over-determined).
  system,

  /// A multi-part / derived-quantity question — no single answer to check.
  multiPart,
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
    this.routeToTutor = false,
    this.tutorRouteReason = TutorRouteReason.proof,
    this.teaching,
    this.animationSchema,
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

  /// True for a proof / abstract-algebra / real-analysis prompt: there's no
  /// answer to compute-and-verify, so the result screen offers to work through
  /// it in the AI tutor instead of showing a "couldn't verify" error.
  final bool routeToTutor;

  /// What KIND of problem was tutor-routed (meaningful only when
  /// [routeToTutor] is true) — selects the invite's honest framing.
  final TutorRouteReason tutorRouteReason;

  /// The v2 teaching layer (spec §2), or null for a v1 payload / when the server
  /// couldn't attach one. Every renderer that reads it must treat null (and each
  /// empty sub-model) as "show nothing" — the current UI is unchanged when absent.
  final TeachingLayer? teaching;

  /// The OPTIONAL per-step animation sidecar (server `animationSchema`), or null —
  /// the common case (flag-gated server-side, only present for mathsteps equation
  /// solves). Null/empty ⇒ the result UI renders exactly as today; a renderer only
  /// surfaces the player when this is present and non-empty.
  final AnimationSchema? animationSchema;

  String get questionLatex => equation.latex;

  /// A copy with the v2 teaching layer merged in — the enriched [steps] +
  /// [methods] (carrying the deeper inline fields) replace the plain ones and
  /// [teaching] is attached; everything else is preserved. Used by the
  /// progressive teaching fetch (`enrichTeaching`) after the answer is shown.
  ResultData withTeaching({
    required TeachingLayer teaching,
    required List<SolutionStep> steps,
    required List<MethodSolution> methods,
  }) =>
      ResultData(
        equation: equation,
        type: type,
        difficulty: difficulty,
        answerLatex: answerLatex,
        answerPlain: answerPlain,
        steps: steps,
        verifyText: verifyText,
        verified: verified,
        explanations: explanations,
        methods: methods,
        practice: practice,
        tutorIntro: tutorIntro,
        graph: graph,
        routeToTutor: routeToTutor,
        tutorRouteReason: tutorRouteReason,
        teaching: teaching,
        // Preserve the animation sidecar across the progressive teaching merge —
        // the enrich response never carries it, so it must be forwarded here.
        animationSchema: animationSchema,
      );

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
        if (routeToTutor) 'routeToTutor': true,
        if (routeToTutor) 'tutorRouteReason': tutorRouteReason.name,
        if (graph != null) 'graph': graph!.toJson(),
        if (teaching != null) 'teaching': teaching!.toJson(),
        if (animationSchema != null) 'animationSchema': animationSchema!.toJson(),
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
        routeToTutor: j['routeToTutor'] as bool? ?? false,
        tutorRouteReason: TutorRouteReason.values.firstWhere(
          (r) => r.name == j['tutorRouteReason'],
          orElse: () => TutorRouteReason.proof,
        ),
        graph: j['graph'] == null
            ? null
            : GraphData.fromJson(j['graph'] as Map<String, dynamic>),
        teaching: j['teaching'] is Map
            ? TeachingLayer.fromJson(
                Map<String, dynamic>.from(j['teaching'] as Map))
            : null,
        animationSchema: AnimationSchema.tryParse(j['animationSchema']),
      );
}
