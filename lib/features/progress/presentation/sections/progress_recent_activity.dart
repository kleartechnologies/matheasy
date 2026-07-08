import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/progress_stats.dart';

/// "Recent activity" — the feed of practice sessions, achievements and
/// milestones. Hidden until there's something to show.
class ProgressRecentActivity extends StatelessWidget {
  const ProgressRecentActivity({super.key, required this.activity});

  final List<LearningActivity> activity;

  @override
  Widget build(BuildContext context) {
    if (activity.isEmpty) return const SizedBox.shrink();
    final items = activity.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Recent activity'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                    color: context.colors.divider,
                  ),
                _ActivityRow(items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.activity);

  final LearningActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icon, color) = _visualFor(activity.type);

    return Semantics(
      label: '${activity.title}. ${activity.subtitle}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: AppRadius.smRadius,
                ),
                child: activity.emoji != null
                    ? Text(
                        activity.emoji!,
                        style: const TextStyle(fontSize: 20),
                      )
                    : Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.title.copyWith(
                        color: colors.textPrimary,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      activity.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color) _visualFor(LearningActivityType type) => switch (type) {
        LearningActivityType.practice => (
            Icons.fitness_center_rounded,
            AppColors.secondary,
          ),
        LearningActivityType.achievement => (
            Icons.emoji_events_rounded,
            AppColors.gold,
          ),
        LearningActivityType.milestone => (
            Icons.trending_up_rounded,
            AppColors.primary,
          ),
        LearningActivityType.scan => (
            Icons.center_focus_strong_rounded,
            AppColors.primary,
          ),
        LearningActivityType.tutor => (Icons.forum_rounded, AppColors.secondary),
      };
}
