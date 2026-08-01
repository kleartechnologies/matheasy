import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/math_semantics.dart';
import 'package:matheasy/core/widgets/chat/highlighted_math.dart';

/// A stand-in palette, so these tests assert the WRAPPING rules rather than the
/// current hex of any token.
String _hex(MathRole role) => switch (role) {
      MathRole.answer => '#111111',
      MathRole.known => '#222222',
      MathRole.operation => '#333333',
      MathRole.unknown => '#444444',
      MathRole.mistake => '#555555',
      MathRole.aside => '#666666',
    };

String _colorize(String latex, List<MathHighlight> spans) =>
    colorizeLatex(latex, spans, _hex);

void main() {
  // Spec Part 8: highlight ONLY the part being explained. A highlight is a view
  // over maths the app already verified, so the one thing it may never do is
  // change what the equation says — a span that can't be wrapped safely is
  // dropped and the equation still renders.
  group('colorizeLatex', () {
    test('wraps the highlighted piece and leaves the rest alone', () {
      expect(
        _colorize('x^2 + 8x + 4 = 0', const [
          MathHighlight(text: '8x', role: MathRole.operation),
        ]),
        r'x^2 + \textcolor{#333333}{8x} + 4 = 0',
      );
    });

    test('wraps several pieces, each in its own role colour', () {
      expect(
        _colorize('2x + 3 = 11', const [
          MathHighlight(text: 'x', role: MathRole.unknown),
          MathHighlight(text: '11', role: MathRole.known),
        ]),
        r'2\textcolor{#444444}{x} + 3 = \textcolor{#222222}{11}',
      );
    });

    test('wraps in position order however the spans were listed', () {
      expect(
        _colorize('a + b', const [
          MathHighlight(text: 'b', role: MathRole.answer),
          MathHighlight(text: 'a', role: MathRole.known),
        ]),
        r'\textcolor{#222222}{a} + \textcolor{#111111}{b}',
      );
    });

    test('gives each repeat of the same symbol its own occurrence', () {
      expect(
        _colorize('x + x', const [
          MathHighlight(text: 'x', role: MathRole.unknown),
          MathHighlight(text: 'x', role: MathRole.answer),
        ]),
        r'\textcolor{#444444}{x} + \textcolor{#111111}{x}',
      );
    });

    test('leaves the equation untouched when there is nothing to highlight', () {
      expect(_colorize('x + 1', const []), 'x + 1');
      expect(_colorize('', const [MathHighlight(text: 'x', role: MathRole.known)]),
          '');
    });

    test('drops a span that does not appear in the equation', () {
      expect(
        _colorize('x + 1', const [
          MathHighlight(text: 'y', role: MathRole.unknown),
        ]),
        'x + 1',
      );
    });

    // Each of these would produce LaTeX that renders wrongly or not at all.
    test('drops a span that would break the LaTeX', () {
      const cases = <(String, MathHighlight, String)>[
        (
          r'\frac{1}{2} + x',
          MathHighlight(text: r'\fr', role: MathRole.known),
          r'splits \frac in half',
        ),
        (
          r'\frac{1}{2}',
          MathHighlight(text: '{1', role: MathRole.known),
          'leaves a brace unbalanced',
        ),
        (
          r'\sqrt{16}',
          MathHighlight(text: '16}', role: MathRole.answer),
          'closes a group it never opened',
        ),
        (
          'x^2 + 1',
          MathHighlight(text: 'x^', role: MathRole.unknown),
          'raises nothing',
        ),
        (
          'x^2 + 1',
          MathHighlight(text: '^2', role: MathRole.operation),
          'a script with no base',
        ),
        (
          r'x &= 1 \\ y &= 2',
          MathHighlight(text: '&=', role: MathRole.aside),
          'alignment markup only parses at the top level',
        ),
      ];
      for (final (latex, span, why) in cases) {
        expect(
          _colorize(latex, [span]),
          latex,
          reason: 'wrapping "${span.text}" in "$latex" $why',
        );
      }
    });

    test('wraps a whole command, which is safe, even though half of one is not',
        () {
      expect(
        _colorize(r'\frac{1}{2} + x', const [
          MathHighlight(text: r'\frac{1}{2}', role: MathRole.known),
        ]),
        r'\textcolor{#222222}{\frac{1}{2}} + x',
      );
    });

    test('keeps a good span when a bad one sits beside it', () {
      expect(
        _colorize('x^2 + 4', const [
          MathHighlight(text: 'x^', role: MathRole.unknown),
          MathHighlight(text: '4', role: MathRole.known),
        ]),
        r'x^2 + \textcolor{#222222}{4}',
      );
    });

    test('never lets two highlights overlap', () {
      // "2x" and "x" both want the same x; the second finds no free occurrence.
      expect(
        _colorize('2x + 1', const [
          MathHighlight(text: '2x', role: MathRole.operation),
          MathHighlight(text: 'x', role: MathRole.unknown),
        ]),
        r'\textcolor{#333333}{2x} + 1',
      );
    });

  });

  group('HighlightedMath', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders the equation', (tester) async {
      await tester.pumpWidget(host(
        const HighlightedMath(
          latex: '2x + 3 = 11',
          highlights: [MathHighlight(text: 'x', role: MathRole.unknown)],
          textStyle: TextStyle(fontSize: 18),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsWidgets);
    });

    // The colour arrives as a cross-fade (spec Part 8: "colours should animate
    // smoothly"), which means an opacity that starts below 1 and reaches it.
    testWidgets('fades the colour in', (tester) async {
      await tester.pumpWidget(host(
        const HighlightedMath(
          latex: '2x + 3 = 11',
          highlights: [MathHighlight(text: 'x', role: MathRole.unknown)],
          textStyle: TextStyle(fontSize: 18),
        ),
      ));
      final fade = find.descendant(
        of: find.byType(AnimatedOpacity),
        matching: find.byType(FadeTransition),
      );
      double opacity() => tester.widget<FadeTransition>(fade).opacity.value;

      await tester.pump(); // the reveal starts a frame after layout
      expect(opacity(), 0);
      await tester.pump(const Duration(milliseconds: 250));
      expect(opacity(), greaterThan(0));
      expect(opacity(), lessThan(1), reason: 'the colour should still be arriving');
      await tester.pumpAndSettle();
      expect(opacity(), 1);
    });

    testWidgets('skips the fade when the student has asked for less motion',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: HighlightedMath(
              latex: '2x + 3 = 11',
              highlights: [MathHighlight(text: 'x', role: MathRole.unknown)],
              textStyle: TextStyle(fontSize: 18),
            ),
          ),
        ),
      ));
      await tester.pump();
      final fade = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(fade.opacity, 1, reason: 'the colour should be there immediately');
      expect(fade.duration, Duration.zero);
    });

    // The point of every wrapping rule above: what we hand the renderer must
    // actually render.
    testWidgets('the coloured LaTeX parses', (tester) async {
      final coloured = _colorize(r'\frac{d}{dx}(x^2) = 2x', const [
        MathHighlight(text: r'\frac{d}{dx}', role: MathRole.operation),
        MathHighlight(text: '2x', role: MathRole.answer),
      ]);
      expect(coloured, contains(r'\textcolor{#333333}{\frac{d}{dx}}'));

      await tester.pumpWidget(host(Math.tex(
        coloured,
        onErrorFallback: (_) => const Text('BROKEN'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('BROKEN'), findsNothing);
    });

    // Nothing wrappable → one plain equation, not a stack of two.
    testWidgets('renders plainly when no highlight applies', (tester) async {
      await tester.pumpWidget(host(
        const HighlightedMath(
          latex: '2x + 3 = 11',
          highlights: [MathHighlight(text: 'z', role: MathRole.unknown)],
          textStyle: TextStyle(fontSize: 18),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(find.byType(Math), findsOneWidget);
    });
  });
}
