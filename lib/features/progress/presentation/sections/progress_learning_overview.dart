import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/progress_overview.dart';

/// "Learning overview" — a 2×2 grid of the headline lifetime stats.
class ProgressLearningOverview extends StatelessWidget {
  const ProgressLearningOverview({super.key, required this.overview});

  final ProgressOverview overview;

  @override
  Widget build(BuildContext context) {
    final tiles = <_StatData>[
      _StatData(
        icon: Icons.check_circle_rounded,
        color: AppColors.primary,
        value: '${overview.questionsSolved}',
        label: 'Questions solved',
      ),
      _StatData(
        icon: Icons.fitness_center_rounded,
        color: AppColors.secondary,
        value: '${overview.sessionsCompleted}',
        label: 'Practice sessions',
      ),
      _StatData(
        icon: Icons.category_rounded,
        color: AppColors.success,
        value: '${overview.topicsPracticed}',
        label: 'Topics practiced',
      ),
      _StatData(
        icon: Icons.schedule_rounded,
        color: AppColors.amber,
        value: overview.timeLearningLabel,
        label: 'Time learning',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Learning overview'),
        const SizedBox(height: AppSpacing.md),
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _StatTile(tiles[row * 2])),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _StatTile(tiles[row * 2 + 1])),
            ],
          ),
        ],
      ],
    );
  }
}

class _StatData {
  const _StatData({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.data);

  final _StatData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: '${data.label}: ${data.value}',
      child: ExcludeSemantics(
        child: AppCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.14),
                  borderRadius: AppRadius.smRadius,
                ),
                child: Icon(data.icon, size: 22, color: data.color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.value,
                      style: AppTypography.headingSmall.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
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
}
