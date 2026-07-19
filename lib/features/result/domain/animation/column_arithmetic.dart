import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style COLUMN ARITHMETIC walkthrough — long addition, subtraction,
/// or single-digit multiplication laid out digit-by-digit (e.g. `72 × 6`,
/// `348 + 275`, `502 − 87`).
///
/// GOLDEN RULE: the result is taken from the VERIFIED server answer, and
/// [tryBuild] only builds when the standard algorithm's result equals it — so the
/// animation can never show a total the solver didn't confirm. The per-column
/// sub-steps are the standard algorithm applied to the given operands (trivial,
/// deterministic), gated by that equality check.

/// The operation being walked through.
enum ColumnOp { add, subtract, multiply }

/// One beat — a full snapshot of what's visible plus the emphasised element. All
/// positions are by COLUMN, `0` = ones (rightmost).
@immutable
class ColumnArithmeticStep {
  const ColumnArithmeticStep({
    required this.caption,
    this.callout,
    this.highlightTop = const {},
    this.highlightBottom = const {},
    this.resultDigits = const [],
    this.carryDigits = const {},
    this.borrowDigits = const {},
    this.struckTop = const {},
    this.emphResultCol,
    this.emphCarryCol,
  });

  final String caption;
  final String? callout;

  /// Top / bottom operand columns highlighted this beat.
  final Set<int> highlightTop;
  final Set<int> highlightBottom;

  /// Revealed answer digits by column (`0` = ones); null = blank.
  final List<int?> resultDigits;

  /// Carry digits shown above the top number: column → carry (add / multiply).
  final Map<int, int> carryDigits;

  /// Borrow: the REDUCED value written above a top column (subtraction).
  final Map<int, int> borrowDigits;

  /// Top columns struck through because they were borrowed from (subtraction).
  final Set<int> struckTop;

  /// The answer column just written (emphasised green + arrow).
  final int? emphResultCol;

  /// The carry / borrow just placed (emphasised blue + arrow).
  final int? emphCarryCol;
}

@immutable
class ColumnArithmetic {
  const ColumnArithmetic({
    required this.op,
    required this.topDigits,
    required this.bottomDigits,
    required this.resultWidth,
    required this.steps,
  });

  final ColumnOp op;

  /// Operand digits, left-to-right.
  final List<int> topDigits;
  final List<int> bottomDigits;

  final int resultWidth;
  final List<ColumnArithmeticStep> steps;

  String get operatorSymbol =>
      switch (op) { ColumnOp.add => '+', ColumnOp.subtract => '−', ColumnOp.multiply => '×' };

  int get topWidth => topDigits.length;
  int get bottomWidth => bottomDigits.length;

  static final RegExp _expr = RegExp(r'^(\d+)([+\-*])(\d+)$');

  /// Build for a verified two-operand column-arithmetic problem, else null.
  static ColumnArithmetic? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final cleaned = result.equation.latex
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(RegExp(r'\\times|\\cdot|×|·'), '*')
        .replaceAll('−', '-');
    final m = _expr.firstMatch(cleaned);
    if (m == null) return null;
    final a = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(3)!);
    if (a == null || b == null) return null;
    final verified = int.tryParse(result.answerPlain.trim());
    if (verified == null) return null;

    switch (m.group(2)) {
      case '+':
        if (a + b != verified) return null;
        final steps = _addSteps(a, b, verified);
        if (steps == null) return null;
        return ColumnArithmetic(
          op: ColumnOp.add,
          topDigits: _digits(a),
          bottomDigits: _digits(b),
          resultWidth: verified.toString().length,
          steps: steps,
        );
      case '-':
        if (a < b || a - b != verified) return null; // positive results only
        final steps = _subSteps(a, b, verified);
        if (steps == null) return null;
        return ColumnArithmetic(
          op: ColumnOp.subtract,
          topDigits: _digits(a),
          bottomDigits: _digits(b),
          resultWidth: _digits(a).length, // subtraction can't widen
          steps: steps,
        );
      case '*':
        final int top, mult;
        if (b < 10) {
          top = a;
          mult = b;
        } else if (a < 10) {
          top = b;
          mult = a;
        } else {
          return null; // both multi-digit → long multiplication (a later method)
        }
        if (mult == 0 || top == 0 || top * mult != verified) return null;
        return ColumnArithmetic(
          op: ColumnOp.multiply,
          topDigits: _digits(top),
          bottomDigits: _digits(mult),
          resultWidth: verified.toString().length,
          steps: _mulSteps(top, mult, verified),
        );
      default:
        return null;
    }
  }

  static List<int> _digits(int n) =>
      n.toString().split('').map(int.parse).toList(growable: false);

  /// digit at column [col] (0 = ones) of the value with left-to-right [digits],
  /// or 0 when out of range.
  static int _at(List<int> digits, int col) {
    final i = digits.length - 1 - col;
    return (i >= 0 && i < digits.length) ? digits[i] : 0;
  }

  // --- long multiplication (top × single digit) ------------------------------
  static List<ColumnArithmeticStep> _mulSteps(int top, int mult, int product) {
    final t = _digits(top);
    final n = t.length;
    final width = product.toString().length;
    final result = List<int?>.filled(width, null);
    final carries = <int, int>{};
    final steps = <ColumnArithmeticStep>[];

    ColumnArithmeticStep snap({
      required String caption,
      String? callout,
      Set<int> hlTop = const {},
      bool hlMult = false,
      int? emphResult,
      int? emphCarry,
    }) =>
        ColumnArithmeticStep(
          caption: caption,
          callout: callout,
          highlightTop: hlTop,
          highlightBottom: hlMult ? {0} : const {},
          resultDigits: List<int?>.from(result),
          carryDigits: Map<int, int>.from(carries),
          emphResultCol: emphResult,
          emphCarryCol: emphCarry,
        );

    var carry = 0;
    for (var col = 0; col < n; col++) {
      final d = t[n - 1 - col];
      final sub = mult * d;
      var callout = '$mult × $d = $sub';
      steps.add(snap(caption: 'Multiply the digits', callout: callout, hlTop: {col}, hlMult: true));

      var total = sub;
      if (carry > 0) {
        total = sub + carry;
        callout = '$sub + $carry = $total';
        steps.add(snap(
            caption: 'Add the carried digit to the previous result',
            callout: callout,
            hlTop: {col},
            hlMult: true));
      }

      final write = total % 10;
      final newCarry = total ~/ 10;
      result[col] = write;
      final isLast = col == n - 1;
      steps.add(snap(
        caption: isLast && newCarry == 0
            ? 'Write the result in the answer line'
            : 'Take the last digit and write it in the answer line',
        callout: callout,
        emphResult: col,
      ));
      if (newCarry > 0) {
        if (!isLast) {
          carries[col + 1] = newCarry;
          steps.add(snap(
              caption: 'Carry the first digit and save it for the next calculation',
              callout: callout,
              emphCarry: col + 1));
        } else {
          final cs = newCarry.toString();
          for (var k = 0; k < cs.length; k++) {
            result[col + 1 + k] = int.parse(cs[cs.length - 1 - k]);
          }
          steps.add(snap(
              caption: 'Write the result in the answer line',
              callout: callout,
              emphResult: col + 1));
        }
      }
      carry = newCarry;
    }
    steps.add(snap(caption: 'The result is $product'));
    return steps;
  }

  // --- long addition ---------------------------------------------------------
  static List<ColumnArithmeticStep>? _addSteps(int a, int b, int sum) {
    final ta = _digits(a), tb = _digits(b);
    final cols = sum.toString().length;
    final width = cols;
    final result = List<int?>.filled(width, null);
    final carries = <int, int>{};
    final steps = <ColumnArithmeticStep>[];
    final n = a.toString().length > b.toString().length
        ? a.toString().length
        : b.toString().length;

    ColumnArithmeticStep snap({
      required String caption,
      String? callout,
      int col = -1,
      int? emphResult,
      int? emphCarry,
    }) =>
        ColumnArithmeticStep(
          caption: caption,
          callout: callout,
          highlightTop: col >= 0 ? {col} : const {},
          highlightBottom: col >= 0 ? {col} : const {},
          resultDigits: List<int?>.from(result),
          carryDigits: Map<int, int>.from(carries),
          emphResultCol: emphResult,
          emphCarryCol: emphCarry,
        );

    var carry = 0;
    for (var col = 0; col < n; col++) {
      final da = _at(ta, col), db = _at(tb, col);
      final total = da + db + carry;
      final callout = carry > 0 ? '$da + $db + $carry = $total' : '$da + $db = $total';
      steps.add(snap(caption: 'Add the digits in this column', callout: callout, col: col));

      final write = total % 10;
      final newCarry = total ~/ 10;
      result[col] = write;
      final isLast = col == n - 1;
      steps.add(snap(
        caption: isLast && newCarry == 0
            ? 'Write the digit in the answer line'
            : 'Take the last digit and write it in the answer line',
        callout: callout,
        emphResult: col,
      ));
      if (newCarry > 0) {
        if (!isLast) {
          carries[col + 1] = newCarry;
          steps.add(snap(
              caption: 'Carry the 1 to the next column', callout: callout, emphCarry: col + 1));
        } else {
          result[col + 1] = newCarry;
          steps.add(snap(
              caption: 'Write the carried digit in the answer line',
              callout: callout,
              emphResult: col + 1));
        }
      }
      carry = newCarry;
    }
    steps.add(snap(caption: 'The result is $sum'));
    return steps;
  }

  // --- long subtraction (a ≥ b) ----------------------------------------------
  static List<ColumnArithmeticStep>? _subSteps(int a, int b, int diffValue) {
    final top = _digits(a).toList(); // mutable, left-to-right
    final tb = _digits(b);
    final n = top.length;
    final result = List<int?>.filled(n, null);
    final borrows = <int, int>{};
    final struck = <int>{};
    final steps = <ColumnArithmeticStep>[];

    // top value at column `col` after borrows (mutating list is left-to-right).
    int topAt(int col) {
      final i = top.length - 1 - col;
      return (i >= 0 && i < top.length) ? top[i] : 0;
    }

    void setTop(int col, int v) {
      final i = top.length - 1 - col;
      if (i >= 0 && i < top.length) top[i] = v;
    }

    ColumnArithmeticStep snap({
      required String caption,
      String? callout,
      int col = -1,
      int? emphResult,
      int? emphCarry,
    }) =>
        ColumnArithmeticStep(
          caption: caption,
          callout: callout,
          highlightTop: col >= 0 ? {col} : const {},
          highlightBottom: col >= 0 ? {col} : const {},
          resultDigits: List<int?>.from(result),
          borrowDigits: Map<int, int>.from(borrows),
          struckTop: Set<int>.from(struck),
          emphResultCol: emphResult,
          emphCarryCol: emphCarry,
        );

    for (var col = 0; col < n; col++) {
      var da = topAt(col);
      final db = _at(tb, col);
      if (da < db) {
        // Borrow from the next-left column. Chained borrows (a 0 next door) are
        // not visualised — decline so the plain step-player handles it.
        if (col + 1 >= n || topAt(col + 1) == 0) return null;
        final reduced = topAt(col + 1) - 1;
        setTop(col + 1, reduced);
        borrows[col + 1] = reduced;
        struck.add(col + 1);
        da += 10;
        steps.add(snap(
          caption: 'Borrow 1 from the next column',
          callout: '${da - 10} → $da',
          col: col,
          emphCarry: col + 1,
        ));
      }
      final d = da - db;
      steps.add(snap(
        caption: 'Subtract the digits in this column',
        callout: '$da − $db = $d',
        col: col,
      ));
      result[col] = d;
      steps.add(snap(
        caption: 'Write the difference in the answer line',
        callout: '$da − $db = $d',
        emphResult: col,
      ));
    }
    steps.add(snap(caption: 'The result is $diffValue'));
    return steps;
  }
}
