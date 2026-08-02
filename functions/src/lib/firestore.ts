/**
 * Firestore access + the metering entry points the endpoints call.
 *
 * The user document `users/{uid}` is the single source of truth the app reads:
 *   entitlement  : 'none' | 'pro'          (written only by the RevenueCat webhook)
 *   usage        : { scans, tutorMessages, ... }   (lifetime metered counts)
 *   usageDaily   : { epoch, counts }        (today's window, reset on rollover)
 *   subscription : { ...snapshot }          (written only by the webhook)
 *   identity     : { installationIds, mergedFrom, mergedInto }
 *   stats        : { xp, streak, ... }      (written only by the aggregation trigger)
 *
 * THE DECISIONS ARE NOT HERE. Since the anti-abuse work this file is a thin
 * shell: `assertWithinQuota` and `incrementUsage` keep their names and their
 * call sites, and delegate to `usage/guard.ts`, which is the one place that
 * compares a counter to a limit. That indirection exists so there is exactly one
 * such place — two would drift, and the drifting one would be the one a student
 * finds. See the header of `usage/guard.ts` for the actual rules.
 */
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

import { PRO_ENTITLEMENT_ID } from "../config";
import { proActiveInSubscriber } from "../billing/entitlement";
import { MeteredFeature, emptyLedger } from "../usage/features";
import { GuardContext, assertUsageAllowed, chargeFeature } from "../usage/guard";
import { db, userRef } from "./db";

export { db, userRef };

export type EntitlementId = "none" | typeof PRO_ENTITLEMENT_ID;

/** The identity an endpoint knows about its caller, beyond the uid. */
export interface RequestIdentity {
  /** The client-sent Firebase installation ID, if any. A lookup key, not a claim. */
  installationId?: unknown;
  /** Whether the caller is a signed-out Firebase anonymous account. */
  isAnonymous?: boolean;
}

/**
 * Ensure a user document exists, seeding the server-managed fields. Called
 * lazily on the first authenticated request so we don't need an Auth
 * background trigger (which would require Identity Platform).
 */
export async function ensureUserDoc(uid: string): Promise<void> {
  const ref = userRef(uid);
  const snap = await ref.get();
  if (snap.exists) return;
  await ref.set(
    {
      entitlement: "none",
      usage: emptyLedger(),
      stats: { xp: 0, streak: 0, problemsSolved: 0 },
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  logger.info("Provisioned user doc", { uid });
}

/** Read the current entitlement, defaulting to the free tier. */
export async function getEntitlement(uid: string): Promise<EntitlementId> {
  const snap = await userRef(uid).get();
  const value = snap.get("entitlement");
  return value === PRO_ENTITLEMENT_ID ? PRO_ENTITLEMENT_ID : "none";
}

/**
 * Assert the caller may spend one unit of [feature] WITHOUT charging. Pro users
 * pass on the lifetime ceiling; nobody passes the daily one. Throws the error
 * the app already maps to the paywall.
 *
 * Call this BEFORE the expensive OpenAI call and [incrementUsage] AFTER it
 * succeeds, so a provider failure never burns a student's allowance. (The
 * check→commit gap allows a benign one-off overrun under heavy concurrency,
 * which is acceptable for a metered learning app.)
 */
export async function assertWithinQuota(
  uid: string,
  feature: MeteredFeature,
  identity: RequestIdentity = {}
): Promise<{ isPro: boolean }> {
  const verification = await assertUsageAllowed(context(uid, feature, identity));
  return { isPro: verification.decision.isPro };
}

/**
 * Charge one unit of [feature] against the caller's allowance, on the account
 * AND on the device. Returns the new effective count and the remaining
 * allowance (`-1` when unlimited) so the app can update its meter without a
 * round-trip.
 */
export async function incrementUsage(
  uid: string,
  feature: MeteredFeature,
  identity: RequestIdentity = {}
): Promise<{ used: number; remaining: number }> {
  return chargeFeature(context(uid, feature, identity));
}

/**
 * Whether the `pro` entitlement is active in a RevenueCat `/subscribers`
 * payload. Kept here as the name the webhook and its tests already use; the
 * implementation — including the store grace window — lives in
 * `billing/entitlement.ts`.
 */
export function proEntitlementActive(body: unknown, nowMs: number): boolean {
  return proActiveInSubscriber(body, nowMs);
}

function context(
  uid: string,
  feature: MeteredFeature,
  identity: RequestIdentity
): GuardContext {
  return {
    uid,
    feature,
    installationId: identity.installationId,
    isAnonymous: identity.isAnonymous,
  };
}

// ---- Solve-failure analytics (turn "couldn't verify" into prioritizable data)

/**
 * Coarse math domain for a classifier `problemType`, so failures roll up to a
 * topic even though `classify` only labels the types it knows.
 */
export function topicForProblemType(problemType: string): string {
  switch (problemType) {
    case "arithmetic":
    case "expression":
    case "linear_equation":
    case "quadratic_equation":
    case "polynomial_equation":
    case "exponential_equation":
    case "system_of_equations":
    case "simultaneous_equations":
      return "algebra";
    case "trigonometric_equation":
      return "trigonometry";
    case "derivative":
    case "integral":
    case "definite_integral":
      return "calculus";
    default:
      return "other";
  }
}

export interface SolveFailure {
  latex: string;
  problemType: string; // classify's problemType (the classification)
  strategy: string; // equation | simplify | arithmetic | derivative | llm_candidate
  verifyMode: string; // substitution | derivative_back | trig | ... | none
  reason: string; // no_verify_mode | llm_no_candidate | verify_gate_failed
}

/**
 * Records a solve that returned `verified:false`, so real-world gaps are
 * measured instead of guessed. Writes BOTH a raw drill-down doc
 * (`solve_failures/*`) and increments a single aggregate dashboard doc
 * (`analytics/solveFailures`) by topic / problemType / reason.
 *
 * Deliberately ANONYMOUS — no uid — and the equation is length-capped: the
 * audience includes minors, and the analytic question is "which TYPES fail",
 * not "who". Best-effort: never throws into the request path.
 */
export async function recordSolveFailure(f: SolveFailure): Promise<void> {
  try {
    const topic = topicForProblemType(f.problemType);
    const latex = f.latex.slice(0, 400);
    const batch = db.batch();
    batch.set(db.collection("solve_failures").doc(), {
      latex,
      topic,
      problemType: f.problemType,
      strategy: f.strategy,
      verifyMode: f.verifyMode,
      reason: f.reason,
      createdAt: FieldValue.serverTimestamp(),
    });
    batch.set(
      db.doc("analytics/solveFailures"),
      {
        total: FieldValue.increment(1),
        byTopic: { [topic]: FieldValue.increment(1) },
        byProblemType: { [f.problemType]: FieldValue.increment(1) },
        byReason: { [f.reason]: FieldValue.increment(1) },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await batch.commit();
  } catch (err) {
    logger.warn("recordSolveFailure failed", { err: String(err) });
  }
}
