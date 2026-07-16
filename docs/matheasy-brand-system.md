# Matheasy Brand System — v2.0 (logo-anchored)

The single source of truth for Matheasy's visual identity. Supersedes the v1.0
"Emerald #10B981 + R8 two-check" system, which is **retired** — if a doc,
comment, or memory still says `#10B981` or "two ascending checkmarks", it is
wrong.

- **Source artwork:** [`brand/matheasy-logo-source.png`](../brand/matheasy-logo-source.png)
- **Derivation scripts:** [`brand/derive-palette.js`](../brand/derive-palette.js),
  [`brand/derive-mark-geometry.js`](../brand/derive-mark-geometry.js)
- **Code:** [`lib/core/theme/app_colors.dart`](../lib/core/theme/app_colors.dart),
  [`lib/core/theme/app_semantic_colors.dart`](../lib/core/theme/app_semantic_colors.dart),
  [`lib/core/brand/matheasy_mark.dart`](../lib/core/brand/matheasy_mark.dart)
- **Enforcement:** [`test/core/theme/brand_contrast_test.dart`](../test/core/theme/brand_contrast_test.dart)

---

## 1. Extracted palette

A k-means cluster over the logo artwork returns five tones. Four are
load-bearing:

| Measured  | Share | HSL              | Role in the artwork | Token        |
|-----------|-------|------------------|---------------------|--------------|
| `#06AC60` | 56.7% | hsl(153, 93, 35) | the tile            | `emerald500` |
| `#024221` | 13.4% | hsl(150, 94, 13) | the outline         | `emerald900` |
| `#FCFCFC` | 13.2% | —                | the letterform      | `white`      |
| `#058446` |  9.7% | hsl(151, 93, 27) | the mid shadow      | `emerald600` |
| `#046934` |  7.1% | hsl(148, 93, 21) | the deep shadow     | `emerald700` |

**The finding that drives everything:** the logo is a *single hue family* —
hue 148–153 at a near-constant 93% saturation. Its entire design language is the
lightness ramp `13 → 21 → 27 → 35`. It is not a green plus some accents; it is
one green at four depths.

Two consequences:

1. The ramp in code is the logo's own tonal steps, with the gaps interpolated
   along the same hue/saturation signature. Nothing is eyeballed.
2. The old brand's `#10B981` is hsl(160, 84, 39) — **7° of hue, 9% of saturation
   and 4% of lightness away**. It is a teal-leaning green; the logo is a true
   green. Every emerald in the app moved.

## 2. The identity / action split

> White on the logo's emerald measures **2.97:1**.

That is below the 4.5:1 AA floor for text *and* the 3:1 floor for non-text. The
logo itself is fine — WCAG 1.4.11 explicitly exempts logotypes — but product UI
is not exempt. The brief asked for both "all colors derived from the logo" and
"maintain WCAG contrast", and for white-on-emerald those cannot both hold.

The resolution is to split the emerald **by job**, using tones the logo already
contains:

| Token           | Value     | Job                                              | Contrast |
|-----------------|-----------|--------------------------------------------------|----------|
| `primary`       | `#06AC60` | **identity only** — mark, icon tile, splash      | white 2.97:1 (exempt) |
| `primaryAction` | `#058446` | **every filled control** carrying white content  | white **4.78:1** ✅ |
| `primaryDark`   | `#046934` | **emerald text/icons on light**, pressed depth   | on white **6.83:1** ✅ |
| `primaryLight`  | `#0CE483` | the emerald that survives on **dark** surfaces   | on dark surface **10.13:1** ✅ |

`primary` and `primaryAction` are one ramp step apart and both come from the
artwork, so they read as one system — but only one of them is safe under a white
label.

**Rules:**
- Never put functional white text or a meaning-bearing white icon on `primary`.
- Never use `primary` as a foreground text color on a light surface.
- Filled control + white label ⇒ `primaryAction`.
- Emerald text ⇒ `primaryDark` (light) / `primaryLight` (dark).

## 3. Token system

Centralised in two files. `AppColors` = fixed brand hues, brightness-agnostic.
`AppSemanticColors` = a `ThemeExtension` that flips light/dark, reached via
`context.colors`. Features must never hardcode a `Color(0x…)`.

### Brand ramp — `AppColors`

```
emerald50   #EDFDF6      emerald500  #06AC60  ← LOGO (tile)
emerald100  #D1FAE8      emerald600  #058446  ← LOGO (mid shadow)
emerald200  #A2F6D0      emerald700  #046934  ← LOGO (deep shadow)
emerald300  #5FF1B0      emerald800  #03542A
emerald400  #0CE483      emerald900  #024221  ← LOGO (outline)
```

Semantic aliases point *into* the ramp (`primary = emerald500`) rather than
redeclaring a value — so each tone has exactly one definition. The old system had
`emerald500`, `primary` and `success` as three separate `#10B981` literals; a
rebrand had to find all three, and missing one produced a silent divergence.

### Ink & status

```
ink      #0A1F16   the brand hue at very low lightness — 17.21:1 on white
inkDeep  #06140E
error    #BF271D   5.96:1     warning  #B65B0C   4.68:1
info     #116BB0   5.59:1     success  = primaryAction
```

`ink` used to be `#0F172A` — a blue-slate that belonged to no part of the
identity and read cold beside the emerald. It is now the logo's own hue pulled
down, so text and brand sit in one family.

**On the status hues:** the logo is monochrome green, so warning/error/info
**cannot** be derived from it by hue — this is a genuine limit of the brief. They
are instead derived by the logo's *tonal signature*: its high-saturation,
mid-lightness discipline (s≈85, l≈35–43) applied at semantic hues. That makes
them siblings of the emerald rather than imports from another palette, and every
one clears AA.

### Surfaces & text — `AppSemanticColors`

The neutrals are not grey: they are the logo's hue (≈155) held at low saturation,
so surfaces sit in the same family as the emerald. Dark mode is the logo's
outline tone carried down past it.

|                 | Light      | Dark       |
|-----------------|------------|------------|
| `background`    | `#F4F7F5`  | `#081410`  |
| `surface`       | `#FFFFFF`  | `#0E1F18`  |
| `card`          | `#FFFFFF`  | `#0E1F18`  |
| `surfaceMuted`  | `#EBF0EE`  | `#14291F`  |
| `border`        | `#DFE7E4`  | white 8%   |
| `textPrimary`   | `#0A1F16`  | `#E8F2EC`  |
| `textSecondary` | `#53655E`  | `#AFC0B9`  |
| `textMuted`     | `#5D6F68`  | `#8A9E96`  |

Every text-on-surface pair clears AA (4.5:1) in both themes — including on
`surfaceMuted`, which is the darkest thing light-mode text ever lands on and the
surface that caught `textMuted` at 4.26:1 during development.

### Gradients

Deliberately almost none. **The logo's tile is flat** — its background measures
`#06AD62` → `#06AB5F` corner to corner, a ~2-unit shift that is imperceptible.
The brand does not gradient its emerald.

`primaryGradient` is **deleted**, not renamed. It was `[#34D399, #10B981,
#059669]` and it filled `AppButton`'s primary variant — i.e. every CTA in the
app — putting white label text at **1.92:1** against its top stop. It was
simultaneously the brief's "excessive gradient" violation and the single worst
accessibility defect in the codebase. Filled controls use solid `primaryAction`.

Only `premiumGradient` (two near-identical deep-emerald stops, depth not colour
shift) and `goldGradient` survive, both on premium surfaces.

## 4. The mark

The M — a bold, italic, geometric letterform.

### Why it is a construction, not a trace

The artwork is a 3D render: the M sits on a plaque rotated ≈4°, carries a long
shadow, and is under a true perspective projection. Tracing the silhouette and
un-projecting it affinely — the best any 2D un-shear can do — yields non-parallel
stems and drunk edges. It was rendered and inspected during development: it read
as a bad scan of the logo, not the logo.

So the geometry is *constructed* clean — parallel stems, one slant, real corner
rounding — from proportions **measured off the artwork**:

| Measured on the artwork              | In `MatheasyMarkPainter` |
|--------------------------------------|--------------------------|
| stem width (L 34 / R 29, of h=100)   | `_S` = 31                |
| inner V vertex depth                 | `_Vi` = 76               |
| outer V notch depth                  | `_Vd` = 42               |
| stem shear (26° screen − 4° plaque)  | `_slant` = 21°           |
| width : height (upright)             | `_W` = 104               |

That is the standard derivation of a flat UI variant from a rendered logo: the
letterform's character is preserved, its render artifacts are not.

### What the flat mark deliberately drops

The **long shadow** and the **extrusion**. They turn to mud below ~32px (the tab
bar renders at 24) and cannot recolor for dark mode. The full 3D artwork remains
the app icon, splash and launch screen, where it is shown large and unmodified.

`MatheasyMarkPainter` is the single source of geometry — `MatheasyLogo`,
`MatheasyBrandAvatar`, `MatheasyAppIcon` and `tool/generate_app_icons.dart` all
paint through it, so the splash mark and the App Store icon are the same vector.

The mark is **single-tone**. The old R8 had a `twoTone` mode (a 42%-alpha
receding stroke) which no call site outside `lib/core/brand/` ever set, and which
leaked a ghost band into Android's `<monochrome>` adaptive-icon layer. The M has
no two-tone concept and the parameter is gone.

## 5. Accessibility

- Every token pair is enforced by `test/core/theme/brand_contrast_test.dart` — 56
  assertions covering the logo anchors, the identity/action split, text on all
  four surfaces × both themes, and every container/on-container pair. Before this
  suite, **zero tests pinned any color**: a rebrand could silently regress
  contrast and nothing would fail.
- The suite also asserts that `primary` is *not* white-safe. If that test ever
  starts passing, `primary` has drifted off the logo.
- Dynamic text composes with the OS scaler; it must never replace it.
- Dark mode is a first-class theme, not an inversion.
