import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/practice_difficulty.dart';

/// A small gold XP badge, e.g. "+20 XP".
class PracticeXpBadge extends StatelessWidget {
  const PracticeXpBadge({super.key, required this.xp, this.showPlus = true});

  final int xp;
  final bool showPlus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${showPlus ? 'Reward ' : ''}$xp XP',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: context.colors.xpContainer,
          borderRadius: AppRadius.smRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 13, color: AppColors.xp),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '${showPlus ? '+' : ''}$xp XP',
              style: AppTypography.label.copyWith(color: AppColors.amber),
            ),
          ],
        ),
      ),
    );
  }
}

/// A theme-aware difficulty pill for the practice engine's [PracticeDifficulty].
class PracticeDifficultyPill extends StatelessWidget {
  const PracticeDifficultyPill(this.difficulty, {super.key});

  final PracticeDifficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (difficulty) {
      PracticeDifficulty.easy => (
          colors.successContainer,
          colors.onSuccessContainer,
        ),
      PracticeDifficulty.medium => (
          colors.warningContainer,
          colors.onWarningContainer,
        ),
      PracticeDifficulty.hard => (
          colors.errorContainer,
          colors.onErrorContainer,
        ),
      PracticeDifficulty.expert => (
          colors.primaryContainer,
          colors.onPrimaryContainer,
        ),
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
