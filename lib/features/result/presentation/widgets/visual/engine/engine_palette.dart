import 'package:flutter/material.dart';

import '../../../../../../core/extensions/context_extensions.dart';
import '../../../../../../core/theme/app_colors.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — theme colours passed INTO the scene
/// painters (a `CustomPainter` can't read `BuildContext`), mirroring the
/// `GeometryPalette` / `ConceptPalette` contract. Immutable so `shouldRepaint`
/// can compare cheaply.
@immutable
class EnginePalette {
  const EnginePalette({
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.warn,
    required this.stroke,
    required this.fill,
    required this.grid,
    required this.axis,
    required this.text,
    required this.muted,
    required this.surface,
  });

  final Color accent; // emerald (identity split honoured)
  final Color accentSoft; // low-alpha emerald fill
  final Color onAccent; // readable on the emerald container
  final Color warn; // amber emphasis
  final Color stroke; // figure outlines
  final Color fill; // faint figure fill
  final Color grid;
  final Color axis;
  final Color text;
  final Color muted;
  final Color surface;

  factory EnginePalette.of(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return EnginePalette(
      accent: emerald,
      accentSoft: emerald.withValues(alpha: context.isDark ? 0.22 : 0.14),
      onAccent: colors.onPrimaryContainer,
      warn: AppColors.warning,
      stroke: colors.textSecondary,
      fill: emerald.withValues(alpha: 0.07),
      grid: colors.border,
      axis: colors.textMuted,
      text: colors.textPrimary,
      muted: colors.textMuted,
      surface: colors.surface,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EnginePalette &&
      other.accent == accent &&
      other.warn == warn &&
      other.stroke == stroke &&
      other.fill == fill &&
      other.grid == grid &&
      other.axis == axis &&
      other.text == text &&
      other.muted == muted &&
      other.surface == surface;

  @override
  int get hashCode =>
      Object.hash(accent, warn, stroke, fill, grid, axis, text, muted, surface);
}
