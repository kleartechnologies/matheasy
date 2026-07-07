import 'package:flutter/material.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/home_models.dart';

/// Streak card: current + best streak, a 7-day flame strip and a motivational
/// line from Numi.
class StreakSection extends StatelessWidget {
  const StreakSection({super.key, required this.streak});

  final StreakInfo streak;

  static const _weekDays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  int get _activeDays => streak.current >= 7 ? 7 : streak.current;

  String get _message => streak.isActive
      ? "You're on fire — keep the streak alive!"
      : 'Start your streak today. Learn a little every day. 💪';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded,
                  size: 30, color: AppColors.streak),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${streak.current}',
                style: AppTypography.headingLarge
                    .copyWith(color: colors.textPrimary),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'day streak',
                  style: AppTypography.bodyMedium
                      .copyWith(color: colors.textSecondary),
                ),
              ),
              const Spacer(),
              _BestChip(best: streak.best),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                _DayFlame(label: _weekDays[i], active: i < _activeDays),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const NumiMascot(expression: NumiExpression.wink, size: 36),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _message,
                  style: AppTypography.bodySmall
                      .copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BestChip extends StatelessWidget {
  const _BestChip({required this.best});

  final int best;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        'Best · $best',
        style: AppTypography.label.copyWith(color: context.colors.textSecondary),
      ),
    );
  }
}

class _DayFlame extends StatelessWidget {
  const _DayFlame({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: active
                ? AppColors.streak.withValues(alpha: 0.14)
                : colors.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.local_fire_department_rounded,
            size: 18,
            color: active ? AppColors.streak : colors.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: colors.textTertiary,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}
