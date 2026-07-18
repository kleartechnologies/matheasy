import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/services/haptics_service.dart';
import '../../application/onboarding_controller.dart';
import '../../domain/onboarding_models.dart';
import '../widgets/onboarding_layouts.dart';
import '../widgets/onboarding_option_tile.dart';

/// Page 8 — Challenge Selection (multi select).
class ChallengePage extends ConsumerWidget {
  const ChallengePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(onboardingFlowControllerProvider).topics;
    return OnboardingQuestionLayout(
      question: context.l10n.onboardingChallengeQuestion,
      subtitle: context.l10n.onboardingChallengeSubtitle,
      options: [
        for (final topic in MathTopic.values)
          OnboardingOptionTile(
            icon: topic.icon,
            label: topic.label,
            selected: selected.contains(topic),
            onTap: () {
              HapticsService.selection();
              ref
                  .read(onboardingFlowControllerProvider.notifier)
                  .toggleTopic(topic);
            },
          ),
      ],
    );
  }
}
