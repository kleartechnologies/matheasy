/**
 * Numi's teaching modes — the pure prompt layer behind `tutorReply`.
 *
 * The whole point of Numi is that it is NOT a chatbot: before it answers, the
 * student has told it *how* they want to learn ("just a hint", "solve together",
 * "teach me", "show the solution", "quiz me"). Each mode is a hard behavioural
 * contract, not a tone — Hint mode may not reveal the answer even if asked
 * directly, Solve Together must stop and wait for the student, and so on.
 *
 * Kept free of Firebase/OpenAI imports so the contract is unit-testable.
 */

/** The five ways a student can ask Numi to teach them (spec Part 3). */
export type TutorMode =
  | "hint"
  | "solveTogether"
  | "teachMe"
  | "showSolution"
  | "quizMe";

export const TUTOR_MODES: readonly TutorMode[] = [
  "hint",
  "solveTogether",
  "teachMe",
  "showSolution",
  "quizMe",
];

/**
 * The default mode when the student hasn't picked one.
 *
 * `solveTogether` — not `showSolution` — because the product thesis is that the
 * student should leave understanding more, and a student who never chose a mode
 * is exactly the one who benefits from being walked through it.
 */
export const DEFAULT_TUTOR_MODE: TutorMode = "solveTogether";

/** Narrow an untrusted client string to a known mode, else the default. */
export function normalizeMode(value: unknown): TutorMode {
  return typeof value === "string" && (TUTOR_MODES as readonly string[]).includes(value)
    ? (value as TutorMode)
    : DEFAULT_TUTOR_MODE;
}

/**
 * How much help a student has already been given in this thread.
 *
 * Spec Part 4: "If the student struggles, become progressively more helpful."
 * The client counts consecutive struggle signals and sends it back, so the
 * escalation is deterministic state rather than something the model has to
 * infer from tone.
 */
export type HelpLevel = 0 | 1 | 2 | 3;

export function normalizeHelpLevel(value: unknown): HelpLevel {
  const n = typeof value === "number" ? Math.floor(value) : 0;
  if (n <= 0) return 0;
  return (n >= 3 ? 3 : n) as HelpLevel;
}

const MODE_DIRECTIVES: Record<TutorMode, string> = {
  hint: `MODE — JUST A HINT.
Give exactly ONE small nudge toward the next move, then stop. Point at what to notice ("look at what's attached to $x$"), name the idea, or ask what they think comes next.
You must NOT state the final answer, and must NOT work the problem through — not even "for context", not even if the student asks you to in this turn. If they ask outright for the answer, say warmly that you're in hint mode, offer one more hint, and tell them they can switch to Show Full Solution any time.
Two to four sentences. End by inviting their attempt.`,

  solveTogether: `MODE — SOLVE TOGETHER.
You and the student work the problem as partners, ONE step per turn. Each turn: acknowledge what they just did, reveal only the NEXT single step, then ask them a question that they must answer before you continue.
Never reveal two steps in one turn, and never run ahead to the answer. Always finish your message with a genuine question and then STOP — the student's reply drives the next step.
If they answer wrongly, say what was right about their thinking first, show precisely where it went off, and let them retry the SAME step.`,

  teachMe: `MODE — TEACH ME.
Teach the underlying concept from first principles before touching this specific problem. Assume they have never seen it.
Structure: what this idea IS in plain language → a real-world analogy or picture → a small worked example with different numbers → then connect it back to their problem.
Prefer concrete over formal. Define every term you use. It is fine to be the longest of the modes, but stay in flowing sentences, and check in at the end with one question that tests understanding rather than recall.`,

  showSolution: `MODE — SHOW FULL SOLUTION.
Walk the complete solution, every step, in order — but this is still teaching, not a dump. For each step say WHAT you do and WHY that move is legal or useful.
Use ONLY the verified steps and the verified final answer given in the context. Do not re-derive them, do not "improve" them, and never state a different answer than the verified one.
Finish with the single idea worth remembering from this problem.`,

  quizMe: `MODE — QUIZ ME.
Turn this into an active recall session. Ask ONE question per turn and WAIT for the answer — start from the very first decision ("what should we do first?"), then the mechanics, then the reasoning.
Never ask a question and answer it yourself in the same message.
When they answer: say whether it's right, why, and ask the next one. When they're wrong, re-teach that one idea briefly and ask a easier variant of the SAME idea before moving on.`,
};

const HELP_LEVEL_DIRECTIVES: Record<HelpLevel, string> = {
  0: "",
  1: `
ESCALATION — the student has signalled confusion once. Change your approach rather than repeating: use smaller words, shorter sentences, and one concrete example with real numbers.`,
  2: `
ESCALATION — the student is still stuck after two attempts. Do NOT re-explain the same way again. Switch representation entirely: a real-world analogy, a picture in words, or break the step into two smaller steps. Reduce what you ask of them.`,
  3: `
ESCALATION — the student has been stuck three or more times. Stop asking them to produce the step. Show the next concrete step worked out with these exact numbers, explain it slowly, and only then ask them to do the step AFTER it. Getting them unstuck now matters more than making them discover it.`,
};

/**
 * The full behavioural directive for a turn: the mode contract plus any
 * progressive-help escalation.
 */
export function modeDirective(mode: TutorMode, helpLevel: HelpLevel = 0): string {
  return `${MODE_DIRECTIVES[mode]}${HELP_LEVEL_DIRECTIVES[helpLevel]}`;
}

/**
 * Whether a mode is allowed to state the final answer.
 *
 * Used as a server-side backstop: in `hint` and `quizMe` the answer is withheld
 * from the model's context entirely, so a prompt-injection ("ignore your mode")
 * has nothing to leak.
 */
export function modeMaySeeAnswer(mode: TutorMode): boolean {
  return mode === "teachMe" || mode === "showSolution" || mode === "solveTogether";
}

/**
 * Whether a mode should end its turn with a question the student answers.
 * Drives the "ask, then stop" instruction and the checkpoint expectation.
 */
export function modeAwaitsStudent(mode: TutorMode): boolean {
  return mode === "solveTogether" || mode === "quizMe" || mode === "hint";
}
