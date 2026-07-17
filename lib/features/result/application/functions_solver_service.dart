import 'dart:ui' show Offset;

import '../../scan/domain/detected_equation.dart';
import '../../scan/domain/scan_source.dart';
import '../domain/result_models.dart';
import 'solver_service.dart';

/// Real solver — calls the `solveEquation` Cloud Function (OpenAI behind the
/// server, key never on device) and maps its JSON onto [ResultData].
///
/// Used only for signed-in users with Firebase configured; guests / the
/// unconfigured checkout keep [MockSolverService] (see [solverServiceProvider]).
class FunctionsSolverService implements SolverService {
  const FunctionsSolverService(this._call);

  /// Injected so the mapping is testable without the `cloud_functions` plugin.
  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)
      _call;

  @override
  Future<ResultData> solve(DetectedEquation equation) async {
    final json = await _call('solveEquation', {
      'latex': equation.latex,
      // A manually-typed problem had no prior OCR scan, so it meters here.
      'countAsScan': equation.source == ScanSource.manual,
    });
    return SolveResponseMapper.toResultData(equation, json);
  }
}

/// Pure JSON → [ResultData] mapping for the `solveEquation` response.
///
/// The Cloud Function returns the deterministic §4 schema (`problemLatex`,
/// `problemType`, `finalAnswer {latex, plain}`, `verified`, `methods[{id, name,
/// examPick, steps[{expression, operation, why}]}]`, `graph`). We map it onto the
/// existing [ResultData] the result UI already renders:
///   • the worked steps come from the exam-pick method,
///   • `verified` drives an honest verify line (spec §1.1),
///   • explanations / practice aren't part of §4 (separate features), so they
///     map to empty lists — the Explain/Practice tabs already show empty states.
///
/// Kept separate so it's unit-testable without any Firebase plugin.
class SolveResponseMapper {
  const SolveResponseMapper._();

  static ResultData toResultData(
    DetectedEquation equation,
    Map<String, dynamic> json,
  ) {
    final verified = json['verified'] == true;
    final routeToTutor = json['routeToTutor'] == true;
    final finalAnswer = json['finalAnswer'];
    final answerLatex = finalAnswer is Map ? _str(finalAnswer['latex']) : '';
    final answerPlain = finalAnswer is Map ? _str(finalAnswer['plain']) : '';

    final methods = _list(json['methods'], _method);
    final examMethod = _pickExamMethod(json['methods']);
    // The server sends the honest problemType alongside routeToTutor, so the
    // invite can say what the problem actually is — a system of equations must
    // never be presented as "a proof".
    final tutorReason = switch (_str(json['problemType'])) {
      'system_of_equations' => TutorRouteReason.system,
      'multi_part' => TutorRouteReason.multiPart,
      _ => TutorRouteReason.proof,
    };

    return ResultData(
      equation: equation,
      type: _typeFor(_str(json['problemType']), equation.kind),
      difficulty: Difficulty.medium,
      answerLatex: answerLatex,
      answerPlain: answerPlain,
      verified: verified,
      routeToTutor: routeToTutor,
      tutorRouteReason: tutorReason,
      verifyText: verified
          ? 'Checked by substituting the answer back into the problem ✓'
          : routeToTutor
              ? switch (tutorReason) {
                  TutorRouteReason.system =>
                    'This system may have several solutions — there\'s no '
                        'single answer to check, so let\'s work through it '
                        'together.',
                  TutorRouteReason.multiPart =>
                    'This problem asks for more than one thing — there\'s no '
                        'single answer to check, so let\'s work through it '
                        'together.',
                  TutorRouteReason.proof =>
                    "This is a proof-style problem — there's no single answer "
                        'to check, so let\'s reason through it together.',
                }
              : "Matheasy couldn't verify this answer — try re-scanning or "
                  'typing it in.',
      tutorIntro: verified
          ? "Here's the solution — tap any step to see why it works."
          : routeToTutor
              ? switch (tutorReason) {
                  TutorRouteReason.system =>
                    "I couldn't prove a complete solution to this system — "
                        "let's solve it together.",
                  TutorRouteReason.multiPart =>
                    "Let's take this one part at a time.",
                  TutorRouteReason.proof =>
                    "I don't compute proofs — but I can walk you through one.",
                }
              : "I couldn't fully check this one, so I'd rather not guess.",
      steps: examMethod == null ? const [] : _list(examMethod['steps'], _step),
      explanations: const [], // not in §4 — Explain tab shows its empty state
      methods: methods,
      practice: const [], // not in §4 — Practice tab shows its empty state
      graph: _graph(json['graph']),
    );
  }

  static SolutionStep _step(Map<String, dynamic> m) {
    final operation = _str(m['operation']);
    return SolutionStep(
      title: operation.isEmpty ? 'Step' : operation,
      resultLatex: _str(m['expression']),
      detail: _str(m['why']),
      operationLabel: operation.isEmpty ? null : operation,
    );
  }

  static MethodSolution _method(Map<String, dynamic> m) => MethodSolution(
        name: _str(m['name'], fallback: 'Method'),
        subtitle: '',
        description: '',
        advantages: const [],
        whenToUse: '',
        // The methods tab lists each step's resulting expression as text…
        steps: _list(m['steps'], (s) => _str(s['expression']))
            .where((s) => s.isNotEmpty)
            .toList(),
        // …while the Solution-tab switcher renders this method's OWN structured
        // stepper (expression + operation + why) — spec §5.
        stepperSteps: _list(m['steps'], _step),
        recommended: m['examPick'] == true,
      );

  static GraphData? _graph(Object? g) {
    if (g is! Map) return null;
    final expression = _str(g['expression']);
    if (expression.isEmpty) return null;
    final points =
        _list(g['keyPoints'], _keyPoint).whereType<GraphKeyPoint>().toList();
    final curve = <Offset>[];
    final rawCurve = g['curve'];
    if (rawCurve is List) {
      for (final p in rawCurve) {
        if (p is Map) {
          final x = p['x'];
          final y = p['y'];
          if (x is num && y is num) curve.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    return GraphData(
      kind: _str(g['kind'], fallback: 'function'),
      expression: expression,
      keyPoints: points,
      curve: curve,
    );
  }

  static GraphKeyPoint? _keyPoint(Map<String, dynamic> m) {
    final x = m['x'];
    final y = m['y'];
    if (x is! num || y is! num) return null;
    return GraphKeyPoint(label: _str(m['label']), x: x.toDouble(), y: y.toDouble());
  }

  /// The first method with `examPick: true`, else the first method, else null.
  static Map<String, dynamic>? _pickExamMethod(Object? methods) {
    if (methods is! List) return null;
    Map<String, dynamic>? first;
    for (final m in methods) {
      if (m is Map) {
        final mm = Map<String, dynamic>.from(m);
        first ??= mm;
        if (mm['examPick'] == true) return mm;
      }
    }
    return first;
  }

  /// Map the §4 snake-case `problemType` onto the display [ResultType], keeping
  /// the pre-solve fraction caption when the server just calls it arithmetic.
  static ResultType _typeFor(String problemType, EquationKind kind) {
    // Geometry is invisible to the solver — classify.ts sees a geometry problem
    // as an equation, so `problemType` is never "geometry". The Vision topic,
    // carried on `kind`, is the only signal. Check it FIRST: after the switch, a
    // geometry problem parsed as (e.g.) a linear equation would be grabbed by the
    // linear/quadratic arm and mis-typed. Order is load-bearing.
    if (kind == EquationKind.geometry) return ResultType.geometry;
    switch (problemType) {
      case 'linear_equation':
        return ResultType.linear;
      case 'quadratic_equation':
      case 'polynomial_equation':
        return ResultType.quadratic;
      case 'trigonometric_equation':
        return ResultType.trigonometry;
      case 'simultaneous_equations':
      case 'linear_system':
        return ResultType.system;
      case 'arithmetic':
      case 'expression':
        return kind == EquationKind.fraction
            ? ResultType.fraction
            : ResultType.expression;
      default:
        return ResultType.expression;
    }
  }

  // ---- Helpers ----
  static String _str(Object? v, {String fallback = ''}) =>
      v is String && v.trim().isNotEmpty ? v.trim() : fallback;

  static List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) map) =>
      v is List
          ? [
              for (final e in v)
                if (e is Map) map(Map<String, dynamic>.from(e)),
            ]
          : const [];
}
