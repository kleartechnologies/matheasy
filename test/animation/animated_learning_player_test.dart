import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/application/animation/animation_script_builder.dart';
import 'package:matheasy/features/result/domain/animation/animation_script.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/engine/animated_learning_player.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/engine/equation_morph_view.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/engine/universal_control_bar.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

DetectedEquation _eq(String latex) => DetectedEquation(
      latex: latex,
      confidence: 1,
      source: ScanSource.camera,
      kind: EquationKind.linear,
    );

AnimationScript _linearScript() => AnimationScriptBuilder.build(ResultData(
      equation: _eq('3x + 5 = 20'),
      type: ResultType.linear,
      difficulty: Difficulty.easy,
      answerLatex: 'x = 5',
      steps: const [
        SolutionStep(title: 'Subtract 5', resultLatex: '3x = 20 - 5', detail: 'move'),
        SolutionStep(title: 'Simplify', resultLatex: '3x = 15', detail: 'combine'),
        SolutionStep(title: 'Divide by 3', resultLatex: 'x = 5', detail: 'isolate'),
      ],
      verifyText: '3(5) + 5 = 20',
      explanations: const [],
      methods: const [],
      practice: const [],
      tutorIntro: '',
    ));

Future<void> _pump(WidgetTester tester, {required bool reduceMotion}) async {
  // A tall surface so the whole player (scene + morph + timeline + controls)
  // fits without scrolling — taps then land directly on the control bar.
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: SingleChildScrollView(
              child: AnimatedLearningPlayer(
                script: _linearScript(),
                onAskMatheasy: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders the calm layout: equation hero, quiet header, controls',
      (tester) async {
    await _pump(tester, reduceMotion: true);
    expect(find.byType(AnimatedLearningPlayer), findsOneWidget);
    expect(find.byType(EquationMorphView), findsOneWidget);
    expect(find.byType(UniversalControlBar), findsOneWidget);
    // Minimal "Step X of Y" — not a big named timeline competing for attention.
    expect(find.text('Step 1 of 5'), findsOneWidget);
  });

  testWidgets('reduced motion hides play/pause and the speed selector',
      (tester) async {
    await _pump(tester, reduceMotion: true);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.text('1×'), findsNothing);
    // No pending timers under reduced motion (autoplay is suppressed).
  });

  testWidgets('with motion, the speed selector cycles', (tester) async {
    await _pump(tester, reduceMotion: false);
    await tester.ensureVisible(find.text('1×'));
    await tester.pump();
    await tester.tap(find.text('1×'));
    await tester.pump();
    expect(find.text('1.5×'), findsOneWidget);
    // Dispose the player so its autoplay timer + controllers are cancelled.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('the Next control advances the beat', (tester) async {
    await _pump(tester, reduceMotion: true);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Step 2 of 5'), findsOneWidget);
  });
}
