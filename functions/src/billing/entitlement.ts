/**
 * Layer 4 — is this person paying, right now, according to somebody other than
 * their phone?
 *
 * RevenueCat is the source of truth. This file turns RevenueCat's view into the
 * single boolean the usage guard needs, and it does that from two inputs, in
 * this order of preference:
 *
 *  1. The subscription snapshot the webhook wrote into `users/{uid}`. Free, no
 *     latency, and correct almost always.
 *  2. RevenueCat's REST API, consulted only when the snapshot says NO and the
 *     student is about to be refused. Webhooks lag, get dropped, and behave
 *     erratically in sandbox; asking directly before showing a paywall to
 *     somebody who has already paid is worth one HTTP call.
 *
 * A local cache on the device is never consulted for a grant. It is fine for
 * the app to draw an unlocked UI from its own cache — that is presentation —
 * but the server decides whether the OpenAI call happens.
 *
 * THE STATES THAT ARE NOT "ACTIVE" OR "EXPIRED"
 *
 * Most of the bugs in subscription code live between those two words:
 *
 *  - CANCELLED means auto-renew is off. The student has paid through to the
 *    expiry date and must keep Pro until then. Treating cancel as revoke is the
 *    classic way to steal access somebody bought.
 *  - BILLING RETRY / GRACE PERIOD means the card failed and the store is trying
 *    again. Both stores keep the subscription alive during this window and so
 *    do we; taking a student's homework tool away over a temporarily declined
 *    card is a support ticket and a refund, not a save.
 *  - PAUSED (Play) and REFUNDED are real revocations, immediately.
 */
import { logger } from "firebase-functions/v2";

import { PRO_ENTITLEMENT_ID, REVENUECAT_SECRET_KEY } from "../config";

/** What the server thinks of a subscription, in one word. */
export type EntitlementState =
  /** Paid and renewing. */
  | "active"
  /** Paid, auto-renew off, still inside the paid period. */
  | "cancelled"
  /** Payment failed; the store is retrying inside its grace window. */
  | "grace"
  /** Was paid, no longer is. */
  | "expired"
  /** Never paid. */
  | "none";

export interface EntitlementView {
  state: EntitlementState;
  /** The one thing the guard needs: does this request get Pro treatment? */
  isPro: boolean;
  expiresAtMs: number | null;
  willRenew: boolean;
  hasBillingIssue: boolean;
}

/** The webhook-written snapshot, as stored. Every field optional by design. */
export interface SubscriptionSnapshot {
  isPro?: boolean;
  expiresAtMs?: number | null;
  willRenew?: boolean;
  unsubscribeDetected?: boolean;
  hasBillingIssue?: boolean;
  lastEventType?: string | null;
  periodType?: string | null;
}

/**
 * How long past expiry a billing-retry subscription still counts as Pro.
 *
 * Apple's billing grace period is up to 16 days and Google's up to 30; the
 * webhook that would tell us the retry succeeded may itself be the thing that
 * is late. Sixteen days is the shorter of the two store windows — long enough
 * to cover a real retry, short enough that a genuinely dead subscription is not
 * free Pro for a month.
 */
export const GRACE_WINDOW_MS = 16 * 24 * 60 * 60 * 1000;

/**
 * Resolve a stored snapshot into a state. PURE.
 *
 * The precedence is deliberate: an explicit expiry in the past beats an
 * `isPro: true` flag, because the flag is a cached opinion from whenever the
 * last webhook arrived and the date is a fact. The exception is a billing
 * issue, which is exactly the case where "expired" is the wrong reading.
 */
export function resolveEntitlement(
  snapshot: SubscriptionSnapshot | undefined,
  entitlementField: unknown,
  now: number
): EntitlementView {
  const sub = snapshot ?? {};
  const expiresAtMs = numberOrNull(sub.expiresAtMs);
  const willRenew = sub.willRenew === true;
  const hasBillingIssue = sub.hasBillingIssue === true;
  const flaggedPro = entitlementField === PRO_ENTITLEMENT_ID || sub.isPro === true;

  const view = (state: EntitlementState, isPro: boolean): EntitlementView => ({
    state,
    isPro,
    expiresAtMs,
    willRenew,
    hasBillingIssue,
  });

  if (!flaggedPro && expiresAtMs === null) return view("none", false);

  // No expiry recorded (lifetime grant, promotional, or an event type that
  // omits the date) — trust the flag.
  if (expiresAtMs === null) {
    return flaggedPro ? view(willRenew ? "active" : "cancelled", true) : view("none", false);
  }

  if (expiresAtMs > now) {
    // Inside the paid period. Auto-renew being off does NOT reduce access.
    if (hasBillingIssue) return view("grace", true);
    return view(willRenew ? "active" : "cancelled", true);
  }

  // Past expiry. The only reason to still grant is an in-flight billing retry.
  if (hasBillingIssue && now - expiresAtMs <= GRACE_WINDOW_MS) {
    return view("grace", true);
  }

  return view(flaggedPro || expiresAtMs !== null ? "expired" : "none", false);
}

// ---------------------------------------------------------------------------
// The direct check
// ---------------------------------------------------------------------------

/**
 * Whether the `pro` entitlement is ACTIVE in a RevenueCat `/subscribers`
 * payload, allowing for the store's grace window. PURE.
 *
 * `grace_period_expires_date` is RevenueCat's own field for exactly the case
 * above; when it is present and in the future the subscriber still has access
 * even though `expires_date` has passed.
 */
export function proActiveInSubscriber(body: unknown, now: number): boolean {
  const entitlements = (body as {
    subscriber?: { entitlements?: Record<string, unknown> };
  })?.subscriber?.entitlements;
  const raw = entitlements?.[PRO_ENTITLEMENT_ID] as
    | { expires_date?: string | null; grace_period_expires_date?: string | null }
    | undefined;
  if (!raw || typeof raw !== "object") return false;

  const grace = parseDate(raw.grace_period_expires_date);
  if (grace !== null && grace > now) return true;

  const expires = raw.expires_date;
  if (expires === null || expires === undefined) return true; // lifetime grant
  const at = parseDate(expires);
  return at !== null && at > now;
}

/**
 * Ask RevenueCat directly. Returns null when the answer is unknown — which is
 * NOT the same as "not Pro", and the caller must treat it as such.
 *
 * Dormant until `REVENUECAT_SECRET_KEY` is configured, so an unconfigured
 * environment behaves exactly as it did before this file existed.
 */
export async function proViaRevenueCat(
  uid: string,
  now: number = Date.now()
): Promise<boolean | null> {
  let key: string;
  try {
    key = REVENUECAT_SECRET_KEY.value();
  } catch {
    return null; // the secret is not bound to this function
  }
  if (!key || key.startsWith("REPLACE_")) return null;

  try {
    const res = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
      { headers: { Authorization: `Bearer ${key}` } }
    );
    if (!res.ok) {
      logger.warn("RevenueCat REST verify non-OK", { uid, status: res.status });
      return null;
    }
    return proActiveInSubscriber(await res.json(), now);
  } catch (err) {
    logger.warn("RevenueCat REST verify failed", { uid, err: String(err) });
    return null;
  }
}

// ---------------------------------------------------------------------------

function numberOrNull(raw: unknown): number | null {
  const value = Number(raw);
  return Number.isFinite(value) && value > 0 ? value : null;
}

function parseDate(raw: unknown): number | null {
  if (raw === null || raw === undefined) return null;
  const at = Date.parse(String(raw));
  return Number.isFinite(at) ? at : null;
}
