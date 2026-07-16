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

/// A single "continue where you left off" card — Home's second priority. One
/// card only, no carousel. Rendered only when a real [CourseProgress] exists.
class HomeContinueCard extends StatelessWidget {
  const HomeContinueCard({super.key, required this.course});

  final CourseProgress course;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final percent = (course.fraction * 100).round();

    return AppCard(
      onTap: () => context.go(AppRoutes.practice),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: AppRadius.smRadius,
                ),
                child: Icon(
                  course.icon,
                  size: 22,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continue learning',
                      style: AppTypography.label.copyWith(color: colors.textMuted),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      course.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headingSmall.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textMuted),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _ProgressBar(fraction: course.fraction),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$percent% complete · ${course.estMinutes} min left',
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The filled track is [AppColors.primaryAction] in both themes: it is a bar, not
/// text, and the interactive emerald keeps progress reading as the same green as
/// every other action on Home.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.pillRadius,
      child: Stack(
        children: [
          Container(height: 6, color: context.colors.surfaceMuted),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(height: 6, color: AppColors.primaryAction),
          ),
        ],
      ),
    );
  }
}
