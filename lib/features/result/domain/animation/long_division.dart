import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style LONG DIVISION walkthrough (e.g. `156 ÷ 4`): the classic
/// bracket worksheet built beat-by-beat — divide, multiply, subtract, bring
/// down — for each quotient digit.
///
/// GOLDEN RULE: only builds for an EXACT integer division whose quotient equals
/// the VERIFIED server answer; [tryBuild] declines otherwise (remainders and
/// non-integer results fall through to other engines).

enum DivMarkKind { quotient, product, difference, broughtDown }

/// A group of digits placed on the worksheet grid.
@immutable
class DivMark {
  const DivMark({
    required this.kind,
    required this.row,
    required this.rightCol,
    required this.digits,
    required this.revealAt,
  });

  final DivMarkKind kind;

  /// Vertical slot: 0 = quotient (above the bracket), 1 = dividend, ≥2 = work.
  final int row;

  /// The rightmost dividend column this mark aligns to (0 = leftmost digit).
  final int rightCol;
  final List<int> digits;

  /// The beat index at which this mark first appears.
  final int revealAt;

  int get leftCol => rightCol - (digits.length - 1);
}

/// A subtraction rule drawn just above [row], spanning [leftCol]..[rightCol].
@immutable
class DivLine {
  const DivLine({
    required this.row,
    required this.leftCol,
    required this.rightCol,
    required this.revealAt,
  });

  final int row;
  final int leftCol;
  final int rightCol;
  final int revealAt;
}

@immutable
class DivStep {
  const DivStep({required this.caption, this.callout});

  final String caption;
  final String? callout;
}

@immutable
class LongDivision {
  const LongDivision({
    required this.dividendDigits,
    required this.divisor,
    required this.quotient,
    required this.cols,
    required this.rows,
    required this.marks,
    required this.lines,
    required this.steps,
  });

  final List<int> dividendDigits;
  final int divisor;
  final int quotient;

  /// Number of dividend columns (grid width).
  final int cols;

  /// Number of vertical slots used (grid height).
  final int rows;

  final List<DivMark> marks;
  final List<DivLine> lines;
  final List<DivStep> steps;

  List<int> get divisorDigits =>
      divisor.toString().split('').map(int.parse).toList(growable: false);

  static LongDivision? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final cleaned =
        result.equation.latex.replaceAll(RegExp(r'\\left|\\right|\$|\s'), '');
    final norm = cleaned.replaceAll(r'\div', '÷').replaceAll(r'\divide', '÷');
    final m = RegExp(r'^(\d+)÷(\d+)$').firstMatch(norm);
    if (m == null) return null;
    final a = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(2)!);
    if (a == null || b == null) return null;
    if (b < 2 || a < 10 || a < b) return null;
    if (a % b != 0) return null; // exact division only (golden-rule safe)
    if (a.toString().length > 6) return null; // keep the worksheet sane
    final quotient = a ~/ b;
    final verified = int.tryParse(result.answerPlain.trim());
    if (verified == null || verified != quotient) return null;

    final digits = a.toString().split('').map(int.parse).toList();
    final n = digits.length;
    final marks = <DivMark>[];
    final lines = <DivLine>[];
    final steps = <DivStep>[];

    var current = 0;
    var started = false;
    var realStep = 0;
    var beat = 0;
    var maxRow = 1;

    for (var i = 0; i < n; i++) {
      current = current * 10 + digits[i];
      final q = current ~/ b;
      if (q == 0 && !started) {
        continue; // leading zero — extend the window, no quotient digit yet
      }
      started = true;
      final product = q * b;
      final rem = current - product;
      final productDigits = product.toString().split('').map(int.parse).toList();
      final remDigits = rem.toString().split('').map(int.parse).toList();
      final prow = 2 + 2 * realStep;
      final drow = 3 + 2 * realStep;
      maxRow = drow;

      // DIVIDE — the quotient digit lands above the current column.
      marks.add(DivMark(
          kind: DivMarkKind.quotient,
          row: 0,
          rightCol: i,
          digits: [q],
          revealAt: beat));
      steps.add(DivStep(
        caption: '$b goes into $current — $q ${q == 1 ? 'time' : 'times'}',
        callout: '$b × $q = $product',
      ));
      beat++;

      // MULTIPLY — the product under the current window.
      marks.add(DivMark(
          kind: DivMarkKind.product,
          row: prow,
          rightCol: i,
          digits: productDigits,
          revealAt: beat));
      steps.add(DivStep(caption: 'Multiply', callout: '$q × $b = $product'));
      beat++;

      // SUBTRACT — rule + the difference.
      lines.add(DivLine(
          row: drow,
          leftCol: i - (productDigits.length - 1),
          rightCol: i,
          revealAt: beat));
      marks.add(DivMark(
          kind: DivMarkKind.difference,
          row: drow,
          rightCol: i,
          digits: remDigits,
          revealAt: beat));
      steps.add(
          DivStep(caption: 'Subtract', callout: '$current − $product = $rem'));
      beat++;

      // BRING DOWN — pull the next dividend digit onto the difference row.
      if (i + 1 < n) {
        marks.add(DivMark(
            kind: DivMarkKind.broughtDown,
            row: drow,
            rightCol: i + 1,
            digits: [digits[i + 1]],
            revealAt: beat));
        steps.add(DivStep(caption: 'Bring down the ${digits[i + 1]}'));
        beat++;
      }

      current = rem;
      realStep++;
    }

    steps.add(DivStep(caption: 'The answer is $quotient'));

    return LongDivision(
      dividendDigits: digits,
      divisor: b,
      quotient: quotient,
      cols: n,
      rows: maxRow + 1,
      marks: marks,
      lines: lines,
      steps: steps,
    );
  }
}
