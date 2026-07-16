import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../subscription/application/subscription_controller.dart';
import '../../../subscription/application/usage_controller.dart';

/// The Profile tab's subscription entry point: a Pro status card for
/// subscribers, or the premium upsell tile (with live remaining-usage context)
/// for free users. Both open the full subscription management screen.
class ProfileSubscriptionSection extends ConsumerWidget {
  const ProfileSubscriptionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);
    void open() => context.push(AppRoutes.profileSubscription);

    if (isPro) return _ProCard(onTap: open);

    final usage = ref.watch(usageSnapshotProvider);
    final remaining = usage.remainingScans;
    final subtitle = remaining <= 0
        ? "You've used your free scans — go unlimited"
        : '$remaining free scans left · unlock unlimited';

    return PremiumFeatureTile(
      title: 'Upgrade to Matheasy Pro',
      subtitle: subtitle,
      onTap: open,
    );
  }
}

class _ProCard extends StatelessWidget {
  const _ProCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      borderRadius: AppRadius.cardRadius,
      child: Semantics(
        button: true,
        label: 'Matheasy Pro. Manage subscription',
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          decoration: const BoxDecoration(
            gradient: AppColors.premiumGradient,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: AppColors.gold, size: 28),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Matheasy Pro',
                      style: AppTypography.title
                          .copyWith(color: AppColors.white),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Unlimited everything · manage plan',
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
      ),
    );
  }
}
