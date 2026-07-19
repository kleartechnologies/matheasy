import 'package:flutter/foundation.dart';

import '../result_models.dart';

/// A Photomath-style LONG MULTIPLICATION walkthrough for a multi-digit ×
/// multi-digit product (e.g. `34 × 27`): each partial product is computed and
/// placed on its own shifted row, then the partials are added.
///
/// GOLDEN RULE: the product (and every partial) is checked against the VERIFIED
/// server answer — [tryBuild] declines otherwise.

/// One partial-product row: top × a single bottom digit, shifted left.
@immutable
class PartialProduct {
  const PartialProduct({required this.value, required this.shift});

  /// The raw partial (top × bottom digit), before the shift.
  final int value;

  /// How many columns it is shifted left (0 = ones row).
  final int shift;

  /// The partial's digits, left-to-right.
  List<int> get digits =>
      value.toString().split('').map(int.parse).toList(growable: false);

  /// The leftmost column this partial occupies.
  int get leftCol => shift + digits.length - 1;
}

@immutable
class LongMulStep {
  const LongMulStep({
    required this.caption,
    this.callout,
    this.highlightTop = const {},
    this.highlightBottomCol,
    this.visiblePartials = 0,
    this.emphPartial,
    this.showSum = false,
    this.emphSum = false,
  });

  final String caption;
  final String? callout;
  final Set<int> highlightTop;
  final int? highlightBottomCol;

  /// How many partial rows are revealed this beat.
  final int visiblePartials;

  /// The partial row just revealed (animate it in).
  final int? emphPartial;

  final bool showSum;
  final bool emphSum;
}

@immutable
class LongMultiplication {
  const LongMultiplication({
    required this.topDigits,
    required this.bottomDigits,
    required this.partials,
    required this.product,
    required this.gridCols,
    required this.steps,
  });

  final List<int> topDigits;
  final List<int> bottomDigits;
  final List<PartialProduct> partials;
  final int product;
  final int gridCols;
  final List<LongMulStep> steps;

  int get topWidth => topDigits.length;
  int get bottomWidth => bottomDigits.length;
  List<int> get productDigits =>
      product.toString().split('').map(int.parse).toList(growable: false);

  static final RegExp _product = RegExp(r'^(\d+)\*(\d+)$');

  /// Build for a verified multi-digit × multi-digit product, else null.
  static LongMultiplication? tryBuild(ResultData result) {
    if (!result.verified) return null;
    final cleaned = result.equation.latex
        .replaceAll(RegExp(r'\\left|\\right|\$|\s'), '')
        .replaceAll(RegExp(r'\\times|\\cdot|×|·'), '*');
    final m = _product.firstMatch(cleaned);
    if (m == null) return null;
    final a = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(2)!);
    if (a == null || b == null) return null;
    // This method is for the both-multi-digit case (single-digit is column mult).
    if (a < 10 || b < 10) return null;
    final verified = int.tryParse(result.answerPlain.trim());
    if (verified == null || a * b != verified) return null;

    // The wider factor goes on top; the multiplier's digits drive the partials.
    final top = a >= b ? a : b;
    final mult = a >= b ? b : a;
    final md = mult.toString().split('').map(int.parse).toList();

    final partials = <PartialProduct>[];
    for (var k = 0; k < md.length; k++) {
      final digit = md[md.length - 1 - k]; // ones-first
      partials.add(PartialProduct(value: top * digit, shift: k));
    }
    final gridCols = [
      verified.toString().length,
      for (final p in partials) p.leftCol + 1,
    ].reduce((x, y) => x > y ? x : y);

    return LongMultiplication(
      topDigits: top.toString().split('').map(int.parse).toList(),
      bottomDigits: md,
      partials: partials,
      product: verified,
      gridCols: gridCols,
      steps: _buildSteps(top, md, partials, verified),
    );
  }

  static List<LongMulStep> _buildSteps(
      int top, List<int> md, List<PartialProduct> partials, int product) {
    final steps = <LongMulStep>[];
    final ordinals = ['ones', 'tens', 'hundreds', 'thousands'];

    for (var k = 0; k < partials.length; k++) {
      final digit = md[md.length - 1 - k];
      final place = k < ordinals.length ? ordinals[k] : 'next';
      steps.add(LongMulStep(
        caption: k == 0
            ? 'Multiply the top number by the $place digit'
            : 'Multiply by the $place digit (shift left $k)',
        callout: '$top × $digit = ${partials[k].value}',
        highlightTop: {for (var c = 0; c < top.toString().length; c++) c},
        highlightBottomCol: k,
        visiblePartials: k, // previous partials still shown
      ));
      steps.add(LongMulStep(
        caption: 'Write the partial product',
        callout: '$top × $digit = ${partials[k].value}',
        highlightBottomCol: k,
        visiblePartials: k + 1,
        emphPartial: k,
      ));
    }

    // Add the partials.
    final partialSum = partials.map((p) => p.value * _pow10(p.shift)).toList();
    steps.add(LongMulStep(
      caption: 'Add the partial products',
      callout: '${partialSum.join(' + ')} = $product',
      visiblePartials: partials.length,
      showSum: true,
      emphSum: true,
    ));
    steps.add(LongMulStep(
      caption: 'The result is $product',
      visiblePartials: partials.length,
      showSum: true,
    ));
    return steps;
  }

  static int _pow10(int k) {
    var v = 1;
    for (var i = 0; i < k; i++) {
      v *= 10;
    }
    return v;
  }
}
