import 'package:flutter/material.dart';

import '../../animations/pressable.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// The workhorse surface of the app: a rounded, softly-elevated white/dark card.
/// Optionally tappable (adds press-scale feedback + haptics).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.card),
    this.borderRadius = AppRadius.cardRadius,
    this.color,
    this.border,
    this.elevated = true,
    this.clip = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? color;
  final BoxBorder? border;
  final bool elevated;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color ?? context.colors.surface,
        borderRadius: borderRadius,
        border: border,
        boxShadow: elevated ? context.elevation.card : null,
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Pressable(
      onTap: onTap,
      borderRadius: borderRadius,
      child: card,
    );
  }
}
