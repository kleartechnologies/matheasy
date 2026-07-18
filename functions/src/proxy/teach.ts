/**
 * `enrichTeaching` — the teaching layer as a SEPARATE, on-demand call.
 *
 * Decoupled from `solveEquation` (which must return the verified answer FAST):
 * the client fetches the answer first, then calls this to load the teaching
 * layer progressively (mirroring how the Visual tab calls `generateVisualSolution`).
 * Cloud Functions can't reliably fire-and-forget after a response (CPU is
 * throttled post-return), so a second callable — not a background task on the
 * solve path — is the clean way to keep solving instant.
 *
 * It reads the VERIFIED CORE from the solve cache (written by the preceding
 * `solveEquation`), so it never re-solves and never touches the golden-rule
 * pipeline. Depth is server-authoritative (Pro→full, free→lite). Returns the
 * teaching layer + the examPick's enriched methods, or `{ teaching: null }`.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import {
  OPENAI_API_KEY,
  OPENAI_MODEL,
  PRO_ENTITLEMENT_ID,
  teachingEnabled,
} from "../config";
import { requireUid } from "../lib/auth";
import { ensureUserDoc, getEntitlement } from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import {
  getCachedSolve,
  getCachedTeaching,
  putCachedTeaching,
  putTeachingNegative,
} from "../lib/solveCache";
import { chatJson, createOpenAI } from "../lib/openai";
import { JsonCompleter } from "../solver/narrate";
import { generateTeaching, methodsAlign } from "../solver/teach";

interface EnrichRequest {
  latex?: string;
}

export const enrichTeaching = onCall(
  { secrets: [OPENAI_API_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const { latex } = (request.data ?? {}) as EnrichRequest;
    if (!latex || typeof latex !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "latex (the problem to teach) is required."
      );
    }

    await ensureUserDoc(uid);

    // Feature-flagged; a client that calls this while it's off just gets no layer.
    if (!teachingEnabled()) return { teaching: null };

    // The verified core must already be cached by the preceding solveEquation.
    // No cache → nothing to teach here (we never re-solve on the teaching path).
    const core = await getCachedSolve(latex);
    if (!core || core.verified !== true || core.routeToTutor === true) {
      return { teaching: null };
    }
    const payload = { ...core, problemLatex: latex };

    const lang = "en";
    const depth: "lite" | "full" =
      (await getEntitlement(uid)) === PRO_ENTITLEMENT_ID ? "full" : "lite";

    const complete: JsonCompleter = (system, user, maxTokens) => {
      const client = createOpenAI(OPENAI_API_KEY.value());
      return chatJson<Record<string, unknown>>(
        client,
        OPENAI_MODEL.value(),
        system,
        user,
        { temperature: 0.2, maxTokens }
      );
    };

    try {
      const cached = await getCachedTeaching(latex, depth, lang);
      let tdoc = cached === "negative" ? null : cached;
      if (!cached) {
        // Rate-limit ONLY the paid OpenAI enrichment — a cached view costs $0 and
        // must never be capped (review #2). A limit hit is caught below and
        // gracefully yields no teaching (the answer is already on screen). This is
        // also the sole cost backstop for a reliably-erroring prompt whose
        // transient throws aren't negative-cached (review #4 — circuit-breaker TODO).
        await assertWithinRateLimit(uid, "teach");
        let built = await generateTeaching(complete, payload, depth);
        // A paying user must never get LESS than a free one: fall back to lite
        // when full fails the (stricter) firewall (mirrors solve.ts, review #1).
        if (!built && depth === "full") {
          built = await generateTeaching(complete, payload, "lite");
        }
        if (built) {
          tdoc = built;
          await putCachedTeaching(latex, built, depth, lang);
        } else {
          await putTeachingNegative(latex, depth, lang);
        }
      }
      // Only return teaching whose steps still byte-match the live core.
      if (tdoc && methodsAlign(payload.methods, tdoc.methods)) {
        return { teaching: tdoc.teaching, methods: tdoc.methods };
      }
    } catch (err) {
      // Teaching is best-effort — a failure just yields no layer, never an error.
      logger.warn("enrichTeaching failed — returning no teaching", {
        uid,
        err: String(err),
      });
    }
    return { teaching: null };
  }
);
