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

import { OPENAI_API_KEY } from "../config";
import { callerIdentity, requireUid } from "../lib/auth";
import {
  assertWithinQuota,
  ensureUserDoc,
  incrementUsage,
} from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import { chatJson, createOpenAI } from "../lib/openai";
import { contentLanguage, languageDirective } from "../lib/language";
import { runDeterministicChecks } from "../quality/checks";
import {
  DIFFICULTY_LEVELS,
  type DifficultyLevel,
  type QualityFinding,
} from "../quality/types";

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
    /** Progressive hints: [0] a nudge, [1] a method pointer. Optional; any
     * hint that leaks the answer is dropped by `sanitizeHints`, never shown. */
    hints?: string[];
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
      "explanation": "why the correct answer is right, in warm student-friendly language",
      "hints": ["a tiny nudge at what to look at", "which method to use, without doing any of it"]
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
- Do NOT reference a diagram, figure, picture or "the shape shown" — there is none. Every number the student needs must be stated in the text.
- "hints" must contain exactly 2 short strings: hint 1 nudges WHERE to look, hint 2 names the METHOD. Hints may quote numbers GIVEN in the question but must NEVER state the answer, any intermediate computed value, or any derived result — no arithmetic at all inside a hint.`;

export const generatePracticeQuestion = onCall(
  { secrets: [OPENAI_API_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const identity = callerIdentity(request);
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
    const lang = contentLanguage(language);
    const wantedDifficulty = asDifficultyLevel(difficulty);
    // Step budget the model must respect (sanitized; maxSteps >= targetSteps).
    const tSteps = Math.max(1, Math.min(20, Math.round(Number(targetSteps)) || 4));
    const mSteps = Math.max(
      tSteps,
      Math.min(30, Math.round(Number(maxSteps)) || 8)
    );

    await ensureUserDoc(uid);
    await assertWithinRateLimit(uid, "practice");

    // Adaptive / AI-generated practice is Pro-exclusive — enforced server-side
    // as a metered allowance whose free ceiling is 0 (see `usage/features.ts`),
    // so opening it to free users, even partially, is a Remote Config edit
    // rather than a deploy. The refusal still carries `upgradeRequired`, which
    // is what the app opens the paywall on.
    await assertWithinQuota(uid, "practiceQuestions", identity);

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
          "practice",
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

        // Educational quality screening (spec check 15). A question that fails
        // is discarded and the shortfall re-prompted by the loop above — the
        // same "validate → discard → regenerate" contract the structural check
        // already uses, so nothing new can reach a student.
        const findings = screenQuestion(q, {
          language: lang,
          difficulty: wantedDifficulty,
          skill,
          skillLabel: skillLabel ?? skill,
          topic,
        });
        const fatal = findings.filter(
          (f) => f.severity === "hard" || (f.severity === "major" && DROP_ON_MAJOR.has(f.check))
        );
        if (fatal.length > 0) {
          logger.warn("practice.qualityRejected", {
            uid,
            skill,
            difficulty: wantedDifficulty,
            language: lang,
            checks: fatal.map((f) => `${f.check}:${f.severity}`),
          });
          // Stays in `seen`: if the model offers the same rejected question
          // again next round, skip it early rather than re-screen it.
          continue;
        }

        collected.push({ ...q, hints: sanitizeHints(q) });
        if (collected.length >= requested) break;
      }
    }

    // One charge per GENERATION, not per question: the batch exists to amortize
    // a single OpenAI call, and that call is what costs money.
    const quota = await incrementUsage(uid, "practiceQuestions", identity);

    return { questions: collected.slice(0, MAX_COUNT), usage: quota };
  }
);

/** The client sends `PracticeDifficulty.name`, which is this vocabulary exactly. */
function asDifficultyLevel(raw: string | undefined): DifficultyLevel {
  const found = DIFFICULTY_LEVELS.find((level) => level === raw);
  return found ?? "medium";
}

/** The reading band each level is pitched at, for the vocabulary checks. */
function bandFor(level: DifficultyLevel): "primary" | "secondary" | "preUniversity" | "university" {
  switch (level) {
    case "veryEasy":
    case "easy":
      return "primary";
    case "medium":
      return "secondary";
    case "hard":
      return "preUniversity";
    case "expert":
      return "university";
  }
}

/**
 * The checks a generated question is DROPPED for.
 *
 * Deliberately narrower than the full battery. A practice question is judged on
 * whether it is in the right language, at the right level, and about the thing
 * the student asked to practise — the three ways a generated question can be
 * useless to the person who requested it. The softer signals (sentence length,
 * an unexplained term inside an explanation) are logged and left alone, because
 * silently binning a usable question to satisfy a heuristic costs the student a
 * question and gains them nothing.
 */
const DROP_ON_MAJOR = new Set<QualityFinding["check"]>([
  "language_quality",
  "practice_alignment",
  "adaptive_teaching",
]);

/**
 * Educational quality screening for ONE generated question (spec check 15).
 *
 * Note what is NOT here: nothing verifies the question's own mathematics, and
 * nothing could — a freshly invented question has never been through the solver,
 * so there is no proven answer to compare against. That is exactly why this is
 * the deterministic subset and no model opinion: asking an LLM whether an
 * unverified question is correct would put a second, unproven source of
 * mathematical truth into the app. The client re-enters every practice question
 * through the full `solve()` gate when the student answers it, and THAT is where
 * its maths is proven.
 */
function screenQuestion(
  q: PracticePayload["questions"][number],
  ctx: {
    language: string;
    difficulty: DifficultyLevel;
    skill: string;
    skillLabel: string;
    topic?: string;
  }
): QualityFinding[] {
  return runDeterministicChecks({
    explanation: {
      fields: [
        {
          id: "prompt",
          kind: "practice",
          text: [q.prompt, q.promptLatex, q.explanation].filter(Boolean).join("\n"),
        },
      ],
    },
    truth: {
      problemLatex: q.promptLatex ?? q.prompt,
      stepExpressions: [],
      verified: false,
      problemType: ctx.skill,
    },
    audience: {
      language: ctx.language,
      difficulty: ctx.difficulty,
      band: bandFor(ctx.difficulty),
      knownConcepts: [ctx.skill, ctx.skillLabel, ctx.topic].filter(
        (c): c is string => Boolean(c)
      ),
    },
    visuals: { anchors: [], actions: [] },
    // A generated question carries no verified solution and makes no claim to
    // one, so there is nothing for the certainty checks to hedge about.
    certainty: { state: "PASS" },
    practice: [
      {
        id: "prompt",
        prompt: q.prompt,
        explanation: q.explanation,
        skill: ctx.skill,
        difficulty: ctx.difficulty,
        concepts: [ctx.skill],
      },
    ],
    surface: "practice",
  });
}

/**
 * Keeps only the hints that are safe to show BEFORE the student has answered:
 * well-formed strings (max 2) that do not contain the question's correct
 * answer. A dropped hint costs nothing — the client falls back to per-skill
 * generic hints — while a leaked answer would defeat the whole hint ladder,
 * so the check errs toward dropping.
 *
 * Exported for tests (pure; no I/O).
 */
export function sanitizeHints(
  q: PracticePayload["questions"][number]
): string[] {
  const raw = Array.isArray(q.hints) ? q.hints : [];
  const answers = [
    ...(Array.isArray(q.acceptedAnswers) ? q.acceptedAnswers : []),
    ...(Array.isArray(q.options) ? q.options : [])
      .filter((o) => o && o.isCorrect === true)
      .map((o) => o.text),
  ]
    .filter((a): a is string => typeof a === "string")
    .map(normalizeForLeak)
    .filter((a) => a.length > 0);

  return raw
    .filter((h): h is string => typeof h === "string" && h.trim().length > 0)
    .slice(0, 2)
    .map((h) => h.trim())
    .filter((h) => {
      const hint = h.toLowerCase().replace(/[\s$,£€]/g, "");
      return !answers.some((a) =>
        // Numeric answers match on digit boundaries so an answer of "3"
        // doesn't falsely flag a hint that mentions a given "13".
        /^\d+$/.test(a)
          ? new RegExp(`(^|\\D)${a}(\\D|$)`).test(hint)
          : hint.includes(a)
      );
    });
}

/** Lowercase, strip spacing/currency and a leading assignment ("x=4" → "4") —
 * mirrors the client's answer normalization so the leak check compares the
 * same canonical form the answer matcher does. Applied to ANSWERS only; hints
 * keep their full text (an "=" inside a hint is prose, not an assignment). */
function normalizeForLeak(s: string): string {
  let value = s.trim().toLowerCase().replace(/[\s$,£€]/g, "");
  const eq = value.indexOf("=");
  if (eq >= 0) value = value.slice(eq + 1);
  return value;
}

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
