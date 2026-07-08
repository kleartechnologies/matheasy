import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../../settings/presentation/widgets/settings_tile.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../subscription/application/usage_controller.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../../subscription/domain/purchase_result.dart';
import '../../subscription/domain/subscription_status.dart';
import '../../subscription/domain/usage_counts.dart';
import '../../subscription/domain/usage_snapshot.dart';
import '../../subscription/presentation/widgets/usage_meter.dart';

/// Full-screen subscription management (pushed over the shell). Shows the
/// current plan, live usage, and the upgrade / restore / manage actions —
/// wired to RevenueCat via [SubscriptionController].
class ProfileSubscriptionScreen extends ConsumerWidget {
  const ProfileSubscriptionScreen({super.key});

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final result =
        await ref.read(subscriptionControllerProvider.notifier).restore();
    if (!context.mounted) return;
    final message = switch (result) {
      PurchaseSuccess() => 'Your Pro subscription has been restored.',
      PurchaseNothingToRestore() => 'No previous purchases found to restore.',
      PurchaseFailure(:final message) => message,
      _ => 'Restore finished.',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _manage(BuildContext context) => AppDialog.show<void>(
        context,
        icon: Icons.settings_rounded,
        title: 'Manage subscription',
        message: Theme.of(context).platform == TargetPlatform.iOS
            ? 'Open the App Store app → tap your profile → Subscriptions to '
                'change or cancel your plan. Changes sync back automatically.'
            : 'Open the Play Store app → Menu → Payments & subscriptions → '
                'Subscriptions to change or cancel your plan. Changes sync back '
                'automatically.',
        primaryLabel: 'Got it',
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(subscriptionControllerProvider);
    final usage = ref.watch(usageSnapshotProvider);
    final isPro = status.isPro;

    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.lg,
            AppSpacing.screenH,
            AppSpacing.xxl,
          ),
          children: [
            if (isPro)
              _ProPlanCard(status: status)
            else
              _FreePlanCard(
                onUpgrade: () => context.push(
                  AppRoutes.paywall,
                  extra: PaywallTrigger.manual,
                ),
              ),
            const SizedBox(height: AppSpacing.section),
            _UsageSection(usage: usage),
            const SizedBox(height: AppSpacing.section),
            SettingsSection(
              children: [
                if (isPro)
                  SettingsTile(
                    icon: Icons.tune_rounded,
                    title: 'Manage subscription',
                    subtitle: 'Change plan or cancel',
                    onTap: () => unawaited(_manage(context)),
                  ),
                SettingsTile(
                  icon: Icons.restore_rounded,
                  title: 'Restore purchases',
                  subtitle: 'Recover a subscription bought before',
                  onTap: () => unawaited(_restore(context, ref)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProPlanCard extends StatelessWidget {
  const _ProPlanCard({required this.status});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final planName = switch (status.activePlan?.isAnnual) {
      true => 'Annual Pro',
      false => 'Monthly Pro',
      null => 'Matheasy Pro',
    };
    final renewLine = status.isCancelledButActive
        ? 'Access until ${_formatDate(status.expiresAt)} · auto-renew off'
        : status.expiresAt == null
            ? 'Active'
            : 'Renews on ${_formatDate(status.expiresAt)}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        gradient: AppColors.premiumGradient,
        borderRadius: AppRadius.cardRadius,
        boxShadow: [
          BoxShadow(
            color: Color(0x521E2440),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: AppColors.gold, size: 30),
              const SizedBox(width: AppSpacing.sm),
              Text(
                planName,
                style:
                    AppTypography.headingSmall.copyWith(color: AppColors.white),
              ),
              const Spacer(),
              _ProBadge(sandbox: status.isSandbox),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            renewLine,
            style: AppTypography.bodySmall
                .copyWith(color: const Color(0xFFB9BEE0)),
          ),
          if (status.hasBillingIssue) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.warning, size: 16),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'There is a billing issue — update your payment method to '
                    'keep Pro.',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.goldLight),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge({required this.sandbox});

  final bool sandbox;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        sandbox ? 'SANDBOX' : 'PRO',
        style: AppTypography.label.copyWith(color: AppColors.onGold),
      ),
    );
  }
}

class _FreePlanCard extends StatelessWidget {
  const _FreePlanCard({required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Free plan',
            style:
                AppTypography.headingSmall.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Upgrade to Pro for unlimited scans, Numi and practice.',
            style: AppTypography.bodySmall
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Upgrade to Pro',
            icon: Icons.workspace_premium_rounded,
            onPressed: onUpgrade,
          ),
        ],
      ),
    );
  }
}

class _UsageSection extends StatelessWidget {
  const _UsageSection({required this.usage});

  final UsageSnapshot usage;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your usage',
            style: AppTypography.title.copyWith(color: context.colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.lg),
          UsageMeter(
            icon: Icons.document_scanner_rounded,
            label: 'Scans',
            color: AppColors.primary,
            used: usage.counts.scansUsed,
            limit: usage.limit(UsageFeature.scan),
          ),
          const SizedBox(height: AppSpacing.lg),
          UsageMeter(
            icon: Icons.forum_rounded,
            label: 'Numi messages',
            color: AppColors.secondary,
            used: usage.counts.numiMessagesUsed,
            limit: usage.limit(UsageFeature.numiMessage),
          ),
          const SizedBox(height: AppSpacing.lg),
          UsageMeter(
            icon: Icons.fitness_center_rounded,
            label: 'Practice questions',
            color: AppColors.success,
            used: usage.counts.practiceQuestionsGenerated,
            limit: usage.limit(UsageFeature.practiceQuestion),
          ),
        ],
      ),
    );
  }
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime? date) {
  if (date == null) return '—';
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}
