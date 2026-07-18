import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'math_format.dart';

/// How [MathText] resolves an expression wider than its available width.
enum MathFit {
  /// Shrink the math down until it fits (the default used almost everywhere).
  /// Never overflows and never scrolls — a long expression renders smaller.
  scaleDown,

  /// Keep the math at its full [MathText.style] size and let a wide expression
  /// scroll horizontally. Reserve for the rare case where shrinking to fit would
  /// make the math illegible and scrolling is the lesser evil.
  scroll,
}

/// Renders LaTeX with a safe plain-text fallback, so messy input never crashes
/// the result screen. Used everywhere the result shows math.
///
/// Every string is passed through [toDisplayLatex] first, so an inline `a/b`
/// division renders as a proper stacked `\frac{a}{b}` — presentation only, the
/// value is unchanged.
class MathText extends StatelessWidget {
  const MathText(
    this.latex, {
    super.key,
    required this.style,
    this.fit = MathFit.scaleDown,
    this.alignment = Alignment.centerLeft,
  });

  final String latex;
  final TextStyle style;

  /// How to handle an expression wider than the box. Defaults to
  /// [MathFit.scaleDown] (fit-to-width, no horizontal scroll).
  final MathFit fit;

  /// Alignment of the math within its box.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final display = toDisplayLatex(latex);
    final math = Math.tex(
      display,
      textStyle: style,
      mathStyle: MathStyle.text,
      onErrorFallback: (_) => Text(display, style: style),
    );
    // Rendered math has no intrinsic semantics — expose the source expression
    // so screen readers can announce it.
    return Semantics(
      label: latex,
      child: ExcludeSemantics(
        child: switch (fit) {
          // Long OCR/AI-recognized equations can exceed their bounded box, and
          // flutter_math neither wraps nor scrolls. Scale down to fit instead of
          // overflowing.
          MathFit.scaleDown => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: alignment,
              child: math,
            ),
          MathFit.scroll => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: math,
            ),
        },
      ),
    );
  }
}

/// A [MathText] that sizes itself to the content: short expressions render at
/// [maxFontSize], longer ones shrink toward [minFontSize] so they still fit the
/// available width without horizontal scrolling. The font stays within the band;
/// the underlying scale-down is the last-resort safety net for the rare
/// expression still too wide at [minFontSize].
///
/// Sizing is measured from [latex]; pass [renderLatex] when the string actually
/// drawn differs (e.g. the step-diff's `\textcolor` emphasis) but has the same
/// width.
class AdaptiveMath extends StatelessWidget {
  const AdaptiveMath(
    this.latex, {
    super.key,
    required this.style,
    required this.minFontSize,
    required this.maxFontSize,
    this.renderLatex,
    this.alignment = Alignment.centerLeft,
  });

  final String latex;
  final String? renderLatex;
  final TextStyle style;
  final double minFontSize;
  final double maxFontSize;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final size = adaptiveMathFontSize(
          latex: latex,
          maxWidth: maxWidth,
          minFontSize: minFontSize,
          maxFontSize: maxFontSize,
        );
        return MathText(
          renderLatex ?? latex,
          alignment: alignment,
          style: style.copyWith(fontSize: size),
        );
      },
    );
  }
}
