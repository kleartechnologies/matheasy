// The step spine — the solving map. Every step is a row you can see and tap;
// exactly one lifts out of the list as a card showing before → what we do →
// after. These tests pin the four promises that make it navigable: the map
// stays whole, ✕ shuts a card without losing your place, any row is a
// destination, and the part that actually changes is lit on BOTH expressions.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/domain/teaching_models.dart';
import 'package:matheasy/features/result/presentation/widgets/math_text.dart';
import 'package:matheasy/features/result/presentation/widgets/step_spine.dart';

const _steps = [
  SolutionStep(
    title: 'Subtract 5 from both sides',
    resultLatex: '2x = 8',
    detail: 'Undo the addition to isolate the term in x.',
  ),
  SolutionStep(
    title: 'Divide both sides by 2',
    resultLatex: 'x = 4',
    detail: 'Undo the multiplication to leave x alone.',
  ),
];

/// The parent the spine expects: it owns the cursor and the open/shut flag, so
/// the callbacks under test actually move something.
class _Host extends StatefulWidget {
  const _Host({this.glossary = const []});

  final List<DefinedTerm> glossary;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int focused = 0;
  bool expanded = true;

  static final _solutionIndex = _steps.length;

  void _focus(int i) => setState(() {
        focused = i.clamp(0, _solutionIndex);
        expanded = true;
      });

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StepSpine(
              problemLatex: '2x + 5 = 13',
              steps: _steps,
              answerLatex: 'x = 4',
              focused: focused,
              expanded: expanded,
              onFocus: _focus,
              onCollapse: () => setState(() => expanded = false),
              // Shut, Next reopens where you are rather than skipping a step
              // you never read — the same rule the real parent follows.
              onNext: () =>
                  expanded ? _focus(focused + 1) : setState(() => expanded = true),
              onBack: () => _focus(focused - 1),
              glossary: widget.glossary,
            ),
          ),
        ),
      );
}

Future<void> _pump(WidgetTester tester, {List<DefinedTerm> glossary = const []}) async {
  tester.view.physicalSize = const Size(360, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_Host(glossary: glossary));
  await tester.pumpAndSettle();
}

Finder get _chevrons => find.byIcon(Icons.keyboard_arrow_down_rounded);
Finder get _closeButton => find.byIcon(Icons.close_rounded);

void main() {
  testWidgets('the whole map is on screen, with one step opened', (tester) async {
    await _pump(tester);

    // Every step is named, whether it is the open one or a row below it…
    expect(find.text('Subtract 5 from both sides'), findsOneWidget);
    expect(find.text('Divide both sides by 2'), findsOneWidget);
    // …and the road ends where the learner can see it does.
    expect(find.text('Solution'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);

    // Only one card is open: the other step and the Solution row stay rows.
    expect(_closeButton, findsOneWidget);
    expect(_chevrons, findsOneWidget); // step 2; the Solution row has a rail
    expect(tester.takeException(), isNull);
  });

  testWidgets('✕ shuts the card without moving your place', (tester) async {
    await _pump(tester);
    await tester.tap(_closeButton);
    await tester.pumpAndSettle();

    // The bare list — nothing opened, nothing lost.
    expect(_closeButton, findsNothing);
    expect(_chevrons, findsNWidgets(2));
    expect(find.text('Step 1 of 3'), findsOneWidget);

    // …and "Next step" reopens where you were, rather than skipping a step you
    // never actually read.
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    expect(_closeButton, findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('any row is a destination — forward or back', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Divide both sides by 2'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);

    // Straight to the end, then straight back to the start.
    await tester.tap(find.text('Solution'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3'), findsOneWidget);
    // The end of the road offers no "next" — only the way back.
    expect(find.text('Next step'), findsNothing);

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);
  });

  testWidgets('the span that changes is lit on both expressions', (tester) async {
    await _pump(tester);

    // The open card renders before and after at the same band, each with a
    // \textcolor overlay on the part that moves — the "5" leaving on top, the
    // "8" arriving underneath.
    final coloured = tester
        .widgetList<AdaptiveMath>(find.byType(AdaptiveMath))
        .where((a) => a.renderLatex?.contains(r'\textcolor') ?? false)
        .toList();
    expect(coloured.length, 2);
    expect(coloured.every((a) => a.maxFontSize == 28), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a glossary term inside the instruction defines itself in place',
      (tester) async {
    await _pump(tester, glossary: const [
      DefinedTerm(term: 'sides', plain: 'the two halves of an equation'),
    ]);

    // The instruction becomes rich text so the term can carry a tap target.
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((r) => r.text.toPlainText() == 'Subtract 5 from both sides');
    final links = <TapGestureRecognizer>[];
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
        links.add(span.recognizer! as TapGestureRecognizer);
      }
      return true;
    });
    expect(links, hasLength(1));

    links.single.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('the two halves of an equation'), findsOneWidget);
  });
}
