/**
 * The Cloud Function Verification Layer — the only place that decides whether a
 * metered request happens.
 *
 * Every paid endpoint calls [assertUsageAllowed] before spending money and
 * [chargeFeature] after the spend succeeds. Nothing else in the codebase is
 * allowed to read a limit and compare it to a counter; if a second copy of that
 * comparison ever appears, one of the two will drift and the drifting one will
 * be the one a student finds.
 *
 * THE CLIENT IS NEVER ASKED
 *
 * The app has a usage meter and a paywall, and both are presentation. The client
 * does not send its remaining allowance, its entitlement, or its own opinion of
 * either, and this file would ignore all three. The only client-supplied value
 * it accepts is the installation ID — which is a LOOKUP KEY, never a claim: the
 * worst a forged one can do is fail to find the device's counter, leaving the
 * account counter, which the client cannot touch, standing.
 *
 * WHAT IS CHECKED, IN ORDER
 *
 *   1. Remote Config     — the live limits and flags (compiled defaults on failure)
 *   2. The account       — `users/{uid}`: lifetime ledger, today's window, subscription
 *   3. RevenueCat        — but only when a free user is about to be refused
 *   4. The installation  — the device's own ledger, hash-keyed
 *   5. The decision      — max(account, device) against the ceiling, pure
 *
 * FAILURE HAS A DIRECTION
 *
 * Two failure modes, deliberately opposite:
 *
 *  - The DEVICE ledger is best-effort. If Firestore cannot serve it, the request
 *    proceeds on the account counter alone. Losing the device layer costs a few
 *    free scans to somebody determined; failing closed costs a lesson to
 *    somebody innocent.
 *  - The ACCOUNT read is load-bearing. If it fails we do not know whether this
 *    person has any allowance left, and neither guess is acceptable: allowing is
 *    an open gate, refusing is a false paywall. So it raises `unavailable` —
 *    "try again", not "you have run out" and not "give us money".
 *
 * And no refusal ever explains itself. The student sees a friendly message; the
 * `details` payload carries only what the app needs to draw the right screen.
 * Which layer said no, what the score was, and what the internal thresholds are
 * stay in the logs.
 */
import { FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { PRO_ENTITLEMENT_ID } from "../config";
import {
  EntitlementView,
  SubscriptionSnapshot,
  proViaRevenueCat,
  resolveEntitlement,
} from "../billing/entitlement";
import {
  InstallationState,
  emptyInstallation,
  installationDocId,
  normaliseInstallationId,
  readInstallation,
  recordInstallationEvent,
} from "../identity/installations";
import { db, userRef } from "../lib/db";
import {
  METERED_FEATURES,
  MeteredFeature,
  UNLIMITED,
  UsageLedger,
  toLedger,
} from "./features";
import {
  DailyWindow,
  UsageDecision,
  chargeDaily,
  dailyUsed,
  decideUsage,
  effectiveUsage,
  toDailyWindow,
} from "./ledger";
import { RemoteSettings, getSettings } from "./limits";
import { recordUsageEvent } from "./events";

/** Everything the guard needs about one request. */
export interface GuardContext {
  uid: string;
  feature: MeteredFeature;
  /** The raw client value; normalised (and rejected) here, never trusted. */
  installationId?: unknown;
  /** Whether this uid is a signed-out Firebase anonymous account. */
  isAnonymous?: boolean;
  /** Injected clock, so daily rollovers and grace windows are testable. */
  now?: number;
}

/** The full picture behind a decision. The endpoints only read `decision`. */
export interface UsageVerification {
  decision: UsageDecision;
  entitlement: EntitlementView;
  /** The normalised installation ID, or null when none was usable. */
  installationId: string | null;
  accountUsage: UsageLedger;
  deviceUsage: UsageLedger;
  settings: RemoteSettings;
  /** False when the Remote Config kill-switch is off: metered, logged, allowed. */
  enforced: boolean;
}

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

/**
 * Work out whether one unit of [ctx.feature] may be spent. Does not charge and
 * does not throw for a refusal — [assertUsageAllowed] does that.
 */
export async function verifyUsage(
  ctx: GuardContext
): Promise<UsageVerification> {
  const now = ctx.now ?? Date.now();
  const settings = await getSettings(now);
  const installationId = normaliseInstallationId(ctx.installationId);

  // --- the account -------------------------------------------------------
  let snap;
  try {
    snap = await userRef(ctx.uid).get();
  } catch (err) {
    // We cannot tell allowance from exhaustion, so we refuse to guess.
    logger.error("Usage verification could not read the account", {
      uid: ctx.uid,
      feature: ctx.feature,
      err: String(err),
    });
    throw new HttpsError(
      "unavailable",
      "We couldn’t check your account just now. Please try again in a moment."
    );
  }

  const accountUsage = toLedger(snap.get("usage"));
  const accountDaily = toDailyWindow(snap.get("usageDaily"));
  let entitlement = resolveEntitlement(
    snap.get("subscription") as SubscriptionSnapshot | undefined,
    snap.get("entitlement"),
    now
  );

  // --- the device --------------------------------------------------------
  const device = await readDevice(installationId, now);
  const deviceUsage = device.lifetimeUsage;

  const lifetimeUsed = effectiveUsage(ctx.feature, accountUsage, deviceUsage);
  const usedToday = Math.max(
    dailyUsed(accountDaily, ctx.feature, now),
    dailyUsed(device.daily, ctx.feature, now)
  );

  const query = {
    feature: ctx.feature,
    lifetimeUsed,
    dailyUsed: usedToday,
    limits: settings.limits,
    now,
    anonymous: ctx.isAnonymous === true,
    anonymousAllowed: settings.flags.anonymousUsageEnabled,
  };

  let decision = decideUsage({ ...query, isPro: entitlement.isPro });

  // --- RevenueCat, only when it can change the answer --------------------
  // A webhook that lagged or was dropped would otherwise paywall somebody who
  // has already paid. One HTTP call at exactly that moment is cheap; asking on
  // every scan would not be. A daily-limit refusal is NOT re-checked: paying
  // does not lift it, so the call could not change the outcome.
  if (!entitlement.isPro && decision.verdict === "upgrade_required") {
    const direct = await proViaRevenueCat(ctx.uid, now);
    if (direct === true) {
      entitlement = { ...entitlement, state: "active", isPro: true };
      decision = decideUsage({ ...query, isPro: true });
      void healEntitlement(ctx.uid);
    }
  }

  // --- the kill switch ---------------------------------------------------
  // Enforcement off still meters, still scores, still records — it only stops
  // the refusal. That way a bad limit can be disarmed in seconds without also
  // going blind to what is happening.
  const enforced = settings.flags.usageEnforcementEnabled;
  if (!enforced && !decision.allowed) {
    logger.info("Usage enforcement disabled — allowing a refused request", {
      uid: ctx.uid,
      feature: ctx.feature,
      verdict: decision.verdict,
    });
    decision = { ...decision, allowed: true };
  }

  return {
    decision,
    entitlement,
    installationId,
    accountUsage,
    deviceUsage,
    settings,
    enforced,
  };
}

/**
 * [verifyUsage], but a refusal throws the error the app already understands.
 *
 * The mapping is the existing client vocabulary, unchanged:
 *  - `resource-exhausted` + `upgradeRequired` → the paywall.
 *  - `resource-exhausted` + `rateLimited`     → "you've done a lot today".
 *  - `failed-precondition` + `signInRequired` → the sign-in sheet.
 */
export async function assertUsageAllowed(
  ctx: GuardContext
): Promise<UsageVerification> {
  const verification = await verifyUsage(ctx);
  const { decision } = verification;
  if (decision.allowed) return verification;

  void recordUsageEvent(
    {
      action: "refused",
      uid: ctx.uid,
      installation: hashed(verification.installationId),
      feature: ctx.feature,
      verdict: decision.verdict,
      isPro: decision.isPro,
      entitlement: verification.entitlement.state,
      anonymous: ctx.isAnonymous === true,
      used: decision.used,
      limit: decision.limit,
    },
    ctx.now ?? Date.now()
  );

  if (decision.verdict === "sign_in_required") {
    throw new HttpsError(
      "failed-precondition",
      "Sign in to keep using Matheasy for free.",
      { feature: ctx.feature, signInRequired: true }
    );
  }

  if (decision.verdict === "daily_limit") {
    throw new HttpsError(
      "resource-exhausted",
      "You’ve done a lot of maths today. Please try again tomorrow.",
      {
        feature: ctx.feature,
        rateLimited: true,
        retryAfterSeconds: decision.retryAfterSeconds ?? 60,
      }
    );
  }

  throw new HttpsError(
    "resource-exhausted",
    `You’ve used all your free ${label(ctx.feature)}. Upgrade to Pro to keep going.`,
    {
      feature: ctx.feature,
      limit: decision.limit,
      used: decision.used,
      upgradeRequired: true,
    }
  );
}

// ---------------------------------------------------------------------------
// Charging
// ---------------------------------------------------------------------------

/**
 * Spend one unit of [ctx.feature], after the paid work has succeeded.
 *
 * The account write is transactional because the daily window is a
 * read-modify-write (it resets on a new UTC day) and two concurrent requests
 * must not both reset it. The lifetime counter is a plain increment inside that
 * same transaction, so it cannot be lost either.
 *
 * The device write is separate and best-effort: it is a second opinion, and a
 * failure to record it must not undo a charge the student has already had the
 * benefit of, nor fail a request whose work is already done and paid for.
 */
export async function chargeFeature(
  ctx: GuardContext
): Promise<{ used: number; remaining: number }> {
  const now = ctx.now ?? Date.now();
  const settings = await getSettings(now);
  const installationId = normaliseInstallationId(ctx.installationId);
  const ref = userRef(ctx.uid);

  const charged = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const usage = toLedger(snap.get("usage"));
    const window = toDailyWindow(snap.get("usageDaily"));
    const isPro =
      resolveEntitlement(
        snap.get("subscription") as SubscriptionSnapshot | undefined,
        snap.get("entitlement"),
        now
      ).isPro;

    const next: DailyWindow = chargeDaily(window, ctx.feature, now);
    tx.set(
      ref,
      {
        usage: { [ctx.feature]: FieldValue.increment(1) },
        usageDaily: next,
        lastUsageAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { accountUsed: (usage[ctx.feature] ?? 0) + 1, isPro };
  });

  // The device ledger. Never allowed to fail the request.
  let deviceUsed = 0;
  if (installationId) {
    try {
      const state = await recordInstallationEvent(
        installationId,
        {
          kind: "charge",
          uid: ctx.uid,
          anonymous: ctx.isAnonymous === true,
          feature: ctx.feature,
        },
        { scoreRisk: settings.flags.riskScoringEnabled, now }
      );
      deviceUsed = state.lifetimeUsage[ctx.feature] ?? 0;
    } catch (err) {
      logger.warn("Device usage not recorded", {
        feature: ctx.feature,
        err: String(err),
      });
    }
  }

  const used = Math.max(charged.accountUsed, deviceUsed);
  const limit = charged.isPro ? UNLIMITED : settings.limits.free[ctx.feature];
  const remaining = limit < 0 ? UNLIMITED : Math.max(0, limit - used);

  void recordUsageEvent(
    {
      action: "charge",
      uid: ctx.uid,
      installation: hashed(installationId),
      feature: ctx.feature,
      isPro: charged.isPro,
      anonymous: ctx.isAnonymous === true,
      used,
      limit,
    },
    now
  );

  return { used, remaining };
}

// ---------------------------------------------------------------------------
// Status — what the app draws its meter from
// ---------------------------------------------------------------------------

export interface UsageStatus {
  isPro: boolean;
  entitlement: EntitlementView;
  /** Effective lifetime usage per feature, across the identity chain. */
  used: UsageLedger;
  /** The lifetime ceiling per feature; -1 for Pro. */
  limits: UsageLedger;
  remaining: UsageLedger;
}

/**
 * The whole meter, in one read — what `usageStatus` returns to the app.
 *
 * The app is free to cache this and draw from the cache; it is a display value.
 * The numbers that decide anything are re-derived by [verifyUsage] on the next
 * request, from the database, so a stale or edited cache changes what the
 * student SEES and nothing about what they GET.
 */
export async function usageSnapshot(
  uid: string,
  installationIdRaw: unknown,
  now: number = Date.now()
): Promise<UsageStatus> {
  const settings = await getSettings(now);
  const installationId = normaliseInstallationId(installationIdRaw);
  const snap = await userRef(uid).get();

  const entitlement = resolveEntitlement(
    snap.get("subscription") as SubscriptionSnapshot | undefined,
    snap.get("entitlement"),
    now
  );
  const accountUsage = toLedger(snap.get("usage"));
  const device = await readDevice(installationId, now);

  const used = {} as UsageLedger;
  const limits = {} as UsageLedger;
  const remaining = {} as UsageLedger;
  for (const feature of METERED_FEATURES) {
    const spent = effectiveUsage(feature, accountUsage, device.lifetimeUsage);
    const limit = entitlement.isPro ? UNLIMITED : settings.limits.free[feature];
    used[feature] = spent;
    limits[feature] = limit;
    remaining[feature] = limit < 0 ? UNLIMITED : Math.max(0, limit - spent);
  }

  return { isPro: entitlement.isPro, entitlement, used, limits, remaining };
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

/**
 * The device's state, or an empty one.
 *
 * Swallows its failure on purpose — see the header. An installation we cannot
 * read is treated exactly like an installation we have never seen, which is the
 * pre-existing, account-only behaviour.
 */
async function readDevice(
  installationId: string | null,
  now: number
): Promise<InstallationState> {
  if (!installationId) return emptyInstallation(now);
  try {
    return await readInstallation(installationId, now);
  } catch (err) {
    logger.warn("Installation ledger unavailable — account-only enforcement", {
      err: String(err),
    });
    return emptyInstallation(now);
  }
}

/**
 * Write back a Pro grant that RevenueCat confirmed but the webhook never
 * delivered, so the next request answers from Firestore instead of the network.
 * Best-effort: the grant has already been applied to THIS request.
 */
async function healEntitlement(uid: string): Promise<void> {
  try {
    await userRef(uid).set(
      {
        entitlement: PRO_ENTITLEMENT_ID,
        subscription: { isPro: true, healedAt: FieldValue.serverTimestamp() },
      },
      { merge: true }
    );
    logger.info("Entitlement healed from RevenueCat", { uid });
  } catch (err) {
    logger.warn("Entitlement heal failed", { uid, err: String(err) });
  }
}

function hashed(installationId: string | null): string | null {
  return installationId ? installationDocId(installationId) : null;
}

/** Human wording for a refusal message. Never mentions a rule or a threshold. */
function label(feature: MeteredFeature): string {
  switch (feature) {
    case "scans":
      return "scans";
    case "tutorMessages":
      return "tutor messages";
    case "practiceQuestions":
      return "practice questions";
    case "animations":
      return "animated walkthroughs";
    case "visualExplanations":
      return "visual explanations";
  }
}
