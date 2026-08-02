/**
 * The usage event ledger, and the analytics rolled up from it.
 *
 * Two writes, two audiences:
 *
 *  - `usage_events/{auto}` is the raw append-only trail: one document per
 *    metered decision, per link, per merge. It answers "what happened to THIS
 *    student on THIS day", which is what a support ticket or an abuse
 *    investigation actually needs, and it is flat enough to export to BigQuery
 *    or a CSV without a transform.
 *  - `analytics/daily_{YYYY-MM-DD}` is the pre-aggregated counter set, so a
 *    dashboard does not have to scan the trail to answer "how many free users
 *    hit their limit yesterday". Firestore increments are cheap and commutative,
 *    so this costs one extra write and never contends.
 *
 * NEITHER IS LOAD-BEARING. Every function here swallows its own failures and
 * returns. Analytics must never be able to fail a student's scan — if the
 * counters are wrong for an hour, nobody's homework is affected; if a failed
 * counter write throws into the guard, everybody's is.
 *
 * PRIVACY. The event carries the uid (we need it to answer support questions
 * about a specific account) and the HASHED installation handle, never the raw
 * installation ID and never any device or advertising identifier. There is no
 * problem text, no image, no answer — this is a meter reading, not a record of
 * what anybody studied.
 */
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

import { db } from "../lib/db";
import { MeteredFeature } from "./features";
import { UsageVerdict } from "./ledger";
import { EntitlementState } from "../billing/entitlement";

/** What kind of thing the event records. */
export type UsageAction =
  /** A metered request was permitted and charged. */
  | "charge"
  /** A metered request was refused. `verdict` says why. */
  | "refused"
  /** An installation was registered or re-seen. */
  | "install"
  /** An identity was bound to an installation (sign-in). */
  | "link"
  /** An anonymous account's usage was merged into a real one. */
  | "merge";

export interface UsageEvent {
  action: UsageAction;
  uid: string;
  /** The SHA-256 handle, never the raw ID. Null when the client sent none. */
  installation: string | null;
  feature?: MeteredFeature;
  verdict?: UsageVerdict;
  isPro?: boolean;
  entitlement?: EntitlementState;
  anonymous?: boolean;
  /** Effective lifetime usage at the moment of the decision. */
  used?: number;
  /** The ceiling in force, or -1. */
  limit?: number;
  /** Free → Pro, anonymous → account: set on `merge`/`link` for the funnel. */
  detail?: string;
}

// ---------------------------------------------------------------------------
// Pure shaping
// ---------------------------------------------------------------------------

/** The UTC day an event belongs to, as `YYYY-MM-DD`. */
export function dayKey(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}

/** The analytics document for a day. One doc per day keeps reads trivial. */
export function rollupDocId(now: number): string {
  return `daily_${dayKey(now)}`;
}

/** The event as stored. Undefined fields are dropped — Firestore rejects them. */
export function eventDocument(
  event: UsageEvent,
  now: number
): Record<string, unknown> {
  const doc: Record<string, unknown> = {
    action: event.action,
    uid: event.uid,
    installation: event.installation,
    day: dayKey(now),
    atMs: now,
    at: FieldValue.serverTimestamp(),
  };
  const optional: Array<[string, unknown]> = [
    ["feature", event.feature],
    ["verdict", event.verdict],
    ["isPro", event.isPro],
    ["entitlement", event.entitlement],
    ["anonymous", event.anonymous],
    ["used", event.used],
    ["limit", event.limit],
    ["detail", event.detail],
  ];
  for (const [key, value] of optional) {
    if (value !== undefined) doc[key] = value;
  }
  return doc;
}

/**
 * The counters an event bumps, as `field path -> amount`. PURE, so the whole
 * analytics vocabulary is one testable function rather than a scatter of
 * increments across the codebase.
 *
 * The names are chosen to answer the questions the product actually asks:
 * conversion to Pro (`proCharges` against `freeCharges`), free-usage completion
 * (`limitReached`), upgrade prompts shown (`upgradeRequired`), feature
 * popularity (`feature.*`), and the anonymous → account funnel (`merges`,
 * `signIns`).
 */
export function rollupIncrements(event: UsageEvent): Record<string, number> {
  const out: Record<string, number> = { events: 1 };

  switch (event.action) {
    case "charge":
      out.charges = 1;
      out[event.isPro ? "proCharges" : "freeCharges"] = 1;
      if (event.feature) out[`feature.${event.feature}.charges`] = 1;
      if (event.anonymous) out.anonymousCharges = 1;
      break;
    case "refused":
      out.refusals = 1;
      if (event.verdict === "upgrade_required") out.upgradeRequired = 1;
      if (event.verdict === "daily_limit") out.dailyLimited = 1;
      if (event.verdict === "sign_in_required") out.signInRequired = 1;
      if (event.feature) out[`feature.${event.feature}.refusals`] = 1;
      break;
    case "install":
      out.installs = 1;
      break;
    case "link":
      out.signIns = 1;
      break;
    case "merge":
      out.merges = 1;
      break;
  }

  return out;
}

// ---------------------------------------------------------------------------
// Writing — best-effort, always
// ---------------------------------------------------------------------------

/**
 * Append an event and bump the day's counters.
 *
 * Never throws and never awaits anything the caller depends on. A caller that
 * wants the request to be fast can drop the promise entirely; a caller that
 * wants deterministic tests can await it. Both are safe.
 */
export async function recordUsageEvent(
  event: UsageEvent,
  now: number = Date.now()
): Promise<void> {
  try {
    const counters = nest(rollupIncrements(event));
    await Promise.all([
      db.collection("usage_events").add(eventDocument(event, now)),
      db
        .collection("analytics")
        .doc(rollupDocId(now))
        .set({ day: dayKey(now), ...counters }, { merge: true }),
    ]);
  } catch (err) {
    logger.warn("Usage event not recorded", {
      action: event.action,
      err: String(err),
    });
  }
}

/**
 * Expand `a.b.c -> n` into `{a: {b: {c: increment(n)}}}`.
 *
 * `set(..., {merge: true})` treats an object key literally, so a dotted key
 * would be an invalid field name rather than a path. A deep merge of nested maps
 * gives the same result and is what the SDK actually supports.
 */
function nest(flat: Record<string, number>): Record<string, unknown> {
  const root: Record<string, unknown> = {};
  for (const [path, amount] of Object.entries(flat)) {
    const parts = path.split(".");
    let node = root;
    for (const part of parts.slice(0, -1)) {
      node[part] ??= {};
      node = node[part] as Record<string, unknown>;
    }
    node[parts[parts.length - 1]] = FieldValue.increment(amount);
  }
  return root;
}
