import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
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
    required this.tutorMessage,
  });

  final XpLevel xpLevel;
  final int streakCurrent;
  final String tutorMessage;

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
                context.l10n.practiceTitle,
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
                      context.l10n.practiceLevelWithNumber(xpLevel.level),
                      style: AppTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    XPProgressBar(value: xpLevel.progress),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n
                          .practiceXpToNextLevel(
                        xpLevel.xpToNext,
                        xpLevel.level + 1,
                      ),
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
                tutorMessage,
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
      // Solid interactive emerald — this badge carries white text (4.78:1 AA).
      decoration: const BoxDecoration(
        color: AppColors.primaryAction,
        shape: BoxShape.circle,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            context.l10n.practiceLevelShort,
            style: AppTypography.label.copyWith(
              // Full white: at 9px this is small text, so it needs the whole
              // 4.78:1 the emerald affords — a 0.85 alpha drops it under AA.
              color: AppColors.white,
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
      label: active
          ? context.l10n.practiceDayStreak(days)
          : context.l10n.practiceNoStreak,
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
              // onStreakContainer, not AppColors.streak: the raw hue is 4.18:1
              // on the light container and 3.32:1 on the dark one. The
              // container's paired on-colour is the only one that is AA on it.
              color: active ? colors.onStreakContainer : colors.textMuted,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$days',
              style: AppTypography.caption.copyWith(
                color: active ? colors.onStreakContainer : colors.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
