import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_dashboard.dart';
import '../../domain/practice_topic.dart';

/// "Strengthen these" — the learner's weaker topics, each starting a session.
class PracticeWeakTopics extends StatelessWidget {
  const PracticeWeakTopics({
    super.key,
    required this.topics,
    required this.onStartTopic,
  });

  final List<WeakTopicView> topics;
  final ValueChanged<PracticeTopic> onStartTopic;

  @override
  Widget build(BuildContext context) {
    if (topics.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Strengthen these'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              for (var i = 0; i < topics.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                    color: context.colors.divider,
                  ),
                _WeakRow(view: topics[i], onTap: onStartTopic),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WeakRow extends StatelessWidget {
  const _WeakRow({required this.view, required this.onTap});

  final WeakTopicView view;
  final ValueChanged<PracticeTopic> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final solved = view.solvedCount == 1
        ? 'Solved 1 problem'
        : 'Solved ${view.solvedCount} problems';
    return Semantics(
      button: true,
      label: '${view.topic.label}, $solved',
      child: InkWell(
        onTap: () => onTap(view.topic),
        borderRadius: AppRadius.mdRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: view.topic.color.withValues(alpha: 0.14),
                  borderRadius: AppRadius.smRadius,
                ),
                child: Icon(
                  view.topic.icon,
                  size: 22,
                  color: view.topic.color,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.topic.label,
                      style: AppTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      solved,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
