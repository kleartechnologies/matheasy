import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/profile_stats.dart';

/// The Profile stats card: level + animated XP count-up, level progress bar and
/// a row of streak / achievement / mastery tiles. Pulls from the aggregated
/// progress data (XP, streak, achievements, mastery).
class ProfileStatsView extends StatelessWidget {
  const ProfileStatsView({super.key, required this.stats});

  final ProfileStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${stats.level}',
                      style: AppTypography.headingMedium
                          .copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    XpCountUp(
                      value: stats.xp,
                      suffix: ' XP',
                      style: AppTypography.title
                          .copyWith(color: AppColors.amber),
                    ),
                  ],
                ),
              ),
              Text(
                '${stats.xpToNext} XP to Level ${stats.level + 1}',
                style: AppTypography.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          XPProgressBar(value: stats.levelProgress),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  icon: Icons.local_fire_department_rounded,
                  value: '${stats.streak}',
                  label: 'Day streak',
                  iconColor: AppColors.streak,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  icon: Icons.emoji_events_rounded,
                  value:
                      '${stats.achievementsUnlocked}/${stats.achievementsTotal}',
                  label: 'Badges',
                  iconColor: AppColors.amber,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  icon: Icons.verified_rounded,
                  value: '${stats.topicsMastered}',
                  label: 'Mastered',
                  iconColor: AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
