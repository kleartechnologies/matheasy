import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/home_models.dart';

/// "Recommended practice" — a horizontal rail of questions tuned to the
/// learner's weak topics.
class RecommendedPractice extends StatelessWidget {
  const RecommendedPractice({super.key, required this.items});

  final List<PracticeRecommendation> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Recommended practice',
          actionLabel: 'More',
          onAction: () => context.go(AppRoutes.practice),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, i) => _RecommendationCard(items[i]),
          ),
        ),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard(this.item);

  final PracticeRecommendation item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (bg, fg) = switch (item.difficulty) {
      Difficulty.easy => (colors.successContainer, colors.onSuccessContainer),
      Difficulty.medium => (colors.warningContainer, colors.onWarningContainer),
      Difficulty.hard => (colors.errorContainer, colors.onErrorContainer),
    };

    return SizedBox(
      width: 176,
      child: AppCard(
        onTap: () => context.go(AppRoutes.practice),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Math.tex(
              item.question,
              textStyle: AppTypography.headingSmall
                  .copyWith(color: colors.textPrimary),
              mathStyle: MathStyle.text,
              onErrorFallback: (_) => Text(
                item.question,
                style: AppTypography.headingSmall
                    .copyWith(color: colors.textPrimary),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppRadius.smRadius,
              ),
              child: Text(
                item.difficulty.label,
                style: AppTypography.label.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
