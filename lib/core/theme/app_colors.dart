import 'package:flutter/widgets.dart';

/// Brand color palette — the fixed, brightness-agnostic hues that define
/// Matheasy's identity. These read the same in light and dark mode.
///
/// Theme-dependent tokens (surfaces, text, borders, container tints) live in
/// [AppSemanticColors] so they can flip between light and dark. Widgets should
/// pull surface/text colors from `context.colors` (the semantic extension) and
/// only reach into [AppColors] for brand hues and gradients.
class AppColors {
  const AppColors._();

  // ---- Neutrals ----
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  // ---- Primary (Brand Blue) ----
  // Anchored to the official brand mark: Brand Blue #2563EB, Deep Blue #1D4ED8.
  // The lighter/tint steps extend the same hue family for gradients and glows.
  static const Color primary = Color(0xFF2563EB); // Brand Blue — icon & mark
  static const Color primaryLight = Color(0xFF3B82F6); // gradient top / hover
  static const Color primaryDark = Color(0xFF1D4ED8); // Deep Blue — pressed/depth
  static const Color primaryPressed = Color(0xFF1D4ED8); // Deep Blue — pressed
  static const Color primaryDeep = Color(0xFF1E40AF); // text on primary container
  static const Color primaryTint = Color(0xFF60A5FA); // soft glow / ring

  /// Brand ink — the wordmark & primary text hue from the brand system.
  static const Color ink = Color(0xFF0F172A);

  /// Brand-blue elevation glow (Brand Blue at ~40% alpha) for hero surfaces.
  /// A const alpha variant of [primary] — Dart cannot derive alpha at
  /// compile-time, so glow tints live here as named tokens next to [primary].
  static const Color primaryGlow = Color(0x662563EB);

  /// Stronger brand-blue glow (~45% alpha) for raised CTAs (e.g. the Scan FAB).
  static const Color primaryGlowStrong = Color(0x732563EB);

  // ---- Secondary (purple) ----
  static const Color secondary = Color(0xFF7C4DFF);
  static const Color secondaryLight = Color(0xFF9B6BFF);

  // ---- Success (green) ----
  static const Color success = Color(0xFF34C759);
  static const Color successDark = Color(0xFF28B14C);
  static const Color successDeep = Color(0xFF158A3F);

  // ---- Warning / accent (orange) ----
  static const Color warning = Color(0xFFFF7A45);
  static const Color warningDeep = Color(0xFFF1740B);
  static const Color amber = Color(0xFFE8A400);

  // ---- Premium / XP (gold) ----
  static const Color gold = Color(0xFFFFD54A);
  static const Color goldLight = Color(0xFFFFE38A);

  /// Ink used on gold surfaces (badges, premium CTAs) in both themes.
  /// Uses the single brand [ink] so the palette has one true near-black.
  static const Color onGold = ink;
  static const Color xp = Color(0xFFFFC61A);
  static const Color streak = Color(0xFFFF7A45);

  // ---- Error (red) ----
  static const Color error = Color(0xFFFF3B30);
  static const Color errorDeep = Color(0xFFD22A20);

  // ---- Extra accent ----
  static const Color pink = Color(0xFFE8467F);

  // ---- Dark brand surfaces (used verbatim in both themes) ----
  static const Color scannerBackground = Color(0xFF0B0F1E);
  static const Color premiumNavy = Color(0xFF1E2440);
  static const Color premiumNavyLight = Color(0xFF33306B);
  static const Color paywallTop = Color(0xFF2C3466);
  static const Color paywallBottom = Color(0xFF11152A);

  // ---- Gradients ----
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primary, primaryDark],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [success, successDark],
  );

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, gold],
  );

  static const LinearGradient premiumGradient = LinearGradient(
    colors: [premiumNavy, premiumNavyLight],
  );

  static const LinearGradient paywallGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [paywallTop, paywallBottom],
  );
}
