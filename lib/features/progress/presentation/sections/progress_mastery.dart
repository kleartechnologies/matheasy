import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../practice/domain/mastery.dart';
import '../../../practice/domain/practice_dashboard.dart' show CategoryView;

/// "Mastery overview" — every topic with its mastery level and progress.
class ProgressMastery extends StatelessWidget {
  const ProgressMastery({super.key, required this.mastery});

  final List<CategoryView> mastery;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Mastery overview'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              for (var i = 0; i < mastery.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                    color: context.colors.divider,
                  ),
                _MasteryRow(view: mastery[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MasteryRow extends StatelessWidget {
  const _MasteryRow({required this.view});

  final CategoryView view;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final topic = view.topic;
    final gradient = LinearGradient(
      colors: [topic.color, topic.color.withValues(alpha: 0.75)],
    );

    return Semantics(
      label: '${topic.label} mastery: ${view.level.label}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: topic.color.withValues(alpha: 0.14),
                  borderRadius: AppRadius.smRadius,
                ),
                child: Icon(topic.icon, size: 22, color: topic.color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            topic.label,
                            style: AppTypography.title.copyWith(
                              color: colors.textPrimary,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        _LevelChip(level: view.level, color: topic.color),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    XPProgressBar(
                      value: view.progress,
                      gradient: gradient,
                      height: 6,
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

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level, required this.color});

  final MasteryLevel level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final mastered = level == MasteryLevel.mastered;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: mastered ? 0.18 : 0.1),
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mastered) ...[
            Icon(Icons.workspace_premium_rounded, size: 12, color: color),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            level.label,
            style: AppTypography.label.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
