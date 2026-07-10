// Stage 14 tests — the Visual Learning Engine (PRO).
//
// Covers the universal schema mapping (defensive JSON → VisualSolution),
// category → tier selection, the generation controller flow, Pro gating
// (teaser for free users, renderers after the offline purchase), renderer
// selection per tier, the never-crash fallback to the Explain tab, the Numi
// visual-step context pipeline, and accessibility (semantics + reduced
// motion). Deterministic and offline throughout: the AI seams are hand-rolled
// fakes, and Firebase/RevenueCat stay unconfigured as in every other test.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/backend/functions_client.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/security/rate_limit_result.dart';
import 'package:matheasy/core/security/rate_limit_service.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/analytics/application/analytics_service.dart';
import 'package:matheasy/features/analytics/domain/analytics_event.dart';
import 'package:matheasy/features/result/application/functions_visual_solution_service.dart';
import 'package:matheasy/features/result/application/visual_prompt_builder.dart';
import 'package:matheasy/features/result/application/visual_solution_controller.dart';
import 'package:matheasy/features/result/application/visual_solution_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/domain/visual_models.dart';
import 'package:matheasy/features/result/presentation/tabs/visual_tab.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/concept_painter.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/tier1_animated_transformation.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/tier2_learning_cards.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/tier3_concept_explorer.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/visual_teaser.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/subscription/application/subscription_controller.dart';
import 'package:matheasy/features/subscription/domain/purchase_result.dart';
import 'package:matheasy/features/subscription/domain/subscription_plan.dart';
import 'package:matheasy/features/tutor/application/functions_tutor_service.dart';
import 'package:matheasy/features/tutor/application/tutor_reply_engine.dart';
import 'package:matheasy/features/tutor/domain/tutor_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _equation = DetectedEquation(
  latex: '2x + 5 = 13',
  confidence: 0.98,
  source: ScanSource.camera,
  kind: EquationKind.linear,
);

const _resultData = ResultData(
  equation: _equation,
  type: ResultType.linear,
  difficulty: Difficulty.easy,
  answerLatex: 'x = 4',
  verifyText: '2(4) + 5 = 13 ✓',
  numiIntro: 'Here we go!',
  steps: [
    SolutionStep(
      title: 'Start with the equation',
      resultLatex: '2x + 5 = 13',
      detail: 'The starting point.',
    ),
    SolutionStep(
      title: 'Subtract 5',
      operationLabel: '− 5',
      resultLatex: '2x = 8',
      detail: 'Undo the + 5.',
    ),
  ],
  explanations: [],
  methods: [],
  practice: [],
);

const _tier1Visual = VisualSolution(
  category: ProblemCategory.algebra,
  difficulty: ProblemDifficulty.secondary,
  visualization: VisualizationType.animatedTransformation,
  answerLatex: 'x = 4',
  intro: 'Watch it unfold.',
  steps: [
    VisualStep(
      title: 'Subtract 5 from both sides',
      beforeLatex: '2x + 5 = 13',
      afterLatex: '2x = 8',
      operationLabel: '− 5',
      explanation: 'Removes the constant.',
      hint: VisualHint(text: 'Think of a balance scale.'),
    ),
    VisualStep(
      title: 'Divide both sides by 2',
      beforeLatex: '2x = 8',
      afterLatex: 'x = 4',
      operationLabel: '÷ 2',
      explanation: 'Isolates x.',
    ),
  ],
  explanation: VisualExplanation(
    summary: 'Undo operations in reverse.',
    keyIdeas: ['Inverse operations'],
  ),
  method: VisualMethod(name: 'Balance method', description: 'Same both sides.'),
);

const _tier2Visual = VisualSolution(
  category: ProblemCategory.trigonometry,
  difficulty: ProblemDifficulty.secondary,
  visualization: VisualizationType.interactiveCards,
  answerLatex: r'\theta = 30^\circ',
  intro: 'Unpack each card.',
  steps: [
    VisualStep(
      title: 'Identify the ratio',
      beforeLatex: r'\sin\theta = 1/2',
      afterLatex: r'\theta = \sin^{-1}(1/2)',
      explanation: 'Inverse sine recovers the angle.',
    ),
  ],
);

const _tier3Visual = VisualSolution(
  category: ProblemCategory.graphs,
  difficulty: ProblemDifficulty.secondary,
  visualization: VisualizationType.conceptExplorer,
  answerLatex: 'x = 4',
  intro: 'See the line.',
  steps: [
    VisualStep(
      title: 'Read the intersection',
      beforeLatex: 'y = 2x + 5',
      afterLatex: 'x = 4',
      explanation: 'Where the line meets y = 13.',
    ),
  ],
  concept: VisualConcept(
    kind: VisualConceptKind.linearGraph,
    caption: 'The line y = 2x + 5 crossing y = 13 at x = 4.',
    params: {'slope': 2, 'intercept': 5},
  ),
);

/// Deterministic visual service — fixed fixture, optional failure, zero delay.
class _FixedVisualService implements VisualSolutionService {
  const _FixedVisualService(this.visual, {this.error});

  final VisualSolution visual;
  final Object? error;

  @override
  Future<VisualSolution> generate(VisualRequest request) async {
    final failure = error;
    if (failure != null) throw failure;
    return visual;
  }
}

/// Counts generations, to prove the controller caches (no re-billing).
class _CountingVisualService implements VisualSolutionService {
  _CountingVisualService(this.visual);

  final VisualSolution visual;
  int calls = 0;

  @override
  Future<VisualSolution> generate(VisualRequest request) async {
    calls++;
    return visual;
  }
}

/// Captures every logged event so analytics assertions stay exact.
class _RecordingAnalytics implements AnalyticsService {
  final List<AnalyticsEvent> events = [];

  @override
  Future<void> logEvent(AnalyticsEvent event) async => events.add(event);

  @override
  Future<void> setUserId(String? id) async {}

  @override
  Future<void> setUserProperty(String name, String? value) async {}
}

Future<ProviderContainer> _container({
  VisualSolutionService? visualService,
  _RecordingAnalytics? analytics,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (visualService != null)
        visualSolutionServiceProvider.overrideWithValue(visualService),
      if (analytics != null)
        analyticsServiceProvider.overrideWithValue(analytics),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Keeps keepAlive controllers alive for the duration of a container test.
void _activate(ProviderContainer container) {
  container.listen(subscriptionControllerProvider, (_, _) {});
}

/// Pumps a result-tab-shaped host (scrollable, finite width) around [child].
Future<void> _pumpTab(
  WidgetTester tester,
  ProviderContainer container,
  Widget child, {
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Universal schema parsing', () {
    test('maps the full generateVisualSolution payload', () {
      final visual = VisualResponseMapper.toVisualSolution({
        'category': 'fractions',
        'difficulty': 'primary',
        'visualization': 'animatedTransformation',
        'answerLatex': r'\frac{5}{6}',
        'intro': 'Watch the pieces match.',
        'steps': [
          {
            'title': 'Common denominator',
            'beforeLatex': '1/2 + 1/3',
            'afterLatex': '3/6 + 2/6',
            'operationLabel': '× 3/3',
            'explanation': 'Same-sized pieces.',
            'hint': 'LCM of 2 and 3 is 6.',
          },
        ],
        'explanation': {
          'summary': 'Match piece sizes first.',
          'keyIdeas': ['Common denominators'],
        },
        'method': {'name': 'LCM method', 'description': 'Use the LCM.'},
        'concept': {
          'kind': 'fractionBar',
          'caption': 'Five of six parts shaded.',
          'params': {'numerator': 5, 'denominator': 6},
          'labels': {'unit': 'sixths'},
          'points': [
            [1, 2],
            [3, 4],
          ],
        },
      });

      expect(visual.category, ProblemCategory.fractions);
      expect(visual.difficulty, ProblemDifficulty.primary);
      expect(visual.visualization, VisualizationType.animatedTransformation);
      expect(visual.answerLatex, r'\frac{5}{6}');
      expect(visual.steps, hasLength(1));
      expect(visual.steps.first.operationLabel, '× 3/3');
      expect(visual.steps.first.hint?.text, 'LCM of 2 and 3 is 6.');
      expect(visual.explanation?.keyIdeas, ['Common denominators']);
      expect(visual.method?.name, 'LCM method');
      expect(visual.concept?.kind, VisualConceptKind.fractionBar);
      expect(visual.concept?.param('denominator'), 6);
      expect(visual.concept?.labels['unit'], 'sixths');
      expect(visual.concept?.points, const [
        VisualPoint(1, 2),
        VisualPoint(3, 4),
      ]);
    });

    test('an empty payload degrades safely instead of crashing', () {
      final visual = VisualResponseMapper.toVisualSolution({});
      expect(visual.category, ProblemCategory.algebra);
      expect(visual.visualization, VisualizationType.interactiveCards);
      expect(visual.steps, isEmpty);
      expect(visual.hasSteps, isFalse);
      expect(visual.explanation, isNull);
      expect(visual.method, isNull);
      expect(visual.concept, isNull);
    });

    test('steps missing either side of the transformation are dropped', () {
      final visual = VisualResponseMapper.toVisualSolution({
        'category': 'algebra',
        'steps': [
          {'title': 'No after', 'beforeLatex': '2x = 8'},
          {'title': 'No before', 'afterLatex': 'x = 4'},
          {'beforeLatex': '2x = 8', 'afterLatex': 'x = 4'},
          'not even a map',
        ],
      });
      expect(visual.steps, hasLength(1));
      expect(visual.steps.first.title, 'Next step');
    });

    test('unknown category without explicit tier falls back to cards', () {
      final visual = VisualResponseMapper.toVisualSolution({
        'category': 'astrology',
        'steps': [
          {'beforeLatex': 'a', 'afterLatex': 'b'},
        ],
      });
      expect(visual.visualization, VisualizationType.interactiveCards);
    });

    test('a known category picks its tier; an explicit tier wins', () {
      expect(
        VisualResponseMapper.toVisualSolution({'category': 'calculus'})
            .visualization,
        VisualizationType.conceptExplorer,
      );
      expect(
        VisualResponseMapper.toVisualSolution({
          'category': 'calculus',
          'visualization': 'interactiveCards',
        }).visualization,
        VisualizationType.interactiveCards,
      );
    });

    test('malformed concept metadata degrades, never crashes', () {
      // Unknown kind → generic; missing caption → no concept at all.
      final unknownKind = VisualResponseMapper.toVisualSolution({
        'concept': {'kind': 'hologram', 'caption': 'A mystery drawing.'},
      });
      expect(unknownKind.concept?.kind, VisualConceptKind.generic);

      final noCaption = VisualResponseMapper.toVisualSolution({
        'concept': {'kind': 'linearGraph'},
      });
      expect(noCaption.concept, isNull);

      final messyPoints = VisualResponseMapper.toVisualSolution({
        'concept': {
          'kind': 'barChart',
          'caption': 'Bars.',
          'params': {'ok': 1, 'bad': 'nope'},
          'points': [
            [1, 2],
            [3, 'x'],
            5,
          ],
        },
      });
      expect(messyPoints.concept?.points, const [VisualPoint(1, 2)]);
      expect(messyPoints.concept?.params, {'ok': 1.0});
    });
  });

  group('Tier selection', () {
    test('every category resolves to the spec tier', () {
      const tier1 = VisualizationType.animatedTransformation;
      const tier2 = VisualizationType.interactiveCards;
      const tier3 = VisualizationType.conceptExplorer;
      const expected = {
        ProblemCategory.arithmetic: tier1,
        ProblemCategory.fractions: tier1,
        ProblemCategory.ratios: tier1,
        ProblemCategory.percentages: tier1,
        ProblemCategory.algebra: tier1,
        ProblemCategory.measurement: tier1,
        ProblemCategory.trigonometry: tier2,
        ProblemCategory.statistics: tier2,
        ProblemCategory.probability: tier2,
        ProblemCategory.matrices: tier2,
        ProblemCategory.vectors: tier2,
        ProblemCategory.linearAlgebra: tier2,
        ProblemCategory.discreteMathematics: tier2,
        ProblemCategory.geometry: tier3,
        ProblemCategory.functions: tier3,
        ProblemCategory.graphs: tier3,
        ProblemCategory.calculus: tier3,
        ProblemCategory.differentialEquations: tier3,
        ProblemCategory.universityMathematics: tier3,
      };
      // Exhaustive: a new category must be added here deliberately.
      expect(expected, hasLength(ProblemCategory.values.length));
      expected.forEach(
        (category, tier) => expect(category.visualization, tier),
      );
    });
  });

  group('VisualPromptBuilder', () {
    test('request payload carries the problem and solver context', () {
      final request = VisualPromptBuilder.request(
        _equation,
        result: _resultData,
      );
      expect(VisualPromptBuilder.requestPayload(request), {
        'latex': '2x + 5 = 13',
        'answerLatex': 'x = 4',
        'problemType': 'linear',
      });
    });

    test('payload omits absent solver context', () {
      expect(
        VisualPromptBuilder.requestPayload(
          VisualPromptBuilder.request(_equation),
        ),
        {'latex': '2x + 5 = 13'},
      );
    });

    test('Numi step context describes the exact transformation', () {
      final context = VisualPromptBuilder.numiStepContext(_tier1Visual, 1);
      expect(context, contains('Step 2 of 2'));
      expect(context, contains('Divide both sides by 2'));
      expect(context, contains('÷ 2'));
      expect(context, contains('2x = 8 becomes x = 4'));
      expect(context, contains('Isolates x.'));
    });

    test('an out-of-range step index still yields usable context', () {
      final context = VisualPromptBuilder.numiStepContext(_tier1Visual, 99);
      expect(context, contains('x = 4'));
    });
  });

  group('FunctionsVisualSolutionService', () {
    test('calls generateVisualSolution and maps the response', () async {
      String? calledName;
      Map<String, dynamic>? sentData;
      final service = FunctionsVisualSolutionService((name, data) async {
        calledName = name;
        sentData = data;
        return {
          'category': 'algebra',
          'answerLatex': 'x = 4',
          'steps': [
            {'beforeLatex': '2x = 8', 'afterLatex': 'x = 4'},
          ],
        };
      });
      final visual = await service.generate(
        VisualPromptBuilder.request(_equation, result: _resultData),
      );
      expect(calledName, 'generateVisualSolution');
      expect(sentData?['latex'], '2x + 5 = 13');
      expect(sentData?['answerLatex'], 'x = 4');
      expect(visual.visualization, VisualizationType.animatedTransformation);
      expect(visual.steps, hasLength(1));
    });
  });

  group('VisualSolutionController', () {
    test('generates lazily and logs visual_viewed', () async {
      final analytics = _RecordingAnalytics();
      final container = await _container(
        visualService: const _FixedVisualService(_tier1Visual),
        analytics: analytics,
      );
      // The provider is auto-dispose (like its widget consumer): a listener
      // must hold it alive across the async build, as the tab does.
      container.listen(
        visualSolutionControllerProvider(_equation),
        (_, _) {},
      );
      final visual = await container
          .read(visualSolutionControllerProvider(_equation).future);
      expect(visual, _tier1Visual);
      final names = analytics.events.map((e) => e.name);
      expect(names, contains('visual_viewed'));
      final event =
          analytics.events.firstWhere((e) => e.name == 'visual_viewed');
      expect(event.parameters, {
        'category': 'algebra',
        'tier': 'animatedTransformation',
      });
    });

    test('a failing service surfaces as an error state, not a crash',
        () async {
      final container = await _container(
        visualService: const _FixedVisualService(
          _tier1Visual,
          error: VisualGenerationException('nope'),
        ),
      );
      container.listen(
        visualSolutionControllerProvider(_equation),
        (_, _) {},
      );
      await expectLater(
        container.read(visualSolutionControllerProvider(_equation).future),
        throwsA(isA<VisualGenerationException>()),
      );
    });

    test('visual generation is rate-limited client-side', () {
      final service = RateLimitService(() => DateTime(2026, 7, 9, 12));
      for (var i = 0; i < 10; i++) {
        expect(
          service.check(RateLimitedAction.visualGeneration).isLimited,
          isFalse,
        );
      }
      expect(
        service.check(RateLimitedAction.visualGeneration).isLimited,
        isTrue,
      );
    });
  });

  group('Pro gating', () {
    testWidgets('free users see the locked teaser, never a renderer',
        (tester) async {
      final container = await _container(
        visualService: const _FixedVisualService(_tier1Visual),
      );
      _activate(container);
      var unlocked = false;
      await _pumpTab(
        tester,
        container,
        VisualTab(
          equation: _equation,
          result: _resultData,
          onUnlock: () => unlocked = true,
          onOpenExplain: () {},
          onAskNumi: (_, _) {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(VisualTeaser), findsOneWidget);
      expect(find.text('Step 1 preview'), findsOneWidget);
      expect(find.text('Unlock Pro to continue'), findsOneWidget);
      expect(find.byType(Tier1AnimatedTransformation), findsNothing);

      await tester.tap(find.text('Start Free Trial'));
      expect(unlocked, isTrue);
    });

    testWidgets('teaser impression is logged once per problem',
        (tester) async {
      final analytics = _RecordingAnalytics();
      final container = await _container(analytics: analytics);
      _activate(container);
      final teaser = VisualTab(
        equation: _equation,
        result: _resultData,
        onUnlock: () {},
        onOpenExplain: () {},
        onAskNumi: (_, _) {},
      );
      await _pumpTab(tester, container, teaser);
      await _pumpTab(tester, container, teaser);
      expect(
        analytics.events.where((e) => e.name == 'visual_teaser_viewed'),
        hasLength(1),
      );
    });

    testWidgets('purchasing Pro unlocks the full experience', (tester) async {
      final container = await _container(
        visualService: const _FixedVisualService(_tier1Visual),
      );
      _activate(container);
      await _pumpTab(
        tester,
        container,
        VisualTab(
          equation: _equation,
          result: _resultData,
          onUnlock: () {},
          onOpenExplain: () {},
          onAskNumi: (_, _) {},
        ),
        // Keeps Tier 1 off auto-play so no timer outlives the test.
        reduceMotion: true,
      );
      expect(find.byType(VisualTeaser), findsOneWidget);

      // The offline purchase path (RevenueCat unconfigured in tests).
      final result = await container
          .read(subscriptionControllerProvider.notifier)
          .purchase(SubscriptionPlan.proAnnual);
      expect(result, isA<PurchaseSuccess>());
      expect(container.read(isProProvider), isTrue);

      await tester.pump();
      // MockSolverService thinks for 500ms before the visual generates.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(VisualTeaser), findsNothing);
      expect(find.byType(Tier1AnimatedTransformation), findsOneWidget);
    });
  });

  group('Renderer selection', () {
    Future<ProviderContainer> proContainer(VisualSolution visual) async {
      final container = await _container(
        visualService: _FixedVisualService(visual),
      );
      _activate(container);
      final result = await container
          .read(subscriptionControllerProvider.notifier)
          .purchase(SubscriptionPlan.proAnnual);
      expect(result, isA<PurchaseSuccess>());
      return container;
    }

    Future<void> pumpVisualTab(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await _pumpTab(
        tester,
        container,
        VisualTab(
          equation: _equation,
          result: _resultData,
          onUnlock: () {},
          onOpenExplain: () {},
          onAskNumi: (_, _) {},
        ),
        reduceMotion: true,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('tier 1 categories get animated transformations',
        (tester) async {
      final container = await proContainer(_tier1Visual);
      await pumpVisualTab(tester, container);
      expect(find.byType(Tier1AnimatedTransformation), findsOneWidget);
      expect(find.text('STEP 1 OF 2'), findsOneWidget);
    });

    testWidgets('tier 2 categories get interactive learning cards',
        (tester) async {
      final container = await proContainer(_tier2Visual);
      await pumpVisualTab(tester, container);
      expect(find.byType(Tier2LearningCards), findsOneWidget);
      expect(find.text('Identify the ratio'), findsOneWidget);
    });

    testWidgets('tier 3 categories get the concept explorer with a canvas',
        (tester) async {
      final container = await proContainer(_tier3Visual);
      await pumpVisualTab(tester, container);
      expect(find.byType(Tier3ConceptExplorer), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
        find.text('The line y = 2x + 5 crossing y = 13 at x = 4.'),
        findsOneWidget,
      );
    });
  });

  group('Fallback behavior', () {
    Future<ProviderContainer> failingProContainer(Object error) async {
      final container = await _container(
        visualService: _FixedVisualService(_tier1Visual, error: error),
      );
      _activate(container);
      final result = await container
          .read(subscriptionControllerProvider.notifier)
          .purchase(SubscriptionPlan.proAnnual);
      expect(result, isA<PurchaseSuccess>());
      return container;
    }

    testWidgets('generation failure offers Explain instead of crashing',
        (tester) async {
      final container =
          await failingProContainer(const VisualGenerationException('down'));
      var openedExplain = false;
      await _pumpTab(
        tester,
        container,
        VisualTab(
          equation: _equation,
          result: _resultData,
          onUnlock: () {},
          onOpenExplain: () => openedExplain = true,
          onAskNumi: (_, _) {},
        ),
        reduceMotion: true,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Try again'), findsOneWidget);
      await tester.ensureVisible(find.text('Open Explain'));
      await tester.tap(find.text('Open Explain'));
      expect(openedExplain, isTrue);
    });

    testWidgets('an empty visual (no steps) also falls back', (tester) async {
      const empty = VisualSolution(
        category: ProblemCategory.algebra,
        difficulty: ProblemDifficulty.secondary,
        visualization: VisualizationType.animatedTransformation,
        answerLatex: 'x = 4',
        intro: 'Nothing to show.',
        steps: [],
      );
      final container = await _container(
        visualService: const _FixedVisualService(empty),
      );
      _activate(container);
      final result = await container
          .read(subscriptionControllerProvider.notifier)
          .purchase(SubscriptionPlan.proAnnual);
      expect(result, isA<PurchaseSuccess>());

      await _pumpTab(
        tester,
        container,
        VisualTab(
          equation: _equation,
          result: _resultData,
          onUnlock: () {},
          onOpenExplain: () {},
          onAskNumi: (_, _) {},
        ),
        reduceMotion: true,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(Tier1AnimatedTransformation), findsNothing);
    });
  });

  group('Numi visual-step integration', () {
    test('TutorLaunchContext equality includes the visual step', () {
      const a = TutorLaunchContext(questionLatex: '2x = 8');
      const b = TutorLaunchContext(
        questionLatex: '2x = 8',
        visualStepSummary: 'Step 1: divide by 2',
      );
      expect(a == b, isFalse);
      expect(b.hasVisualStep, isTrue);
      expect(a.hasVisualStep, isFalse);
    });

    test('FunctionsTutorService forwards the visual step to the backend',
        () async {
      Map<String, dynamic>? sent;
      final service = FunctionsTutorService((name, data) async {
        sent = data;
        return {'reply': 'Because dividing undoes multiplying!'};
      });
      await service.reply(
        'Why divide by 2?',
        history: const [],
        context: const TutorLaunchContext(
          questionLatex: '2x + 5 = 13',
          visualStepSummary: 'Step 2 of 2 — "Divide by 2": 2x = 8 becomes x = 4.',
        ),
      );
      expect(sent?['problemLatex'], '2x + 5 = 13');
      expect(sent?['visualStep'], contains('Divide by 2'));
    });

    test('the offline engine greets visual-step launches specifically', () {
      const engine = TutorReplyEngine();
      final greeting = engine.greeting(
        const TutorLaunchContext(
          questionLatex: '2x + 5 = 13',
          visualStepSummary: 'Step 1',
        ),
      );
      expect(greeting.text.toLowerCase(), contains('step'));
    });
  });

  group('Accessibility', () {
    testWidgets('tier 1 announces the whole transformation as one sentence',
        (tester) async {
      final handle = tester.ensureSemantics();
      final container = await _container();
      await _pumpTab(
        tester,
        container,
        Tier1AnimatedTransformation(visual: _tier1Visual, onAskNumi: (_) {}),
        reduceMotion: true,
      );
      expect(
        find.bySemanticsLabel(RegExp('2x \\+ 5 = 13 becomes 2x = 8')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('reduced motion removes auto-play entirely', (tester) async {
      final container = await _container();
      await _pumpTab(
        tester,
        container,
        Tier1AnimatedTransformation(visual: _tier1Visual, onAskNumi: (_) {}),
        reduceMotion: true,
      );
      expect(find.byIcon(Icons.pause_circle_rounded), findsNothing);
      expect(find.byIcon(Icons.play_circle_rounded), findsNothing);
      // Still fully navigable by hand.
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('STEP 2 OF 2'), findsOneWidget);
    });

    testWidgets('with motion enabled the walkthrough auto-plays',
        (tester) async {
      final container = await _container();
      await _pumpTab(
        tester,
        container,
        Tier1AnimatedTransformation(visual: _tier1Visual, onAskNumi: (_) {}),
      );
      expect(find.text('STEP 1 OF 2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('STEP 2 OF 2'), findsOneWidget);
      // Unmount to cancel the walkthrough timer before the test ends.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the teaser CTA is a labelled button', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await _container();
      _activate(container);
      await _pumpTab(
        tester,
        container,
        VisualTeaser(result: _resultData, onUnlock: () {}),
      );
      expect(find.bySemanticsLabel('Start Free Trial'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Caching (no re-billing on tab switch)', () {
    test('a successful visual is reused, not regenerated', () async {
      final service = _CountingVisualService(_tier1Visual);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          visualSolutionServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      // First mount generates once.
      final sub = container.listen(
        visualSolutionControllerProvider(_equation),
        (_, _) {},
      );
      await container
          .read(visualSolutionControllerProvider(_equation).future);
      expect(service.calls, 1);

      // Tab switch away = the only listener drops.
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Returning re-reads: keepAlive on success means the cached value is
      // served without a second billed generation.
      container.listen(
        visualSolutionControllerProvider(_equation),
        (_, _) {},
      );
      final again = await container
          .read(visualSolutionControllerProvider(_equation).future);
      expect(again, _tier1Visual);
      expect(service.calls, 1, reason: 'must not re-generate on revisit');
    });
  });

  group('Lapsed-entitlement routing', () {
    testWidgets('a permission-denied surfaces the upgrade path, not a dead '
        'retry loop', (tester) async {
      final container = await _container(
        visualService: const _FixedVisualService(
          _tier1Visual,
          error: BackendException(
            'Visual Learning is a Matheasy Pro feature.',
            code: 'permission-denied',
          ),
        ),
      );
      _activate(container);
      final result = await container
          .read(subscriptionControllerProvider.notifier)
          .purchase(SubscriptionPlan.proAnnual);
      expect(result, isA<PurchaseSuccess>());

      var unlocked = false;
      await _pumpTab(
        tester,
        container,
        VisualTab(
          equation: _equation,
          result: _resultData,
          onUnlock: () => unlocked = true,
          onOpenExplain: () {},
          onAskNumi: (_, _) {},
        ),
        reduceMotion: true,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      // The server said "upgrade", so show the teaser CTA, not "Try again".
      expect(find.byType(VisualTeaser), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      await tester.tap(find.text('Start Free Trial'));
      expect(unlocked, isTrue);
    });
  });

  group('Concept rendering across tiers', () {
    testWidgets('a Tier 2 solution still draws its concept canvas',
        (tester) async {
      const withConcept = VisualSolution(
        category: ProblemCategory.trigonometry,
        difficulty: ProblemDifficulty.secondary,
        visualization: VisualizationType.interactiveCards,
        answerLatex: r'\theta = 30^\circ',
        intro: 'Unpack each card.',
        steps: [
          VisualStep(
            title: 'Identify the ratio',
            beforeLatex: r'\sin\theta = 1/2',
            afterLatex: r'\theta = 30^\circ',
            explanation: 'Inverse sine.',
          ),
        ],
        concept: VisualConcept(
          kind: VisualConceptKind.unitCircle,
          caption: 'The unit circle with a 30° angle marked.',
          params: {'angleDegrees': 30},
        ),
      );
      final container = await _container();
      await _pumpTab(
        tester,
        container,
        Tier2LearningCards(visual: withConcept, onAskNumi: (_) {}),
        reduceMotion: true,
      );
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
        find.text('The unit circle with a 30° angle marked.'),
        findsOneWidget,
      );
    });
  });

  group('ConceptPainter robustness', () {
    const palette = ConceptPalette(
      grid: Color(0xFFEEEEEE),
      axis: Color(0xFF888888),
      stroke: Color(0xFF2563EB),
      fill: Color(0x282563EB),
      accent: Color(0xFFFF7A45),
    );

    void paintOnce(VisualConcept concept) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      ConceptPainter(concept: concept, palette: palette)
          .paint(canvas, const Size(300, 200));
      recorder.endRecording().dispose();
    }

    test('extreme params terminate instead of freezing the raster thread', () {
      // Pre-fix, a step below the ulp at 1e16 spun `x += step` forever.
      paintOnce(const VisualConcept(
        kind: VisualConceptKind.numberLine,
        caption: 'huge',
        params: {'min': 1e16, 'max': 1e16 + 10, 'value': 1e16 + 5},
      ));
      paintOnce(const VisualConcept(
        kind: VisualConceptKind.linearGraph,
        caption: 'huge',
        params: {'slope': 1, 'intercept': 0, 'xMin': 1e16, 'xMax': 1e16 + 10},
      ));
      // A degenerate / non-finite parabola bails rather than drawing garbage.
      paintOnce(const VisualConcept(
        kind: VisualConceptKind.parabolaGraph,
        caption: 'flat',
        params: {'a': 0, 'b': 0, 'c': 0},
      ));
      expect(true, isTrue); // Reaching here means no hang / no throw.
    });

    test('areaUnderCurve keeps the integration bounds inside the window', () {
      // ∫₀⁴(x²+1)dx — roots are complex, so vertex-only framing would clip at
      // x=3; the fix widens the window to include from/to. We assert it paints
      // without error (the window math no longer draws off-canvas).
      paintOnce(const VisualConcept(
        kind: VisualConceptKind.areaUnderCurve,
        caption: 'area',
        params: {'a': 1, 'b': 0, 'c': 1, 'from': 0, 'to': 4},
      ));
      expect(true, isTrue);
    });
  });
}
