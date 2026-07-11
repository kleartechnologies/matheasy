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

/// "Continue learning" — a horizontal rail of in-progress courses, or a starter
/// card on the first day.
class ContinueLearning extends StatelessWidget {
  const ContinueLearning({super.key, required this.courses});

  final List<CourseProgress> courses;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) return const _StarterCard();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Continue learning',
          actionLabel: 'See all',
          onAction: () => context.go(AppRoutes.practice),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: courses.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, i) => _CourseCard(courses[i]),
          ),
        ),
      ],
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard(this.course);

  final CourseProgress course;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 172,
      child: AppCard(
        onTap: () => context.go(AppRoutes.practice),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 74,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [course.color, course.color.withValues(alpha: 0.72)],
                ),
                borderRadius: AppRadius.mdRadius,
              ),
              child: Icon(course.icon, size: 32, color: AppColors.white),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              course.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.title
                  .copyWith(color: context.colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            XPProgressBar(
              value: course.fraction,
              height: 7,
              gradient: LinearGradient(colors: [course.color, course.color]),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${(course.fraction * 100).round()}% · ~${course.estMinutes} min left',
              style: AppTypography.caption
                  .copyWith(color: context.colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarterCard extends StatelessWidget {
  const _StarterCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: AppRadius.mdRadius,
            ),
            child: const Icon(Icons.school_rounded,
                size: 26, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start your first lesson',
                  style: AppTypography.title.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Pick a topic and Matheasy will guide you.',
                  style: AppTypography.bodySmall
                      .copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GhostButton(
            label: 'Start',
            size: AppButtonSize.small,
            onPressed: () => context.go(AppRoutes.practice),
          ),
        ],
      ),
    );
  }
}
