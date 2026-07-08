import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/progress_overview.dart';

/// Profile summary: avatar, name, XP level with progress, and current streak.
class ProgressProfile extends StatelessWidget {
  const ProgressProfile({super.key, required this.overview});

  final ProgressOverview overview;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final xp = overview.xpLevel;

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              _Avatar(name: overview.userName, photoUrl: overview.photoUrl),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overview.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headingSmall.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Level ${xp.level} · ${xp.totalXp} XP',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _StreakPill(days: overview.streakCurrent),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          XPProgressBar(value: xp.progress),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(
                'Level ${xp.level}',
                style: AppTypography.caption.copyWith(
                  color: colors.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${xp.xpToNext} XP to Level ${xp.level + 1}',
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.photoUrl});

  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: AppTypography.headingMedium.copyWith(color: AppColors.white),
      ),
    );

    final url = photoUrl;
    return Semantics(
      label: 'Profile',
      child: url == null
          ? fallback
          : ClipOval(
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
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
