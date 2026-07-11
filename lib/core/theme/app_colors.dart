import 'package:flutter/widgets.dart';

/// Brand color palette — the fixed, brightness-agnostic hues that define
/// Matheasy's identity. These read the same in light and dark mode.
///
/// Anchored to the finalized **Matheasy Brand System (v1.0)**: an optimistic
/// Emerald (#10B981) paired with Mint and a deep Ink — the language of learning
/// and correctness, deliberately never fintech / crypto / enterprise.
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

  // ---- Primary (Brand Emerald) ----
  // Anchored to the brand mark: Emerald #10B981, Dark Emerald #059669. The
  // lighter/tint steps extend the same hue family for gradients and glows.
  static const Color primary = Color(0xFF10B981); // Emerald 500 — icon & mark
  static const Color primaryLight = Color(0xFF34D399); // Emerald 400 — gradient top / dark-mode mark
  static const Color primaryDark = Color(0xFF059669); // Emerald 600 — pressed/depth
  static const Color primaryDeep = Color(0xFF065F46); // Emerald 800 — text on primary container
  static const Color primaryTint = Color(0xFF6EE7B7); // Emerald 300 — soft glow / ring

  /// Brand ink — the wordmark & primary text hue from the brand system.
  static const Color ink = Color(0xFF0F172A);

  /// Deep ink — brand dark sections / immersive backdrops (#0B1220).
  static const Color inkDeep = Color(0xFF0B1220);

  /// Emerald elevation glow (Emerald at ~40% alpha) for hero surfaces.
  /// A const alpha variant of [primary] — Dart cannot derive alpha at
  /// compile-time, so glow tints live here as named tokens next to [primary].
  static const Color primaryGlow = Color(0x6610B981);

  /// Stronger emerald glow (~45% alpha) for raised CTAs (e.g. the Scan FAB).
  static const Color primaryGlowStrong = Color(0x7310B981);

  // ---- Emerald ramp (tints & shades) ----
  // The full brand ramp, for tonal surfaces and progress states.
  static const Color emerald50 = Color(0xFFECFDF5);
  static const Color emerald100 = Color(0xFFD1FAE5);
  static const Color emerald200 = Color(0xFFA7F3D0);
  static const Color emerald300 = Color(0xFF6EE7B7);
  static const Color emerald400 = Color(0xFF34D399);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald700 = Color(0xFF047857);
  static const Color emerald800 = Color(0xFF065F46);
  static const Color emerald900 = Color(0xFF064E3B);

  /// Mint surface — understanding & success tint from the brand system.
  static const Color mint = Color(0xFFD1FAE5);

  // ---- Categorical accents ----
  // The emerald brand is near-monochrome; these warm, harmonious hues keep
  // decorative/categorical UI (badges, topics, avatars, cards) legible without
  // the retired purple. Emerald stays the first accent; indigo / amber / coral
  // round out a four-hue set. [secondary] is kept as a name (used by the Material
  // ColorScheme) and points at the indigo accent.
  static const Color secondary = Color(0xFF6366F1); // Indigo 500 — categorical accent
  static const Color secondaryLight = Color(0xFF818CF8); // Indigo 400
  static const Color accentIndigo = secondary;
  static const Color accentAmber = Color(0xFFF59E0B); // Amber 500 — categorical amber
  static const Color accentCoral = Color(0xFFFB7185); // Rose 400
  static const Color accentCoralLight = Color(0xFFFDA4AF); // Rose 300

  // ---- Success (brand emerald doubles as "correct") ----
  // The brand system reuses the identity green for success on purpose — on an
  // education product, "correct" *is* the brand. Where success sits beside the
  // primary as a distinct category, use the accents above instead.
  static const Color success = Color(0xFF10B981);
  static const Color successDark = Color(0xFF059669);
  static const Color successDeep = Color(0xFF065F46);

  // ---- Warning / accent (orange) ----
  static const Color warning = Color(0xFFFF7A45);
  static const Color warningDeep = Color(0xFFF1740B);

  /// Legacy amber — unified to the single categorical brand amber
  /// [accentAmber] (#F59E0B) so the palette holds exactly one amber. Retained
  /// as a name for existing call sites; new code should reach for [accentAmber]
  /// (categorical) or [gold] / [xp] (premium / gamification) directly.
  static const Color amber = accentAmber;

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

  // ---- Dark brand surfaces ----
  // The scanner stays cool deep-ink (green tint muddies a camera feed); the
  // premium/paywall surfaces are a deep-emerald prestige (emerald + gold reads
  // premium and stays on-brand-warm).
  static const Color scannerBackground = Color(0xFF0A0F1C); // cool deep ink (camera)
  static const Color premiumNavy = Color(0xFF0E2A21); // deep emerald (premium)
  static const Color premiumNavyLight = Color(0xFF16493A); // mid emerald
  // Paywall background — two very close deep-navy stops. The gap is deliberately
  // near-imperceptible: this reads as depth, not a visible gradient (no colour
  // shift, no glow). Fixed (theme-independent) because the paywall is always dark.
  static const Color paywallTop = Color(0xFF0C1826); // navy (top)
  static const Color paywallBottom = Color(0xFF07111F); // deeper navy (bottom) — matches dark bg

  // ---- Gradients ----
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primary, primaryDark],
  );

  /// The brand app-icon gradient — Emerald 500 → 600, near-vertical (≈158°).
  static const LinearGradient iconGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primary, primaryDark],
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

  /// Paywall backdrop: a subtle vertical navy gradient (top → bottom) for depth
  /// only. Both stops are dark enough that white / emerald / gold text stays
  /// fully legible over it.
  static const LinearGradient paywallGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [paywallTop, paywallBottom],
  );
}
