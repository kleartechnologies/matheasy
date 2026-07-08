import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_dashboard.dart';
import '../../domain/practice_topic.dart';

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
    final gradient = LinearGradient(
      colors: [topic.color, topic.color.withValues(alpha: 0.75)],
    );

    return AppCard(
      onTap: () => onTap(topic),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  topic.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.title.copyWith(
                    color: colors.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          XPProgressBar(value: category.progress, gradient: gradient, height: 6),
          const SizedBox(height: AppSpacing.xs),
          Text(
            category.level.label,
            style: AppTypography.caption.copyWith(
              color: topic.color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
