import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_topic.dart';
import '../widgets/practice_chips.dart';

/// A horizontal rail of recommended topics (from the learner's onboarding
/// choices). Tapping one starts a session for that topic.
class PracticeRecommendedTopics extends StatelessWidget {
  const PracticeRecommendedTopics({
    super.key,
    required this.topics,
    required this.onStartTopic,
  });

  final List<PracticeTopic> topics;
  final ValueChanged<PracticeTopic> onStartTopic;

  @override
  Widget build(BuildContext context) {
    if (topics.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: context.l10n.practiceRecommendedForYou),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            clipBehavior: Clip.none,
            itemCount: topics.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, i) =>
                _TopicCard(topic: topics[i], onTap: onStartTopic),
          ),
        ),
      ],
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.onTap});

  final PracticeTopic topic;
  final ValueChanged<PracticeTopic> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 140,
      child: AppCard(
        onTap: () => onTap(topic),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            PracticeTopicIcon(topic: topic),
            Text(
              topic.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.title.copyWith(
                color: colors.textPrimary,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
