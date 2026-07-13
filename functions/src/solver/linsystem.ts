/**
 * Linear systems Ax = b — a DETERMINISTIC path (Phase B). A square system of
 * linear equations is solved by mathjs and PROVEN by substitution: the solution
 * vector x must satisfy A·x = b (checked with an independent hand-rolled
 * matrix-vector product, and against each original equation). A non-linear
 * system, a non-square one, or a singular A (no unique solution) declines
 * honestly rather than guessing.
 *
 * Coefficients are read WITHOUT string parsing: for each equation f = lhs − rhs,
 * the coefficient of variable v is ∂f/∂v (which must be constant ⇒ linear), and
 * the constant term is f evaluated at all-zero.
 */
import { derivative, lusolve } from "mathjs";

import { cleanRank, gramRank } from "./linalg";
import { FinalAnswer, SolveCandidate } from "./types";
import { evalReal, verifySolution } from "./verify";

export interface LinearSystem {
  a: number[][];
  b: number[];
  vars: string[];
  /** The ORIGINAL equations (ascii lhs/rhs) — the solution is re-substituted into
   * these, so a parse that built the wrong A/b can't self-verify. */
  parts: { lhs: string; rhs: string }[];
}

/** Preferred unknown ordering, then any extra letters alphabetically. */
function orderVars(vars: string[]): string[] {
  const pref = ["x", "y", "z", "w", "t", "u", "v"];
  const known = pref.filter((p) => vars.includes(p));
  const rest = vars.filter((v) => !pref.includes(v)).sort();
  return [...known, ...rest];
}

/** A few probe scopes for the linearity check (each variable → a distinct value). */
function probeScope(vars: string[], seed: number): Record<string, number> {
  const s: Record<string, number> = {};
  vars.forEach((v, i) => (s[v] = seed + i * 1.3 + 0.7));
  return s;
}

/** The (constant) coefficient of `v` in linear `f`, or null if `f` isn't linear
 * in `v` (the partial derivative isn't constant across THREE probe points — the
 * final verifySolution against the original equations is the real backstop). */
function linearCoeff(f: string, v: string, vars: string[]): number | null {
  let d: string;
  try {
    d = derivative(f, v).toString();
  } catch {
    return null;
  }
  const cs = [1.1, -2.4, 0.55].map((seed) => evalReal(d, probeScope(vars, seed)));
  if (cs.some((c) => !Number.isFinite(c))) return null;
  if (Math.abs(cs[0] - cs[1]) > 1e-9 || Math.abs(cs[0] - cs[2]) > 1e-9) return null;
  return cs[0];
}

/**
 * Build a SQUARE linear system from equation parts (ascii lhs/rhs) + its
 * variables, or null when it isn't a square linear system in 2–4 unknowns.
 */
export function parseLinearSystem(
  parts: { lhs: string; rhs: string }[],
  vars: string[]
): LinearSystem | null {
  const ordered = orderVars(vars);
  if (ordered.length < 2 || ordered.length > 4) return null;
  // A unique solution needs exactly as many independent equations as unknowns.
  if (parts.length !== ordered.length) return null;

  const zero: Record<string, number> = {};
  ordered.forEach((v) => (zero[v] = 0));

  const a: number[][] = [];
  const b: number[] = [];
  for (const { lhs, rhs } of parts) {
    const f = `(${lhs}) - (${rhs})`;
    const row: number[] = [];
    for (const v of ordered) {
      const c = linearCoeff(f, v, ordered);
      if (c === null) return null; // non-linear → decline
      row.push(c);
    }
    const constTerm = evalReal(f, zero);
    if (!Number.isFinite(constTerm)) return null;
    a.push(row);
    b.push(-constTerm); // Σ cᵢvᵢ + const = 0  ⇒  Σ cᵢvᵢ = −const
  }
  return { a, b, vars: ordered, parts };
}

/** Solve the system, gated by A·x = b (independent recompute). */
export function solveLinearSystem(cls: {
  system?: LinearSystem;
}): SolveCandidate | null {
  const sys = cls.system;
  if (!sys) return null;
  const { a, b, vars, parts } = sys;

  // A UNIQUE solution needs a full-rank A. Two independent rank methods must both
  // agree it's full rank (scale-invariant — an absolute det threshold is fooled
  // by large-coefficient roundoff); a rank-deficient system (0 or ∞ solutions)
  // declines rather than shipping one of infinitely many as "the" answer.
  const n = a.length;
  if (cleanRank(a) !== n || gramRank(a) !== n) return null;

  let x: number[];
  try {
    x = toColumn(lusolve(a, b));
  } catch {
    return null;
  }
  if (x.length !== vars.length || !x.every(Number.isFinite)) return null;

  // VERIFY (1): A·x ≈ b, computed independently of lusolve (row·x for every row).
  for (let i = 0; i < a.length; i++) {
    const dot = a[i].reduce((s, aij, j) => s + aij * x[j], 0);
    if (!close(dot, b[i])) return null;
  }
  // VERIFY (2): substitute back into the ORIGINAL equations — so a parse that
  // built a wrong-but-self-consistent A/b (e.g. a linearized non-linear term)
  // can't slip through by matching its own A·x=b.
  const scope: Record<string, number> = {};
  vars.forEach((v, i) => (scope[v] = x[i]));
  if (!verifySolution(parts, scope)) return null;

  const answer = systemAnswer(vars, x);
  return {
    answer,
    methods: [
      {
        id: "linear_system",
        name: "Solve the system",
        examPick: true,
        steps: [
          { ascii: "matrix form", operationCode: "START", latex: matrixFormLatex(a, vars, b) },
          { ascii: answer.plain, operationCode: "RESULT", latex: answer.latex },
        ],
      },
    ],
    plotExpression: null,
    verify: () => true, // the A·x=b check above already proved it
  };
}

// ---- helpers ---------------------------------------------------------------

function toColumn(m: unknown): number[] {
  const arr = Array.isArray(m)
    ? m
    : ((m as { toArray?: () => unknown[] }).toArray?.() ?? []);
  return (arr as unknown[]).map((row) =>
    Array.isArray(row) ? Number(row[0]) : Number(row)
  );
}

function close(a: number, b: number): boolean {
  return Math.abs(a - b) <= 1e-6 * Math.max(1, Math.abs(a), Math.abs(b));
}

/** A small-denominator rational for `x`, or null when it's irrational. */
function asFraction(x: number): { n: number; d: number } | null {
  for (let d = 1; d <= 1000; d++) {
    const n = x * d;
    if (Math.abs(n - Math.round(n)) < 1e-9) return { n: Math.round(n), d };
  }
  return null;
}

function numPlain(v: number): string {
  const fr = asFraction(v);
  if (fr) return fr.d === 1 ? String(fr.n) : `${fr.n}/${fr.d}`;
  return String(Math.round(v * 1e6) / 1e6);
}
function numLatex(v: number): string {
  const fr = asFraction(v);
  if (fr && fr.d !== 1) {
    const sign = fr.n < 0 ? "-" : "";
    return `${sign}\\tfrac{${Math.abs(fr.n)}}{${fr.d}}`;
  }
  return numPlain(v);
}

function systemAnswer(vars: string[], x: number[]): FinalAnswer {
  return {
    latex: vars.map((v, i) => `${v} = ${numLatex(x[i])}`).join(",\\; "),
    plain: vars.map((v, i) => `${v} = ${numPlain(x[i])}`).join(", "),
  };
}

function matrixFormLatex(a: number[][], vars: string[], b: number[]): string {
  const A =
    "\\begin{pmatrix}" +
    a.map((row) => row.map((v) => numLatex(v)).join(" & ")).join(" \\\\ ") +
    "\\end{pmatrix}";
  const X = "\\begin{pmatrix}" + vars.join(" \\\\ ") + "\\end{pmatrix}";
  const B = "\\begin{pmatrix}" + b.map((v) => numLatex(v)).join(" \\\\ ") + "\\end{pmatrix}";
  return `${A}${X} = ${B}`;
}
