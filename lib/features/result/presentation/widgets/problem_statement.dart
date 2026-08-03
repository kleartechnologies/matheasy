import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'math_format.dart';
import 'math_text.dart';

/// The recognized problem, laid out the way the worksheet had it: the
/// instruction as ordinary prose, the maths typeset beneath it, one line per
/// line — fractions stacked, roots under a radical, exponents raised.
///
/// The student's only way to check that Matheasy read their page correctly is to
/// compare this against the page, so it has exactly one job: look like what they
/// scanned. LaTeX stays the internal contract (OCR → solve → verify → history);
/// it is never what gets drawn. See [parseProblemStatement] for the split and
/// [toReadableMath] for what happens when typesetting fails.
class ProblemStatement extends StatelessWidget {
  const ProblemStatement({
    super.key,
    required this.latex,
    this.minFontSize = 26,
    this.maxFontSize = 38,
    this.proseStyle,
    this.mathStyle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mathAlignment = Alignment.centerLeft,
  });

  /// The recognizer's LaTeX for the whole problem.
  final String latex;

  /// The band the maths sizes itself within — a short problem gets
  /// [maxFontSize], a long one shrinks toward [minFontSize] rather than
  /// scrolling sideways or clipping.
  final double minFontSize;
  final double maxFontSize;

  final TextStyle? proseStyle;
  final TextStyle? mathStyle;

  final CrossAxisAlignment crossAxisAlignment;
  final AlignmentGeometry mathAlignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lines = parseProblemStatement(latex);
    final prose = proseStyle ??
        AppTypography.bodyMedium.copyWith(
          color: colors.textSecondary,
          height: 1.35,
        );
    final maths = mathStyle ??
        AppTypography.displaySmall.copyWith(color: colors.textPrimary);

    if (lines.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0) {
        // Prose sits close to the maths it introduces; two expressions get more
        // room between them so they read as separate lines of the worksheet.
        final tight = !lines[i - 1].isMath || !line.isMath;
        children.add(SizedBox(height: tight ? AppSpacing.sm : AppSpacing.md));
      }
      children.add(
        line.isMath
            ? AdaptiveMath(
                line.content,
                minFontSize: minFontSize,
                maxFontSize: maxFontSize,
                alignment: mathAlignment,
                style: maths,
              )
            : Text(
                line.content,
                style: prose,
                textAlign: crossAxisAlignment == CrossAxisAlignment.center
                    ? TextAlign.center
                    : TextAlign.start,
              ),
      );
    }

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
