import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../subscription/application/subscription_controller.dart';
import '../../../subscription/application/usage_controller.dart';
import '../../../subscription/domain/usage_counts.dart';
import '../../../subscription/presentation/widgets/usage_meter.dart';

/// Free-plan usage — remaining scans, AI tutor messages and practice questions.
/// Lives on Profile (the account dashboard); Pro users see nothing (unlimited).
class ProfileUsageSection extends ConsumerWidget {
  const ProfileUsageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isProProvider)) return const SizedBox.shrink();

    final usage = ref.watch(usageSnapshotProvider);
    final colors = context.colors;
    // The meter's colour is a foreground (icon + bar), so the identity emerald
    // (2.97:1 on a light card) can't carry it.
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.profileFreePlanUsage,
            style: AppTypography.label.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          UsageMeter(
            icon: Icons.document_scanner_rounded,
            label: context.l10n.profileUsageScans,
            color: emerald,
            used: usage.counts.scansUsed,
            limit: usage.limit(UsageFeature.scan),
          ),
          const SizedBox(height: AppSpacing.md),
          UsageMeter(
            icon: Icons.forum_rounded,
            label: context.l10n.profileUsageTutor,
            color: AppColors.secondary,
            used: usage.counts.tutorMessagesUsed,
            limit: usage.limit(UsageFeature.tutorMessage),
          ),
          const SizedBox(height: AppSpacing.md),
          UsageMeter(
            icon: Icons.fitness_center_rounded,
            label: context.l10n.profileUsagePractice,
            color: AppColors.accentAmber,
            used: usage.counts.practiceQuestionsGenerated,
            limit: usage.limit(UsageFeature.practiceQuestion),
          ),
        ],
      ),
    );
  }
}
