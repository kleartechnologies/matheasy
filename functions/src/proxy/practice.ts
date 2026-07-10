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
import { chatJson, createOpenAI } from "../lib/openai";

interface PracticeRequest {
  topic?: string;
  skill?: string;
  skillLabel?: string;
  difficulty?: string;
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

const SYSTEM_PROMPT = `You are Numi, the friendly math tutor inside the Matheasy app, generating fresh PRACTICE questions.
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
- Make every question solvable with a single, unambiguous answer at the stated difficulty. Keep language age-appropriate.`;

export const generatePracticeQuestion = onCall(
  { secrets: [OPENAI_API_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const {
      topic,
      skill,
      skillLabel,
      difficulty,
      count,
    } = (request.data ?? {}) as PracticeRequest;

    if (!skill || typeof skill !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "skill (the practice skill id) is required."
      );
    }

    const requested = Math.max(1, Math.min(MAX_COUNT, Number(count) || 3));

    await ensureUserDoc(uid);

    // Adaptive / AI-generated practice is Pro-exclusive — enforce server-side.
    const entitlement = await getEntitlement(uid);
    if (entitlement !== PRO_ENTITLEMENT_ID) {
      throw new HttpsError(
        "permission-denied",
        "Adaptive Practice is a Matheasy Pro feature. Upgrade to unlock it.",
        { feature: "adaptivePractice", upgradeRequired: true }
      );
    }

    const userMessage = [
      `Generate ${requested} distinct practice questions.`,
      `Skill: ${skillLabel ?? skill}${topic ? ` (topic: ${topic})` : ""}.`,
      `Difficulty: ${difficulty ?? "medium"}.`,
    ].join("\n");

    let payload: PracticePayload;
    try {
      const client = createOpenAI(OPENAI_API_KEY.value());
      payload = await chatJson<PracticePayload>(
        client,
        OPENAI_MODEL.value(),
        SYSTEM_PROMPT,
        userMessage,
        { temperature: 0.7, maxTokens: 2500 }
      );
    } catch (err) {
      logger.error("generatePracticeQuestion failed", {
        uid,
        skill,
        err: String(err),
      });
      throw new HttpsError(
        "internal",
        "Numi couldn't create those questions. Please try again."
      );
    }

    const questions = Array.isArray(payload.questions)
      ? payload.questions.slice(0, MAX_COUNT)
      : [];

    return { questions, usage: null };
  }
);
