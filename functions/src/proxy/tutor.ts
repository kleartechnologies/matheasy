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

import { OPENAI_API_KEY, REVENUECAT_SECRET_KEY } from "../config";
import { requireUid } from "../lib/auth";
import { assertWithinQuota, ensureUserDoc, incrementUsage } from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import { createOpenAI } from "../lib/openai";
import { chatParams } from "../lib/models";
import { languageDirective } from "../lib/language";
import { verifyTutorCard, type TutorCardOut } from "./tutorCard";
import { verifyTutorFocus, type TutorFocusOut } from "./tutorFocus";
import {
  anchorContextBlock,
  coerceSemanticAnchors,
  type SemanticAnchor,
} from "./anchors";
import { verifyTutorActions, type TutorActionOut } from "./tutorActions";
import {
  normalizeVerificationState,
  verificationDirective,
  verificationState,
  type VerificationState,
} from "./tutorVerification";
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

/**
 * How the problem was READ off the page — the scanner's draft transcription and
 * how sure it was (see `proxy/ocr.ts`).
 *
 * Numi needs this because the most common "the app is wrong" is not a wrong
 * solve, it is a wrong READ: a 5 taken for a 6, a missing prime, a lost minus.
 * Knowing the confidence and exactly which marks were doubtful lets her say
 * "the 6 in the second line was hard to read — is it a 6 or a 5?" instead of
 * defending an answer to a problem the student never wrote.
 */
interface TutorOcr {
  latex?: string;
  confidence?: number;
  uncertain?: string[];
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
  /** The scanner's read of the photo, when the problem came from one. */
  ocr?: TutorOcr;
  /** The practice questions the app has already generated for this problem. */
  practice?: string[];
  /**
   * The parts of the student's page Numi may point at, derived deterministically
   * at scan time (see `anchors.ts`). Empty for a typed problem.
   */
  anchors?: unknown;
  /**
   * How sure the app is (see `tutorVerification.ts`). The client may send one;
   * an absent or unrecognised value is recomputed here from the facts, so an
   * older client still gets the right behaviour.
   */
  verification?: unknown;
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
  /**
   * The photo the problem was scanned from, as base64 or a data URI. Optional,
   * and read only on the OPENING turn — see `openingScanImage`.
   */
  imageBase64?: string;
  /** MIME type for [imageBase64] when it isn't already a data URI. */
  mimeType?: string;
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
  /** Where to point on the student's page — verified in `tutorActions.ts`. */
  actions?: unknown;
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

/** Mirrors `MAX_IMAGE_BASE64_LEN` in `scan.ts` — ~5MB base64 ≈ 3.7MB decoded. */
const MAX_IMAGE_BASE64_LEN = 5_000_000;

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
  "actions": [],
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
You give the NAME only. Every number in the drawing is computed by the app from the same verified equation, so a picture can never disagree with the maths — and if the equation isn't really that shape, the app draws nothing. Omit "sketch" when no picture would help.

ACTIONS — point at their page while you talk. When the context includes a list of page anchors (THE PAGE ITSELF), the student is looking at a photo of their own worksheet and you can make the app draw on it:
{"actions":[{"type":"highlight","target":"angle_B"},{"type":"pulse","target":"equation"}]}
- "target" MUST be an id copied EXACTLY from the anchor list you were given. Never invent an id, never guess coordinates, never point at something that isn't listed — the server silently discards anything it cannot find, and a discarded action means you gestured at nothing.
- "type" is one of: highlight (tint the region — your default), circle (draw a ring around it), underline, glow, pulse (a soft repeating beat — use for "look here first"), flash (one quick blink), zoom, focusRegion (dim the rest of the page and spotlight this), fade (push it into the background), drawArrow (point at it from outside), drawBracket (bracket it as a group).
- At most TWO actions per turn, usually ONE. A page with six things lit up teaches nothing about where to look. Emit "actions":[] whenever you are not talking about a specific place on the page.
- Optional "role" sets the teaching colour and defaults to the anchor's own: "unknown" (what we're solving for), "known" (a given), "operation" (the formula at work), "answer" (the result), "mistake", "hint", "concept", "memory". Use it deliberately — colour means something here.
- THE POINT of an action is that it changes how you WRITE. When you point at something, refer to it by place, not by value: "look at this angle", "notice this denominator", "the side I've circled", "the highlighted radius" — NOT "the value 28" or "the number in the third line". The student can see exactly what you are pointing at.
- Actions decorate the page; they never assert arithmetic. Pointing at the unknown is allowed even in modes where you must not reveal the answer.`;

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

  // HOW IT WAS READ. Included in every mode, answer-withheld ones too: this is
  // about the transcription of the QUESTION, never about the answer.
  lines.push(...ocrLines(problem.ocr));

  // The practice already waiting for this student, so "give me another one"
  // points at a question the app has generated and checked rather than one Numi
  // invents on the spot.
  const practice = list(problem.practice, 5, 200);
  if (practice.length > 0) {
    lines.push(
      "Practice questions the app has already generated for this problem (you may point the student at these; they are checked):"
    );
    practice.forEach((q, i) => lines.push(`  ${i + 1}. ${q}`));
  }

  return lines.join("\n");
}

/**
 * The "how confident is the read" block.
 *
 * A low confidence or a listed doubtful mark is ACTIONABLE for a tutor: it turns
 * "no, the answer is right" into "which character is that?" — the only honest
 * response when the problem itself may be a misread.
 */
function ocrLines(ocr: TutorOcr | undefined): string[] {
  if (!ocr || typeof ocr !== "object") return [];
  const lines: string[] = [];
  const draft = text(ocr.latex, 300);
  const confidence =
    typeof ocr.confidence === "number" && Number.isFinite(ocr.confidence)
      ? Math.min(1, Math.max(0, ocr.confidence))
      : null;
  const uncertain = list(ocr.uncertain, 6, 160);

  if (draft) lines.push(`This problem was READ from a photo. The transcription: ${draft}`);
  if (confidence !== null) {
    lines.push(
      confidence < 0.7
        ? `The transcription confidence was LOW (${confidence.toFixed(2)}). If the student says the problem looks wrong, believe them — the likeliest fault is the read, not the maths.`
        : `Transcription confidence: ${confidence.toFixed(2)}.`
    );
  }
  if (uncertain.length > 0) {
    lines.push(
      `Marks the reader was unsure of — check these first if the student disputes the problem: ${uncertain.join("; ")}`
    );
  }
  return lines;
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

/**
 * The scanned photo to attach to THIS turn, or null.
 *
 * Attached only on the opening turn of a conversation. The reasoning:
 *
 *   • VALUE is front-loaded. The photo settles "is that a 5 or a 6?" and shows a
 *     figure no LaTeX line can carry — and once Numi has read it, that reading is
 *     in the transcript for every later turn. Re-sending the same pixels each
 *     message buys nothing.
 *   • COST is not. It is a mobile upload and a vision-token charge per message,
 *     on the one endpoint a student uses dozens of times per session.
 *
 * "Opening" is measured by the student's turns, not the transcript's length: a
 * chat that opens with Numi's greeting is still the student's first message, and
 * keying off `history.length` would silently mean "never".
 *
 * Anything oversized or not a plausible image is DROPPED, never an error — the
 * turn simply proceeds as it always did.
 */
export function openingScanImage(
  data: Pick<TutorRequest, "imageBase64" | "mimeType">,
  history: TutorTurn[]
): string | null {
  if (Array.isArray(history) && history.some((turn) => turn?.role === "user")) {
    return null;
  }
  const raw = typeof data.imageBase64 === "string" ? data.imageBase64.trim() : "";
  if (!raw || raw.length > MAX_IMAGE_BASE64_LEN) return null;
  if (raw.startsWith("data:")) {
    return /^data:image\/[a-z0-9.+-]+;base64,.+/i.test(raw) ? raw : null;
  }
  const mime =
    typeof data.mimeType === "string" && /^image\/[a-z0-9.+-]+$/i.test(data.mimeType.trim())
      ? data.mimeType.trim()
      : "image/jpeg";
  return `data:${mime};base64,${raw}`;
}

/**
 * The student's turn — with the scanned page attached when there is one.
 *
 * The trailing instruction matters as much as the image: without it a model
 * handed a photo of a solved problem will happily re-read the maths off the page
 * and start narrating ITS reading instead of the verified solve. The photo is
 * for seeing what is written, never for recomputing what it means.
 */
function userMessage(
  userText: string,
  image: string | null
): OpenAI.Chat.ChatCompletionMessageParam {
  if (!image) return { role: "user", content: userText };
  return {
    role: "user",
    content: [
      { type: "text", text: userText },
      { type: "image_url", image_url: { url: image } },
      {
        type: "text",
        text: "The image above is the photo this problem was scanned from. Use it to see what is actually on the page — the figure, the layout, the exact characters. The verified answer and steps in your context still stand: looking at the photo NEVER means recomputing them.",
      },
    ],
  };
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
  // 1GiB because the opening turn of a scanned-problem chat can carry a
  // multi-megabyte base64 photo through this process (see `openingScanImage`).
  { secrets: [OPENAI_API_KEY, REVENUECAT_SECRET_KEY], memory: "1GiB", timeoutSeconds: 120 },
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

    // THE PAGE. The anchors were located deterministically at scan time and make
    // the round trip with the conversation — no vision tokens are spent to point
    // at them, and pointing works on every turn, not just the one carrying the
    // photo.
    const anchors: SemanticAnchor[] = coerceSemanticAnchors(problem.anchors);
    const anchorContext = anchorContextBlock(anchors);
    if (anchorContext) {
      messages.push({ role: "system", content: anchorContext });
    }

    // HOW SURE THE APP IS. Computed from facts the app owns, and expressed as
    // behaviour: the doubtful states tell Numi to stop and check the question
    // with the student rather than to teach an answer they may not have asked.
    const state: VerificationState =
      normalizeVerificationState(problem.verification) ??
      verificationState({
        verified: problem.verified,
        hasAnswer: text(problem.finalAnswer, 200).length > 0,
        ocrConfidence: problem.ocr?.confidence,
        uncertain: problem.ocr?.uncertain,
      });
    messages.push({
      role: "system",
      content: verificationDirective(state, list(problem.ocr?.uncertain, 4, 160)),
    });

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

    // THE PHOTO ITSELF, on the opening turn of a chat about a scanned problem.
    // Everything else Numi gets is a transcription of the page; the page is the
    // only thing that can settle a dispute about what is actually written on it,
    // and for a figure it carries what no LaTeX line can. Only the opening turn
    // (see `openingScanImage`) — a conversation costs one upload, not one per
    // message — and its absence changes nothing else.
    const scanImage = openingScanImage(data, history);

    // Streamed so the student sees Numi start writing rather than a typing dot
    // (spec Part 18). `sendChunk` no-ops for a client that didn't ask for a
    // stream — an app version already in the stores is served exactly as before,
    // because the final `return` below is unchanged either way.
    const streamer = new ReplyStreamer();
    const client = createOpenAI(OPENAI_API_KEY.value());

    /** One streamed attempt, with or without the photo attached. */
    const attempt = async (image: string | null): Promise<TutorPayload> => {
      let content = "";
      const completion = await client.chat.completions.create({
        // Numi runs on the NARRATION tier at low effort: every number she is
        // allowed to say was already computed and verified by the solver (the
        // answer firewall), so what is being bought here is prose quality, and
        // she is on the latency-visible streaming path. `chatParams` also drops
        // the temperature a reasoning model would reject.
        //
        // A turn carrying the photo is a different job — it is READING a page —
        // so it goes to the reasoning tier, the one already proven on this app's
        // vision path.
        ...chatParams(
          image ? "tutorVision" : "tutor",
          // Teach Me legitimately runs longer than the interactive modes.
          { temperature: 0.6, maxTokens: mode === "teachMe" ? 1200 : 900 }
        ),
        response_format: { type: "json_object" },
        messages: [...messages, userMessage(userText, image)],
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
      return JSON.parse(content) as TutorPayload;
    };

    let payload: TutorPayload;
    try {
      try {
        payload = await attempt(scanImage);
      } catch (err) {
        // The photo is an ENHANCEMENT to the turn, never a requirement — and it
        // is the one part of this request that changes the model, the tier and
        // the request shape all at once. If that combination fails before a
        // single word reached the student, take the turn text-only rather than
        // let a scanned problem lose its tutor.
        if (!scanImage || streamer.text.trim()) throw err;
        logger.warn("tutorReply retrying without the scan photo", {
          uid,
          mode,
          err: String(err),
        });
        payload = await attempt(null);
      }
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

    // The same gate once more, for pointing: Numi may only gesture at places the
    // APP located on the page. An id nobody derived is dropped rather than
    // drawn — an outline at invented coordinates would point confidently at the
    // wrong part of the student's own homework.
    let actions: TutorActionOut[] = [];
    if (payload.actions) {
      const verdict = verifyTutorActions(payload.actions, anchors);
      actions = verdict.actions;
      if (verdict.reason) {
        logger.warn("tutorReply actions rejected", { uid, mode, reason: verdict.reason });
      }
    }

    const suggestions = parseSuggestions(payload.suggestions);
    const quota = await incrementUsage(uid, "tutorMessages");

    return {
      reply: typeof payload.reply === "string" ? payload.reply : "",
      suggestions: suggestions.length > 0 ? suggestions : defaultSuggestions(mode),
      card,
      focus: focusOut,
      actions,
      // Echoed so the client can show the same honesty in its own UI (a
      // "check the question" banner) without recomputing the rules.
      verification: state,
      meta: parseMeta(payload.meta),
      mode: mode ?? DEFAULT_TUTOR_MODE,
      usage: quota,
    };
  }
);
