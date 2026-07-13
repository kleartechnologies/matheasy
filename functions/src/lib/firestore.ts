/**
 * Firestore access + server-side usage metering.
 *
 * The user document `users/{uid}` is the single source of truth the app reads:
 *   entitlement  : 'none' | 'pro'         (written only by the RevenueCat webhook)
 *   usage        : { scans, tutorMessages, practiceQuestions }  (metered counts)
 *   subscription : { ...snapshot }         (written only by the webhook)
 *   stats        : { xp, streak, ... }     (written only by the aggregation trigger)
 *
 * Quotas are enforced HERE, on the server — the client cannot forge Pro status
 * or reset its counters (see firestore.rules).
 */
import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import {
  FREE_QUOTA,
  MeteredFeature,
  PRO_ENTITLEMENT_ID,
  REVENUECAT_SECRET_KEY,
  UNLIMITED,
} from "../config";

// Initialize the Admin SDK exactly once, even across warm invocations.
if (getApps().length === 0) {
  initializeApp();
}

export const db = getFirestore();

export type EntitlementId = "none" | typeof PRO_ENTITLEMENT_ID;

export function userRef(uid: string) {
  return db.collection("users").doc(uid);
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
      usage: { scans: 0, tutorMessages: 0, practiceQuestions: 0 },
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
 * Assert a free user is still within the quota for [feature] WITHOUT charging.
 * Pro users always pass. Throws `resource-exhausted` when a free user has hit
 * the cap — the app maps that to the paywall.
 *
 * Call this BEFORE the expensive OpenAI call; call [incrementUsage]
 * AFTER it succeeds, so a provider failure never burns a user's allowance.
 * (The check→commit gap allows a benign one-off overrun under heavy
 * concurrency, which is acceptable for a metered learning app.)
 */
export async function assertWithinQuota(
  uid: string,
  feature: MeteredFeature
): Promise<{ isPro: boolean }> {
  const snap = await userRef(uid).get();
  const isPro = snap.get("entitlement") === PRO_ENTITLEMENT_ID;
  if (isPro) return { isPro };

  const limit = FREE_QUOTA[feature];
  const current = Number(snap.get(`usage.${feature}`) ?? 0);
  if (current >= limit) {
    // The webhook-written cache says free + over quota — but RevenueCat webhooks
    // can lag or miss a grant (common in sandbox), which would wrongly paywall a
    // paying user. Re-check with RevenueCat directly before blocking. This stays
    // server-authoritative: it trusts RevenueCat's OWN subscriber record, never
    // a client "I'm Pro" claim. Dormant until REVENUECAT_SECRET_KEY is set.
    if (await isProViaRevenueCat(uid)) return { isPro: true };
    throw new HttpsError(
      "resource-exhausted",
      `Free-tier limit reached for "${feature}" (${limit}). Upgrade to Pro for unlimited access.`,
      { feature, limit, used: current, upgradeRequired: true }
    );
  }
  return { isPro };
}

/**
 * Whether the `pro` entitlement is ACTIVE in a RevenueCat `/subscribers` payload.
 * Pure (no I/O) so it's unit-testable: active iff the entitlement exists and its
 * `expires_date` is null (non-expiring) or in the future.
 */
export function proEntitlementActive(body: unknown, nowMs: number): boolean {
  const subscriber = (body as { subscriber?: { entitlements?: unknown } })
    ?.subscriber;
  const entitlements = subscriber?.entitlements as
    | Record<string, { expires_date?: string | null }>
    | undefined;
  const ent = entitlements?.[PRO_ENTITLEMENT_ID];
  if (!ent || typeof ent !== "object") return false;
  const expires = ent.expires_date;
  if (expires == null) return true; // lifetime / non-expiring grant
  const t = Date.parse(String(expires));
  return Number.isFinite(t) ? t > nowMs : false;
}

/**
 * Server-authoritative Pro check via RevenueCat's REST API — the resilience
 * fallback for a lagged/missed webhook. Reads RevenueCat's own record for [uid]
 * (never a client claim). Returns false — failing CLOSED so the webhook stays
 * the primary path — when the key is unset/placeholder, on any non-OK response,
 * or on any error.
 */
async function isProViaRevenueCat(uid: string): Promise<boolean> {
  let key: string;
  try {
    key = REVENUECAT_SECRET_KEY.value();
  } catch {
    return false; // secret not bound to this function
  }
  if (!key || key.startsWith("REPLACE_")) return false; // dormant until configured
  try {
    const res = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
      { headers: { Authorization: `Bearer ${key}` } }
    );
    if (!res.ok) {
      logger.warn("RevenueCat REST verify non-OK", { uid, status: res.status });
      return false;
    }
    return proEntitlementActive(await res.json(), Date.now());
  } catch (err) {
    logger.warn("RevenueCat REST verify failed", { uid, err: String(err) });
    return false;
  }
}

/**
 * Charge one unit of [feature] against the user's allowance. Returns the new
 * count and remaining allowance (`-1` when unlimited) so the app can update its
 * usage meter without a round-trip.
 */
export async function incrementUsage(
  uid: string,
  feature: MeteredFeature
): Promise<{ used: number; remaining: number }> {
  const ref = userRef(uid);
  await ref.set(
    { usage: { [feature]: FieldValue.increment(1) } },
    { merge: true }
  );
  const snap = await ref.get();
  const isPro = snap.get("entitlement") === PRO_ENTITLEMENT_ID;
  const used = Number(snap.get(`usage.${feature}`) ?? 0);
  const remaining = isPro ? UNLIMITED : Math.max(0, FREE_QUOTA[feature] - used);
  return { used, remaining };
}
