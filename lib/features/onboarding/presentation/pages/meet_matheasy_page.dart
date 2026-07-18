import 'package:flutter/material.dart';
import 'package:matheasy/core/brand/brand.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 6 — Meet Matheasy (hero).
class MeetMatheasyPage extends StatelessWidget {
  const MeetMatheasyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingIntroLayout(
      headline: context.l10n.onboardingMeetHeadline,
      subtitle: context.l10n.onboardingMeetSubtitle,
      illustration: const _MeetMatheasyArt(),
    );
  }
}

class _MeetMatheasyArt extends StatelessWidget {
  const _MeetMatheasyArt();

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
          const Floaty(
            child: MatheasyLogo(
              variant: MatheasyLogoVariant.vertical,
              size: MatheasyLogoSize.large,
            ),
          ),
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
