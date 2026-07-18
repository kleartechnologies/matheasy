import 'package:flutter/material.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 3 — Learn, Don't Just Copy.
class UnderstandPage extends StatelessWidget {
  const UnderstandPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingIntroLayout(
      headline: context.l10n.onboardingUnderstandHeadline,
      subtitle: context.l10n.onboardingUnderstandSubtitle,
      illustration: const _UnderstandArt(),
    );
  }
}

class _UnderstandArt extends StatelessWidget {
  const _UnderstandArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatBubble(text: context.l10n.onboardingUnderstandQuestion, isUser: true),
          const SizedBox(height: AppSpacing.md),
          MatheasyBubble(
            text: context.l10n.onboardingUnderstandAnswer,
          ),
        ],
      ),
    );
  }
}
