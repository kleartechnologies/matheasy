import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/services/haptics_service.dart';
import '../../application/onboarding_controller.dart';
import '../../domain/onboarding_models.dart';
import '../widgets/onboarding_layouts.dart';
import '../widgets/onboarding_option_tile.dart';

/// Page 9 — Daily Goal (single select).
class DailyGoalPage extends ConsumerWidget {
  const DailyGoalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(onboardingFlowControllerProvider).goal;
    return OnboardingQuestionLayout(
      question: context.l10n.onboardingDailyGoalQuestion,
      subtitle: context.l10n.onboardingDailyGoalSubtitle,
      options: [
        for (final goal in DailyGoal.values)
          OnboardingOptionTile(
            icon: Icons.schedule_rounded,
            label: goal.label,
            trailingText: goal.tag,
            selected: selected == goal,
            onTap: () {
              HapticsService.selection();
              ref
                  .read(onboardingFlowControllerProvider.notifier)
                  .selectGoal(goal);
            },
          ),
      ],
    );
  }
}
