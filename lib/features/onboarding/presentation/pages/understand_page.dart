import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 3 — Learn, Don't Just Copy.
class UnderstandPage extends StatelessWidget {
  const UnderstandPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingIntroLayout(
      headline: 'Understand Every Step',
      subtitle: 'Matheasy explains the why behind each step — so it actually '
          'sticks, not just copies.',
      illustration: _UnderstandArt(),
    );
  }
}

class _UnderstandArt extends StatelessWidget {
  const _UnderstandArt();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatBubble(text: 'Why do we subtract 5?', isUser: true),
          SizedBox(height: AppSpacing.md),
          MatheasyBubble(
            text: 'To get 2x on its own we undo the +5 first. Whatever we do '
                'to one side, we do to the other. 👍',
          ),
        ],
      ),
    );
  }
}
