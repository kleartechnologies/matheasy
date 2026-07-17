/**
 * Central configuration for the Matheasy Functions backend.
 *
 * Secrets are declared with `defineSecret` (Cloud Secret Manager) so they are
 * NEVER checked into the repo or shipped in the app bundle — the whole reason
 * this backend exists. Set each one with:
 *
 *   firebase functions:secrets:set OPENAI_API_KEY
 *   firebase functions:secrets:set REVENUECAT_WEBHOOK_TOKEN
 *
 * A function only receives a secret's value if it lists it in `secrets: [...]`.
 */
import { defineSecret, defineString } from "firebase-functions/params";
import { setGlobalOptions } from "firebase-functions/v2";

// --- Secrets (values live in Cloud Secret Manager, not in code) -------------
export const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
/** Shared secret validated against the RevenueCat webhook Authorization header. */
export const REVENUECAT_WEBHOOK_TOKEN = defineSecret("REVENUECAT_WEBHOOK_TOKEN");
/**
 * RevenueCat SECRET (REST) API key — server-only, from RevenueCat → API keys →
 * Secret keys. Powers the quota gate's on-demand Pro verification when the
 * webhook-written entitlement lags/misses. Optional: leave unset (or a
 * `REPLACE_` placeholder) to keep the fallback dormant and rely on the webhook.
 */
export const REVENUECAT_SECRET_KEY = defineSecret("REVENUECAT_SECRET_KEY");

// --- Parameters (non-secret, overridable at deploy time) --------------------
/**
 * The OpenAI model powering the solver + tutor. Kept as a parameter so you can
 * bump the model without a code change:
 *   firebase deploy --only functions  (prompts for the value the first time)
 * or set a default in .env — see functions/README.md.
 */
export const OPENAI_MODEL = defineString("OPENAI_MODEL", {
  default: "gpt-4o",
});

/**
 * Firebase uid allowed to read the solve-failure analytics report. Empty (the
 * default) denies everyone — set it to your uid to enable:
 *   firebase functions:secrets  N/A — it's a param: set ADMIN_UID in .env or at deploy.
 */
export const ADMIN_UID = defineString("ADMIN_UID", { default: "" });

/**
 * The kill switch for the v2 teaching engine (spec §10). OFF by default: the
 * solver emits `schemaVersion:2` but attaches NO `teaching` layer, so the client
 * renders today's UI. Flip to "true" at deploy time (or ramp in Phase 1) to turn
 * on server-side teaching enrichment — the verified `solve→verify` path is
 * untouched either way, so this only gates the ADDITIVE narration layer.
 *   set TEACHING_ENABLED=true in .env or at deploy.
 */
export const TEACHING_ENABLED = defineString("TEACHING_ENABLED", {
  default: "false",
});

/** Whether server-side teaching enrichment is on. Phase 0: always false. */
export function teachingEnabled(): boolean {
  return TEACHING_ENABLED.value() === "true";
}

// The region all functions run in. Keep it close to your users / Firestore.
export const REGION = "us-central1";

setGlobalOptions({
  region: REGION,
  maxInstances: 10,
});

// --- Product constants (mirror the Flutter app's Stage 11 contract) ---------
/** RevenueCat entitlement id — matches `RevenueCatConfig.entitlementId`. */
export const PRO_ENTITLEMENT_ID = "pro";

export const PRODUCT_MONTHLY = "matheasy_pro_monthly";
export const PRODUCT_ANNUAL = "matheasy_pro_annual";

/**
 * Free-tier lifetime allowances, per metered feature. Mirrors
 * `UsageQuota.free` in the Flutter app so client and server agree. `-1` means
 * uncapped (the Pro tier).
 */
export const FREE_QUOTA = {
  scans: 5,
  tutorMessages: 20,
  practiceQuestions: 10,
} as const;

export const UNLIMITED = -1;

/** The metered features the server enforces quotas for. */
export type MeteredFeature = keyof typeof FREE_QUOTA;

/**
 * Per-user, server-enforced RATE LIMITS on the paid OpenAI endpoints (spec §10).
 *
 * These are the cost/abuse backstop that the free-tier quota can't provide:
 *   • the free `scans` quota is a lifetime total, not a rate — it can't stop a
 *     retry-loop bug from firing thousands of calls in a minute;
 *   • Pro users are quota-unlimited, so WITHOUT a rate limit a single looping or
 *     compromised Pro account could run an unbounded OpenAI bill;
 *   • `solveEquation(countAsScan:false)` skips the quota check (a scan already
 *     paid for OCR-sourced problems) yet still makes a paid LLM narration call —
 *     the rate limit is what caps that otherwise-uncapped path.
 *
 * Applied to EVERY user (free and Pro) BEFORE the paid call. The ceilings are
 * generous for a human (a person can't scan 20 problems in a minute) but tight
 * for a script/loop. A `perMinute` catches bursts; a `perDay` caps slow drip.
 */
export const RATE_LIMITS = {
  recognize: { perMinute: 20, perDay: 300 },
  solve: { perMinute: 30, perDay: 400 },
  tutor: { perMinute: 30, perDay: 300 },
  visual: { perMinute: 15, perDay: 100 },
  practice: { perMinute: 20, perDay: 200 },
} as const;

/** The paid endpoints the server rate-limits per user. */
export type RateLimitedAction = keyof typeof RATE_LIMITS;
