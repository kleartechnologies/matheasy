/**
 * The arithmetic of free usage — the pure core of the anti-abuse system.
 *
 * Everything here is a function of its arguments: no Firestore, no clock, no
 * network. That is deliberate. This is the code that decides whether a student
 * gets to scan their homework, so it is the code that has to be provably
 * correct, and a decision function you can call a thousand times in a unit test
 * is worth more than one you can only observe through an emulator.
 *
 * THE CENTRAL IDEA
 *
 * A person's free allowance is not stored in one place, because a person is not
 * one identifier. They are an installation, an anonymous session, and — once
 * they sign in — an account, and they can shed any one of those at will. So the
 * ledger is read as the MAXIMUM across every identity we can tie together:
 *
 *   effective usage = max(what this account has spent, what this device has spent)
 *
 * Signing out, signing in with a different Google account, or clearing the app's
 * data drops one of those numbers and leaves the other standing. Reinstalling
 * resets the device number but not the account's. Getting back to zero requires
 * a new device AND a new account — which is exactly the bar the product wants:
 * not impossible, just not worth it.
 *
 * Nothing here ever DECREASES a counter. There is no code path in this file
 * that returns a smaller number than it was given.
 */
import {
  METERED_FEATURES,
  MeteredFeature,
  UNLIMITED,
  UsageLedger,
  emptyLedger,
} from "./features";

// ---------------------------------------------------------------------------
// Reading the ledger across identities
// ---------------------------------------------------------------------------

/**
 * The usage that actually counts against [feature], given everything we can tie
 * to this request.
 *
 * Max, not sum. The account counter and the device counter overlap — a scan by
 * a signed-in user on their own phone lands in both — so adding them would
 * charge a loyal, single-device user twice for every scan they ever made. Max
 * is also idempotent, which is what makes the merge below safe to re-run.
 */
export function effectiveUsage(
  feature: MeteredFeature,
  account: UsageLedger,
  device: UsageLedger
): number {
  return Math.max(account[feature] ?? 0, device[feature] ?? 0);
}

/** [effectiveUsage] for every feature at once — what the status callable returns. */
export function effectiveLedger(
  account: UsageLedger,
  device: UsageLedger
): UsageLedger {
  const out = emptyLedger();
  for (const feature of METERED_FEATURES) {
    out[feature] = effectiveUsage(feature, account, device);
  }
  return out;
}

/**
 * Fold two ledgers into one, taking the larger count of each feature.
 *
 * Used when an anonymous session is merged into the account a student has just
 * signed into. MAX rather than SUM for two reasons, and both matter:
 *
 *  - Idempotency. A merge can be replayed — the client retries, the network
 *    drops the response, the same anonymous uid is linked twice. Summing would
 *    quietly double a student's spent allowance every time that happened.
 *  - No double-charging. The anonymous session's scans are already on the
 *    installation's counter, and the installation is consulted on every
 *    request, so summing would count the same scan twice over.
 *
 * The consequence is deliberate and worth stating plainly: merging can never
 * take free usage AWAY from a student who did nothing wrong, and can never give
 * any back to one who is trying it on.
 */
export function mergeLedgers(a: UsageLedger, b: UsageLedger): UsageLedger {
  const out = emptyLedger();
  for (const feature of METERED_FEATURES) {
    out[feature] = Math.max(a[feature] ?? 0, b[feature] ?? 0);
  }
  return out;
}

// ---------------------------------------------------------------------------
// The decision
// ---------------------------------------------------------------------------

/** Why a request was refused. `ok` means it was not. */
export type UsageVerdict =
  /** Within allowance. */
  | "ok"
  /** Free allowance spent — this is the one that opens the paywall. */
  | "upgrade_required"
  /** Today's ceiling reached. Upgrading does NOT lift this; waiting does. */
  | "daily_limit"
  /** Signed-out usage is switched off. Signing in fixes it; paying does not. */
  | "sign_in_required";

export interface UsageDecision {
  allowed: boolean;
  verdict: UsageVerdict;
  feature: MeteredFeature;
  /** Effective lifetime usage BEFORE this request. */
  used: number;
  /** The lifetime ceiling, or [UNLIMITED]. */
  limit: number;
  /** Lifetime allowance left after this request would be charged, or [UNLIMITED]. */
  remaining: number;
  isPro: boolean;
  /** Seconds until the daily window rolls over — only set on `daily_limit`. */
  retryAfterSeconds?: number;
}

export interface UsageLimits {
  /** Lifetime free allowance per feature. */
  free: UsageLedger;
  /** Daily ceiling per feature for free users. */
  freeDaily: UsageLedger;
  /** Daily ceiling per feature for Pro users — a cost backstop, not a product limit. */
  proDaily: UsageLedger;
}

export interface UsageQuery {
  feature: MeteredFeature;
  isPro: boolean;
  /** Effective lifetime usage across the identity chain. */
  lifetimeUsed: number;
  /** Requests already made by this identity inside the current UTC day. */
  dailyUsed: number;
  limits: UsageLimits;
  /** Wall clock, injected so the daily rollover is testable. */
  now: number;
  /** Whether the caller is a signed-out (anonymous) session. */
  anonymous?: boolean;
  /**
   * Whether signed-out sessions may spend free usage at all. Defaults to true;
   * the Remote Config flag can turn it off, which forces a sign-in wall in front
   * of the free tier without a deploy.
   */
  anonymousAllowed?: boolean;
}

/**
 * Decide whether one more unit of [feature] may be spent.
 *
 * Reads as: Pro users have no lifetime ceiling but do have a daily one; free
 * users have both, and the lifetime one is checked first because "you have used
 * your free scans" is a different message, and a different product moment, from
 * "you have done a lot today". Getting that order wrong would show a student the
 * paywall for a reason paying would not fix.
 *
 * A ceiling of [UNLIMITED] (or anything negative) means no ceiling. A ceiling of
 * zero means the feature is off for that tier — which is a legitimate Remote
 * Config state, so it must read as "upgrade", never as "allow".
 *
 * A paying anonymous user is still a paying user: the sign-in wall applies to
 * the FREE tier only, so somebody who bought Pro and has not linked an account
 * is never locked out of what they paid for.
 */
export function decideUsage(query: UsageQuery): UsageDecision {
  const { feature, isPro, lifetimeUsed, dailyUsed, limits, now } = query;
  const lifetimeLimit = isPro ? UNLIMITED : limits.free[feature];
  const dailyLimit = isPro ? limits.proDaily[feature] : limits.freeDaily[feature];

  const base = {
    feature,
    used: lifetimeUsed,
    limit: lifetimeLimit,
    isPro,
    remaining: uncapped(lifetimeLimit)
      ? UNLIMITED
      : Math.max(0, lifetimeLimit - lifetimeUsed - 1),
  };

  if (!isPro && query.anonymous === true && query.anonymousAllowed === false) {
    return { ...base, allowed: false, verdict: "sign_in_required" };
  }

  if (!uncapped(lifetimeLimit) && lifetimeUsed >= lifetimeLimit) {
    return { ...base, allowed: false, verdict: "upgrade_required", remaining: 0 };
  }

  if (!uncapped(dailyLimit) && dailyUsed >= dailyLimit) {
    return {
      ...base,
      allowed: false,
      verdict: "daily_limit",
      retryAfterSeconds: secondsUntilNextDay(now),
    };
  }

  return { ...base, allowed: true, verdict: "ok" };
}

/** A negative ceiling means "no ceiling"; [UNLIMITED] is the canonical one. */
function uncapped(limit: number): boolean {
  return !Number.isFinite(limit) || limit < 0;
}

/** Seconds remaining in the current UTC day, floored at 1 so it is never "retry now". */
export function secondsUntilNextDay(now: number): number {
  const dayMs = 86_400_000;
  return Math.max(1, Math.ceil((dayMs - (now % dayMs)) / 1000));
}

// ---------------------------------------------------------------------------
// Daily windows
// ---------------------------------------------------------------------------

export interface DailyWindow {
  /** UTC day index — `Math.floor(now / 86_400_000)`. */
  epoch: number;
  counts: Partial<Record<MeteredFeature, number>>;
}

/** The UTC day [now] falls in. */
export function dayEpoch(now: number): number {
  return Math.floor(now / 86_400_000);
}

/**
 * How much of [feature] has been spent today, given the stored window.
 *
 * A window from an earlier day reads as zero rather than being trusted, so a
 * counter left over from yesterday can neither block today nor be replayed.
 */
export function dailyUsed(
  window: DailyWindow | undefined,
  feature: MeteredFeature,
  now: number
): number {
  if (!window || window.epoch !== dayEpoch(now)) return 0;
  const value = Number(window.counts?.[feature]);
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
}

/** The window to persist after charging one unit of [feature]. */
export function chargeDaily(
  window: DailyWindow | undefined,
  feature: MeteredFeature,
  now: number
): DailyWindow {
  const epoch = dayEpoch(now);
  const fresh = !window || window.epoch !== epoch;
  const counts = fresh ? {} : { ...window.counts };
  counts[feature] = (fresh ? 0 : Number(counts[feature] ?? 0)) + 1;
  return { epoch, counts };
}

/** Read an untrusted stored window, dropping anything malformed. */
export function toDailyWindow(raw: unknown): DailyWindow | undefined {
  const source = raw as { epoch?: unknown; counts?: unknown } | undefined;
  const epoch = Number(source?.epoch);
  if (!Number.isFinite(epoch)) return undefined;
  const counts: Partial<Record<MeteredFeature, number>> = {};
  const rawCounts = (source?.counts ?? {}) as Record<string, unknown>;
  for (const feature of METERED_FEATURES) {
    const value = Number(rawCounts[feature]);
    if (Number.isFinite(value) && value > 0) counts[feature] = Math.floor(value);
  }
  return { epoch, counts };
}
