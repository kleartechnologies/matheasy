import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style walkthrough for POWERS (`2^5`) and PERFECT ROOTS
/// (`√144`, `∛27`): a power expands into repeated multiplication; a root asks
/// "what number, raised to k, gives n?".
///
/// GOLDEN RULE: the computed value is checked against the VERIFIED server answer
/// — [tryBuild] declines otherwise (non-perfect roots fall through to other
/// engines).
@immutable
class PowerRootStep {
  const PowerRootStep({required this.latex, required this.caption, this.callout});

  final String latex;
  final String caption;
  final String? callout;
}

@immutable
class PowerRoot {
  const PowerRoot({required this.steps});

  final List<PowerRootStep> steps;

  static final RegExp _power = RegExp(r'^(\d+)\^\{?(\d+)\}?$');
  static final RegExp _sqrt = RegExp(r'^\\sqrt\{(\d+)\}$');
  static final RegExp _nthRoot = RegExp(r'^\\sqrt\[(\d+)\]\{(\d+)\}$');

  static PowerRoot? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final cleaned =
        result.equation.latex.replaceAll(RegExp(r'\\left|\\right|\$|\s'), '');
    final verified = int.tryParse(result.answerPlain.trim());
    if (verified == null) return null;

    final power = _power.firstMatch(cleaned);
    if (power != null) {
      final b = int.tryParse(power.group(1)!);
      final e = int.tryParse(power.group(2)!);
      if (b == null || e == null) return null;
      // Keep it a sensible, non-overflowing walkthrough.
      if (b < 2 || b > 40 || e < 2 || e > 8) return null;
      var p = 1;
      for (var i = 0; i < e; i++) {
        p *= b;
      }
      if (p != verified) return null;
      return PowerRoot(steps: _powerSteps(b, e, p));
    }

    final sqrt = _sqrt.firstMatch(cleaned);
    if (sqrt != null) {
      final n = int.tryParse(sqrt.group(1)!);
      if (n == null || n < 1) return null;
      final r = math.sqrt(n).round();
      if (r * r != n) return null; // perfect squares only
      if (r != verified) return null;
      return PowerRoot(steps: _rootSteps(2, n, r));
    }

    final nth = _nthRoot.firstMatch(cleaned);
    if (nth != null) {
      final k = int.tryParse(nth.group(1)!);
      final n = int.tryParse(nth.group(2)!);
      if (k == null || n == null || k < 2 || k > 8 || n < 1) return null;
      final r = math.pow(n, 1 / k).round();
      var pr = 1;
      for (var i = 0; i < k; i++) {
        pr *= r;
      }
      if (pr != n) return null; // perfect kth powers only
      if (r != verified) return null;
      return PowerRoot(steps: _rootSteps(k, n, r));
    }

    return null;
  }

  static List<PowerRootStep> _powerSteps(int b, int e, int p) {
    final expansion = List.filled(e, '$b').join(r' \times ');
    // The running product, worked left to right (2 → 4 → 8 → 16 → 32).
    final chain = <int>[];
    var run = 1;
    for (var i = 0; i < e; i++) {
      run *= b;
      chain.add(run);
    }
    return [
      PowerRootStep(
        latex: '$b^{$e}',
        caption: '$b to the power of $e',
        callout: 'Multiply $b by itself $e times',
      ),
      PowerRootStep(
        latex: expansion,
        caption: 'Write it as repeated multiplication',
      ),
      PowerRootStep(
        latex: '$p',
        // A square has a single multiplication — the running chain (2→4→8…) only
        // helps for e ≥ 3, so squares just show b × b = p.
        caption: e == 2 ? 'Multiply it out' : 'Multiply left to right',
        callout: e == 2 ? '$b × $b = $p' : chain.join(' → '),
      ),
      PowerRootStep(
        latex: '$b^{$e} = $p',
        caption: 'So $b to the power of $e is $p',
      ),
    ];
  }

  static List<PowerRootStep> _rootSteps(int k, int n, int r) {
    final rootLatex = k == 2 ? '\\sqrt{$n}' : '\\sqrt[$k]{$n}';
    final power = k == 2 ? '$r \\times $r' : '$r^{$k}';
    final ask = k == 2
        ? 'What number times itself gives $n?'
        : 'What number to the power $k gives $n?';
    return [
      PowerRootStep(
        latex: rootLatex,
        caption: k == 2 ? 'The square root of $n' : 'The ${_ordinal(k)} root of $n',
        callout: ask,
      ),
      PowerRootStep(
        latex: '$power = $n',
        caption: 'Test $r',
        callout: '$r works ✓',
      ),
      PowerRootStep(
        latex: '$rootLatex = $r',
        caption: 'So the answer is $r',
      ),
    ];
  }

  static String _ordinal(int k) => switch (k) {
        3 => 'cube',
        4 => 'fourth',
        5 => 'fifth',
        6 => 'sixth',
        7 => 'seventh',
        8 => 'eighth',
        _ => '${k}th',
      };
}
