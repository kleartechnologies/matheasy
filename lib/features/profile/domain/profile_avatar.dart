import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A selectable placeholder avatar — a flat brand colour rendered behind the
/// learner's initial. Real photo uploads arrive in a later stage; this gives
/// email-less accounts an expressive, personal identity today.
///
/// Every colour is a token, and every one clears 4.5:1 against the white
/// initial that sits on it. They were gradients until the brand migration: the
/// light stop of each pair (`primaryLight` behind Ocean, `secondaryLight`
/// behind Grape) put that initial at ~1.7:1 — the same mistake the deleted
/// `primaryGradient` made. Flat, AA-safe tones instead.
///
/// The enum *names* are the persisted keys — never rename them.
enum ProfileAvatar {
  meadow('Meadow', AppColors.primaryAction),
  ocean('Ocean', AppColors.info),
  grape('Grape', AppColors.secondary),
  sunset('Sunset', AppColors.warning),
  blossom('Blossom', AppColors.accentCoral);

  const ProfileAvatar(this.label, this.color);

  /// The default identity, so an untouched profile reads as brand emerald.
  static const ProfileAvatar fallback = ProfileAvatar.meadow;

  final String label;
  final Color color;
}
