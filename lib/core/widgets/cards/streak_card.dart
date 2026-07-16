import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'app_card.dart';

/// Highlights the user's learning streak with a warm flame accent.
class StreakCard extends StatelessWidget {
  const StreakCard({
    super.key,
    required this.days,
    this.subtitle = 'Day streak — keep it alive!',
    this.onTap,
  });

  final int days;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.colors.streakContainer,
              borderRadius: AppRadius.mdRadius,
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              // The container's paired on-colour. The raw AppColors.streak hue
              // is 3.32:1 on the dark container — a hair over the icon floor
              // and under it the moment anything nudges the tone.
              color: context.colors.onStreakContainer,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$days',
                  style: AppTypography.headingMedium
                      .copyWith(color: context.colors.textPrimary),
                ),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall
                      .copyWith(color: context.colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
