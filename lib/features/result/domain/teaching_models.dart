import 'package:flutter/foundation.dart';

import 'visual_models.dart' show ProblemDifficulty;

/// Client mirror of the backend v2 `TeachingLayer` (spec §2 / §4) — the additive,
/// LLM-narrated teaching layer that rides on the verified solve payload. Every
/// model here is null-safe and every parser TOTAL: a v1 payload (no `teaching`)
/// yields `null`, and an unknown enum/category value degrades to a sensible
/// default rather than throwing, so a newer server can never crash an older
/// client. Nothing symbolic runs on device — the client only renders this shape.

// --- category (a stable snake_case string, NOT an enum — spec R2) -----------

/// Human label for a backend `TeachingCategory` string. TOTAL: an unknown value
/// title-cases gracefully (never `enum.byName`, which would throw).
String teachingCategoryLabel(String raw) =>
    _teachingCategoryLabels[raw] ?? _titleCase(raw);

const Map<String, String> _teachingCategoryLabels = {
  'arithmetic': 'Arithmetic',
  'fractions': 'Fractions',
  'algebra': 'Algebra',
  'equations': 'Equations',
  'inequalities': 'Inequalities',
  'functions': 'Functions',
  'trigonometry': 'Trigonometry',
  'calculus': 'Calculus',
  'statistics': 'Statistics',
  'probability': 'Probability',
  'linear_algebra': 'Linear Algebra',
  'geometry': 'Geometry',
  'sequences': 'Sequences',
  'word_problem': 'Word Problem',
  'differential_equations': 'Differential Equations',
  'conceptual': 'Conceptual',
  'other': 'Maths',
};

String _titleCase(String s) {
  if (s.trim().isEmpty) return 'Maths';
  return s
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Parse a backend difficulty string → [ProblemDifficulty] (TOTAL; default
/// [ProblemDifficulty.secondary]). Reuses the Visual-tier enum, no duplicate.
ProblemDifficulty teachingDifficulty(String raw) => switch (raw) {
      'primary' => ProblemDifficulty.primary,
      'secondary' => ProblemDifficulty.secondary,
      'preUniversity' => ProblemDifficulty.preUniversity,
      'university' => ProblemDifficulty.university,
      _ => ProblemDifficulty.secondary,
    };

// --- shared JSON helpers ----------------------------------------------------

String _s(Object? v) => v is String ? v.trim() : '';
String? _sn(Object? v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

List<String> _strList(Object? v) => v is List
    ? [
        for (final e in v)
          if (_s(e).isNotEmpty) _s(e),
      ]
    : const [];

List<T> _objList<T>(Object? v, T Function(Map<String, dynamic>) map) => v is List
    ? [
        for (final e in v)
          if (e is Map) map(Map<String, dynamic>.from(e)),
      ]
    : const [];

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

// --- header -----------------------------------------------------------------

@immutable
class TeachingHeader {
  const TeachingHeader({
    required this.category,
    required this.subcategory,
    required this.difficulty,
    required this.learningObjective,
    required this.methodChosen,
    required this.whyMethodChosen,
  });

  /// Raw snake_case category (kept for mapping to the Visual tier); use
  /// [categoryLabel] for display.
  final String category;
  final String subcategory;
  final ProblemDifficulty difficulty;
  final String learningObjective;
  final String methodChosen;
  final String whyMethodChosen;

  String get categoryLabel => teachingCategoryLabel(category);

  Map<String, dynamic> toJson() => {
        'category': category,
        'subcategory': subcategory,
        'difficulty': difficulty.name,
        'learningObjective': learningObjective,
        'methodChosen': methodChosen,
        'whyMethodChosen': whyMethodChosen,
      };

  factory TeachingHeader.fromJson(Map<String, dynamic> j) => TeachingHeader(
        category: _s(j['category']),
        subcategory: _s(j['subcategory']),
        difficulty: teachingDifficulty(_s(j['difficulty'])),
        learningObjective: _s(j['learningObjective']),
        methodChosen: _s(j['methodChosen']),
        whyMethodChosen: _s(j['whyMethodChosen']),
      );
}

// --- overview + concept -----------------------------------------------------

@immutable
class ProblemOverview {
  const ProblemOverview({
    required this.asked,
    required this.goal,
    required this.givens,
    required this.predictionPrompt,
  });

  final String asked;
  final String goal;
  final List<String> givens;

  /// A one-tap estimation QUESTION shown before the answer reveals — the client
  /// must render it unmistakably as a question, never as a fact (it is exempt
  /// from the server's numeric firewall by design).
  final String predictionPrompt;

  bool get isEmpty =>
      asked.isEmpty && goal.isEmpty && givens.isEmpty && predictionPrompt.isEmpty;

  Map<String, dynamic> toJson() => {
        'asked': asked,
        'goal': goal,
        'givens': givens,
        'predictionPrompt': predictionPrompt,
      };

  factory ProblemOverview.fromJson(Map<String, dynamic> j) => ProblemOverview(
        asked: _s(j['asked']),
        goal: _s(j['goal']),
        givens: _strList(j['givens']),
        predictionPrompt: _s(j['predictionPrompt']),
      );
}

@immutable
class DefinedTerm {
  const DefinedTerm({required this.term, required this.plain});

  final String term;
  final String plain;

  Map<String, dynamic> toJson() => {'term': term, 'plain': plain};

  factory DefinedTerm.fromJson(Map<String, dynamic> j) =>
      DefinedTerm(term: _s(j['term']), plain: _s(j['plain']));
}

@immutable
class ConceptOverview {
  const ConceptOverview({required this.body, required this.definedTerms});

  final String body;
  final List<DefinedTerm> definedTerms;

  bool get isEmpty => body.isEmpty && definedTerms.isEmpty;

  Map<String, dynamic> toJson() => {
        'body': body,
        'definedTerms': definedTerms.map((d) => d.toJson()).toList(),
      };

  factory ConceptOverview.fromJson(Map<String, dynamic> j) => ConceptOverview(
        body: _s(j['body']),
        definedTerms: _objList(j['definedTerms'], DefinedTerm.fromJson),
      );
}

// --- method rationale -------------------------------------------------------

@immutable
class MethodAlternative {
  const MethodAlternative({required this.name, required this.whenBetter});

  final String name;
  final String whenBetter;

  Map<String, dynamic> toJson() => {'name': name, 'whenBetter': whenBetter};

  factory MethodAlternative.fromJson(Map<String, dynamic> j) =>
      MethodAlternative(name: _s(j['name']), whenBetter: _s(j['whenBetter']));
}

@immutable
class MethodRationale {
  const MethodRationale({required this.alternatives});

  final List<MethodAlternative> alternatives;

  bool get isEmpty => alternatives.isEmpty;

  Map<String, dynamic> toJson() =>
      {'alternatives': alternatives.map((a) => a.toJson()).toList()};

  factory MethodRationale.fromJson(Map<String, dynamic> j) => MethodRationale(
        alternatives: _objList(j['alternatives'], MethodAlternative.fromJson),
      );
}

// --- learning journey -------------------------------------------------------

/// A learning-journey stage. Labels are CLIENT constants (never wired).
enum JourneyStageId {
  understand('Understand'),
  chooseMethod('Choose Method'),
  apply('Apply'),
  simplify('Simplify'),
  verify('Verify'),
  takeaway('Takeaway');

  const JourneyStageId(this.label);

  final String label;

  /// TOTAL parse — an unknown id yields null so the stage is dropped, not thrown.
  static JourneyStageId? tryParse(String raw) => switch (raw) {
        'understand' => JourneyStageId.understand,
        'chooseMethod' => JourneyStageId.chooseMethod,
        'apply' => JourneyStageId.apply,
        'simplify' => JourneyStageId.simplify,
        'verify' => JourneyStageId.verify,
        'takeaway' => JourneyStageId.takeaway,
        _ => null,
      };
}

@immutable
class JourneyStage {
  const JourneyStage({
    required this.id,
    required this.summary,
    required this.stepIndices,
  });

  final JourneyStageId id;
  final String? summary;

  /// Indices into the examPick method's steps (engine-computed server-side). These
  /// are stored VERBATIM and NOT bounds-checked against the step count here — a
  /// renderer (Phase 3) MUST clamp/skip any index outside `0..steps.length-1`
  /// before indexing, so a malformed/foreign cached blob can't throw at paint.
  final List<int> stepIndices;

  Map<String, dynamic> toJson() => {
        'id': id.name,
        if (summary != null) 'summary': summary,
        'stepIndices': stepIndices,
      };

  /// Null when the id is unknown (dropped by the caller).
  static JourneyStage? tryFromJson(Map<String, dynamic> j) {
    final id = JourneyStageId.tryParse(_s(j['id']));
    if (id == null) return null;
    final raw = j['stepIndices'];
    final indices = raw is List
        ? [
            for (final e in raw)
              if (e is num) e.toInt(),
          ]
        : const <int>[];
    return JourneyStage(id: id, summary: _sn(j['summary']), stepIndices: indices);
  }
}

// --- mistakes / takeaway / practice -----------------------------------------

@immutable
class CommonMistake {
  const CommonMistake({
    required this.mistake,
    required this.whyTempting,
    required this.fix,
  });

  final String mistake;
  final String whyTempting;
  final String fix;

  Map<String, dynamic> toJson() =>
      {'mistake': mistake, 'whyTempting': whyTempting, 'fix': fix};

  factory CommonMistake.fromJson(Map<String, dynamic> j) => CommonMistake(
        mistake: _s(j['mistake']),
        whyTempting: _s(j['whyTempting']),
        fix: _s(j['fix']),
      );
}

@immutable
class KeyTakeaway {
  const KeyTakeaway({required this.headline, required this.detail});

  final String headline;
  final String? detail;

  bool get isEmpty => headline.isEmpty;

  Map<String, dynamic> toJson() =>
      {'headline': headline, if (detail != null) 'detail': detail};

  factory KeyTakeaway.fromJson(Map<String, dynamic> j) =>
      KeyTakeaway(headline: _s(j['headline']), detail: _sn(j['detail']));
}

@immutable
class PracticeItem {
  const PracticeItem({
    required this.latex,
    required this.plain,
    required this.rung,
    required this.skillHint,
  });

  final String latex;
  final String? plain;

  /// "easier" | "similar" | "harder".
  final String rung;
  final String? skillHint;

  Map<String, dynamic> toJson() => {
        'latex': latex,
        if (plain != null) 'plain': plain,
        'rung': rung,
        if (skillHint != null) 'skillHint': skillHint,
      };

  factory PracticeItem.fromJson(Map<String, dynamic> j) => PracticeItem(
        latex: _s(j['latex']),
        plain: _sn(j['plain']),
        rung: _s(j['rung']),
        skillHint: _sn(j['skillHint']),
      );
}

@immutable
class PracticeLadder {
  const PracticeLadder({
    required this.easier,
    required this.similar,
    required this.harder,
  });

  final PracticeItem easier;
  final PracticeItem similar;
  final PracticeItem harder;

  List<PracticeItem> get rungs => [easier, similar, harder];

  Map<String, dynamic> toJson() => {
        'easier': easier.toJson(),
        'similar': similar.toJson(),
        'harder': harder.toJson(),
      };

  /// Null when any rung is missing (the ladder is only useful complete).
  static PracticeLadder? tryFromJson(Map<String, dynamic> j) {
    final e = j['easier'], s = j['similar'], h = j['harder'];
    if (e is! Map || s is! Map || h is! Map) return null;
    return PracticeLadder(
      easier: PracticeItem.fromJson(Map<String, dynamic>.from(e)),
      similar: PracticeItem.fromJson(Map<String, dynamic>.from(s)),
      harder: PracticeItem.fromJson(Map<String, dynamic>.from(h)),
    );
  }
}

// --- the teaching layer -----------------------------------------------------

@immutable
class TeachingLayer {
  const TeachingLayer({
    required this.depth,
    required this.honestReason,
    required this.header,
    required this.overview,
    required this.concept,
    required this.methodRationale,
    required this.journey,
    required this.translation,
    required this.decompositionPlan,
    required this.approach,
    required this.commonMistakes,
    required this.keyTakeaway,
    required this.practiceLadder,
  });

  /// "full" | "lite" | "concept_only".
  final String depth;

  /// Only set with depth "concept_only": read_failure | uncovered_type | proof |
  /// multi_part.
  final String? honestReason;

  final TeachingHeader header;
  final ProblemOverview overview;
  final ConceptOverview concept;
  final MethodRationale methodRationale;
  final List<JourneyStage> journey;
  final List<String>? translation;
  final List<String>? decompositionPlan;

  /// HONEST MODE (concept_only) only — how to THINK about an unverifiable problem
  /// (recognise it, the key strategy, what's tricky). No worked answer.
  final List<String>? approach;
  final List<CommonMistake> commonMistakes;
  final KeyTakeaway keyTakeaway;
  final PracticeLadder? practiceLadder;

  Map<String, dynamic> toJson() => {
        'depth': depth,
        if (honestReason != null) 'honestReason': honestReason,
        'header': header.toJson(),
        'overview': overview.toJson(),
        'concept': concept.toJson(),
        'methodRationale': methodRationale.toJson(),
        'journey': journey.map((s) => s.toJson()).toList(),
        if (translation != null) 'translation': translation,
        if (decompositionPlan != null) 'decompositionPlan': decompositionPlan,
        if (approach != null) 'approach': approach,
        'commonMistakes': commonMistakes.map((m) => m.toJson()).toList(),
        'keyTakeaway': keyTakeaway.toJson(),
        if (practiceLadder != null) 'practiceLadder': practiceLadder!.toJson(),
      };

  factory TeachingLayer.fromJson(Map<String, dynamic> j) => TeachingLayer(
        depth: _s(j['depth']).isEmpty ? 'lite' : _s(j['depth']),
        honestReason: _sn(j['honestReason']),
        header: TeachingHeader.fromJson(_map(j['header'])),
        overview: ProblemOverview.fromJson(_map(j['overview'])),
        concept: ConceptOverview.fromJson(_map(j['concept'])),
        methodRationale: MethodRationale.fromJson(_map(j['methodRationale'])),
        journey: _objList(j['journey'], JourneyStage.tryFromJson)
            .whereType<JourneyStage>()
            .toList(),
        translation: j['translation'] is List ? _strList(j['translation']) : null,
        decompositionPlan: j['decompositionPlan'] is List
            ? _strList(j['decompositionPlan'])
            : null,
        approach: j['approach'] is List ? _strList(j['approach']) : null,
        commonMistakes: _objList(j['commonMistakes'], CommonMistake.fromJson),
        keyTakeaway: KeyTakeaway.fromJson(_map(j['keyTakeaway'])),
        practiceLadder: j['practiceLadder'] is Map
            ? PracticeLadder.tryFromJson(
                Map<String, dynamic>.from(j['practiceLadder'] as Map))
            : null,
      );

  /// Whether this problem's answer is unverified (honest / conceptual).
  bool get isHonest => depth == 'concept_only';

  /// Nothing worth showing — used so a teaching card renders ONLY when it has
  /// content (graceful degradation for a v1 payload or a sparse enrichment).
  bool get isEmpty =>
      concept.isEmpty &&
      header.learningObjective.isEmpty &&
      keyTakeaway.isEmpty &&
      commonMistakes.isEmpty &&
      methodRationale.isEmpty &&
      overview.isEmpty;
}
