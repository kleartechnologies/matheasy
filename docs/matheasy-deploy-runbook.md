# Matheasy Scanner — Deploy & Launch Runbook

> Everything in the §11 build (steps 1–9) is written, tested, and **uncommitted /
> undeployed**. Nothing is live. This runbook is the exact sequence from "code on
> disk" to "verified in production." Do the steps **in order** — several have
> dependencies that bite if skipped (the TTL policy especially).
>
> Legend: 🖥️ = needs your Mac · ☁️ = touches live Firebase/billing · 📱 = on-device
> · ⚠️ = easy-to-forget gotcha

---

## 0. Pre-flight — commit first

Everything is gated and uncommitted. Before deploying anything, commit the verified
state so you have a clean rollback point.

```bash
# from repo root
git status                      # confirm what's staged
git add -A
git commit -m "feat(scanner): steps 1-9 complete — verified solver, scanner, keyboard, stepper, graph, history, states, cost caps"
```

If you've been committing per-step (recommended earlier), this is just the final
step-9 commit instead.

---

## 1. ☁️ Confirm Firebase project + plan

```bash
firebase projects:list                    # confirm matheasy-f9b3f is there
firebase use matheasy-f9b3f               # select it
```

⚠️ **Blaze plan is required** — Cloud Functions that call OpenAI (outbound network)
do NOT run on the free Spark plan. The step-1 report said the project is already
Blaze (`matheasy-f9b3f`, nodejs22, Blaze) — confirm in the console
(console.firebase.google.com → project → Usage & billing) before proceeding. If it's
somehow on Spark, functions deploy but fail at runtime with a network error.

---

## 2. ☁️⚠️ Set the OpenAI secret

The functions read `OPENAI_API_KEY` from Secret Manager — it must NOT be in code.

```bash
# check whether it's already set
firebase functions:secrets:access OPENAI_API_KEY 2>/dev/null && echo "SET" || echo "NOT SET"

# if not set:
firebase functions:secrets:set OPENAI_API_KEY
# (paste the key when prompted; it's stored in Secret Manager, not the repo)
```

⚠️ If you rotate the key later, re-run `:set` **and redeploy** — functions bind the
secret version at deploy time.

There is **no Mathpix key** — `recognize()` is OpenAI-Vision-only (decided during the
build). Don't let any stale doc tell you to set `MATHPIX_APP_ID`.

---

## 3. Install function deps + build

```bash
cd functions
npm install                     # pulls mathsteps + mathjs (the deterministic solver)
npm run build                   # tsc — must be clean (was clean at step 9: 109 tests)
npm test                        # optional but wise: confirm the 109 pass on your machine
cd ..
```

⚠️ `mathsteps@0.2.0` pulls old transitive deps that throw npm-audit warnings. These
are **known and accepted** (server-side, controlled input — noted since step 4). Do
NOT `npm audit fix --force`; it can bump `mathsteps` and break the solver. Leave them.

---

## 4. ☁️ Deploy the functions

```bash
firebase deploy --only functions
```

This deploys recognize / solve / tutor / visual / practice with the cost caps, rate
limiter, moderation gate, and solve cache. Watch the output for per-function success.

⚠️ First deploy of a nodejs22 function can take a few minutes and may prompt to enable
APIs (Cloud Functions, Cloud Build, Artifact Registry) — say yes.

---

## 5. ☁️⚠️⚠️ The one-time TTL policy — DO NOT SKIP

The solve cache writes an `expiresAt` field, but Firestore only actually deletes
expired docs if you enable a **TTL policy** on that field. This is a separate,
one-time command that is NOT part of `firebase deploy` — it's the single easiest
thing to forget, and if you skip it the `solveCache` collection **grows forever**.

```bash
gcloud firestore fields ttls update expiresAt \
  --collection-group=solveCache \
  --enable-ttl \
  --project=matheasy-f9b3f
```

(Requires `gcloud` CLI authenticated to the project: `gcloud auth login` +
`gcloud config set project matheasy-f9b3f` if you haven't.)

Verify it took:
```bash
gcloud firestore fields ttls list --collection-group=solveCache --project=matheasy-f9b3f
```

⚠️ Same consideration applies to any other `expiresAt`-bearing collection the rate
limiter or quota counters use — check whether `rateLimits`/quota docs are meant to
expire and enable TTL on those too if so. (If they're per-user documents that get
overwritten rather than accumulated, they don't need TTL — confirm which.)

---

## 6. 🖥️📱 iOS — pod install + build

The step-8 Podfile hardening (`PERMISSION_*=0`, compiling out every permission handler
except `openAppSettings()`) needs a pod install on your Mac to take effect.

```bash
cd ios
pod install                     # applies the Podfile permission-compile-out
cd ..
flutter clean
flutter pub get
flutter build ios               # or run on device from Xcode / flutter run
```

⚠️ The permission-compile-out is what keeps App Store review from flagging
unused-permission API references. If you skip `pod install`, the hardening isn't
applied and you risk that rejection. Confirm the build succeeds after it.

---

## 7. 📱 On-device verification battery — the tests the suite CAN'T cover

The 344 Dart + 109 function tests pass, but these are the things only real
hardware + deployed functions can prove. Run each deliberately.

### 7a. 📱☁️ Cost caps — test by EXCEEDING them (highest priority)
The caps are server-authoritative; unit tests assert the window logic, but only a
deployed call proves the function rejects **before spending money**.
- Burn through the **free-tier scan cap** → confirm the paywall fires AND (if you can
  inspect) the server returns `ScanQuotaExceeded` rather than completing a paid vision
  call. The cap must hold even against a replayed/direct request, not just the client
  gate.
- Hammer **solve()** past the rate limit (rapid repeated solves) → confirm you get a
  **rate-limited** response, and critically that it does **NOT** send you to the
  paywall (the step-9 `isRateLimited` vs `isQuotaExceeded` split). A rate-limited user
  told to "upgrade" is the bug to catch here.
- Confirm the previously-uncapped path is now capped: a Pro user (or the
  `countAsScan:false` re-solve from an OCR correction) hitting solve repeatedly should
  now hit the rate limit — that was the unbounded hole step 9 closed.

### 7b. 📱☁️ Moderation gate (COPPA)
- Submit a **non-math / inappropriate image** → confirm it's **rejected** (fail-closed
  on a flag), nothing inappropriate processed or returned.
- Submit a normal **math scan** → confirm it passes through to recognition.
- (Fail-open on a moderation *outage* is hard to induce manually — the output-contract
  backstop covers it; the flagged→rejected path is the one to verify by hand.)

### 7c. 📱 Offline behavior — the airplane-mode battery (re-confirm on device)
- Solve a problem → force-quit → **airplane mode** → reopen → open History → the item
  is there and re-opens to the **full** result (answer + steps + methods + graph) with
  **no connectivity, no re-solve, no spinner**. Confirms the offline-first cache + the
  step-8 forever-hang fix hold on real hardware (the hang was framework-version
  specific — device is the honest test).
- Airplane-mode a **fresh scan** → the offline state appears (says what still works),
  and the result screen does **NOT** hang.

### 7d. 📱 The state break-tests (steps 8) — cause each failure
- **Deny camera permission** → open scanner → "Open Settings" button appears and
  actually opens Settings.
- **Scan illegible / non-math** → couldn't-recognize state routes to the keyboard.
- **Force a verify-gate failure** (messy handwriting that OCRs wrong) → read the
  couldn't-verify screen **as a student would**: calm, honest, "on me not you," offers
  Edit/Rescan — not a crash, not blaming the student. This is the honesty payoff; it's
  a judgment only you can make by seeing it.

### 7e. 📱 Auto-capture (step 9, lower stakes)
- Point at a worksheet, hold steady ~0.8s → auto-triggers recognition on its own.
- Tap the manual shutter first → still works (auto-capture must never break the
  fallback).
- Confirm an auto-triggered scan still respects the cap (a capped free user isn't
  silently pushed past the paywall by auto-capture).

### 7f. 📱 The visual/pedagogical eyeballs (steps 5–6)
- Run a real quadratic (e.g. `5x²+3x−2`): stepper advances one step at a time, the
  **changed term draws your eye** (colored emphasis reads as pedagogy, not decoration),
  method switcher shows genuinely different approaches with the exam-pick starred.
- Expand the graph: marked **roots sit exactly where the curve crosses the x-axis**,
  vertex at the turning point, curve shape matches the equation.

---

## 8. Known carried debt — fix before REAL users (not deploy-blocking)

These don't block getting it live, but the first is close to a correctness issue and
should be fixed before you promote to real students.

- ⚠️ **Symbolic-form display (`√2` → `1.414…`)** — carried since step 4. A derivative
  or irrational root shown as a decimal instead of the exact form is **marked wrong by
  a teacher**. For an SPM/IGCSE tutor the exact form IS the correct answer. The verify
  gate can keep computing numerically; the *display* must preserve the symbolic form
  (mathsteps/mathjs both retain symbolic expressions — the decimalization is in the
  narration/mapping layer). Fix before real users.
- **Caret navigation** (step 4) — character-based; crossing `}{` takes two presses. UX
  friction, minor.
- **Explain / Practice tabs** — still empty/"coming soon" states; they're the tutor and
  practice-generator features, separate builds. Visible in-app, so know they read as
  unbuilt until you build them.
- **`4ac`→`4*ac`→NaN** (step 4) — mathjs reads consecutive letters as one symbol; only
  affects a raw formula typed as a bare expression, not real equation inputs. Noted,
  low-priority.

---

## 9. Rollback

If a deploy misbehaves:
```bash
firebase functions:log                        # see what failed
# redeploy a single function:
firebase deploy --only functions:solve
# or revert the commit and redeploy:
git revert HEAD && firebase deploy --only functions
```
The client is gated behind the server, and caches/moderation are best-effort
(degrade to miss / fail-open on outage), so a function issue degrades rather than
hard-breaks the app — but the cap and moderation are the two you want healthy before
real traffic.

---

## Launch checklist (tick before real users)

- [ ] Committed (§0)
- [ ] Blaze confirmed (§1)
- [ ] `OPENAI_API_KEY` set (§2)
- [ ] Functions built + deployed (§3–4)
- [ ] **TTL policy enabled on `solveCache`** (§5) ← the easy-to-forget one
- [ ] `pod install` run, iOS builds (§6)
- [ ] Cap holds when exceeded, server-side (§7a)
- [ ] Rate-limit ≠ paywall (§7a)
- [ ] Moderation rejects non-math image (§7b)
- [ ] Offline history re-opens with no spinner (§7c)
- [ ] Couldn't-verify reads calm + honest on device (§7d)
- [ ] `√2` symbolic-form bug fixed (§8) ← before real students
