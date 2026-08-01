/**
 * The golden-rule gate for inline cards Numi attaches to a chat turn.
 *
 * A quiz card is not narration — it ASSERTS arithmetic ("option B is the
 * answer"). That is exactly what the architecture forbids the LLM from
 * inventing, so every card is checked here against mathjs before it reaches the
 * student, and a card that can't be checked is DROPPED (the reply still ships as
 * text). Numi silently teaching from a wrong quiz key is the one failure this
 * app must never have.
 *
 * Pure — no Firebase/OpenAI imports — so the gate is unit-testable in isolation.
 */
import { cleanLatex, latexToAscii, splitEquation, variablesIn } from "../solver/latex";
import { countSignChangeRoots, evalReal, verifySolution } from "../solver/verify";

/** The card shape the model is asked to emit (all fields untrusted). */
export interface RawTutorCard {
  kind?: unknown;
  prompt?: unknown;
  promptLatex?: unknown;
  options?: unknown;
  correctIndex?: unknown;
  explanation?: unknown;
  questionLatex?: unknown;
  difficulty?: unknown;
  encouragement?: unknown;
}

export interface QuizCardOut {
  kind: "quiz";
  prompt: string;
  promptLatex: string;
  options: string[];
  correctIndex: number;
  explanation: string;
}

export interface PracticeCardOut {
  kind: "practice";
  questionLatex: string;
  difficulty: "easy" | "medium" | "hard";
  xpReward: number;
  encouragement: string;
}

export type TutorCardOut = QuizCardOut | PracticeCardOut;

export interface CardVerdict {
  card: TutorCardOut | null;
  /** Why a card was dropped — logged, never shown to the student. */
  reason: string;
}

const DIFFICULTY_XP: Record<PracticeCardOut["difficulty"], number> = {
  easy: 15,
  medium: 30,
  hard: 45,
};

const MAX_TEXT = 400;

function str(value: unknown, max = MAX_TEXT): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

/**
 * Read an option as a real number.
 *
 * Options arrive as display text, so tolerate the shapes a tutor actually
 * writes: `3`, `x = 3`, `-1/2`, `\frac{1}{2}`, `x=-4`. Returns NaN for anything
 * that isn't a plain real value — which is a DROP, not a guess.
 */
export function optionValue(text: string): number {
  let s = text.trim();
  if (!s) return NaN;
  // Peel a leading assignment ("x = 3", "y=-1/2") — the value is what matters.
  s = s.replace(/^[a-zA-Z]\s*=\s*/, "");
  const ascii = latexToAscii(cleanLatex(s));
  // Reject anything still carrying a variable: an option like "2x" is not a
  // value we can substitute and check.
  if (variablesIn(ascii).length > 0) return NaN;
  return evalReal(ascii);
}

/**
 * Verify a multiple-choice quiz the model proposed.
 *
 * Accepts ONLY when the whole claim is machine-checkable:
 *   1. the prompt is an equation in exactly one unknown;
 *   2. every option is a plain real number;
 *   3. the option the model marked correct actually satisfies the equation;
 *   4. no OTHER option also satisfies it (two right answers = a broken quiz).
 *
 * Anything else — symbolic answers, word prompts, unparseable LaTeX — is
 * dropped. Numi keeps teaching in prose; it just doesn't get to run a quiz it
 * can't stand behind.
 */
export function verifyQuizCard(raw: RawTutorCard): CardVerdict {
  const prompt = str(raw.prompt, 200);
  const promptLatex = str(raw.promptLatex, 200);
  const explanation = str(raw.explanation);
  const rawOptions = Array.isArray(raw.options) ? raw.options : [];
  const options = rawOptions.map((o) => str(o, 80)).filter((o) => o.length > 0);
  const correctIndex =
    typeof raw.correctIndex === "number" ? Math.floor(raw.correctIndex) : -1;

  if (!prompt) return { card: null, reason: "quiz: missing prompt" };
  if (!promptLatex) return { card: null, reason: "quiz: missing promptLatex" };
  if (!explanation) return { card: null, reason: "quiz: missing explanation" };
  if (options.length < 2 || options.length > 4) {
    return { card: null, reason: `quiz: ${options.length} options` };
  }
  if (options.length !== rawOptions.length) {
    return { card: null, reason: "quiz: blank option" };
  }
  if (correctIndex < 0 || correctIndex >= options.length) {
    return { card: null, reason: "quiz: correctIndex out of range" };
  }
  if (new Set(options.map((o) => o.toLowerCase())).size !== options.length) {
    return { card: null, reason: "quiz: duplicate options" };
  }

  const ascii = latexToAscii(cleanLatex(promptLatex));
  const eq = splitEquation(ascii);
  if (!eq.isEquation) return { card: null, reason: "quiz: prompt is not an equation" };

  const unknowns = variablesIn(ascii);
  if (unknowns.length !== 1) {
    return { card: null, reason: `quiz: ${unknowns.length} unknowns` };
  }
  const unknown = unknowns[0];
  const parts = [{ lhs: eq.lhs, rhs: eq.rhs }];

  const values = options.map(optionValue);
  if (values.some((v) => !Number.isFinite(v))) {
    return { card: null, reason: "quiz: non-numeric option" };
  }

  if (!verifySolution(parts, { [unknown]: values[correctIndex] })) {
    return { card: null, reason: "quiz: marked answer fails substitution" };
  }
  for (let i = 0; i < values.length; i++) {
    if (i === correctIndex) continue;
    if (verifySolution(parts, { [unknown]: values[i] })) {
      return { card: null, reason: "quiz: a distractor also solves it" };
    }
  }

  return {
    card: { kind: "quiz", prompt, promptLatex, options, correctIndex, explanation },
    reason: "",
  };
}

/**
 * Verify a practice question Numi is offering the student to try.
 *
 * A practice card poses a question rather than asserting an answer, so the bar
 * is well-formedness, not substitution: it must be an equation in one unknown
 * that provably HAS a real solution. Handing a student an unsolvable "practice"
 * question is its own kind of lying.
 */
export function verifyPracticeCard(raw: RawTutorCard): CardVerdict {
  const questionLatex = str(raw.questionLatex, 200);
  const encouragement = str(raw.encouragement, 200);
  const difficulty =
    raw.difficulty === "easy" || raw.difficulty === "medium" || raw.difficulty === "hard"
      ? raw.difficulty
      : "medium";

  if (!questionLatex) return { card: null, reason: "practice: missing questionLatex" };
  if (!encouragement) return { card: null, reason: "practice: missing encouragement" };

  const ascii = latexToAscii(cleanLatex(questionLatex));
  const eq = splitEquation(ascii);
  if (!eq.isEquation) {
    return { card: null, reason: "practice: question is not an equation" };
  }
  const unknowns = variablesIn(ascii);
  if (unknowns.length !== 1) {
    return { card: null, reason: `practice: ${unknowns.length} unknowns` };
  }
  // A real root must exist. The sign-change scan is a LOWER bound, so zero
  // crossings is not proof of no solution — but it does mean we can't show it's
  // solvable, and unproven is a drop.
  if (countSignChangeRoots({ lhs: eq.lhs, rhs: eq.rhs }, unknowns[0]) < 1) {
    return { card: null, reason: "practice: no real solution found" };
  }

  return {
    card: {
      kind: "practice",
      questionLatex,
      difficulty,
      xpReward: DIFFICULTY_XP[difficulty],
      encouragement,
    },
    reason: "",
  };
}

/** Route an untrusted card to its verifier. Unknown kinds are dropped. */
export function verifyTutorCard(raw: unknown): CardVerdict {
  if (!raw || typeof raw !== "object") return { card: null, reason: "" };
  const card = raw as RawTutorCard;
  if (card.kind === "quiz") return verifyQuizCard(card);
  if (card.kind === "practice") return verifyPracticeCard(card);
  return { card: null, reason: `unknown card kind: ${String(card.kind)}` };
}
