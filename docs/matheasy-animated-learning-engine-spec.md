# Matheasy — Universal Animated Learning Engine (AS-BUILT)

> Status: **v1 built + wired + adversarially reviewed + verified** (flutter analyze
> clean, full Dart suite green at 812 tests, functions tsc clean; a 5-dimension
> adversarial review found 9 real defects — all fixed, incl. a golden-rule
> fraction-sign leak). Additive over the Stage-14 Visual Learning Engine — nothing
> shipped was regressed. User-visible after a client app-store release.

The Animated Learning Engine makes students **watch** mathematics transform:
numbers, operators and terms **move, fade, merge and split** across the equals
sign under a named learning timeline and a universal control bar. It is the same
engine for every topic — arithmetic through calculus — with per-topic visual
objects layered on top.

## §0 The one non-negotiable — the golden rule

**The engine never computes or invents a displayed value.** It is a *rendering*
layer over the already-verified solve payload:

- The deterministic solver (`functions/src/solver`) computes every answer and
  every intermediate step and **verifies it by back-substitution** (spec §1 of
  the scanner spec). The client receives this as `ResultData` (`steps[].resultLatex`
  are the engine-frozen, verified expression states).
- The engine builds its walkthrough from **those frozen strings**. The symbol
  morph only *re-positions tokens that already exist* in the verified before/after
  LaTeX — the `15` in `20 - 5 → 15` is read from the verified `afterLatex`, never
  arithmetic'd on device.
- Every scene builder mirrors `GeometryScene.tryBuild`: it only *positions*
  verified values and returns **null** on any inconsistency, so the player shows
  the morph alone rather than a made-up picture.
- Low-confidence diffs degrade to a whole-expression **crossfade** (today's Tier-1
  behaviour). The engine never blocks and never misleads.

Enforced by tests: `test/animation/animation_script_builder_test.dart` asserts
every beat's `afterLatex` is one of the verified states.

## §1 Architecture (layers)

```
AnimatedLearningEngine   AnimationScriptBuilder.build(ResultData)  — application/animation/
        ↓                     · consumes methods/steps + journey + graph
AnimationScript          ordered AnimationStep[] + LearningPhase + AnimationPrimitive
        ↓                     + StepMorph (token-diff) + SceneObject   — domain/animation/
AnimatedLearningPlayer   the shared shell: scene · morph · timeline · control bar · haptics
        ↓                     — presentation/widgets/visual/engine/
AnimationRenderer        dispatch on SceneObject.kind → the visual-object view
        ↓
Primitive renderers      EquationMorphView (token-fragment) · scene painters (balance/curve/…)
        ↓
Math widgets / Canvas    MathText · flutter_math_fork · CustomPainter
```

## §2 Data model (domain/animation)

- **`AnimationScript`** — `categoryLabel`, `answerLatex`, `intro`, `List<AnimationStep>`,
  `SceneObject scene`, `keyIdeas`, `methodName`, `phases` (derived).
- **`AnimationStep`** — `title`, `LearningPhase phase`, `AnimationPrimitive primitive`,
  `beforeLatex`/`afterLatex`, `StepMorph morph`, `explanation`, `operationLabel?`,
  `hint?`, `isAnswer`.
- **`LearningPhase`** — `understand · chooseMethod · apply · simplify · verify · answer`
  (icon + label; mapped from the backend `JourneyStageId`, `takeaway → answer`).
- **`AnimationPrimitive`** — ~30 named animations (`moveTermAcrossEquals`, `mergeTerms`,
  `splitExpression`, `balanceScale`, `pieChart`, `derivativeAnimation`, `integralArea`,
  `matrixTransform`, `vectorMovement`, `success`, …). **Total, non-throwing** parse
  (unknown → `equationMorph`) so a future primitive can't crash an old client.
- **`EqToken`** — a signed TERM or the RELATION symbol; `id`, `latex`, `side`,
  `sign`, `key` (sign-independent match key).
- **`StepMorph` / `MorphOp`** — the token-diff: per-token `keep / move / enter / exit /
  merge`, plus `confident`, `crossedRelation`, `merged`, `split`.
- **`SceneObject` / `SceneObjectKind`** — the loose visual-object spec (kind + params +
  labels + points); unknown kind → `none` (morph only).
- **`PlaybackSpeed`** — `0.5× · 1× · 1.5× · 2×` (a duration scale).

## §3 The engine (application/animation)

- **`EquationTokenizer`** — pragmatic delimiter-free-LaTeX → `EqToken[]`: split on the
  top-level relation, then top-level `+`/`-`, respecting brace/paren/bracket depth
  (a `\frac{a-b}{c}` or `x^{-2}` is never torn). Never throws; a degenerate parse
  collapses to a single token (→ crossfade). Cap 24 terms.
- **`EquationDiff`** — aligns before/after tokens by key (prefer same side): a `+5`
  on the left pairing with `-5` on the right is a *move* (`crossedRelation`);
  `20,-5 → 15` is a *merge*. Confidence = ≥50% of after-terms traceable and ≤12
  terms/side, else the view crossfades.
- **`AnimationScriptBuilder`** — `build(ResultData)` (result path, strongest golden-rule
  source) and `fromVisual(VisualSolution)` (practice path, answer-anchored LLM steps).
  Prepends an *Understand* beat, morphs each verified step, appends a *Verify* beat
  (the solver's `verifyText`), maps phases, and attaches a scene.
- **`SceneBuilders`** — `balanceScale` (equation sides as chips), `graph`
  (server-sampled curve/parabola + roots/vertex), `fractionBar` (answer fraction).
  All null-on-mismatch.

## §4 The player (presentation/widgets/visual/engine)

- **`AnimatedLearningPlayer`** — generalized from `GeometryVisualPlayer`: per-beat
  entrance controller, autoplay `Timer` (paced by speed), scene panel + morph card +
  step strip + timeline + control bar, `MathCelebration` on the answer beat, step-aware
  `Semantics`, full reduced-motion discipline (snap to rest, no autoplay, no
  celebration, disposes its Timer + controller).
- **`EquationMorphView`** — the token-fragment morph: measures each fragment (offstage
  `GlobalKey` pass), lays out the before and after rows in a shared centred space, then
  as `progress` runs 0→1 slides persistent terms, flashes amber on a cross-relation
  move, pops in merged/entered values (emerald), fades exits. Falls back to a
  whole-expression crossfade when the diff is unconfident, un-measured, overflowing, or
  reduced-motion.
- **`UniversalControlBar`** — Prev · Play/Pause · scrubbable progress · **speed selector
  (0.5×–2×)** · Next/Replay. 44dp targets; Play/Pause + speed hide under reduced motion.
- **`LearningTimeline`** — the named phase rail (Understand→…→Answer); completed phases
  check off, the current glows. Localized labels.
- **`AnimationRenderer` (`AnimatedLearningSceneView`)** — dispatches `SceneObject.kind`
  to a view; unmapped kinds render nothing (morph stands alone).
- **Scene views** — `BalanceScaleView` (level beam = equality), `CurveSceneView`
  (parabola/curve reveal + roots/vertex), `FractionBarSceneView`, `PieSceneView`,
  `BarChartSceneView`, `NumberLineSceneView`. `EnginePalette` carries theme colours in
  (painters can't read context), immutable for cheap `shouldRepaint`.

## §5 Motion design system

- All durations/curves from `AppDurations`/`AppCurves` (added `morph`=950ms,
  `celebrate`=1800ms). Speed multiplies the step/morph/autoplay duration.
- Haptics centralized in `HapticsService` (`step` / `merge` / `celebrate`) — fired on
  beat advance, never inline.
- Emphasis honours the brand split: emerald `primaryDark`/`primaryLight` for identity,
  amber `warning` for the moving term. Particles are low-alpha, reduced-motion aware,
  and never sit behind white label text.
- Reduced motion (`MediaQuery.disableAnimationsOf`) has parity everywhere.

## §6 Wiring (additive)

- **Result tab** (`visual_tab.dart`): dispatch is `geometryScene → AnimatedLearningPlayer
  (non-empty script) → Tier1/2/3`. Pro gating, `keepAlive` caching, analytics, and the
  permission-denied→paywall path are untouched.
- **Practice** (`practice_visual_screen.dart`): routes through the same player via
  `fromVisual`, falling back to the tiers — fixing the prior geometry/timeline divergence.
- l10n: engine chrome keys added to `app_en.arb` (`engine*`), regenerated. Other locales
  fall back to English until translated (see follow-ups).

## §7 Performance

- One `AnimatedBuilder` per animated surface inside a `RepaintBoundary`; painters gate on
  `shouldRepaint`. `EquationMorphView` measures fragments once per beat (cached), and the
  offstage pass only exists while un-measured. Script build is O(steps) tokenization,
  memo-free but cheap; the `keepAlive` controller means no re-bill / rebuild storm on tab
  switch.

## §8 Coverage & tests

- `test/animation/equation_diff_test.dart` — tokenizer + diff (moves, merges, confidence,
  never-throws).
- `test/animation/animation_script_builder_test.dart` — phased script, primitive selection,
  the golden-rule trace assertion, empty-script fallback.
- `test/animation/animated_learning_player_test.dart` — renders morph/timeline/controls,
  reduced-motion hides play+speed, speed cycles, Next advances.
- `test/visual_learning_test.dart` — updated: solved problems play the engine; the tier
  path is exercised via a step-less result (now the fallback).

## §9 Roadmap (follow-ups, each additive)

1. Deepen category scenes: quadratics **area model** + completing-the-square; calculus
   **tangent sweep** + **Riemann rectangles** (from `graph.curve`); trig **unit circle**;
   matrices/vectors; probability **tree**/**spinner**. (Enum values + renderer slots exist;
   they fall back to morph-only until painted.)
2. Per-step balance-scale state (chips update as terms move) and area/factor morphs.
3. ~~Translate the `engine*` l10n keys~~ — DONE (all 8 locales at parity).
4. Optional: an `enrichAnimation`-style callable if a category ever needs LLM-chosen
   animation metadata — it must pass the `extractNumbers` firewall (mirror
   `validateTeaching`).
