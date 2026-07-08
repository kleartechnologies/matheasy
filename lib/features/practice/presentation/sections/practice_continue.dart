import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_session.dart';

/// "Continue practice" — resumes the topic from the last session.
class PracticeContinue extends StatelessWidget {
  const PracticeContinue({
    super.key,
    required this.request,
    required this.onResume,
  });

  final PracticeRequest request;
  final ValueChanged<PracticeRequest> onResume;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      onTap: () => onResume(request),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: request.topic.color.withValues(alpha: 0.14),
              borderRadius: AppRadius.mdRadius,
            ),
            child: Icon(request.topic.icon, size: 24, color: request.topic.color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Continue practice',
                  style: AppTypography.caption.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  request.displayTitle,
                  style: AppTypography.title.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 24,
              color: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}
