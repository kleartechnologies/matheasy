import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/math_semantics.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/tutor_models.dart';
import 'tutor_sketch_view.dart';

/// The equation Numi is pointing at, with only the piece she is explaining lit
/// up (spec Parts 7–8).
///
/// Deliberately quieter than the quiz and practice cards: it is not a thing to
/// act on, it is the sentence above it made visible. So it gets a flat, tinted
/// panel rather than a raised card, and the caption wears the same colour as the
/// highlight — which is how a student learns the colour vocabulary without ever
/// being shown a legend.
class TutorFocusCard extends StatelessWidget {
  const TutorFocusCard(this.focus, {super.key});

  final TutorFocus focus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = focus.leadRole.color(colors, isDark: isDark);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.lgRadius,
        // A hairline in the highlight's own colour, so the panel belongs to
        // what it is pointing at.
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wide working scrolls rather than shrinking to an unreadable sliver.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Semantics(
              label: focus.latex,
              child: ExcludeSemantics(
                child: HighlightedMath(
                  latex: focus.latex,
                  highlights: focus.highlights,
                  textStyle:
                      AppTypography.headingSmall.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
          ),
          // The drawing sits between the equation and the words, because it is
          // the same claim in a third form — and the caption below then reads
          // as the legend for both.
          if (focus.sketch != null) ...[
            const SizedBox(height: AppSpacing.sm),
            TutorSketchView(focus.sketch!),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            focus.caption,
            style: AppTypography.caption.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
