/**
 * The LLM layer — narration only, never arithmetic (spec §1).
 *
 * Two jobs, both keeping the math out of the model's hands:
 *   • narrateDeterministic — the answer + every step are already computed; the
 *     LLM only writes the short `operation` label and the plain-language `why`.
 *     Its output is merged by index; if it disagrees or fails, we fall back to a
 *     humanized label and an empty why. It can never change an expression.
 *   • generateLlmCandidate — for problems no engine can solve, the LLM proposes
 *     a CANDIDATE (numeric solution + narrated steps). The orchestrator then puts
 *     that candidate through the verification gate; nothing ships unverified.
 */
import { logger } from "firebase-functions/v2";

import { asciiToLatex, latexToAscii } from "./latex";
import {
  Classification,
  FinalAnswer,
  MethodData,
  RawMethod,
  StepData,
} from "./types";

/** Injected JSON-mode completion (wired to OpenAI in the proxy; stubbed in tests). */
export type JsonCompleter = (
  system: string,
  user: string,
  maxTokens: number
) => Promise<Record<string, unknown>>;

// --- Deterministic narration ------------------------------------------------

interface StepNarration {
  operation?: unknown;
  why?: unknown;
}
interface MethodNarration {
  id?: unknown;
  steps?: unknown;
}

const NARRATE_SYSTEM = `You are Matheasy, a warm math tutor for students aged 8-18.
You are given a math problem and its ALREADY-SOLVED steps. The math is final and correct — DO NOT change, add, remove, or recompute any of it.
Return ONLY a JSON object (no prose, no markdown) of this exact shape:
{ "methods": [ { "id": "<same id>", "steps": [ { "operation": "<2-5 word label>", "why": "<one friendly sentence explaining this step>" } ] } ] }
Keep the same method ids and the same number of steps per method. "operation" is a short action label; "why" is one encouraging, plain-language sentence a student would understand.`;

/** Ask the LLM to narrate fixed steps; returns null on any failure. */
export async function narrateDeterministic(
  complete: JsonCompleter,
  cls: Classification,
  methods: RawMethod[]
): Promise<Record<string, MethodNarration> | null> {
  const brief = methods.map((m) => ({
    id: m.id,
    name: m.name,
    steps: m.steps.map((s) => ({
      expression: s.latex ?? asciiToLatex(s.ascii),
      op: s.operationCode,
    })),
  }));
  const user = `Problem (LaTeX): ${cls.latex}\nProblem type: ${cls.problemType}\nSolved methods and steps:\n${JSON.stringify(brief)}`;
  try {
    const json = await complete(NARRATE_SYSTEM, user, 1400);
    const rawMethods = Array.isArray(json.methods) ? json.methods : [];
    const byId: Record<string, MethodNarration> = {};
    for (const m of rawMethods as MethodNarration[]) {
      if (m && typeof m.id === "string") byId[m.id] = m;
    }
    return byId;
  } catch {
    return null;
  }
}

/** Merge deterministic methods with (optional) narration into the §4 shape. */
export function assembleMethods(
  methods: RawMethod[],
  narration: Record<string, MethodNarration> | null
): MethodData[] {
  return methods.map((m) => {
    const n = narration?.[m.id];
    const nSteps = Array.isArray(n?.steps) ? (n!.steps as StepNarration[]) : [];
    const steps: StepData[] = m.steps.map((s, i) => ({
      expression: s.latex ?? asciiToLatex(s.ascii),
      operation: str(nSteps[i]?.operation) || humanizeOperation(s.operationCode),
      why: str(nSteps[i]?.why),
    }));
    return { id: m.id, name: m.name, examPick: m.examPick, steps };
  });
}

// --- LLM-candidate tier -----------------------------------------------------

export interface CandidateAssignment {
  variable: string;
  value: number;
}

export interface LlmCandidate {
  answer: FinalAnswer;
  /** The answer expression as ascii (for equality / derivative-back checks). */
  answerAscii: string;
  /** Numeric solution(s): one per variable (system) or one per root. */
  assignments: CandidateAssignment[];
  methods: MethodData[];
}

const CANDIDATE_SYSTEM = `You are Matheasy, a careful math solver + tutor for students aged 8-18.
Solve the problem exactly. Return ONLY a JSON object (no prose, no markdown) of this exact shape:
{
  "answerLatex": "the final answer as delimiter-free LaTeX",
  "answerPlain": "the final answer in plain text",
  "solutions": [ { "variable": "x", "value": -1.5 } ],
  "methods": [ { "id": "method_id", "name": "Method name", "examPick": true, "steps": [ { "expression": "state after this step as delimiter-free LaTeX", "operation": "short label", "why": "one friendly sentence" } ] } ]
}
Rules:
- "value" must be a decimal number (e.g. 0.4, -1.5, 0.5235988), never a string, ALWAYS in RADIANS for trigonometric problems, and with at least 6 significant digits for non-integer values.
- "solutions" carries the numeric solution(s) the answer is CHECKED against:
  • Polynomial/linear equation: one entry per solution value (repeat "variable" for multiple roots).
  • System of equations: one entry per variable.
  • Trigonometric equation (infinitely many solutions): put the GENERAL solution in "answerLatex" (e.g. "x = \\frac{\\pi}{6} + 2\\pi n"), and list the PRINCIPAL numeric solutions in the interval [0, 2\\pi) in "solutions" as decimal radians (one entry each).
  • Indefinite integral: put the antiderivative (WITHOUT +C) in "answerLatex"; leave "solutions" as [].
  • Definite integral: put the exact value in "answerLatex" and "answerPlain"; leave "solutions" as [].
- Provide 1-2 methods, exactly one with "examPick": true, each with 2-5 steps.
- All LaTeX must be valid and delimiter-free (no $, no \\[ \\]).`;

/** Get a candidate solution from the LLM; returns null on failure. */
export async function generateLlmCandidate(
  complete: JsonCompleter,
  cls: Classification
): Promise<LlmCandidate | null> {
  const user = `Problem (LaTeX): ${cls.latex}\nProblem type: ${cls.problemType}`;
  let json: Record<string, unknown>;
  try {
    json = await complete(CANDIDATE_SYSTEM, user, 2000);
  } catch (err) {
    // Was swallowed silently — an OpenAI 429 / timeout / malformed JSON here is
    // the difference between "the model errored" and "we honestly couldn't
    // solve it", and the caller can't tell null apart. Log it.
    logger.error("generateLlmCandidate.completerFailed", {
      problemType: cls.problemType,
      err: String(err),
    });
    return null;
  }

  const answerLatex = str(json.answerLatex);
  const answerPlain = str(json.answerPlain) || answerLatex;
  if (!answerLatex) {
    logger.info("generateLlmCandidate.emptyAnswer", {
      problemType: cls.problemType,
    });
    return null;
  }

  const assignments: CandidateAssignment[] = [];
  if (Array.isArray(json.solutions)) {
    for (const s of json.solutions) {
      if (s && typeof s === "object") {
        const variable = str((s as Record<string, unknown>).variable) || cls.unknown;
        const value = Number((s as Record<string, unknown>).value);
        if (Number.isFinite(value)) assignments.push({ variable, value });
      }
    }
  }

  const methods = coerceMethods(json.methods);

  return {
    answer: { latex: answerLatex, plain: answerPlain },
    answerAscii: latexToAscii(answerLatex),
    assignments,
    methods,
  };
}

function coerceMethods(raw: unknown): MethodData[] {
  if (!Array.isArray(raw)) return [];
  const methods: MethodData[] = [];
  for (const m of raw) {
    if (!m || typeof m !== "object") continue;
    const mo = m as Record<string, unknown>;
    const steps: StepData[] = [];
    if (Array.isArray(mo.steps)) {
      for (const s of mo.steps) {
        if (!s || typeof s !== "object") continue;
        const so = s as Record<string, unknown>;
        const expression = str(so.expression);
        if (!expression) continue;
        steps.push({
          expression,
          operation: str(so.operation),
          why: str(so.why),
        });
      }
    }
    if (steps.length === 0) continue;
    methods.push({
      id: str(mo.id) || `method_${methods.length + 1}`,
      name: str(mo.name) || "Solution",
      examPick: mo.examPick === true,
      steps,
    });
  }
  // Guarantee exactly one exam pick.
  if (methods.length && !methods.some((m) => m.examPick)) {
    methods[0].examPick = true;
  }
  let seenPick = false;
  for (const m of methods) {
    if (m.examPick && seenPick) m.examPick = false;
    if (m.examPick) seenPick = true;
  }
  return methods;
}

// --- helpers ----------------------------------------------------------------

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

const OPERATION_LABELS: Record<string, string> = {
  ADD_TO_BOTH_SIDES: "Add to both sides",
  SUBTRACT_FROM_BOTH_SIDES: "Subtract from both sides",
  MULTIPLY_BOTH_SIDES: "Multiply both sides",
  DIVIDE_FROM_BOTH_SIDES: "Divide both sides",
  SIMPLIFY_LEFT_SIDE: "Simplify",
  SIMPLIFY_RIGHT_SIDE: "Simplify",
  SIMPLIFY_ARITHMETIC: "Simplify",
  SIMPLIFY_FRACTION: "Simplify the fraction",
  COLLECT_AND_COMBINE_LIKE_TERMS: "Combine like terms",
  FACTOR_SUM_PRODUCT_RULE: "Factor",
  BREAK_UP_TERM: "Split the middle term",
  FIND_ROOTS: "Find the roots",
  IDENTIFY_COEFFICIENTS: "Identify a, b, c",
  APPLY_QUADRATIC_FORMULA: "Apply the quadratic formula",
  SIMPLIFY_DISCRIMINANT: "Simplify the discriminant",
  DIFFERENTIATE: "Differentiate",
  RESULT: "Result",
  START: "Start",
  COMPUTE: "Compute",
  SIMPLIFY: "Simplify",
};

/** A friendly fallback label for an operation code. */
export function humanizeOperation(code: string): string {
  if (OPERATION_LABELS[code]) return OPERATION_LABELS[code];
  const words = code.toLowerCase().replace(/_/g, " ").trim();
  return words ? words.charAt(0).toUpperCase() + words.slice(1) : "Step";
}
