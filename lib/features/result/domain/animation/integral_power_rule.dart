import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style INTEGRAL walkthrough for a polynomial via the POWER RULE
/// (e.g. `∫(3x^2 + 4x - 5) dx`): add one to each power, divide by the new power,
/// add C.
///
/// GOLDEN RULE: the computed antiderivative (as a canonical power→reduced-fraction
/// map) must equal the VERIFIED server answer (C stripped) — [tryBuild] declines
/// otherwise (non-polynomials / unrecognised answer formats fall through to the
/// symbol-morph engine).
@immutable
class IntegralStep {
  const IntegralStep({required this.latex, required this.caption, this.callout});

  final String latex;
  final String caption;
  final String? callout;
}

@immutable
class IntegralPowerRule {
  const IntegralPowerRule({required this.steps});

  final List<IntegralStep> steps;

  static IntegralPowerRule? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final s = result.equation.latex
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(r'\,', '');
    // \int <integrand> d<var>  (indefinite only — no _a^b bounds)
    final m = RegExp(r'^\\int(.+?)d([a-z])$').firstMatch(s);
    if (m == null) return null;
    final v = m.group(2)!;
    var body = m.group(1)!;
    if (body.startsWith('(') && body.endsWith(')')) {
      body = body.substring(1, body.length - 1);
    }
    final poly = _parseIntPoly(body, v);
    if (poly == null || poly.isEmpty) return null;
    // A real integration (not ∫ of a bare constant).
    if (poly.keys.reduce((a, b) => a > b ? a : b) < 1) return null;

    // Antiderivative: c·x^p → (c/(p+1)) x^{p+1}.
    final anti = <int, (int, int)>{};
    poly.forEach((p, c) => anti[p + 1] = _reduce(c, p + 1));

    final answer = _parseRationalPoly(result.answerLatex, v) ??
        _parseRationalPoly(result.answerPlain, v);
    if (answer == null || !_ratMapsEqual(anti, answer)) return null;

    return IntegralPowerRule(steps: _steps(poly, anti, v));
  }

  static List<IntegralStep> _steps(
      Map<int, int> poly, Map<int, (int, int)> anti, String v) {
    final integrand = _intPolyLatex(poly, v);
    final result = _ratPolyLatex(anti, v, withC: true);
    return [
      IntegralStep(
        latex: '\\int\\left($integrand\\right)\\,d$v',
        caption: 'Integrate with the power rule',
        callout: '\\int $v^n\\,d$v=\\frac{$v^{n+1}}{n+1}+C',
      ),
      IntegralStep(
        latex: _expandedLatex(poly, v),
        caption: 'Add one to each power, divide by the new power',
      ),
      IntegralStep(
        latex: result,
        caption: 'Simplify, and add the constant C',
      ),
      IntegralStep(
        latex: '\\int\\left($integrand\\right)\\,d$v=$result',
        caption: 'The integral',
      ),
    ];
  }

  // ---- integrand (integer polynomial) parsing --------------------------------

  static Map<int, int>? _parseIntPoly(String raw, String v) {
    var s = raw
        .replaceAll(RegExp(r'\\cdot|\\times'), '')
        .replaceAll('−', '-')
        .replaceAllMapped(
            RegExp('$v' r'\^\{(\d+)\}'), (m) => '$v^${m.group(1)}');
    // Token-aware: rewrite the variable to x WITHOUT touching the same letter
    // inside a LaTeX command (e.g. don't turn \frac into \fxac when v is f/r/a/c).
    if (v != 'x') {
      s = s.replaceAll(RegExp(r'(?<![A-Za-z\\])' + v + r'(?![A-Za-z])'), 'x');
    }
    if (s.isEmpty) return null;
    final poly = <int, int>{};
    for (final match in RegExp(r'[+-]?[^+-]+').allMatches(s)) {
      var t = match.group(0)!;
      if (t.startsWith('+')) t = t.substring(1);
      if (t.isEmpty) continue;
      final cp = _coefPower(t);
      if (cp == null) return null;
      poly[cp.$2] = (poly[cp.$2] ?? 0) + cp.$1;
    }
    poly.removeWhere((k, v) => v == 0);
    return poly;
  }

  // ---- answer (rational polynomial) parsing ----------------------------------

  static Map<int, (int, int)>? _parseRationalPoly(String raw, String v) {
    var s = raw
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(RegExp(r'\\cdot|\\times'), '')
        .replaceAll(r'\,', '')
        .replaceAll('−', '-')
        .replaceAllMapped(
            RegExp('$v' r'\^\{(\d+)\}'), (m) => '$v^${m.group(1)}');
    // Token-aware: rewrite the variable to x WITHOUT touching the same letter
    // inside a LaTeX command (e.g. don't turn \frac into \fxac when v is f/r/a/c).
    if (v != 'x') {
      s = s.replaceAll(RegExp(r'(?<![A-Za-z\\])' + v + r'(?![A-Za-z])'), 'x');
    }
    if (s.isEmpty) return null;

    final out = <int, (int, int)>{};
    for (final match in RegExp(r'[+-]?[^+-]+').allMatches(s)) {
      var t = match.group(0)!;
      final neg = t.startsWith('-');
      if (t.startsWith('+') || t.startsWith('-')) t = t.substring(1);
      if (t.isEmpty) continue;
      if (t == 'C' || t == 'c') continue; // constant of integration

      int num;
      int den;
      int power;
      final frac = RegExp(r'^\\frac\{(.+?)\}\{(\d+)\}(.*)$').firstMatch(t);
      if (frac != null) {
        final n = frac.group(1)!;
        den = int.parse(frac.group(2)!);
        final trailing = frac.group(3)!;
        if (trailing.contains('x')) {
          // form B: \frac{int}{den} x^q
          final ni = int.tryParse(n);
          final pw = _powerOf(trailing);
          if (ni == null || pw == null) return null;
          num = ni;
          power = pw;
        } else if (trailing.isEmpty) {
          // form A: \frac{<x-expr>}{den}
          final cp = _coefPower(n);
          if (cp == null) return null;
          num = cp.$1;
          power = cp.$2;
        } else {
          return null;
        }
      } else {
        // form C: integer coeff x^power
        final cp = _coefPower(t);
        if (cp == null) return null;
        num = cp.$1;
        den = 1;
        power = cp.$2;
      }
      if (neg) num = -num;
      if (out.containsKey(power)) return null; // unexpected duplicate term
      out[power] = _reduce(num, den);
    }
    return out;
  }

  /// "2x^3"→(2,3), "x^3"→(1,3), "x"→(1,1), "-x"→(-1,1), "5"→(5,0).
  static (int, int)? _coefPower(String t) {
    final xp = RegExp(r'^(-?\d*)x\^(\d+)$').firstMatch(t);
    if (xp != null) return (_c(xp.group(1)!), int.parse(xp.group(2)!));
    final x1 = RegExp(r'^(-?\d*)x$').firstMatch(t);
    if (x1 != null) return (_c(x1.group(1)!), 1);
    final c0 = int.tryParse(t);
    if (c0 != null) return (c0, 0);
    return null;
  }

  static int _c(String s) => s.isEmpty ? 1 : (s == '-' ? -1 : int.parse(s));

  static int? _powerOf(String t) {
    final xp = RegExp(r'^x\^(\d+)$').firstMatch(t);
    if (xp != null) return int.parse(xp.group(1)!);
    if (t == 'x') return 1;
    return null;
  }

  // ---- fraction helpers ------------------------------------------------------

  static (int, int) _reduce(int n, int d) {
    if (d < 0) {
      n = -n;
      d = -d;
    }
    final g = _gcd(n.abs(), d);
    return g == 0 ? (n, d) : (n ~/ g, d ~/ g);
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  static bool _ratMapsEqual(Map<int, (int, int)> a, Map<int, (int, int)> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final o = b[e.key];
      if (o == null || o.$1 != e.value.$1 || o.$2 != e.value.$2) return false;
    }
    return true;
  }

  // ---- rendering -------------------------------------------------------------

  static String _intPolyLatex(Map<int, int> m, String v) {
    final powers = m.keys.toList()..sort((a, b) => b.compareTo(a));
    final sb = StringBuffer();
    for (var i = 0; i < powers.length; i++) {
      final p = powers[i];
      final c = m[p]!;
      final sign = c < 0 ? '-' : (i == 0 ? '' : '+');
      final mag = c.abs();
      final coef = (mag == 1 && p != 0) ? '' : '$mag';
      final xPart = p == 0 ? '' : (p == 1 ? v : '$v^{$p}');
      sb.write('$sign$coef$xPart');
    }
    return sb.isEmpty ? '0' : sb.toString();
  }

  static String _ratPolyLatex(Map<int, (int, int)> m, String v,
      {bool withC = false}) {
    final powers = m.keys.toList()..sort((a, b) => b.compareTo(a));
    final sb = StringBuffer();
    for (var i = 0; i < powers.length; i++) {
      final q = powers[i];
      final (num, den) = m[q]!;
      final neg = num < 0;
      final n = num.abs();
      final sign = neg ? '-' : (i == 0 ? '' : '+');
      final xp = q == 0 ? '' : (q == 1 ? v : '$v^{$q}');
      final String term;
      if (den == 1) {
        final coef = (n == 1 && q != 0) ? '' : '$n';
        term = '$coef$xp';
      } else {
        final numPart = n == 1 ? xp : '$n$xp';
        term = '\\frac{$numPart}{$den}';
      }
      sb.write('$sign$term');
    }
    var res = sb.isEmpty ? '0' : sb.toString();
    if (withC) res = '$res+C';
    return res;
  }

  static String _expandedLatex(Map<int, int> poly, String v) {
    final powers = poly.keys.toList()..sort((a, b) => b.compareTo(a));
    final sb = StringBuffer();
    for (var i = 0; i < powers.length; i++) {
      final p = powers[i];
      final c = poly[p]!;
      final sign = c < 0 ? '-' : (i == 0 ? '' : '+');
      final mag = c.abs();
      final coef = mag == 1 ? '' : '$mag';
      sb.write('$sign\\frac{$coef$v^{${p + 1}}}{${p + 1}}');
    }
    return '${sb.isEmpty ? '0' : sb}+C';
  }
}
