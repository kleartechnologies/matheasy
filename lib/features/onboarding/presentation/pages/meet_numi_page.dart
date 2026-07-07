import 'package:flutter/material.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 6 — Meet Numi (hero).
class MeetNumiPage extends StatelessWidget {
  const MeetNumiPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingIntroLayout(
      headline: 'Meet Numi',
      subtitle: 'Your AI Math Coach.',
      illustration: _MeetNumiArt(),
    );
  }
}

class _MeetNumiArt extends StatelessWidget {
  const _MeetNumiArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primaryTint.withValues(alpha: 0.28),
                  AppColors.primaryTint.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          const Floaty(child: NumiMascot(expression: NumiExpression.wave, size: 210)),
          const Positioned(top: 24, left: 30, child: _Sparkle(color: AppColors.gold, size: 20)),
          const Positioned(top: 80, right: 24, child: _Sparkle(color: AppColors.primaryTint, size: 14)),
          const Positioned(bottom: 54, left: 20, child: _Sparkle(color: AppColors.success, size: 13)),
        ],
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.25),
        ),
      ),
    );
  }
}
