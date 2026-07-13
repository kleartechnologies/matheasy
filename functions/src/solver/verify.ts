/**
 * The verification gate (spec §1.1) — the single source of truth.
 *
 * No answer is ever returned without being substituted back into the ORIGINAL
 * problem here and satisfying it within tolerance. mathsteps can silently return
 * a non-solution (e.g. `x^2 + 1 = 0` → `x^2 = -1`); the LLM tier can hallucinate.
 * This module is what makes either safe: whatever the candidate, it must check
 * out numerically against the real problem or it does not ship.
 */
import { derivative, evaluate, parse } from "mathjs";

import { variablesIn } from "./latex";

/** Deterministic sample points — fixed (not random) so tests are reproducible. */
const SAMPLES = [-2.7, -1.3, 0.37, 1.6, 2.9, 4.2, -0.6];
/**
 * A wide, dense deterministic grid (-19.63 … 20.37, step 0.5). Used for equality
 * checks so we can still find enough in-domain points when the domain is
 * restricted (e.g. sqrt(x-4) is only defined for x>4). Non-integer offset avoids
 * landing on special points.
 */
const WIDE_SAMPLES = Array.from({ length: 81 }, (_, k) =>
  Number((-20 + k * 0.5 + 0.37).toFixed(4))
);
// Tolerance for substitution checks. Loose enough to accept a correctly-rounded
// IRRATIONAL candidate value (an LLM gives ~5-6 sig figs; substituting it back
// incurs error up to ~1e-5, amplified by the local derivative), yet far tighter
// than any structurally-wrong answer, which is off by orders of magnitude more.
const ABS_TOL = 1e-4;
const REL_TOL = 1e-4;
/** Minimum matching samples required to accept an equality/derivative check. */
const MIN_SAMPLES = 3;

/** Evaluate `expr` to a finite real number, or NaN on any failure/complex/etc. */
export function evalReal(expr: string, scope: Record<string, number> = {}): number {
  if (!expr || !expr.trim()) return NaN;
  try {
    const v = evaluate(expr, scope);
    if (typeof v === "number") return Number.isFinite(v) ? v : NaN;
    // Reject Complex / Unit / Matrix / Fraction-object results as non-real,
    // except a mathjs Fraction / BigNumber that coerces cleanly to a number.
    const n = Number(v as unknown as number);
    return Number.isFinite(n) ? n : NaN;
  } catch {
    return NaN;
  }
}

/** Two reals equal within absolute-or-relative tolerance. */
function close(a: number, b: number): boolean {
  if (!Number.isFinite(a) || !Number.isFinite(b)) return false;
  const diff = Math.abs(a - b);
  return diff <= ABS_TOL + REL_TOL * Math.max(1, Math.abs(a), Math.abs(b));
}

export interface EquationPart {
  lhs: string;
  rhs: string;
}

/**
 * Verify a solution assignment satisfies EVERY equation. Handles a single
 * unknown (`{x: -1}`) and systems (`{x: 2, y: 1}`) uniformly — each equation's
 * two sides must evaluate equal at the assignment.
 */
export function verifySolution(
  parts: EquationPart[],
  assignment: Record<string, number>
): boolean {
  if (parts.length === 0) return false;
  for (const v of Object.values(assignment)) {
    if (!Number.isFinite(v)) return false;
  }
  for (const { lhs, rhs } of parts) {
    const l = evalReal(lhs, assignment);
    const r = evalReal(rhs, assignment);
    if (!close(l, r)) return false;
  }
  return true;
}

/**
 * Verify each of `roots` satisfies the (single-unknown) equation. All roots must
 * check out AND there must be at least one — a "solution" of zero roots is not a
 * solution.
 */
export function verifyRoots(
  parts: EquationPart[],
  unknown: string,
  roots: number[]
): boolean {
  if (roots.length === 0) return false;
  return roots.every((r) => verifySolution(parts, { [unknown]: r }));
}

/**
 * True if `unknown` appears in a denominator of `expr` (division by it, or a
 * negative power like x^-1) — i.e. the expression can have POLES. The
 * sign-change root count is only a valid lower bound for pole-free expressions
 * (true polynomials); poles inject sign flips that aren't roots. Returns true
 * (the safe answer — "skip completeness") when the expression can't be parsed.
 */
export function unknownInDenominator(expr: string, unknown: string): boolean {
  type LooseNode = {
    type?: string;
    op?: string;
    name?: string;
    value?: unknown;
    args?: LooseNode[];
    traverse: (cb: (n: LooseNode) => void) => void;
  };
  const hasSymbol = (node: LooseNode | undefined): boolean => {
    if (!node) return false;
    let has = false;
    node.traverse((n) => {
      if (n.type === "SymbolNode" && n.name === unknown) has = true;
    });
    return has;
  };
  try {
    let found = false;
    (parse(expr) as unknown as LooseNode).traverse((node) => {
      const args = node.args;
      if (node.type === "OperatorNode" && node.op === "/" && hasSymbol(args?.[1])) {
        found = true;
      }
      // x^(negative constant) ⇒ x in a denominator
      if (
        node.type === "OperatorNode" &&
        node.op === "^" &&
        hasSymbol(args?.[0])
      ) {
        const exp = args?.[1];
        if (exp?.type === "ConstantNode" && Number(exp.value) < 0) found = true;
      }
    });
    return found;
  } catch {
    return true;
  }
}

/**
 * A LOWER BOUND on the number of distinct real roots of a single-variable
 * equation, by counting sign changes of `lhs - rhs` across a dense grid. If the
 * scan sees K sign changes there are provably ≥K real roots, so a candidate
 * offering fewer roots is demonstrably incomplete. (It can undercount — touching
 * even-multiplicity roots or roots outside the window — so it's only ever used
 * as a floor, never to reject a complete answer.)
 */
export function countSignChangeRoots(
  part: EquationPart,
  unknown: string
): number {
  let count = 0;
  let prevSign = 0;
  // Offset grid: an integer/half-integer step would land EXACTLY on nice roots
  // (p = 0, neither + nor −), hiding the sign change. The 0.017 offset + 0.1
  // step avoids coinciding with typical rational roots.
  const start = -50;
  const step = 0.1;
  const steps = 1000;
  for (let i = 0; i <= steps; i++) {
    const x = start + 0.017 + i * step;
    const l = evalReal(part.lhs, { [unknown]: x });
    const r = evalReal(part.rhs, { [unknown]: x });
    const p = l - r;
    if (!Number.isFinite(p)) {
      prevSign = 0; // a domain hole breaks the sign-change chain
      continue;
    }
    const sign = p > 0 ? 1 : p < 0 ? -1 : 0;
    if (sign !== 0) {
      if (prevSign !== 0 && sign !== prevSign) count++;
      prevSign = sign;
    }
  }
  return count;
}

/**
 * Verify two expressions are equal everywhere (used for simplify). Strategy:
 *   1. syntactically identical (whitespace-normalized) ⇒ trivially equal;
 *   2. no variables ⇒ compare the two constant values;
 *   3. otherwise scan a wide, dense grid, comparing at every point where BOTH
 *      sides are finite reals — reject on any mismatch, accept once at least
 *      MIN_SAMPLES in-domain points agree. The wide grid is what lets restricted
 *      domains (sqrt/log with large offsets) still find enough valid points.
 */
export function verifyEquality(
  original: string,
  candidate: string,
  vars: string[]
): boolean {
  if (normalizeExpr(original) === normalizeExpr(candidate)) return true;

  if (vars.length === 0) {
    const a = evalReal(original);
    const b = evalReal(candidate);
    return !Number.isNaN(a) && !Number.isNaN(b) && close(a, b);
  }

  let matched = 0;
  for (let i = 0; i < WIDE_SAMPLES.length; i++) {
    const scope: Record<string, number> = {};
    vars.forEach((v, k) => {
      scope[v] = WIDE_SAMPLES[(i + k * 7) % WIDE_SAMPLES.length];
    });
    const a = evalReal(original, scope);
    const b = evalReal(candidate, scope);
    if (Number.isNaN(a) || Number.isNaN(b)) continue;
    if (!close(a, b)) return false;
    matched++;
  }
  return matched >= MIN_SAMPLES;
}

/** Whitespace-stripped form for a cheap syntactic-equality check. */
function normalizeExpr(s: string): string {
  return s.replace(/\s+/g, "");
}

/**
 * Verify `candidate = d/d<unknown>(target)` by comparing to mathjs's own
 * derivative numerically at several points. Used both to confirm the
 * deterministic derivative and to check an integral by differentiating back.
 */
export function verifyDerivative(
  target: string,
  candidate: string,
  unknown: string
): boolean {
  let d: ReturnType<typeof derivative>;
  try {
    d = derivative(target, unknown);
  } catch {
    return false;
  }
  // Sample the unknown AND any other free symbols (a parameter like `a`, or a
  // second variable) so parametric derivatives verify — and, critically, so an
  // unrelated symbol makes evaluate return NaN (couldn't-verify) rather than
  // throw an uncaught error out of the request.
  const vars = [
    ...new Set([unknown, ...variablesIn(target), ...variablesIn(candidate)]),
  ];
  let matched = 0;
  for (let i = 0; i < SAMPLES.length; i++) {
    const scope: Record<string, number> = {};
    vars.forEach((v, k) => {
      scope[v] = SAMPLES[(i + k) % SAMPLES.length];
    });
    let a: number;
    try {
      const v = d.evaluate(scope);
      a = typeof v === "number" && Number.isFinite(v) ? v : NaN;
    } catch {
      a = NaN;
    }
    const b = evalReal(candidate, scope);
    if (Number.isNaN(a) || Number.isNaN(b)) continue;
    if (!close(a, b)) return false;
    matched++;
  }
  return matched >= MIN_SAMPLES;
}

/** Strip a trailing integration constant (`+ C`) from an integral candidate. */
export function stripIntegrationConstant(candidate: string): string {
  return candidate.replace(/\s*[+\-]\s*C\b\s*$/i, "").trim();
}

/**
 * Definite integral of `integrand` d(unknown) from `a` to `b` by composite
 * Simpson's rule (exact for cubics, ~1e-9 otherwise). This is the deterministic
 * ENGINE that verifies a definite-integral candidate. Returns NaN if a bound or
 * any sample is non-finite (e.g. a singularity in range).
 */
export function numericIntegrate(
  integrand: string,
  unknown: string,
  a: string,
  b: string
): number {
  const lo = evalReal(a);
  const hi = evalReal(b);
  if (Number.isNaN(lo) || Number.isNaN(hi)) return NaN;
  if (lo === hi) return 0;
  const N = 1000; // even
  const h = (hi - lo) / N;
  const f = (x: number) => evalReal(integrand, { [unknown]: x });
  let sum = f(lo) + f(hi);
  if (Number.isNaN(sum)) return NaN;
  for (let i = 1; i < N; i++) {
    const fx = f(lo + i * h);
    if (Number.isNaN(fx)) return NaN;
    sum += (i % 2 === 0 ? 2 : 4) * fx;
  }
  return (h / 3) * sum;
}

/** Absolute-or-relative closeness, exported for cross-engine comparisons. */
export function closeEnough(a: number, b: number): boolean {
  return close(a, b);
}

// ---- Inequalities ----------------------------------------------------------

/** A single interval of the real line. `null` bound = ±∞; `*Open` = exclusive. */
export interface Interval {
  lo: number | null;
  hi: number | null;
  loOpen: boolean;
  hiOpen: boolean;
}

export type IneqOp = "<" | ">" | "<=" | ">=";

function inIntervals(x: number, intervals: Interval[]): boolean {
  return intervals.some((iv) => {
    const okLo = iv.lo === null || (iv.loOpen ? x > iv.lo : x >= iv.lo);
    const okHi = iv.hi === null || (iv.hiOpen ? x < iv.hi : x <= iv.hi);
    return okLo && okHi;
  });
}

function satisfies(diff: number, op: IneqOp): boolean {
  switch (op) {
    case "<":
      return diff < 0;
    case ">":
      return diff > 0;
    case "<=":
      return diff <= 0;
    case ">=":
      return diff >= 0;
  }
}

/**
 * Verify a candidate SOLUTION SET for `lhs op rhs` by sampling the real line: at
 * every test point, being inside the claimed intervals must match the
 * inequality actually holding there. Dense sampling around each boundary
 * catches a misplaced boundary; a separate check at each genuine equality
 * boundary confirms the open/closed choice (strict `<`/`>` → open, `≤`/`≥` →
 * closed). Points on the boundary (diff≈0) and domain holes (NaN) are skipped.
 */
export function verifyInequality(
  lhs: string,
  rhs: string,
  op: IneqOp,
  unknown: string,
  intervals: Interval[]
): boolean {
  if (!Array.isArray(intervals)) return false;
  const bounds = intervals
    .flatMap((iv) => [iv.lo, iv.hi])
    .filter((b): b is number => b !== null && Number.isFinite(b));

  // Sample grid: a wide span framing every finite boundary, each boundary ±δ,
  // and far tails for unbounded intervals.
  const lo = bounds.length ? Math.min(...bounds) - 10 : -50;
  const hi = bounds.length ? Math.max(...bounds) + 10 : 50;
  const samples = new Set<number>([-1e6, -1e4, 1e4, 1e6]);
  for (let x = lo; x <= hi; x += 0.5) samples.add(Number(x.toFixed(4)));
  for (const b of bounds) {
    samples.add(b - 1e-3);
    samples.add(b + 1e-3);
  }

  const diffAt = (x: number): number => {
    const l = evalReal(lhs, { [unknown]: x });
    const r = evalReal(rhs, { [unknown]: x });
    return Number.isFinite(l) && Number.isFinite(r) ? l - r : NaN;
  };

  let matched = 0;
  for (const x of samples) {
    const diff = diffAt(x);
    if (Number.isNaN(diff) || Math.abs(diff) < 1e-7) continue; // hole / on-boundary
    if (satisfies(diff, op) !== inIntervals(x, intervals)) return false;
    matched++;
  }
  if (matched < 8) return false; // too few valid points to trust

  // Open/closed correctness at genuine equality boundaries (lhs = rhs there).
  const boundaryClosed = op === "<=" || op === ">=";
  for (const iv of intervals) {
    for (const [b, open] of [
      [iv.lo, iv.loOpen],
      [iv.hi, iv.hiOpen],
    ] as [number | null, boolean][]) {
      if (b === null || !Number.isFinite(b)) continue;
      const d = diffAt(b);
      if (!Number.isNaN(d) && Math.abs(d) < 1e-6 && open === boundaryClosed) {
        return false; // an included boundary should be closed only for ≤/≥
      }
    }
  }
  return true;
}
