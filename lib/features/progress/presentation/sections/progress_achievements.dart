import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../application/achievement_controller.dart';
import '../../domain/achievement_progress.dart';
import '../widgets/badge_card.dart';

/// "Achievements" rail — recent unlocks first, then in-progress. Tapping "See
/// all" opens the full achievements screen.
class ProgressAchievements extends ConsumerWidget {
  const ProgressAchievements({super.key, required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(achievementControllerProvider);
    final views = _railOrder(state.views);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Achievements · ${state.unlockedCount}/${state.total}',
          actionLabel: 'See all',
          onAction: onSeeAll,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            clipBehavior: Clip.none,
            itemCount: views.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, i) => SizedBox(
              width: 168,
              child: AchievementBadgeCard(view: views[i], onTap: onSeeAll),
            ),
          ),
        ),
      ],
    );
  }

  /// Unlocked (most recent first), then in-progress (closest first), capped for
  /// the rail — the full list lives on the achievements screen.
  List<AchievementView> _railOrder(List<AchievementView> views) {
    final sorted = [...views]..sort((a, b) {
        if (a.isUnlocked != b.isUnlocked) return a.isUnlocked ? -1 : 1;
        if (a.isUnlocked && b.isUnlocked) {
          return b.unlockedAt!.compareTo(a.unlockedAt!);
        }
        return b.progress.fraction.compareTo(a.progress.fraction);
      });
    return sorted.take(8).toList();
  }
}
