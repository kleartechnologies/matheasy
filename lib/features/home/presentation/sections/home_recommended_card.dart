import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/home_models.dart';

/// A single adaptive practice recommendation, from Adaptive Practice weakness
/// targeting. One recommendation only.
class HomeRecommendedCard extends StatelessWidget {
  const HomeRecommendedCard({super.key, required this.topic});

  final WeakTopic topic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppCard(
      onTap: () => context.go(AppRoutes.practice),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recommended for you',
            style: AppTypography.label.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headingSmall.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${topic.accuracy}% accuracy',
                      style: AppTypography.caption.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Practice',
                    style: AppTypography.caption.copyWith(
                      color: topic.color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: topic.color),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
