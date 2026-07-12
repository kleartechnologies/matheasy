# Matheasy — Meta Ads SDK Integration & Attribution Audit

_Production analytics & attribution implementation. Last updated 2026-07-12._

This document is the deliverable for the Meta Ads readiness work: what was
audited, what was implemented, and the exact manual steps left before Meta Ads
Manager can optimize Matheasy campaigns.

> **TL;DR** — The Facebook SDK (`facebook_app_events` 0.30.3) + App Tracking
> Transparency (`app_tracking_transparency` 2.0.7) are installed and wired
> through the app's existing `AnalyticsService` seam, gated so they stay fully
> dormant until real Meta credentials are pasted in. Revenue attribution is
> **server-side via RevenueCat's Conversions API** (the client feeds it the FB
> anonymous id + device identifiers), so purchases are never double-counted.
> `flutter analyze` is clean and **387 tests pass**. Remaining work is external
> config (Meta credentials, RevenueCat dashboard, an AGP bump) — see
> [§10](#10-launch-readiness-score) and [Required manual steps](#required-manual-steps-before-go-live).

> ✅ **COPPA age gate — IMPLEMENTED.** Matheasy has *actual knowledge* of a child
> audience (`functions/src/proxy/scan.ts` "COPPA moderation gate (minors, 8–18)";
> onboarding offers "Primary School"), and COPPA bars collecting persistent
> identifiers (IDFA/GAID/FB anon id) from under-13s for ads — ATT "Allow" is not
> valid child consent. So a neutral **birth-year age gate** now guards the entire
> Meta layer via the `MetaSdk.trackingAllowed` flag (default **false** — fails
> closed). Under-13 **and unknown-age** users get **zero** Meta activity: no
> events, no `activateApp`, no ATT prompt, no advertiser-id/attribution. Only a
> confirmed 13+ user unlocks tracking. See [§6](#6-att-status--implemented) and
> [Age gate](#coppa-age-gate-how-it-works).

---

## 1. Meta SDK Audit (before)

| Area | Status before this work | Evidence |
|---|---|---|
| Meta / Facebook SDK installed | **No** | `pubspec.yaml` had only `firebase_analytics`, `purchases_flutter`, `firebase_crashlytics` — no `facebook_app_events`. |
| Meta SDK configured/initialized | **No** | No `FacebookAppID`/`FacebookClientToken` in `Info.plist`; no `com.facebook.sdk.*` in `AndroidManifest.xml`. |
| iOS ATT | **No** | No `app_tracking_transparency`; no `NSUserTrackingUsageDescription`; no ATT prompt. |
| SKAdNetwork | **No** | No `SKAdNetworkItems` in `Info.plist`. |
| iOS `LSApplicationQueriesSchemes` / fb URL scheme | **No** | Absent from `Info.plist`. |
| Android Meta app id / client token / AD_ID | **No** | Absent; no `res/values/strings.xml`. |
| RevenueCat → Meta attribution | **No** | No `setFBAnonymousID` / `collectDeviceIdentifiers` calls. |
| Deferred deep linking (Meta) | **No** | Only a custom `matheasy://` scheme via GoRouter — unrelated to FB deferred links. |
| Product analytics baseline | **Yes (Firebase only)** | `AnalyticsService` interface + `FirebaseAnalyticsService`, event taxonomy in `AnalyticsEvent`, central `AnalyticsController`. **This was the seam we built on.** |

**Conclusion:** Meta was **not installed, not partially configured, not
initialized** on either platform. The app did, however, already have a clean
analytics abstraction — so the integration was done additively behind it, with
zero changes to any event call site.

---

## 2. Missing Configurations (found → resolved)

| Missing | Resolution |
|---|---|
| Meta SDK dependency | Added `facebook_app_events: ^0.30.3` (FBSDK v18.x). |
| ATT dependency | Added `app_tracking_transparency: ^2.0.7`. |
| Runtime gate for Meta | New `lib/core/config/meta_config.dart` (placeholder sentinel, mirrors `RevenueCatConfig`). |
| iOS Facebook keys | `FacebookAppID`, `FacebookClientToken`, `FacebookDisplayName` in `Info.plist`. |
| iOS ATT string | `NSUserTrackingUsageDescription` in `Info.plist`. |
| iOS SKAdNetwork | `SKAdNetworkItems` (Meta + Audience Network ids). |
| iOS query schemes + fb URL scheme | `LSApplicationQueriesSchemes` + `fb<APP_ID>` in `CFBundleURLTypes`. |
| Android Meta config | `com.facebook.sdk.*` meta-data in `AndroidManifest.xml` + new `res/values/strings.xml`. |
| RevenueCat attribution bridge | New `SubscriptionService.attachAdAttribution()` (FB anon id + device identifiers). |
| Still-open items | Real credentials, RevenueCat CAPI dashboard config, AGP bump, deferred deep linking — see [Required manual steps](#required-manual-steps-before-go-live). |

---

## 3. Implemented Changes

**New files**

- `lib/core/config/meta_config.dart` — the App ID / Client Token gate. Placeholder ⇒ Meta layer is a complete no-op.
- `lib/features/analytics/domain/meta_event.dart` — `MetaEvent` value object, `MetaEventNames` (canonical strings), and the **pure** `MetaEventMapper` (app taxonomy → Meta events; drops revenue events).
- `lib/features/analytics/application/composite_analytics_service.dart` — fans every analytics call to Firebase **and** Meta with per-delegate error isolation.
- `lib/features/analytics/application/meta_analytics_service.dart` — `MetaAnalyticsService` (Meta backend), `MetaSdk` (quarantined SDK handle), `initializeMetaAnalytics()`.
- `lib/features/analytics/application/tracking_consent_controller.dart` — ATT request + consent propagation to Meta + RevenueCat (gated behind the age gate).
- `lib/features/analytics/domain/age_assurance.dart` — pure birth-year → `AgeAssurance` classifier (COPPA threshold, fail-closed).
- `lib/features/analytics/application/age_gate_controller.dart` — persists birth year, drives `MetaSdk.trackingAllowed`.
- `lib/features/analytics/presentation/ad_consent_gate.dart` — invisible shell wrapper: neutral birth-year prompt → consent flow.
- `android/app/src/main/res/values/strings.xml` — Facebook string resources.
- `test/meta_analytics_test.dart` — 20 tests (mapper correctness, **no revenue double-firing**, fan-out isolation, config gate, **age-gate classification + `trackingAllowed`**).

**Modified files**

- `pubspec.yaml` — the two dependencies.
- `lib/bootstrap.dart` — after Firebase/RevenueCat init, composes Meta onto `Analytics.instance` (no-op when unconfigured).
- `lib/features/shell/presentation/app_shell.dart` — wraps the shell in `AdConsentGate` (age gate → ATT), in-app.
- `lib/core/persistence/preferences_store.dart` — persisted `birthYear` + `adConsentPrompted`.
- `lib/features/subscription/application/subscription_service.dart` (+ RevenueCat/Local impls) — `attachAdAttribution()`.
- `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml` — native config above.

**Architecture (one seam, no duplicate firing):**

```
 emit AnalyticsEvent (existing call sites — UNCHANGED)
        │
   analyticsServiceProvider → Analytics.instance
        │
   CompositeAnalyticsService  ── fan out ──┐
        ├─► FirebaseAnalyticsService (all events, unchanged)
        └─► MetaAnalyticsService ─► MetaEventMapper.map(event)  (null ⇒ not forwarded)
                                        └─► FacebookAppEvents.logEvent(...)

 Revenue (Subscribe / StartTrial / Purchase) ─► RevenueCat Conversions API (server) ─► Meta
                                        ▲
   TrackingConsentController: ATT → setAdvertiserIdCollectionEnabled + attachAdAttribution(fbAnonId, $idfa/$gpsAdId)
```

Because each `AnalyticsEvent` maps to **at most one** Meta event and the call
sites are untouched, there is exactly one fire per action per backend.

---

## 4. Event Mapping Table

Client-side = logged by the Meta SDK from the app. Server-side = delivered to
Meta by RevenueCat's Conversions API (no app code / no double count).

| Requested event | Source `AnalyticsEvent` | Meta event | Where | Trigger location |
|---|---|---|---|---|
| Install | — (SDK auto) | `fb_mobile_activate_app` | Client (auto) | FB SDK on first launch (release, post-config) |
| Sign Up | `account_created` | `fb_mobile_complete_registration` (+ `fb_registration_method`) | Client | `auth_controller.dart` interactive sign-in |
| Login | `account_created` | `fb_mobile_complete_registration` | Client | same — **not distinguished from Sign Up** (see gaps) |
| First Scan | `achievement_unlocked{firstScan}` | `FirstScan` (custom, once) | Client | `analytics_controller.dart` on first-scan achievement |
| Problem Solved | `result_viewed` | `fb_mobile_content_view` (+ `fb_content_type`) | Client | `result_controller.dart` |
| Visual Learning Opened | `visual_viewed` | `VisualLearningOpened` (custom) | Client | `visual_solution_controller.dart` |
| Practice Started | `practice_started` | `PracticeStarted` (custom) | Client | `practice_controller.dart` |
| Practice Completed | `practice_completed` | `PracticeCompleted` (custom, `correct`/`total`) | Client | `practice_controller.dart` |
| AI Tutor Opened | `tutor_opened` | `AITutorOpened` (custom) | Client | `tutor_controller.dart` |
| Paywall Viewed | `paywall_viewed` | `PaywallViewed` (custom) | Client | `paywall_controller.dart` |
| Subscription Restored | `subscription_restored` | `SubscriptionRestored` (custom) | Client | `subscription_controller.dart` |
| Trial Started | (RevenueCat) | `StartTrial` | **Server** | RevenueCat CAPI |
| Subscription Started / Purchase Completed | (RevenueCat) | `Subscribe` / `Purchase` | **Server** | RevenueCat CAPI |
| Subscription Renewed | (RevenueCat) | `Subscribe` | **Server** | RevenueCat CAPI (no app open) |
| Subscription Cancelled | — | — | **Not tracked to Meta** | See note below |

> **Paywall Viewed** is mapped to a *custom* `PaywallViewed` (not the standard
> `InitiateCheckout`) on purpose: the paywall auto-opens on scan/tutor/practice
> limits, so an impression is not checkout intent and must not inflate a standard
> funnel event.
>
> **Subscription Cancelled is a genuine gap, by design:** Meta has no
> "cancellation" conversion event and it isn't an ad-optimization signal, so
> RevenueCat's Meta CAPI does **not** send one and no client event is emitted. If
> you want cancellation analytics, add a Firebase-only event off RevenueCat's
> `unsubscribeDetected` status (out of scope for Meta Ads).

Also mapped (bonus activation signal): `onboarding_completed → fb_mobile_tutorial_completion`.

**Deliberately NOT forwarded to Meta** (would add noise or double-count):
`subscription_purchased` (revenue — server owns it), `app_opened`,
`scan_started`, `scan_completed`, `recognition_*`, `question_*`,
`mastery_increased`, `sync_completed`, `profile_edited`, non-`firstScan`
achievements. All of these still flow to **Firebase Analytics** unchanged.

**AEO funnel** (recommended optimization order, high→low volume):
`CompleteRegistration → PaywallViewed → StartTrial → Subscribe`. Meta removed the
8-event limit (June 2025), so custom events (`PaywallViewed`, etc.) are also
processed for optimization.

---

## 5. Revenue Attribution Status — ✅ ready (server-side), pending dashboard config

**Design decision (verified against RevenueCat's Meta Ads docs):** purchases,
trials, and renewals are sent to Meta **server-side by RevenueCat's Conversions
API**, mapped to Meta Standard events (`Subscribe`, `StartTrial`, `Purchase`).
This is strictly better than client-side `logPurchase` because:

1. **No double counting.** RevenueCat's docs: _"remove all client side tracking
   of revenue … tracking purchases with the Meta SDK directly can lead to double
   counting."_ Enforced two ways: (a) the client **never** calls
   `FacebookAppEvents.logPurchase` — `MetaEventMapper` returns `null` for
   `subscription_purchased` (unit-tested); and (b) **automatic app-event logging
   is kept OFF** (`setAutoLogAppEventsEnabled(false)`), which disables the FB
   SDK's *implicit* in-app-purchase observer that would otherwise auto-detect
   StoreKit/Billing purchases and double-count them. The install/session signal
   is emitted explicitly via `activateApp()` instead (no purchase data). Also set
   the Meta dashboard "Log In-App Events Automatically → No".
2. **Renewals & trial conversions** happen with no app open — only the server
   path can report them at all.

The client's job is to make matching possible, done by `attachAdAttribution()`
(called after the ATT decision):

- `Purchases.setFBAnonymousID(fbAnonId)` → RevenueCat's reserved `$fbAnonId`
  (sent as CAPI `anon_id`).
- `Purchases.collectDeviceIdentifiers()` → `$idfa`/`$idfv` (iOS) / `$gpsAdId`
  (Android).

**To finish (dashboard, ~15 min):** In RevenueCat → Integrations → Meta Ads, add
the **Conversions API** integration (Dataset ID + Client Token from Meta Events
Manager). Set Meta app dashboard **"Log In-App Events Automatically → No"** so
the FB SDK's implicit purchase detection can't double-count.

---

## 6. ATT Status — ✅ implemented

- **Prompt exists:** `TrackingConsentController.requestIfNeeded()` calls
  `AppTrackingTransparency.requestTrackingAuthorization()` (only when
  `notDetermined`; reuses the decision otherwise).
- **Explanation:** `NSUserTrackingUsageDescription` (honest, App-Review-safe).
- **Timing (best practice):** **NOT at launch.** Triggered from `AppShell` (the
  first post-auth content screen) via `AdConsentGate`'s post-frame callback, so
  the app is foreground/active — Apple silently no-ops an ATT prompt shown before
  the app is active. It runs **only after the COPPA age gate confirms a 13+
  user** (the neutral birth-year prompt shows first). Release-only + a no-op
  until Meta is configured, so debug builds and a fresh checkout never prompt.
- **Consequences wired:** on the result it sets Meta
  `setAdvertiserIdCollectionEnabled(authorized)`. **A denial is honoured** —
  `attachAdAttribution` (FB anon id + device identifiers to RevenueCat) runs
  **only when the user authorized tracking**; a denied user hands over no
  matching identifiers.

**Recommended optimal trigger point:** for higher opt-in, move the
`requestIfNeeded()` call to just **after the user's first solved problem** (the
"aha" moment). The controller is the single seam — only the call site changes. A
pre-permission priming screen before the system prompt is a further (optional)
opt-in booster.

**Android:** ATT is iOS-only; on Android advertiser-id collection is enabled
(subject to the `AD_ID` permission + the user's Google settings).

### COPPA age gate — how it works

1. **`MetaSdk.trackingAllowed`** (default **false**) is the single flag every Meta
   path checks — event forwarding (`MetaAnalyticsService`), `activateApp()`, the
   ATT prompt, and RevenueCat attribution all short-circuit when it's false. So
   the safe default is *no collection from anyone*.
2. **`AgeGateController`** reads a persisted birth year, classifies it
   (`AgeAssurance`: `unknown` / `child` / `teenOrAdult`, threshold 13,
   implausible years → `unknown`), and sets `trackingAllowed` to true **only** for
   a confirmed `teenOrAdult`.
3. **`AdConsentGate`** (wraps the shell) shows a **neutral birth-year picker**
   once — no mention of ads, no stated eligible age (COPPA-safe, non-leading) —
   then runs the ATT/attribution flow only if the gate opened. A dismissed prompt
   leaves the user untracked and isn't re-nagged.
4. Result: under-13 **and** unknown-age users produce **zero** Meta activity;
   `activateApp` (install) is delayed until a 13+ user is confirmed, so even the
   install ping is never sent for a child.

You should still set the App Store age rating / Play Data-Safety form to match.

---

## 7. SKAdNetwork Status — ✅ complete

`Info.plist` → `SKAdNetworkItems` contains Meta's two ids (source: Meta for
Developers SKAdNetwork docs, corroborated by AppsFlyer/Adjust/Singular):

- `v9wttpbfk9.skadnetwork` — Meta primary/mandatory
- `n38lu8286q.skadnetwork` — Meta Audience Network

Meta owns only these two; the 100+‑id lists MMPs hand out are the *all-networks*
list. If Matheasy later adds other ad networks, merge your MMP's consolidated
`Info.plist` (it already contains these two).

---

## 8. Android Status — ⚠️ configured; one toolchain follow-up

- `AndroidManifest.xml`: `com.facebook.sdk.ApplicationId` / `ClientToken` (from
  `strings.xml`), `AutoLogAppEventsEnabled=false`, `AdvertiserIDCollectionEnabled=false`.
- `AutoInitEnabled` is **intentionally left enabled** — the plugin builds an
  `AppEventsLogger` at startup, which needs the SDK initialized. Placeholder
  credentials are *present* (so the FBSDK "ClientToken must be set" assertion
  doesn't fire) but wrong, and with auto-log off no network calls happen ⇒ no
  launch crash.
- `INTERNET` permission already present. `com.google.android.gms.permission.AD_ID`
  (which the FB SDK would auto-merge) is **stripped by default** via
  `tools:node="remove"` — privacy-safe while Meta is dormant and Families-policy
  friendly. **Delete that override when you go live** with Meta Ads on Android so
  the GAID can be collected (keep it removed if you stay in the Families program).
- Install Referrer: Meta attribution does **not** require the Play Install
  Referrer library; RevenueCat CAPI + FB anon id / GAID cover attribution.

**Follow-up (Android build):** `facebook_app_events` 0.30.2+ expects **AGP 8.13 /
compileSdk 36**; this project is on **AGP 8.11.1** (Gradle wrapper 8.14 already
supports 8.13). Bump `com.android.application` to `8.13.0` in
`android/settings.gradle.kts` and confirm `flutter.compileSdkVersion` ≥ 36 before
the first Android release build. _This was not applied here because the Android
Gradle build was not run in this environment (see verification note)._

---

## 9. iOS Status — ✅ configured (pod install pending on a build machine)

`Info.plist` now has: `FacebookAppID`, `FacebookClientToken`,
`FacebookDisplayName`, `FacebookAutoLogAppEventsEnabled=false`,
`FacebookAdvertiserIDCollectionEnabled=false`, `NSUserTrackingUsageDescription`,
`SKAdNetworkItems`, `LSApplicationQueriesSchemes` (`fbapi`,
`fb-messenger-share-api`, `fbauth2`, `fbshareextension`), and the `fb<APP_ID>`
URL scheme. Existing `matheasy://` + Google URL schemes preserved. `plutil -lint`
passes. No `AppDelegate` change is required for App Events (FBSDK v18 + the
plugin self-initialize). `pod install` must be run on a Mac build machine (not
run here).

---

## 10. Launch Readiness Score

**Code/config readiness: 9/10.** SDK installed, wired, gated, tested; native
config complete and validated; attribution architecture correct and
double-count-safe. The missing point is the items that require **external
accounts/build machines** and can't be done from the repo:

| Blocker | Owner | Effort |
|---|---|---|
| **Meta App ID `1922020571820303` + Client Token are BOTH wired** ⇒ `MetaConfig.isConfigured == true`, so Meta **activates in release builds** (for confirmed 13+ users). Debug/profile stay dormant. | ✅ done | — |
| **COPPA age gate — implemented** (birth-year gate → `MetaSdk.trackingAllowed`, fails closed). | ✅ done | — |
| App Store age-rating / Play Data-Safety declarations match the ad-tracking behaviour | You | 15 min |
| RevenueCat Meta **Conversions API** integration (Dataset ID + token) | You | 15 min |
| AGP 8.11.1 → 8.13.0 + verify Android release build | You | 15 min |
| `pod install` + iOS build/TestFlight smoke test | You | 15 min |
| Deferred deep linking (optional — see below) | You | ~½ day if needed |

After the top four, **Meta Ads Manager can optimize for App Installs,
Registrations, First Scan, Problem Solved, and Subscription Purchases.**

---

## Deferred deep linking (Phase 7) — documented gap

`facebook_app_events` 0.30.3 is **App Events only**; it cannot fetch a deferred
deep link. Matheasy's `matheasy://` scheme (GoRouter + `FlutterDeepLinkingEnabled`)
is a **separate mechanism** — Facebook returns the deferred link out-of-band via
the FB SDK, not through the OS URL path.

To add it (recommended: a small hand-rolled MethodChannel, ~40 lines, no
lightly-maintained third-party wrapper):

1. iOS `AppDelegate.applicationDidBecomeActive` → `AppLinkUtility.fetchDeferredAppLink { url … }` (main thread; returns once).
2. Android `MainActivity` → `AppLinkData.fetchDeferredAppLinkData(this) { … it?.targetUri }`.
3. Bridge the URL over a channel to Dart; map it to a GoRouter location yourself.
4. Gate behind the consent flag; de-dupe (delivered once on first activation).

The `fb<APP_ID>` URL scheme + `LSApplicationQueriesSchemes` scaffolding for this
is already in `Info.plist`.

---

## Event validation checklist (Phase 10)

Run after pasting real credentials (Meta **Events Manager → Test Events**, and
the **App Ads Helper**). Build in **release** (events are release-only by design).

| # | Event | Trigger to perform | Expected in Events Manager | Params |
|---|---|---|---|---|
| 1 | Install / Activate | Fresh install + open | `Activate App` / install | — |
| 2 | CompleteRegistration | Sign in with Google/Apple | `fb_mobile_complete_registration` | `fb_registration_method` |
| 3 | FirstScan | Scan the first problem | `FirstScan` (once) | — |
| 4 | ViewContent | Open a solved result | `fb_mobile_content_view` | `fb_content_type` |
| 5 | VisualLearningOpened | Open Visual Learning | `VisualLearningOpened` | — |
| 6 | PracticeStarted | Start a practice set | `PracticeStarted` | — |
| 7 | PracticeCompleted | Finish a practice set | `PracticeCompleted` | `correct`, `total` |
| 8 | AITutorOpened | Open the AI tutor | `AITutorOpened` | — |
| 9 | InitiateCheckout | Open the paywall | `fb_mobile_initiated_checkout` | — |
| 10 | ATT prompt | Reach the app first time | system ATT dialog appears (not at launch) | — |
| 11 | SubscriptionRestored | Restore a purchase | `SubscriptionRestored` | — |
| 12 | StartTrial / Subscribe / Purchase | Buy monthly/annual, start trial | server events in Events Manager (RevenueCat CAPI), **not** duplicated | value + currency |

Verify in **Events Manager → Diagnostics** there are **no deduplication /
double-count warnings** on `Subscribe`/`Purchase`.

---

## Security review (Phase 11)

| Check | Result |
|---|---|
| No secrets committed | ✅ App ID + Client Token are **placeholders**; the **App Secret is never referenced anywhere** (client token is public and safe to ship, like the RevenueCat SDK key). |
| No debug event leakage | ✅ The **entire Meta layer is release-only**: `initializeMetaAnalytics()` returns null in debug/profile, so the SDK is never installed, ATT never prompts, and no identifiers are collected. Native `FacebookAutoLogAppEventsEnabled=false` too. |
| No duplicate initialization | ✅ `initializeMetaAnalytics()` runs once in bootstrap; `MetaSdk` is a single installed handle. |
| No test app IDs / no unconfigured SDK activity | ✅ `MetaConfig.isConfigured` gate ⇒ placeholder checkout never touches the SDK, never prompts ATT, never sends events. |
| Advertiser id (IDFA/GAID) privacy | ✅ Collection stays OFF (native default + runtime) until ATT authorizes; a **denial is honoured** (no identifiers handed to RevenueCat/Meta). Android `AD_ID` permission stripped by default. |
| No revenue double-counting | ✅ `MetaEventMapper` drops `subscription_purchased`; unit-tested. Revenue is server-side (RevenueCat CAPI) only. |
| COPPA / minors | ✅ A neutral **birth-year age gate** (`AgeGateController` + `AdConsentGate`) drives `MetaSdk.trackingAllowed` (default **false**, fails closed). Under-13/unknown-age users get zero Meta activity (no events, `activateApp`, ATT, or attribution); only confirmed 13+ unlock it. Unit-tested. Still complete the App Store age-rating / Play Data-Safety declarations to match. |

---

## Required manual steps before go-live

1. **Paste the Meta Client Token** (the App ID `1922020571820303` is already
   wired). Set `clientToken` in `lib/core/config/meta_config.dart`,
   `FacebookClientToken` in `ios/Runner/Info.plist`, and `facebook_client_token`
   in `android/.../res/values/strings.xml`. (App Secret must NEVER be used.)
2. **RevenueCat → Meta Conversions API** integration (Dataset ID + Client Token);
   set Meta dashboard "Log In-App Events Automatically → No".
3. **Android:** bump AGP to 8.13.0; verify the release build; confirm compileSdk ≥ 36.
4. **iOS:** `pod install`; build + TestFlight smoke test; confirm ATT prompt & no launch crash.
5. Run the [validation checklist](#event-validation-checklist-phase-10) in Events Manager.
6. (Optional) implement Meta deferred deep linking per the section above.

## Verification performed in this environment

- `flutter analyze` — **clean** (no issues).
- `flutter test` — **379 tests pass** (incl. 12 new Meta tests).
- `plutil -lint Info.plist`, XML parse of `AndroidManifest.xml`/`strings.xml` — **OK**.
- **Not run here** (require a build machine / external accounts): iOS `pod install`
  + Xcode build, Android Gradle release build, on-device Meta event delivery.
