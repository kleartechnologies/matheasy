import '../domain/visual_models.dart';
import 'visual_prompt_builder.dart';
import 'visual_solution_service.dart';

/// Real Visual Learning Engine — calls the `generateVisualSolution` Cloud
/// Function (OpenAI behind the server, Pro entitlement enforced server-side)
/// and maps its JSON onto [VisualSolution].
///
/// Used only for signed-in users with Firebase configured; guests / the
/// unconfigured checkout keep [MockVisualSolutionService]
/// (see [visualSolutionServiceProvider]).
class FunctionsVisualSolutionService implements VisualSolutionService {
  const FunctionsVisualSolutionService(this._call);

  /// Injected so the mapping is testable without the `cloud_functions` plugin.
  final Future<Map<String, dynamic>> Function(
      String name, Map<String, dynamic> data) _call;

  @override
  Future<VisualSolution> generate(VisualRequest request) async {
    final json = await _call(
      'generateVisualSolution',
      VisualPromptBuilder.requestPayload(request),
    );
    return VisualResponseMapper.toVisualSolution(json);
  }
}

/// Pure JSON → [VisualSolution] mapping for the `generateVisualSolution`
/// response. Defensive throughout — the model output is untrusted, so every
/// field coerces with a fallback and malformed sections degrade to empty
/// rather than crashing (the tab then falls back to the Explain tab).
class VisualResponseMapper {
  const VisualResponseMapper._();

  static VisualSolution toVisualSolution(Map<String, dynamic> json) {
    final category = _enumByName(ProblemCategory.values, json['category']);
    final explicit =
        _enumByName(VisualizationType.values, json['visualization']);

    // Resolve the renderer tier once: the AI's explicit choice wins; else the
    // category's default tier; else (neither recognised) interactive cards,
    // which render any step structure safely.
    final visualization = explicit ??
        category?.visualization ??
        VisualizationType.interactiveCards;

    return VisualSolution(
      category: category ?? ProblemCategory.algebra,
      difficulty: _enumByName(ProblemDifficulty.values, json['difficulty']) ??
          ProblemDifficulty.secondary,
      visualization: visualization,
      answerLatex: _str(json['answerLatex']),
      intro: _str(
        json['intro'],
        fallback: "Let's watch this solution unfold.",
      ),
      steps: _list(json['steps'], _step).whereType<VisualStep>().toList(),
      explanation: _explanation(json['explanation']),
      method: _method(json['method']),
      concept: _concept(json['concept']),
    );
  }

  /// A step needs both sides of the transformation to be renderable; anything
  /// less is dropped (an empty step list triggers the tab's fallback).
  static VisualStep? _step(Map<String, dynamic> m) {
    final before = _str(m['beforeLatex']);
    final after = _str(m['afterLatex']);
    if (before.isEmpty || after.isEmpty) return null;
    final hint = _str(m['hint']);
    return VisualStep(
      title: _str(m['title'], fallback: 'Next step'),
      beforeLatex: before,
      afterLatex: after,
      explanation: _str(m['explanation']),
      operationLabel: _optional(m['operationLabel']),
      hint: hint.isEmpty ? null : VisualHint(text: hint),
    );
  }

  static VisualExplanation? _explanation(Object? v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final summary = _str(m['summary']);
    if (summary.isEmpty) return null;
    return VisualExplanation(summary: summary, keyIdeas: _strList(m['keyIdeas']));
  }

  static VisualMethod? _method(Object? v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final name = _str(m['name']);
    if (name.isEmpty) return null;
    return VisualMethod(name: name, description: _str(m['description']));
  }

  static VisualConcept? _concept(Object? v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final kind = _enumByName(VisualConceptKind.values, m['kind']) ??
        VisualConceptKind.generic;
    final caption = _str(m['caption']);
    // A drawing nobody can describe isn't worth showing.
    if (caption.isEmpty) return null;
    return VisualConcept(
      kind: kind,
      caption: caption,
      params: _numMap(m['params']),
      labels: _strMap(m['labels']),
      points: _points(m['points']),
    );
  }

  // ---- Helpers ----
  static String _str(Object? v, {String fallback = ''}) =>
      v is String && v.isNotEmpty ? v : fallback;

  static String? _optional(Object? v) {
    if (v is! String) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _strList(Object? v) =>
      v is List ? [for (final e in v) if (e is String) e] : const [];

  static Map<String, double> _numMap(Object? v) {
    if (v is! Map) return const {};
    return {
      for (final entry in v.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toDouble(),
    };
  }

  static Map<String, String> _strMap(Object? v) {
    if (v is! Map) return const {};
    return {
      for (final entry in v.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  /// Points arrive as `[[x, y], ...]`; malformed entries are skipped.
  static List<VisualPoint> _points(Object? v) {
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is List && e.length >= 2 && e[0] is num && e[1] is num)
          VisualPoint((e[0] as num).toDouble(), (e[1] as num).toDouble()),
    ];
  }

  static List<T?> _list<T>(Object? v, T? Function(Map<String, dynamic>) map) =>
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
