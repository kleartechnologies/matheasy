/**
 * The Account Merge Service — layer 3, where an anonymous session becomes a
 * person with an account.
 *
 * A student opens the app, scans three problems, likes it, and signs in with
 * Google. Two things must be true at that moment and they pull in opposite
 * directions:
 *
 *  1. Their three scans must follow them. Free usage is LIFETIME, and signing
 *     in must not be a way to get more of it.
 *  2. Nothing they earned may be lost. Signing in is the single most valuable
 *     thing a free user can do for us, and a student who signs in and finds
 *     their history gone will not do it twice.
 *
 * So the merge takes the MAXIMUM of the two ledgers, unions the identity trail,
 * and records where the history came from. It never subtracts, never resets,
 * and — because max is idempotent — never double-charges when it runs twice,
 * which it will: clients retry, networks drop responses, and the same anonymous
 * uid can arrive at the same account more than once.
 *
 * The merge is one-directional and one-time per anonymous uid. Once an
 * anonymous account has been merged into a real one it is marked as such, so it
 * cannot be re-merged into a SECOND account to launder a fresh allowance.
 */
import { FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { UsageLedger, toLedger } from "../usage/features";
import { mergeLedgers } from "../usage/ledger";
import { db, userRef } from "../lib/db";

export interface MergeInput {
  /** The account being merged FROM (the anonymous session). */
  source: { uid: string; usage: UsageLedger; installationIds: string[]; mergedInto?: string | null };
  /** The account being merged INTO (the one just signed into). */
  target: { uid: string; usage: UsageLedger; installationIds: string[] };
}

export interface MergeResult {
  /** The target's usage after the merge. */
  usage: UsageLedger;
  /** Every installation now associated with the target. */
  installationIds: string[];
  /** False when there was nothing to do (already merged, or same account). */
  changed: boolean;
  reason: "merged" | "already_merged" | "same_account" | "nothing_to_merge";
}

/**
 * Compute the merge. PURE — the transaction below applies whatever this says.
 *
 * Refuses two cases that would otherwise be quiet correctness bugs:
 *  - Merging an account into itself, which a retry with a stale uid can cause.
 *  - Re-merging a source that has already been consumed by a DIFFERENT target.
 *    That is the laundering path: sign in as A, merge the anonymous session,
 *    sign out, sign in as B, replay the same merge. Allowing it would let one
 *    anonymous session's spent allowance be "absorbed" by any number of fresh
 *    accounts, which is harmless — but the same call also unions installations,
 *    and repeating it would smear one device's trail across accounts that never
 *    touched it, corrupting exactly the signal this system runs on.
 */
export function planMerge(input: MergeInput): MergeResult {
  const { source, target } = input;

  if (source.uid === target.uid) {
    return {
      usage: target.usage,
      installationIds: target.installationIds,
      changed: false,
      reason: "same_account",
    };
  }

  if (source.mergedInto && source.mergedInto !== target.uid) {
    return {
      usage: target.usage,
      installationIds: target.installationIds,
      changed: false,
      reason: "already_merged",
    };
  }

  const usage = mergeLedgers(source.usage, target.usage);
  const installationIds = union(target.installationIds, source.installationIds);
  const changed =
    !sameLedger(usage, target.usage) ||
    installationIds.length !== target.installationIds.length ||
    source.mergedInto !== target.uid;

  return {
    usage,
    installationIds,
    changed,
    reason: changed ? "merged" : "nothing_to_merge",
  };
}

/**
 * Merge [sourceUid] into [targetUid], transactionally.
 *
 * Both documents are read inside the transaction, so a scan landing on either
 * account mid-merge cannot be lost: it either happens before the read and is
 * included, or after the commit and applies to the merged total.
 *
 * The source is not deleted. It is marked `mergedInto` and left in place —
 * partly so the merge stays idempotent, partly because deleting the record of
 * an account that spent free usage is the one thing that WOULD make this
 * farmable. Firebase Auth may reap the anonymous user; the ledger row is what
 * matters and it is ours.
 */
export async function mergeAccounts(
  sourceUid: string,
  targetUid: string
): Promise<MergeResult> {
  if (!sourceUid || !targetUid) {
    throw new HttpsError("invalid-argument", "Both accounts are required.");
  }

  const sourceRef = userRef(sourceUid);
  const targetRef = userRef(targetUid);

  const result = await db.runTransaction(async (tx) => {
    const [sourceSnap, targetSnap] = await Promise.all([
      tx.get(sourceRef),
      tx.get(targetRef),
    ]);

    const plan = planMerge({
      source: {
        uid: sourceUid,
        usage: toLedger(sourceSnap.get("usage")),
        installationIds: asStrings(sourceSnap.get("identity.installationIds")),
        mergedInto: sourceSnap.get("identity.mergedInto") ?? null,
      },
      target: {
        uid: targetUid,
        usage: toLedger(targetSnap.get("usage")),
        installationIds: asStrings(targetSnap.get("identity.installationIds")),
      },
    });

    if (!plan.changed) return plan;

    tx.set(
      targetRef,
      {
        usage: plan.usage,
        identity: {
          installationIds: plan.installationIds,
          mergedFrom: FieldValue.arrayUnion(sourceUid),
          lastMergeAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );

    tx.set(
      sourceRef,
      {
        identity: {
          mergedInto: targetUid,
          mergedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );

    return plan;
  });

  logger.info("Account merge", {
    source: sourceUid,
    target: targetUid,
    reason: result.reason,
    changed: result.changed,
  });
  return result;
}

// ---------------------------------------------------------------------------

function union(a: string[], b: string[]): string[] {
  return Array.from(new Set([...a, ...b]));
}

function sameLedger(a: UsageLedger, b: UsageLedger): boolean {
  return (Object.keys(a) as Array<keyof UsageLedger>).every((k) => a[k] === b[k]);
}

function asStrings(raw: unknown): string[] {
  return Array.isArray(raw) ? raw.filter((v): v is string => typeof v === "string") : [];
}
