# Matheasy — Scanner + Solver Spec (AS-BUILT / reconciled)

> **Status: reconciled to shipped code after §11 steps 1–9.** This replaces the
> original build spec, which drifted from the codebase at nearly every step. This
> version is a TRUE RECORD of what was built — use it as the accurate baseline for
> future work or a fresh session. Where the original spec said something the code
> contradicts, this notes it as `[was: …]` so the history is legible.
>
> The golden rule (never confidently wrong) held through all nine steps and is the
> spine of the app. Everything else bent to the real code.

---

## 0. Stack (as-built)

- Flutter (Dart)
- Riverpod v2 + GoRouter (`StatefulShellRoute`)
- **Firebase** — Auth, Cloud Functions, **plus the existing sync framework**
  (`shared_preferences` + Firestore `users/{uid}/state/{domain}`)
  `[was: "Isar for offline"]` — Isar was never added; the existing sync framework
  handles persistence.
- RevenueCat — billing / entitlements
- Math rendering: `flutter_math_fork`
- Vision/OCR: **OpenAI Vision (GPT-4o) only** `[was: "Mathpix primary + OpenAI
  fallback"]` — Mathpix was removed (Scanner V2); recognize() is OpenAI-only. No
  Mathpix account or keys.
- Moderation: OpenAI `omni-moderation-latest` (free) before the paid vision call
- Sensors: `sensors_plus` (auto-capture steadiness)
- Permissions: `permission_handler` (only `openAppSettings()` used; all other
  handlers compiled out in the iOS Podfile for App Store review)

---

## 1. Architecture — the golden rule (held)

**The LLM never invents arithmetic.** Deterministic solve, verify by substitution,
LLM narrates only. As-built pipeline:

```
Camera frame → on-device framing/steadiness (expo… no: camera plugin + sensors_plus)
   → capture (inline base64, NEVER stored to Storage)
   → Cloud Function recognize():
        moderateImage (free, fail-closed on flag / fail-open on outage)
        → OpenAI Vision → { isMath, latex, confidence }
   → detected equation, EDITABLE (tap → math keyboard prefilled)
   → Cloud Function solve():
        rate-limit check (server, before paid call)
        → solve-cache check (verified-only, collision-safe key) — hit = free
        → classify → deterministic solve (mathsteps + mathjs) → VERIFY GATE
          (substitute back, 1e-4 tolerance)
        → tiered: unsupported types → constrained LLM candidate → SAME gate
        → LLM narrates operation/why per step
        → §4 JSON (see §4)
   → answer-first → stepper (changed-term emphasis) → methods → graph → history
```

Every paid call is server-proxied, rate-limited, and quota-checked **before** the
spend. Keys in Secret Manager, never in the bundle.

### 1.1 Deterministic solving (as-built)
- `mathsteps` (primary: linear/quadratic/simplify) + `mathjs` (arithmetic/derivatives)
  in the Node Cloud Functions runtime.
- **Tiered** `[confirmed choice]`: types the deterministic engines can't solve
  (cubics, trig, systems, integrals) go to a constrained LLM that produces a
  *candidate*, which STILL must pass the substitution/verification gate; the displayed
  answer is rebuilt from verified numbers, not the model's text.
- Definite integrals: verified via deterministic numeric integration (composite
  Simpson) that must agree with the candidate.
- Trig: model returns principal radians; gate verifies each principal + periodicity;
  displayed exact-radian form built from verified values.
- **Verify gate tolerance: 1e-4** `[was: 1e-6]` — loosened during step-4 live testing
  because 5-sig-fig irrational values from the model err ~3e-6; 1e-4 still rejects any
  structurally-wrong answer (off by orders of magnitude). Prompt asks for ≥6 sig figs.
- **LaTeX normalizer (`latex.ts`):** single interleaved fixpoint loop (innermost braces
  first, peel outward) `[was: sequential per-rule passes]` — the sequential version
  mangled nested fractions including the quadratic formula shape; fixed in step 4.

---

## 2. Scanner (as-built)

Camera-first (Scanner V2). Full-screen preview, framing reticle in **AppColors.primary
(emerald)** `[was: "primary accent" — implemented as emerald; corners were white
pre-step-2]`. Manual shutter + gallery (`image_picker`) + **crop-confirm**
`[crop was a V2 addition not in the original spec — kept; it aids OCR]`.

Hint + processing overlay use **`MatheasyBrandAvatar`** `[was: "NumiMascot, thinking
expression"]` — NumiMascot is the dead pre-rebrand mascot; the brand avatar is the
expression-less replacement in use everywhere.

**Scan gate:** `_allowScanOrPaywall()` reads `usageSnapshotProvider.canScan` and routes
to the existing paywall **before** capture, from `_shutter`/`_gallery`/`_onContinue`.
This is UX only — the **server** `assertWithinQuota` in the Cloud Function is the
authoritative cap (see §10).

**Auto-capture (step 9):** `SteadinessDetector` (accelerometer, `sensors_plus`) fires
the existing `_shutter()` flow after ~0.8s steady — so it routes through the same gate
and server cap. Fires once, re-arms on a movement spike. "Auto on/off" toggle (default
on; safe because crop-confirm precedes the paid recognize). Guarded like the camera —
sensorless device just doesn't auto-capture; manual shutter untouched.

---

## 3. Recognition + editable detected equation (as-built)

`recognize()` returns `{ latex, confidence, source }`. Rendered as proper math
(`flutter_math_fork`, `5x^2`→5x²) with raw-text fallback.

**Editable (the §3 non-negotiable — was NOT present before step 3):** the detected
equation is tappable (framed + edit pencil) → opens `ManualInputScreen` **prefilled**
with the recognized LaTeX (`ManualInputArgs`) → correct → "Use this" → re-solves via
`confirm(countAsScan:false)` so the correction does NOT double-charge
`[the OCR-result-into-editor flow was the actual work of step 3; manual input was a
separate blank path before]`.

Confidence: high → "DETECTED · %" check; low (<0.8) → "CHECK THIS · %" + "tap the
problem to fix it before solving." Primary action: "Solve" (`PrimaryButton`).

---

## 4. solve() schema (as-built)

Returns exactly this (LLM emits only this; parsed into freezed models). ResultData
gained `verified` / `answerPlain` / `graph` during steps 1/5; graph gained `curve`
during step 6.

```json
{
  "problemLatex": "5x^2 + 3x - 2 = 0",
  "problemType": "quadratic_equation",
  "finalAnswer": { "latex": "x_1 = -1,\\; x_2 = \\tfrac{2}{5}", "plain": "x = -1 or x = 2/5" },
  "verified": true,
  "methods": [
    { "id": "factoring", "name": "Factoring", "examPick": true,
      "steps": [ { "expression": "…", "operation": "…", "why": "…" } ] }
  ],
  "graph": {
    "kind": "function",
    "expression": "5x^2 + 3x - 2",
    "keyPoints": [ { "label": "root", "x": -1, "y": 0 }, { "label": "vertex", "x": -0.3, "y": -2.45 } ],
    "curve": [ /* server-sampled [x,y] points from the verified expression */ ]
  }
}
```

`graph` null when not plottable. `methods` ≥ 1. **`verified:false`** returned when no
answer passes the gate (see §5 couldn't-verify). **keyPoints are deterministic +
verified** — roots from verified candidate/assignments (y=0), vertex from `-b/2a` +
`evalReal`, y-intercept from `evalReal(expr,0)`. `curve` is server-sampled from the same
verified expression `[the server sends curve samples because there's no Dart math-eval
lib; client just draws the polyline — added step 6]`.

---

## 5. Stepper + methods + couldn't-verify (as-built)

- **One-at-a-time stepper** ("Next step · n of N" + "Reveal all" toggle), expandable
  "why". `[was: showed all steps at once]`
- **"What changed" emphasis** (`step_diff.dart`): atom-diff wraps the changed span in
  `\textcolor{…}{…}` (confirmed flutter_math renders it) + a scale-pulse on reveal
  `[was: a hardcoded #10B981 — the retired brand, and 2.54:1 on a white card. The
  hex is now derived per-theme from the brand ramp by `solution_tab.dart`:
  primaryDark on light, primaryLight on dark. See docs/matheasy-brand-system.md]`
  (suppressed under `disableAnimations`; the color persists — pedagogy survives
  reduce-motion). **Faithful for single-contiguous changes; honest whole-line fallback**
  for two-site / whole-expression / deep-fraction changes (correctness over cleverness —
  wrong emphasis would mis-teach).
- **Method switcher** (`MethodSolution.stepperSteps`): chips, exam-pick starred, each
  drives its own stepper. `[was: hard-wired to exam-pick; Methods was a read-only tab]`
- **verified:false → `result_couldnt_verify.dart`** (fully expanded in step 8): reframed
  as app integrity, never the student's fault — *"I couldn't confirm a reliable answer…
  that's on me, not you… I only show answers I can check by working them backwards."*
  Shows the problem, NO answer, "Edit the problem" (→ keyboard prefilled) primary,
  "Rescan" secondary. **Deliberately no "Ask Matheasy" path** — it would offer an answer
  through a side door and break the honesty. `[was: rendered an empty green answer card
  — a real bug]`

Step-8 robustness fix: step-card timeline uses `Stack`+positioned connector `[was:
IntrinsicHeight, overflowed ~1.4px on MathText sub-pixel intrinsics]`.

---

## 6. Math keyboard (as-built)

The existing V1.1 `MathKeyboard` `[was: "evaluate math_keyboard from pub.dev" — IGNORED;
the repo's own keyboard was used and is the OCR-correction editor from §3]`.

**Raw-text + structured templates, NOT a token tree** — but the exponent key writes
`^{}` (never a bare `^`), so a flat `5x^2` is physically unproducible; nesting is
preserved at input time. All six probed structures build/render/solve:
`x^{2/3}`, `\sqrt{x+1}`, `\frac{x^2}{3}`, `x_1`, `\sin(3x)`, `\frac{d}{dx}(…)`.
`[the one probe failure — nested-fraction `\frac{x^2}{3}` — was a SERVER normalizer bug
(§1.1), not the keyboard.]`

Has: number row, + − × ÷ =, parens, fraction, exponent, sqrt, nth-root, subscript,
sin/cos/tan, log/ln, π, d/dx, live MathText preview, feeds solve().

Known friction: caret navigation is character-based (crossing `}{` = two presses).

---

## 7. Graph (as-built)

`CustomPaint` (`result_graph.dart`) — **no charting dependency added** `[was: "fl_chart"
— none was in pubspec; hand-drawn CustomPaint instead]`. Draws the **server-sampled
curve polyline** + axes + haloed keyPoint dots with `(x,y)` labels, AppColors.primary,
light/dark themed. Pan/zoom via a one-line `InteractiveViewer`.

"Show graph" is a **collapsed-by-default expander** in the Solution tab after the
stepper; **omitted entirely when `graph == null`** (no empty box).

---

## 8. History + caching (as-built)

Persists to Firestore `users/{uid}/state/{domain}` + local via the **existing sync
framework** `[was: "Isar + solutions collection"]`. Not Isar.

- List: rendered equation preview + timestamp, most-recent-first; Home "Recent" section
  + full History screen. `[recent-scans row was a no-op toast before step 7]`
- **Tap → re-open full result WITHOUT re-solving** — `ResultController.build` hits the
  cache before solving; no `solve()` call, no scan charge, works offline. **Only
  `verified:true` cached** (a couldn't-verify re-scan still retries).
- **Client cache key `historyCacheKey()`:** conservative, identity-preserving-only,
  **strictly finer than the server normalizer** so it can never merge two problems the
  solver distinguishes (`5x^2`≡`5x^{2}`; `x^{10}`≠`x^10`). `[deliberately NOT a re-port
  of the server normalizer — a re-port would drift out of sync.]`
- **Reconciliation (`SyncMerge._mergeHistory`):** union by canonical key; same key →
  newest-by-timestamp (last-write-wins); most-recent-first, capped. **Local is the
  working set; Firestore reconciles INTO it, never over it** — an unsynced offline solve
  survives and syncs up.
- **Privacy (COPPA):** LaTeX + solution JSON only; **no image bytes** (test asserts no
  `image`/`bytes`/`base64`/`jpeg` in the serialized entry). Clear-history: swipe-one +
  "Clear all" (confirm dialog).

---

## 9. States (as-built, step 8)

All in Matheasy's voice — errors give direction, empty states invite:
- **Camera denied** → "Matheasy needs the camera to scan problems" + "Open Settings"
  (`permission_handler.openAppSettings()`) + "Type it in".
- **Couldn't recognize** → "That was hard to read… try again — or type it in," routes to
  keyboard.
- **Offline** → "You're offline… Your saved solutions still open offline" (names what
  still works).
- **Empty history** → invitation to scan (from step 7).
- **Non-permission camera failure** → explained state, not a blank screen.
- **Explain tab empty** → "…but I can talk you through it" + Ask Matheasy.
- **Practice tab empty** → now carries a Generate button `[fixed a broken affordance —
  copy said "tap Generate" with no button]`.

Step-8 bug fix: an async provider throwing an `Exception` (e.g. `BackendException`)
stays stuck in `AsyncLoading` in this Riverpod/flutter_test version — only a thrown
`Error` surfaces as `AsyncError`. Offline solve could hang the result screen forever.
Fixed: catch in `ResultController.build`, rethrow `ResultSolveFailure extends Error`
carrying `offline`.

---

## 10. Cost caps + safety (as-built, step 9) — server-authoritative

- **Free-tier scan cap:** `assertWithinQuota` in the Cloud Function fires **before** the
  paid OpenAI call; `users/{uid}` is `allow write: if false` so counters can't be forged.
  The client `_allowScanOrPaywall` gate is UX only.
- **Per-user rate limiter (`rateLimit.ts`) — NEW in step 9; none existed before.**
  Firestore fixed-window (per-minute burst + per-day) before the paid call, for **every**
  user incl. Pro, on recognize/solve/tutor/visual/practice. Limits: recognize 20/min·
  300/day, solve 30/400, tutor 30/300, visual 15/100, practice 20/200. **This closed the
  previously-unbounded path** — Pro users were uncapped and `solve(countAsScan:false)`
  skipped metering while making a paid LLM call.
- Client (`functions_client.dart`): `isRateLimited` split from `isQuotaExceeded` so a
  rate-limited user is NOT wrongly sent to the paywall.
- **Moderation (`openai.ts moderateImage`) — NEW:** free `omni-moderation-latest` before
  the paid vision call. **Fail-closed on a flag** (reject), **fail-open on a moderation
  outage** (the `{isMath, latex}` output contract is the backstop). COPPA.
- **Server solve cache (`solveCache.ts`) — NEW:** global, verified-only, collision-safe
  canonical LaTeX key (same transforms as `historyCacheKey`, ported to TS), SHA-256 doc
  IDs, best-effort (failure → miss), `expiresAt` for TTL.
- **Images never stored** — inline base64, discarded. Stronger than "auto-expire."

Note: `maxInstances: 10` is a global concurrency ceiling, not a per-user cap — does not
replace the rate limiter.

---

## 11. Status vs. the build order

Steps 1–9 complete. What remains is **deploy/operational** (see the deploy runbook), not
build:
- `firebase deploy --only functions`, `OPENAI_API_KEY` secret confirmed
- **one-time `solveCache` TTL policy** (`gcloud firestore fields ttls update`)
- `pod install` on a Mac (applies the Podfile permission-compile-out)
- on-device verification of caps/moderation/offline/auto-capture

**Carried build debt (not blocking, fix before real users):**
- **`√2`→`1.414…` symbolic-form display** (since step 4) — exact form IS the correct
  answer for SPM/IGCSE; fix in the narration/mapping layer, verify gate can stay numeric.
- Caret navigation character-based (step 4).
- Explain/Practice tabs are empty states — separate features (tutor, practice generator).
- `4ac`→NaN in mathjs for bare multi-var expressions (step 4) — doesn't affect real
  equation inputs.

---

## Out of scope of THIS spec (separate features, `// HANDOFF` stubs in code)

Numi/Matheasy chat tutor, practice generator, exam modes, gamification, onboarding,
auth. The scanner flow leaves marked handoffs to these; they each need their own scoped
spec.
