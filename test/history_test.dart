// Step 7 — history + caching (§8).
//
// Covers: the collision-safe cache-key normalizer (both directions), the local
// HistoryRepository (record/dedupe/order/remove/clear), the union merge policy
// (offline solve survives, cloud-only appears, same key → newest by timestamp),
// the read-through cache in ResultController (a re-open never re-solves and an
// unverified result is never cached), full ResultData serialization round-trip,
// and the COPPA guarantee that no image is ever persisted.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/features/history/application/history_controller.dart';
import 'package:matheasy/features/history/application/history_repository.dart';
import 'package:matheasy/features/history/domain/history_entry.dart';
import 'package:matheasy/features/progress/application/achievement_service.dart'
    show clockProvider;
import 'package:matheasy/features/result/application/result_controller.dart';
import 'package:matheasy/features/result/application/solver_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/sync/application/sync_merge.dart';
import 'package:matheasy/features/sync/domain/sync_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _quadratic = DetectedEquation(
  latex: r'5x^2 + 3x - 2 = 0',
  confidence: 0.95,
  source: ScanSource.camera,
  kind: EquationKind.quadratic,
);

ResultData _verified(DetectedEquation equation, {String answer = 'x = -1'}) =>
    ResultData(
      equation: equation,
      type: ResultType.quadratic,
      difficulty: Difficulty.medium,
      answerLatex: answer,
      answerPlain: answer,
      verifyText: 'Checked ✓',
      tutorIntro: "Here's how.",
      steps: [
        const SolutionStep(
            title: 'Factor', resultLatex: '(5x-2)(x+1)=0', detail: 'group'),
      ],
      explanations: const [],
      methods: [
        const MethodSolution(
          name: 'Factoring',
          subtitle: '',
          description: '',
          advantages: [],
          whenToUse: '',
          steps: ['(5x-2)(x+1)=0'],
          recommended: true,
          stepperSteps: [
            SolutionStep(
                title: 'Factor', resultLatex: '(5x-2)(x+1)=0', detail: 'group'),
          ],
        ),
      ],
      practice: const [],
      graph: const GraphData(
        kind: 'function',
        expression: '5x^2 + 3x - 2',
        keyPoints: [
          GraphKeyPoint(label: 'root', x: -1, y: 0),
          GraphKeyPoint(label: 'vertex', x: -0.3, y: -2.45),
        ],
        curve: [Offset(-2, 12), Offset(-1, 0), Offset(0, -2), Offset(1, 6)],
      ),
    );

ResultData _unverified(DetectedEquation equation) => ResultData(
      equation: equation,
      type: ResultType.trigonometry,
      difficulty: Difficulty.medium,
      answerLatex: '',
      verified: false,
      verifyText: "couldn't verify",
      tutorIntro: '',
      steps: const [],
      explanations: const [],
      methods: const [],
      practice: const [],
    );

Future<PreferencesStore> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return PreferencesStore(await SharedPreferences.getInstance());
}

/// A solver that counts how often it's asked to solve — proves a cache hit
/// never re-solves.
class _CountingSolver implements SolverService {
  _CountingSolver(this._build);
  final ResultData Function(DetectedEquation) _build;
  int calls = 0;

  @override
  Future<ResultData> solve(DetectedEquation equation) async {
    calls++;
    return _build(equation);
  }
}

void main() {
  group('historyCacheKey — collision-safe both ways', () {
    test('same problem, different rendering → same key', () {
      // The braced vs bare exponent (the §8 example).
      expect(historyCacheKey('5x^2'), historyCacheKey('5x^{2}'));
      // \left \right are rendering-only.
      expect(historyCacheKey(r'\left(x+1\right)^2'), historyCacheKey('(x+1)^2'));
      // \cdot and \times both mean multiply.
      expect(historyCacheKey(r'2\cdot3'), historyCacheKey(r'2\times3'));
      // Whitespace is insignificant between these tokens.
      expect(historyCacheKey('2x + 5 = 13'), historyCacheKey('2x+5=13'));
      // Subscripts unwrap the same way.
      expect(historyCacheKey('x_{1}'), historyCacheKey('x_1'));
    });

    test('genuinely different problems → different keys', () {
      expect(historyCacheKey('x^2 + 1 = 0') == historyCacheKey('x^2 - 1 = 0'),
          isFalse);
      expect(historyCacheKey('5x^2') == historyCacheKey('5x^3'), isFalse);
      expect(historyCacheKey('2x+3=7') == historyCacheKey('2x+3=8'), isFalse);
      // A multi-char braced group is NOT unwrapped: x^{10} (x to the 10th) must
      // not collapse into x^10 (which reads as x^1 · 0).
      expect(historyCacheKey('x^{10}') == historyCacheKey('x^10'), isFalse);
    });
  });

  group('LocalHistoryRepository', () {
    test('records, looks up (across rendering), and orders most-recent-first',
        () async {
      final repo = LocalHistoryRepository(await _prefs());
      await repo.record(_verified(_quadratic), nowMillis: 1000);

      // Lookup with a differently-braced rendering still hits.
      const braced = DetectedEquation(
        latex: r'5x^{2} + 3x - 2 = 0',
        confidence: 1,
        source: ScanSource.manual,
        kind: EquationKind.quadratic,
      );
      expect(repo.lookup(braced.latex), isNotNull);
      expect(repo.lookup('totally different = 0'), isNull);

      // A second, newer problem sorts ahead of the first.
      const linear = DetectedEquation(
        latex: '2x + 5 = 13',
        confidence: 1,
        source: ScanSource.camera,
        kind: EquationKind.linear,
      );
      await repo.record(_verified(linear), nowMillis: 2000);
      final all = repo.load();
      expect(all, hasLength(2));
      expect(all.first.equation.latex, '2x + 5 = 13'); // newest first
    });

    test('re-recording the same problem dedupes and refreshes it', () async {
      final repo = LocalHistoryRepository(await _prefs());
      await repo.record(_verified(_quadratic, answer: 'old'), nowMillis: 1000);
      await repo.record(_verified(_quadratic, answer: 'new'), nowMillis: 5000);

      final all = repo.load();
      expect(all, hasLength(1)); // deduped by canonical key
      expect(all.first.result.answerLatex, 'new'); // newest kept
      expect(all.first.timestampMillis, 5000);
    });

    test('remove deletes one; clear empties', () async {
      final repo = LocalHistoryRepository(await _prefs());
      await repo.record(_verified(_quadratic), nowMillis: 1000);
      final key = historyCacheKey(_quadratic.latex);

      await repo.remove(key);
      expect(repo.load(), isEmpty);

      await repo.record(_verified(_quadratic), nowMillis: 2000);
      await repo.clear();
      expect(repo.load(), isEmpty);
    });
  });

  group('privacy — no image is ever persisted (COPPA)', () {
    test('the serialized entry carries LaTeX + solution only, no image bytes',
        () async {
      final entry = HistoryEntry(
        canonicalKey: historyCacheKey(_quadratic.latex),
        result: _verified(_quadratic),
        timestampMillis: 1000,
      );
      final raw = jsonEncode(entry.toJson()).toLowerCase();
      expect(raw, contains('5x^2')); // the problem is stored
      expect(raw, isNot(contains('image')));
      expect(raw, isNot(contains('bytes')));
      expect(raw, isNot(contains('base64')));
      expect(raw, isNot(contains('jpeg')));
    });
  });

  group('ResultData serialization round-trip', () {
    test('toJson → fromJson preserves the answer, methods and graph', () {
      final restored = ResultData.fromJson(jsonDecode(
          jsonEncode(_verified(_quadratic).toJson())) as Map<String, dynamic>);

      expect(restored.equation, _quadratic);
      expect(restored.verified, isTrue);
      expect(restored.answerLatex, 'x = -1');
      expect(restored.methods, hasLength(1));
      expect(restored.methods.first.recommended, isTrue);
      expect(restored.methods.first.stepperSteps.first.title, 'Factor');
      expect(restored.graph, isNotNull);
      expect(restored.graph!.keyPoints, hasLength(2));
      expect(restored.graph!.keyPoints.last.label, 'vertex');
      expect(restored.graph!.curve, hasLength(4));
      expect(restored.graph!.curve[1], const Offset(-1, 0));
    });
  });

  group('SyncMerge.history — union, offline-survives, newest-wins', () {
    test('unions both sides; same key keeps the newer by timestamp', () {
      final merged = SyncMerge.merge(
        SyncDomain.history,
        // Local has an offline solve of A (newer than the cloud's copy of A).
        local: {
          'entries': [
            {
              'canonicalKey': 'a',
              'timestampMillis': 100,
              'result': {'tag': 'local-A'},
            },
          ],
        },
        remote: {
          'entries': [
            {
              'canonicalKey': 'b',
              'timestampMillis': 200,
              'result': {'tag': 'cloud-B'},
            },
            {
              'canonicalKey': 'a',
              'timestampMillis': 50, // older copy of A
              'result': {'tag': 'cloud-A-old'},
            },
          ],
        },
        remoteNewer: true,
      );

      final entries = merged['entries'] as List;
      // Union: both A and B survive (offline-local A is not wiped; cloud-only B
      // appears locally).
      expect(entries, hasLength(2));
      // Most-recent-first: B (200) then A (100).
      expect((entries.first as Map)['canonicalKey'], 'b');
      // Same-key conflict resolved by timestamp → local's newer A wins.
      final a = entries.firstWhere((e) => (e as Map)['canonicalKey'] == 'a');
      expect((a as Map)['timestampMillis'], 100);
      expect((a['result'] as Map)['tag'], 'local-A');
    });
  });

  group('ResultController read-through cache (§8)', () {
    test('a re-open reads the cache — no second solve(), and it is recorded',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final solver = _CountingSolver(_verified);
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        solverServiceProvider.overrideWithValue(solver),
        clockProvider.overrideWithValue(() => DateTime(2026, 7, 12, 9)),
      ]);
      addTearDown(c.dispose);

      final first = await c.read(resultControllerProvider(_quadratic).future);
      expect(solver.calls, 1);
      expect(first.answerLatex, 'x = -1');
      // Recorded to history (visible to Home / History screen).
      expect(c.read(historyControllerProvider), hasLength(1));

      // Re-open the same problem → served from cache, solver NOT called again.
      c.invalidate(resultControllerProvider(_quadratic));
      final again = await c.read(resultControllerProvider(_quadratic).future);
      expect(solver.calls, 1); // still 1 — free re-open
      expect(again.answerLatex, first.answerLatex);
      expect(again.graph!.curve, hasLength(4)); // full result rehydrated
    });

    test('an unverified (couldn\'t-verify) result is never cached', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final solver = _CountingSolver(_unverified);
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        solverServiceProvider.overrideWithValue(solver),
        clockProvider.overrideWithValue(() => DateTime(2026, 7, 12, 9)),
      ]);
      addTearDown(c.dispose);

      final result = await c.read(resultControllerProvider(_quadratic).future);
      expect(result.verified, isFalse);
      expect(c.read(historyControllerProvider), isEmpty); // not stored

      // Re-solving DOES call the solver again (no cached failure to short it).
      c.invalidate(resultControllerProvider(_quadratic));
      await c.read(resultControllerProvider(_quadratic).future);
      expect(solver.calls, 2);
    });
  });
}
