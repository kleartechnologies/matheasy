import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style 2×2 DETERMINANT walkthrough (e.g. `|1 2; 3 4|`): main
/// diagonal minus anti-diagonal, ad − bc.
///
/// GOLDEN RULE: the computed determinant is checked against the VERIFIED server
/// answer — [tryBuild] declines otherwise.
@immutable
class MatrixDetStep {
  const MatrixDetStep({required this.latex, required this.caption, this.callout});

  final String latex;
  final String caption;
  final String? callout;
}

@immutable
class MatrixDeterminant {
  const MatrixDeterminant({required this.steps});

  final List<MatrixDetStep> steps;

  // \begin{vmatrix|pmatrix|bmatrix} a & b \\ c & d \end{...}
  static final RegExp _re = RegExp(
      r'\\begin\{[bpv]matrix\}(-?\d+)&(-?\d+)\\\\(-?\d+)&(-?\d+)\\end\{[bpv]matrix\}');

  static MatrixDeterminant? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final s = result.equation.latex
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(r'\det', '');
    final m = _re.firstMatch(s);
    if (m == null) return null;
    final a = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(2)!);
    final c = int.tryParse(m.group(3)!);
    final d = int.tryParse(m.group(4)!);
    if (a == null || b == null || c == null || d == null) return null;

    final det = a * d - b * c;
    final verified = int.tryParse(result.answerPlain.trim());
    if (verified == null || det != verified) return null;

    return MatrixDeterminant(steps: _steps(a, b, c, d, det));
  }

  static List<MatrixDetStep> _steps(int a, int b, int c, int d, int det) {
    final matrix = '\\begin{vmatrix}$a&$b\\\\$c&$d\\end{vmatrix}';
    final ad = a * d;
    final bc = b * c;
    final second = bc < 0 ? '$ad+${-bc}' : '$ad-$bc';
    return [
      MatrixDetStep(
        latex: matrix,
        caption: 'Determinant of a 2×2 matrix',
        callout: '= ad - bc',
      ),
      MatrixDetStep(
        latex: '($a)($d)-($b)($c)',
        caption: 'Main diagonal minus anti-diagonal',
      ),
      MatrixDetStep(
        latex: second,
        caption: 'Work out each product',
        callout: '$a\\times$d=$ad,\\ $b\\times$c=$bc',
      ),
      MatrixDetStep(
        latex: '$det',
        caption: 'The determinant is $det',
      ),
    ];
  }
}
