// Practice as a learning system — the reusable per-solved-problem practice set.
//
// Covers: building a set from the teaching ladder (challenge included), the
// JSON round-trip with completion state, the controller lifecycle (create once,
// complete-on-verified-solve with XP through the single ledger, the
// challenge/mixed-review unlock, the mastered state + bonus + milestone), the
// "new set" re-roll (variant bump, old progress dropped, failure keeps the old
// set), and the sync merge policy (union by problem; same roll OR-merges
// completion with earliest-wins; different rolls → newest wins whole).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/features/history/domain/history_entry.dart';
import 'package:matheasy/features/practice/application/practice_progress_controller.dart';
import 'package:matheasy/features/practice_set/application/practice_set_controller.dart';
import 'package:matheasy/features/practice_set/application/practice_set_repository.dart';
import 'package:matheasy/features/practice_set/domain/practice_set.dart';
import 'package:matheasy/features/progress/application/achievement_service.dart'
    show clockProvider;
import 'package:matheasy/features/progress/application/stats_controller.dart';
import 'package:matheasy/features/result/application/functions_teaching_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/domain/teaching_models.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/sync/application/sync_merge.dart';
import 'package:matheasy/features/sync/domain/sync_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _eq = DetectedEquation(
  latex: '2x + 5 = 13',
  confidence: 0.98,
  source: ScanSource.manual,
  kind: EquationKind.linear,
);

const _easier = 'x + 2 = 5';
const _similar = '3x + 1 = 10';
const _harder = '4x - 5 = 15';
const _challenge = '6x + 7 = -11';

TeachingLayer _teachingWithLadder({bool challenge = true}) =>
    TeachingLayer.fromJson({
      'depth': 'full',
      'practiceLadder': {
        'easier': {'latex': _easier, 'rung': 'easier'},
        'similar': {'latex': _similar, 'rung': 'similar'},
        'harder': {'latex': _harder, 'rung': 'harder'},
        if (challenge) 'challenge': {'latex': _challenge, 'rung': 'challenge'},
      },
    });

ResultData _solved({
  DetectedEquation equation = _eq,
  TeachingLayer? teaching,
  bool verified = true,
}) =>
    ResultData(
      equation: equation,
      type: ResultType.linear,
      difficulty: Difficulty.easy,
      answerLatex: 'x = 4',
      verified: verified,
      verifyText: 'Checked ✓',
      tutorIntro: '',
      steps: const [],
      explanations: const [],
      methods: const [],
      practice: const [],
      teaching: teaching,
    );

class _FakeTeachingService implements TeachingService {
  _FakeTeachingService({this.ladder});

  PracticeLadder? ladder;
  int? lastVariant;

  @override
  Future<ResultData?> enrich(ResultData base) async => null;

  @override
  Future<PracticeLadder?> fetchLadder(String latex, {int variant = 0}) async {
    lastVariant = variant;
    return ladder;
  }
}

Future<ProviderContainer> _container({_FakeTeachingService? teaching}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    clockProvider.overrideWithValue(() => DateTime(2026, 8, 6, 12)),
    teachingServiceProvider
        .overrideWithValue(teaching ?? _FakeTeachingService()),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('PracticeSet model', () {
    test('fromLadder maps the rungs in order, challenge separate + locked',
        () {
      final set = PracticeSet.fromLadder(
        sourceKey: historyCacheKey(_eq.latex),
        sourceLatex: _eq.latex,
        sourceType: ResultType.linear,
        ladder: _teachingWithLadder().practiceLadder!,
        nowMillis: 1000,
      );
      expect(set.items.map((i) => i.rung).toList(), const [
        PracticeSetRung.easier,
        PracticeSetRung.similar,
        PracticeSetRung.harder,
      ]);
      expect(set.challenge!.latex, _challenge);
      expect(set.challengeUnlocked, isFalse); // locked until the core is done
      expect(set.nextItem!.latex, _easier);
      expect(set.completedCount, 0);
      expect(set.totalCount, 4);
    });

    test('JSON round-trip preserves completion + unlock state', () {
      var set = PracticeSet.fromLadder(
        sourceKey: 'k',
        sourceLatex: _eq.latex,
        sourceType: ResultType.linear,
        ladder: _teachingWithLadder().practiceLadder!,
        nowMillis: 1000,
      );
      set = set.copyWith(
        items: [for (final i in set.items) i.complete(2000)],
        mixedReviewAtMillis: 3000,
      );
      final revived = PracticeSet.tryFromJson(set.toJson())!;
      expect(revived.coreComplete, isTrue);
      expect(revived.challengeUnlocked, isTrue);
      expect(revived.mixedReviewComplete, isTrue);
      expect(revived.mastered, isFalse); // challenge still pending
      expect(revived.items.first.completedAtMillis, 2000);
      expect(revived.sourceType, ResultType.linear);
    });

    test('tryFromJson rejects malformed records (sync payloads are untrusted)',
        () {
      expect(PracticeSet.tryFromJson(const {}), isNull);
      expect(
        PracticeSet.tryFromJson(const {
          'sourceKey': 'k',
          'sourceLatex': 'x',
          'items': <Object?>[],
        }),
        isNull,
      );
    });
  });

  group('PracticeSetController — the journey', () {
    test('ensureForResult creates the set ONCE and keeps it linked', () async {
      final c = await _container();
      final controller = c.read(practiceSetControllerProvider.notifier);

      controller.ensureForResult(_solved(teaching: _teachingWithLadder()));
      expect(c.read(practiceSetControllerProvider), hasLength(1));

      // Re-solving the same problem must NOT reset progress or re-roll.
      controller.recordSolved(_easier);
      controller.ensureForResult(_solved(teaching: _teachingWithLadder()));
      final set = c.read(practiceSetControllerProvider).single;
      expect(set.completedCount, 1);
    });

    test('no ladder / unverified → no set', () async {
      final c = await _container();
      final controller = c.read(practiceSetControllerProvider.notifier);
      controller.ensureForResult(_solved());
      controller.ensureForResult(
          _solved(teaching: _teachingWithLadder(), verified: false));
      expect(c.read(practiceSetControllerProvider), isEmpty);
    });

    test(
        'a verified solve completes its rung and pays rung XP into the one ledger',
        () async {
      final c = await _container();
      final controller = c.read(practiceSetControllerProvider.notifier);
      controller.ensureForResult(_solved(teaching: _teachingWithLadder()));
      final xpBefore = c.read(practiceProgressControllerProvider).totalXp;

      // The editor re-renders the problem slightly differently — the canonical
      // key (not the raw string) is the match.
      controller.recordSolved('x+2=5');

      final set = c.read(practiceSetControllerProvider).single;
      expect(set.items.first.completed, isTrue);
      expect(set.items[1].completed, isFalse);
      expect(
        c.read(practiceProgressControllerProvider).totalXp - xpBefore,
        PracticeSetRung.easier.xp,
      );
    });

    test('an unrelated solve changes nothing', () async {
      final c = await _container();
      final controller = c.read(practiceSetControllerProvider.notifier);
      controller.ensureForResult(_solved(teaching: _teachingWithLadder()));
      controller.recordSolved('y^2 - 9 = 0');
      expect(c.read(practiceSetControllerProvider).single.completedCount, 0);
    });

    test(
        'core → challenge unlock → mixed review → MASTERED (bonus XP + milestone)',
        () async {
      final c = await _container();
      final controller = c.read(practiceSetControllerProvider.notifier);
      controller.ensureForResult(_solved(teaching: _teachingWithLadder()));

      controller.recordSolved(_easier);
      controller.recordSolved(_similar);
      var set = c.read(practiceSetControllerProvider).single;
      expect(set.coreComplete, isFalse);
      expect(set.nextItem!.latex, _harder);

      controller.recordSolved(_harder);
      set = c.read(practiceSetControllerProvider).single;
      expect(set.coreComplete, isTrue);
      expect(set.challengeUnlocked, isTrue);
      expect(set.nextItem!.latex, _challenge); // the stretch goal surfaces

      final xpBefore = c.read(practiceProgressControllerProvider).totalXp;
      controller.recordSolved(_challenge);
      controller.markMixedReviewCompleted(set.sourceKey);

      set = c.read(practiceSetControllerProvider).single;
      expect(set.journeyComplete, isTrue);
      expect(set.mastered, isTrue);
      // Challenge XP + the mastered bonus, all through the single ledger.
      expect(
        c.read(practiceProgressControllerProvider).totalXp - xpBefore,
        PracticeSetRung.challenge.xp + PracticeSetController.masteredBonusXp,
      );
      expect(
        c
            .read(statsControllerProvider)
            .recentActivity
            .map((a) => a.title),
        contains('Topic mastered'),
      );
    });

    test('mastering is once-only (no double bonus)', () async {
      final c = await _container();
      final controller = c.read(practiceSetControllerProvider.notifier);
      controller.ensureForResult(_solved(teaching: _teachingWithLadder()));
      controller.recordSolved(_easier);
      controller.recordSolved(_similar);
      controller.recordSolved(_harder);
      controller.recordSolved(_challenge);
      controller.markMixedReviewCompleted(historyCacheKey(_eq.latex));
      final xpAfter = c.read(practiceProgressControllerProvider).totalXp;
      controller.markMixedReviewCompleted(historyCacheKey(_eq.latex));
      controller.recordSolved(_challenge);
      expect(c.read(practiceProgressControllerProvider).totalXp, xpAfter);
    });

    test('requestNewSet re-rolls at the next variant, dropping old progress',
        () async {
      final fresh = PracticeLadder.tryFromJson(const {
        'easier': {'latex': 'x + 9 = 11', 'rung': 'easier'},
        'similar': {'latex': '2x + 1 = 7', 'rung': 'similar'},
        'harder': {'latex': '5x - 2 = 13', 'rung': 'harder'},
      });
      final teaching = _FakeTeachingService(ladder: fresh);
      final c = await _container(teaching: teaching);
      final controller = c.read(practiceSetControllerProvider.notifier);
      controller.ensureForResult(_solved(teaching: _teachingWithLadder()));
      controller.recordSolved(_easier);

      final ok =
          await controller.requestNewSet(historyCacheKey(_eq.latex));
      expect(ok, isTrue);
      expect(teaching.lastVariant, 1); // the next deterministic roll
      final set = c.read(practiceSetControllerProvider).single;
      expect(set.variant, 1);
      expect(set.completedCount, 0); // a NEW set, fresh journey
      expect(set.items.first.latex, 'x + 9 = 11');
    });

    test('requestNewSet failure keeps the old set untouched', () async {
      final c = await _container(teaching: _FakeTeachingService());
      final controller = c.read(practiceSetControllerProvider.notifier);
      controller.ensureForResult(_solved(teaching: _teachingWithLadder()));
      controller.recordSolved(_easier);

      final ok =
          await controller.requestNewSet(historyCacheKey(_eq.latex));
      expect(ok, isFalse);
      final set = c.read(practiceSetControllerProvider).single;
      expect(set.variant, 0);
      expect(set.completedCount, 1);
    });

    test('persists across a fresh controller (the reusable set)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      ProviderContainer make() => ProviderContainer(overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            clockProvider.overrideWithValue(() => DateTime(2026, 8, 6)),
            teachingServiceProvider.overrideWithValue(_FakeTeachingService()),
          ]);

      final first = make();
      first
          .read(practiceSetControllerProvider.notifier)
          .ensureForResult(_solved(teaching: _teachingWithLadder()));
      first.read(practiceSetControllerProvider.notifier).recordSolved(_easier);
      // Let the unawaited repository save flush.
      await Future<void>.delayed(Duration.zero);
      first.dispose();

      final second = make();
      addTearDown(second.dispose);
      final revived = second.read(practiceSetControllerProvider).single;
      expect(revived.sourceKey, historyCacheKey(_eq.latex));
      expect(revived.items.first.completed, isTrue);
    });

    test('continuePracticeSetProvider surfaces the actionable set', () async {
      final c = await _container();
      final controller = c.read(practiceSetControllerProvider.notifier);
      expect(c.read(continuePracticeSetProvider), isNull);

      controller.ensureForResult(_solved(teaching: _teachingWithLadder()));
      expect(c.read(continuePracticeSetProvider)!.sourceKey,
          historyCacheKey(_eq.latex));

      // Finish everything → nothing left to continue.
      controller.recordSolved(_easier);
      controller.recordSolved(_similar);
      controller.recordSolved(_harder);
      controller.recordSolved(_challenge);
      controller.markMixedReviewCompleted(historyCacheKey(_eq.latex));
      expect(c.read(continuePracticeSetProvider), isNull);
    });

    test('removeFor and clear drop linked sets', () async {
      final c = await _container();
      final controller = c.read(practiceSetControllerProvider.notifier);
      controller.ensureForResult(_solved(teaching: _teachingWithLadder()));
      controller.removeFor(historyCacheKey(_eq.latex));
      expect(c.read(practiceSetControllerProvider), isEmpty);
    });
  });

  group('LocalPracticeSetRepository', () {
    test('corrupt blob → empty, never a crash', () async {
      SharedPreferences.setMockInitialValues(
          {'practice.sets': 'not json at all {'});
      final store = PreferencesStore(await SharedPreferences.getInstance());
      expect(LocalPracticeSetRepository(store).load(), isEmpty);
    });
  });

  group('SyncMerge — practiceSets', () {
    Map<String, dynamic> setJson(
      String key, {
      int variant = 0,
      int createdAt = 1000,
      int? easierDoneAt,
      int? masteredAt,
    }) =>
        {
          'sourceKey': key,
          'sourceLatex': '2x + 5 = 13',
          'sourceType': 'linear',
          'variant': variant,
          'createdAtMillis': createdAt,
          'items': [
            {
              'latex': _easier,
              'rung': 'easier',
              'completedAtMillis': ?easierDoneAt,
            },
            {'latex': _similar, 'rung': 'similar'},
            {'latex': _harder, 'rung': 'harder'},
          ],
          'masteredAtMillis': ?masteredAt,
        };

    test('union: a set on either side survives', () {
      final merged = SyncMerge.merge(
        SyncDomain.practiceSets,
        local: {
          'sets': [setJson('a')]
        },
        remote: {
          'sets': [setJson('b')]
        },
        remoteNewer: true,
      );
      expect(merged['sets'] as List, hasLength(2));
    });

    test('same roll → completion OR-merges, earliest timestamp wins', () {
      final merged = SyncMerge.merge(
        SyncDomain.practiceSets,
        local: {
          'sets': [setJson('a', easierDoneAt: 5000)]
        },
        remote: {
          'sets': [setJson('a', easierDoneAt: 3000, masteredAt: 9000)]
        },
        remoteNewer: false,
      );
      final sets = merged['sets'] as List;
      final a = Map<String, dynamic>.from(sets.single as Map);
      final items = a['items'] as List;
      expect(
          Map<String, dynamic>.from(items.first as Map)['completedAtMillis'],
          3000); // a completion can't be un-earned; earliest wins
      expect(a['masteredAtMillis'], 9000); // one-sided flags survive
    });

    test('different rolls of the same problem → the newest roll wins whole',
        () {
      final merged = SyncMerge.merge(
        SyncDomain.practiceSets,
        local: {
          'sets': [setJson('a', easierDoneAt: 1)]
        },
        remote: {
          'sets': [setJson('a', variant: 1, createdAt: 2000)]
        },
        remoteNewer: false,
      );
      final a = Map<String, dynamic>.from(
          (merged['sets'] as List).single as Map);
      expect(a['variant'], 1);
      final items = a['items'] as List;
      expect(
          Map<String, dynamic>.from(items.first as Map)
              .containsKey('completedAtMillis'),
          isFalse); // the old roll's progress does not leak into the new one
    });
  });
}
