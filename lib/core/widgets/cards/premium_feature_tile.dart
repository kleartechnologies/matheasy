import 'package:flutter/material.dart';

import '../../animations/pressable.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The dark, gold-accented premium upsell banner used on Home and Profile.
/// Reads identically in light and dark mode (it is always the deep emerald
/// card).
class PremiumFeatureTile extends StatelessWidget {
  const PremiumFeatureTile({
    super.key,
    this.title = 'Unlock Matheasy Premium',
    this.subtitle = 'Unlimited scans, tutor & practice',
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      borderRadius: AppRadius.cardRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          gradient: AppColors.premiumGradient,
          borderRadius: AppRadius.cardRadius,
          // A neutral raise, not an emerald bloom: the tile is the darkest
          // thing on the page and needs lift, not glow.
          boxShadow: context.elevation.raised,
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium_rounded,
                color: AppColors.gold, size: 30),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.title.copyWith(color: AppColors.white),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.emerald100),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.gold, size: 24),
          ],
        ),
      ),
    );
  }
}
