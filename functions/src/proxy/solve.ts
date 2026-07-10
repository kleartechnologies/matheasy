/**
 * `solveEquation` — the secure OpenAI solver proxy.
 *
 * Takes recognized LaTeX and returns a full worked solution shaped to the app's
 * `ResultData` (answer + steps + simple/teacher/exam explanations + alternative
 * methods + practice). Downstream of `recognizeEquation`, so by default it does
 * NOT charge a scan again — pass `countAsScan: true` for the manual-entry path
 * (typed problem, no OCR) so it still meters correctly.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { OPENAI_API_KEY, OPENAI_MODEL } from "../config";
import { requireUid } from "../lib/auth";
import {
  assertWithinQuota,
  ensureUserDoc,
  incrementUsage,
} from "../lib/firestore";
import { chatJson, createOpenAI } from "../lib/openai";

interface SolveRequest {
  latex?: string;
  countAsScan?: boolean;
}

/** The JSON contract the model must return — maps 1:1 to the Flutter domain. */
interface SolvePayload {
  type: string;
  difficulty: "easy" | "medium" | "hard";
  answerLatex: string;
  verifyText: string;
  tutorIntro: string;
  steps: Array<{
    title: string;
    operationLabel?: string;
    resultLatex: string;
    detail: string;
  }>;
  explanations: Array<{
    mode: "simple" | "teacher" | "exam";
    body: string;
    points: string[];
  }>;
  methods: Array<{
    name: string;
    subtitle: string;
    description: string;
    advantages: string[];
    whenToUse: string;
    steps: string[];
    recommended?: boolean;
  }>;
  practice: Array<{
    questionLatex: string;
    difficulty: "easy" | "medium" | "hard";
    xpReward: number;
  }>;
}

const SYSTEM_PROMPT = `You are Matheasy, the friendly, encouraging math tutor inside the Matheasy app.
Solve the given problem and return ONLY a JSON object (no prose, no markdown) with this exact shape:
{
  "type": "linear|quadratic|fraction|expression|trigonometry",
  "difficulty": "easy|medium|hard",
  "answerLatex": "the final answer as LaTeX",
  "verifyText": "a one-line check that the answer is correct, ending with ✓",
  "tutorIntro": "one warm sentence introducing the solution",
  "steps": [ { "title": "...", "operationLabel": "optional short op like '÷ 2'", "resultLatex": "state after this step, as LaTeX", "detail": "why this step works, in plain student-friendly language" } ],
  "explanations": [
    { "mode": "simple",  "body": "...", "points": ["...", "..."] },
    { "mode": "teacher", "body": "...", "points": ["...", "..."] },
    { "mode": "exam",    "body": "...", "points": ["...", "..."] }
  ],
  "methods": [ { "name": "...", "subtitle": "...", "description": "...", "advantages": ["..."], "whenToUse": "...", "steps": ["..."], "recommended": true } ],
  "practice": [ { "questionLatex": "similar practice problem as LaTeX", "difficulty": "easy|medium|hard", "xpReward": 15 } ]
}
Rules: LaTeX must be valid and delimiter-free. Provide 2-4 steps, all three explanation modes, 1-3 methods (exactly one recommended), and 2-4 practice questions with xpReward 15-50. Keep language warm and age-appropriate.`;

export const solveEquation = onCall(
  { secrets: [OPENAI_API_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const { latex, countAsScan = false } = (request.data ?? {}) as SolveRequest;

    if (!latex || typeof latex !== "string") {
      throw new HttpsError("invalid-argument", "latex (the problem to solve) is required.");
    }

    await ensureUserDoc(uid);
    if (countAsScan) {
      await assertWithinQuota(uid, "scans");
    }

    let payload: SolvePayload;
    try {
      const client = createOpenAI(OPENAI_API_KEY.value());
      payload = await chatJson<SolvePayload>(
        client,
        OPENAI_MODEL.value(),
        SYSTEM_PROMPT,
        `Solve this problem: ${latex}`,
        { temperature: 0.2, maxTokens: 2000 }
      );
    } catch (err) {
      logger.error("solveEquation failed", { uid, err: String(err) });
      throw new HttpsError("internal", "Matheasy couldn't solve that one. Please try again.");
    }

    const quota = countAsScan ? await incrementUsage(uid, "scans") : null;

    return { ...payload, usage: quota };
  }
);
