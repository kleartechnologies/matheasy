import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/functions_client.dart';
import '../../settings/application/language_provider.dart';
import '../domain/practice_difficulty.dart';
import '../domain/practice_question.dart';
import '../domain/practice_skill.dart';

/// Tier 3 — AI question generation via the `generatePracticeQuestion` Cloud
/// Function (OpenAI server-side, Pro-gated). Used only where templates/rules
/// can't reach (calculus, advanced/university math).
///
/// Cost control is built in: requests are **batched** (a single call fetches a
/// buffer of questions) and the surplus is **cached in memory** per
/// skill+difficulty, so a five-question calculus set costs one OpenAI call, and
/// the next set is often free. `null` from [aiPracticeGeneratorProvider] means
/// AI isn't available (guest / offline / unconfigured) — the orchestrator then
/// degrades gracefully to on-device tiers.
abstract interface class AiPracticeGenerator {
  /// Best-effort — returns up to [count] questions for [skill] at [difficulty].
  /// May return fewer (or throw) on backend failure; the caller falls back.
  Future<List<PracticeQuestion>> generate({
    required PracticeSkill skill,
    required PracticeDifficulty difficulty,
    required int count,
  });
}

typedef _CallFn = Future<Map<String, dynamic>> Function(
  String name,
  Map<String, dynamic> data,
);

/// Real AI generator — calls `generatePracticeQuestion` and maps its JSON onto
/// [PracticeQuestion]s, with an in-memory per-(skill, difficulty) buffer.
class FunctionsAiPracticeGenerator implements AiPracticeGenerator {
  FunctionsAiPracticeGenerator(this._call);

  final _CallFn _call;

  /// Surplus questions kept for the next request, keyed by `skillId:difficulty`.
  final Map<String, List<PracticeQuestion>> _cache = {};
  int _idCounter = 0;

  /// How many questions to fetch per backend round-trip (amortizes OpenAI cost).
  static const int _batchSize = 6;

  @override
  Future<List<PracticeQuestion>> generate({
    required PracticeSkill skill,
    required PracticeDifficulty difficulty,
    required int count,
  }) async {
    final key = '${skill.id}:${difficulty.name}';
    final buffer = _cache.putIfAbsent(key, () => <PracticeQuestion>[]);
    final result = <PracticeQuestion>[];

    // Serve from the buffer first — often makes a session cost zero AI calls.
    while (result.length < count && buffer.isNotEmpty) {
      result.add(buffer.removeAt(0));
    }
    if (result.length >= count) return result;

    final need = count - result.length;
    final fetchCount = need < _batchSize ? _batchSize : need;

    final spec = difficulty.spec;
    final json = await _call('generatePracticeQuestion', {
      'topic': skill.topic.name,
      'skill': skill.id,
      'skillLabel': skill.label,
      'difficulty': difficulty.name,
      // The strict difficulty contract (spec §"Generation Rules"): the server
      // gives the model the grade band, target complexity + max solving steps.
      'grade': spec.gradeLabel,
      'targetSteps': spec.targetSteps,
      'maxSteps': spec.maxSteps,
      'count': fetchCount,
    });

    final fetched = PracticeQuestionMapper.fromResponse(
      json,
      skill: skill,
      difficulty: difficulty,
      nextId: _nextId,
    );
    result.addAll(fetched.take(need));
    if (fetched.length > need) {
      buffer.addAll(fetched.skip(need)); // stash the surplus for next time
    }
    return result;
  }

  String _nextId() => 'ai-${_idCounter++}';
}

/// Pure JSON → [PracticeQuestion] mapping for the `generatePracticeQuestion`
/// response. Defensive throughout — model output is untrusted, so every field
/// coerces with a fallback and malformed questions are dropped rather than
/// crashing (the orchestrator then tops up from another tier).
class PracticeQuestionMapper {
  const PracticeQuestionMapper._();

  static List<PracticeQuestion> fromResponse(
    Map<String, dynamic> json, {
    required PracticeSkill skill,
    required PracticeDifficulty difficulty,
    required String Function() nextId,
  }) {
    final raw = json['questions'];
    if (raw is! List) return const [];
    final questions = <PracticeQuestion>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final question = _question(map, skill, difficulty, nextId());
      if (question != null) questions.add(question);
    }
    return questions;
  }

  static PracticeQuestion? _question(
    Map<String, dynamic> map,
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    String id,
  ) {
    final prompt = _str(map['prompt']);
    if (prompt.isEmpty) return null;
    final type = _type(map['type']);
    final explanation = _str(map['explanation'], fallback: 'Work it through '
        'step by step.');

    final options = _options(map['options']);
    final acceptedAnswers = _strList(map['acceptedAnswers']);

    // A question must be answerable: a choice type needs a correct option; a
    // typed type needs at least one accepted answer.
    final isChoice = type == PracticeQuestionType.multipleChoice ||
        type == PracticeQuestionType.trueFalse;
    if (isChoice) {
      if (!options.any((o) => o.isCorrect)) return null;
    } else if (acceptedAnswers.isEmpty) {
      return null;
    }

    return PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: type,
      prompt: prompt,
      promptLatex: _optional(map['promptLatex']),
      spokenPrompt: _optional(map['spokenPrompt']),
      explanation: explanation,
      skillId: skill.id,
      options: isChoice ? options : const [],
      acceptedAnswers: isChoice ? const [] : acceptedAnswers,
    );
  }

  static PracticeQuestionType _type(Object? value) {
    if (value is String) {
      for (final t in PracticeQuestionType.values) {
        if (t.name == value) return t;
      }
    }
    return PracticeQuestionType.input;
  }

  static List<PracticeOption> _options(Object? value) {
    if (value is! List) return const [];
    final options = <PracticeOption>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final text = _str(entry['text']);
      if (text.isEmpty) continue;
      options.add(PracticeOption(text, isCorrect: entry['isCorrect'] == true));
    }
    return options;
  }

  static String _str(Object? value, {String fallback = ''}) =>
      value is String && value.trim().isNotEmpty ? value.trim() : fallback;

  static String? _optional(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _strList(Object? value) => value is List
      ? [
          for (final e in value)
            if (e is String && e.trim().isNotEmpty) e.trim(),
        ]
      : const [];
}

/// Provides the active [AiPracticeGenerator], or `null` when the AI backend
/// isn't usable (guest / unconfigured / offline — same gate as the other AI
/// services). The orchestrator treats `null` as "AI unavailable" and falls back.
final Provider<AiPracticeGenerator?> aiPracticeGeneratorProvider =
    Provider<AiPracticeGenerator?>((ref) {
  if (!ref.watch(aiBackendReadyProvider)) return null;
  final functions = ref.watch(firebaseFunctionsProvider);
  final ctx = ref.watch(aiRequestContextProvider);
  return FunctionsAiPracticeGenerator(
    (name, data) => callFunction(functions, name, {...data, ...ctx}),
  );
});
