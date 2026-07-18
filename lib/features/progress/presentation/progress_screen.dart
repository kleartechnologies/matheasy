import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/progress_controller.dart';
import 'sections/progress_achievements.dart';
import 'sections/progress_mastery.dart';
import 'sections/progress_matheasy_insight.dart';
import 'sections/progress_profile.dart';
import 'sections/progress_recent_activity.dart';

/// The Progress tab — the XP / level / streak hero, mastery per topic, then
/// achievements, recent activity and a Matheasy insight. Reads an assembled
/// [ProgressOverview] that reacts to practice, achievement and analytics
/// changes.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(progressControllerProvider);

    final sections = <Widget>[
      ProgressProfile(overview: overview),
      ProgressMastery(mastery: overview.mastery),
      ProgressAchievements(
        onSeeAll: () => context.push(AppRoutes.progressAchievements),
      ),
      ProgressRecentActivity(activity: overview.recentActivity),
      ProgressMatheasyInsight(message: overview.matheasyInsight),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _Header()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.sm,
                AppSpacing.screenH,
                AppSpacing.tabClearance,
              ),
              sliver: SliverList.separated(
                itemCount: sections.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.section),
                itemBuilder: (context, index) => AppTransitions.slideUp(
                  delay: Duration(milliseconds: (index * 60).clamp(0, 300)),
                  duration: AppDurations.slow,
                  child: sections[index],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.lg,
        AppSpacing.screenH,
        AppSpacing.sm,
      ),
      child: _Title(),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        context.l10n.navProgress,
        style: Theme.of(context).textTheme.displaySmall,
      ),
    );
  }
}
