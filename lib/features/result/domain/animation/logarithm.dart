import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style LOGARITHM walkthrough (e.g. `log_2(8)`): a log asks "what
/// power of the base gives the number?".
///
/// GOLDEN RULE: only builds when base^answer == argument (an exact integer log)
/// AND the answer is the verified server answer — declines otherwise.
@immutable
class LogStep {
  const LogStep({required this.latex, required this.caption, this.callout});

  final String latex;
  final String caption;
  final String? callout;
}

@immutable
class Logarithm {
  const Logarithm({required this.steps});

  final List<LogStep> steps;

  static final RegExp _withBase = RegExp(r'^\\log_\{?(\d+)\}?\(?(\d+)\)?$');
  static final RegExp _base10 = RegExp(r'^\\log\(?(\d+)\)?$');

  static Logarithm? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final s = result.equation.latex.replaceAll(RegExp(r'\\left|\\right|\$|\s'), '');
    final y = int.tryParse(result.answerPlain.trim());
    if (y == null || y < 0) return null;

    int base;
    int arg;
    var base10 = false;
    final wb = _withBase.firstMatch(s);
    if (wb != null) {
      final b = int.tryParse(wb.group(1)!);
      final a = int.tryParse(wb.group(2)!);
      if (b == null || a == null) return null;
      base = b;
      arg = a;
    } else {
      final b10 = _base10.firstMatch(s);
      if (b10 == null) return null;
      final a = int.tryParse(b10.group(1)!);
      if (a == null) return null;
      base = 10;
      arg = a;
      base10 = true;
    }
    if (base < 2 || arg < 1) return null;

    // base^y must equal arg exactly (guards overflow by breaking early).
    var p = 1;
    for (var i = 0; i < y; i++) {
      p *= base;
      if (p > arg) break;
    }
    if (p != arg) return null;

    return Logarithm(steps: _steps(base, arg, y, base10));
  }

  static List<LogStep> _steps(int b, int x, int y, bool base10) {
    final logLatex = base10 ? '\\log($x)' : '\\log_{$b}($x)';
    return [
      LogStep(
        latex: logLatex,
        caption: base10
            ? 'A logarithm (base 10) asks: what power?'
            : 'A logarithm asks: what power?',
        callout: 'Which power of $b gives $x?',
      ),
      LogStep(
        latex: '$b^{$y}=$x',
        caption: 'Find the power',
        callout: '$b to the power $y is $x ✓',
      ),
      LogStep(
        latex: '$logLatex=$y',
        caption: 'So the answer is $y',
      ),
    ];
  }
}
