# Matheasy — Anti-Abuse & Free-Usage Protection

> **The goal is not to make abuse impossible.** It is to make creating multiple
> accounts not worth the trouble. Every design decision below is measured against
> that bar, and where the system stops short, this document says so plainly
> rather than implying a wall that isn't there.

**Status:** built, tested (`functions/test/antiAbuse.test.ts`, 77 tests;
`test/anti_abuse_client_test.dart`, 17 tests). Server enforcement is live the
moment `functions/` is deployed; the client half ships with the next app release.

---

## 0. The one rule

**Never trust the client.** The app has a usage meter, a paywall and a set of
gates, and every one of them is *presentation*. The client does not send its
remaining allowance, its entitlement, or its opinion of either — and the server
would ignore all three if it did.

There is exactly one client-supplied value in the whole system: the
**installation ID**. It is a *lookup key*, never a claim. Forging it does not
raise an allowance; the worst it can do is fail to find this device's counter,
leaving the account counter — which the client cannot touch — standing.

---

## 1. The identity chain

Four layers, each one harder to shed than the last. A user only escapes free-tier
metering by shedding **all** of them at once.

| # | Layer | Where it lives | Survives |
|---|-------|----------------|----------|
| 1 | **Installation ID** (Firebase FID) | `installations/{sha256(fid)}` | logout, account switch, new Google/Apple account |
| 2 | **Anonymous Firebase account** | `users/{uid}` | app backgrounding, restarts; merged forward on sign-in |
| 3 | **User account** (Google / Apple) | `users/{uid}` | reinstall, new device, factory reset |
| 4 | **Subscription** (RevenueCat) | `users/{uid}.subscription` + RevenueCat | everything — it *is* the entitlement |

**Layer 1 — Installation ID.** Firebase mints one per app-install. It is *not*
IMEI, MAC address, serial number, or advertising ID — none of those is read,
derived from, or stored anywhere in this codebase, which is what keeps it
compliant with the App Store, Google Play and GDPR. It is resettable by deleting
the app; that is the user's privacy escape hatch, and its cost is bounded by
layer 3. **The raw value is never stored.** The server keys on its SHA-256
(`installationDocId`), so the database holds no device-linked identifier in the
clear.

**Layer 2 — Anonymous account.** A fresh install signs in anonymously at launch,
before anybody touches a sign-in button, so the device has a server identity and
any usage it accrues has somewhere to land. It is deliberately invisible to the
rest of the app: `FirebaseAuthService` maps an anonymous Firebase user to a
`null` `AppUser`, so the router's sign-in wall, `aiBackendReadyProvider` and the
RevenueCat `logIn(uid)` binding all behave exactly as they did before this system
existed.

**Layer 3 — User account.** On interactive sign-in the client sends the anonymous
uid it was holding a moment ago as `previousUid`, and the server merges. It is
safe to send unproven: **a merge takes the maximum of the two ledgers**, so there
is no value of `previousUid` that raises anybody's allowance — the worst a forged
one can do is import somebody else's spent usage onto your own account, which
gives you *less*.

**Layer 4 — Subscription.** RevenueCat is the source of truth. The server mirrors
it (webhook → `users/{uid}.subscription`) and re-derives the entitlement from
that mirror on every request. When a free user is about to be *refused*, and only
then, it also asks RevenueCat directly — so a webhook that was dropped or delayed
never turns a paying customer away — and heals the mirror from the answer.

---

## 2. What actually stops the evasion

Free usage is **lifetime**, and effective usage is

```
used(feature) = max( account counter , installation counter )
```

Not the sum. Max, for two reasons: summing would double-charge an honest person
who has only ever used one device, and max is **idempotent**, so a merge that
replays — a retried callable, a re-linked account — converges instead of
drifting.

That single line is what defeats each of these:

| The move | What happens | Why |
|----------|--------------|-----|
| Sign out, sign back in | Nothing changes | Installation counter is untouched |
| Sign in with a different Google account | Nothing changes | New account, same installation counter |
| Cycle through four accounts | Nothing changes | Every one of them reads the same device counter |
| Delete the app, reinstall | Nothing changes **if signing back into any prior account** | Account counter is server-side |
| Delete the app, reinstall, *and* create a brand-new Google account | **Free usage resets** | See §7 — this is the accepted bar |
| Edit the local meter / clear app data | Nothing changes | The gate reads the database, not the app |
| Replay a `linkIdentity` call | Nothing changes | Max is idempotent |

Each row above is a test in `functions/test/antiAbuse.test.ts`, driven through an
in-memory harness that replays the whole flow rather than asserting on internals.

---

## 3. Where the decision is made

One place: **`functions/src/usage/guard.ts`**. Every paid endpoint calls
`assertUsageAllowed` before spending money and `chargeFeature` after the spend
succeeds. Nothing else in the codebase is allowed to compare a counter to a
limit — a second copy of that comparison would eventually drift, and the drifting
one is the one a student would find.

Order of checks:

1. **Remote Config** — the live limits and flags (compiled defaults on failure)
2. **The account** — `users/{uid}`: lifetime ledger, today's window, subscription
3. **RevenueCat** — but *only* when a free user is about to be refused
4. **The installation** — the device's own ledger, hash-keyed
5. **The decision** — `max(account, device)` against the ceiling, pure and tested

### Failure has a direction, on purpose

- The **device** read is best-effort. If Firestore can't serve it, the request
  proceeds on the account counter alone. Losing that layer costs a few free scans
  to somebody determined; failing closed costs a lesson to somebody innocent.
- The **account** read is load-bearing. If it fails we don't know whether this
  person has anything left, and *neither* guess is acceptable — allowing is an
  open gate, refusing is a false paywall. So it raises `unavailable`: "try
  again", not "you've run out" and not "give us money".

### Refusals don't explain themselves

The student sees a friendly message. The `details` payload carries only what the
app needs to draw the right screen:

| Situation | Code | `details` | App does |
|-----------|------|-----------|----------|
| Free allowance spent | `resource-exhausted` | `{upgradeRequired: true, feature, limit, used}` | Opens the paywall |
| Daily ceiling hit | `resource-exhausted` | `{rateLimited: true, retryAfterSeconds}` | "Try again later" — **never** the paywall |
| Anonymous, and anonymous spend is off | `failed-precondition` | `{signInRequired: true}` | Prompts sign-in |

Which layer said no, what the risk score was, and where the internal thresholds
sit stay in the logs. Nothing in a response teaches somebody what to avoid.

### The practice solve lane (AS-BUILT, V5)

Practice's "Show Solution" / deep-hint path re-enters the real `solveEquation`
pipeline with `countAsScan: false` (client sends `ScanSource.practice`, so
only `manual` entry meters as a scan). This is a **deliberate decision**: the
question was already paid for at generation by the `practiceQuestions` quota,
and charging a second scan for its solution would tax exactly the students who
need help most. The lane is not uncapped — `assertWithinRateLimit(uid,
"solve")` still applies per user, the global verified-solve cache absorbs
repeats (identical practice questions resolve without an OpenAI call), and
solves are lazy (only when a student asks for hint level 3+, Show Solution or
Review My Solution — never preemptively). What it does mean: a scripted client
could run un-metered solves at the rate limit; that sits in §7's "costs real
effort, bounded by rate limits" category, same as re-solves from history.

---

## 4. Firestore schema

```
users/{uid}
  profile        …existing…
  subscription   { entitlement, expiresAtMs, state, ... }   ← RevenueCat mirror
  entitlement    "pro" | null                               ← healed cache
  usage          { scans, tutorMessages, practiceQuestions, animations, visualExplanations }
  usageDaily     { day: <epochDay>, counts: {...} }
  identity       { installationIds: [sha256…], lastInstallationAt }

installations/{sha256(installationId)}      ← SERVER ONLY
  createdAtMs, lastSeenAtMs, updatedAt
  primaryUid            the first uid ever seen here; never overwritten
  uids[]                every uid seen here, newest last (capped at MAX_TRACKED_UIDS = 50)
  anonymousUids[]       the subset that were anonymous when first seen
  accountCount
  lifetimeUsage         { …ledger… }   ← the device counter, the load-bearing field
  daily                 { epoch, counts }
  signInCount
  requestWindow         { epoch, count }   burst signal, per hour
  switchWindow          { epoch, count }   account switches, per UTC day
  lastSwitchAtMs, fastestSwitchMs
  riskScore, riskBand

usage_events/{eventId}                      ← SERVER ONLY, append-only
  action ("charge"|"refused"|"install"|"link"|"merge"), uid,
  installation (HASHED), feature, verdict, isPro, entitlement, used, limit

analytics/daily_{YYYY-MM-DD}                ← SERVER ONLY, pre-aggregated counters

solve_failures/{failureId}                  ← SERVER ONLY (pre-existing)
```

> Naming note: the spec asked for `anonymousUid` / `linkedUid` as single fields.
> They are stored as **lists** (`anonymousUids[]`, `uids[]`) because a device
> legitimately carries more than one of each over its life — a family iPad, a
> student who signs out — and the whole point of the document is to remember
> *all* of them. `primaryUid` is the "linked" account in the singular sense.

`firestore.rules` denies client read **and** write on all four server-only
collections. Read matters as much as write: a readable installation document
would hand a user their own risk score and the list of uids the device has
carried, and a writable one would let them zero the device ledger and make this
entire system decorative.

### What is *not* stored

No raw installation ID. No IMEI, MAC, serial, or advertising ID. No problem text,
image, or answer in the usage trail — a usage event carries a uid, a hashed
installation, a feature name and a verdict, and nothing else.

---

## 5. Remote Config — nothing is hardcoded

Every limit and flag is a Remote Config parameter, read server-side via
`getServerTemplate()` and cached 5 minutes. Flat keys, not one JSON blob, so a
Remote Config **condition** can target a single parameter — which is what makes
"give Malaysian users 8 free scans this month" or a percentage rollout possible
without touching code.

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `limit_scans_free` | 5 | Lifetime free scans |
| `limit_tutor_messages_free` | 20 | Lifetime free tutor messages |
| `limit_practice_questions_free` | 0 | Pro-exclusive today |
| `limit_animations_free` | 0 | Pro-exclusive today |
| `limit_visual_explanations_free` | 0 | Pro-exclusive today |
| `limit_*_free_daily` | 20–60 | Free daily ceilings |
| `limit_*_pro_daily` | 200–600 | Pro daily ceilings — a **cost** control, not a monetisation one |
| `usage_enforcement_enabled` | `true` | Kill switch. **Off still meters and logs**; it only suppresses the refusal |
| `anonymous_usage_enabled` | `true` | Whether signed-out installs may spend free usage |
| `risk_scoring_enabled` | `true` | Whether risk scores are recorded. Never blocks either way |

**A limit of `0` is how "Pro-exclusive" is spelled.** Practice, animations and
visual explanations are gated as an allowance of zero rather than an
`if (!isPro) throw`, so the day the product wants to give free users one visual
explanation as a taste, that is a number in a console — not a deploy.

Parsing is paranoid by design: `-1` is honoured as "no ceiling" because that is
the sentinel the rest of the system speaks, and every other non-integer,
negative or absent value falls back to the compiled default. A typo in the
console must not be able to hand out infinite free scans. `0` and *absent* are
never conflated.

The compiled fallbacks are **today's shipped behaviour, exactly**, so a Remote
Config outage degrades to what the app already does rather than to a surprise in
either direction.

---

## 6. Abuse detection — monitoring only

`identity/risk.ts` scores an installation 0–100 from its own history. Every rule
has the shape *"this is normal up to N, and unusual in proportion to how far past
N it goes"*, capped, so no single signal can max the score alone. A shared family
device trips one rule hard and lands mid-band; a scripted farm trips four and
lands high — which is the only distinction the score is really being asked to
draw.

| Signal | Normal up to | Max points |
|--------|--------------|-----------|
| Accounts on this installation | 4 | 30 |
| Anonymous sessions | 3 | 25 |
| Different accounts in 24h | 3 | 20 |
| Sign-in events | 15 | 15 |
| Metered requests in the last hour | 40 | 20 |
| Two accounts within 60s of each other | — | 20 |

Bands: `normal` (<30) · `watch` (30–59) · `elevated` (≥60).

**The score blocks nothing.** It is not consulted by the guard, it never appears
in a response, and it cannot deny a request. It exists so a human can look at a
dashboard and decide whether a limit needs changing. A classroom of thirty
students sharing one iPad is *supposed* to score high, and is supposed to keep
working.

---

## 7. What this does NOT stop

Stated plainly, because a security document that only lists wins is a marketing
document.

1. **A new device + a brand-new account.** New FID, new uid, nothing to link —
   free usage resets. This is the accepted bar. Closing it needs hardware
   attestation or phone-number verification, and both cost more in lost
   legitimate users than they save.
2. **Reinstall + a brand-new Google/Apple account on the same device.** iOS and
   Android both issue a fresh FID after an uninstall, so nothing links the two
   installs. Costs an attacker a real new account each time.
3. **Emulator / device farms.** Every instance is a genuinely new device by every
   signal available to us. The risk engine will *see* it; nothing automatically
   acts on that.
4. **Sharing one Pro account.** Pro daily ceilings bound the cost, not the
   sharing.
5. **A client that never calls `registerInstallation`.** It just doesn't get the
   device layer — the account layer still enforces. Withholding the installation
   ID cannot *increase* an allowance, only fail to decrease one.

What the system does guarantee is that none of the *cheap* moves work: not
logging out, not switching accounts, not clearing app data, not editing the local
meter, not replaying calls. Everything left on this list costs the attacker real
effort per free scan, which is the whole objective.

---

## 8. Offline

The app caches the last entitlement and the last meter and keeps counting
locally, so it stays usable and honest-looking with no connection. It **cannot
permanently increase usage offline** — nothing is spent until a Cloud Function
charges it, and a metered feature that can't reach the server simply doesn't run.
The local ledger is reconciled with the server's on the next launch by taking the
larger of each counter, which is idempotent and therefore safe to repeat.

---

## 9. Analytics

`usage_events/` is the append-only trail (uid, hashed installation, feature,
verdict) and `analytics/daily_{date}` holds pre-aggregated counters, both
export-friendly to BigQuery. Between them they answer: conversion to Pro, free
usage completion rate, upgrade rate, average scans per user, retention,
per-feature usage, anonymous→account conversion, and which features are most
used. Writes are fire-and-forget and never fail a user's request — a lost
analytics row is not worth a failed scan.

---

## 10. Where the code is

| Deliverable | File |
|-------------|------|
| Usage Manager (server) | `functions/src/usage/ledger.ts`, `usage/features.ts` |
| Usage Manager (client meter) | `lib/features/subscription/application/server_usage_controller.dart` |
| Installation Manager | `functions/src/identity/installations.ts` |
| Anonymous Account Manager | `lib/features/auth/application/firebase_auth_service.dart`, `identity_controller.dart` |
| Account Merge Service | `functions/src/identity/merge.ts` |
| Verification Layer | `functions/src/usage/guard.ts` |
| Firestore schema + rules | this doc §4, `firestore.rules` |
| RevenueCat verification | `functions/src/billing/entitlement.ts` |
| Remote Config | `functions/src/usage/limits.ts` |
| Abuse detection | `functions/src/identity/risk.ts` |
| Analytics | `functions/src/usage/events.ts` |
| Callables | `functions/src/proxy/usage.ts` |
| Client identity wiring | `lib/core/security/installation_identity.dart`, `lib/core/backend/identity_service.dart` |
| Tests | `functions/test/antiAbuse.test.ts`, `test/anti_abuse_client_test.dart` |

### Test-style note

`functions/test/` contains **no `vi.mock`**, and this subsystem holds the line:
every decision is a pure function (`decideUsage`, `planMerge`, `assessRisk`,
`applyIdentityEvent`, `resolveEntitlement`, `parseLimits`) with Firestore I/O as
a thin shell around it. The evasion scenarios in §2 run against an in-memory
world that replays the real call sequence, so they test behaviour rather than
implementation.
