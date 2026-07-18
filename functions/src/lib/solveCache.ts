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

import {
  SolvePayload,
  TeachingCacheDoc,
  TEACHING_SCHEMA_VERSION,
} from "../solver/types";
import { db } from "./firestore";
import { contentLanguage } from "./language";

const COLLECTION = "solveCache";
/** The teaching layer caches SEPARATELY from the verified core (spec §4.6), so
 * old v1 cores stay valid (no cold-cache spike on the expensive verified math)
 * and free/Pro depths never collide. DEPLOY PREREQUISITE (Phase 1): configure a
 * Firestore TTL policy on this collection's `expiresAt` field — like `solveCache`,
 * docs are NOT auto-purged without one. */
const TEACHING_COLLECTION = "teachingCache";
const TTL_DAYS = 30;

/** A teaching layer's depth, used to namespace its cache entry. */
export type TeachingDepth = "full" | "lite" | "concept_only";

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

// Namespaced by LANGUAGE: the verified math (answer/graph) is language-agnostic,
// but the step narration in the payload is written in the learner's language, so
// two languages must not share one entry (else an English user could be served
// Malay narration). Each language keeps its own bucket; the answer re-computes
// deterministically (cheap) per language.
function docId(latex: string, language: string): string {
  // Key on the EFFECTIVE content language: an unknown code renders English, so it
  // must land in the "en" bucket (see contentLanguage), never its own.
  return createHash("sha256")
    .update(`${contentLanguage(language)}:${solveCacheKey(latex)}`)
    .digest("hex");
}

/** The cached verified payload for [latex] in [language], or null on a miss. */
export async function getCachedSolve(
  latex: string,
  language = "en"
): Promise<SolvePayload | null> {
  try {
    const snap = await db.collection(COLLECTION).doc(docId(latex, language)).get();
    if (!snap.exists) return null;
    const payload = snap.get("payload");
    return payload ? (payload as SolvePayload) : null;
  } catch (err) {
    logger.warn("solveCache read failed — treating as a miss", { err: String(err) });
    return null;
  }
}

/** Stores a VERIFIED payload for [latex] in [language]. Best-effort; never throws. */
export async function putCachedSolve(
  latex: string,
  payload: SolvePayload,
  language = "en"
): Promise<void> {
  if (!payload.verified) return;
  try {
    await db.collection(COLLECTION).doc(docId(latex, language)).set({
      key: `${contentLanguage(language)}:${solveCacheKey(latex)}`,
      payload,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + TTL_DAYS * 86_400_000),
    });
  } catch (err) {
    logger.warn("solveCache write failed — skipping", { err: String(err) });
  }
}

// ---------------------------------------------------------------------------
// Teaching-layer cache (spec §4.6). Namespaced by teaching schema version +
// depth + language so the free (`lite`) and Pro (`full`) layers, and any future
// language, never collide and both share the ONE verified core above. Wired into
// solve.ts in Phase 1; the doc-id + read/write helpers land here in Phase 0.
// ---------------------------------------------------------------------------

/** Doc id for a teaching layer of the given depth + language over [latex]. */
function teachingDocId(latex: string, depth: TeachingDepth, language: string): string {
  return createHash("sha256")
    .update(`${TEACHING_SCHEMA_VERSION}:${depth}:${language}:${solveCacheKey(latex)}`)
    .digest("hex");
}

/** The cached teaching for [latex] at this depth/language:
 *   • a `TeachingCacheDoc` — a real hit (attach it);
 *   • `"negative"` — a pinned DETERMINISTIC no-teaching marker (skip; do NOT
 *     re-enrich, until the short negative TTL lapses);
 *   • `null` — a true miss (generate). */
export async function getCachedTeaching(
  latex: string,
  depth: TeachingDepth,
  language: string
): Promise<TeachingCacheDoc | "negative" | null> {
  try {
    const snap = await db
      .collection(TEACHING_COLLECTION)
      .doc(teachingDocId(latex, depth, language))
      .get();
    if (!snap.exists) return null;
    if (snap.get("negative") === true) return "negative";
    const doc = snap.get("doc");
    return doc ? (doc as TeachingCacheDoc) : null;
  } catch (err) {
    logger.warn("teachingCache read failed — treating as a miss", { err: String(err) });
    return null;
  }
}

/** Negative TTL — shorter than a hit's, so a prompt fix propagates within a day
 * rather than being pinned for a month. */
const NEGATIVE_TTL_DAYS = 1;

/** Pin a DETERMINISTIC no-teaching outcome (a firewall/viability rejection — never
 * a transient failure) so the paid enrich call isn't repeated on every later solve
 * of the same problem. Best-effort. */
export async function putTeachingNegative(
  latex: string,
  depth: TeachingDepth,
  language: string
): Promise<void> {
  if (depth === "concept_only") return;
  try {
    await db
      .collection(TEACHING_COLLECTION)
      .doc(teachingDocId(latex, depth, language))
      .set({
        key: solveCacheKey(latex),
        negative: true,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(Date.now() + NEGATIVE_TTL_DAYS * 86_400_000),
      });
  } catch (err) {
    logger.warn("teachingCache negative write failed — skipping", { err: String(err) });
  }
}

/** Stores a teaching doc for [latex]. Only `full`/`lite` (verified-path) layers
 * are cached — `concept_only` (honest) layers are never pinned. Best-effort. */
export async function putCachedTeaching(
  latex: string,
  doc: TeachingCacheDoc,
  depth: TeachingDepth,
  language: string
): Promise<void> {
  if (depth === "concept_only") return;
  try {
    await db
      .collection(TEACHING_COLLECTION)
      .doc(teachingDocId(latex, depth, language))
      .set({
        key: solveCacheKey(latex),
        doc,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(Date.now() + TTL_DAYS * 86_400_000),
      });
  } catch (err) {
    logger.warn("teachingCache write failed — skipping", { err: String(err) });
  }
}
