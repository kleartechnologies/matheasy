import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../widgets/account_upgrade_benefits.dart';

/// The guest upsell shown on the Profile screen — the value of creating a free
/// account, with a clear primary CTA and a low-pressure "keep learning" exit.
///
/// Deliberately never mentions Premium or subscriptions.
class ProfileGuestCard extends StatelessWidget {
  const ProfileGuestCard({
    super.key,
    required this.onCreateAccount,
    required this.onContinue,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  // Solid interactive emerald — the icon on it is white.
                  color: AppColors.primaryAction,
                  borderRadius: AppRadius.mdRadius,
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  color: AppColors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "You're learning as a guest",
                      style: AppTypography.headingSmall
                          .copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Create a free account to keep your progress safe.',
                      style: AppTypography.bodySmall
                          .copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const AccountUpgradeBenefits(),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Create free account',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: onCreateAccount,
          ),
          const SizedBox(height: AppSpacing.sm),
          GhostButton(
            label: 'Continue learning',
            expand: true,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}
