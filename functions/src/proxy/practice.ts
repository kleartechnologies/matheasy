/**
 * `generatePracticeQuestion` — the Tier 3 AI practice generator (Stage 15).
 *
 * Produces a batch of unique practice questions for an advanced skill
 * (calculus, university math…) that the on-device template/rule tiers can't
 * reach. PRO-ONLY: the `pro` entitlement is enforced HERE, server-side, so the
 * advanced/adaptive practice engine can't be unlocked by spoofing UI state
 * (mirrors `generateVisualSolution`). Not metered — Pro usage is unlimited; the
 * free tier's 10-question allowance is spent only on the on-device tiers and
 * never reaches this function.
 *
 * Returns `{ questions: [...] }` (an OBJECT, never a bare array — the client's
 * `callFunction` requires a Map and OpenAI JSON-mode can't emit a top-level
 * array). The batch lets the client cache the surplus and amortize OpenAI cost.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { OPENAI_API_KEY, OPENAI_MODEL, PRO_ENTITLEMENT_ID } from "../config";
import { requireUid } from "../lib/auth";
import { ensureUserDoc, getEntitlement } from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import { chatJson, createOpenAI } from "../lib/openai";
import { languageDirective } from "../lib/language";

interface PracticeRequest {
  topic?: string;
  skill?: string;
  skillLabel?: string;
  difficulty?: string;
  /** Grade band for the level, e.g. "A-Level" / "University". */
  grade?: string;
  /** The ideal number of solving steps a question should take. */
  targetSteps?: number;
  /** The hard ceiling on solving steps — the model must not exceed it. */
  maxSteps?: number;
  /** BCP-47 language the questions' prose must be written in (math stays universal). */
  language?: string;
  count?: number;
}

/** The JSON contract the model must return — maps 1:1 to the Flutter mapper. */
interface PracticePayload {
  questions: Array<{
    prompt: string;
    promptLatex?: string;
    spokenPrompt?: string;
    type: "multipleChoice" | "trueFalse" | "input" | "equation";
    options?: Array<{ text: string; isCorrect: boolean }>;
    acceptedAnswers?: string[];
    explanation: string;
  }>;
}

const MAX_COUNT = 10;
/** How many times we'll re-prompt to top up the batch after discarding invalid
 * questions before returning what validated. */
const MAX_ATTEMPTS = 3;

const SYSTEM_PROMPT = `You are Matheasy, the friendly math tutor inside the Matheasy app, generating fresh PRACTICE questions.
Generate the requested number of DISTINCT practice questions for the given skill and difficulty. Vary the numbers/scenario across questions so none are duplicates.
Return ONLY a JSON object (no prose, no markdown) with this exact shape:
{
  "questions": [
    {
      "prompt": "plain-language instruction the student reads, e.g. 'Differentiate the function'",
      "promptLatex": "optional LaTeX shown large (delimiter-free), e.g. 'f(x) = 3x^2 + 2x'",
      "spokenPrompt": "optional plain-text reading of the LaTeX for screen readers",
      "type": "multipleChoice|trueFalse|input|equation",
      "options": [ { "text": "an answer choice (plain text, math as unicode)", "isCorrect": true } ],
      "acceptedAnswers": ["accepted typed answer", "alternative form"],
      "explanation": "why the correct answer is right, in warm student-friendly language"
    }
  ]
}
Rules:
- For "multipleChoice" provide exactly 4 options with EXACTLY ONE isCorrect:true; for "trueFalse" provide 2 options; do NOT include "acceptedAnswers".
- For "input" and "equation" provide 1-3 "acceptedAnswers" (include equivalent forms) and OMIT "options".
- LaTeX must be valid and delimiter-free (no surrounding $). Keep answer choices short and unambiguous.
- Make every question solvable with a single, unambiguous answer at the stated difficulty. Keep language age-appropriate.
- MATCH THE DIFFICULTY EXACTLY. Every question must sit at the requested level and grade — never easier, never harder. Use ONLY concepts appropriate at that level; do NOT use any concept above it (e.g. no calculus in a secondary-level set).
- STAY WITHIN THE STEP BUDGET. A question should take about the target number of solving steps and MUST NOT exceed the stated maximum. If a draft is too involved, simplify it or replace it.
- Do NOT reference a diagram, figure, picture or "the shape shown" — there is none. Every number the student needs must be stated in the text.`;

export const generatePracticeQuestion = onCall(
  { secrets: [OPENAI_API_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const {
      topic,
      skill,
      skillLabel,
      difficulty,
      grade,
      targetSteps,
      maxSteps,
      language,
      count,
    } = (request.data ?? {}) as PracticeRequest;

    if (!skill || typeof skill !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "skill (the practice skill id) is required."
      );
    }

    const requested = Math.max(1, Math.min(MAX_COUNT, Number(count) || 3));
    // Step budget the model must respect (sanitized; maxSteps >= targetSteps).
    const tSteps = Math.max(1, Math.min(20, Math.round(Number(targetSteps)) || 4));
    const mSteps = Math.max(
      tSteps,
      Math.min(30, Math.round(Number(maxSteps)) || 8)
    );

    await ensureUserDoc(uid);
    await assertWithinRateLimit(uid, "practice");

    // Adaptive / AI-generated practice is Pro-exclusive — enforce server-side.
    const entitlement = await getEntitlement(uid);
    if (entitlement !== PRO_ENTITLEMENT_ID) {
      throw new HttpsError(
        "permission-denied",
        "Adaptive Practice is a Matheasy Pro feature. Upgrade to unlock it.",
        { feature: "adaptivePractice", upgradeRequired: true }
      );
    }

    const buildUserMessage = (need: number) =>
      [
        `Generate ${need} distinct practice questions.`,
        `Skill: ${skillLabel ?? skill}${topic ? ` (topic: ${topic})` : ""}.`,
        `Difficulty: ${difficulty ?? "medium"}` +
          (grade ? ` (grade level: ${grade})` : "") +
          ".",
        `Target about ${tSteps} solving steps; never more than ${mSteps}.`,
        `Use ONLY concepts appropriate for "${difficulty ?? "medium"}" — nothing above it.`,
      ].join("\n");

    const client = createOpenAI(OPENAI_API_KEY.value());
    // Validate → discard → regenerate. Malformed / duplicate questions are
    // dropped and the shortfall re-prompted (bounded), so we never return a
    // question that doesn't fit the requested level's structure.
    const collected: PracticePayload["questions"] = [];
    const seen = new Set<string>();
    for (
      let attempt = 0;
      attempt < MAX_ATTEMPTS && collected.length < requested;
      attempt++
    ) {
      const need = requested - collected.length;
      let payload: PracticePayload;
      try {
        payload = await chatJson<PracticePayload>(
          client,
          OPENAI_MODEL.value(),
          SYSTEM_PROMPT + languageDirective(language),
          buildUserMessage(need),
          { temperature: 0.7, maxTokens: 2500 }
        );
      } catch (err) {
        logger.error("generatePracticeQuestion failed", {
          uid,
          skill,
          attempt,
          err: String(err),
        });
        // A first-attempt failure is a hard error; a later one keeps what we
        // already validated rather than losing the whole batch.
        if (attempt === 0) {
          throw new HttpsError(
            "internal",
            "Matheasy couldn't create those questions. Please try again."
          );
        }
        break;
      }

      const batch = Array.isArray(payload.questions) ? payload.questions : [];
      for (const q of batch) {
        if (!isStructurallyValid(q)) continue; // discard malformed
        const key = (q.promptLatex ?? q.prompt).trim().toLowerCase();
        if (seen.has(key)) continue; // discard duplicates
        seen.add(key);
        collected.push(q);
        if (collected.length >= requested) break;
      }
    }

    return { questions: collected.slice(0, MAX_COUNT), usage: null };
  }
);

/** Structural validation mirroring the client mapper — a malformed question is
 * discarded (and regenerated) rather than shown. */
function isStructurallyValid(
  q: PracticePayload["questions"][number]
): boolean {
  if (!q || typeof q.prompt !== "string" || q.prompt.trim() === "") {
    return false;
  }
  if (typeof q.explanation !== "string" || q.explanation.trim() === "") {
    return false;
  }
  if (q.type === "multipleChoice" || q.type === "trueFalse") {
    const opts = Array.isArray(q.options) ? q.options : [];
    const correct = opts.filter((o) => o && o.isCorrect === true);
    if (correct.length !== 1) return false;
    if (q.type === "multipleChoice" && opts.length !== 4) return false;
    if (q.type === "trueFalse" && opts.length !== 2) return false;
    return true;
  }
  if (q.type === "input" || q.type === "equation") {
    const answers = Array.isArray(q.acceptedAnswers)
      ? q.acceptedAnswers.filter(
          (a) => typeof a === "string" && a.trim() !== ""
        )
      : [];
    return answers.length > 0;
  }
  return false; // unknown type
}
