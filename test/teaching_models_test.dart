// Phase 2 — the client teaching models + the mapper's v2 parsing. Verifies that
// a v2 payload (with `teaching`) is parsed in full, that a v1 payload is
// byte-identical to today's ResultData (back-compat), that every parser is TOTAL
// (unknown enum/category never throws), and that the layer round-trips through
// history caching.

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/application/functions_solver_service.dart';
import 'package:matheasy/features/result/application/functions_teaching_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/domain/teaching_models.dart';
import 'package:matheasy/features/result/domain/visual_models.dart'
    show ProblemDifficulty;
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

const _equation = DetectedEquation(
  latex: 'x^2 - 5x + 6 = 0',
  confidence: 0.98,
  source: ScanSource.camera,
  kind: EquationKind.quadratic,
);

/// A verified quadratic payload carrying a v2 teaching layer (spec §4.2, trimmed).
Map<String, dynamic> _teachedPayload() => {
      'schemaVersion': 2,
      'problemLatex': 'x^2 - 5x + 6 = 0',
      'problemType': 'quadratic_equation',
      'verified': true,
      'finalAnswer': {'latex': r'x_1 = 2,\; x_2 = 3', 'plain': 'x = 2 or x = 3'},
      'graph': null,
      'methods': [
        {
          'id': 'factoring',
          'name': 'Factoring',
          'examPick': true,
          'steps': [
            {
              'expression': 'x^2 - 5x + 6 = 0',
              'operation': 'Start with the equation',
              'why': 'We begin with the quadratic exactly as given.',
            },
            {
              'expression': '(x - 2)(x - 3) = 0',
              'operation': 'Factor into two brackets',
              'operationSymbol': 'factor',
              'why': 'Two numbers multiply to the constant and add to the middle.',
              'rule': 'Sum-product factoring',
              'selfExplainPrompt': 'Which pair multiplies to 6 and adds to -5?',
              'pivotal': true,
            },
          ],
        },
      ],
      'teaching': {
        'depth': 'lite',
        'header': {
          'category': 'equations',
          'subcategory': 'Quadratic equation (factorable)',
          'difficulty': 'secondary',
          'learningObjective': 'Solve a factorable quadratic with the zero-product rule.',
          'methodChosen': 'Factoring',
          'whyMethodChosen': 'The constant factors into small whole numbers.',
        },
        'overview': {
          'asked': 'Find every value of x that makes the expression zero.',
          'goal': 'Rewrite as a product of two factors, then set each to zero.',
          'givens': ['x^2 - 5x + 6 = 0'],
          'predictionPrompt': 'One answer, two, or none?',
        },
        'concept': {
          'body': 'A quadratic is an equation where the variable is squared.',
          'definedTerms': [
            {'term': 'root', 'plain': 'a value of x that makes the expression zero'},
          ],
        },
        'methodRationale': {
          'alternatives': [
            {'name': 'Quadratic Formula', 'whenBetter': 'When it does not factor.'},
          ],
        },
        'journey': [
          {'id': 'understand', 'stepIndices': <int>[]},
          {'id': 'apply', 'stepIndices': [1]},
          {'id': 'simplify', 'stepIndices': [2, 3]},
          // An UNKNOWN stage id must be dropped, never throw.
          {'id': 'time_travel', 'stepIndices': [9]},
        ],
        'commonMistakes': [
          {
            'mistake': 'Getting the signs wrong.',
            'whyTempting': 'Both roots are positive.',
            'fix': 'Expand the brackets back and check the middle term.',
          },
        ],
        'keyTakeaway': {
          'headline': 'See a factorable quadratic? Factor, then zero each bracket.',
          'detail': 'The roots fall straight out.',
        },
        'practiceLadder': {
          'easier': {'latex': 'x^2 - 3x + 2 = 0', 'rung': 'easier', 'skillHint': 'quad'},
          'similar': {'latex': 'x^2 - 7x + 12 = 0', 'rung': 'similar'},
          'harder': {'latex': '2x^2 - 7x + 3 = 0', 'rung': 'harder'},
        },
      },
    };

/// The SAME payload with the teaching layer stripped — a v1 server response.
Map<String, dynamic> _v1Payload() {
  final p = _teachedPayload();
  p.remove('teaching');
  p.remove('schemaVersion');
  // Strip the inline v2 step fields too (a real v1 payload never had them).
  for (final m in p['methods'] as List) {
    for (final s in (m as Map)['steps'] as List) {
      (s as Map)
        ..remove('operationSymbol')
        ..remove('rule')
        ..remove('selfExplainPrompt')
        ..remove('pivotal');
    }
  }
  return p;
}

void main() {
  group('SolveResponseMapper — v2 teaching layer', () {
    test('parses the full teaching layer from a v2 payload', () {
      final r = SolveResponseMapper.toResultData(_equation, _teachedPayload());
      final t = r.teaching;
      expect(t, isNotNull);
      expect(t!.depth, 'lite');
      expect(t.isHonest, isFalse);
      // Header.
      expect(t.header.category, 'equations');
      expect(t.header.categoryLabel, 'Equations');
      expect(t.header.difficulty, ProblemDifficulty.secondary);
      expect(t.header.methodChosen, 'Factoring');
      // Concept + overview.
      expect(t.concept.body, isNotEmpty);
      expect(t.concept.definedTerms.single.term, 'root');
      expect(t.overview.givens, ['x^2 - 5x + 6 = 0']);
      expect(t.overview.predictionPrompt, isNotEmpty);
      // Journey: the unknown "time_travel" stage is DROPPED, not thrown.
      expect(t.journey.map((s) => s.id.name),
          containsAll(<String>['understand', 'apply', 'simplify']));
      expect(t.journey.any((s) => s.id.name == 'time_travel'), isFalse);
      expect(t.journey.firstWhere((s) => s.id == JourneyStageId.apply).stepIndices,
          [1]);
      // Mistakes + takeaway + ladder.
      expect(t.commonMistakes.single.fix, isNotEmpty);
      expect(t.keyTakeaway.headline, isNotEmpty);
      expect(t.practiceLadder, isNotNull);
      expect(t.practiceLadder!.harder.latex, '2x^2 - 7x + 3 = 0');
    });

    test('folds enriched step fields onto the Solution steps', () {
      final r = SolveResponseMapper.toResultData(_equation, _teachedPayload());
      final pivotal = r.steps[1];
      expect(pivotal.pivotal, isTrue);
      // operationSymbol becomes the operation chip when present.
      expect(pivotal.operationLabel, 'factor');
      expect(pivotal.rule, 'Sum-product factoring');
      expect(pivotal.selfExplainPrompt, isNotEmpty);
      // A non-enriched step keeps v1 behaviour (chip = operation label).
      expect(r.steps[0].pivotal, isFalse);
      expect(r.steps[0].operationLabel, 'Start with the equation');
      expect(r.steps[0].rule, isNull);
    });

    test('a v1 payload yields teaching == null and byte-identical steps', () {
      final r = SolveResponseMapper.toResultData(_equation, _v1Payload());
      expect(r.teaching, isNull);
      // Steps unchanged: chip = operation, no v2 fields.
      expect(r.steps, hasLength(2));
      expect(r.steps[1].operationLabel, 'Factor into two brackets');
      expect(r.steps[1].pivotal, isFalse);
      expect(r.steps[1].rule, isNull);
      expect(r.steps[1].selfExplainPrompt, isNull);
      expect(r.answerLatex, r'x_1 = 2,\; x_2 = 3');
      expect(r.verified, isTrue);
    });

    test('teaching survives a history-cache round-trip (toJson/fromJson)', () {
      final r = SolveResponseMapper.toResultData(_equation, _teachedPayload());
      final restored = ResultData.fromJson(r.toJson());
      expect(restored.teaching, isNotNull);
      expect(restored.teaching!.header.methodChosen, 'Factoring');
      expect(restored.teaching!.practiceLadder!.harder.latex, '2x^2 - 7x + 3 = 0');
      expect(restored.steps[1].pivotal, isTrue);
      expect(restored.steps[1].rule, 'Sum-product factoring');
    });
  });

  group('teaching parsers are TOTAL (never throw)', () {
    test('unknown category title-cases instead of throwing', () {
      expect(teachingCategoryLabel('equations'), 'Equations');
      expect(teachingCategoryLabel('linear_algebra'), 'Linear Algebra');
      expect(teachingCategoryLabel('brand_new_topic_v9'), 'Brand New Topic V9');
      expect(teachingCategoryLabel(''), 'Maths');
    });

    test('unknown difficulty falls back to secondary', () {
      expect(teachingDifficulty('university'), ProblemDifficulty.university);
      expect(teachingDifficulty('galactic'), ProblemDifficulty.secondary);
    });

    test('an all-empty teaching object parses to an isEmpty layer', () {
      final t = TeachingLayer.fromJson(const {});
      expect(t.isEmpty, isTrue);
      expect(t.depth, 'lite'); // sane default
      expect(t.journey, isEmpty);
      expect(t.practiceLadder, isNull);
    });

    test('an honest concept_only layer is flagged', () {
      final t = TeachingLayer.fromJson(const {
        'depth': 'concept_only',
        'honestReason': 'proof',
        'concept': {'body': 'A proof argues, it does not compute.'},
      });
      expect(t.isHonest, isTrue);
      expect(t.honestReason, 'proof');
      expect(t.isEmpty, isFalse);
    });

    test('SolutionStep.fromJson is total on wrong-typed cache fields', () {
      // A foreign / hand-edited synced blob with wrong types must degrade, not throw.
      final s = SolutionStep.fromJson(const {
        'title': 42, // number where a String is expected
        'resultLatex': ['x'], // list
        'detail': null,
        'pivotal': 'yes', // string where a bool is expected
        'rule': 7, // number
      });
      expect(s.title, '');
      expect(s.resultLatex, '');
      expect(s.detail, '');
      expect(s.pivotal, isFalse);
      expect(s.rule, isNull);
    });

    test('a concept with only definedTerms (no body) is NOT empty', () {
      // The jargon chips must not be silently dropped (review #3).
      final t = TeachingLayer.fromJson(const {
        'concept': {
          'definedTerms': [
            {'term': 'root', 'plain': 'a value that makes it zero'},
          ],
        },
      });
      expect(t.concept.body, isEmpty);
      expect(t.concept.definedTerms, hasLength(1));
      expect(t.concept.isEmpty, isFalse);
    });

    test('a partial practice ladder (missing a rung) is dropped', () {
      final t = TeachingLayer.fromJson(const {
        'practiceLadder': {
          'easier': {'latex': 'x=1', 'rung': 'easier'},
          // similar + harder missing → whole ladder null (only useful complete).
        },
      });
      expect(t.practiceLadder, isNull);
    });
  });

  group('progressive teaching fetch (enrichTeaching)', () {
    // The base result as `solve` now returns it — fast, no teaching.
    ResultData base() => SolveResponseMapper.toResultData(_equation, _v1Payload());

    // What the separate `enrichTeaching` callable returns: { teaching, methods }.
    Map<String, dynamic> enrichResponse() => {
          'teaching': _teachedPayload()['teaching'],
          'methods': _teachedPayload()['methods'],
        };

    test('mergeTeaching attaches the layer + the enriched steps', () {
      final merged = SolveResponseMapper.mergeTeaching(base(), enrichResponse());
      expect(merged, isNotNull);
      expect(merged!.teaching, isNotNull);
      expect(merged.teaching!.header.methodChosen, 'Factoring');
      // Steps are replaced by the enriched ones (pivotal + rule now present).
      expect(merged.steps[1].pivotal, isTrue);
      expect(merged.steps[1].rule, 'Sum-product factoring');
    });

    test('mergeTeaching returns null when the response has no teaching', () {
      expect(
        SolveResponseMapper.mergeTeaching(base(), const {'teaching': null}),
        isNull,
      );
    });

    test('FunctionsTeachingService.enrich merges via the callable', () async {
      final service = FunctionsTeachingService((name, data) async {
        expect(name, 'enrichTeaching');
        expect(data['latex'], _equation.latex);
        return enrichResponse();
      });
      final merged = await service.enrich(base());
      expect(merged?.teaching, isNotNull);
      expect(merged!.steps[1].rule, 'Sum-product factoring');
    });

    test('NoTeachingService yields no teaching (guests / offline)', () async {
      expect(await const NoTeachingService().enrich(base()), isNull);
    });
  });
}
