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
  /** The resulting expression after this step, as delimiter-free LaTeX. */
  expression: string;
  /** Short operation label, e.g. "Factor each group". */
  operation: string;
  /** Plain-language reason — the ONLY field the LLM authors. */
  why: string;
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
