/**
 * The identity and usage callables — the three calls the app makes about WHO it
 * is, as opposed to what it wants to solve.
 *
 *   registerInstallation — "this copy of the app, holding this account, is here"
 *   linkIdentity         — "the anonymous session you knew is now this account"
 *   usageStatus          — "how much of the free tier is left" (a display value)
 *
 * None of them accepts a usage number, a limit, or an entitlement from the
 * client. `registerInstallation` and `linkIdentity` take one client-supplied
 * value each — the installation ID — and it is a lookup key, not a claim: the
 * only thing a forged one can do is fail to find a device ledger, which leaves
 * the account ledger, which the client cannot reach, doing the enforcing.
 *
 * `usageStatus` is READ-ONLY and advisory. The app may cache it, draw a meter
 * from it, and decide whether to show an upsell — all presentation. Every real
 * decision is re-made server-side, from the database, inside `usage/guard.ts` on
 * the next metered request. A student who edits the cached response gets a
 * different-looking meter and exactly the same number of scans.
 */
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { requireUid } from "../lib/auth";
import { ensureUserDoc, userRef } from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import {
  installationDocId,
  normaliseInstallationId,
  recordInstallationEvent,
} from "../identity/installations";
import { mergeAccounts } from "../identity/merge";
import { usageSnapshot } from "../usage/guard";
import { getSettings } from "../usage/limits";
import { recordUsageEvent } from "../usage/events";
import { FieldValue } from "firebase-admin/firestore";

/** Whether the CALLER is a Firebase anonymous user, per the verified token. */
function callerIsAnonymous(request: { auth?: { token?: unknown } }): boolean {
  const token = request.auth?.token as { firebase?: { sign_in_provider?: string } } | undefined;
  return token?.firebase?.sign_in_provider === "anonymous";
}

/**
 * Announce an installation and bind the current account to it.
 *
 * Called on every cold start, which makes it the heartbeat that keeps
 * `lastSeen` fresh and the place a brand-new device first appears. It writes no
 * usage — it only records that this uid has been seen here, which is what makes
 * a later account switch on the same device visible.
 */
export const registerInstallation = onCall(async (request) => {
  const uid = requireUid(request);
  const installationId = normaliseInstallationId(
    (request.data as { installationId?: unknown } | undefined)?.installationId
  );
  if (!installationId) {
    throw new HttpsError("invalid-argument", "A valid installationId is required.");
  }

  await ensureUserDoc(uid);
  const anonymous = callerIsAnonymous(request);
  const settings = await getSettings();

  const state = await recordInstallationEvent(
    installationId,
    { kind: "seen", uid, anonymous },
    { scoreRisk: settings.flags.riskScoringEnabled }
  );

  // Remember the device on the account too, so the trail survives even if the
  // installation document is later lost — and so a merge can carry it across.
  await userRef(uid).set(
    {
      identity: {
        installationIds: FieldValue.arrayUnion(installationDocId(installationId)),
        lastInstallationAt: FieldValue.serverTimestamp(),
      },
    },
    { merge: true }
  );

  void recordUsageEvent({
    action: "install",
    uid,
    installation: installationDocId(installationId),
    anonymous,
  });

  // Deliberately thin. The risk score, the uid list and the device's counters
  // are internal monitoring; telling the client any of it would only teach
  // somebody what to avoid tripping.
  return { ok: true, knownAccounts: state.uids.length > 1 };
});

/**
 * Bind a just-signed-in account to this installation and absorb the anonymous
 * session's usage.
 *
 * The client calls this immediately after a Google/Apple/email sign-in, passing
 * the uid it was using a moment ago. Free usage is LIFETIME, so this merge takes
 * the maximum of the two ledgers: signing in can never cost a student what they
 * had, and can never hand them a fresh allowance either.
 *
 * `previousUid` is client-supplied and therefore only ever ADDITIVE — the worst
 * a forged one can do is import somebody else's spent usage onto your own
 * account, which is a way to give yourself LESS. There is no value of it that
 * increases anybody's allowance, which is why it needs no proof.
 */
export const linkIdentity = onCall(async (request) => {
  const uid = requireUid(request);
  const data = (request.data ?? {}) as {
    installationId?: unknown;
    previousUid?: unknown;
  };
  const installationId = normaliseInstallationId(data.installationId);
  const previousUid =
    typeof data.previousUid === "string" && data.previousUid.trim().length > 0
      ? data.previousUid.trim()
      : null;

  await ensureUserDoc(uid);
  await assertWithinRateLimit(uid, "identity");

  const anonymous = callerIsAnonymous(request);
  const settings = await getSettings();

  if (installationId) {
    try {
      await recordInstallationEvent(
        installationId,
        { kind: "signIn", uid, anonymous },
        { scoreRisk: settings.flags.riskScoringEnabled }
      );
      await userRef(uid).set(
        {
          identity: {
            installationIds: FieldValue.arrayUnion(installationDocId(installationId)),
          },
        },
        { merge: true }
      );
    } catch (err) {
      // The account merge below matters more than the device trail. Losing the
      // trail costs monitoring fidelity; failing here would cost a sign-in.
      logger.warn("linkIdentity could not record the installation", {
        err: String(err),
      });
    }
  }

  let merged: string | null = null;
  if (previousUid && previousUid !== uid) {
    const result = await mergeAccounts(previousUid, uid);
    merged = result.reason;
  }

  void recordUsageEvent({
    action: "link",
    uid,
    installation: installationId ? installationDocId(installationId) : null,
    anonymous,
    detail: merged ?? "no_previous",
  });

  return { ok: true, merged: merged === "merged" };
});

/**
 * The current meter. Read-only, and safe to cache on the device.
 *
 * Returns effective usage — the maximum across this account and this
 * installation — so a signed-out user who has spent their scans sees the same
 * remaining count after signing in as before. That is the point: there is no
 * arrangement of accounts that makes the number go back up.
 */
export const usageStatus = onCall(async (request) => {
  const uid = requireUid(request);
  const installationId = (request.data as { installationId?: unknown } | undefined)
    ?.installationId;

  await ensureUserDoc(uid);
  const status = await usageSnapshot(uid, installationId);

  return {
    isPro: status.isPro,
    entitlement: status.entitlement.state,
    expiresAtMs: status.entitlement.expiresAtMs,
    used: status.used,
    limits: status.limits,
    remaining: status.remaining,
    // Authoritative wall-clock time. The client persists the offset from its
    // own clock and uses it to keep daily-challenge / streak day-keys honest
    // when a device clock has been wound far off (reward farming).
    serverNowMs: Date.now(),
  };
});
