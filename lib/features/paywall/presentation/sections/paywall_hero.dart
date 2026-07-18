import 'package:flutter/material.dart';
import 'package:matheasy/core/brand/brand.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../subscription/domain/paywall_trigger.dart';
import '../paywall_copy.dart';

/// The paywall's emotional opener: a floating Matheasy brand avatar over a warm
/// gold glow, then the headline and a trigger-aware sub-headline.
class PaywallHero extends StatelessWidget {
  const PaywallHero({super.key, required this.trigger});

  final PaywallTrigger trigger;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Soft gold aura behind the brand avatar.
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0.30),
                      AppColors.gold.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              const Floaty(child: MatheasyBrandAvatar(size: 116)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          context.l10n.paywallHeadline,
          textAlign: TextAlign.center,
          style: AppTypography.displaySmall.copyWith(color: AppColors.white),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            PaywallCopy.subheadline(trigger),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white.withValues(alpha: 0.76),
            ),
          ),
        ),
      ],
    );
  }
}
