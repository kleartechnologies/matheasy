import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style FRACTION ARITHMETIC walkthrough — add, subtract, multiply,
/// or divide two fractions (e.g. `1/2 + 1/3`, `2/3 × 3/4`, `1/2 ÷ 3/4`).
///
/// Each step carries the current expression as LaTeX (the view renders it with the
/// real fraction renderer) plus a plain caption and an optional callout for the key
/// move (the common denominator, the numerator sum, the simplification).
///
/// GOLDEN RULE: the final reduced fraction must equal the VERIFIED server answer —
/// [tryBuild] declines otherwise, so the walkthrough can never end on a value the
/// solver didn't confirm.
@immutable
class FractionStep {
  const FractionStep({required this.latex, required this.caption, this.callout});

  /// The current expression as delimiter-free LaTeX (uses `\frac{}{}`).
  final String latex;
  final String caption;
  final String? callout;
}

@immutable
class FractionArithmetic {
  const FractionArithmetic({required this.steps});

  final List<FractionStep> steps;

  static int _gcd(int a, int b) {
    a = a.abs();
    b = b.abs();
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a == 0 ? 1 : a;
  }

  static int _lcm(int a, int b) => (a ~/ _gcd(a, b)) * b;

  static (int, int) _reduce(int n, int d) {
    if (d < 0) {
      n = -n;
      d = -d;
    }
    final g = _gcd(n, d);
    return (n ~/ g, d ~/ g);
  }

  static String _frac(int n, int d) {
    if (d == 1) return '$n';
    if (n < 0) return '-\\frac{${-n}}{$d}';
    return '\\frac{$n}{$d}';
  }

  // \frac{a}{b} <op> \frac{c}{d}, ops: + - * / (× ÷ folded), operands can be bare ints.
  static final RegExp _pair = RegExp(
      r'^(?:\\frac\{(\d+)\}\{(\d+)\}|(\d+))([+\-*/])(?:\\frac\{(\d+)\}\{(\d+)\}|(\d+))$');

  /// Build for a verified two-fraction problem, else null.
  static FractionArithmetic? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final cleaned = result.equation.latex
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(RegExp(r'\\times|\\cdot|×'), '*')
        .replaceAll(RegExp(r'\\div|÷'), '/')
        .replaceAll('−', '-');
    final m = _pair.firstMatch(cleaned);
    if (m == null) return null;

    // Require at least one real fraction (else it's plain integer arithmetic).
    final aFrac = m.group(1) != null;
    final bFrac = m.group(5) != null;
    if (!aFrac && !bFrac) return null;

    final n1 = int.parse(m.group(1) ?? m.group(3)!);
    final d1 = int.parse(m.group(2) ?? '1');
    final op = m.group(4)!;
    final n2 = int.parse(m.group(5) ?? m.group(7)!);
    final d2 = int.parse(m.group(6) ?? '1');
    if (d1 == 0 || d2 == 0) return null;

    // Compute the exact result as a reduced fraction.
    int rn, rd;
    switch (op) {
      case '+':
        rn = n1 * d2 + n2 * d1;
        rd = d1 * d2;
      case '-':
        rn = n1 * d2 - n2 * d1;
        rd = d1 * d2;
      case '*':
        rn = n1 * n2;
        rd = d1 * d2;
      case '/':
        if (n2 == 0) return null;
        rn = n1 * d2;
        rd = d1 * n2;
      default:
        return null;
    }
    final (rrn, rrd) = _reduce(rn, rd);
    if (!_matchesAnswer(result.answerPlain, rrn, rrd)) return null;

    final steps = switch (op) {
      '+' || '-' => _addSubSteps(n1, d1, op, n2, d2, rrn, rrd),
      '*' => _mulSteps(n1, d1, n2, d2, rrn, rrd),
      '/' => _divSteps(n1, d1, n2, d2, rrn, rrd),
      _ => null,
    };
    if (steps == null || steps.length < 2) return null;
    return FractionArithmetic(steps: steps);
  }

  /// The verified answer (as `n/d`, `-n/d`, or an integer) equals `rn/rd`?
  static bool _matchesAnswer(String answerPlain, int rn, int rd) {
    final s = answerPlain.trim();
    final fm = RegExp(r'^(-?\d+)\s*/\s*(-?\d+)$').firstMatch(s);
    if (fm != null) {
      final rawN = int.parse(fm.group(1)!);
      final rawD = int.parse(fm.group(2)!);
      if (rawD == 0) return false;
      final (an, ad) = _reduce(rawN, rawD);
      return an == rn && ad == rd;
    }
    final iv = int.tryParse(s);
    if (iv != null) return rd == 1 && rn == iv;
    return false;
  }

  static String _opSym(String op) => op == '+' ? '+' : '-';

  static List<FractionStep> _addSubSteps(
      int n1, int d1, String op, int n2, int d2, int rn, int rd) {
    final steps = <FractionStep>[
      FractionStep(
        latex: '${_frac(n1, d1)} ${_opSym(op)} ${_frac(n2, d2)}',
        caption: 'Start with the two fractions',
      ),
    ];

    int cn1 = n1, cn2 = n2, den = d1;
    if (d1 != d2) {
      final l = _lcm(d1, d2);
      cn1 = n1 * (l ~/ d1);
      cn2 = n2 * (l ~/ d2);
      den = l;
      steps.add(FractionStep(
        latex: '${_frac(n1, d1)} ${_opSym(op)} ${_frac(n2, d2)}',
        caption: 'Find a common denominator',
        callout: 'LCD of $d1 and $d2 = $l',
      ));
      steps.add(FractionStep(
        latex: '${_frac(cn1, l)} ${_opSym(op)} ${_frac(cn2, l)}',
        caption: 'Rewrite each fraction over $l',
        callout: '${_frac(n1, d1)} = ${_frac(cn1, l)},  ${_frac(n2, d2)} = ${_frac(cn2, l)}'
            .replaceAll(r'\frac', r'\tfrac'),
      ));
    }

    final combined = op == '+' ? cn1 + cn2 : cn1 - cn2;
    steps.add(FractionStep(
      latex: _frac(combined, den),
      caption: 'Combine the numerators',
      callout: '$cn1 ${_opSym(op)} $cn2 = $combined',
    ));

    if ((combined, den) != (rn, rd)) {
      steps.add(FractionStep(
        latex: _frac(rn, rd),
        caption: 'Simplify the fraction',
        callout: 'divide by ${_gcd(combined, den)}',
      ));
    }
    steps.add(FractionStep(
      latex: _frac(rn, rd),
      caption: 'The result is ${_plain(rn, rd)}',
    ));
    return steps;
  }

  static List<FractionStep> _mulSteps(
      int n1, int d1, int n2, int d2, int rn, int rd) {
    final pn = n1 * n2, pd = d1 * d2;
    final steps = <FractionStep>[
      FractionStep(
        latex: '${_frac(n1, d1)} \\times ${_frac(n2, d2)}',
        caption: 'Start with the two fractions',
      ),
      FractionStep(
        latex: '\\frac{$n1 \\times $n2}{$d1 \\times $d2}',
        caption: 'Multiply the numerators and the denominators',
        callout: '$n1 × $n2 = $pn,  $d1 × $d2 = $pd',
      ),
      FractionStep(latex: _frac(pn, pd), caption: 'Multiply straight across'),
    ];
    if ((pn, pd) != (rn, rd)) {
      steps.add(FractionStep(
        latex: _frac(rn, rd),
        caption: 'Simplify the fraction',
        callout: 'divide by ${_gcd(pn, pd)}',
      ));
    }
    steps.add(FractionStep(
        latex: _frac(rn, rd), caption: 'The result is ${_plain(rn, rd)}'));
    return steps;
  }

  static List<FractionStep> _divSteps(
      int n1, int d1, int n2, int d2, int rn, int rd) {
    final pn = n1 * d2, pd = d1 * n2;
    final steps = <FractionStep>[
      FractionStep(
        latex: '${_frac(n1, d1)} \\div ${_frac(n2, d2)}',
        caption: 'Start with the two fractions',
      ),
      FractionStep(
        latex: '${_frac(n1, d1)} \\times ${_frac(d2, n2)}',
        caption: 'Flip the second fraction and multiply',
        callout: '÷ ${_plain(n2, d2)}  becomes  × ${_plain(d2, n2)}',
      ),
      FractionStep(
        latex: '\\frac{$n1 \\times $d2}{$d1 \\times $n2}',
        caption: 'Multiply the numerators and the denominators',
        callout: '$n1 × $d2 = $pn,  $d1 × $n2 = $pd',
      ),
      FractionStep(latex: _frac(pn, pd), caption: 'Multiply straight across'),
    ];
    if ((pn, pd) != (rn, rd)) {
      steps.add(FractionStep(
        latex: _frac(rn, rd),
        caption: 'Simplify the fraction',
        callout: 'divide by ${_gcd(pn, pd)}',
      ));
    }
    steps.add(FractionStep(
        latex: _frac(rn, rd), caption: 'The result is ${_plain(rn, rd)}'));
    return steps;
  }

  static String _plain(int n, int d) => d == 1 ? '$n' : '$n/$d';
}
