# Matheasy — project guide for Claude

Matheasy is a **Flutter + Firebase** math-tutor app: scan or type a problem →
get a **deterministically-solved, verified** answer with step-by-step working,
method switching, a graph, explanations, adaptive practice, and an AI tutor.

## Canonical references (read these first)

- **Scanner + solver spec (AS-BUILT):** [`docs/matheasy-scanner-spec-RECONCILED.md`](docs/matheasy-scanner-spec-RECONCILED.md)
  — the single source of truth for the scan→solve→result→history pipeline
  (§0 stack, §1 golden rule, §2–§7 scan/solve/UI/graph, §8 history+caching,
  §9 states, §10 cost caps + safety). It is reconciled to the shipped code after
  build-order steps 1–9; where the old build spec drifted it records `[was: …]`.
  The earlier `matheasy-scanner-spec-flutter.md` was **stale and has been
  deleted** — do not resurrect it.
- **Brand system (v2.0, logo-anchored):**
  [`docs/matheasy-brand-system.md`](docs/matheasy-brand-system.md) — the source of
  truth for colour and the mark. Every emerald is **measured from**
  [`brand/matheasy-logo-source.png`](brand/matheasy-logo-source.png). The v1.0
  system (Emerald `#10B981` + the "R8 two-check" mark) is **retired**; if a doc,
  comment, or memory still says either, it is wrong.
- **Deploy runbook:** [`docs/matheasy-deploy-runbook.md`](docs/matheasy-deploy-runbook.md).

## The real stack (do NOT assume otherwise)

- **Flutter (Dart)** — Riverpod v2 (`@riverpod` codegen) + GoRouter
  (`StatefulShellRoute`). Clean-architecture feature folders under `lib/features/`.
- **Firebase** — Auth, Cloud Functions (the `functions/` TypeScript backend),
  Firestore, Crashlytics, Analytics.
- **Persistence = the existing offline-first sync framework** in
  `lib/features/sync/` (`shared_preferences` locally + Firestore
  `users/{uid}/state/{domain}` blobs, reconciled by `SyncMerge`/`SyncService`).
  **NOT Isar** — Isar was never added; do not introduce it.
- **Recognition = OpenAI Vision (GPT-4o) ONLY**, server-side via
  `recognizeEquation`. **No Mathpix** — it was removed in Scanner V2; there is no
  Mathpix account, key, or `MATHPIX_*` env. A free `omni-moderation-latest` gate
  screens images before the paid vision call (COPPA).
- **Billing = RevenueCat** (entitlement `pro`); the server is authoritative.
- Math rendering: `flutter_math_fork` (via the shared `MathText` widget).
- Native helpers: `permission_handler` (only `openAppSettings()`), `sensors_plus`
  (auto-capture steadiness), `camera`, `image_picker`, `crop_your_image`.

**This app is NOT React Native, NOT Expo, NOT Supabase, and does NOT use Mathpix
or Isar.** If any doc, comment, or memory says otherwise, it is wrong — trust the
reconciled spec and the code.

## Architecture golden rule (never break this)

**The LLM never invents arithmetic.** The answer is computed deterministically
(mathsteps + mathjs), **verified by substituting it back into the original
problem**, and only then returned. When no engine can solve it, a constrained LLM
proposes a *candidate* that must still pass the same substitution gate — else the
app returns an honest `verified:false` "couldn't verify" state, **never a
confident wrong answer.** The LLM only narrates the "why". Exact symbolic form
(√2, π, fractions) is the correct answer and must be preserved in the display;
verification may still compute numerically underneath.

## Working rules

- **Client changes are presentation/infrastructure only.** The real enforcement
  (quotas, per-user rate limits, moderation, entitlement checks) lives
  **server-side** in `functions/`; client gates are UX only and bypassable.
- **Preserve routing + monetization.** Don't touch the GoRouter structure, the
  scan-limit/paywall gating, or RevenueCat wiring unless that IS the task.
- **Additive by default.** Reuse the repo's widgets/theme tokens (`AppColors`,
  `AppTypography`, `AppSpacing`, `context.colors`) and the `MatheasyBrandAvatar`
  (there is no mascot / "NumiMascot"). Don't regress shipped features.
- **The emerald splits by job — this is not optional.** White on the logo's
  emerald is 2.97:1. `AppColors.primary` (#06AC60) is the **identity** and is for
  brand art only (mark, icon tile, splash); it must never sit under functional
  white content or be a text colour on a light surface. Filled controls use
  `primaryAction` (#058446, white 4.78:1 ✓); emerald text uses `primaryDark` on
  light / `primaryLight` on dark. Never put a gradient behind white label text.
  `test/core/theme/brand_contrast_test.dart` enforces all of it.
- **The `§4` solve schema** (`problemLatex`, `problemType`, `finalAnswer`,
  `verified`, `methods[]`, `graph`) is the contract between server and client —
  keep both sides in sync.

## Verify your work

```bash
flutter analyze                       # must be clean
flutter test                          # full Dart suite
cd functions && npm run build         # tsc — must be clean
cd functions && npx vitest run        # functions suite
```

End git commit messages with:
`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
