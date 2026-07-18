import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../application/achievement_controller.dart';
import '../domain/achievement.dart';
import '../domain/achievement_progress.dart';
import 'widgets/badge_card.dart';

/// The full achievements screen — every badge grouped by category, with an
/// overall unlocked summary. Pushed over the shell from the Progress dashboard.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(achievementControllerProvider);
    final byCategory = <AchievementCategory, List<AchievementView>>{};
    for (final view in state.views) {
      byCategory.putIfAbsent(view.achievement.category, () => []).add(view);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 28,
          tooltip: context.l10n.progressBack,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(context.l10n.progressAchievementsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.md,
          AppSpacing.screenH,
          AppSpacing.xxl,
        ),
        children: [
          _SummaryCard(unlocked: state.unlockedCount, total: state.total),
          for (final category in AchievementCategory.values)
            if (byCategory[category] case final views?) ...[
              const SizedBox(height: AppSpacing.section),
              SectionHeader(title: category.label),
              const SizedBox(height: AppSpacing.md),
              _BadgeGrid(views: views),
            ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.unlocked, required this.total});

  final int unlocked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fraction = total == 0 ? 0.0 : unlocked / total;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$unlocked',
                style: AppTypography.displaySmall.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'of $total unlocked',
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          XPProgressBar(value: fraction),
        ],
      ),
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({required this.views});

  final List<AchievementView> views;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final view in views)
              SizedBox(
                width: cardWidth,
                child: AchievementBadgeCard(view: view),
              ),
          ],
        );
      },
    );
  }
}
