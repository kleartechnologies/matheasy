# Matheasy — Cloud Functions backend

The server-side backend for Matheasy. Three concerns:

| Function | Type | What it does |
| --- | --- | --- |
| `recognizeEquation` | callable | OpenAI Vision OCR proxy — photo → LaTeX. Meters the free `scans` quota. |
| `solveEquation` | callable | **Deterministic** solver — mathsteps + mathjs compute + verify the answer; the LLM only narrates. Returns the §4 schema. |
| `tutorReply` | callable | OpenAI tutor (Matheasy) — chat history → reply + suggestions. Meters `tutorMessages`. |
| `revenuecatWebhook` | HTTPS | Syncs RevenueCat entitlement + subscription state into Firestore. |
| `aggregateProgress` | Firestore trigger | Rolls `progressEvents` up into aggregate `stats`. |

**Why this exists:** the OpenAI API key must never ship inside the app. The
client calls these functions; the functions hold the secret (in Cloud Secret
Manager) and enforce the free-tier quotas server-side, so paid status and usage
counts can't be forged on-device.

**The solver's golden rule (see `src/solver/`):** the answer is ALWAYS computed
by a symbolic engine (`mathsteps` for equation-solving + simplification, `mathjs`
for evaluation + derivatives) and substituted back into the original problem to
**verify** before it is returned. The LLM never produces the math — it only
writes the plain-language "why" for each already-computed step. When no engine
can solve a problem, a constrained LLM proposes a *candidate* that must still
pass the same substitution gate, or the function returns a `verified:false`
"couldn't verify" state instead of a confident wrong answer. Coverage today:
arithmetic, simplification, linear + quadratic equations, and derivatives solve
fully deterministically; higher-degree/trig equations, systems, and integrals go
through the verified-candidate path; anything unverifiable returns the honest
"couldn't verify" state.

## Prerequisites

- Logged into the Firebase CLI as an account that owns `matheasy-f9b3f`
  (`firebase login`), the **Blaze** plan (already enabled), and Node 22.

## 1. Install dependencies

```bash
cd functions
npm install
```

## 2. Set the secrets

Each value is stored in Cloud Secret Manager, never in the repo:

```bash
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set REVENUECAT_WEBHOOK_TOKEN   # invent a long random string
```

Optional — pick the OpenAI model (defaults to `gpt-4o`). Create `functions/.env`:

```
OPENAI_MODEL=gpt-4o
```

## 3. Deploy

```bash
# from the repo root
firebase deploy --only functions
# and the security rules:
firebase deploy --only firestore:rules
```

The first deploy prints each callable's URL and the webhook URL:
`https://us-central1-matheasy-f9b3f.cloudfunctions.net/revenuecatWebhook`

## 4. Wire RevenueCat → the webhook

RevenueCat dashboard → **Integrations → Webhooks**:

- **URL:** the `revenuecatWebhook` URL from the deploy output.
- **Authorization header:** the exact string you set as `REVENUECAT_WEBHOOK_TOKEN`.

### Required app-side change (user mapping)

The webhook keys the Firestore user off `app_user_id`. Today the app calls
`Purchases.configure(apiKey)` with **no** user id, so RevenueCat uses an
anonymous id the backend can't map. After Firebase auth resolves, the app must:

```dart
await Purchases.logIn(firebaseUid);   // on sign-in / auth-state change
await Purchases.logOut();             // on sign-out
```

Until then, webhook events are acknowledged but skipped (logged as "unmapped").

## Local development (emulators)

```bash
npm run serve     # builds, then starts the functions + firestore + auth emulators
```

Point the Flutter app at the emulators in debug with
`FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001)` (and the
equivalent for Firestore/Auth).

## Firestore shape written by this backend

```
users/{uid}
  entitlement: 'none' | 'pro'          # written only by revenuecatWebhook
  usage: { scans, tutorMessages, practiceQuestions }
  rateLimits: { recognize|solve|tutor|visual|practice: { minEpoch, minCount, dayEpoch, dayCount } }
  subscription: { isPro, productId, store, expiresAtMs, willRenew, ... }
  stats: { xp, problemsSolved, streak, lastActivityAt }
  progressEvents/{eventId}             # append-only, client-written

solveCache/{sha256(canonicalLatex)}    # global, verified-only; { key, payload, createdAt, expiresAt }
```

## Cost & safety hardening (spec §10)

Enforced server-side, before the paid OpenAI call, on every user (client gates
are UX-only and bypassable):

- **Free-tier quota** — `assertWithinQuota` caps lifetime `scans` (5) / tutor
  (20) / practice (10). `users/{uid}` is `allow write: if false`, so counters
  can't be forged.
- **Per-user rate limits** (`RATE_LIMITS` in `config.ts`) — a per-minute burst +
  per-day ceiling on `recognize`/`solve`/`tutor`/`visual`/`practice`, applied to
  free **and** Pro users. This is what caps the otherwise-uncapped
  `solveEquation(countAsScan:false)` path and any retry loop. Over-limit throws
  `resource-exhausted` with `details.rateLimited = true` (the client shows "slow
  down", not the paywall).
- **Image moderation** — `recognizeEquation` screens the photo with the free
  `omni-moderation-latest` model before the paid vision call (fail-closed on a
  flag, fail-open on a moderation outage; the math-only output contract is the
  backstop). Minors-facing / COPPA.
- **Server solve cache** — a repeat problem returns the verified payload with no
  LLM call, keyed by a collision-safe canonical LaTeX (same transforms as the
  client `historyCacheKey`). Scan images are **never** written to Storage.

### One-time console setup

The `solveCache` docs carry an `expiresAt` timestamp for auto-purge. Enable a
Firestore **TTL policy** on that field (once):

```bash
gcloud firestore fields ttls update expiresAt \
  --collection-group=solveCache --enable-ttl
```

Without it the cache still works but is never purged; with it, cached solutions
auto-delete ~30 days after they're written (minimal-retention posture).

## Client call signatures (Flutter `cloud_functions`)

```dart
final fns = FirebaseFunctions.instance;

// scan → LaTeX
final scan = await fns.httpsCallable('recognizeEquation')
    .call({'imageBase64': base64Jpeg, 'mimeType': 'image/jpeg', 'source': 'camera'});

// LaTeX → solution (returns the §4 schema: problemLatex, problemType,
// finalAnswer {latex, plain}, verified, methods[], graph). `verified:false`
// means the answer couldn't be proven — show the "try re-scanning" state.
final solved = await fns.httpsCallable('solveEquation')
    .call({'latex': scan.data['latex']});

// tutor turn
final reply = await fns.httpsCallable('tutorReply')
    .call({'userText': msg, 'history': history, 'problemLatex': latex});
```

On a free-tier cap the callables throw `FirebaseFunctionsException` with
`code == 'resource-exhausted'` and `details.upgradeRequired == true` — map that
to the paywall.
