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

/// Pure JSON → [ResultData] mapping for the `solveEquation` response. Kept
/// separate so it's unit-testable without any Firebase plugin.
class SolveResponseMapper {
  const SolveResponseMapper._();

  static ResultData toResultData(
    DetectedEquation equation,
    Map<String, dynamic> json,
  ) {
    return ResultData(
      equation: equation,
      type: _enumByName(ResultType.values, json['type']) ?? ResultType.expression,
      difficulty:
          _enumByName(Difficulty.values, json['difficulty']) ?? Difficulty.medium,
      answerLatex: _str(json['answerLatex']),
      verifyText: _str(json['verifyText']),
      tutorIntro: _str(json['tutorIntro'], fallback: "Here's the solution."),
      steps: _list(json['steps'], _step),
      explanations: _list(json['explanations'], _explanation)
          .whereType<Explanation>()
          .toList(),
      methods: _list(json['methods'], _method),
      practice: _list(json['practice'], _practice),
    );
  }

  static SolutionStep _step(Map<String, dynamic> m) => SolutionStep(
        title: _str(m['title']),
        resultLatex: _str(m['resultLatex']),
        detail: _str(m['detail']),
        operationLabel: (m['operationLabel'] as String?)?.trim().isEmpty ?? true
            ? null
            : m['operationLabel'] as String,
      );

  static Explanation? _explanation(Map<String, dynamic> m) {
    final mode = _enumByName(ExplanationMode.values, m['mode']);
    if (mode == null) return null;
    return Explanation(
      mode: mode,
      body: _str(m['body']),
      points: _strList(m['points']),
    );
  }

  static MethodSolution _method(Map<String, dynamic> m) => MethodSolution(
        name: _str(m['name']),
        subtitle: _str(m['subtitle']),
        description: _str(m['description']),
        advantages: _strList(m['advantages']),
        whenToUse: _str(m['whenToUse']),
        steps: _strList(m['steps']),
        recommended: m['recommended'] == true,
      );

  static PracticeQuestion _practice(Map<String, dynamic> m) => PracticeQuestion(
        questionLatex: _str(m['questionLatex']),
        difficulty:
            _enumByName(Difficulty.values, m['difficulty']) ?? Difficulty.medium,
        xpReward: m['xpReward'] is int ? m['xpReward'] as int : 20,
      );

  // ---- Helpers ----
  static String _str(Object? v, {String fallback = ''}) =>
      v is String && v.isNotEmpty ? v : fallback;

  static List<String> _strList(Object? v) =>
      v is List ? [for (final e in v) if (e is String) e] : const [];

  static List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) map) =>
      v is List
          ? [
              for (final e in v)
                if (e is Map) map(Map<String, dynamic>.from(e)),
            ]
          : const [];

  static T? _enumByName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
