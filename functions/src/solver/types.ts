/**
 * Shared types for the deterministic solver pipeline.
 *
 * `SolvePayload` is the EXACT §4 contract the `solveEquation` function returns
 * (plus an out-of-band `usage` field appended by the proxy for the quota meter).
 * Everything else here is internal plumbing between classify → solve → verify →
 * narrate.
 *
 * The golden rule (spec §1): the answer is ALWAYS computed by a symbolic engine
 * and substituted back to verify. The LLM never produces the math — it only
 * writes the plain-language `why` for each already-computed step.
 */

// --- §4 wire contract -------------------------------------------------------

export interface FinalAnswer {
  /** Rendered form, e.g. `x_1 = -1,\; x_2 = \tfrac{2}{5}`. */
  latex: string;
  /** Screen-reader / copy-paste form, e.g. `x = -1 or x = 2/5`. */
  plain: string;
}

export interface StepData {
  /** The resulting expression after this step, as delimiter-free LaTeX.
   * The ONLY math field — ENGINE-frozen, never authored by the LLM. */
  expression: string;
  /** Short operation label, e.g. "Factor each group". NARRATION. */
  operation: string;
  /** Plain-language reason this move is VALID (never what it equals). NARRATION. */
  why: string;
  // --- v2 teaching narration (all optional; absent ⇒ today's thin step) ------
  /** The transform chip, e.g. `− 5`, `×LCM`. NARRATION. */
  operationSymbol?: string;
  /** "What changed" in plain language, revealed on demand. NARRATION (Pro). */
  explanation?: string;
  /** The trap AT THIS STEP, revealed on demand. NARRATION (Pro). */
  commonMistake?: string;
  /** A named property label ≤6 words, e.g. "Zero-product property". NARRATION (Pro). */
  rule?: string;
  /** An ELICITED QUESTION for the pivotal step (student answers before `why`). NARRATION. */
  selfExplainPrompt?: string;
  /** ENGINE-set — the step the journey's `apply` stage points at. */
  pivotal?: boolean;
}

export interface MethodData {
  /** Stable id, e.g. "factoring", "quadratic_formula". */
  id: string;
  name: string;
  /** The method a teacher would mark — exactly one method is the exam pick. */
  examPick: boolean;
  steps: StepData[];
}

export interface GraphKeyPoint {
  label: string;
  x: number;
  y: number;
}

/** One sampled point on the plotted curve. */
export interface CurvePoint {
  x: number;
  y: number;
}

export interface GraphData {
  kind: "function";
  /** The plotted expression as delimiter-free LaTeX, e.g. `5x^2 + 3x - 2`. */
  expression: string;
  keyPoints: GraphKeyPoint[];
  /**
   * Deterministic samples of the (verified) expression across a window around
   * the key points — the client draws the true curve as a polyline through
   * these, without needing to evaluate the LaTeX on-device.
   */
  curve: CurvePoint[];
}

/** The exact §4 schema. `finalAnswer`/`graph` are null when not applicable. */
export interface SolvePayload {
  problemLatex: string;
  problemType: string;
  finalAnswer: FinalAnswer | null;
  verified: boolean;
  methods: MethodData[];
  graph: GraphData | null;
  /**
   * True for a proof / abstract-algebra / real-analysis prompt: there is no
   * answer to compute-and-verify, so instead of a dishonest "couldn't verify"
   * the client offers to work through it in the AI tutor (spec §1 golden rule —
   * we never fake a proof). Absent/false for every ordinary problem.
   */
  routeToTutor?: boolean;
  // --- v2 teaching engine (additive; a v1 payload is a valid v2 payload) ------
  /** = SOLVE_SCHEMA_VERSION. TELEMETRY ONLY — never a client render gate. */
  schemaVersion?: number;
  /** The additive teaching layer. Capability = `teaching != null` (see §2.3);
   * absent ⇒ the client renders today's UI unchanged. */
  teaching?: TeachingLayer;
}

// --- v2 teaching layer (spec: docs/matheasy-teaching-engine-spec.md §2, §4) --
//
// The teaching layer is an ADDITIVE, LLM-NARRATED wrap over the FROZEN verified
// skeleton (spec §0.2). Only `expression` (above) carries math; every field here
// is either engine-derived metadata or pure "why" narration that structurally
// cannot assert a number the verify gate never saw (enforced by `validateTeaching`
// in solver/teach.ts). A teaching failure degrades to the v1 payload — invisible
// to correctness.

/** Bumped when the SolvePayload wire shape changes. Telemetry only. */
export const SOLVE_SCHEMA_VERSION = 2 as const;
/** Bumped to invalidate the teaching cache (independent of the verified core). */
export const TEACHING_SCHEMA_VERSION = "teach-v1";

/** Coarse teaching category — a stable snake_case string (NOT the client's Dart
 * `ProblemCategory` enum). The client parses it with a TOTAL, non-throwing map,
 * so a new value here can never crash an old client (spec R2). */
export type TeachingCategory =
  | "arithmetic"
  | "fractions"
  | "algebra"
  | "equations"
  | "inequalities"
  | "functions"
  | "trigonometry"
  | "calculus"
  | "statistics"
  | "probability"
  | "linear_algebra"
  | "geometry"
  | "sequences"
  | "word_problem"
  | "differential_equations"
  | "conceptual"
  | "other";

/** Schooling level a teaching layer is pitched at (steers tone/depth, not
 * scoring — kept distinct from the practice-item `easy|medium|hard` axis, R3). */
export type TeachingDifficulty =
  | "primary"
  | "secondary"
  | "preUniversity"
  | "university";

export interface TeachingHeader {
  /** ENGINE — from `deriveTeachingMeta`. */
  category: TeachingCategory;
  /** NARRATION — textbook-index topic, e.g. "Quadratic equation (integer roots)". */
  subcategory: string;
  /** ENGINE — from `deriveTeachingMeta`. */
  difficulty: TeachingDifficulty;
  /** NARRATION — a FORWARD goal, "you will be able to…" (≤14 words). */
  learningObjective: string;
  /** ENGINE-anchored — must equal the examPick method's name. */
  methodChosen: string;
  /** NARRATION — a PROPERTY of THIS problem (never a speed/quality comparison). */
  whyMethodChosen: string;
}

export interface ProblemOverview {
  asked: string;
  goal: string;
  /** LaTeX restatements of the givens. */
  givens: string[];
  /** NARRATION — a one-tap question gating the answer reveal (a QUESTION, so it
   * is EXEMPT from the numeric firewall — it may use estimation anchors). */
  predictionPrompt: string;
}

export interface DefinedTerm {
  term: string;
  plain: string;
}

export interface ConceptOverview {
  /** First-principles, tier-pitched. NARRATION. */
  body: string;
  definedTerms: DefinedTerm[];
}

export interface MethodAlternative {
  name: string;
  whenBetter: string;
}

export interface MethodRationale {
  alternatives: MethodAlternative[];
}

/** The fixed 6-stage learning journey. Stage LABELS are client constants; the
 * wire carries only the (optional) summary + engine-computed step indices. */
export type JourneyStageId =
  | "understand"
  | "chooseMethod"
  | "apply"
  | "simplify"
  | "verify"
  | "takeaway";

export interface JourneyStage {
  id: JourneyStageId;
  summary?: string;
  /** ENGINE — indices into the examPick method's steps (never model-supplied). */
  stepIndices: number[];
}

/** A refutation triple — the trap, WHY it's tempting, and the fix. */
export interface CommonMistake {
  mistake: string;
  whyTempting: string;
  fix: string;
}

/** A retrieval cue — a rule to recall a week later (distinct from the objective). */
export interface KeyTakeaway {
  headline: string;
  detail?: string;
}

/** One rung of the practice ladder — a PROBLEM, never an answer. Each rung is
 * re-verified by `buildPracticeLadder` before display and re-enters the full
 * `solve()` gate on tap. */
export interface PracticeItem {
  latex: string;
  plain?: string;
  rung: "easier" | "similar" | "harder";
  skillHint?: string;
}

export interface PracticeLadder {
  easier: PracticeItem;
  similar: PracticeItem;
  harder: PracticeItem;
}

export interface TeachingLayer {
  /** `full` (Pro) · `lite` (Free) · `concept_only` (honest / unverified). */
  depth: "full" | "lite" | "concept_only";
  /** WHY the problem is unverified — governs how much is safe to teach.
   * Present only when `depth === "concept_only"`. */
  honestReason?: "read_failure" | "uncovered_type" | "proof" | "multi_part";
  header: TeachingHeader;
  overview: ProblemOverview;
  concept: ConceptOverview;
  methodRationale: MethodRationale;
  journey: JourneyStage[];
  /** word_problem ONLY — English → equation, referencing only the givens. */
  translation?: string[];
  /** multi_part ONLY — "first solve X, then compute Y". */
  decompositionPlan?: string[];
  commonMistakes: CommonMistake[];
  keyTakeaway: KeyTakeaway;
  /** Pro (`full`) only; omitted for `concept_only`. */
  practiceLadder?: PracticeLadder;
}

/** What `deriveTeachingMeta` computes deterministically from the problem type —
 * the ENGINE-owned header fields the LLM is forbidden to choose. */
export interface TeachingMeta {
  category: TeachingCategory;
  difficulty: TeachingDifficulty;
}

// --- Internal pipeline types ------------------------------------------------

/** How the problem will be solved deterministically (or not). */
export type Strategy =
  | "equation" // solve for a single unknown (linear/quadratic/…)
  | "simplify" // simplify an expression in one variable
  | "arithmetic" // evaluate a pure-numeric expression
  | "derivative" // d/dx of an expression
  | "statistics" // a descriptive statistic over a data set (mean/median/…)
  | "linalg" // matrix/vector operation (det/inverse/eigenvalues) via mathjs
  | "linsystem" // a linear system Ax=b, solved via mathjs, verified by A·x=b
  | "simultaneous" // 2-var linear+quadratic pair: substitution, verified per-pair
  | "taylor" // Taylor/Maclaurin series via mathjs, proven by contact order
  | "conceptual" // a proof / abstract-algebra / analysis prompt → route to the tutor
  | "llm_candidate"; // engines can't solve it → constrained LLM, then verify

/** How an LLM-candidate answer gets proven. */
export type VerifyMode =
  | "substitution" // substitute the solution into the original equation(s)
  | "equality" // simplify: candidate must equal the original everywhere
  | "derivative_back" // indefinite integral: d/dx(candidate) == integrand
  | "definite_integral" // definite integral: numeric integration == candidate
  | "trig" // periodic equation: verify principal solutions + 2π-periodicity
  | "inequality" // solution set: points inside satisfy it, points outside don't
  | "word_problem" // NL: the answer must satisfy the model's EXTRACTED equation
  | "ode" // differential equation: substitute the candidate solution back in
  | "none"; // nothing to check against → forces couldn't-verify

export interface Classification {
  /** Snake-case §4 problemType, e.g. "quadratic_equation". */
  problemType: string;
  strategy: Strategy;
  /** The unknown to solve for / differentiate against (default "x"). */
  unknown: string;
  /** True when the normalized input contains a top-level `=`. */
  isEquation: boolean;
  /** The LaTeX input as ascii-math (what mathsteps/mathjs consume). */
  ascii: string;
  /** The original, cleaned LaTeX for display (`problemLatex`). */
  latex: string;
  /** How to verify an LLM candidate for this problem (unused for det. paths). */
  verifyMode: VerifyMode;
  /** The operand of a derivative, as ascii (derivative strategy only). */
  derivativeTarget?: string;
  /** Order of a derivative (1 by default; 2 for d²/dx², etc.). */
  derivativeOrder?: number;
  /** The integrand of an integral, as ascii (integral paths). */
  integrand?: string;
  /** Lower/upper limits of a definite integral, as ascii. */
  lowerBound?: string;
  upperBound?: string;
  /** The requested descriptive statistic + its data set (statistics strategy). */
  statKind?: string;
  statData?: number[];
  /** An inequality's two sides (ascii) + operator, for the inequality gate. */
  ineqLhs?: string;
  ineqRhs?: string;
  ineqOp?: "<" | ">" | "<=" | ">=";
  /** A linear-algebra request: the operation + its matrix (+ a second, for A·B). */
  linalgOp?: string;
  matrixData?: number[][];
  matrixB?: number[][];
  /** A vector request: dot/cross/magnitude + the operand vector(s). */
  vectorOp?: string;
  vectorData?: number[][];
  /** A linear system Ax=b: the coefficient matrix, the RHS, the unknown order,
   * and the original equations (for re-substitution) — solved deterministically
   * and verified by A·x=b AND against the original equations. */
  system?: {
    a: number[][];
    b: number[];
    vars: string[];
    parts: { lhs: string; rhs: string }[];
  };
  /** A 2-var LINEAR + QUADRATIC simultaneous pair: the linear member's
   * coefficients (cu·vars[0] + cv·vars[1] + k = 0), the non-linear member, and
   * BOTH original equations — every candidate pair is re-substituted into the
   * originals, so a bad parse/composition can never self-verify. */
  simul?: {
    vars: [string, string];
    cu: number;
    cv: number;
    k: number;
    other: { lhs: string; rhs: string };
    parts: { lhs: string; rhs: string }[];
  };
  /** A Taylor/Maclaurin request: the function (ascii), center + its display, and
   * order. The expansion variable is `unknown`. */
  taylorFn?: string;
  taylorCenter?: number;
  taylorCenterLatex?: string;
  taylorOrder?: number;
  /** An ODE: the residual (ascii, in tokens indepVar/depVar/dy/ddy), its
   * variables + order, and any numeric initial conditions — the LLM's candidate
   * solution is substituted into the residual to verify. */
  odeResidual?: string;
  odeDepVar?: string;
  odeIndepVar?: string;
  odeOrder?: number;
  odeInitial?: { order: number; at: number; value: number }[];
}

/** A raw deterministic step, before the LLM adds the `why`. */
export interface RawStep {
  /** Result expression as ascii-math (converted to LaTeX for the payload). */
  ascii: string;
  /** mathsteps changeType or a synthesized operation code. */
  operationCode: string;
  /** Pre-built LaTeX; used verbatim instead of converting `ascii` when set. */
  latex?: string;
}

/** A method the deterministic engine produced (steps have no `why` yet). */
export interface RawMethod {
  id: string;
  name: string;
  examPick: boolean;
  steps: RawStep[];
}

/**
 * What a deterministic solver hands back. `verify` is a closure the orchestrator
 * calls to prove the candidate against the ORIGINAL problem — nothing is trusted
 * until it returns true.
 */
export interface SolveCandidate {
  /** The verified-once-checked answer. */
  answer: FinalAnswer;
  methods: RawMethod[];
  /** Real numeric roots (equations) — also feed the graph. */
  roots?: number[];
  /** Quadratic coefficients when known, for the graph + formula method. */
  quadratic?: { a: number; b: number; c: number };
  /** The plottable expression (ascii) when the problem graphs, else null. */
  plotExpression?: string | null;
  /** Proves the candidate against the original problem. */
  verify: () => boolean;
}
