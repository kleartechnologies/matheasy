/**
 * The educational quality gate — the contract.
 *
 * Matheasy already proves the ANSWER. This layer asks the other half of the
 * question: is the EXPLANATION any good? Correct arithmetic wrapped in prose
 * that contradicts it, skips the reasoning, reaches for a word the student has
 * never met, points at a highlight that isn't there, or quietly slips back into
 * English is still a failed lesson — and it fails in a way the substitution gate
 * cannot see.
 *
 * THIS LAYER NEVER COMPUTES MATHEMATICS. Not once, not as a cross-check, not
 * "just to be sure". The verified solver is the only source of mathematical
 * truth in this app, and a second opinion about the maths would be a second
 * source of truth — which is exactly the thing the golden rule forbids. Every
 * check here compares WORDS against a solution that is already proven: it can
 * conclude "the prose says 7 and the verified answer is 5", which is set
 * membership, not arithmetic. It can never conclude what the answer should be.
 *
 * A failure regenerates the EXPLANATION ONLY. The verified answer, its steps,
 * its formulas and its verification never change, and never re-run.
 */
import type { AnchorRole, SemanticAnchor } from "../proxy/anchors";
import type { ActionType } from "../proxy/tutorActions";
import type { VerificationState } from "../proxy/tutorVerification";
import type { JourneyStageId, TeachingDifficulty } from "../solver/types";

// ---------------------------------------------------------------------------
// Scores
// ---------------------------------------------------------------------------

/** The six scored dimensions. Each is 0-100. */
export const QUALITY_DIMENSIONS = [
  /** Does the prose agree with the verified answer, steps, formulas, units, signs? */
  "mathematicalConsistency",
  /** Can the student follow it? */
  "teachingClarity",
  /** Is it pitched at the level they asked for? */
  "difficultyMatch",
  /** Is it written in their language, all the way through? */
  "languageQuality",
  /** Does everything it points at exist, in the right colour? */
  "visualConsistency",
  /** Is it teaching — introducing, sequencing, reminding — or just narrating? */
  "pedagogicalQuality",
] as const;

export type QualityDimension = (typeof QUALITY_DIMENSIONS)[number];

export type QualityScores = Record<QualityDimension, number>;

/** A perfect score. Every dimension starts here and is deducted from. */
export const PERFECT: QualityScores = {
  mathematicalConsistency: 100,
  teachingClarity: 100,
  difficultyMatch: 100,
  languageQuality: 100,
  visualConsistency: 100,
  pedagogicalQuality: 100,
};

/**
 * How the overall score is weighted.
 *
 * Mathematical consistency carries the most weight even though it is separately
 * required to be perfect, because a near-miss there should also crush the
 * overall score rather than let a strong lesson carry a contradiction.
 */
export const DIMENSION_WEIGHT: Record<QualityDimension, number> = {
  mathematicalConsistency: 0.3,
  pedagogicalQuality: 0.2,
  teachingClarity: 0.2,
  difficultyMatch: 0.1,
  languageQuality: 0.1,
  visualConsistency: 0.1,
};

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

/**
 * The fifteen checks, in spec order. The id is what gets logged, so it is
 * stable, snake_case, and never localised — these strings end up in dashboards.
 */
export const CHECK_IDS = [
  "mathematical_consistency",
  "difficulty_alignment",
  "language_quality",
  "concept_introduction",
  "visual_reference",
  "colour_consistency",
  "educational_flow",
  "hidden_steps",
  "student_memory",
  "terminology",
  "adaptive_teaching",
  "visual_learning_alignment",
  "ocr_awareness",
  "verification_awareness",
  "practice_alignment",
] as const;

export type CheckId = (typeof CHECK_IDS)[number];

/**
 * How badly a finding hurts.
 *
 * `hard` zeroes its dimension outright — it is reserved for the things that make
 * an explanation actively misleading rather than merely weak: contradicting the
 * verified answer, pointing at a visual that does not exist, asserting an answer
 * the verifier rejected. `major` and `minor` deduct.
 */
export type Severity = "hard" | "major" | "minor";

export const SEVERITY_PENALTY: Record<Severity, number> = {
  hard: 100,
  major: 25,
  minor: 8,
};

/** One thing wrong with one explanation. Logged; never shown to a student. */
export interface QualityFinding {
  check: CheckId;
  dimension: QualityDimension;
  severity: Severity;
  /** What is wrong, in engineer-facing English. Feeds the regeneration prompt. */
  detail: string;
  /** Which field it is wrong in, when the check can tell. */
  field?: string;
}

// ---------------------------------------------------------------------------
// Input — everything the gate is allowed to know
// ---------------------------------------------------------------------------

/** What kind of text a field is, which decides which checks apply to it. */
export type FieldKind =
  /** Problem-level narration: overview, concept, rationale, takeaway. */
  | "prose"
  /** Narration attached to one verified step. */
  | "step"
  /** A question put to the student (self-explain, prediction) — not an assertion. */
  | "question"
  /**
   * A caption: a topic name, an objective line, the name of a rule. It is read
   * for language and for contradictions like any other text, but it is not
   * narration — a title that names the topic is not jargon-before-definition,
   * and "Sum-product factoring" is not a step explained in three words.
   */
  | "label"
  /** A practice item's prompt or explanation. */
  | "practice";

/** One piece of the explanation, addressable so a finding can name it. */
export interface ExplanationField {
  /** Dotted path into the source document, e.g. `journey.2.summary`. */
  id: string;
  kind: FieldKind;
  text: string;
  /** The verified step this narrates, when it narrates one. */
  stepIndex?: number;
  /**
   * Anchors this field claims to point at. The generator DECLARES these; the
   * gate verifies they exist and are actually being drawn. Declaring them makes
   * check 5 exact and language-independent — a claim, checkable against the
   * app's own inventory, rather than a phrase we have to recognise in 32
   * languages.
   */
  visualRefs?: string[];
  /** The teaching colour this field asks for, if any. */
  role?: AnchorRole;
}

/** The explanation under review. */
export interface ExplanationDraft {
  fields: ExplanationField[];
  /** The teaching journey's stage order, for check 7. */
  journey?: JourneyStageId[];
  /** Which attempt this is, 1-based. Logged so retries are visible. */
  attempt?: number;
}

/**
 * The verified solution, as GROUND TRUTH.
 *
 * Everything here came out of the deterministic solver and through the
 * substitution gate. The quality layer reads it; it never questions it, and it
 * never recomputes any part of it.
 */
export interface VerifiedTruth {
  problemLatex: string;
  /** The answer, in every form the app holds it. */
  answerLatex?: string;
  answerPlain?: string;
  /** Each verified step's resulting expression, in order. */
  stepExpressions: string[];
  /** The step operations the engine (not a model) named. */
  stepOperations?: string[];
  /** Formula/rule names the engine attached, e.g. "quadratic formula". */
  formulas?: string[];
  /** Units the answer carries, e.g. `cm`, `m/s`. */
  units?: string[];
  /** Variables the problem actually uses. */
  variables?: string[];
  /** Was the answer proven? A false here changes what may be said. */
  verified: boolean;
  problemType?: string;
}

/** Who is reading, and what they have got wrong before. */
export interface Audience {
  /** BCP-47, already resolved through `contentLanguage`. */
  language: string;
  /** The five-level ladder the student picked. */
  difficulty: DifficultyLevel;
  /** The engine's own band for this problem, when known. */
  band?: TeachingDifficulty;
  /** Recurring mistakes from the student's memory, as app-owned tags. */
  recurringMistakes?: MistakeTag[];
  /** Concepts the student has already been taught and got right. */
  knownConcepts?: string[];
}

/** The student-selected difficulty ladder (spec check 2). */
export const DIFFICULTY_LEVELS = [
  "veryEasy",
  "easy",
  "medium",
  "hard",
  "expert",
] as const;

export type DifficultyLevel = (typeof DIFFICULTY_LEVELS)[number];

/**
 * The mistake vocabulary the app owns. Tags, not prose, so a reminder can be
 * required in any of 32 languages without matching words.
 */
export const MISTAKE_TAGS = [
  "negativeSigns",
  "fractions",
  "units",
  "algebra",
  "orderOfOperations",
  "distribution",
  "exponents",
  "wordProblemSetup",
  "geometryFormulas",
  "calculusRules",
] as const;

export type MistakeTag = (typeof MISTAKE_TAGS)[number];

/** What is actually on screen for this problem. */
export interface VisualInventory {
  /** Every place on the page the app located. */
  anchors: SemanticAnchor[];
  /** Every gesture that will actually be drawn this turn. */
  actions: Array<{ type: ActionType; target: string; role: AnchorRole }>;
  /**
   * The Visual Learning steps, when the animated player is in play: the step
   * index each scene shows and the expression it shows there.
   */
  visualSteps?: Array<{ stepIndex: number; expression: string }>;
}

/** How sure the app is, which decides what the explanation is allowed to claim. */
export interface CertaintyContext {
  state: VerificationState;
  /** The reader's confidence in its own transcription, 0-1. */
  ocrConfidence?: number;
  /** Marks the reader flagged as doubtful. */
  uncertainMarks?: string[];
}

/** A generated practice question, for check 15. */
export interface PracticeDraft {
  id: string;
  prompt: string;
  explanation?: string;
  /** The skill it is supposed to be practising. */
  skill: string;
  /** The difficulty it was requested at. */
  difficulty: DifficultyLevel;
  /**
   * Which rung of a practice ladder this is, when it belongs to one.
   *
   * A ladder is SUPPOSED to straddle the level — that is what makes it a ladder
   * — so its outer rungs are checked one step either side of the requested
   * difficulty rather than against it. Absent for an ordinary batch, where every
   * item must sit exactly where it was asked for.
   */
  rung?: "easier" | "similar" | "harder";
  /** Concepts the question actually uses, as declared by the generator. */
  concepts?: string[];
}

/** Move a level one rung, clamped at the ends of the ladder. */
export function shiftDifficulty(level: DifficultyLevel, delta: number): DifficultyLevel {
  const at = DIFFICULTY_LEVELS.indexOf(level);
  const to = Math.max(0, Math.min(DIFFICULTY_LEVELS.length - 1, at + delta));
  return DIFFICULTY_LEVELS[to];
}

/** Where a practice item is expected to sit, given the level that was requested. */
export function expectedDifficulty(
  requested: DifficultyLevel,
  rung?: PracticeDraft["rung"]
): DifficultyLevel {
  if (rung === "easier") return shiftDifficulty(requested, -1);
  if (rung === "harder") return shiftDifficulty(requested, 1);
  return requested;
}

/** Everything the gate may look at. */
export interface QualityInput {
  explanation: ExplanationDraft;
  truth: VerifiedTruth;
  audience: Audience;
  visuals: VisualInventory;
  certainty: CertaintyContext;
  practice?: PracticeDraft[];
  /** Which surface produced this, for logging: `teach`, `practice`, `tutor`. */
  surface: string;
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

export interface QualityReport {
  pass: boolean;
  overall: number;
  scores: QualityScores;
  findings: QualityFinding[];
  /** True when an LLM judge contributed; false for a deterministic-only run. */
  judged: boolean;
}

/**
 * The bar. Nothing renders below it.
 *
 * The two absolutes are not stylistic: an explanation that contradicts the
 * verified answer teaches the student the wrong thing, and one that points at a
 * highlight that was never drawn teaches them to distrust the app. Neither is
 * survivable at 99.
 */
export const PASS_CRITERIA = {
  overall: 95,
  mathematicalConsistency: 100,
  visualConsistency: 100,
} as const;

/**
 * The semantic colour vocabulary, as the spec fixes it.
 *
 * This is the shared contract between the anchor roles the server derives, the
 * gestures the tutor draws, and the `MathRole` palette the client paints — the
 * whole point being that a student learns "green means the unknown" once. Check
 * 6 rejects any explanation that colours a concept against this table.
 */
export const ROLE_COLOUR: Record<AnchorRole, string> = {
  unknown: "green",
  known: "blue",
  operation: "purple",
  answer: "gold",
  mistake: "red",
  hint: "orange",
  concept: "teal",
  memory: "yellow",
  aside: "neutral",
};

/** The canonical order of the teaching journey (check 7). */
export const JOURNEY_ORDER: JourneyStageId[] = [
  "understand",
  "chooseMethod",
  "apply",
  "simplify",
  "verify",
  "takeaway",
];
