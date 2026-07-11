import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../subscription/application/usage_controller.dart';
import '../../../subscription/domain/paywall_trigger.dart';
import '../../../subscription/domain/usage_counts.dart';
import '../../../subscription/presentation/widgets/usage_meter.dart';

/// A subtle, non-intrusive Home entry point for free users: their remaining
/// scans / AI tutor / practice at a glance, with a quiet upgrade affordance. Pro
/// users never see it (the caller omits it), so there's no nagging.
class HomeUsageCard extends ConsumerWidget {
  const HomeUsageCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(usageSnapshotProvider);
    final colors = context.colors;

    return AppCard(
      onTap: () =>
          context.push(AppRoutes.paywall, extra: PaywallTrigger.manual),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Your free plan',
                style: AppTypography.title.copyWith(color: colors.textPrimary),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Upgrade',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.primary),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          UsageMeter(
            icon: Icons.document_scanner_rounded,
            label: 'Scans',
            color: AppColors.primary,
            used: usage.counts.scansUsed,
            limit: usage.limit(UsageFeature.scan),
          ),
          const SizedBox(height: AppSpacing.md),
          UsageMeter(
            icon: Icons.forum_rounded,
            label: 'AI tutor messages',
            color: AppColors.secondary,
            used: usage.counts.tutorMessagesUsed,
            limit: usage.limit(UsageFeature.tutorMessage),
          ),
          const SizedBox(height: AppSpacing.md),
          UsageMeter(
            icon: Icons.fitness_center_rounded,
            label: 'Practice questions',
            color: AppColors.accentAmber,
            used: usage.counts.practiceQuestionsGenerated,
            limit: usage.limit(UsageFeature.practiceQuestion),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: AppRadius.smRadius,
            ),
            child: Text(
              'Unlock Visual Learning + unlimited scans, tutor & practice',
              textAlign: TextAlign.center,
              style: AppTypography.caption
                  .copyWith(color: colors.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
