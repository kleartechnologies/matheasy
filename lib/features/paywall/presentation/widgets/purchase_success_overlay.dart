import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/mascot/numi_mascot.dart';

/// A full-screen celebration shown the moment a purchase succeeds, before the
/// paywall dismisses. A quick scale-in of a cheering Numi over a gold burst —
/// the reward moment.
class PurchaseSuccessOverlay extends StatefulWidget {
  const PurchaseSuccessOverlay({super.key, required this.planName});

  final String planName;

  @override
  State<PurchaseSuccessOverlay> createState() => _PurchaseSuccessOverlayState();
}

class _PurchaseSuccessOverlayState extends State<PurchaseSuccessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.verySlow,
  )..forward();

  late final Animation<double> _pop = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.6, curve: Curves.easeOutBack),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.35, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: AppColors.paywallBottom.withValues(alpha: 0.96),
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: "You're now on ${widget.planName}. Enjoy unlimited learning!",
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.6, end: 1).animate(_pop),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.gold.withValues(alpha: 0.35),
                          AppColors.gold.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    child: const NumiMascot(
                      expression: NumiExpression.celebrate,
                      size: 132,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    "You're all set!",
                    style: AppTypography.displaySmall
                        .copyWith(color: AppColors.white),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Welcome to ${widget.planName} — enjoy unlimited learning.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
