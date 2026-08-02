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
 * The OpenAI models powering the pipeline, split by JOB (see `lib/models.ts`).
 *
 * The product rule is **accuracy > speed > cost**: every workflow where a wrong
 * output would reach a student as maths — reading the photo, correcting the OCR,
 * interpreting a geometry figure, proposing a candidate solution, generating
 * practice, reading handwritten work — runs on the REASONING tier. The tiers the
 * student only ever sees as *prose* about already-verified maths (Numi's replies,
 * the teaching layer) run on the NARRATION tier, which is cheaper and lower
 * latency without touching a single number.
 *
 * Both are deploy-time parameters so a model bump is a config change, not a code
 * change. Set them in `.env` (see `functions/README.md`) or at deploy:
 *   OPENAI_MODEL_REASONING=gpt-5.6-sol
 *   OPENAI_MODEL_NARRATION=gpt-5.6-terra
 *
 * ROLLBACK: setting BOTH to `gpt-4o` restores the pre-migration behaviour
 * exactly — `lib/models.ts` detects a legacy sampling model and sends the old
 * `temperature` + `max_tokens` shape (see `isReasoningModel`).
 */
/**
 * The tier defaults, as literals.
 *
 * These are NOT redundant with the `default:` below. A `defineString` default is
 * only used by the deploy tooling to seed the value — at RUNTIME `.value()`
 * returns the EMPTY STRING when the variable is absent from the environment, it
 * does not fall back. Relying on `default:` alone would ship `model: ""` and 400
 * every call, so `lib/models.ts` falls back to these constants instead.
 */
export const DEFAULT_MODEL_REASONING = "gpt-5.6-sol";
export const DEFAULT_MODEL_NARRATION = "gpt-5.6-terra";

export const OPENAI_MODEL_REASONING = defineString("OPENAI_MODEL_REASONING", {
  default: DEFAULT_MODEL_REASONING,
});

export const OPENAI_MODEL_NARRATION = defineString("OPENAI_MODEL_NARRATION", {
  default: DEFAULT_MODEL_NARRATION,
});

/**
 * DEPRECATED single-model parameter, kept only as an escape hatch: when set to a
 * non-empty value it OVERRIDES both tiers above. Leave it unset. It exists so a
 * live incident can be pinned to one known-good model with one env var and a
 * redeploy, without editing code.
 */
export const OPENAI_MODEL_OVERRIDE = defineString("OPENAI_MODEL", {
  default: "",
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

/** Whether server-side teaching enrichment is on. Phase 0: always false.
 *
 * COST NOTE: when ON, a fresh (cache-miss) verified solve makes TWO OpenAI calls —
 * `narrateDeterministic` AND the teaching enrichment — but `RATE_LIMITS.solve` is
 * spent once per REQUEST, so the effective per-user OpenAI-call ceiling roughly
 * doubles on cache-miss solves. Repeats are $0 (both the verified core and the
 * teaching layer are cached; deterministic enrich rejections are negative-cached).
 * The small-% flag rollout + the solve rate limit bound the exposure; a per-token
 * daily circuit-breaker is a planned follow-up. */
export function teachingEnabled(): boolean {
  return TEACHING_ENABLED.value() === "true";
}

/**
 * The kill switch for the additive animation-schema sidecar. OFF by default: the
 * solver attaches NO `animationSchema` to the payload, so nothing changes vs today.
 * Flip to "true" at deploy time (or via .env) to attach the schema on fresh
 * mathsteps-path solves — the verified `solve→verify` path is untouched either way,
 * so this only gates the ADDITIVE, strictly non-load-bearing sidecar. Rollback is
 * asymmetric by design: OFF actively strips any sidecar on egress (even one a cache
 * entry still carries from when it was ON), ON is lazy (no cache backfill).
 *   set ANIMATION_SCHEMA_ENABLED=true in .env or at deploy.
 */
export const ANIMATION_SCHEMA_ENABLED = defineString("ANIMATION_SCHEMA_ENABLED", {
  default: "false",
});

/** Whether the animation-schema sidecar is attached. Default OFF. */
export function animationSchemaEnabled(): boolean {
  return ANIMATION_SCHEMA_ENABLED.value() === "true";
}

/**
 * The kill switch for the model-backed half of the educational quality gate.
 *
 * ON (the default) an explanation is read by a judge before it is shown, and
 * anything below the bar is regenerated. OFF collapses the gate to its
 * deterministic checks — the structural half still runs and still blocks, so a
 * lesson that contradicts the verified answer or points at a highlight nobody
 * drew is rejected either way. The lever exists for cost and for latency
 * incidents, not for quality: turning it off makes the gate cheaper, never
 * absent.
 *   set QUALITY_JUDGE_ENABLED=false in .env or at deploy.
 */
export const QUALITY_JUDGE_ENABLED = defineString("QUALITY_JUDGE_ENABLED", {
  default: "true",
});

/** Whether the LLM judge runs. Default ON; the deterministic checks always run. */
export function qualityJudgeEnabled(): boolean {
  return QUALITY_JUDGE_ENABLED.value() !== "false";
}

/**
 * How many times an explanation may be regenerated before the layer gives up.
 *
 * Giving up means showing NO explanation — never a bad one, and never a
 * different answer. The verified solution has already been proven and is on
 * screen regardless; the teaching layer is additive, so its worst case is the
 * app as it was before this layer existed.
 */
export const QUALITY_MAX_ATTEMPTS = defineString("QUALITY_MAX_ATTEMPTS", {
  default: "3",
});

/** Attempts allowed per explanation, clamped to a sane 1-5. */
export function qualityMaxAttempts(): number {
  const parsed = Number.parseInt(QUALITY_MAX_ATTEMPTS.value(), 10);
  if (!Number.isFinite(parsed)) return 3;
  return Math.max(1, Math.min(5, parsed));
}

/**
 * The kill switch for the two-pass scan pipeline (preprocess → OCR → vision).
 *
 * ON (the default) the scanner enhances the photo, runs a dedicated OCR
 * transcription pass, and hands pass 2 both images plus that draft reading. OFF
 * collapses to the original single-pass call on the raw photo — the pre-rebuild
 * behaviour — which is the lever to pull if the second pass ever proves to cost
 * more latency than it buys in accuracy.
 *
 * COST: ON, a cache-miss scan makes TWO vision calls instead of one. Both are
 * metered as a single `recognize` request, so as with teaching enrichment the
 * per-user OpenAI-call ceiling is double the request ceiling.
 *   set SCAN_PIPELINE_ENABLED=false in .env or at deploy to disable.
 */
export const SCAN_PIPELINE_ENABLED = defineString("SCAN_PIPELINE_ENABLED", {
  default: "true",
});

/** Whether the two-pass scan pipeline is on. Defaults to ON when unset. */
export function scanPipelineEnabled(): boolean {
  // Note the inverted read: an unset param resolves to "" at runtime (a
  // `default:` only seeds the deploy prompt), and the default for this flag is
  // ON — so anything other than an explicit "false" means on.
  return SCAN_PIPELINE_ENABLED.value().trim().toLowerCase() !== "false";
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
 * Free-tier lifetime allowances and the metered feature list.
 *
 * These moved to `usage/features.ts` when limits became Remote Config-driven,
 * and are re-exported here only so older imports keep resolving. There is one
 * catalogue and one set of defaults; do not add a feature or a number here.
 * The COMPILED values in `usage/features.ts` are just the fallback — the live
 * ceilings come from Remote Config via `usage/limits.ts`.
 */
export {
  DEFAULT_FREE_LIMITS as FREE_QUOTA,
  UNLIMITED,
  type MeteredFeature,
} from "./usage/features";

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
  // Teaching enrichment — a separate on-demand call per result view (decoupled
  // from solve so it never adds latency to the answer). Cache-first, so most
  // views cost nothing; the ceiling caps a retry loop / cold-cache burst.
  teach: { perMinute: 30, perDay: 400 },
  // Account linking. Free to call and it writes to two documents, so it needs a
  // ceiling — but a legitimate student may genuinely sign in and out a few times
  // while working out which account they used, so the ceiling is loose.
  identity: { perMinute: 10, perDay: 60 },
} as const;

/** The paid endpoints the server rate-limits per user. */
export type RateLimitedAction = keyof typeof RATE_LIMITS;
