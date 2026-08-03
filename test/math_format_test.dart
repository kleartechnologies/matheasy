import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/presentation/widgets/math_format.dart';

void main() {
  group('toDisplayLatex — inline division → stacked fraction', () {
    test('the reported bug: parenthesised rational folds to \\frac', () {
      expect(
        toDisplayLatex('(12p+9q)/(p^2-q^2)'),
        r'\frac{12p+9q}{p^2-q^2}',
      );
    });

    test('folds simple and numeric quotients', () {
      expect(toDisplayLatex('x/2'), r'\frac{x}{2}');
      expect(toDisplayLatex('1/2'), r'\frac{1}{2}');
      expect(toDisplayLatex('x^2/2'), r'\frac{x^2}{2}');
    });

    test('preserves the rest of the expression around the quotient', () {
      expect(toDisplayLatex('x = (a+b)/(c)'), r'x = \frac{a+b}{c}');
      expect(toDisplayLatex(r'a + b/2'), r'a + \frac{b}{2}');
    });

    test('folds with \\cdot operands inside parenthesised groups', () {
      expect(
        toDisplayLatex(r'(12 \cdot p + 9 \cdot q) / (p^2 - q^2)'),
        r'\frac{12 \cdot p + 9 \cdot q}{p^2 - q^2}',
      );
    });

    test('left-associative chains fold correctly', () {
      expect(toDisplayLatex('a/b/c'), r'\frac{\frac{a}{b}}{c}');
    });

    test('is idempotent and leaves existing \\frac untouched', () {
      const already = r'\frac{5}{6}';
      expect(toDisplayLatex(already), already);
      expect(toDisplayLatex(toDisplayLatex('x/2')), r'\frac{x}{2}');
    });

    test('no-slash input is returned verbatim', () {
      expect(toDisplayLatex('x = 4'), 'x = 4');
      expect(toDisplayLatex(r'\theta = 30^\circ'), r'\theta = 30^\circ');
    });

    test('does NOT mis-group function application / juxtaposition', () {
      // sin(x)/2 must not become sin(x/2) — left inline instead.
      expect(toDisplayLatex(r'\sin(x)/2'), r'\sin(x)/2');
      // a/f(x) must not become (a/f)(x) — left inline instead.
      expect(toDisplayLatex('a/f(x)'), 'a/f(x)');
    });

    test('stacks the Leibniz derivative operator applied to an argument', () {
      expect(toDisplayLatex('d/dx(x^2)'), r'\frac{d}{dx}(x^2)');
      expect(toDisplayLatex('d^2/dx^2(x^3)'), r'\frac{d^2}{dx^2}(x^3)');
    });

    test('a derivative ratio dx/dy still folds via the general rule', () {
      expect(toDisplayLatex('dx/dy'), r'\frac{dx}{dy}');
    });

    test('never throws on malformed input; returns something', () {
      for (final s in [r'\frac{a', '((a)/', 'a/', '/b', r'a \\ b/c']) {
        expect(() => toDisplayLatex(s), returnsNormally);
      }
    });
  });

  group('estimateMathWidthEm — width awareness', () {
    test('a stacked fraction is only as wide as its wider line', () {
      // \frac{5}{6} should be far narrower than a 10-char inline expression.
      final frac = estimateMathWidthEm(r'\frac{12p+9q}{p^2-q^2}');
      final inline = estimateMathWidthEm('12p+9q + p2q2 stuff here');
      expect(frac, lessThan(inline));
      // width ≈ the wider operand (~6 glyphs), not their sum (~12).
      expect(frac, lessThan(9));
    });

    test('short answers estimate small, long answers estimate large', () {
      expect(estimateMathWidthEm('x = 4'), lessThan(6));
      expect(
        estimateMathWidthEm(r'x = \frac{-3 \pm \sqrt{89}}{10}'),
        greaterThan(estimateMathWidthEm('x = 4')),
      );
    });

    test('a matrix is as wide as its widest row, not all cells summed', () {
      final matrix = estimateMathWidthEm(
          r'\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}');
      // Two 1-glyph columns + gaps — a handful of em, not a dozen.
      expect(matrix, greaterThan(2));
      expect(matrix, lessThan(12));
    });
  });

  group('adaptiveMathFontSize — bands + fit', () {
    test('short answer gets the max size', () {
      expect(
        adaptiveMathFontSize(
            latex: 'x = 4', maxWidth: 320, minFontSize: 48, maxFontSize: 56),
        56,
      );
    });

    test('a long answer shrinks toward — but not below — the min', () {
      final size = adaptiveMathFontSize(
        latex: r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a} + 12345678',
        maxWidth: 300,
        minFontSize: 32,
        maxFontSize: 56,
      );
      expect(size, greaterThanOrEqualTo(32));
      expect(size, lessThan(56));
    });

    test('degenerate width falls back to max', () {
      expect(
        adaptiveMathFontSize(
            latex: 'x', maxWidth: 0, minFontSize: 32, maxFontSize: 56),
        56,
      );
    });

    test('malformed LaTeX never throws from the sizing path (regression)', () {
      // Truncated \frac from OCR/vision used to throw FormatException out of the
      // LayoutBuilder and crash the answer/step subtree; it must degrade to the
      // max size so MathText's onErrorFallback can render the raw string.
      for (final s in [
        r'\frac{1}{2',
        r'\frac{a',
        r'\frac{\sqrt{2}}{3',
        r'x = \frac{1}{',
        r'\begin{bmatrix} 1 & 2',
        r'\frac{1}{2}/',
      ]) {
        expect(() => estimateMathWidthEm(s), returnsNormally, reason: s);
        final size = adaptiveMathFontSize(
            latex: s, maxWidth: 300, minFontSize: 32, maxFontSize: 56);
        expect(size, inInclusiveRange(32, 56), reason: s);
        expect(size.isFinite, isTrue, reason: s);
      }
    });
  });

  group('parseProblemStatement — worksheet layout, not source', () {
    test('the reported bug: instruction becomes prose, maths stays maths', () {
      final lines = parseProblemStatement(
        r'\text{Solve the equation} \\ 9^{4x-3} =\frac{1}{3\sqrt{3}}',
      );

      expect(lines, hasLength(2));
      expect(lines.first.isMath, isFalse);
      expect(lines.first.content, 'Solve the equation');
      expect(lines.last.isMath, isTrue);
      expect(lines.last.content, r'9^{4x-3} =\frac{1}{3\sqrt{3}}');
    });

    test('a leading instruction without a line break still lifts out', () {
      final lines = parseProblemStatement(r'\text{Find } x \text{ if } 2x = 8');
      // Leading prose above, the maths below; the mid-expression \text stays
      // put — pulling it out would reorder the sentence.
      expect(lines.first.isMath, isFalse);
      expect(lines.first.content, 'Find');
      expect(lines[1].isMath, isTrue);
      expect(lines[1].content, contains('2x = 8'));
    });

    test('a trailing instruction drops below the maths', () {
      final lines =
          parseProblemStatement(r'x^2 - 4 = 0 \\ \text{Give exact answers.}');
      expect(lines.last.isMath, isFalse);
      expect(lines.last.content, 'Give exact answers.');
    });

    test('matrix row breaks are NOT statement breaks', () {
      const m = r'\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}';
      final lines = parseProblemStatement(m);
      expect(lines, hasLength(1));
      expect(lines.single.isMath, isTrue);
      expect(lines.single.content, m);
    });

    test('strips the wrapping math delimiters storage sometimes carries', () {
      expect(parseProblemStatement(r'$x + 1$').single.content, 'x + 1');
      expect(parseProblemStatement(r'\[x + 1\]').single.content, 'x + 1');
    });

    test('degrades to one math line rather than losing the problem', () {
      expect(parseProblemStatement(r'\frac{1}{2').single.isMath, isTrue);
      expect(parseProblemStatement('  '), isEmpty);
    });
  });

  group('toReadableMath — the fallback a student can still read', () {
    test('the reported bug never shows a backslash', () {
      final out = toReadableMath(r'9^{4x-3} =\frac{1}{3\sqrt{3}}');
      expect(out, '9^(4x-3) = 1/(3√3)');
      expect(out, isNot(contains(r'\')));
    });

    test('folds fractions, roots and scripts into readable maths', () {
      expect(toReadableMath(r'\frac{a+b}{2}'), '(a+b)/2');
      expect(toReadableMath(r'\sqrt{2}'), '√2');
      expect(toReadableMath(r'\sqrt[3]{8}'), '8^(1/3)');
      expect(toReadableMath('x^2'), 'x²');
      expect(toReadableMath('a_1'), 'a₁');
    });

    test('speaks symbols instead of commands', () {
      expect(toReadableMath(r'\int_0^1 x \, dx'), contains('∫'));
      expect(toReadableMath(r'\alpha + \beta \le \pi'), 'α + β ≤ π');
      expect(toReadableMath(r'\sin\theta'), 'sinθ');
      expect(toReadableMath(r'90^\circ'), '90°');
    });

    test('matrices read as rows, not as an environment', () {
      expect(
        toReadableMath(r'\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}'),
        '[1, 2; 3, 4]',
      );
    });

    test('malformed input degrades quietly and drops every backslash', () {
      for (final s in [r'\frac{1}{2', r'\sqrt{', r'\begin{bmatrix} 1 & 2']) {
        expect(() => toReadableMath(s), returnsNormally, reason: s);
        expect(toReadableMath(s), isNot(contains(r'\')), reason: s);
      }
    });
  });
}
