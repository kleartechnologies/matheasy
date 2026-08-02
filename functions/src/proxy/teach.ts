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
import { contentLanguage, languageDirective } from "../lib/language";
import { teachingToQualityInput } from "../quality/adapters";
import { gateExplanation } from "../quality/gate";
import { classify } from "../solver/classify";
import { JsonCompleter } from "../solver/narrate";
import {
  generateHonestTeaching,
  generateTeaching,
  methodsAlign,
} from "../solver/teach";
import type { TeachingCacheDoc } from "../solver/types";

/**
 * Turn the previous attempt's findings into an instruction for the next one.
 *
 * It appends to the SYSTEM prompt of the narration call, which only ever writes
 * prose over the frozen verified skeleton — so "try again" here can only produce
 * different words. The answer, the steps and the verification are not in scope
 * for this call and cannot be reached by it, whatever the feedback says.
 */
function regenerationDirective(feedback: string[]): string {
  if (feedback.length === 0) return "";
  return [
    "",
    "",
    "YOUR PREVIOUS ATTEMPT WAS REJECTED BY THE EDUCATIONAL QUALITY REVIEW.",
    "Rewrite the EXPLANATION to fix every point below. The verified answer, the",
    "steps and their expressions are unchanged and are not yours to alter —",
    "change only the words that teach them.",
    ...feedback.map((line) => `- ${line}`),
  ].join("\n");
}

interface EnrichRequest {
  latex?: string;
  /** True for a routeToTutor problem (proof/conceptual/multi-part): teach the
   * APPROACH (concept_only), since there's no verified core to enrich. */
  honest?: boolean;
  /** BCP-47 language the teaching prose must be written in (math stays universal). */
  language?: string;
}

export const enrichTeaching = onCall(
  { secrets: [OPENAI_API_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const { latex, honest, language } = (request.data ?? {}) as EnrichRequest;
    if (!latex || typeof latex !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "latex (the problem to teach) is required."
      );
    }

    await ensureUserDoc(uid);

    // Feature-flagged; a client that calls this while it's off just gets no layer.
    if (!teachingEnabled()) return { teaching: null };

    const client = createOpenAI(OPENAI_API_KEY.value());

    /** A completer that carries the quality review's feedback, if there is any. */
    const completerWith = (feedback: string[] = []): JsonCompleter =>
      (system, user, maxTokens) =>
        chatJson<Record<string, unknown>>(
          client,
          "teach",
          // Inject the language directive into every teaching LLM call so all
          // narration is written in the learner's language (math stays universal).
          system + languageDirective(language) + regenerationDirective(feedback),
          user,
          { temperature: 0.2, maxTokens }
        );

    const complete = completerWith();

    // HONEST path: a routeToTutor problem (proof/conceptual/multi-part) has NO
    // verified core to enrich — classify it and teach the APPROACH (concept_only,
    // no answer). Not cached (spec §4.6). Confirm it really is unsolvable, so a
    // solvable problem can never be honest-taught by a spoofed flag.
    //
    // Deliberately NOT run through the educational quality gate: that gate scores
    // prose against a verified solution, and here there is none by definition.
    // Honest mode has its own, stricter firewall — `generateHonestTeaching`
    // rejects ANY number the problem statement does not contain, because a
    // lesson about a problem we could not solve must not contain a result.
    if (honest === true) {
      const cls = classify(latex);
      if (cls.strategy !== "conceptual") return { teaching: null };
      try {
        await assertWithinRateLimit(uid, "teach");
        const doc = await generateHonestTeaching(complete, cls.latex, cls.problemType);
        if (doc) return { teaching: doc.teaching, methods: doc.methods };
      } catch (err) {
        logger.warn("enrichTeaching honest failed — no teaching", {
          uid,
          err: String(err),
        });
      }
      return { teaching: null };
    }

    // VERIFIED path: the core must already be cached by the preceding solveEquation
    // (in the SAME language — the client sends `language` on both calls). No cache
    // → nothing to teach here (we never re-solve on the teaching path).
    const lang = contentLanguage(language);
    const core = await getCachedSolve(latex, lang);
    if (!core || core.verified !== true || core.routeToTutor === true) {
      return { teaching: null };
    }
    const payload = { ...core, problemLatex: latex };
    const depth: "lite" | "full" =
      (await getEntitlement(uid)) === PRO_ENTITLEMENT_ID ? "full" : "lite";

    try {
      const cached = await getCachedTeaching(latex, depth, lang);
      let tdoc = cached === "negative" ? null : cached;
      if (!cached) {
        // Rate-limit ONLY the paid OpenAI enrichment — a cached view costs $0 and
        // must never be capped (review #2). A limit hit is caught below and
        // gracefully yields no teaching (the answer is already on screen). This is
        // also the sole cost backstop for a reliably-erroring prompt whose
        // transient throws aren't negative-cached (review #4 — circuit-breaker TODO).
        // Generate → review → regenerate. Every attempt spends a rate-limit
        // token, so a retry loop cannot quietly multiply a user's OpenAI budget;
        // a limit hit mid-loop throws out to the handler below and yields no
        // teaching, which is the same floor as any other failure here.
        const gated = await gateExplanation<TeachingCacheDoc>({
          client,
          surface: "teach",
          generate: async (_attempt, feedback) => {
            await assertWithinRateLimit(uid, "teach");
            const completer = completerWith(feedback);
            let built = await generateTeaching(completer, payload, depth);
            // A paying user must never get LESS than a free one: fall back to
            // lite when full fails the (stricter) firewall (mirrors solve.ts,
            // review #1).
            if (!built && depth === "full") {
              built = await generateTeaching(completer, payload, "lite");
            }
            return built;
          },
          toInput: (draft, attempt) =>
            teachingToQualityInput({
              payload,
              teaching: draft.teaching,
              methods: draft.methods,
              language: lang,
              attempt,
            }),
        });

        // ONLY a lesson that cleared the bar is cached. A rejected draft is not
        // stored, not shown, and not half-shown — the student gets the verified
        // answer with the app's ordinary working, exactly as they did before
        // this layer existed.
        if (gated.draft) {
          tdoc = gated.draft;
          await putCachedTeaching(latex, gated.draft, depth, lang);
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
