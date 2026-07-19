import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style QUADRATIC FORMULA walkthrough (e.g. `x^2 - 5x + 6 = 0`):
/// identify a, b, c → write the formula → substitute → discriminant → two roots.
///
/// GOLDEN RULE: the roots are real roots of the parsed equation AND appear in the
/// VERIFIED server answer — [tryBuild] declines otherwise (restricted to
/// integer-root quadratics so the display stays exact; everything else falls
/// through to the symbol-morph engine).
@immutable
class QuadraticStep {
  const QuadraticStep({required this.latex, required this.caption, this.callout});

  final String latex;
  final String caption;
  final String? callout;
}

@immutable
class QuadraticFormula {
  const QuadraticFormula({required this.steps});

  final List<QuadraticStep> steps;

  static QuadraticFormula? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final parsed = _parse(result.equation.latex);
    if (parsed == null) return null;
    final (a, b, c) = parsed;

    final disc = b * b - 4 * a * c;
    if (disc < 0) return null;
    final d = math.sqrt(disc).round();
    if (d * d != disc) return null; // rational-root quadratics only
    final den = 2 * a;
    final num1 = -b + d;
    final num2 = -b - d;
    if (num1 % den != 0 || num2 % den != 0) return null; // integer roots only
    final r1 = num1 ~/ den;
    final r2 = num2 ~/ den;

    // The verified answer must contain both roots (they are real roots by
    // construction — d² = disc — so this is the golden-rule alignment check).
    final answerNums = _answerInts(result.answerPlain);
    if (!answerNums.contains(r1) || !answerNums.contains(r2)) return null;

    return QuadraticFormula(steps: _steps(a, b, c, disc, d, den, r1, r2));
  }

  static (int, int, int)? _parse(String latex) {
    final s = latex
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(RegExp(r'\\cdot|\\times'), '')
        .replaceAll('x^{2}', 'x^2')
        .replaceAll('x²', 'x^2')
        .replaceAll('−', '-');
    final sides = s.split('=');
    if (sides.length != 2 || sides[1] != '0') return null;
    final lhs = sides[0];
    if (!lhs.contains('x^2')) return null;

    var a = 0, b = 0, c = 0;
    for (final match in RegExp(r'[+-]?[^+-]+').allMatches(lhs)) {
      var t = match.group(0)!;
      if (t.startsWith('+')) t = t.substring(1);
      if (t.contains('x^2')) {
        final v = _coef(t.replaceAll('x^2', ''));
        if (v == null) return null;
        a += v;
      } else if (t.contains('x')) {
        final v = _coef(t.replaceAll('x', ''));
        if (v == null) return null;
        b += v;
      } else {
        final v = int.tryParse(t);
        if (v == null) return null;
        c += v;
      }
    }
    if (a == 0) return null;
    return (a, b, c);
  }

  static int? _coef(String s) {
    if (s.isEmpty) return 1;
    if (s == '-') return -1;
    return int.tryParse(s);
  }

  /// Integers in the verified answer, ignoring subscripts (x_1, x_2).
  static Set<int> _answerInts(String answer) {
    final cleaned = answer.replaceAll(RegExp(r'_\{?\d+\}?'), '');
    return RegExp(r'-?\d+')
        .allMatches(cleaned)
        .map((m) => int.parse(m.group(0)!))
        .toSet();
  }

  static List<QuadraticStep> _steps(
      int a, int b, int c, int disc, int d, int den, int r1, int r2) {
    return [
      QuadraticStep(
        latex: _quad(a, b, c),
        caption: 'A quadratic — solve with the formula',
        callout: 'a=$a,\\ b=$b,\\ c=$c',
      ),
      const QuadraticStep(
        latex: r'x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}',
        caption: 'The quadratic formula',
      ),
      QuadraticStep(
        latex:
            'x=\\frac{-($b)\\pm\\sqrt{($b)^2-4($a)($c)}}{2($a)}',
        caption: 'Substitute a, b and c',
      ),
      QuadraticStep(
        latex: 'x=\\frac{${-b}\\pm\\sqrt{$disc}}{$den}',
        caption: 'Work out the discriminant',
        callout: 'b^2-4ac=$disc',
      ),
      QuadraticStep(
        latex: 'x=\\frac{${-b}\\pm$d}{$den}',
        caption: '\\sqrt{$disc}=$d',
      ),
      QuadraticStep(
        latex: 'x=$r1 \\quad\\text{or}\\quad x=$r2',
        caption: 'The two solutions',
      ),
    ];
  }

  static String _quad(int a, int b, int c) {
    final sb = StringBuffer()
      ..write(a == 1
          ? 'x^2'
          : (a == -1 ? '-x^2' : '${a}x^2'));
    if (b != 0) {
      final mag = b.abs() == 1 ? '' : '${b.abs()}';
      sb.write(b > 0 ? '+${mag}x' : '-${mag}x');
    }
    if (c != 0) sb.write(c > 0 ? '+$c' : '$c');
    sb.write('=0');
    return sb.toString();
  }
}
