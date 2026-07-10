# Matheasy — Cloud Functions backend

The server-side backend for Matheasy. Three concerns:

| Function | Type | What it does |
| --- | --- | --- |
| `recognizeEquation` | callable | Mathpix OCR proxy — photo → LaTeX. Meters the free `scans` quota. |
| `solveEquation` | callable | OpenAI solver — LaTeX → full worked solution (`ResultData` shape). |
| `tutorReply` | callable | OpenAI tutor (Numi) — chat history → reply + suggestions. Meters `numiMessages`. |
| `revenuecatWebhook` | HTTPS | Syncs RevenueCat entitlement + subscription state into Firestore. |
| `aggregateProgress` | Firestore trigger | Rolls `progressEvents` up into aggregate `stats`. |

**Why this exists:** the Mathpix and OpenAI API keys must never ship inside the
app. The client calls these functions; the functions hold the secrets (in Cloud
Secret Manager) and enforce the free-tier quotas server-side, so paid status and
usage counts can't be forged on-device.

## Prerequisites

- Logged into the Firebase CLI as an account that owns `matheasy-873e2`
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
firebase functions:secrets:set MATHPIX_APP_ID
firebase functions:secrets:set MATHPIX_APP_KEY
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
`https://us-central1-matheasy-873e2.cloudfunctions.net/revenuecatWebhook`

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
  usage: { scans, numiMessages, practiceQuestions }
  subscription: { isPro, productId, store, expiresAtMs, willRenew, ... }
  stats: { xp, problemsSolved, streak, lastActivityAt }
  progressEvents/{eventId}             # append-only, client-written
```

## Client call signatures (Flutter `cloud_functions`)

```dart
final fns = FirebaseFunctions.instance;

// scan → LaTeX
final scan = await fns.httpsCallable('recognizeEquation')
    .call({'imageBase64': base64Jpeg, 'mimeType': 'image/jpeg', 'source': 'camera'});

// LaTeX → solution
final solved = await fns.httpsCallable('solveEquation')
    .call({'latex': scan.data['latex']});

// tutor turn
final reply = await fns.httpsCallable('tutorReply')
    .call({'userText': msg, 'history': history, 'problemLatex': latex});
```

On a free-tier cap the callables throw `FirebaseFunctionsException` with
`code == 'resource-exhausted'` and `details.upgradeRequired == true` — map that
to the paywall.
