# Matheasy — Geometry Practice with Figures (staged build spec)

> **For Claude Code.** Feature: a solved geometry problem generates GEOMETRY
> practice (not algebra), and those questions carry textbook-style LABELLED
> figures. Built in 4 stages + 1 hardening step, in dependency order. Each stage
> is independently reviewable and shippable. Grounded in the 5-part audit — file
> paths and traps below come from the real code.
>
> **The golden rule applies to figures exactly as to answers:** a figure is drawn
> from the rule-generator's OWN verified numbers, never LLM-invented. A triangle
> labelled 86°/37° must actually BE 86°/37° — correct by construction, because the
> same template that generates the numbers generates the figure.

---

## Stack facts (from audit — don't re-derive)

- `classify.ts` classifies structurally over LaTeX and is **geometry-blind** — a
  geometry problem (`A = ½·6·4`) looks identical to a linear equation. Geometry
  CANNOT be detected at solve time.
- The ONLY geometry signal is the **Vision recognizer topic** (`scan.ts:48` prompts
  for topic ∈ {…, geometry, …}), currently **thrown away** at
  `functions_scanner_service.dart:83`.
- `ConceptPainter` (`concept_painter.dart:41`) is a **pure painter**, decoupled from
  the backend — takes an in-memory `VisualConcept` + `ConceptPalette`. Can be driven
  on-device with NO backend round-trip.
- `PracticeQuestion` is **never serialized** (no toJson/fromJson) — adding a figure
  field needs zero migration.
- Geometry skills are **hard-locked to `GenerationTier.ruleBased`** — they never reach
  the LLM generator, so the figure-reference risk is architecturally impossible unless
  someone manually sets a geometry skill to `GenerationTier.ai`.

---

## KNOWN LIMITATION — state it, don't fix it here

**This lights up SCANNED geometry only, not TYPED geometry.** The math-keyboard path
has no Vision topic, so a typed geometry problem stays classified as algebra and
generates algebra practice. This is a deliberate scope boundary of this feature, not
a bug. (Future fix — a topic picker on the keyboard, or a topic override on the
practice screen — is its own small feature, out of scope.) Document this in code
comments at the routing seam so it's a known gap, not a surprise.

---

## STAGE 1 — Routing (the live bug; no dependencies; ship on its own)

**Goal:** solved SCANNED geometry generates geometry practice, not algebra. This is
correct and shippable BEFORE any figure work — text-solvable geometry practice
(the existing 3 templates) becomes reachable from the Solution flow.

Edits (preserve the Vision topic; do NOT teach the solver geometry):
1. Add `geometry` to `EquationKind` (`detected_equation.dart:11`).
2. Stop collapsing geometry at `functions_scanner_service.dart:83` — the
   `case 'geometry'` currently falls into the group returning
   `EquationKind.expression`; route it to `EquationKind.geometry`.
3. Add `geometry` to `ResultType` (`result_models.dart:11`) — `.name` JSON
   round-trips automatically.
4. In `functions_solver_service._typeFor(problemType, kind)`: check
   `kind == EquationKind.geometry → ResultType.geometry` **BEFORE the problemType
   switch**. ORDER IS LOAD-BEARING — if this check comes after, a geometry problem
   parsed as an equation gets grabbed by the linear_equation/quadratic_equation arm
   first and mis-routes.

Compile-forced switch arms (the compiler will flag these — the audit named them):
- `_practiceTopicFor` (`result_screen.dart:93`): add
  `ResultType.geometry => PracticeTopic.geometry` (the target already exists).
- `MockSolverService.solve` (`solver_service.dart:34`): fold `EquationKind.geometry`
  into `_fallback`.
- (`_typeFor`'s `switch(problemType)` is over a String with a default — won't break.)

Add the KNOWN LIMITATION comment (typed geometry undetected) at the scanner-service
seam.

**Stage 1 done =** scan a geometry problem → solve → "Generate practice" produces
geometry questions (text-only, existing templates), not linear-equation practice.
Verify with a scanned geometry problem end to end. Ship it.

---

## STAGE 2 — Figure labelling in ConceptPainter (enabling capability; PARALLEL with Stage 1)

**Goal:** `ConceptPainter` can draw text ON figures (angle values, side lengths,
vertex names). No dependency on routing — can be built alongside Stage 1.

The data model ALREADY has label slots — the painter just ignores them:
`VisualConcept.labels: Map<String,String>` + `params: Map<String,double>` + `points`.
So NO model change for the data; only the painter needs to draw it.

Edits:
1. Port `result_graph.dart:239`'s `_drawLabel(canvas, size, at, text)` (TextPainter +
   `tp.paint(canvas, offset)`) into `ConceptPainter`. This is the proven on-canvas-text
   pattern — copy it, don't invent one.
2. In the geometry paint methods (`_paintGeometryShape`, `_paintUnitCircle`), draw the
   angle values / side lengths / vertex names from `labels`/`params` at computed
   positions: vertex points for names, edge midpoints for side lengths, the angle arc
   for angle values.
3. `ConceptPalette` has no text color (only grid/axis/stroke/fill/accent) — add a
   `textColor` field (or reuse `axis`). Derive from theme tokens like the others.

**Stage 2 done =** given a `VisualConcept` with populated `labels`/`params`,
`ConceptPainter` renders the figure WITH its measurements labelled. Test with a
hand-built triangle concept (angles labelled). Self-contained; no routing needed.

---

## STAGE 3 — Practice render path (needs Stage 2)

**Goal:** a practice question can carry an optional figure and render it above the
prompt. Cheap because `PracticeQuestion` is never serialized (zero migration).

Edits:
1. Define `PracticeFigure` — a small deterministic value object: shape kind + labelled
   sides/angles/vertices. No assets, no network. (Stage 4 populates it; here just the
   type + rendering.)
2. Add `final PracticeFigure? figure;` to `PracticeQuestion` (`practice_question.dart:44-48`)
   — nullable, so all ~40 existing constructions compile untouched.
3. **THE LOAD-BEARING TRAP — `withId()`.** `PracticeQuestion.withId()`
   (`practice_question.dart:84`) hand-copies every field, and every generated question
   is re-stamped via `.withId(slotId)` at `adaptive_practice_service.dart:103`. You
   MUST add `figure: figure` to the `withId()` copy — omit it and the figure is
   **silently dropped** at stamping with no error. This is the #1 way this stage breaks
   invisibly. Add it, and add a test that a figure survives `.withId()`.
4. Render as the FIRST child of the Column in `practice_question_view.dart:28`:
   `if (question.figure != null) …[FigureWidget, SizedBox]`, above the prompt. The
   `FigureWidget` wraps `ConceptPainter` (Stage 2) via a `CustomPaint`. Give it a
   `Semantics(label:)` for a11y — a screen-reader user needs the figure described.
   No change to `practice_session_screen.dart`.

**Stage 3 done =** a `PracticeQuestion` with a non-null `figure` renders the labelled
figure above the prompt, and the figure survives `.withId()` restamping. Test both.

---

## STAGE 4 — Deterministic figure generation + variety (needs Stages 1-3)

**Goal:** geometry templates emit a figure spec drawn from THEIR OWN numbers, and add
variety beyond the current 3 templates.

Figure generation (golden rule — figure from verified numbers):
- In the rule-based geometry templates (`rule_based_generator.dart`), when a template
  generates its numbers (e.g. `_triangleAngle` picks 86°, 37°), it ALSO builds a
  `PracticeFigure` from THOSE SAME numbers — the drawn triangle's angles ARE the
  generated angles. Never a second source, never an LLM. Correct by construction.
- The `FigureWidget` (Stage 3) → `ConceptPainter` (Stage 2) draws it with labels.
- Not every template needs a figure — `PracticeFigure?` is nullable. Start with the
  templates where a figure genuinely helps (triangle angles, right-triangle/Pythagoras);
  rectangle area may or may not warrant one. Use judgment: a figure that adds nothing
  (or that can't be drawn faithfully) should be omitted, not forced.

Variety (deterministic only — the engine is built for this):
- New templates = one enum entry in `PracticeSkill` (`practice_skill.dart:106`,
  `GenerationTier.ruleBased, proOnly: true`), one line in the `_templates` map
  (`rule_based_generator.dart:37`), one pure `RuleTemplate` function (copy
  `_triangleAngle`'s shape: rng params → build question + a unique signature for
  anti-repetition). Dispatch is data-driven off the map — no switches to touch.
- **CRITICAL: keep every new geometry skill `GenerationTier.ruleBased`.** Do NOT set any
  geometry skill to `GenerationTier.ai` — that's the ONLY way geometry could reach the
  LLM generator, which has no figure field and no "don't reference a diagram" guard, and
  would reintroduce broken figure-referencing questions. Deterministic templates only.
- What "richer" means concretely (decide/confirm with me before building the list):
  e.g. angles-on-a-straight-line, angles-in-a-quadrilateral, isosceles-triangle,
  circle-radius/diameter, area-of-triangle-from-base-height. All text-solvable + a
  faithful figure.

**Stage 4 done =** solved geometry generates varied geometry practice, each question
with a labelled figure drawn from its own verified numbers. Verify the figure matches
the question (labelled 86° IS 86°) on device.

---

## HARDENING (one line; cheap insurance; anytime)

Add a "do NOT reference a diagram/figure; all data must be in the text" instruction to
the LLM practice prompt (`practice.ts:48-68`). Geometry can't reach this path today, but
the guard means IF a geometry skill is ever mis-declared `GenerationTier.ai`, the LLM
still won't emit figure-referencing broken questions. One line, protects the invariant
the whole feature relies on.

---

## Build order recap

1. **Stage 1 (routing)** + **Stage 2 (labelling)** in parallel — neither depends on the
   other. Stage 1 ships text-only geometry practice; Stage 2 is the drawing capability.
2. **Stage 3 (render path)** — needs Stage 2.
3. **Stage 4 (figure generation + variety)** — needs 1, 2, 3.
4. **Hardening** — anytime.

Each stage: report which files you'll touch, flag any spec-vs-code drift (the audit is
recent but confirm), and STOP after each for review. Same discipline as the scanner build.

## Reminder to Claude Code
- Figures drawn from verified template numbers, NEVER LLM-invented.
- Scanned geometry only — typed geometry is a stated limitation, not a bug.
- The two silent-failure traps: `_typeFor` ordering (Stage 1), `withId()` figure-drop
  (Stage 3). Both have no error if you get them wrong — the tests are the safety net.
- Keep geometry `ruleBased`. Never `GenerationTier.ai`.
