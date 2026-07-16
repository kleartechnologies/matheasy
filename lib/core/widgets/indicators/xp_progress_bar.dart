import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_durations.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Animated progress bar for XP / lesson / goal completion.
class XPProgressBar extends StatelessWidget {
  const XPProgressBar({
    super.key,
    required this.value,
    this.height = 9,
    this.gradient,
    this.trackColor,
    this.label,
  }) : assert(value >= 0 && value <= 1, 'value must be between 0 and 1');

  /// Completion fraction in the range 0–1.
  final double value;
  final double height;

  /// Opt-in fill for the bars that are deliberately *not* brand-emerald (a gold
  /// daily challenge, a per-topic mastery bar). Left null, the fill is the solid
  /// interactive emerald — progress is a brand moment, and the brand's emerald
  /// does not gradient.
  final Gradient? gradient;

  final Color? trackColor;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: Stack(
            children: [
              Container(
                height: height,
                width: width,
                color: trackColor ?? context.colors.surfaceMuted,
              ),
              AnimatedContainer(
                duration: AppDurations.slow,
                curve: Curves.easeOutCubic,
                height: height,
                width: width * value.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  gradient: gradient,
                  color: gradient == null ? AppColors.primaryAction : null,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (label == null) return bar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar,
        const SizedBox(height: AppSpacing.xs),
        Text(
          label!,
          style: AppTypography.caption.copyWith(
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
