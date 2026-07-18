import 'package:flutter/material.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/widgets/widgets.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 2 — Snap & Solve.
class SnapSolvePage extends StatelessWidget {
  const SnapSolvePage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingIntroLayout(
      headline: context.l10n.onboardingSnapHeadline,
      subtitle: context.l10n.onboardingSnapSubtitle,
      illustration: const _SnapArt(),
    );
  }
}

class _SnapArt extends StatelessWidget {
  const _SnapArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 280,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -0.04,
            child: MathSolutionCard(
              equationTex: r'2x + 5 = 13',
              label: 'DETECTED · 99%',
              caption: context.l10n.onboardingSnapCaption,
              answerTex: r'x = 4',
            ),
          ),
          const Positioned(
            bottom: -26,
            right: -8,
            child: Floaty(child: MatheasyBrandAvatar(size: 92)),
          ),
        ],
      ),
    );
  }
}
