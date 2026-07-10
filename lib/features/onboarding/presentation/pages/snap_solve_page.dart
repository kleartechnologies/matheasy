import 'package:flutter/material.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/widgets/widgets.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 2 — Snap & Solve.
class SnapSolvePage extends StatelessWidget {
  const SnapSolvePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingIntroLayout(
      headline: 'Snap Any Math Question',
      subtitle: 'Point your camera at any problem and get a clear, '
          'step-by-step answer in seconds.',
      illustration: _SnapArt(),
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
            child: const MathSolutionCard(
              equationTex: r'2x + 5 = 13',
              label: 'DETECTED · 99%',
              caption: 'Linear equation · one unknown',
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
