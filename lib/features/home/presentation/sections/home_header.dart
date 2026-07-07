import 'package:flutter/material.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/home_models.dart';

/// Greeting + streak + Numi avatar row at the top of Home.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.userName, required this.streak});

  final String userName;
  final StreakInfo streak;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final greeting = greetingForHour(DateTime.now().hour);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting,',
                style: AppTypography.bodyMedium
                    .copyWith(color: colors.textSecondary),
              ),
              Text(
                userName,
                style: AppTypography.headingLarge
                    .copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        _StreakPill(count: streak.current),
        const SizedBox(width: AppSpacing.sm),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: AppRadius.mdRadius,
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.topCenter,
          child: const Padding(
            padding: EdgeInsets.only(top: 6),
            child: NumiMascot(size: 42),
          ),
        ),
      ],
    );
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.mdRadius,
        boxShadow: context.elevation.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              size: 20, color: AppColors.streak),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$count',
            style: AppTypography.title.copyWith(color: context.colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
