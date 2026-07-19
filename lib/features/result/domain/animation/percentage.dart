import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style PERCENTAGE walkthrough (e.g. `15% of 80`): percent means
/// "out of 100", so rewrite as a fraction of 100 and multiply.
///
/// GOLDEN RULE: the computed value is checked against the VERIFIED server answer
/// — [tryBuild] declines otherwise. Note: if the app normalises a percent to
/// `\frac{15}{100}\times 80` or `0.15\times 80`, the fraction / decimal players
/// (earlier in the dispatch) handle it instead; this player catches the literal
/// `%` form.
@immutable
class PercentageStep {
  const PercentageStep({required this.latex, required this.caption, this.callout});

  final String latex;
  final String caption;
  final String? callout;
}

@immutable
class Percentage {
  const Percentage({required this.steps});

  final List<PercentageStep> steps;

  // "P% of B", "P% × B", "P%B" — after folding × / · / "of" to *.
  static final RegExp _re = RegExp(r'^(\d+)%\*?(\d+)$');

  static Percentage? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final cleaned = result.equation.latex
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(r'\%', '%')
        .replaceAll(RegExp(r'\\times|\\cdot|×|·'), '*')
        .replaceAll(r'\text{of}', '*')
        .replaceAll('of', '*');
    final m = _re.firstMatch(cleaned);
    if (m == null) return null;
    final p = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(2)!);
    if (p == null || b == null) return null;

    // result = p% × b = (p × b) / 100 — an integer scaled by 100.
    final answer = _normalize(_format(p * b, 2));
    if (answer != _normalize(result.answerPlain.trim())) return null;

    return Percentage(steps: _steps(p, b, answer));
  }

  static List<PercentageStep> _steps(int p, int b, String answer) {
    return [
      PercentageStep(
        latex: '$p\\% \\text{ of } $b',
        caption: "Percent means 'out of 100'",
        callout: '$p% = $p out of 100',
      ),
      PercentageStep(
        latex: '\\frac{$p}{100} \\times $b',
        caption: 'Write the percent as a fraction of 100',
        callout: '$p% → $p/100',
      ),
      PercentageStep(
        latex: answer,
        caption: 'Multiply it out',
        callout: '($p × $b) ÷ 100 = $answer',
      ),
      PercentageStep(
        latex: '$p\\% \\text{ of } $b = $answer',
        caption: 'So $p% of $b is $answer',
      ),
    ];
  }

  /// Render an integer [value] scaled by [decimals] as a decimal string.
  static String _format(int value, int decimals) {
    if (decimals == 0) return '$value';
    final s = value.abs().toString().padLeft(decimals + 1, '0');
    final cut = s.length - decimals;
    final out = '${s.substring(0, cut)}.${s.substring(cut)}';
    return value < 0 ? '-$out' : out;
  }

  /// Trim trailing decimal zeros (12.00 → 12, 10.50 → 10.5).
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
