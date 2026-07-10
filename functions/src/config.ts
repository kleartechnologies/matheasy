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
  numiMessages: 20,
  practiceQuestions: 10,
} as const;

export const UNLIMITED = -1;

/** The metered features the server enforces quotas for. */
export type MeteredFeature = keyof typeof FREE_QUOTA;
