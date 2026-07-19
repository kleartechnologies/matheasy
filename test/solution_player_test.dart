// Phase 1 — the STATIC SolutionPlayer: it renders the server `animationSchema`
// one step at a time, shows the tutor "why" sentence (reused from the solve
// narration, index-aligned), and steps with Prev/Next. No animation is asserted
// here (there is none this phase). The defensive-lookup test pins that the raw
// explanationKey can NEVER reach the user.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/animation_schema.dart';
import 'package:matheasy/features/result/presentation/widgets/solution_player.dart';

/// A two-step schema shaped exactly like the server sends it.
AnimationSchema _schema() => AnimationSchema.fromJson([
      {
        'stepIndex': 0,
        'changeType': 'SUBTRACT_FROM_BOTH_SIDES',
        'beforeLatex': '2x + 5 = 13',
        'afterLatex': '2x = 8',
        'animationTemplate': 'move_across_equals',
        'tokens': [
          {
            'value': '5',
            'fromPath': 'L/1',
            'toPath': 'R/1',
            'color': 'pink',
            'highlight': 'circle',
          },
        ],
        'explanationKey': 'anim.step.SUBTRACT_FROM_BOTH_SIDES',
      },
      {
        'stepIndex': 1,
        'changeType': 'DIVIDE_FROM_BOTH_SIDES',
        'beforeLatex': '2x = 8',
        'afterLatex': 'x = 4',
        'animationTemplate': 'divide_both_sides',
        'tokens': const [],
        'explanationKey': 'anim.step.DIVIDE_FROM_BOTH_SIDES',
      },
    ]);

// The per-step tutor sentences + operation labels, index-aligned with the schema
// (as SolutionTab passes from ResultData.steps[].detail / .title).
const _details = [
  'Subtract 5 from both sides to isolate the x term.',
  'Divide both sides by 2 to solve for x.',
];
const _labels = ['Subtract from both sides', 'Divide both sides'];

Future<void> _pump(
  WidgetTester tester, {
  AnimationSchema? schema,
  List<String> details = _details,
  List<String> labels = _labels,
  Size? surface,
}) async {
  if (surface != null) {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SolutionPlayer(
          schema: schema ?? _schema(),
          stepDetails: details,
          stepLabels: labels,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the real tutor sentence, not the raw explanationKey',
      (tester) async {
    await _pump(tester);

    // The step's arrived-at expression renders (MathText exposes it as a label).
    expect(find.bySemanticsLabel('2x = 8'), findsOneWidget);
    expect(find.text('STEP 1 OF 2'), findsOneWidget);
    // The tutor "why" sentence shows — NOT the raw "anim.step.X" key.
    expect(find.text(_details[0]), findsOneWidget);
    expect(find.text('anim.step.SUBTRACT_FROM_BOTH_SIDES'), findsNothing);
    // The participating token still renders as a static chip.
    expect(find.bySemanticsLabel('5'), findsOneWidget);
  });

  testWidgets('Next advances and shows the next sentence; Prev goes back',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Next step'));
    await tester.pump();

    expect(find.bySemanticsLabel('x = 4'), findsOneWidget);
    expect(find.text('SOLVED'), findsOneWidget);
    expect(find.text(_details[1]), findsOneWidget); // step 2's sentence
    expect(find.text('Got it!'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    expect(find.bySemanticsLabel('2x = 8'), findsOneWidget);
    expect(find.text(_details[0]), findsOneWidget);
  });

  testWidgets('DEFENSIVE: out-of-range stepIndex → humanized label, never the key',
      (tester) async {
    // A schema whose stepIndex is out of range for the details/labels lists —
    // the exact drift a future filter change could introduce. It must degrade to
    // a humanized label, NOT the raw key, and NOT throw.
    final schema = AnimationSchema.fromJson([
      {
        'stepIndex': 99, // out of range for both lists below
        'changeType': 'DIVIDE_FROM_BOTH_SIDES',
        'beforeLatex': '2x = 8',
        'afterLatex': 'x = 4',
        'animationTemplate': 'divide_both_sides',
        'tokens': const [],
        'explanationKey': 'anim.step.DIVIDE_FROM_BOTH_SIDES',
      },
    ]);
    await _pump(tester, schema: schema, details: const ['unrelated'], labels: const []);

    expect(tester.takeException(), isNull); // no crash
    expect(find.text('Divide both sides'), findsOneWidget); // humanized label
    // The raw key must NEVER reach the user under any branch.
    expect(find.text('anim.step.DIVIDE_FROM_BOTH_SIDES'), findsNothing);
    expect(find.textContaining('anim.step.'), findsNothing);
  });

  testWidgets('in-range step with an empty sentence → falls back to the label',
      (tester) async {
    // Tier 2: the "why" is empty for this step, so the operation label shows —
    // still never the raw key.
    await _pump(
      tester,
      details: const [''],
      labels: const ['Subtract from both sides'],
    );
    expect(find.text('Subtract from both sides'), findsOneWidget);
    expect(find.textContaining('anim.step.'), findsNothing);
  });

  testWidgets('does not overflow on a small screen (long expression)',
      (tester) async {
    final schema = AnimationSchema.fromJson([
      {
        'stepIndex': 0,
        'changeType': 'SIMPLIFY_LEFT_SIDE',
        'beforeLatex': '3x + 5x - 2 + 7 = 4x + 10 - x',
        'afterLatex': '8x + 5 = 3x + 10',
        'animationTemplate': 'simplify_in_place',
        'tokens': const [],
        'explanationKey': 'anim.step.SIMPLIFY_LEFT_SIDE',
      },
    ]);
    await _pump(
      tester,
      schema: schema,
      details: const ['Combine the like terms on each side.'],
      labels: const ['Simplify'],
      surface: const Size(320, 480), // a small phone
    );
    // A wide equation scales to fit width; a tall card scrolls — no overflow.
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('8x + 5 = 3x + 10'), findsOneWidget);
  });
}
