import 'package:flutter/widgets.dart';

/// Brand color palette — the fixed, brightness-agnostic hues that define
/// Matheasy's identity. These read the same in light and dark mode.
///
/// ## Anchored to the logo artwork
///
/// Every emerald in this file is **measured from the Matheasy logo**, not
/// invented. A k-means cluster over the artwork returns five tones, and four of
/// them are load-bearing:
///
/// | measured   | share | hsl              | role in the artwork |
/// |------------|-------|------------------|---------------------|
/// | `#06AC60`  | 56.7% | hsl(153, 93, 35) | the tile / identity |
/// | `#058446`  |  9.7% | hsl(151, 93, 27) | the mid shadow      |
/// | `#046934`  |  7.1% | hsl(148, 93, 21) | the deep shadow     |
/// | `#024221`  | 13.4% | hsl(150, 94, 13) | the outline         |
/// | `#FCFCFC`  | 13.2% | —                | the letterform      |
///
/// The logo is a *single hue family* — hue 148–153 at a near-constant 93%
/// saturation — and its whole design language is the lightness ramp
/// 13 → 21 → 27 → 35. [emerald500] / [emerald600] / [emerald700] / [emerald900]
/// are those four tones verbatim; the remaining steps interpolate along the same
/// hue/saturation signature. Nothing here is eyeballed.
///
/// ## The identity / action split (read this before using [primary])
///
/// White on the logo's emerald measures **2.97:1** — below both the 4.5:1 AA
/// text floor and the 3:1 non-text floor. The logo is exempt (WCAG 1.4.11
/// excludes logotypes) but *product UI is not*. So the emerald is split by job:
///
/// - [primary] (`#06AC60`) — the **identity**. The logo, the app icon tile, the
///   splash, brand art. Pixel-exact to the artwork. Never put functional white
///   text or a meaning-bearing white icon on it.
/// - [primaryAction] (`#058446`) — the **interactive** emerald. Every filled
///   control that carries white content: buttons, the Scan FAB, active states.
///   White on it is 4.78:1 ✓ AA.
/// - [primaryDark] (`#046934`) — emerald **text/icons on light surfaces**
///   (6.83:1 ✓ AA) and pressed depth.
///
/// Both are the logo's own tones one ramp step apart, so they read as one
/// system. `test/core/theme/brand_contrast_test.dart` enforces every ratio
/// quoted above — if you change a value here, that suite tells you what broke.
///
/// Theme-dependent tokens (surfaces, text, borders, container tints) live in
/// [AppSemanticColors] so they can flip between light and dark. Widgets should
/// pull surface/text colors from `context.colors` (the semantic extension) and
/// only reach into [AppColors] for brand hues.
class AppColors {
  const AppColors._();

  // ---- Neutrals ----
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  // ---- The brand emerald ramp ----
  // The single source of truth for every green in the product. Four steps are
  // measured from the logo; the rest interpolate along the logo's signature —
  // hue 149–154, saturation 93 through the mid/dark steps, easing to ~80 at the
  // near-white 50/100 tints (full saturation reads acid at 96% lightness).
  // Semantic aliases below point INTO this ramp — they never redeclare a value,
  // so there is exactly one definition of each tone.
  static const Color emerald50 = Color(0xFFEDFDF6);
  static const Color emerald100 = Color(0xFFD1FAE8);
  static const Color emerald200 = Color(0xFFA2F6D0);
  static const Color emerald300 = Color(0xFF5FF1B0);
  static const Color emerald400 = Color(0xFF0CE483);

  /// **Measured from the logo** — the tile. hsl(153, 93%, 35%).
  static const Color emerald500 = Color(0xFF06AC60);

  /// **Measured from the logo** — the mid shadow. hsl(151, 93%, 27%).
  static const Color emerald600 = Color(0xFF058446);

  /// **Measured from the logo** — the deep shadow. hsl(148, 93%, 21%).
  static const Color emerald700 = Color(0xFF046934);

  static const Color emerald800 = Color(0xFF03542A);

  /// **Measured from the logo** — the outline. hsl(150, 94%, 13%).
  static const Color emerald900 = Color(0xFF024221);

  // ---- Primary (semantic aliases into the ramp) ----

  /// The **identity** emerald — pixel-exact to the logo tile.
  ///
  /// Use for brand art: the mark, the app-icon tile, the splash. White on this
  /// is 2.97:1, so it is *not* a surface for functional white text or icons —
  /// reach for [primaryAction] there.
  static const Color primary = emerald500;

  /// The **interactive** emerald — the fill behind white label text and
  /// meaning-bearing white icons. White on this is 4.78:1 ✓ AA.
  ///
  /// This is the workhorse: buttons, the Scan FAB, active tab, filled chips.
  static const Color primaryAction = emerald600;

  /// Emerald **text and icons on light surfaces** (6.83:1 ✓ AA), and the
  /// pressed/depth step under [primaryAction].
  static const Color primaryDark = emerald700;

  /// Text on a light [AppSemanticColors.primaryContainer] (11.08:1 ✓ AA).
  static const Color primaryDeep = emerald900;

  /// The emerald that survives on dark surfaces — dark-mode marks and accents
  /// (10.13:1 on the dark surface ✓ AA).
  static const Color primaryLight = emerald400;

  /// Soft emerald for rings, tracks and tints. Decorative only — 1.43:1 on
  /// white, so never text.
  static const Color primaryTint = emerald300;

  /// Brand ink — the primary text hue. Derived from the logo: the brand hue
  /// pulled to a very low lightness, hsl(155, 51%, 8%). 17.21:1 on white.
  ///
  /// (Replaces the previous `#0F172A`, a blue-slate that belonged to no part of
  /// the identity and read cold against the emerald.)
  static const Color ink = Color(0xFF0A1F16);

  /// Deep ink — immersive backdrops. hsl(155, 55%, 5%).
  static const Color inkDeep = Color(0xFF06140E);

  // ---- Success (the brand emerald doubles as "correct") ----
  // On an education product, "correct" *is* the brand. Success reuses the
  // interactive emerald so a correct answer and a primary action share one
  // green — deliberate, per the brand system.
  static const Color success = primaryAction;
  static const Color successDeep = emerald900;

  // ---- Semantic status hues ----
  // The logo is monochrome green, so warning / error / info cannot be derived
  // from it by HUE. They are instead derived by its **tonal signature** — the
  // logo's own high-saturation, mid-lightness discipline (s~85, l~35–43)
  // applied at semantic hues. That keeps them siblings of the emerald rather
  // than imports from another palette, and every one clears AA on white.
  static const Color error = Color(0xFFBF271D); // hsl(4, 74, 43) — 5.96:1
  static const Color errorDeep = Color(0xFF941D14); // 8.59:1
  static const Color warning = Color(0xFFB65B0C); // hsl(28, 88, 38) — 4.68:1
  static const Color warningDeep = Color(0xFF8D4107); // 7.26:1
  static const Color info = Color(0xFF116BB0); // hsl(206, 82, 38) — 5.59:1
  static const Color infoDeep = Color(0xFF0C4E88); // 8.53:1

  // ---- Categorical accents ----
  // The emerald brand is near-monochrome; these hues keep decorative /
  // categorical UI (topics, badges, avatars) separable. They carry the same
  // tonal discipline as the ramp. [secondary] is the name the Material
  // ColorScheme wants and points at the indigo accent.
  static const Color secondary = Color(0xFF4F46E5); // Indigo — 6.30:1 on white
  static const Color secondaryLight = Color(0xFF818CF8);
  static const Color accentIndigo = secondary;
  static const Color accentAmber = warning;
  static const Color accentCoral = Color(0xFFC2410C);

  // ---- Premium / XP (gold) ----
  // Gamification accents. Gold is a *surface* color (dark ink sits on it), never
  // a text color on white — 1.63:1 there.
  static const Color gold = Color(0xFFFFD54A);
  static const Color goldLight = Color(0xFFFFE38A);

  /// Ink used on gold surfaces (badges, premium CTAs) in both themes.
  static const Color onGold = ink;
  static const Color xp = Color(0xFFFFC61A);
  static const Color streak = warning;

  // ---- Dark brand surfaces ----

  /// The scanner backdrop. Stays a near-neutral deep ink: a green tint muddies
  /// a live camera feed and makes real paper look wrong.
  static const Color scannerBackground = Color(0xFF080D0B);

  /// Premium / paywall backdrop — the logo's own outline tone [emerald900]
  /// pulled darker. Deep emerald + gold reads premium and stays on-brand.
  static const Color premiumDeep = Color(0xFF041A0F);
  static const Color premiumMid = Color(0xFF0A3323);

  // ---- Gradients ----
  // Deliberately few. The logo's tile is *flat* — its background measures
  // #06AD62 → #06AB5F corner to corner, a ~2-unit shift that is imperceptible.
  // So the brand does not gradient its emerald, and there is no `primaryGradient`
  // here on purpose: it used to fill every primary CTA with a #34D399 top stop
  // that put white text at 1.92:1. Filled controls use solid [primaryAction].

  /// Premium surfaces only (paywall, subscription). Two very close deep-emerald
  /// stops — depth, not a visible colour shift.
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [premiumMid, premiumDeep],
  );

  /// Gold gradient for premium badges and the paywall CTA.
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, gold],
  );
}
