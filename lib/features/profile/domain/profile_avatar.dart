import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A selectable placeholder avatar — a brand-coloured gradient rendered behind
/// the learner's initial. Real photo uploads arrive in a later stage; this gives
/// guests and email-less accounts an expressive, personal identity today.
enum ProfileAvatar {
  ocean('Ocean', [AppColors.primaryLight, AppColors.primaryDark]),
  grape('Grape', [AppColors.secondaryLight, AppColors.secondary]),
  meadow('Meadow', [AppColors.success, AppColors.successDeep]),
  sunset('Sunset', [AppColors.warning, AppColors.warningDeep]),
  blossom('Blossom', [AppColors.pink, AppColors.secondary]);

  const ProfileAvatar(this.label, this.colors);

  static const ProfileAvatar fallback = ProfileAvatar.ocean;

  final String label;
  final List<Color> colors;

  Gradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      );
}
