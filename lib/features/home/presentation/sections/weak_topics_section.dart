import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../practice/domain/practice_session.dart';
import '../../../practice/domain/practice_topic.dart';
import '../../domain/home_models.dart';

/// "Let's strengthen these" — topics needing improvement, or a friendly
/// placeholder when we don't know any yet.
class WeakTopicsSection extends StatelessWidget {
  const WeakTopicsSection({super.key, required this.topics});

  final List<WeakTopic> topics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: "Let's strengthen these",
          actionLabel: topics.isEmpty ? null : 'Practice',
          onAction: topics.isEmpty ? null : () => context.go(AppRoutes.practice),
        ),
        const SizedBox(height: AppSpacing.md),
        if (topics.isEmpty)
          const _EmptyTopics()
        else
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
                  _TopicRow(topics[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow(this.topic);

  final WeakTopic topic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => context.push(
        AppRoutes.practiceSession,
        extra: PracticeRequest(topic: PracticeTopic.fromLabel(topic.label)),
      ),
      borderRadius: AppRadius.mdRadius,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
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
                  Text(
                    topic.label,
                    style:
                        AppTypography.title.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${topic.accuracy}% accuracy · ${topic.note}',
                    style: AppTypography.bodySmall
                        .copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_forward_rounded,
                  size: 18, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTopics extends StatelessWidget {
  const _EmptyTopics();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const NumiMascot(size: 48),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              "We'll spot your tricky topics as you learn — then help you master "
              'them.',
              style: AppTypography.bodyMedium
                  .copyWith(color: context.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
