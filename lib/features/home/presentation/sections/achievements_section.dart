import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/home_models.dart';

/// "Achievements" preview — a horizontal rail of recent badges.
class AchievementsSection extends StatelessWidget {
  const AchievementsSection({super.key, required this.achievements});

  final List<AchievementBadge> achievements;

  @override
  Widget build(BuildContext context) {
    if (achievements.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Achievements',
          actionLabel: 'See all',
          onAction: () => context.go(AppRoutes.profile),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: achievements.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, i) => _BadgeCard(achievements[i]),
          ),
        ),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard(this.badge);

  final AchievementBadge badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 150,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: badge.unlocked
                        ? badge.accent.withValues(alpha: 0.16)
                        : colors.surfaceMuted,
                    borderRadius: AppRadius.smRadius,
                  ),
                  child: Icon(
                    badge.unlocked ? badge.icon : Icons.lock_rounded,
                    size: 24,
                    color: badge.unlocked ? badge.accent : colors.textTertiary,
                  ),
                ),
                if (badge.unlocked)
                  const Positioned(
                    right: 0,
                    top: 0,
                    child: Icon(Icons.verified_rounded,
                        size: 16, color: AppColors.success),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              badge.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.title.copyWith(
                color: badge.unlocked ? colors.textPrimary : colors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Expanded(
              child: Text(
                badge.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall
                    .copyWith(color: colors.textSecondary, fontSize: 12),
              ),
            ),
            if (!badge.unlocked && badge.progress != null)
              XPProgressBar(value: badge.progress!, height: 6),
          ],
        ),
      ),
    );
  }
}
