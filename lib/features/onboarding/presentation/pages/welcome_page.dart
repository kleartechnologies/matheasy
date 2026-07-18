import 'package:flutter/material.dart';
import 'package:matheasy/core/brand/brand.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 1 — Welcome.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingIntroLayout(
      headline: context.l10n.onboardingWelcomeHeadline,
      subtitle: context.l10n.onboardingWelcomeSubtitle,
      illustration: const _WelcomeArt(),
    );
  }
}

class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primaryTint.withValues(alpha: 0.2),
                  AppColors.primaryTint.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          const Floaty(child: MatheasyBrandAvatar(size: 190)),
          const Positioned(top: 12, left: 24, child: _Sparkle(color: AppColors.gold, size: 18)),
          const Positioned(top: 70, right: 20, child: _Sparkle(color: AppColors.primaryTint, size: 13)),
          const Positioned(bottom: 40, left: 14, child: _Sparkle(color: AppColors.success, size: 12)),
        ],
      ),
    );
  }
}

/// A small rotated diamond accent used across the onboarding hero art.
class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45°
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
