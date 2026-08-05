# Matheasy — Scanner Performance Audit (Phase 1, pre-optimisation)

> **The "after" is [`matheasy-scanner-performance-report.md`](matheasy-scanner-performance-report.md).**
> This document is deliberately left as it was written: a baseline you revise is
> not a baseline. Where the report disagrees with it, the report is newer.
>
> **Status: baseline.** This is the "before" record for the scanner speed work.
> It documents the shipped pipeline as of `geometry-visual-learning`, names the
> bottlenecks in rank order, and describes the instrumentation added to produce
> real device numbers. Nothing in the pipeline was optimised to write it — the
> only code change is measurement, so the numbers this produces are a true
> baseline.

---

## 0. What is measured, and what is inferred

Two kinds of claim appear below and they are **not** interchangeable:

- **Structural** — read directly off the code: how many network round trips
  there are, what runs sequentially, where a human tap sits on the critical
  path. These are facts and are marked as such.
- **Estimated** — wall-clock ranges for stages that need a real device and a
  real network to measure. These are **engineering estimates, not
  measurements**, and every one is labelled `(est.)`.

The instrumentation added in this phase exists precisely so the `(est.)` column
can be replaced with measurements. **No optimisation should be judged against
the estimates** — run the app, capture a trace, and judge against that.

---

## 1. The pipeline, as built

```
ScannerScreen.initState
  └─ availableCameras()                     platform channel
  └─ CameraController(ResolutionPreset.veryHigh).initialize()
  └─ setFlashMode()
        ↓                                   [user aims the phone]
  shutter (tap, or steadiness auto-capture)
  └─ camera.takePicture()                   → writes a temp FILE
  └─ file.readAsBytes()                     → reads it back
        ↓
  ── CropScreen pushed (a full-screen route) ─────────── HUMAN STEP
  └─ user drags handles, taps "Use photo"
  └─ CropController.crop()                  native crop
  └─ compute(encodeScanJpeg)                Dart `image` isolate — CONDITIONAL
        ↓
  ScannerController.recognize()
  └─ base64Encode(bytes)                    ON THE UI ISOLATE
  └─ callFunction('recognizeEquation')      ── network ──▶
        │
        │   ┌── Cloud Function (no minInstances → cold starts) ──┐
        │   │  ensureUserDoc / rateLimit / quota   Firestore ×3   │
        │   │  moderateImage()                     OpenAI  #1     │
        │   │  prepareScanImage()                  sharp, ≤8s cap │
        │   │  readPage()          OCR pass        OpenAI  #2  ◀── reasoning, 2 images
        │   │  chatVisionJson()    vision pass     OpenAI  #3  ◀── reasoning, 2 images
        │   │  deriveSemanticAnchors()             deterministic  │
        │   │  incrementUsage()                    Firestore      │
        │   └──────────────── STRICTLY SEQUENTIAL ────────────────┘
        ↓
  ScanCaptured → _CapturedView (the detected-equation card)
        ↓                                   [user reads it, taps "Solve"] ── HUMAN STEP
  ScanComplete → pushReplacement(scanResult)
        ↓
  ResultController.build
  └─ history cache lookup                   local, can short-circuit everything
  └─ callFunction('solveEquation')          ── network ──▶
        │   rateLimit / quota               Firestore
        │   solve cache                     Firestore
        │   classify → mathsteps/mathjs     deterministic
        │   VERIFY GATE
        │   [if unsupported] LLM candidate  OpenAI #4  (effort: high)
        │   [if gate rejects] retry         OpenAI #5  (effort: max)
        │   narration                       OpenAI #6
        ↓
  answer rendered
  └─ _attachTeaching()                      OFF the critical path ✓ (correct)
```

### The structural headline

**Between the shutter and the answer there are up to six sequential LLM round
trips, four of them on the reasoning tier, split across two Cloud Function calls
that are separated by a mandatory human tap.**

---

## 2. Bottlenecks, in rank order

### #1 — `recognizeEquation` runs two reasoning-model vision passes back to back

**Structural.** `functions/src/proxy/scan.ts` makes three sequential OpenAI calls
before it returns anything:

| Stage | Model | Effort | Budget | Images sent |
|---|---|---|---|---|
| `moderateImage` | `omni-moderation-latest` | — | — | 1 |
| `readPage` (OCR) | `gpt-5.6-sol` | `medium` | 2 600 + 6 000 headroom | 2 |
| `chatVisionJson` (scan) | `gpt-5.6-sol` | `high` | 1 200 + 12 000 headroom | 2 |

Two reasoning-model vision calls at `medium` and `high` effort, one after the
other, is **8–25 s (est.)** and dominates everything else combined. The function's
own `timeoutSeconds: 180` is the strongest evidence that this was expected to be
slow.

The split is **not** gratuitous — the file argues convincingly that a single pass
which reads and interprets at once normalises `f'(x)` into `f(x)`, and that is a
correctness argument I would not overrule. But note the cost is paid on *every*
scan, including a crisp printed textbook line where the OCR pass and the vision
pass will agree exactly.

Also structural: **four image payloads reach OpenAI per scan** (original +
enhanced, to each of two passes) from one image the phone uploaded.

### #2 — The crop screen is a mandatory human step on the critical path

**Structural.** [`scanner_screen.dart:398`](../lib/features/scan/presentation/scanner_screen.dart#L398)
pushes `CropScreen` after every capture and awaits it. The user must drag corner
handles and tap "Use photo" before a single byte leaves the phone.

This is **3–10 s (est.)** of pure human latency, it is unbounded, and it is the
single biggest difference in *felt* speed versus Photomath, which crops
automatically and shows the user nothing. It also blocks any pipelining: nothing
can be uploaded speculatively while the user fiddles with the handles.

### #3 — The "Solve" tap serialises recognition and solving

**Structural.** After recognition, `_CapturedView` shows the detected equation
and waits for a tap ([`scanner_controller.dart` `confirm()`](../lib/features/scan/application/scanner_controller.dart#L116)).
`solveEquation` only starts *after* it. So the solve — itself up to three more
LLM round trips — begins from a cold start at the exact moment the user is most
convinced the app is finished.

The recognition result is known and stable at that point. There is no
correctness reason the solve cannot be in flight while the user reads the card.

### #4 — Moderation, preprocessing and OCR are sequential but not dependent

**Structural.** `moderateImage` and `prepareScanImage` both take only the
original image and neither reads the other's output, yet they run one after the
other, and both complete before `readPage` starts. Roughly **0.5–1.4 s (est.)**
sits on the critical path that does not have to.

(`readPage` genuinely does depend on `prepareScanImage`, and `chatVisionJson`
genuinely does depend on `readPage`. Those two orderings are real.)

### #5 — No `minInstances`: every idle-period scan pays a cold start

**Structural.** `functions/src/config.ts:199` sets `region` and
`maxInstances: 10` but no `minInstances`. `recognizeEquation` requests
`memory: "1GiB"` and pulls in `sharp` and the OpenAI SDK — a heavy cold start,
**1–3 s (est.)**, paid by the unlucky first user after any quiet spell. For a
consumer app with bursty after-school traffic, that is a large share of sessions.

### #6 — `base64Encode` runs on the UI isolate, and inflates the upload by a third

**Structural.** [`functions_scanner_service.dart:44`](../lib/features/scan/application/functions_scanner_service.dart#L44)
calls `base64Encode(imageBytes)` synchronously on the main isolate. For a ~900 KB
JPEG that is a ~1.2 MB string built in one go on the thread that draws frames —
visible jank at the exact moment the user is watching for a response, plus 33 %
more bytes on the wire than the image itself.

### #7 — The Dart `image` package re-encode, sometimes paid twice

**Structural.** `encodeScanJpeg` does `decodeImage` → `copyResize` → `encodeJpg`
in pure Dart — **400–1200 ms (est.)** for a 1080p frame even inside `compute`.

The camera path is already guarded well: the `≤1 MB && isJpeg` fast path in
[`crop_screen.dart`](../lib/features/scan/presentation/crop_screen.dart#L46)
skips it for the common case, and that guard is a genuinely good optimisation
that is already in place.

The **gallery path is not** so lucky: `_gallery()` runs `compute(encodeScanJpeg, …)`
unconditionally on the picked bytes *before* the crop, and then `_onCropped` may
run it **again** on the crop result. Two full decode/resize/encode cycles for one
gallery scan.

### #8 — Camera initialisation is not pre-warmed

**Structural.** `_initCamera()` starts in `initState`, i.e. only once the
scanner route is already being built. `availableCameras()` plus
`initialize()` at `ResolutionPreset.veryHigh` is **300–900 ms (est.)** during
which the user stares at the empty scanner background.

---

## 3. What is already right

Worth recording, so the optimisation work does not "fix" these:

- **`_attachTeaching` is correctly off the critical path** — the answer renders,
  then teaching enriches it in place. This is exactly the pattern the rest of the
  pipeline needs.
- **The read-through history cache** short-circuits the entire solve leg for a
  re-opened problem, and works offline.
- **The server-side solve cache** (`getCachedSolve`) makes a repeat problem free
  and fast for everyone, not just the user who first solved it.
- **The `≤1 MB && isJpeg` direct-upload fast path** already avoids the most
  expensive client-side step in the common camera case.
- **The steadiness auto-capture** already removes the shutter tap for users who
  leave it on — genuine perceived-speed work that predates this audit.
- **The `_picking` / `_busy` guards** are load-bearing concurrency correctness,
  not incidental. Any pipelining work must preserve them.

---

## 4. Instrumentation added in this phase

Measurement only — no behaviour changed.

### Client: `PerfTrace` ([`lib/core/monitoring/perf_trace.dart`](../lib/core/monitoring/perf_trace.dart))

A span recorder that renders a waterfall. Spans are mirrored to
`dart:developer`'s Timeline, so a run shows up in DevTools next to the frame
chart — which is how UI-isolate jank (bottleneck #6) becomes visible rather than
merely suspected. The summary logs at `LogLevel.debug`, which `LoggingService`
drops in release, so a shipped build pays only for the stopwatch.

The trace is shared through
[`scanTraceProvider`](../lib/features/scan/application/scan_trace.dart) because
the scan crosses four owners that never see each other — the scanner screen, the
pushed crop route, the scanner controller, and the result controller on a
different screen. Threading a profiler argument through `ScannerService` and
`SolverService` would have contaminated both contracts.

Stages recorded, shutter → answer:

| Span | What it isolates |
|---|---|
| `capture.takePicture` | sensor + encode |
| `capture.readBytes` | the temp-file round trip |
| `gallery.pick` / `gallery.readBytes` / `gallery.normalizeJpeg` | the gallery path, incl. its extra encode |
| `crop.screen` | **human** framing time |
| `crop.execute` | the native crop |
| `crop.reencode` | the Dart `image` isolate (only when the fast path misses) |
| `recognize.roundTrip` | the whole `recognizeEquation` call as the phone feels it |
| `userTappedSolve` | a mark — the gap before it is dead time |
| `solve.roundTrip` / `solve.cacheHit` | the solve leg |

Screen startup is traced separately as `scanner.open`
(`cameraInit.enumerate`, `cameraInit.initialize`, `cameraInit.flashMode`,
`firstFrame`), because it happens once per screen while a scan happens many
times, and because "camera open" has its own target and its own fix.

### Server: stage timings in `recognizeEquation`

`functions/src/proxy/scan.ts` now logs one structured
`recognizeEquation.timings` line per call — `moderate`, `imagePrep`, `ocrPass`,
`visionPass`, `total`, plus `enhanced`, `ocrOk` and `base64Len`. Queryable in
Cloud Logging, so the two-reasoning-pass hypothesis (#1) can be confirmed against
production traffic rather than argued from the code.

`total` is deliberately larger than the sum of its stages; the difference is the
Firestore quota/rate-limit work and base64 handling, and a growing gap there is
itself a finding.

### How to capture a baseline

```bash
flutter run --profile           # debug-level logs survive; release drops them
# scan a printed equation, a handwritten one, and one from the gallery
# the waterfall prints under the `matheasy.perf` log name
```

Server side: filter Cloud Logging on `jsonPayload.message="recognizeEquation.timings"`.

---

## 5. Estimated baseline budget

**Estimates, pending device capture.** Camera scan, warm function, printed
equation, good light:

| Stage | Est. | Nature |
|---|---|---|
| Camera open (route → first frame) | 300–900 ms | machine |
| Aim | — | human |
| `takePicture` + `readAsBytes` | 200–600 ms | machine |
| **Crop screen** | **3 000–10 000 ms** | **human** |
| Crop execute (+ conditional re-encode) | 50–1 200 ms | machine |
| base64 + upload | 300–1 000 ms | machine, UI-isolate jank |
| **`recognizeEquation`** | **8 000–25 000 ms** | **machine** |
| Read the card, tap Solve | 1 000–4 000 ms | human |
| `solveEquation` | 2 000–20 000 ms | machine |
| **Shutter → answer** | **~15–60 s** | |

Against the Phase 10 targets, the two that matter:

- *Detected equation visible: <800 ms* — currently gated behind a human crop step
  plus two sequential reasoning-model vision passes. Off by more than an order of
  magnitude, and **not reachable by tuning**: it requires the detected equation to
  come from somewhere other than a server round trip.
- *Final answer: 2–4 s* — plausible for the deterministic-solve path once
  recognition is fixed and the solve is no longer gated behind a tap; not
  plausible for the LLM-candidate-plus-retry path, which is three more reasoning
  calls.

---

## 6. A conflict in the brief that has to be resolved before Phase 4

The brief asks (Phase 4) for **Apple Vision / ML Kit as the primary OCR**, with
GPT Vision demoted to a fallback, while also requiring (Phase 11) that **OCR
accuracy and mathematical correctness must not regress**.

For this app those two cannot both hold. Apple Vision and ML Kit are *line text*
recognisers built for receipts, signs and documents. They have no notion of
two-dimensional mathematical layout:

- a fraction returns as two adjacent lines, or as `3 4` — the bar is not a glyph
  it models;
- exponents lose their superscript relationship, so `x^2` reads as `x2`;
- `√`, `∫`, `Σ` and matrix brackets are dropped, mangled, or split across lines;
- a `-` and a fraction bar are the same mark to it;
- handwriting support is weak, and handwritten maths is a stated target case.

Making either one the *transcriber* would feed the solver structurally wrong
LaTeX. Because the verification gate substitutes back into **the problem as
transcribed**, a misread problem verifies perfectly and the app returns a
confidently wrong answer — the one failure mode the golden rule exists to
prevent. That is a correctness regression, not a speed/accuracy trade.

**The adaptation that gets the speed without the regression:** use on-device
vision for **detection and localisation**, never transcription.

| On-device is genuinely good at | Which serves |
|---|---|
| finding text blocks, at frame rate | Phase 2 — the live green bounding box |
| bounding the equation region | Phase 3 — smart auto-crop, removing the human crop step |
| "is there any text here at all" | Phase 5 — instant feedback, cheap pre-gate |
| block count / layout / diagram-vs-text | Phase 8 — parallel category + diagram hints |

GPT Vision stays the transcriber. This keeps every accuracy property intact while
removing bottlenecks #2 (human crop), most of #8 (framing feedback), and shrinking
the upload (#3/#7) by cropping tightly on-device.

**Recommendation: adopt the detection-only adaptation for Phases 2–5 and 8, and
explicitly drop "local OCR as primary transcription" from Phase 4.** The
perceived-speed goal is met by showing the user a *detected, highlighted, cropped*
equation in <100 ms — which on-device vision can do — rather than by showing them
*transcribed LaTeX* in <100 ms, which it cannot do correctly.

---

## 7. Recommended sequence

Ordered by value per unit of risk, not by the brief's numbering:

1. **Start the solve as soon as recognition lands**, without waiting for the
   "Solve" tap (kills #3). No new dependency; the confirmation card stays exactly
   as it is, but by the time the user taps, the answer is usually already there.
   Must respect the existing quota gate — the tap is also the paywall checkpoint,
   so this needs care, not just a moved `await`.
2. **Parallelise `moderateImage` with `prepareScanImage`** server-side (kills
   #4). Contained, server-only, deployable without a client release.
3. **Set `minInstances: 1`** on `recognizeEquation` and `solveEquation` (kills
   #5). A config line and a small standing bill.
4. **Move `base64Encode` into the isolate that already re-encodes** (kills #6).
5. **Fix the gallery double-encode** — one pass, after the crop, not before and
   after (kills half of #7).
6. **On-device detection + auto-crop**, crop screen demoted to an optional
   "Adjust" affordance (kills #2, the biggest human-time win). This is the one
   that needs a new dependency and a real design decision.
7. **Re-examine the two-pass recognition** — measure how often the OCR pass and
   the vision pass actually disagree. If they agree on, say, clean printed input,
   a confidence-gated single pass for that case is worth 5–12 s (est.) on the most
   common scan of all. *Only* with the disagreement data in hand; the two-pass
   split exists for a real correctness reason and must not be removed on a hunch.

Items 1–5 are additive, low-risk, and touch no contract. Item 6 is a product
decision. Item 7 is a correctness-sensitive change that must be driven by
measurement.

---

## 8. Open questions for the next phase

- Does the crop screen disappear entirely, or become an "Adjust" button on the
  confirmation card? (Affects whether users can still fix a bad auto-crop.)
- Is a new native dependency acceptable (`google_mlkit_text_recognition` covers
  both platforms; ~2–6 MB of app size, new iOS pods)?
- Can the solve start pre-emptively without breaking the scan-limit paywall
  checkpoint, which currently sits on the same tap?
