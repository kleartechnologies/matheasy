import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/xp_level.dart';

/// The Practice dashboard header: the title, the current streak, and an XP level
/// card with a progress bar toward the next level.
class PracticeHeader extends StatelessWidget {
  const PracticeHeader({
    super.key,
    required this.xpLevel,
    required this.streakCurrent,
    required this.numiMessage,
  });

  final XpLevel xpLevel;
  final int streakCurrent;
  final String numiMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Practice',
                style: AppTypography.displaySmall.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            _StreakPill(days: streakCurrent),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Row(
            children: [
              _LevelBadge(level: xpLevel.level),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${xpLevel.level}',
                      style: AppTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    XPProgressBar(value: xpLevel.progress),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${xpLevel.xpToNext} XP to Level ${xpLevel.level + 1}',
                      style: AppTypography.caption.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Text(
                numiMessage,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'LV',
            style: AppTypography.label.copyWith(
              color: AppColors.white.withValues(alpha: 0.85),
              fontSize: 9,
            ),
          ),
          Text(
            '$level',
            style: AppTypography.headingSmall.copyWith(color: AppColors.white),
          ),
        ],
      ),
    );
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final active = days > 0;
    final colors = context.colors;
    return Semantics(
      label: active ? '$days day streak' : 'No streak yet',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: active ? colors.streakContainer : colors.surfaceMuted,
          borderRadius: AppRadius.pillRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 18,
              color: active ? AppColors.streak : colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$days',
              style: AppTypography.caption.copyWith(
                color: active ? AppColors.streak : colors.textTertiary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
