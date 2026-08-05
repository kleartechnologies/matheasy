# Matheasy — Scanner Optimisation Report (after)

> The "after" half of the scanner speed work. The "before" is
> [`matheasy-scanner-performance-audit.md`](matheasy-scanner-performance-audit.md),
> which is a **baseline and stays one** — it is not edited to match this, because
> a baseline you revise is not a baseline.

---

## 0. What this report can and cannot claim

Three kinds of claim appear below, and they are **not** interchangeable:

- **Structural** — read straight off the shipped code: how many round trips
  there are, what runs concurrently, whether a human tap sits on the critical
  path, how many bytes go up. These are facts, and they are where the real
  result of this work lives.
- **Estimated** `(est.)` — wall-clock ranges. Every one is an engineering
  estimate. The baseline's numbers were estimates too, so the before/after
  columns are at least commensurable — but a range compared against a range is
  an argument, not a measurement.
- **Verified** — passed a test or a build in this repo. Listed in §7.

**No device capture was run for this report.** The instrumentation to produce
one shipped in Phase 1 and is still in place; §8 is the exact procedure. Until
someone runs it, treat every `(est.)` here the way the baseline asked its own
estimates to be treated: as a hypothesis with a test attached.

The one number nobody has to estimate: **the crop screen used to sit between the
shutter and the first byte leaving the phone, and now it does not.** That is
structural, it is the largest single item, and it does not depend on a stopwatch.

---

## 1. Headline

| | Before | After |
|---|---|---|
| Human steps between shutter and answer | **2** (crop, then Solve) | **1** (Solve) |
| Human steps that block the upload | **1** (crop) | **0** |
| Sequential server stages in `recognizeEquation` | 4 | 3 (moderation ∥ preprocessing) |
| Solve starts | on the "Solve" tap | at recognition |
| Feedback before capture | none | live box, **<100 ms**, continuous |
| base64 of a ~900 KB JPEG | UI isolate | worker isolate |
| Bytes uploaded | whole frame | detected region + 4 % padding |
| Gallery Dart re-encodes | up to **2** | **0–1** |
| Camera enumeration | every scanner open | once per launch, pre-warmed at boot |
| Wait screens with no content | 2 | 0 |

**Nothing about recognition or solving accuracy changed.** No prompt, no model,
no effort tier, no verification gate. The two passes still run, the substitution
gate still decides, and an unverifiable answer still comes back as an honest
`verified:false`. Every item above is scheduling, framing, or feedback.

---

## 2. What shipped

### Phase 1 — Audit ✅
[`perf_trace.dart`](../lib/core/monitoring/perf_trace.dart) (span recorder →
`dart:developer` Timeline + a waterfall log),
[`scan_trace.dart`](../lib/features/scan/application/scan_trace.dart) (shared
across the four owners a scan crosses), and one structured
`recognizeEquation.timings` line per server call. Still shipped, still the way to
replace the estimates below.

### Phase 2 — Live detection ✅
[`region_detector.dart`](../lib/features/scan/application/region_detector.dart)
feeds preview frames to ML Kit; [`detection_overlay.dart`](../lib/features/scan/presentation/widgets/detection_overlay.dart)
draws the result. `120 ms` floor between reads — not a latency throttle (ML Kit
reads a preview frame in roughly 30–80 ms) but a ceiling on how much CPU and
battery a viewfinder hint may take. Frames arriving mid-detection are **dropped,
not queued**: a queue makes the box lag further behind the phone the longer it is
held up.

The preview stream moved to `nv21`/`bgra8888` — the two formats ML Kit accepts —
so no frame is JPEG-decoded to be looked at. `takePicture()` still returns JPEG.

### Phase 3 — Smart cropping ✅
[`cropScanJpeg`](../lib/features/scan/application/scan_image_codec.dart) cuts the
still to `cropRectFor(region)`: the union of the maths-scoring text blocks, 4 %
padding (10 % when a figure is detected beside the text, so a diagram is never
severed from the problem that references it), floor of 25 % of each edge, longest
edge capped at 1600 px.

Orientation is **baked before cropping**. The rectangle arrives in display space
— what the detector and the user's eyes both see — while a phone stores its
picture in sensor order plus an EXIF flag. Cropping unbaked pixels with a
display-space rectangle cuts a sideways slice of margin out of the page.

Every failure path returns the original bytes: undecodable image, degenerate
rectangle, sub-32 px result, or any throw. A scan that uploads the whole page
still gets solved; a scan that failed here would be a photo the user has to take
again.

### Phase 4 — On-device vision, **detection only** ✅ *(as decided)*
On-device vision locates; **OpenAI Vision remains the only transcriber.** The
audit's §6 argument stands: ML Kit and Apple Vision are line-text recognisers
with no model of two-dimensional notation — a fraction returns as two lines,
`x^2` as `x2`, `√`/`∫`/`Σ` dropped. And because the verify gate substitutes back
into the problem *as transcribed*, a misread problem verifies perfectly. Letting
a line-text reader transcribe would have produced confidently wrong answers,
which is the exact failure the golden rule exists to prevent.

[`math_text_scorer.dart`](../lib/features/scan/domain/math_text_scorer.dart)
scores blocks by character class (relational marks weigh heaviest — prose almost
never contains a bare `=`) purely to decide *what to frame*.
[`DetectedRegion`](../lib/features/scan/domain/detected_region.dart) carries no
field that could be mistaken for a reading.

### Phase 5 — Immediate feedback ✅ *(re-scoped, see §5)*
The live box gives instant, continuous, pre-capture feedback. The **detected
equation** still appears only after the server round trip, because that is the
only place a trustworthy transcription exists.

### Phase 6 — Background solving ✅
[`preemptive_solve.dart`](../lib/features/result/application/preemptive_solve.dart):
the solve starts when recognition lands, not when the user taps Solve. By the
time they finish reading the card it is often already done.

Three properties that make this safe rather than merely fast:
- **It spends nothing new.** `countAsScan` is true only for manual input, so a
  camera/gallery solve was already free — recognition charged the scan. Manual
  problems are explicitly excluded from the head start.
- **It is keyed by equation.** Correcting a misread starts a new solve; the stale
  one cannot answer for the corrected problem.
- **Claiming consumes.** A retry after a failure starts a genuinely new solve
  rather than re-awaiting the same broken future.

### Phase 7 — Perceived performance ✅
Haptic on the shutter, fired before any work starts — the only genuinely instant
part of a capture. [`SolvingState`](../lib/features/result/presentation/widgets/solving_state.dart)
replaces the blank result-screen spinner: it keeps the typeset problem on screen
and names the stage. `ProcessingOverlay`'s stages were English string literals
and are now localised — live detection made that overlay short enough to notice,
and a Spanish-speaking student waiting on an English "Almost there…" is a bug in
32 languages.

The stage lines are on a timer, not on real callbacks — the solve is one server
round trip and the phone cannot see inside it — so they are worded as
descriptions of the **work**, never as claims about the **answer**. None of them
says anything a student could be misled by when the solve ends in an honest
"couldn't verify".

### Phase 8 — Parallel execution ✅
- **Server:** `moderateImage` ∥ `prepareScanImage`. This does not weaken the
  COPPA gate: what the gate must guarantee is that no flagged image reaches a
  *paid* call, and both paid passes still wait on the verdict. Preprocessing is
  local `sharp` CPU that sends nothing anywhere and is discarded unread on a
  flag. The in-flight render is settled on the flag path so it cannot surface as
  an unhandled rejection.
- **Client:** ML Kit's block read ∥ the still's decode-for-size. Neither reads
  the other's output; on a 12 MP still, sequencing them doubled the step for
  nothing. `readBlocks` returns unnormalised blocks precisely so the caller can
  fold in the size afterwards — normalising inside the detector would have put
  the decode back on the critical path.

### Phase 9 — Caching ✅
[`camera_warmup.dart`](../lib/features/scan/application/camera_warmup.dart):
enumeration once per launch, pre-warmed post-first-frame from `bootstrap.dart`.
It only asks the OS what hardware exists — no session, no permission prompt, no
camera indicator. **Failures are not cached**, and neither is an empty list ("a
failure wearing a success's clothes"): remembering a transient failure forever
would turn one bad moment into a scanner that stays broken until the app is
killed.

The two caches that mattered most already existed and were left alone: the local
read-through history cache and the server-side solve cache.

### Phases 10–12
§4 (targets), §7 (regressions), §6 (validation) below.

### Declined, and left undone
- **`minInstances: 1`** — a standing bill. Cold starts (audit #5, 1–3 s est.)
  remain.
- **Two-pass recognition investigation** — the split exists for a real
  correctness reason and must not be touched on a hunch. Bottleneck #1 remains,
  intact and dominant.

---

## 3. Previous vs new timings

Camera scan, warm function, printed equation, good light. **Both columns are
estimates**; the before column is the audit's §5, unchanged.

| Stage | Before (est.) | After (est.) | Why |
|---|---|---|---|
| Camera open → first frame | 300–900 ms | 250–800 ms | enumeration pre-warmed; the sensor spin-up is unchanged and dominates |
| Aim | human | human, **now guided** | live box, <100 ms |
| `stopImageStream` | — | **+10–50 ms** | new; the stream and the shutter cannot both run |
| `takePicture` + `readAsBytes` | 200–600 ms | 200–600 ms | unchanged |
| **Crop screen (human)** | **3 000–10 000 ms** | **0 ms** | removed from the default path |
| Region detect on the still | — | **+150–400 ms** | new; runs ∥ the decode |
| Crop execute | 50 ms native (+0–1 200 ms conditional re-encode) | **400–1 200 ms** | ⚠️ **regression** — see §5 |
| base64 + upload | 300–1 000 ms, UI jank | 150–600 ms, **no jank** | off-thread; tighter crop = fewer bytes |
| **`recognizeEquation`** | **8 000–25 000 ms** | **7 000–24 000 ms** | moderation ∥ prep; smaller images |
| Read the card, tap Solve | 1 000–4 000 ms | 1 000–4 000 ms human — **but the solve is running through it** | |
| `solveEquation` (observed) | 2 000–20 000 ms | **0–18 000 ms** | starts ~2–4 s earlier; a fast solve is finished before the tap |
| **Shutter → answer** | **~15–60 s** | **~9–35 s** | |
| **Time to first feedback** | crop screen (a blank framing UI) | **<100 ms**, live, before the shutter | |

The saving is roughly **40 %** of the estimated envelope, and about two-thirds of
it is the crop screen. That is not a coincidence — it was the largest item in the
baseline and it was human time, which no amount of server tuning could reach.

---

## 4. Phase 10 targets — scorecard

| Target | Status | Note |
|---|---|---|
| Camera open <300 ms | ⚠️ borderline | enumeration now free; `initialize()` at `veryHigh` is the remainder and is hardware-bound |
| Live detection <100 ms | ✅ | ML Kit 30–80 ms/frame, 120 ms cadence |
| Capture <100 ms | ❌ | `takePicture` + a temp-file round trip is 200–600 ms; the file hop is the plugin's API, not ours |
| Crop <50 ms | ❌ | 400–1 200 ms — see §5 |
| OCR 300–600 ms | ❌ **by design** | on-device OCR was rejected on correctness grounds; the transcriber is a reasoning-model vision pass |
| Detected equation <800 ms | ❌ **by design** | same reason. What *is* <100 ms is the live box — the equation is *located* instantly and *read* accurately |
| Final answer 2–4 s | ⚠️ | reachable for a cached or deterministic solve; not for the LLM-candidate-plus-retry path, which is three more reasoning calls |

Four of these were unreachable the moment the correctness constraint was chosen
over the speed constraint — which is the right call and the one the brief itself
asked for in Phase 11. They are recorded as misses rather than redefined as hits.

---

## 5. Remaining bottlenecks

**#1 — Two sequential reasoning vision passes.** Unchanged and still dominant:
7–24 s (est.) of a 9–35 s scan. Not touched, by decision.

**#2 — The auto-crop is a full Dart decode/encode cycle. ⚠️ New.** It replaced a
~50 ms native crop with `decodeImage` → `bakeOrientation` → `copyCrop` →
`copyResize` → `encodeJpg` on a 12 MP still — 400–1 200 ms (est.) in a worker
isolate. Net still strongly positive (it removed 3–10 s of human time), and it is
off the UI thread so it costs no frames, but it is honestly a machine-time
regression and it is the cheapest remaining win.

**#3 — Cold starts.** 1–3 s (est.) for the first user after a quiet spell.
Declined, not solved.

**#4 — `takePicture` writes a file the app immediately reads back.** A plugin API
shape, not a bug, but it is real I/O on the critical path.

**#5 — The "Solve" tap still exists.** It is now overlapped rather than
blocking, so it costs nothing when the solve is slower than the reading — but a
cached solve finishes in ~100 ms and then waits on a human for seconds.

**#6 — `_adjustCrop` re-recognises from scratch.** Correct (the framing changed,
so the read must change) but it is a second full round trip. It is a button, not
the default, which is why this is acceptable.

---

## 6. Validation (Phase 12) — what was and was not done

**Done, and green:**

| Gate | Result |
|---|---|
| `flutter analyze` | clean |
| `flutter test` | **1232 passed** |
| `npm run build` (functions) | clean |
| `npx vitest run` (functions) | **1720 passed, 190 skipped** |

New coverage: [`scan_detection_test.dart`](../test/scan_detection_test.dart)
(scoring, region union, cover-fit projection, crop rectangle),
[`preemptive_solve_test.dart`](../test/preemptive_solve_test.dart) (8 tests —
including the monetisation guard, corrected-problem isolation, consume-once, and
that a failing head start cannot escape as an unhandled async error),
[`test/core/monitoring/`](../test/core/monitoring/) (the trace recorder).

**Not done — needs a physical device and is the honest gap in this report:**

- the Phase 12 input matrix (printed, handwriting, fractions, integrals,
  derivatives, matrices, graphs, geometry, word problems, low light, blur,
  perspective) against the **detector**, which is the only new thing in the read
  path. What matters per case is not the transcription (unchanged) but whether
  the auto-crop frames the whole problem. **A crop that severs a sub-part is now
  the highest-risk failure mode this work introduced** — the `hasDiagram` widening
  and the 25 % floor exist to blunt it, but they are heuristics with no field data.
- the device capture that would replace every `(est.)` above.
- a Photomath side-by-side.

---

## 7. Phase 11 — no-regression audit

| Must not regress | Status |
|---|---|
| OCR accuracy | ✅ untouched — same model, prompts, effort, two passes, both image views |
| Solver correctness | ✅ untouched — same deterministic engines, same substitution gate |
| Geometry support | ✅ the `geometry` payload is unchanged; `hasDiagram` **widens** the crop so a figure is not severed |
| Verification | ✅ untouched |
| Accessibility | ✅ the overlay is decorative and non-interactive; `SolvingState` is text, not a bare spinner |
| Localization | ✅ **improved** — 13 keys added and 1 dead key removed across all 33 ARBs (666 keys each, parity verified); two English-only leaks closed (`ProcessingOverlay`'s stages, `EquationKind.label`) |
| Existing tests | ✅ 1232 + 1720 green |
| Routing / monetization | ✅ GoRouter untouched; the paywall checkpoint still sits on the same tap; the head start is excluded for manual input precisely so it cannot spend a scan the user has not asked to spend |

One deliberate behaviour change: **the crop screen is no longer mandatory.** It
is one tap away on the confirmation card, and it re-opens on the *original*
photo, not the auto-cropped slice — cropping a crop would make the escape hatch
narrower every time it was used.

One deliberate deletion: `EquationKind.label` was **removed**, not widened. It
held an English display string, which meant every non-English user saw
"Quadratic equation" under a problem the rest of the screen described in their
own language. The label now lives in the ARBs behind `EquationKindL10n.labelOf`,
in the presentation layer — the enum is domain, it is serialised into history and
compared for equality, and giving it a `BuildContext` would drag localization
into a type that has no screen.

---

## 8. Recommendations, in order of value per unit of risk

1. **Capture the real numbers.** Everything above is an estimate over an
   estimate. `flutter run --profile`, scan a printed equation, a handwritten one
   and a gallery pick; the waterfall prints under `matheasy.perf`. Server side,
   filter Cloud Logging on `jsonPayload.message="recognizeEquation.timings"`.
   Nothing else on this list should be started first.
2. **Run the Phase 12 matrix against the auto-crop** (§6). One bad crop is a
   worse user outcome than any latency on this page.
3. **Make the crop cheap** (remaining #2, 400–1 200 ms). Cheapest option: lower
   the still to `ResolutionPreset.high` — the upload is downscaled to 1600 px
   anyway, so most of a 12 MP capture is decoded and resized only to be thrown
   away. Better but larger: crop natively rather than in the Dart `image`
   package.
4. **Skip the temp file** (remaining #4) if the camera plugin ever exposes bytes
   directly.
5. **Auto-advance a cached solve** (remaining #5) — when the answer is already in
   hand as the card renders, the "Solve" tap is a toll on nothing. Needs care:
   the tap is also the paywall checkpoint.
6. **Reconsider `minInstances: 1`** with real cold-start data from step 1. It was
   declined on cost with no numbers; the numbers may change the answer.
7. **Then, and only then, revisit the two-pass recognition** (bottleneck #1 —
   the largest remaining item by far). The audit's condition still binds: measure
   how often the OCR pass and the vision pass actually *disagree* before
   proposing a confidence-gated single pass. If they agree on clean printed
   input, that is worth 5–12 s (est.) on the most common scan of all. If the
   disagreement data does not exist, this stays untouched.

---

## 9. The honest summary

The scanner is meaningfully faster, and the reason is not tuning — it is that a
human step was taken off the critical path and a machine step was moved earlier
than the tap that used to gate it. The single largest cost in the pipeline, two
sequential reasoning-model vision passes, was deliberately not touched, because
the only ways to shrink it either cost money (declined) or trade away the
correctness the golden rule exists to protect.

Against Photomath, Matheasy now *feels* comparable up to the point of capture —
live box, no crop screen, instant haptic, never a blank wait — and remains
slower to the answer, by roughly the two vision passes. That gap buys the thing
Photomath does not do: an answer that has been substituted back into the problem
before it is shown to a student.
