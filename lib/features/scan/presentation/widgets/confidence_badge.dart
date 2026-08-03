import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/detected_equation.dart';

/// How sure the read was, as a state rather than a number.
///
/// "99%" reads as a claim about the *answer*, which it is not — and "78%" tells
/// a student nothing they can act on. These three say the only actionable
/// thing: whether to glance back at the page before trusting it.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge(
    this.confidence, {
    super.key,
    this.style,
    this.prominent = false,
  });

  final ReadConfidence confidence;

  /// Overrides the caption default (the capture sheet sets it in label type).
  final TextStyle? style;

  /// Whether the wording carries the accent colour too. True where the badge is
  /// the headline (the capture sheet); false where it is one chip on a quiet
  /// metadata line and must not compete with the maths above it.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final review = confidence == ReadConfidence.review;
    final accent =
        review ? colors.onWarningContainer : colors.onSuccessContainer;
    final base = style ?? AppTypography.caption;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          review ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          size: (base.fontSize ?? 12) + 1,
          color: accent,
        ),
        const SizedBox(width: AppSpacing.xxs),
        // Flexible so a long translation or a large text scale shortens the
        // wording rather than overflowing the line it sits on.
        Flexible(
          child: Text(
            confidenceLabel(context, confidence),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // A review prompt always keeps its amber; a clean read only shouts
            // where it is the headline.
            style: base.copyWith(
              color: review || prominent ? accent : colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The student-facing name of a [ReadConfidence].
String confidenceLabel(BuildContext context, ReadConfidence confidence) =>
    switch (confidence) {
      ReadConfidence.high => context.l10n.resultConfidenceHigh,
      ReadConfidence.medium => context.l10n.resultConfidenceMedium,
      ReadConfidence.review => context.l10n.resultConfidenceReview,
    };
