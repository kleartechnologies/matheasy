import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../progress/application/achievement_controller.dart';
import '../../../progress/application/progress_controller.dart';
import '../../../progress/domain/achievement_progress.dart';
import '../../../progress/presentation/widgets/badge_card.dart';

/// Home shortcut into Progress: XP level, streak and the latest badge earned.
class HomeProgressCard extends ConsumerWidget {
  const HomeProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(progressControllerProvider);
    final achievements = ref.watch(achievementControllerProvider);
    final colors = context.colors;
    final xp = overview.xpLevel;

    final unlocked = achievements.unlocked;
    final AchievementView? latest = unlocked.isEmpty
        ? null
        : unlocked.reduce(
            (a, b) => a.unlockedAt!.isAfter(b.unlockedAt!) ? a : b,
          );

    return AppCard(
      onTap: () => context.go(AppRoutes.progress),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Your progress',
                style: AppTypography.headingSmall.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              _StreakPill(days: overview.streakCurrent),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: colors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${xp.level}',
                      style: AppTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    XPProgressBar(value: xp.progress),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${xp.xpToNext} XP to Level ${xp.level + 1}',
                      style: AppTypography.caption.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (latest != null) ...[
                const SizedBox(width: AppSpacing.lg),
                Column(
                  children: [
                    BadgeMedallion(
                      emoji: latest.achievement.badge.emoji,
                      color: latest.achievement.badge.color,
                      size: 52,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Latest',
                      style: AppTypography.caption.copyWith(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
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
            size: 15,
            color: active ? AppColors.streak : colors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            '$days',
            style: AppTypography.caption.copyWith(
              color: active ? AppColors.streak : colors.textTertiary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
