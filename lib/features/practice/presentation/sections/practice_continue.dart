import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_session.dart';
import '../widgets/practice_chips.dart';

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
          PracticeTopicIcon(topic: request.topic, size: 48),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.practiceContinueTitle,
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
            // Solid interactive emerald — carries a white glyph (4.78:1 AA).
            decoration: const BoxDecoration(
              color: AppColors.primaryAction,
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
