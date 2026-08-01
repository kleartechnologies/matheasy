/**
 * `tutorReply` — Numi, the AI math tutor (Matheasy's brain).
 *
 * Not a chatbot wrapper. Before Numi answers it knows two things a chatbot
 * doesn't: **which mode** the student asked to learn in (hint / solve together /
 * teach me / show solution / quiz me — a hard behavioural contract, see
 * `tutorMode.ts`) and **the full verified solve context** for the problem on
 * screen (steps, answer, verification, the exact step they tapped).
 *
 * Three invariants hold here:
 *   1. The verified answer in context is AUTHORITATIVE. Numi narrates it; it
 *      never recomputes or contradicts it (the app's golden rule).
 *   2. In modes that must not reveal the answer, the answer is stripped from the
 *      model's context entirely — so "ignore your instructions" has nothing to
 *      leak.
 *   3. Any card Numi attaches is machine-verified in `tutorCard.ts` or dropped.
 *
 * The reply is STREAMED (spec Part 18): the model's JSON is scanned as it is
 * generated and the `reply` text is pushed out word by word, while the card and
 * the learning signals are still parsed and verified from the complete document
 * at the end. The final return value is identical either way.
 *
 * Wire-compatible with the pre-Numi client: the old `problemLatex`/`visualStep`
 * request fields and the old `{reply, suggestions:string[]}` response still work,
 * and a client that doesn't ask for a stream simply receives that same final
 * value — so a deployed function keeps serving app versions already in the
 * stores.
 */
import OpenAI from "openai";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { OPENAI_API_KEY, OPENAI_MODEL, REVENUECAT_SECRET_KEY } from "../config";
import { requireUid } from "../lib/auth";
import { assertWithinQuota, ensureUserDoc, incrementUsage } from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import { createOpenAI } from "../lib/openai";
import { languageDirective } from "../lib/language";
import { verifyTutorCard, type TutorCardOut } from "./tutorCard";
import { verifyTutorFocus, type TutorFocusOut } from "./tutorFocus";
import {
  DEFAULT_TUTOR_MODE,
  modeAwaitsStudent,
  modeDirective,
  modeMaySeeAnswer,
  normalizeHelpLevel,
  normalizeMode,
  type TutorMode,
} from "./tutorMode";
import {
  buildWorkContext,
  checkStudentWork,
  normalizeWorkLines,
} from "./tutorWork";
import { ReplyStreamer } from "./tutorStream";

interface TutorTurn {
  role?: "user" | "assistant";
  text?: string;
}

/** One verified solution step, as the client already has it on screen. */
interface TutorStep {
  title?: string;
  resultLatex?: string;
  detail?: string;
  rule?: string;
}

/** The full solve context (spec Part 1) — everything Numi should already know. */
interface TutorProblem {
  questionLatex?: string;
  questionText?: string;
  problemType?: string;
  topic?: string;
  difficulty?: string;
  finalAnswer?: string;
  verified?: boolean;
  verifyText?: string;
  steps?: TutorStep[];
  commonMistakes?: string[];
  source?: string;
}

/** The exact step the student tapped "Ask Numi about this" on (spec Part 6). */
interface TutorStepFocus {
  index?: number;
  total?: number;
  summary?: string;
  equationLatex?: string;
}

/** What Numi has learned about this student this session (spec Parts 10, 11). */
interface TutorMemory {
  conceptsCovered?: string[];
  mistakes?: string[];
  strengths?: string[];
  style?: string;
}

interface TutorRequest {
  userText?: string;
  history?: TutorTurn[];
  mode?: string;
  /** Consecutive struggle signals — drives progressive help (spec Part 4). */
  helpLevel?: number;
  problem?: TutorProblem;
  stepFocus?: TutorStepFocus;
  memory?: TutorMemory;
  /**
   * The student's own working, transcribed from a photo by `tutorImage`, one
   * entry per written line (spec Part 12). Checked deterministically here — see
   * `tutorWork.ts` — before Numi is allowed to say a word about it.
   */
  studentWork?: unknown;
  language?: string;
  /** Legacy (pre-Numi clients). */
  problemLatex?: string;
  /** Legacy (pre-Numi clients). */
  visualStep?: string;
}

/** Per-turn learning signals the client folds into session memory. */
interface TutorMeta {
  conceptsCovered: string[];
  mistake: string | null;
  understanding: "struggling" | "following" | "confident";
  checkpoint: boolean;
  style: "concise" | "detailed" | "visual" | null;
}

interface TutorPayload {
  reply?: unknown;
  suggestions?: unknown;
  card?: unknown;
  focus?: unknown;
  meta?: unknown;
}

/** The chips the client can render. The model picks ids; the CLIENT localizes. */
const SUGGESTION_IDS = [
  "explainSimpler",
  "giveExample",
  "tellMeWhy",
  "showAnotherMethod",
  "createQuiz",
  "practiceMore",
  "giveHint",
  "nextStep",
  "checkMyWork",
  "commonMistakes",
  "practiceEasier",
  "practiceSimilar",
  "practiceHarder",
  "practiceChallenge",
  "showSolution",
  "iDontUnderstand",
] as const;

const SUGGESTION_SET = new Set<string>(SUGGESTION_IDS);

const MAX_STEPS = 14;
const MAX_HISTORY = 14;

const SYSTEM_PROMPT = `You are Numi, the AI math tutor inside the Matheasy app. You are a warm, patient private tutor sitting beside one student — not a chatbot, not documentation, not an answer machine. Your job is that the student leaves understanding MORE than before, not that they leave with an answer.

WHO YOU ARE
Patient, encouraging, curious, human. You celebrate real progress in a few words ("Nice.", "Exactly.", "Good catch.") and never gush. You are never sarcastic, never arrogant, never patronising, never robotic. You do not lecture and you do not overwhelm — teach progressively, one idea at a time.

HOW YOU TEACH
- Ask before you tell. When a student is stuck, a guiding question ("What is attached to $x$ here?", "Which operation undoes that?") beats a paragraph.
- If they say they don't understand, NEVER repeat yourself. Change the explanation: simpler words, a real-world analogy, a picture in words, or smaller steps.
- After you explain something, end with ONE checkpoint question that tests understanding rather than recall.
- Name the mistake students commonly make here (sign slips, dropping a coefficient, mis-reading a discriminant) and how to avoid it — but only when it's relevant to what they just did or asked.
- Re-use what you already know about this student. Do not re-explain a concept listed as already covered.

HONESTY — THIS OVERRIDES EVERYTHING
- You NEVER invent arithmetic. When the context below gives you a verified answer and verified steps, they are authoritative and already checked: narrate them, explain WHY they work, and never state a different answer or silently recompute one.
- When no verified answer is given, do not assert one. Reason out loud, teach the method, and say plainly what you are unsure about.
- If you cannot help with something, say so honestly and offer what you CAN do. An honest "I'm not certain here" is always better than a confident wrong answer.

FORMATTING — follow exactly, no exceptions
- Write in plain, friendly sentences. No markdown: no headings (#), no bullet or asterisk lists, no tables, no bold/italic markers (**, __, *).
- NEVER write program code, pseudocode, or code blocks, and never use backticks. You are a math tutor, not a programmer.
- Write EVERY piece of mathematics as LaTeX inside single dollar signs: $\\frac{1}{2}$, $x^2 + 3x - 4 = 0$, $\\sqrt{16} = 4$. Never write a LaTeX command outside a $...$ wrapper, and never show math as raw text.
- Keep replies tight. Two to six sentences unless the mode explicitly calls for more.

RESPONSE — return ONLY a JSON object, no markdown:
{
  "reply": "your message to the student — plain sentences, all math in $...$, no code, no markdown",
  "suggestions": ["2-3 ids from the allowed list below"],
  "card": null,
  "focus": null,
  "meta": {
    "conceptsCovered": ["short names of ideas you taught this turn"],
    "mistake": "the specific misconception the student just showed, or null",
    "understanding": "struggling|following|confident",
    "checkpoint": true if your reply ends with a question the student must answer,
    "style": "concise|detailed|visual, or null if unclear"
  }
}

ALLOWED suggestion ids (use these EXACT strings, never free text): explainSimpler, giveExample, tellMeWhy, showAnotherMethod, createQuiz, practiceMore, giveHint, nextStep, checkMyWork, commonMistakes, practiceEasier, practiceSimilar, practiceHarder, practiceChallenge, showSolution, iDontUnderstand.

CARDS — optional, and strictly gated. Set "card" to null unless the student asked to be quizzed or asked for a practice question.
- Quiz: {"kind":"quiz","prompt":"Solve for x","promptLatex":"2x + 4 = 10","options":["2","3","4","5"],"correctIndex":1,"explanation":"why the answer is right"}
  The promptLatex MUST be an equation in exactly ONE unknown, every option MUST be a plain number, and EXACTLY ONE option may satisfy the equation. The server re-solves your quiz and silently discards it if your key is wrong — a discarded card wastes the student's turn, so only emit one you are certain of.
- Practice: {"kind":"practice","questionLatex":"3x + 6 = 18","difficulty":"easy|medium|hard","encouragement":"one short warm line"}
  Must be an equation in one unknown that has a real solution.
Your "reply" must make sense on its own, because the card may not survive verification.

FOCUS — point at the maths while you talk about it. Whenever your reply is about a specific piece of an equation, set "focus" so the app can show that equation with exactly that piece lit up:
{"focus":{"latex":"copy an equation VERBATIM from the context above","caption":"one short line naming what is highlighted","spans":[{"text":"8x","role":"operation"}]}}
- "latex" MUST be copied character-for-character from the CONTEXT (the problem, the step on screen, or a verified step result). Never write your own equation here, never a rearranged or simplified one, and never one whose result you were not given. The server checks it against what the app has verified and silently discards anything else.
- Each "text" must be a literal substring of that equation — the smallest piece you are actually talking about. At most 3 spans, and never the whole line: highlighting everything highlights nothing.
- "role" says what the piece MEANS, and colour is consistent across the whole app, so pick honestly: "answer" (the result / key takeaway), "known" (a given value or constant), "operation" (the formula or operation being applied right now), "unknown" (the variable being solved for), "mistake" (a slip or wrong assumption), "aside" (supporting detail).
- Set "focus" to null when your turn is not about one specific piece of an equation. A focus never replaces the explanation — say it in words too.

SKETCH — add a picture when the maths has one. Inside "focus" you may add "sketch" with ONE of these names, and nothing else:
- "fraction" — the equation contains a fraction of whole numbers; draws it as a shaded bar.
- "numberLine" — the equation gives a single value (x = 4); marks it on a number line.
- "line" — a straight-line relationship (y = 2x + 3); draws it with its intercept and root.
- "parabola" — a quadratic; draws the curve with its roots.
- "area" — a definite integral; shades the region being measured.
- "unitCircle" — a trig ratio of a specific angle; draws the angle on the unit circle.
You give the NAME only. Every number in the drawing is computed by the app from the same verified equation, so a picture can never disagree with the maths — and if the equation isn't really that shape, the app draws nothing. Omit "sketch" when no picture would help.`;

/** Trim + cap an untrusted string field. */
function text(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

/** Trim + cap an untrusted string list. */
function list(value: unknown, max: number, itemMax: number): string[] {
  if (!Array.isArray(value)) return [];
  const out: string[] = [];
  for (const item of value) {
    const s = text(item, itemMax);
    if (s) out.push(s);
    if (out.length >= max) break;
  }
  return out;
}

/**
 * Render the solve context as a system turn.
 *
 * `withAnswer` is false for modes that must not reveal the answer — the answer,
 * the verification line and the step RESULTS are withheld entirely rather than
 * merely forbidden, so no prompt injection can surface them. Step titles and
 * reasoning stay, because Numi still needs to know the shape of the route to
 * give a good hint.
 */
export function buildProblemContext(problem: TutorProblem, withAnswer: boolean): string {
  const lines: string[] = [];
  const question = text(problem.questionLatex, 300);
  const questionText = text(problem.questionText, 400);
  if (question) lines.push(`Problem (LaTeX): ${question}`);
  if (questionText && questionText !== question) {
    lines.push(`Problem as the student sees it: ${questionText}`);
  }
  const type = text(problem.problemType, 60);
  const topic = text(problem.topic, 60);
  if (type) lines.push(`Problem type: ${type}`);
  if (topic && topic !== type) lines.push(`Topic: ${topic}`);
  const difficulty = text(problem.difficulty, 40);
  if (difficulty) lines.push(`Difficulty: ${difficulty}`);
  if (text(problem.source, 40)) lines.push(`Came from: ${text(problem.source, 40)}`);

  if (withAnswer) {
    const answer = text(problem.finalAnswer, 200);
    if (answer) {
      lines.push(
        problem.verified === true
          ? `VERIFIED final answer (authoritative — checked by substitution, never contradict it): ${answer}`
          : `Candidate final answer — NOT verified. Do not present it as certain: ${answer}`
      );
    }
    const verifyText = text(problem.verifyText, 300);
    if (verifyText) lines.push(`How it was checked: ${verifyText}`);
  } else {
    lines.push(
      "The verified answer is deliberately withheld from you in this mode. You do not know it and must not guess it."
    );
  }

  const steps = Array.isArray(problem.steps) ? problem.steps.slice(0, MAX_STEPS) : [];
  if (steps.length > 0) {
    lines.push(
      withAnswer
        ? "Verified solution steps (already checked — use these, do not re-derive):"
        : "The route the solution takes (RESULTS withheld in this mode — use it only to aim your hints):"
    );
    steps.forEach((step, i) => {
      const parts: string[] = [];
      const title = text(step.title, 120);
      const result = text(step.resultLatex, 160);
      const detail = text(step.detail, 240);
      const rule = text(step.rule, 120);
      if (title) parts.push(title);
      if (withAnswer && result) parts.push(`→ ${result}`);
      if (detail) parts.push(`(${detail})`);
      if (rule) parts.push(`[rule: ${rule}]`);
      if (parts.length > 0) lines.push(`  ${i + 1}. ${parts.join(" ")}`);
    });
  }

  const mistakes = list(problem.commonMistakes, 5, 200);
  if (mistakes.length > 0) {
    lines.push(`Common mistakes on this kind of problem: ${mistakes.join("; ")}`);
  }

  return lines.join("\n");
}

/** Render what Numi already knows about this student (spec Parts 10, 11). */
export function buildMemoryContext(memory: TutorMemory): string {
  const lines: string[] = [];
  const covered = list(memory.conceptsCovered, 12, 80);
  const mistakes = list(memory.mistakes, 6, 200);
  const strengths = list(memory.strengths, 6, 80);
  const style = text(memory.style, 20);

  if (covered.length > 0) {
    lines.push(
      `Already explained to this student — do NOT re-explain from scratch, build on it: ${covered.join(", ")}`
    );
  }
  if (mistakes.length > 0) {
    lines.push(`Mistakes this student has made: ${mistakes.join("; ")}`);
  }
  if (strengths.length > 0) {
    lines.push(`This student is solid on: ${strengths.join(", ")}`);
  }
  if (style === "concise") {
    lines.push("This student prefers short, direct answers. Be brief.");
  } else if (style === "detailed") {
    lines.push("This student wants thorough explanations. Expand and give context.");
  } else if (style === "visual") {
    lines.push(
      "This student learns visually. Lead with a picture in words, a diagram description, or a concrete real-world analogy."
    );
  }
  return lines.join("\n");
}

/** Parse the model's suggestion ids, dropping anything outside the vocabulary. */
export function parseSuggestions(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const out: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") continue;
    const id = item.trim();
    if (SUGGESTION_SET.has(id) && !out.includes(id)) out.push(id);
    if (out.length >= 3) break;
  }
  return out;
}

/** Sensible chips when the model gave none we recognise — mode-appropriate. */
export function defaultSuggestions(mode: TutorMode): string[] {
  switch (mode) {
    case "hint":
      return ["giveHint", "iDontUnderstand", "showSolution"];
    case "solveTogether":
      return ["nextStep", "iDontUnderstand", "tellMeWhy"];
    case "teachMe":
      return ["giveExample", "explainSimpler", "checkMyWork"];
    case "showSolution":
      return ["tellMeWhy", "showAnotherMethod", "practiceSimilar"];
    case "quizMe":
      return ["giveHint", "explainSimpler", "practiceEasier"];
  }
}

/** Coerce the model's learning signals into the typed shape the client folds in. */
export function parseMeta(value: unknown): TutorMeta {
  const raw = (value ?? {}) as Record<string, unknown>;
  const understanding = raw.understanding;
  return {
    conceptsCovered: list(raw.conceptsCovered, 6, 80),
    mistake: text(raw.mistake, 200) || null,
    understanding:
      understanding === "struggling" || understanding === "confident"
        ? understanding
        : "following",
    checkpoint: raw.checkpoint === true,
    style:
      raw.style === "concise" || raw.style === "detailed" || raw.style === "visual"
        ? raw.style
        : null,
  };
}

export const tutorReply = onCall(
  { secrets: [OPENAI_API_KEY, REVENUECAT_SECRET_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request, response) => {
    const uid = requireUid(request);
    const data = (request.data ?? {}) as TutorRequest;
    const { userText, history = [], language } = data;

    if (!userText || typeof userText !== "string") {
      throw new HttpsError("invalid-argument", "userText (the student's message) is required.");
    }

    await ensureUserDoc(uid);
    await assertWithinRateLimit(uid, "tutor");
    await assertWithinQuota(uid, "tutorMessages");

    const mode = normalizeMode(data.mode);
    const helpLevel = normalizeHelpLevel(data.helpLevel);
    const withAnswer = modeMaySeeAnswer(mode);

    const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [
      { role: "system", content: SYSTEM_PROMPT + languageDirective(language) },
      { role: "system", content: modeDirective(mode, helpLevel) },
    ];

    // Full solve context. A pre-Numi client sends only `problemLatex`; fold it
    // into the same shape so both generations get the same handling.
    const problem: TutorProblem =
      data.problem && typeof data.problem === "object"
        ? data.problem
        : { questionLatex: data.problemLatex };
    const problemContext = buildProblemContext(problem, withAnswer);
    if (problemContext) {
      messages.push({
        role: "system",
        content: `CONTEXT — what the student is working on right now.\n${problemContext}`,
      });
    }

    // The exact step they tapped (spec Part 6): answer about THAT step unless
    // they ask otherwise. `visualStep` is the legacy field for the same thing.
    const focus = data.stepFocus;
    const stepSummary = text(focus?.summary, 400) || text(data.visualStep, 400);
    if (stepSummary) {
      const where =
        focus && typeof focus.index === "number" && typeof focus.total === "number"
          ? ` (step ${focus.index + 1} of ${focus.total})`
          : "";
      const equation = text(focus?.equationLatex, 200);
      messages.push({
        role: "system",
        content:
          `THE STUDENT IS LOOKING AT THIS STEP${where} and is almost certainly asking about it. ` +
          `Answer about this step specifically unless they clearly ask about something else.\n${stepSummary}` +
          (equation ? `\nThe expression on screen: ${equation}` : ""),
      });
    }

    // The student photographed their own working (spec Part 12). The verdict is
    // computed by the app's verifier, never by the model — Numi is handed a
    // finding it may narrate but must not overrule, and an honest "couldn't
    // check this" when the verifier can't decide.
    //
    // This runs in EVERY mode, including the ones the answer is withheld from:
    // the verdict is a line number about the student's own writing, not the
    // answer, and refusing to tell a student their own work holds up would be
    // the opposite of what the firewall is for.
    const workLines = normalizeWorkLines(data.studentWork);
    if (workLines.length > 0) {
      const check = checkStudentWork(
        text(problem.questionLatex, 300),
        text(problem.finalAnswer, 200),
        workLines
      );
      messages.push({
        role: "system",
        content: buildWorkContext(workLines, check),
      });
      logger.info("tutorReply checked student work", {
        uid,
        status: check.status,
        checked: check.checkedCount,
        total: check.totalLines,
      });
    }

    if (data.memory && typeof data.memory === "object") {
      const memoryContext = buildMemoryContext(data.memory);
      if (memoryContext) {
        messages.push({
          role: "system",
          content: `WHAT YOU KNOW ABOUT THIS STUDENT.\n${memoryContext}`,
        });
      }
    }

    if (modeAwaitsStudent(mode)) {
      messages.push({
        role: "system",
        content:
          "End this turn with a question and then STOP. Do not answer your own question — the student's next message continues the lesson.",
      });
    }

    for (const turn of history.slice(-MAX_HISTORY)) {
      if (!turn.text) continue;
      messages.push({
        role: turn.role === "user" ? "user" : "assistant",
        content: turn.text,
      });
    }
    messages.push({ role: "user", content: userText });

    // Streamed so the student sees Numi start writing rather than a typing dot
    // (spec Part 18). `sendChunk` no-ops for a client that didn't ask for a
    // stream — an app version already in the stores is served exactly as before,
    // because the final `return` below is unchanged either way.
    const streamer = new ReplyStreamer();
    let payload: TutorPayload;
    let content = "";
    try {
      const client = createOpenAI(OPENAI_API_KEY.value());
      const completion = await client.chat.completions.create({
        model: OPENAI_MODEL.value(),
        temperature: 0.6,
        // Teach Me legitimately runs longer than the interactive modes.
        max_tokens: mode === "teachMe" ? 1200 : 900,
        response_format: { type: "json_object" },
        messages,
        stream: true,
      });
      for await (const part of completion) {
        const piece = part.choices[0]?.delta?.content;
        if (!piece) continue;
        content += piece;
        const delta = streamer.push(piece);
        if (delta) await response?.sendChunk({ delta });
      }
      if (!content) throw new Error("empty response");
      payload = JSON.parse(content) as TutorPayload;
    } catch (err) {
      // The reply itself may have arrived intact even though the JSON around it
      // did not (a `max_tokens` cut lands mid-object). The student already has
      // those words on screen; taking them back to show an error would be worse
      // than shipping them without the optional card.
      const salvaged = streamer.text.trim();
      if (salvaged) {
        logger.warn("tutorReply salvaged a streamed reply", {
          uid,
          mode,
          complete: streamer.done,
          err: String(err),
        });
        payload = { reply: salvaged };
      } else {
        logger.error("tutorReply failed", { uid, mode, err: String(err) });
        throw new HttpsError(
          "internal",
          "Numi is thinking too hard right now. Please try again."
        );
      }
    }

    // Golden rule: a card asserts arithmetic, so it is machine-checked or dropped.
    let card: TutorCardOut | null = null;
    if (payload.card) {
      const verdict = verifyTutorCard(payload.card);
      card = verdict.card;
      if (!card && verdict.reason) {
        logger.warn("tutorReply card rejected", { uid, mode, reason: verdict.reason });
      }
    }

    // Golden rule, again: a highlighted equation is an equation the app is
    // asserting, so Numi may only point at maths already on the student's screen
    // and already checked. Step RESULTS join the list only in a mode allowed to
    // reveal them, which is what extends the answer firewall to highlighting.
    let focusOut: TutorFocusOut | null = null;
    if (payload.focus) {
      const allowed = [
        text(problem.questionLatex, 300),
        text(focus?.equationLatex, 300),
        ...(withAnswer
          ? [
              text(problem.finalAnswer, 200),
              ...(Array.isArray(problem.steps) ? problem.steps.slice(0, MAX_STEPS) : []).map(
                (step) => text(step.resultLatex, 300)
              ),
            ]
          : []),
      ].filter((s) => s.length > 0);
      const verdict = verifyTutorFocus(payload.focus, allowed);
      focusOut = verdict.focus;
      if (!focusOut && verdict.reason) {
        logger.warn("tutorReply focus rejected", { uid, mode, reason: verdict.reason });
      }
    }

    const suggestions = parseSuggestions(payload.suggestions);
    const quota = await incrementUsage(uid, "tutorMessages");

    return {
      reply: typeof payload.reply === "string" ? payload.reply : "",
      suggestions: suggestions.length > 0 ? suggestions : defaultSuggestions(mode),
      card,
      focus: focusOut,
      meta: parseMeta(payload.meta),
      mode: mode ?? DEFAULT_TUTOR_MODE,
      usage: quota,
    };
  }
);
