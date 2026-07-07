import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/result_models.dart';

/// A small, theme-aware pill showing a [Difficulty]. Colors come from the
/// semantic container tokens so it reads correctly in light and dark mode.
class DifficultyPill extends StatelessWidget {
  const DifficultyPill(this.difficulty, {super.key});

  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (difficulty) {
      Difficulty.easy => (colors.successContainer, colors.onSuccessContainer),
      Difficulty.medium => (colors.warningContainer, colors.onWarningContainer),
      Difficulty.hard => (colors.errorContainer, colors.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        difficulty.label,
        style: AppTypography.label.copyWith(color: foreground),
      ),
    );
  }
}
