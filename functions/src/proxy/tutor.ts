/**
 * `tutorReply` — the secure OpenAI tutor proxy (Matheasy's brain).
 *
 * Takes the running chat history + the student's new message and returns Matheasy's
 * reply plus follow-up suggestion chips. Mirrors the Flutter `TutorService`
 * contract and meters against the free `tutorMessages` quota.
 */
import OpenAI from "openai";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { OPENAI_API_KEY, OPENAI_MODEL, REVENUECAT_SECRET_KEY } from "../config";
import { requireUid } from "../lib/auth";
import {
  assertWithinQuota,
  ensureUserDoc,
  incrementUsage,
} from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import { createOpenAI } from "../lib/openai";
import { languageDirective } from "../lib/language";

interface TutorTurn {
  role?: "user" | "assistant";
  text?: string;
}

interface TutorRequest {
  userText?: string;
  history?: TutorTurn[];
  /** Optional LaTeX of the problem the chat was launched from. */
  problemLatex?: string;
  /**
   * Optional one-sentence description of the Visual Learning step the student
   * tapped (Stage 14), so Matheasy can explain that exact transformation.
   */
  visualStep?: string;
  /** BCP-47 language the tutor must reply in (math stays universal). */
  language?: string;
}

interface TutorPayload {
  reply: string;
  suggestions: string[];
}

const SYSTEM_PROMPT = `You are Matheasy, the warm, patient, encouraging AI math tutor in the Matheasy app for students.
Guide the student to understanding — ask a leading question when they're stuck rather than only handing over the answer, celebrate progress, and keep it concise and age-appropriate.
Return ONLY a JSON object (no markdown) of the form:
{ "reply": "your message to the student (use plain text; wrap any math in $...$)", "suggestions": ["2-3 short follow-up prompts the student might tap next"] }`;

export const tutorReply = onCall(
  { secrets: [OPENAI_API_KEY, REVENUECAT_SECRET_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const {
      userText,
      history = [],
      problemLatex,
      visualStep,
      language,
    } = (request.data ?? {}) as TutorRequest;

    if (!userText || typeof userText !== "string") {
      throw new HttpsError("invalid-argument", "userText (the student's message) is required.");
    }

    await ensureUserDoc(uid);
    await assertWithinRateLimit(uid, "tutor");
    await assertWithinQuota(uid, "tutorMessages");

    const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [
      // The tutor replies in the learner's language by default (the student can
      // still ask for another language in-chat, which the model honours).
      { role: "system", content: SYSTEM_PROMPT + languageDirective(language) },
    ];
    if (problemLatex) {
      messages.push({
        role: "system",
        content: `The student is working on this problem: ${problemLatex}`,
      });
    }
    if (visualStep && typeof visualStep === "string") {
      messages.push({
        role: "system",
        content: `The student is looking at this step of the visual solution and may ask about it: ${visualStep}`,
      });
    }
    // Replay recent history (cap to keep prompts small), mapping any non-user turn → assistant.
    for (const turn of history.slice(-12)) {
      if (!turn.text) continue;
      const role = turn.role === "user" ? "user" : "assistant";
      messages.push({ role, content: turn.text });
    }
    messages.push({ role: "user", content: userText });

    let payload: TutorPayload;
    try {
      const client = createOpenAI(OPENAI_API_KEY.value());
      const completion = await client.chat.completions.create({
        model: OPENAI_MODEL.value(),
        temperature: 0.6,
        max_tokens: 800,
        response_format: { type: "json_object" },
        messages,
      });
      const content = completion.choices[0]?.message?.content;
      if (!content) throw new Error("empty response");
      payload = JSON.parse(content) as TutorPayload;
    } catch (err) {
      logger.error("tutorReply failed", { uid, err: String(err) });
      throw new HttpsError("internal", "Matheasy is thinking too hard right now. Please try again.");
    }

    const quota = await incrementUsage(uid, "tutorMessages");

    return {
      reply: payload.reply ?? "",
      suggestions: Array.isArray(payload.suggestions) ? payload.suggestions : [],
      usage: quota,
    };
  }
);
