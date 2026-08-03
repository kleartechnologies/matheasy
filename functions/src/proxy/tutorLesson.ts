/**
 * The golden-rule gate for Numi's STRUCTURED lesson — the goal / steps /
 * concept / common-mistake / final-answer object the app renders as cards
 * instead of a wall of chat prose.
 *
 * Structure is a readability change, not a licence to author maths. A card is
 * more dangerous than a paragraph, not less: an equation printed alone on a
 * tinted line, under a numbered step heading, in the app's own typography, is
 * read as something the app CHECKED. So every equation that reaches a card has
 * to earn it, in exactly one of two ways:
 *
 *   1. It is maths the app already has on screen and already verified — the
 *      problem, the step the student tapped, a verified step result, the
 *      verified answer. The model's characters are thrown away and the APP's
 *      copy is rendered, so a card can only ever echo what passed the solver.
 *   2. It is a CLOSED numeric identity ("9 = 3^2", "\frac{1}{2} = 0.5") with no
 *      free variable, which this module re-evaluates with mathjs and keeps only
 *      if both sides actually agree. This is what lets Teach Me show the little
 *      worked aside it needs without inventing a competing answer.
 *
 * Anything else — a rearranged line, an invented example with an unknown in it,
 * an expression that asserts nothing — is DROPPED. The step keeps its words and
 * loses its equation, which is the same trade `tutorFocus` makes: the
 * explanation still ships, the unverified maths does not.
 *
 * `finalAnswer` is stricter still. The model never authors it: it may only
 * REQUEST the answer card, and the string that renders is the app's verified
 * answer, substituted here. In a mode that must not reveal the answer there is
 * nothing to substitute, so the card cannot exist — the answer firewall covers
 * the cards for free.
 *
 * Pure — no Firebase/OpenAI imports — so the gate is unit-testable in isolation.
 */

import { cleanLatex, latexToAscii, splitEquation, variablesIn } from "../solver/latex";
import { closeEnough, evalReal } from "../solver/verify";
import { sameLatex } from "./tutorFocus";
import type { TutorMode } from "./tutorMode";

/** One numbered card: a short heading, two-or-three sentences, one equation. */
export interface LessonStepOut {
  title: string;
  explanation: string;
  /** The app's copy of a verified equation, or a checked numeric identity. */
  equation?: string;
}

export interface TutorLessonOut {
  goal: string;
  steps: LessonStepOut[];
  concept?: string;
  commonMistake?: string;
  /** The app's VERIFIED answer — never the model's. */
  finalAnswer?: string;
}

export interface LessonVerdict {
  lesson: TutorLessonOut | null;
  /** Why a lesson (or a field of it) was dropped — logged, never shown. */
  reason: string;
}

/**
 * What shape of lesson a mode is allowed to render.
 *
 * This is the mode contract from `tutorMode.ts` expressed in cards. Structure
 * must not smuggle a full solution into a mode that promised not to give one:
 * a Hint that renders six numbered steps has stopped being a hint, whatever the
 * prose around it says. So Hint gets the framing cards and no route at all,
 * Solve Together gets exactly the ONE step it is revealing this turn, and
 * Quiz Me gets no lesson — its format is the question it just asked, and a
 * lesson would answer it.
 */
export interface LessonShape {
  /** Zero means "framing only": a goal, the idea, the trap — never the route. */
  maxSteps: number;
  /** Whether the final-answer card may render at all in this mode. */
  mayShowAnswer: boolean;
  /**
   * Whether a step may print a closed arithmetic fact of the model's own
   * (`9 = 3^2`) rather than a line copied from the verified context.
   *
   * Separate from [mayShowAnswer] on purpose: Solve Together is walking the
   * real solution one move at a time and needs to be able to show the
   * arithmetic of the move it just revealed, but must still never print the
   * final answer card and run ahead of the student.
   */
  allowIdentity: boolean;
}

const LESSON_SHAPES: Record<TutorMode, LessonShape | null> = {
  hint: { maxSteps: 0, mayShowAnswer: false, allowIdentity: false },
  solveTogether: { maxSteps: 1, mayShowAnswer: false, allowIdentity: true },
  teachMe: { maxSteps: 6, mayShowAnswer: true, allowIdentity: true },
  showSolution: { maxSteps: 10, mayShowAnswer: true, allowIdentity: true },
  quizMe: null,
};

export function lessonShape(mode: TutorMode): LessonShape | null {
  return LESSON_SHAPES[mode] ?? null;
}

/**
 * What to tell the model about the lesson it may build this turn.
 *
 * The gate above enforces the shape whatever the model does, but a model told
 * "six steps" and then trimmed to one has written the wrong six: the surviving
 * step reads as an excerpt. So the contract is stated in the prompt as well as
 * enforced after it.
 */
export function lessonDirective(mode: TutorMode): string {
  switch (mode) {
    case "hint":
      return `LESSON SHAPE — a hint has NO steps. Send "lesson" only when a framing card genuinely helps: a "goal" naming what we are aiming at, and optionally "concept" or "commonMistake". Never send "steps" and never send "finalAnswer" — a numbered route IS the solution, and you are not giving one.`;
    case "solveTogether":
      return `LESSON SHAPE — exactly ONE step: the single move you are revealing this turn, as one card. Never send a second step, never send "finalAnswer". Your question to the student goes in "reply", not in the lesson.`;
    case "teachMe":
      return `LESSON SHAPE — this is the mode the cards were built for. Send a "goal", the steps that teach the idea (up to six), a "concept" card saying WHY it works, and a "commonMistake". Send "finalAnswer" only if you carried the worked example all the way to this problem's answer.`;
    case "showSolution":
      return `LESSON SHAPE — the full lesson: "goal", every verified step as its own numbered card (in order, copying the verified results), "concept" for the idea worth keeping, "commonMistake" for the trap, and "finalAnswer". This mode should almost always send a lesson — walking a solution as chat prose is exactly the wall of text the cards exist to replace.`;
    case "quizMe":
      return `LESSON SHAPE — send "lesson": null. Your format this turn is the question you are asking; a lesson would answer it for them.`;
  }
}

/** Caps. Deliberately tight — the whole point of the redesign is short cards. */
const MAX_GOAL = 160;
const MAX_TITLE = 60;
const MAX_EXPLANATION = 280;
const MAX_CONCEPT = 280;
const MAX_MISTAKE = 200;
const MAX_EQUATION = 300;
const MAX_ANSWER = 200;

function str(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

/**
 * Whether an equation the model wrote is a closed numeric identity that is
 * actually TRUE — `9 = 3^2`, `\frac{1}{2} = 0.5`, `12 \times 4 = 48`.
 *
 * A free variable disqualifies it: `2x = 6` is not a fact, it is a claim about
 * an unknown, and the only claims about this problem's unknown that may be
 * printed are the ones the solver verified. A bare expression with no `=`
 * disqualifies it too — it asserts nothing, so there is nothing to check, and a
 * lone `\frac{9}{16}` sitting under a step heading reads exactly like an answer.
 */
export function isTrueNumericIdentity(latex: string): boolean {
  const ascii = latexToAscii(cleanLatex(latex));
  if (!ascii) return false;
  const { isEquation, lhs, rhs } = splitEquation(ascii);
  if (!isEquation || !lhs || !rhs) return false;
  if (variablesIn(lhs).length > 0 || variablesIn(rhs).length > 0) return false;
  const a = evalReal(lhs);
  const b = evalReal(rhs);
  if (!Number.isFinite(a) || !Number.isFinite(b)) return false;
  return closeEnough(a, b);
}

/**
 * Resolve one step equation to something printable, or null.
 *
 * [allowed] wins first and returns the APP's characters, so the common case —
 * "print the line that is already on screen" — renders byte-for-byte what the
 * solver checked. Only when nothing matches does the numeric-identity tier get
 * a look, and only in modes cleared for it.
 */
export function resolveEquation(
  claimed: string,
  allowed: string[],
  allowIdentity: boolean
): string | null {
  if (!claimed) return null;
  const verified = allowed
    .map((s) => (typeof s === "string" ? s.trim() : ""))
    .filter((s) => s.length > 0 && s.length <= MAX_EQUATION)
    .find((s) => sameLatex(s, claimed));
  if (verified) return verified;
  if (allowIdentity && isTrueNumericIdentity(claimed)) return claimed;
  return null;
}

export interface LessonContext {
  /** Verified maths already on the student's screen, in this mode. */
  allowed: string[];
  /** The app's verified final answer, or "" when there isn't one to show. */
  answer: string;
  shape: LessonShape;
}

/**
 * Verify the structured lesson the model proposed.
 *
 * Returns `{lesson: null}` for anything that isn't a usable lesson — the turn
 * still ships as prose, exactly as it does today. Nothing here can fail the
 * turn; the worst case is that the student reads Numi's words without the cards
 * around them.
 */
export function verifyTutorLesson(raw: unknown, ctx: LessonContext): LessonVerdict {
  if (!raw || typeof raw !== "object") return { lesson: null, reason: "" };
  const lesson = raw as {
    goal?: unknown;
    steps?: unknown;
    concept?: unknown;
    commonMistake?: unknown;
    finalAnswer?: unknown;
  };

  const goal = str(lesson.goal, MAX_GOAL);
  if (!goal) return { lesson: null, reason: "lesson: missing goal" };

  const dropped: string[] = [];
  const steps: LessonStepOut[] = [];
  const rawSteps = Array.isArray(lesson.steps) ? lesson.steps : [];
  for (const item of rawSteps) {
    if (steps.length >= ctx.shape.maxSteps) {
      dropped.push("step over the mode's cap");
      break;
    }
    if (!item || typeof item !== "object") continue;
    const step = item as { title?: unknown; explanation?: unknown; equation?: unknown };
    const title = str(step.title, MAX_TITLE);
    const explanation = str(step.explanation, MAX_EXPLANATION);
    // A card with neither a heading nor a sentence is a blank box on screen.
    if (!title && !explanation) continue;

    const claimed = str(step.equation, MAX_EQUATION);
    const equation = resolveEquation(claimed, ctx.allowed, ctx.shape.allowIdentity);
    if (claimed && !equation) dropped.push("step equation is not verified maths");

    steps.push({
      title: title || explanation.slice(0, MAX_TITLE),
      explanation,
      ...(equation ? { equation } : {}),
    });
  }

  const concept = str(lesson.concept, MAX_CONCEPT);
  const commonMistake = str(lesson.commonMistake, MAX_MISTAKE);

  // THE ANSWER CARD. The model's string is read only as a REQUEST to show it;
  // what renders is the app's verified answer. In a withheld-answer mode there
  // is no verified answer in context, so the card cannot appear.
  const wants = str(lesson.finalAnswer, MAX_ANSWER);
  const answer = ctx.shape.mayShowAnswer ? str(ctx.answer, MAX_ANSWER) : "";
  let finalAnswer = "";
  if (wants && answer) {
    finalAnswer = answer;
    if (!sameLatex(wants, answer)) {
      // Not fatal — the verified string is what renders either way — but a model
      // reaching for a different answer is worth seeing in the logs.
      dropped.push("final answer differed from the verified one");
    }
  } else if (wants) {
    dropped.push("final answer withheld in this mode");
  }

  // A goal on its own is a heading, not a lesson: it would render as one lonely
  // card that says less than the sentence above it.
  if (steps.length === 0 && !concept && !commonMistake && !finalAnswer) {
    return { lesson: null, reason: "lesson: nothing to render but a goal" };
  }

  return {
    lesson: {
      goal,
      steps,
      ...(concept ? { concept } : {}),
      ...(commonMistake ? { commonMistake } : {}),
      ...(finalAnswer ? { finalAnswer } : {}),
    },
    reason: dropped.join("; "),
  };
}
