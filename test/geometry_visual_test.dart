// Geometry Visual Learning — payload mapping + the diagram-first player.
//
// Covers the defensive `geometry` → GeometryScene mapping (VisualResponseMapper)
// and the GeometryVisualPlayer widget: the diagram is the primary element
// (70/20/10), steps advance, and the animated painter survives every step under
// both normal and reduced motion. Offline throughout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/theme/app_durations.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/application/functions_visual_solution_service.dart';
import 'package:matheasy/features/result/application/visual_prompt_builder.dart';
import 'package:matheasy/features/result/domain/geometry_models.dart';
import 'package:matheasy/features/result/domain/visual_models.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/geometry_scene_painter.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/geometry_visual_player.dart';

VisualSolution _sceneSolution() {
  final scene = GeometryScene.tryBuild(
    kind: GeometrySceneKind.triangleAngles,
    knownAngles: const [
      GeometryKnownAngle(label: 'A', value: 60),
      GeometryKnownAngle(label: 'B', value: 40),
    ],
    unknownLabel: 'x',
  )!;
  return VisualSolution(
    category: ProblemCategory.geometry,
    difficulty: ProblemDifficulty.secondary,
    visualization: VisualizationType.conceptExplorer,
    answerLatex: r'x = 80^\circ',
    intro: 'Find the missing angle.',
    steps: const [],
    geometryScene: scene,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
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
  );
  await tester.pump();
}

Finder _geometryPainter() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is GeometryScenePainter,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('geometry payload mapping', () {
    test('maps a well-formed triangle payload into a solved scene', () {
      final visual = VisualResponseMapper.toVisualSolution({
        'category': 'geometry',
        'answerLatex': r'x = 80^\circ',
        'intro': 'Find the missing angle.',
        'steps': const [],
        'geometry': {
          'kind': 'triangleAngles',
          'knownAngles': [
            {'label': 'A', 'value': 60},
            {'label': 'B', 'value': 40},
          ],
          'unknown': 'x',
        },
      });
      expect(visual.geometryScene, isNotNull);
      expect(visual.geometryScene!.unknownValue, closeTo(80, 1e-9));
      expect(visual.hasGeometryScene, isTrue);
    });

    test('coerces numeric strings and a missing label', () {
      final visual = VisualResponseMapper.toVisualSolution({
        'category': 'geometry',
        'geometry': {
          'kind': 'straightLineAngles',
          'knownAngles': [
            {'value': '130'}, // string number, no label
          ],
          'unknown': {'label': 'y'},
        },
      });
      expect(visual.geometryScene, isNotNull);
      expect(visual.geometryScene!.unknownValue, closeTo(50, 1e-9));
      expect(visual.geometryScene!.unknownLabel, 'y');
    });

    test('drops an unknown kind / absent geometry (→ null → fallback)', () {
      expect(
        VisualResponseMapper.toVisualSolution({
          'category': 'geometry',
          'geometry': {'kind': 'nonsense', 'knownAngles': []},
        }).geometryScene,
        isNull,
      );
      expect(
        VisualResponseMapper.toVisualSolution({'category': 'geometry'})
            .geometryScene,
        isNull,
      );
    });

    test('refuses a scene that contradicts the verified answer', () {
      final visual = VisualResponseMapper.toVisualSolution({
        'category': 'geometry',
        'answerLatex': r'x = 999^\circ', // solver disagrees with 80
        'geometry': {
          'kind': 'triangleAngles',
          'knownAngles': [
            {'label': 'A', 'value': 60},
            {'label': 'B', 'value': 40},
          ],
          'unknown': 'x',
        },
      });
      expect(visual.geometryScene, isNull);
    });

    test('the SOLVER answer wins over the model\'s self-consistent echo', () {
      // The model echoes an answer matching its own givens (80), but the solver
      // verified 90 — the ground-truth cross-check must reject the scene.
      final visual = VisualResponseMapper.toVisualSolution(
        {
          'category': 'geometry',
          'answerLatex': r'x = 80^\circ', // model's echo (matches its givens)
          'geometry': {
            'kind': 'triangleAngles',
            'knownAngles': [
              {'label': 'A', 'value': 60},
              {'label': 'B', 'value': 40},
            ],
            'unknown': 'x',
          },
        },
        verifiedAnswerLatex: r'x = 90^\circ', // solver ground truth
      );
      expect(visual.geometryScene, isNull);
    });

    test('an over-long unknown label is rejected (defaults to x)', () {
      final visual = VisualResponseMapper.toVisualSolution({
        'category': 'geometry',
        'geometry': {
          'kind': 'triangleAngles',
          'knownAngles': [
            {'label': 'A', 'value': 60},
            {'label': 'B', 'value': 40},
          ],
          'unknown': 'this-label-is-far-too-long-to-draw',
        },
      });
      expect(visual.geometryScene!.unknownLabel, 'x');
    });
  });

  group('the painter reveal is step-driven', () {
    test('shouldRepaint fires when the reveal step advances', () {
      const palette = GeometryPalette(
        figureStroke: Color(0xFF334155),
        figureFill: Color(0x1410B981),
        knownArc: Color(0xFF0B7A4B),
        highlight: Color(0xFFB65B0C),
        highlightText: Color(0xFFB65B0C),
        vertexDot: Color(0xFF64748B),
        text: Color(0xFF0F172A),
        dim: Color(0x8064748B),
        badgeBackground: Color(0xFFF7E3CC),
        badgeText: Color(0xFF7A3D08),
        tick: Color(0xFF0B7A4B),
      );
      final scene = _sceneSolution().geometryScene!;
      GeometryScenePainter at(int step, double p) => GeometryScenePainter(
            scene: scene,
            revealStep: step,
            stepProgress: p,
            pulse: 1,
            palette: palette,
          );
      // The animated reveal must repaint as the step (and progress) change,
      // and stay still when nothing does.
      expect(at(3, 1).shouldRepaint(at(0, 1)), isTrue); // step changed
      expect(at(0, 0.5).shouldRepaint(at(0, 1)), isTrue); // progress changed
      expect(at(0, 1).shouldRepaint(at(0, 1)), isFalse); // identical
    });
  });

  group('tutor step context', () {
    test('geometry uses the scene\'s beats, not the (empty) visual.steps', () {
      final scene = _sceneSolution().geometryScene!;
      final ctx = VisualPromptBuilder.tutorGeometryStepContext(scene, 1);
      expect(ctx, contains('Step 2 of 4'));
      expect(ctx, contains(scene.ruleName));
      // Out-of-range indices degrade gracefully instead of throwing.
      expect(
        () => VisualPromptBuilder.tutorGeometryStepContext(scene, 99),
        returnsNormally,
      );
    });
  });

  group('GeometryVisualPlayer', () {
    testWidgets('renders the diagram as the primary element (70/20/10)',
        (tester) async {
      await _pump(tester, GeometryVisualPlayer(
        visual: _sceneSolution(),
        scene: _sceneSolution().geometryScene!,
        onAskMatheasy: (_) {},
      ));

      // The animated geometry canvas is present.
      expect(_geometryPainter(), findsOneWidget);

      // The diagram-first ratio: the region splits 7 / 2 / (1) by flex.
      final flexes = tester
          .widgetList<Expanded>(find.byType(Expanded))
          .map((e) => e.flex)
          .toList();
      expect(flexes, containsAll(<int>[7, 2]));
      expect(flexes.reduce((a, b) => a > b ? a : b), 7); // diagram dominates
    });

    testWidgets('starts on step 1 and Next advances the reveal',
        (tester) async {
      final sol = _sceneSolution();
      await _pump(tester, GeometryVisualPlayer(
        visual: sol,
        scene: sol.geometryScene!,
        onAskMatheasy: (_) {},
      ));

      expect(find.textContaining('STEP 1 OF 4'), findsOneWidget);

      await tester.tap(find.byTooltip('Next step'));
      await tester.pump();
      expect(find.textContaining('STEP 2 OF 4'), findsOneWidget);
    });

    testWidgets('the painter survives every reveal step', (tester) async {
      final sol = _sceneSolution();
      await _pump(tester, GeometryVisualPlayer(
        visual: sol,
        scene: sol.geometryScene!,
        onAskMatheasy: (_) {},
      ));
      // Walk to the answer step; each tap repaints the animated canvas.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Next step'));
        await tester.pump();
      }
      expect(find.textContaining('STEP 4 OF 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('auto-plays through the steps under normal motion',
        (tester) async {
      final sol = _sceneSolution();
      await _pump(
        tester,
        GeometryVisualPlayer(
          visual: sol,
          scene: sol.geometryScene!,
          onAskMatheasy: (_) {},
        ),
        reduceMotion: false,
      );
      expect(find.textContaining('STEP 1 OF 4'), findsOneWidget);
      // The autoplay timer advances one beat.
      await tester.pump(AppDurations.walkthroughStep);
      await tester.pump();
      expect(find.textContaining('STEP 2 OF 4'), findsOneWidget);

      // Dispose to cancel the periodic timer + repeating animation cleanly.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
