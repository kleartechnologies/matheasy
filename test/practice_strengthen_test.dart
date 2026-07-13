// "Strengthen these" is fully scan-history driven — no placeholder topics, no
// fabricated accuracy. A new user (no scans) sees nothing; a returning user
// sees their scanned topics weakest-first with real solved counts, each row
// launching a topic-specific practice session.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/history/application/history_controller.dart';
import 'package:matheasy/features/history/domain/history_entry.dart';
import 'package:matheasy/features/practice/application/practice_dashboard_controller.dart';
import 'package:matheasy/features/practice/domain/practice_dashboard.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';
import 'package:matheasy/features/practice/presentation/sections/practice_weak_topics.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedHistory extends HistoryController {
  _FixedHistory(this.entries);
  final List<HistoryEntry> entries;
  @override
  List<HistoryEntry> build() => entries;
}

ResultData _result(ResultType type, {required bool verified}) => ResultData(
      equation: const DetectedEquation(
        latex: 'x + 1 = 2',
        confidence: 1,
        source: ScanSource.camera,
        kind: EquationKind.linear,
      ),
      type: type,
      difficulty: Difficulty.medium,
      answerLatex: verified ? 'x = 1' : '',
      verified: verified,
      verifyText: '',
      tutorIntro: '',
      steps: const [],
      explanations: const [],
      methods: const [],
      practice: const [],
    );

HistoryEntry _scan(ResultType type, {bool verified = true, required int ts}) =>
    HistoryEntry(
      canonicalKey: 'k$ts-${type.name}',
      timestampMillis: ts,
      result: _result(type, verified: verified),
    );

Future<ProviderContainer> _dashboard(List<HistoryEntry> history) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    historyControllerProvider.overrideWith(() => _FixedHistory(history)),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('Strengthen these — scan-history driven', () {
    test('a new user with NO scan history gets no weak topics (section hidden, '
        'no fabricated Word Problems / Trigonometry placeholders)', () async {
      final c = await _dashboard(const []);
      expect(c.read(practiceDashboardProvider).weakTopics, isEmpty);
    });

    test('builds from real scans, weakest-first, with real solved counts '
        '(spec example: Algebra×2 + Fractions×1)', () async {
      final c = await _dashboard([
        _scan(ResultType.linear, ts: 1), // → Algebra
        _scan(ResultType.linear, ts: 2), // → Algebra
        _scan(ResultType.fraction, ts: 3), // → Fractions
      ]);
      final weak = c.read(practiceDashboardProvider).weakTopics;
      // Fractions (1 solved) before Algebra (2 solved).
      expect(weak.map((w) => w.topic).toList(),
          [PracticeTopic.fractions, PracticeTopic.algebra]);
      expect(weak.map((w) => w.solvedCount).toList(), [1, 2]);
      expect(weak.map((w) => w.correctCount).toList(), [1, 2]);
    });

    test('ranks a lower verified-rate topic first (a couldn\'t-verify scan '
        'drags accuracy down)', () async {
      final c = await _dashboard([
        _scan(ResultType.linear, ts: 1), // Algebra, verified
        _scan(ResultType.linear, ts: 2), // Algebra, verified
        _scan(ResultType.trigonometry, verified: false, ts: 3), // Trig, 0/1
      ]);
      final weak = c.read(practiceDashboardProvider).weakTopics;
      expect(weak.first.topic, PracticeTopic.trigonometry); // accuracy 0 → first
      expect(weak.first.solvedCount, 1);
      expect(weak.first.correctCount, 0);
    });
  });

  group('PracticeWeakTopics widget', () {
    testWidgets('renders "Solved N problems" (never a % accuracy) and launches '
        'the tapped topic', (tester) async {
      PracticeTopic? tapped;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PracticeWeakTopics(
            topics: const [
              WeakTopicView(
                  topic: PracticeTopic.fractions, solvedCount: 1, correctCount: 1),
              WeakTopicView(
                  topic: PracticeTopic.algebra, solvedCount: 2, correctCount: 2),
            ],
            onStartTopic: (t) => tapped = t,
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('Strengthen these'), findsOneWidget);
      expect(find.text('Solved 1 problem'), findsOneWidget);
      expect(find.text('Solved 2 problems'), findsOneWidget);
      expect(find.textContaining('% accuracy'), findsNothing); // no fake data

      await tester.tap(find.text('Fractions'));
      expect(tapped, PracticeTopic.fractions); // opens topic-specific practice
    });
  });
}
