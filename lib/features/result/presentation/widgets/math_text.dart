import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Renders LaTeX with a safe plain-text fallback, so messy input never crashes
/// the result screen. Used everywhere the result shows math.
class MathText extends StatelessWidget {
  const MathText(this.latex, {super.key, required this.style});

  final String latex;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // Rendered math has no intrinsic semantics — expose the source expression
    // so screen readers can announce it.
    return Semantics(
      label: latex,
      child: ExcludeSemantics(
        // Long OCR/AI-recognized equations can exceed their bounded box, and
        // flutter_math neither wraps nor scrolls. Scale down to fit instead of
        // overflowing — centralized here so every MathText caller is safe.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Math.tex(
            latex,
            textStyle: style,
            mathStyle: MathStyle.text,
            onErrorFallback: (_) => Text(latex, style: style),
          ),
        ),
      ),
    );
  }
}
