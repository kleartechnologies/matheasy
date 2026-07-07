import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'app_card.dart';

/// Compact metric tile: an icon, a big value and a small label. Used in the
/// profile/progress stat rows (streak, XP, accuracy, …).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: iconColor),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.headingMedium
                .copyWith(color: context.colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
