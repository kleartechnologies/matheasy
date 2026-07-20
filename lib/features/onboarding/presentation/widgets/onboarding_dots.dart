import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';

/// The carousel page indicator: [count] dots where the active one stretches
/// into an emerald pill. Animates the width change on page change and honours
/// reduced motion (jumps instead of tweening).
class OnboardingDots extends StatelessWidget {
  const OnboardingDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final active = context.isDark
        ? AppColors.primaryLight
        : AppColors.primaryAction;
    final inactive = context.colors.textMuted.withValues(alpha: 0.28);
    return Semantics(
      label: context.l10n.resultStepOfTotal(index + 1, count),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: reduced ? Duration.zero : AppDurations.medium,
              curve: AppCurves.emphasized,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == index ? 26 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index ? active : inactive,
                borderRadius: AppRadius.pillRadius,
              ),
            ),
        ],
      ),
    );
  }
}
