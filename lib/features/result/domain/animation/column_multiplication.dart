import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style COLUMN (long) MULTIPLICATION walkthrough for an
/// integer × single-digit product, e.g. `72 × 6`.
///
/// The choreography is the standard short-multiplication algorithm broken into
/// the same beats Photomath shows: multiply a digit, add the carry, write the
/// answer digit, carry the tens. GOLDEN RULE: the final product is taken from the
/// VERIFIED server answer, and [tryBuild] only builds when the algorithm's product
/// equals it — so the animation can never show a total the solver didn't confirm.
/// The per-digit sub-products are the standard algorithm applied to the given
/// operands (trivial, deterministic), gated by that equality check.

/// One beat of the walkthrough — a full snapshot of what is visible plus the one
/// element being emphasised. All positions are by COLUMN, `0` = ones (rightmost).
@immutable
class ColMulStep {
  const ColMulStep({
    required this.caption,
    this.callout,
    this.highlightTopCols = const {},
    this.highlightMultiplier = false,
    this.resultDigits = const [],
    this.carryDigits = const {},
    this.emphResultCol,
    this.emphCarryCol,
  });

  /// The plain-language instruction for this beat.
  final String caption;

  /// The sub-calculation to show in the callout box, e.g. "6 × 2 = 12". Null when
  /// this beat just writes/carries a digit.
  final String? callout;

  /// Top-number columns highlighted this beat (`0` = ones).
  final Set<int> highlightTopCols;

  /// Whether the single-digit multiplier is highlighted this beat.
  final bool highlightMultiplier;

  /// Revealed answer digits by column (`0` = ones); null = still blank.
  final List<int?> resultDigits;

  /// Revealed carry digits shown above the top number: column → carry digit.
  final Map<int, int> carryDigits;

  /// The answer column just written (emphasised green + callout arrow points to it).
  final int? emphResultCol;

  /// The carry column just placed (emphasised blue + arrow up).
  final int? emphCarryCol;
}

/// A built column-multiplication walkthrough. [tryBuild] returns null when the
/// problem isn't an integer × single-digit product, or when the algorithm's
/// product doesn't match the verified answer.
@immutable
class ColumnMultiplication {
  const ColumnMultiplication({
    required this.top,
    required this.multiplier,
    required this.product,
    required this.steps,
  });

  /// The multi-digit factor shown on top, e.g. 72.
  final int top;

  /// The single-digit factor, e.g. 6.
  final int multiplier;

  /// The VERIFIED product, e.g. 432.
  final int product;

  final List<ColMulStep> steps;

  /// The top number's digits, left-to-right (e.g. [7, 2]).
  List<int> get topDigits =>
      top.toString().split('').map(int.parse).toList(growable: false);

  /// Number of answer columns (e.g. 3 for 432).
  int get resultWidth => product.toString().length;

  /// Number of top columns (e.g. 2 for 72).
  int get topWidth => top.toString().length;

  static final RegExp _product = RegExp(r'^(\d+)\*(\d+)$');

  /// Build for a verified integer × single-digit multiplication, else null.
  static ColumnMultiplication? tryBuild(ResultData result) {
    if (!result.verified) return null;
    // Normalise the problem to `a*b`: drop delimiters/spaces, fold ×, ·, \times.
    final cleaned = result.equation.latex
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(RegExp(r'\\times|\\cdot|×|·'), '*');
    final m = _product.firstMatch(cleaned);
    if (m == null) return null;
    final a = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(2)!);
    if (a == null || b == null) return null;

    // Short multiplication needs a single-digit multiplier; put it on the bottom.
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
    if (mult == 0 || top == 0) return null; // ×0 has no interesting walkthrough

    // GOLDEN RULE: the shown product must equal the VERIFIED answer.
    final verified = int.tryParse(result.answerPlain.trim());
    final product = top * mult;
    if (verified == null || verified != product) return null;

    return ColumnMultiplication(
      top: top,
      multiplier: mult,
      product: product,
      steps: _buildSteps(top, mult, product),
    );
  }

  static List<ColMulStep> _buildSteps(int top, int mult, int product) {
    final topDigits = top.toString().split('').map(int.parse).toList();
    final n = topDigits.length;
    final width = product.toString().length;
    final result = List<int?>.filled(width, null);
    final carries = <int, int>{};
    final steps = <ColMulStep>[];

    ColMulStep snap({
      required String caption,
      String? callout,
      Set<int> hlTop = const {},
      bool hlMult = false,
      int? emphResult,
      int? emphCarry,
    }) =>
        ColMulStep(
          caption: caption,
          callout: callout,
          highlightTopCols: hlTop,
          highlightMultiplier: hlMult,
          resultDigits: List<int?>.from(result),
          carryDigits: Map<int, int>.from(carries),
          emphResultCol: emphResult,
          emphCarryCol: emphCarry,
        );

    var carry = 0;
    for (var col = 0; col < n; col++) {
      final digit = topDigits[n - 1 - col]; // column 0 = ones = last digit
      final sub = mult * digit;
      // The callout persists through this column's write + carry beats (as in
      // Photomath), so the dashed arrows can point from it to their destinations.
      var callout = '$mult × $digit = $sub';
      steps.add(snap(
        caption: 'Multiply the digits',
        callout: callout,
        hlTop: {col},
        hlMult: true,
      ));

      var total = sub;
      if (carry > 0) {
        total = sub + carry;
        callout = '$sub + $carry = $total';
        steps.add(snap(
          caption: 'Add the carried digit to the previous result',
          callout: callout,
          hlTop: {col},
          hlMult: true,
        ));
      }

      final writeDigit = total % 10;
      final newCarry = total ~/ 10;
      result[col] = writeDigit;
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
          carries[col + 1] = newCarry; // shown above the next top column
          steps.add(snap(
            caption: 'Carry the first digit and save it for the next calculation',
            callout: callout,
            emphCarry: col + 1,
          ));
        } else {
          // Last column: the carry becomes the leading answer digit(s).
          final cs = newCarry.toString();
          for (var k = 0; k < cs.length; k++) {
            result[col + 1 + k] = int.parse(cs[cs.length - 1 - k]);
          }
          steps.add(snap(
            caption: 'Write the result in the answer line',
            callout: callout,
            emphResult: col + 1,
          ));
        }
      }
      carry = newCarry;
    }

    steps.add(snap(caption: 'The result is $product'));
    return steps;
  }
}
