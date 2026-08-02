/**
 * The metered feature catalogue — what free usage is spent ON.
 *
 * One list, imported by the config, the guard, the installation ledger and the
 * client-facing status callable, so that adding a feature is one edit and
 * nobody can meter a feature the limits do not know about.
 *
 * Free usage in Matheasy is LIFETIME, not monthly and not per-device. The
 * numbers here are only the fallback the server uses when Remote Config has not
 * been read yet (cold start, fetch failure, emulator) — the live values come
 * from Remote Config so a limit can be tuned without a deploy. See `limits.ts`.
 */

/** Every feature the server meters. Order is display order. */
export const METERED_FEATURES = [
  "scans",
  "tutorMessages",
  "practiceQuestions",
  "animations",
  "visualExplanations",
] as const;

export type MeteredFeature = (typeof METERED_FEATURES)[number];

/** A count per feature. The unit of everything in this subsystem. */
export type UsageLedger = Record<MeteredFeature, number>;

/** `remaining` for a user with no ceiling. */
export const UNLIMITED = -1;

/** A ledger with nothing spent. */
export function emptyLedger(): UsageLedger {
  return {
    scans: 0,
    tutorMessages: 0,
    practiceQuestions: 0,
    animations: 0,
    visualExplanations: 0,
  };
}

/**
 * Lifetime free allowances — the fallback when Remote Config is unavailable.
 *
 * These are TODAY'S SHIPPED BEHAVIOUR, exactly, so a Remote Config outage
 * degrades to what the app already does rather than to a surprise in either
 * direction. Scans and tutor messages carry their long-standing free
 * allowances; the last three are **0 because those features are Pro-exclusive
 * right now**, and 0 is how "Pro-exclusive" is spelled in this system.
 *
 * Writing it as a limit rather than as an `if (!isPro) throw` is the point: the
 * day the product wants to give free users two practice questions or one visual
 * explanation as a taste, that is a number in the Remote Config console, not a
 * deploy. Nothing else has to change.
 */
export const DEFAULT_FREE_LIMITS: UsageLedger = {
  scans: 5,
  tutorMessages: 20,
  practiceQuestions: 0,
  animations: 0,
  visualExplanations: 0,
};

/**
 * Daily ceilings for PRO users, per feature.
 *
 * Not a monetisation lever — a cost one. Pro is sold as unlimited and behaves
 * as unlimited for any human; these numbers exist so a single looping or
 * compromised Pro account cannot run an unbounded OpenAI bill overnight. They
 * sit far above real use and are Remote Config-tunable, so an incident is a
 * dashboard edit rather than a deploy.
 */
export const DEFAULT_PRO_DAILY_LIMITS: UsageLedger = {
  scans: 400,
  tutorMessages: 600,
  practiceQuestions: 400,
  animations: 300,
  visualExplanations: 200,
};

/**
 * Daily ceilings for FREE users.
 *
 * Mostly redundant against a lifetime allowance that is smaller than the daily
 * one — until the lifetime allowance is raised in Remote Config, at which point
 * this is what stops a promotional bump from being farmed in one afternoon.
 */
export const DEFAULT_FREE_DAILY_LIMITS: UsageLedger = {
  scans: 20,
  tutorMessages: 60,
  practiceQuestions: 40,
  animations: 20,
  visualExplanations: 20,
};

/** Whether [value] names a metered feature — the guard for anything client-sent. */
export function isMeteredFeature(value: unknown): value is MeteredFeature {
  return (
    typeof value === "string" &&
    (METERED_FEATURES as readonly string[]).includes(value)
  );
}

/**
 * Read a ledger out of an untrusted/partial Firestore map.
 *
 * Missing is zero and nonsense is zero: a corrupt counter must never read as a
 * NEGATIVE balance, which would hand somebody unlimited free usage. Fractions
 * are floored and everything is clamped at zero for the same reason.
 */
export function toLedger(raw: unknown): UsageLedger {
  const source = (raw ?? {}) as Record<string, unknown>;
  const out = emptyLedger();
  for (const feature of METERED_FEATURES) {
    const value = Number(source[feature]);
    out[feature] = Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }
  return out;
}
