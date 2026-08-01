import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Numi — the official AI identity of Matheasy, transcribed from the design.
///
/// **Every number in this file comes from the Claude Design export** in
/// `Numi identity and orb design/`:
///
/// * `NumiOrb.dc.html` — the orb itself: the seven-stop body gradient, the
///   core drift, the bounce light, the rim, the specular highlight, the star
///   halo and the star polygon.
/// * `Numi Identity.dc.html` §02 Anatomy — proportions and the light source,
///   §04 Colour System — the locked palette, §05 Motion — the four official
///   states, §06 Light & Dark — the two environments, §07 Scale — the 24→256
///   ramp.
///
/// Nothing here is invented and nothing here should be tuned by eye. The
/// identity is three shapes and one colour: **a green orb, a white four-point
/// star, a soft green glow** — §11 Brand Rules: never rotate or remove the
/// star, never break the circle, never change the green, never add a face.
///
/// All geometry is expressed as a **fraction of D** (the orb diameter), so the
/// mark is resolution independent from 24 px to 256 px and beyond.
abstract final class NumiSpec {
  // ───────────────────────────────────────────────────────── palette (§04)
  /// `#05AC60` — "THE ONE GREEN".
  ///
  /// One step off `AppColors.primary` (`#06AC60`, measured from the logo art).
  /// The two are indistinguishable on screen and are meant to be the same
  /// emerald; each keeps the value its own source of truth states, so neither
  /// silently drifts to match the other.
  static const Color coreGreen = Color(0xFF05AC60);

  /// `#8DF5BC` — internal light, and the colour of the ripple rings.
  static const Color highlight = Color(0xFF8DF5BC);

  /// `#023B21` — the terminator edge where the sphere turns away from light.
  static const Color shadow = Color(0xFF023B21);

  /// `#012D19` — the deepened terminator used on a brand-green surface (§06).
  static const Color shadowOnBrand = Color(0xFF012D19);

  /// `#3ADE8C` — the outer glow at its brightest, nearest the orb.
  static const Color glow = Color(0xFF3ADE8C);

  // ────────────────────────────────────────────────── orb body (NumiOrb.dc)
  // radial-gradient(118% 118% at 32% 22%, …) — a single soft light source at
  // 10:30 (§02), which is what makes the orb read as a sphere rather than a
  // disc. The centre is up and to the left; the gradient runs past the far
  // edge (radius 1.18 D) so the terminator never bands.
  static const Offset bodyCenter = Offset(0.32, 0.22);
  static const double bodyRadius = 1.18;
  static const List<Color> bodyColors = <Color>[
    Color(0xFFC9FFE2),
    Color(0xFF79F3B6),
    Color(0xFF2FD684),
    Color(0xFF05AC60),
    Color(0xFF06894C),
    Color(0xFF03562F),
    Color(0xFF023B21),
  ];
  static const List<double> bodyStops = <double>[
    0.0,
    0.09,
    0.26,
    0.50,
    0.72,
    0.89,
    1.0,
  ];

  // ─────────────────────────────────────────────────────── internal core
  // radial-gradient(46% 46% at 52% 62%, …), animated by `numi-core`: the light
  // *inside* the orb, drifting slowly around the star. §05: "the light moves,
  // never the symbol".
  static const Offset coreCenter = Offset(0.52, 0.62);
  static const double coreRadius = 0.46;
  static const List<Color> coreColors = <Color>[
    Color(0x8CB4FFD7), // rgba(180,255,215,.55)
    Color(0x475AF0AA), // rgba( 90,240,170,.28)
    Color(0x005AF0AA),
    Color(0x005AF0AA),
  ];
  static const List<double> coreStops = <double>[0.0, 0.38, 0.72, 1.0];

  /// `numi-core` keyframes: rest → peak → rest, as offsets in units of D.
  static const Offset coreDriftRest = Offset(-0.02, 0.01);
  static const Offset coreDriftPeak = Offset(0.04, -0.04);
  static const double coreScaleRest = 1.0;
  static const double coreScalePeak = 1.09;
  static const double coreOpacityRest = 0.82;
  static const double coreOpacityPeak = 1.0;

  // ─────────────────────────────────────────────────────── bounce light
  // radial-gradient(64% 34% at 50% 101%, …) — light thrown back up into the
  // underside of the sphere from the surface it sits on (§02: 50% / 101%).
  static const Offset bounceCenter = Offset(0.5, 1.01);
  static const double bounceRadiusX = 0.64;
  static const double bounceRadiusY = 0.34;
  static const List<Color> bounceColors = <Color>[
    Color(0x6BA3FFCE), // rgba(163,255,206,.42)
    Color(0x1FA3FFCE), // rgba(163,255,206,.12)
    Color(0x00A3FFCE),
    Color(0x00A3FFCE),
  ];
  static const List<double> bounceStops = <double>[0.0, 0.34, 0.62, 1.0];

  // ────────────────────────────────────────────────────────── rim light
  // The bright edge that separates the sphere from the surface behind it.
  // §06 dims it to 60% in light mode.
  //
  // NB the export writes these stops against a `farthest-corner` circle
  // (radius 0.707 D), which puts the whole ramp *outside* the 0.5 D disc the
  // orb is clipped to — i.e. a literal transcription renders no rim at all,
  // yet §06 lists "RIM LIGHT 100% / 60%" as a property of the two
  // environments. The stops are therefore resolved against the visible disc,
  // which is the only reading under which the named element exists.
  static const List<Color> rimColors = <Color>[
    Color(0x00FFFFFF),
    Color(0x00FFFFFF),
    Color(0x29FFFFFF), // rgba(255,255,255,.16)
    Color(0x4DFFFFFF), // rgba(255,255,255,.30)
  ];
  static const List<double> rimStops = <double>[0.0, 0.84, 0.95, 1.0];

  // ─────────────────────────────────────────────────── specular highlight
  // left:15% top:9% w:36% h:25% rotate(-22deg) — the hot spot of the 10:30
  // key light. Stored as centre + radii so it scales cleanly.
  static const Offset specularCenter = Offset(0.33, 0.215);
  static const double specularRadiusX = 0.18;
  static const double specularRadiusY = 0.125;
  static const double specularRotation = -22 * (3.1415926535897932 / 180);
  static const List<Color> specularColors = <Color>[
    Color(0xE6FFFFFF), // rgba(255,255,255,.9)
    Color(0x6BFFFFFF), // rgba(255,255,255,.42)
    Color(0x00FFFFFF),
  ];
  static const List<double> specularStops = <double>[0.0, 0.42, 1.0];

  // ──────────────────────────────────────────────── the star and its halo
  /// Optical centre of the star (§02: "CENTRE Y 0.47" — slightly above the
  /// geometric centre, so it reads as centred).
  static const Offset starCenter = Offset(0.5, 0.47);

  /// §02: 4 points, inner ratio 0.30, **axis locked at 0°**.
  static const int starPoints = 4;
  static const double starInnerRatio = 0.30;

  /// The soft bloom behind the star: `starR × 3.2` wide, i.e. 1.6 × its radius.
  static const double starHaloScale = 1.6;
  static const List<Color> starHaloColors = <Color>[
    Color(0x6BFFFFFF), // rgba(255,255,255,.42)
    Color(0x29DCFFEC), // rgba(220,255,236,.16)
    Color(0x00DCFFEC),
  ];
  static const List<double> starHaloStops = <double>[0.0, 0.40, 1.0];

  // ─────────────────────────────────────────────────────── ambient glow
  // inset:-42% with a farthest-corner circle, so the field reaches 0.91 D from
  // the centre — 0.41 D beyond the orb's edge, inside the 0.5 D clear space
  // §02 reserves. "AMBIENT, NEVER CLIPPED."
  static const double glowInset = 0.42;
  static const double glowRadius = 1.3011; // (1 + 2×0.42)/2 × √2
  static const List<Color> glowColors = <Color>[
    Color(0x573ADE8C), // rgba( 58,222,140,.34)
    Color(0x3805AC60), // rgba(  5,172, 96,.22)
    Color(0x1705AC60), // rgba(  5,172, 96,.09)
    Color(0x0005AC60),
    Color(0x0005AC60),
  ];
  static const List<double> glowStops = <double>[0.0, 0.26, 0.46, 0.70, 1.0];

  /// `numi-ambient` — the field breathes with the orb on the same 6.5s clock,
  /// swelling slightly as it brightens.
  ///
  /// The export declares the layer twice over: an inline
  /// `opacity: calc(var(--glow) * var(--gs) * 0.9)` *and* a keyframe that
  /// animates opacity `.62 → .9 → .62`. In CSS the animation wins outright, so
  /// as written the state knob `--gs` would do nothing — yet it is the very
  /// thing §05 varies per state (+35% listening, +55% responding) and §07 per
  /// size. The two are therefore composed rather than one discarded: the
  /// breathing runs `.62 → .9` and the knobs scale it, which reproduces the
  /// inline value exactly at the top of each breath.
  static const double glowOpacityRest = 0.62;
  static const double glowOpacityPeak = 0.9;
  static const double glowSpreadPeak = 1.04;
  static const Curve glowCurve = Curves.easeInOut;

  // ───────────────────────────────────────────────────────────── breathe
  // `numi-breathe` 6.5s — a float so small it is felt rather than seen. §05:
  // "The student should feel that Numi is patiently waiting, not idling."
  static const Duration breatheDuration = Duration(milliseconds: 6500);
  static const Curve breatheCurve = Cubic(0.45, 0, 0.55, 1);
  static const double breatheFloat = -0.014; // translateY(-1.4%)

  /// `numi-ripple` — a 1 px ring expanding from the orb's edge to 2.05 × D.
  ///
  /// The stroke is a CSS `border`, so it is scaled by the same transform that
  /// expands the ring, and it is 1 px at every orb size — a hairline is what
  /// keeps a ripple from reading as a second, harder edge.
  static const Curve rippleCurve = Cubic(0.15, 0.6, 0.3, 1);
  static const double rippleEndScale = 2.05;
  static const double rippleStartOpacity = 0.6;
  static const double rippleStrokeWidth = 1.0;

  /// `numi-sparkle` — 1.6s, invisible at rest, briefly bright at 45%.
  static const Duration sparkleDuration = Duration(milliseconds: 1600);
  static const double sparklePeak = 0.45;
  static const double sparklePeakOpacity = 0.9;
  static const double sparkleRestScale = 0.4;

  /// The four sparkles of the `--spark` layer, as (centre, diameter, phase) in
  /// units of D.
  ///
  /// They ring the orb at almost exactly its edge, and — like the ripples —
  /// paint *behind* it: in the export both layers are positioned siblings that
  /// precede the orb in tree order, and the orb's own root is positioned too,
  /// so it paints last and covers them. What survives is a sliver of light at
  /// the rim, which is the "faint sparkle" §05 asks of the responding state.
  static const List<({Offset center, double diameter, double phase})>
      sparkles = <({Offset center, double diameter, double phase})>[
    (center: Offset(0.0909, 0.2309), diameter: 0.0217, phase: 0.0),
    (center: Offset(0.8713, 0.3487), diameter: 0.0174, phase: 0.25),
    (center: Offset(0.7491, 0.8491), diameter: 0.0217, phase: 0.50),
    (center: Offset(0.2065, 0.7735), diameter: 0.0130, phase: 0.75),
  ];

  // ────────────────────────────────────────────────────────── scale (§07)
  /// The star grows as the orb shrinks, so the signature stays legible in
  /// toolbars and tab bars. §07: "Never simplify further — the star is never
  /// removed."
  /// §07's ramp exactly: 256/128/64 → 0.26, 48 → 0.28, 32 → 0.30, 24 → 0.32.
  static double starRatioFor(double size) {
    if (size >= 56) return 0.26;
    if (size >= 40) return 0.28;
    if (size >= 28) return 0.30;
    return 0.32;
  }

  /// …and the glow is pulled back with it, so a small orb stays a crisp shape
  /// rather than a green smudge: 48 and up → full, 32 → 0.70, 24 → 0.55.
  static double glowRampFor(double size) {
    if (size >= 40) return 1.0;
    if (size >= 28) return 0.70;
    return 0.55;
  }
}

/// The surface Numi is sitting on (§06 — "one orb, two environments").
enum NumiSurface {
  /// `#060B08`-ish. Glow `3ADE8C @ 34%`, full radius, rim light 100%.
  dark(glowScale: 1.0, rimOpacity: 1.0, shadowEdge: NumiSpec.shadow),

  /// `#F4F7F4`-ish. Glow `05AC60 @ 18%`, full radius, rim light 60%.
  light(glowScale: 0.5, rimOpacity: 0.6, shadowEdge: NumiSpec.shadow),

  /// On brand green: glow off, shadow only, terminator deepened to `#012D19`.
  brandGreen(
    glowScale: 0.0,
    rimOpacity: 1.0,
    shadowEdge: NumiSpec.shadowOnBrand,
  );

  const NumiSurface({
    required this.glowScale,
    required this.rimOpacity,
    required this.shadowEdge,
  });

  final double glowScale;
  final double rimOpacity;
  final Color shadowEdge;
}

/// The four official states (§05 Motion). Numi has no expression — everything
/// it feels is carried by light, breath and timing.
enum NumiState { idle, listening, thinking, responding }

/// One ripple ring: how strong it is, and where in the loop it starts.
typedef NumiRing = ({double opacity, double phase});

/// The motion contract for a state, transcribed from the `spec` object in
/// §05 Motion together with the four labelled state cards.
@immutable
class NumiStateSpec {
  const NumiStateSpec({
    required this.rippleOpacity,
    required this.rippleDuration,
    required this.rings,
    required this.rippleColor,
    required this.sparkleOpacity,
    required this.coreDuration,
    required this.glowScale,
    required this.scalePeak,
  });

  /// `--rip`: the opacity of the whole ripple layer.
  final double rippleOpacity;

  /// `--rip-dur`: how long one ring takes to expand and fade.
  final Duration rippleDuration;

  /// The concentric rings, each with its own strength and stagger.
  final List<NumiRing> rings;

  /// Ring stroke colour — `#8DF5BC`, brightened to `#C8FFE2` when responding.
  final Color rippleColor;

  /// `--spark`: the opacity of the sparkle layer.
  final double sparkleOpacity;

  /// `--core-dur`: how fast the internal light drifts. Faster = more effort.
  final Duration coreDuration;

  /// `--gs`: the glow multiplier. Listening leans in with light alone.
  final double glowScale;

  /// The top of the breathe: 1.018 idle, 1.035 on a responding bloom.
  final double scalePeak;

  static const NumiStateSpec idle = NumiStateSpec(
    rippleOpacity: 0,
    rippleDuration: Duration(milliseconds: 3000),
    rings: <NumiRing>[],
    rippleColor: NumiSpec.highlight,
    sparkleOpacity: 0,
    coreDuration: Duration(milliseconds: 7500),
    glowScale: 1.0,
    scalePeak: 1.018,
  );

  static const NumiStateSpec listening = NumiStateSpec(
    rippleOpacity: 0.9,
    rippleDuration: Duration(milliseconds: 2600),
    rings: <NumiRing>[(opacity: 0.5, phase: 0.0), (opacity: 0.32, phase: 0.5)],
    rippleColor: NumiSpec.highlight,
    sparkleOpacity: 0,
    coreDuration: Duration(milliseconds: 6000),
    glowScale: 1.3,
    scalePeak: 1.010,
  );

  static const NumiStateSpec thinking = NumiStateSpec(
    rippleOpacity: 0.65,
    rippleDuration: Duration(milliseconds: 3400),
    rings: <NumiRing>[
      (opacity: 0.4, phase: 0.0),
      (opacity: 0.28, phase: 1.1 / 3.4),
      (opacity: 0.18, phase: 2.2 / 3.4),
    ],
    rippleColor: NumiSpec.highlight,
    sparkleOpacity: 0,
    coreDuration: Duration(milliseconds: 3600),
    glowScale: 1.12,
    scalePeak: 1.018,
  );

  static const NumiStateSpec responding = NumiStateSpec(
    rippleOpacity: 0.95,
    rippleDuration: Duration(milliseconds: 900),
    rings: <NumiRing>[(opacity: 0.6, phase: 0.0)],
    rippleColor: Color(0xFFC8FFE2), // rgba(200,255,226,…)
    sparkleOpacity: 1,
    coreDuration: Duration(milliseconds: 2000),
    glowScale: 1.55,
    scalePeak: 1.035,
  );

  static NumiStateSpec of(NumiState state) => switch (state) {
        NumiState.idle => idle,
        NumiState.listening => listening,
        NumiState.thinking => thinking,
        NumiState.responding => responding,
      };

  /// Blend towards another state — used to land the responding one-shot back
  /// on idle ("a smooth return to idle. No fireworks, no celebration.").
  NumiStateSpec lerpTo(NumiStateSpec other, double t) => NumiStateSpec(
        rippleOpacity: rippleOpacity + (other.rippleOpacity - rippleOpacity) * t,
        rippleDuration: rippleDuration,
        rings: rings,
        rippleColor: rippleColor,
        sparkleOpacity:
            sparkleOpacity + (other.sparkleOpacity - sparkleOpacity) * t,
        coreDuration: coreDuration,
        glowScale: glowScale + (other.glowScale - glowScale) * t,
        scalePeak: scalePeak + (other.scalePeak - scalePeak) * t,
      );
}
