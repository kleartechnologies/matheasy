import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/services/haptics_service.dart';
import '../../application/onboarding_controller.dart';
import '../../domain/onboarding_models.dart';
import '../widgets/onboarding_layouts.dart';
import '../widgets/onboarding_option_tile.dart';

/// Page 7 — Study Level (single select).
class StudyLevelPage extends ConsumerWidget {
  const StudyLevelPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(onboardingFlowControllerProvider).level;
    return OnboardingQuestionLayout(
      question: context.l10n.onboardingStudyLevelQuestion,
      subtitle: context.l10n.onboardingStudyLevelSubtitle,
      options: [
        for (final level in StudyLevel.values)
          OnboardingOptionTile(
            icon: level.icon,
            label: level.label,
            selected: selected == level,
            onTap: () {
              HapticsService.selection();
              ref
                  .read(onboardingFlowControllerProvider.notifier)
                  .selectLevel(level);
            },
          ),
      ],
    );
  }
}
