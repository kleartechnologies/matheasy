/**
 * Server-side per-user rate limiting for the paid OpenAI endpoints (spec §10).
 *
 * A fixed-window counter kept on `users/{uid}.rateLimits.{action}` and updated
 * inside a Firestore transaction (so concurrent calls can't race past the cap).
 * Enforced BEFORE the paid call and for EVERY user — the free-tier quota is a
 * lifetime total that can't stop a burst, and Pro users are quota-unlimited, so
 * this is the only thing standing between a retry-loop / abuse and an unbounded
 * OpenAI bill.
 *
 * Over-limit throws `resource-exhausted` with `details.rateLimited = true`, so
 * the client can tell "slow down for a moment" apart from "you've used your free
 * scans → upgrade" (which is `resource-exhausted` WITHOUT that flag).
 */
import { HttpsError } from "firebase-functions/v2/https";

import { RATE_LIMITS, RateLimitedAction } from "../config";
import { db, userRef } from "./firestore";

export interface WindowState {
  minEpoch?: number;
  minCount?: number;
  dayEpoch?: number;
  dayCount?: number;
}

export interface RateDecision {
  allow: boolean;
  /** The window state to persist after counting this call. */
  next: Required<WindowState>;
  /** Which ceiling was hit (only when `allow` is false). */
  window?: "minute" | "day";
  retryAfterSeconds?: number;
}

/**
 * Pure fixed-window rate-limit decision (no I/O — the testable core). Counts the
 * current call into the minute/day windows, resetting a window when its epoch
 * rolls over, and rejects when either ceiling is exceeded.
 */
export function evaluateRateLimit(
  state: WindowState,
  limits: { perMinute: number; perDay: number },
  now: number
): RateDecision {
  const minute = Math.floor(now / 60_000);
  const day = Math.floor(now / 86_400_000);
  const minCount = state.minEpoch === minute ? (state.minCount ?? 0) + 1 : 1;
  const dayCount = state.dayEpoch === day ? (state.dayCount ?? 0) + 1 : 1;
  const next = { minEpoch: minute, minCount, dayEpoch: day, dayCount };

  if (minCount > limits.perMinute) {
    return {
      allow: false,
      next,
      window: "minute",
      retryAfterSeconds: Math.max(1, 60 - Math.floor((now % 60_000) / 1000)),
    };
  }
  if (dayCount > limits.perDay) {
    return {
      allow: false,
      next,
      window: "day",
      retryAfterSeconds: Math.max(1, 86_400 - Math.floor((now % 86_400_000) / 1000)),
    };
  }
  return { allow: true, next };
}

/**
 * Throws `resource-exhausted` (with `rateLimited: true`) if [uid] has exceeded
 * the per-minute or per-day ceiling for [action]; otherwise records the call.
 * The read + count + write run in a transaction so concurrent calls can't race
 * past the cap. [now] is injectable for tests; defaults to wall-clock.
 */
export async function assertWithinRateLimit(
  uid: string,
  action: RateLimitedAction,
  now: number = Date.now()
): Promise<void> {
  const limits = RATE_LIMITS[action];
  const ref = userRef(uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const state = (snap.get(`rateLimits.${action}`) ?? {}) as WindowState;
    const decision = evaluateRateLimit(state, limits, now);

    if (!decision.allow) {
      throw rateLimitError(decision.retryAfterSeconds ?? 60, decision.window ?? "minute");
    }

    tx.set(ref, { rateLimits: { [action]: decision.next } }, { merge: true });
  });
}

function rateLimitError(retryAfterSeconds: number, window: "minute" | "day" = "minute"): HttpsError {
  const message =
    window === "day"
      ? "You've hit today's usage limit. Please come back tomorrow."
      : "You're going a little fast — give it a few seconds and try again.";
  return new HttpsError("resource-exhausted", message, {
    rateLimited: true,
    retryAfterSeconds: Math.max(1, retryAfterSeconds),
  });
}
