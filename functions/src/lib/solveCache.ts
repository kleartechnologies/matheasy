/**
 * Server-side result cache for `solveEquation` (spec §10).
 *
 * A verified solution is deterministic and user-independent (2x+5=15 → x=5 for
 * everyone), so a GLOBAL cache lets a repeat problem — from ANY user or device,
 * unbypassable, unlike the client-side history cache — return with NO OpenAI
 * call. Only VERIFIED payloads are cached (a couldn't-verify result may succeed
 * on a retry, and must never be pinned).
 *
 * The key is a COLLISION-SAFE canonical form of the problem LaTeX — the exact
 * same identity-preserving transforms as the client's `historyCacheKey`
 * (step 7): two renderings of the same problem share a key, two different
 * problems never do, so a cache HIT can never serve a wrong answer. The doc id
 * is a SHA-256 of that key (avoids Firestore doc-id char/length limits).
 *
 * The cache is BEST-EFFORT: any read/write failure degrades to a miss and never
 * breaks solving. Docs carry `expiresAt` for a Firestore TTL policy (auto-purge;
 * see functions/README) so nothing is retained indefinitely.
 */
import { createHash } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

import { SolvePayload } from "../solver/types";
import { db } from "./firestore";

const COLLECTION = "solveCache";
const TTL_DAYS = 30;

/**
 * The collision-safe cache key. Applies only transforms that preserve
 * mathematical identity (strictly finer than the solver's `latexToAscii`, so it
 * can never merge two problems the solver distinguishes):
 *   • drop `\left`/`\right` (pure rendering);
 *   • fold `\cdot`/`\times` → `*` (both mean multiply);
 *   • unwrap single-char super/subscript braces (`^{2}` ≡ `^2`);
 *   • strip whitespace.
 */
export function solveCacheKey(latex: string): string {
  return latex
    .replace(/\\left/g, "")
    .replace(/\\right/g, "")
    .replace(/\\cdot/g, "*")
    .replace(/\\times/g, "*")
    .replace(/([_^])\{(\w)\}/g, "$1$2")
    .replace(/\s+/g, "");
}

function docId(latex: string): string {
  return createHash("sha256").update(solveCacheKey(latex)).digest("hex");
}

/** The cached verified payload for [latex], or null on a miss / any error. */
export async function getCachedSolve(latex: string): Promise<SolvePayload | null> {
  try {
    const snap = await db.collection(COLLECTION).doc(docId(latex)).get();
    if (!snap.exists) return null;
    const payload = snap.get("payload");
    return payload ? (payload as SolvePayload) : null;
  } catch (err) {
    logger.warn("solveCache read failed — treating as a miss", { err: String(err) });
    return null;
  }
}

/** Stores a VERIFIED payload for [latex]. Best-effort; never throws. */
export async function putCachedSolve(latex: string, payload: SolvePayload): Promise<void> {
  if (!payload.verified) return;
  try {
    await db.collection(COLLECTION).doc(docId(latex)).set({
      key: solveCacheKey(latex),
      payload,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + TTL_DAYS * 86_400_000),
    });
  } catch (err) {
    logger.warn("solveCache write failed — skipping", { err: String(err) });
  }
}
