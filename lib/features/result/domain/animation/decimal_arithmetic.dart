import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style DECIMAL ARITHMETIC walkthrough (e.g. `3.2 + 1.45`,
/// `0.5 × 4`): line up the decimal points for +/−, or "multiply as whole
/// numbers then place the point" for ×.
///
/// GOLDEN RULE: the computed value is checked against the VERIFIED server answer
/// — [tryBuild] declines otherwise.
@immutable
class DecimalStep {
  const DecimalStep({required this.latex, required this.caption, this.callout});

  final String latex;
  final String caption;
  final String? callout;
}

@immutable
class DecimalArithmetic {
  const DecimalArithmetic({required this.steps});

  final List<DecimalStep> steps;

  // a <op> b, where at least one operand carries a decimal point.
  static final RegExp _expr =
      RegExp(r'^(\d+(?:\.\d+)?)([+\-*])(\d+(?:\.\d+)?)$');

  static DecimalArithmetic? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final cleaned = result.equation.latex
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(RegExp(r'\\times|\\cdot|×|·'), '*')
        .replaceAll('−', '-');
    final m = _expr.firstMatch(cleaned);
    if (m == null) return null;
    final a = m.group(1)!;
    final op = m.group(2)!;
    final b = m.group(3)!;
    // At least one real decimal (else it's plain integer column arithmetic).
    if (!a.contains('.') && !b.contains('.')) return null;

    final da = _decimals(a);
    final db = _decimals(b);
    final ai = _scaled(a); // digits as an int (3.2 → 32)
    final bi = _scaled(b);
    if (ai == null || bi == null) return null;

    final String resStr;
    switch (op) {
      case '+':
      case '-':
        final l = da > db ? da : db;
        final va = ai * _pow10(l - da);
        final vb = bi * _pow10(l - db);
        final res = op == '+' ? va + vb : va - vb;
        if (res < 0) return null; // keep it a positive, sign-free walkthrough
        resStr = _format(res, l);
      case '*':
        resStr = _format(ai * bi, da + db);
      default:
        return null;
    }

    if (_normalize(resStr) != _normalize(result.answerPlain.trim())) return null;

    final answer = _normalize(resStr);
    return DecimalArithmetic(
      steps: op == '*'
          ? _mulSteps(a, b, ai, bi, da, db, resStr, answer)
          : _addSubSteps(a, b, op, da, db, resStr, answer),
    );
  }

  static List<DecimalStep> _addSubSteps(String a, String b, String op, int da,
      int db, String resStr, String answer) {
    final word = op == '+' ? 'Add' : 'Subtract';
    final l = da > db ? da : db;
    final aPad = _pad(a, l);
    final bPad = _pad(b, l);
    final steps = <DecimalStep>[
      DecimalStep(
        latex: '$a $op $b',
        caption: 'Line up the decimal points',
        callout: 'Stack them so the points sit in one column',
      ),
    ];
    if (aPad != a || bPad != b) {
      steps.add(DecimalStep(
        latex: '$aPad $op $bPad',
        caption: 'Pad with zeros so both have the same decimals',
      ));
    }
    steps.add(DecimalStep(
      latex: resStr,
      caption: '$word as whole numbers, keep the point in line',
      callout: '$aPad $op $bPad = $resStr',
    ));
    steps.add(DecimalStep(
      latex: '$a $op $b = $answer',
      caption: 'So the answer is $answer',
    ));
    return steps;
  }

  static List<DecimalStep> _mulSteps(String a, String b, int ai, int bi, int da,
      int db, String resStr, String answer) {
    final places = da + db;
    final placeWord = places == 1 ? '1 decimal place' : '$places decimal places';
    return [
      DecimalStep(
        latex: '$a \\times $b',
        caption: 'Ignore the decimal points for now',
        callout: 'Multiply $ai × $bi',
      ),
      DecimalStep(
        latex: '$ai \\times $bi = ${ai * bi}',
        caption: 'Multiply as whole numbers',
      ),
      DecimalStep(
        latex: resStr,
        caption: 'Put the decimal point back',
        callout: '$da + $db = $placeWord',
      ),
      DecimalStep(
        latex: '$a \\times $b = $answer',
        caption: 'So the answer is $answer',
      ),
    ];
  }

  static int _decimals(String s) {
    final i = s.indexOf('.');
    return i < 0 ? 0 : s.length - i - 1;
  }

  static int? _scaled(String s) => int.tryParse(s.replaceAll('.', ''));

  static int _pow10(int k) {
    var v = 1;
    for (var i = 0; i < k; i++) {
      v *= 10;
    }
    return v;
  }

  /// Render an integer [value] scaled by [decimals] as a decimal string.
  static String _format(int value, int decimals) {
    if (decimals == 0) return '$value';
    final neg = value < 0;
    final s = value.abs().toString().padLeft(decimals + 1, '0');
    final cut = s.length - decimals;
    final out = '${s.substring(0, cut)}.${s.substring(cut)}';
    return neg ? '-$out' : out;
  }

  /// Pad a decimal string to [decimals] places (3.2 → 3.20).
  static String _pad(String s, int decimals) {
    if (decimals == 0) return s;
    final dot = s.indexOf('.');
    if (dot < 0) return '$s.${'0' * decimals}';
    final have = s.length - dot - 1;
    return have >= decimals ? s : s + ('0' * (decimals - have));
  }

  /// Trim trailing decimal zeros for answer comparison (2.0 → 2, 4.650 → 4.65).
  static String _normalize(String s) {
    if (!s.contains('.')) return s;
    var t = s;
    while (t.endsWith('0')) {
      t = t.substring(0, t.length - 1);
    }
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    return t;
  }
}
