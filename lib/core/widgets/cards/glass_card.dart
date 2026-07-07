import 'dart:ui';

import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// A frosted-glass surface (blurred translucent background). Used for overlays
/// on imagery — e.g. scanner controls and the floating tab bar.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.card),
    this.borderRadius = AppRadius.cardRadius,
    this.blur = 22,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blur;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint ?? context.colors.surfaceGlass,
            borderRadius: borderRadius,
            border: Border.all(
              color: context.colors.border.withValues(alpha: 0.6),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
