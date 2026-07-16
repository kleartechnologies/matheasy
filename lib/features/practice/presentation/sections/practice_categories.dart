import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_dashboard.dart';
import '../../domain/practice_topic.dart';
import '../widgets/practice_chips.dart';

/// A two-column grid of every topic with its current mastery — the practice
/// categories. Tapping a card starts a session for that topic.
class PracticeCategories extends StatelessWidget {
  const PracticeCategories({
    super.key,
    required this.categories,
    required this.onStartTopic,
  });

  final List<CategoryView> categories;
  final ValueChanged<PracticeTopic> onStartTopic;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'All topics'),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - AppSpacing.md) / 2;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final category in categories)
                  SizedBox(
                    width: cardWidth,
                    child: _CategoryCard(
                      category: category,
                      onTap: onStartTopic,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final CategoryView category;
  final ValueChanged<PracticeTopic> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final topic = category.topic;

    return AppCard(
      onTap: () => onTap(topic),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PracticeTopicIcon(topic: topic),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  topic.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          XPProgressBar(value: category.progress, height: 6),
          const SizedBox(height: AppSpacing.xs),
          Text(
            category.level.label,
            style: AppTypography.caption.copyWith(
              // Emerald that stays AA on the card in either theme.
              color: context.isDark
                  ? AppColors.primaryLight
                  : AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
