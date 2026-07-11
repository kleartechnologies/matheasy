import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/tutor_models.dart';

/// A two-column grid of learning categories. Tapping a card opens the chat
/// seeded to teach that topic.
class TutorLearningCategories extends StatelessWidget {
  const TutorLearningCategories({
    super.key,
    required this.categories,
    required this.onSelected,
  });

  final List<TutorCategory> categories;
  final ValueChanged<TutorCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Explore topics'),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth =
                (constraints.maxWidth - AppSpacing.md) / 2;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final category in categories)
                  SizedBox(
                    width: cardWidth,
                    child: _CategoryCard(
                      category: category,
                      onTap: onSelected,
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

  final TutorCategory category;
  final ValueChanged<TutorCategory> onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => onTap(category),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: 0.14),
              borderRadius: AppRadius.smRadius,
            ),
            child: Icon(category.icon, size: 22, color: category.color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              category.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
