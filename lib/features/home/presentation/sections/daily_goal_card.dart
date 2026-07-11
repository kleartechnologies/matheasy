import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/animations/pressable.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/home_models.dart';

/// The gradient "coach" hero — today's goal, progress and a Continue CTA.
class DailyGoalCard extends StatelessWidget {
  const DailyGoalCard({super.key, required this.goal, required this.isFirstDay});

  final DailyGoalInfo goal;
  final bool isFirstDay;

  @override
  Widget build(BuildContext context) {
    final title = isFirstDay
        ? "Let's start your first lesson!"
        : '${goal.lessonsDone} of ${goal.lessonsTarget} lessons done — nearly there!';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: AppRadius.heroRadius,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGlow,
            blurRadius: 40,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            right: -12,
            bottom: -20,
            child: Floaty(
              child: MatheasyBrandAvatar(size: 104),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pill(context, "TODAY'S GOAL"),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 210),
                child: Text(
                  title,
                  softWrap: true,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headingMedium
                      .copyWith(color: AppColors.white),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: 180,
                child: XPProgressBar(
                  value: goal.lessonsFraction,
                  gradient: AppColors.goldGradient,
                  trackColor: Colors.white.withValues(alpha: 0.28),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${goal.minutesStudied} / ${goal.minutesTarget} min studied today',
                style: AppTypography.caption
                    .copyWith(color: Colors.white.withValues(alpha: 0.85)),
              ),
              const SizedBox(height: AppSpacing.lg),
              _ContinueButton(
                label: isFirstDay ? 'Start learning' : 'Continue learning',
                onTap: () => context.go(AppRoutes.practice),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        text,
        style: AppTypography.label.copyWith(color: AppColors.white),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      borderRadius: AppRadius.pillRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.pillRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.button
                  .copyWith(color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.arrow_forward_rounded,
                size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
