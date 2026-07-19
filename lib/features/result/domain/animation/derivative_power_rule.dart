import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style DERIVATIVE walkthrough for a polynomial via the POWER RULE
/// (e.g. `d/dx(x^3 + 2x^2 - 5x + 1)`): bring each power down as a multiplier and
/// drop it by one.
///
/// GOLDEN RULE: the computed derivative must equal the VERIFIED server answer
/// (compared as canonical power→coefficient maps) — [tryBuild] declines
/// otherwise (non-polynomials / other forms fall through to the engine).
@immutable
class DerivativeStep {
  const DerivativeStep({required this.latex, required this.caption, this.callout});

  final String latex;
  final String caption;
  final String? callout;
}

@immutable
class DerivativePowerRule {
  const DerivativePowerRule({required this.steps});

  final List<DerivativeStep> steps;

  static DerivativePowerRule? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final s = result.equation.latex.replaceAll(RegExp(r'\\left|\\right|\$|\s'), '');
    // Require an explicit d/d<var>( … ) operator.
    final m = RegExp(r'^\\frac\{d\}\{d([a-z])\}(.+)$').firstMatch(s);
    if (m == null) return null;
    final varName = m.group(1)!;
    var body = m.group(2)!;
    if (body.startsWith('(') && body.endsWith(')')) {
      body = body.substring(1, body.length - 1);
    }
    final poly = _parsePoly(body, varName);
    if (poly == null || poly.isEmpty) return null;
    // Worth a power-rule demo (not just d/dx of a constant or a bare line).
    if ((poly.keys.reduce((a, b) => a > b ? a : b)) < 2) return null;

    final deriv = <int, int>{};
    poly.forEach((p, c) {
      if (p >= 1) deriv[p - 1] = (deriv[p - 1] ?? 0) + c * p;
    });
    deriv.removeWhere((k, v) => v == 0);
    if (deriv.isEmpty) return null;

    final answerPoly = _parsePoly(result.answerLatex, varName) ??
        _parsePoly(result.answerPlain, varName);
    if (answerPoly == null || !_mapsEqual(deriv, answerPoly)) return null;

    return DerivativePowerRule(steps: _steps(poly, deriv));
  }

  static List<DerivativeStep> _steps(Map<int, int> poly, Map<int, int> deriv) {
    final original = _polyLatex(poly);
    final derivLatex = _polyLatex(deriv);
    return [
      DerivativeStep(
        latex: '\\frac{d}{dx}\\left($original\\right)',
        caption: 'Differentiate with the power rule',
        callout: '\\frac{d}{dx}x^n = n\\,x^{n-1}',
      ),
      DerivativeStep(
        latex: _expandedLatex(poly),
        caption: 'Bring each power down as a multiplier, drop it by one',
      ),
      DerivativeStep(
        latex: derivLatex,
        caption: 'Multiply out',
      ),
      DerivativeStep(
        latex: '\\frac{d}{dx}\\left($original\\right)=$derivLatex',
        caption: 'The derivative',
      ),
    ];
  }

  static Map<int, int>? _parsePoly(String raw, String varName) {
    var s = raw
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(RegExp(r'\\cdot|\\times'), '')
        .replaceAll('−', '-')
        .replaceAllMapped(
            RegExp('$varName' r'\^\{(\d+)\}'), (m) => '$varName^${m.group(1)}');
    if (varName != 'x') s = s.replaceAll(varName, 'x');
    if (s.isEmpty) return null;

    final poly = <int, int>{};
    for (final match in RegExp(r'[+-]?[^+-]+').allMatches(s)) {
      var t = match.group(0)!;
      if (t.startsWith('+')) t = t.substring(1);
      if (t.isEmpty) continue;
      int power;
      String coefStr;
      final xp = RegExp(r'^(.*)x\^(\d+)$').firstMatch(t);
      if (xp != null) {
        power = int.parse(xp.group(2)!);
        coefStr = xp.group(1)!;
      } else if (t.contains('x')) {
        power = 1;
        coefStr = t.replaceAll('x', '');
      } else {
        power = 0;
        coefStr = t;
      }
      final c = _coef(coefStr, power);
      if (c == null) return null;
      poly[power] = (poly[power] ?? 0) + c;
    }
    poly.removeWhere((k, v) => v == 0);
    return poly;
  }

  static int? _coef(String s, int power) {
    if (s.isEmpty) return power == 0 ? null : 1;
    if (s == '-') return -1;
    return int.tryParse(s);
  }

  static bool _mapsEqual(Map<int, int> a, Map<int, int> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  static String _polyLatex(Map<int, int> m) {
    final powers = m.keys.toList()..sort((a, b) => b.compareTo(a));
    final sb = StringBuffer();
    for (var i = 0; i < powers.length; i++) {
      final p = powers[i];
      final c = m[p]!;
      final sign = c < 0 ? '-' : (i == 0 ? '' : '+');
      final mag = c.abs();
      final coefPart = (mag == 1 && p != 0) ? '' : '$mag';
      final xPart = p == 0 ? '' : (p == 1 ? 'x' : 'x^{$p}');
      sb.write('$sign$coefPart$xPart');
    }
    return sb.isEmpty ? '0' : sb.toString();
  }

  static String _expandedLatex(Map<int, int> poly) {
    final powers = poly.keys.where((p) => p >= 1).toList()
      ..sort((a, b) => b.compareTo(a));
    final sb = StringBuffer();
    for (var i = 0; i < powers.length; i++) {
      final p = powers[i];
      final c = poly[p]!;
      final sign = c < 0 ? '-' : (i == 0 ? '' : '+');
      final mag = c.abs();
      final np = p - 1;
      final xPart = np == 0 ? '' : (np == 1 ? 'x' : 'x^{$np}');
      sb.write('$sign$mag\\cdot$p\\,$xPart');
    }
    return sb.isEmpty ? '0' : sb.toString();
  }
}
