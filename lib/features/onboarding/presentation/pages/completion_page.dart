import 'package:flutter/material.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 10 — Completion (celebration).
class CompletionPage extends StatelessWidget {
  const CompletionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingIntroLayout(
      headline: "You're Ready To Start Learning.",
      subtitle: 'Numi will guide you every step of the way.',
      illustration: _CompletionArt(),
    );
  }
}

class _CompletionArt extends StatelessWidget {
  const _CompletionArt();

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
                  AppColors.success.withValues(alpha: 0.28),
                  AppColors.success.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          const Floaty(
            child: NumiMascot(expression: NumiExpression.celebrate, size: 200),
          ),
          const Positioned(top: 20, left: 26, child: _Sparkle(color: AppColors.gold, size: 20)),
          const Positioned(top: 60, right: 20, child: _Sparkle(color: AppColors.success, size: 15)),
          const Positioned(bottom: 46, left: 24, child: _Sparkle(color: AppColors.primaryTint, size: 13)),
          const Positioned(bottom: 80, right: 34, child: _Sparkle(color: AppColors.gold, size: 11)),
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
