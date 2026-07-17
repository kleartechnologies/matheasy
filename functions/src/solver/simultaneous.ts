/**
 * Simultaneous LINEAR + QUADRATIC systems in two variables — a DETERMINISTIC
 * path (the GCSE/IGCSE staple: a line meeting a curve, e.g. the chained exam
 * form 2(x−y) = x+y−1 = 2x²−11y²).
 *
 * Method (all engine, no LLM): the linear equation expresses one variable in
 * terms of the other; composing that into the second equation gives a single-
 * variable function whose degree is PROVEN ≤ 2 by a sampling fit (the fit must
 * predict extra probe points, so a cubic/rational composition declines). The
 * quadratic formula then enumerates ALL real roots — completeness follows from
 * the degree bound — and every (x, y) pair is substitution-verified against
 * BOTH ORIGINAL equations before anything ships (golden rule: verify against
 * the original problem, never the composed form).
 */
import { derivative, parse } from "mathjs";

import { exactForm } from "./exact";
import { linearCoeff, orderVars } from "./linsystem";
import { FinalAnswer, SolveCandidate } from "./types";
import { evalReal, verifySolution } from "./verify";

export interface SimultaneousSystem {
  /** The two unknowns in display order (x before y). */
  vars: [string, string];
  /** The linear member's coefficients: cu·vars[0] + cv·vars[1] + k = 0. */
  cu: number;
  cv: number;
  k: number;
  /** The non-linear member (ascii lhs/rhs). */
  other: { lhs: string; rhs: string };
  /** BOTH original equations — every candidate pair is re-substituted into
   * these, so a bad parse/composition can never self-verify. */
  parts: { lhs: string; rhs: string }[];
}

const EPS = 1e-9;

/**
 * Detect a 2-equation, 2-variable system with EXACTLY ONE linear member (the
 * both-linear case belongs to parseLinearSystem, which classify tries first),
 * or null. The other member's shape is not constrained here — the degree-≤2
 * proof happens inside solveSimultaneous, where a decline is final.
 */
export function parseSimultaneous(
  parts: { lhs: string; rhs: string }[],
  vars: string[]
): SimultaneousSystem | null {
  if (parts.length !== 2) return null;
  const ordered = orderVars(vars);
  if (ordered.length !== 2) return null;

  const lin = parts.map(({ lhs, rhs }) => {
    const f = `(${lhs}) - (${rhs})`;
    const cu = linearCoeff(f, ordered[0], ordered);
    if (cu === null) return null;
    const cv = linearCoeff(f, ordered[1], ordered);
    if (cv === null) return null;
    const k = evalReal(f, { [ordered[0]]: 0, [ordered[1]]: 0 });
    if (!Number.isFinite(k)) return null;
    return { cu, cv, k };
  });
  const linearIdx = lin.findIndex(Boolean);
  if (linearIdx === -1 || lin.filter(Boolean).length !== 1) return null;

  const { cu, cv, k } = lin[linearIdx] as { cu: number; cv: number; k: number };
  // The linear member must actually relate the variables (0 = 0 doesn't).
  if (Math.abs(cu) < EPS && Math.abs(cv) < EPS) return null;

  return {
    vars: [ordered[0], ordered[1]],
    cu,
    cv,
    k,
    other: parts[1 - linearIdx],
    parts,
  };
}

/** Solve by substitution; every pair gated by BOTH original equations. */
export function solveSimultaneous(cls: {
  simul?: SimultaneousSystem;
}): SolveCandidate | null {
  const sys = cls.simul;
  if (!sys) return null;
  const { vars, cu, cv, k, other, parts } = sys;

  // Compose the other equation into a single-variable function by expressing
  // elimVar via the linear relation, then fit a·t² + b·t + c through p(0),
  // p(±1) and PROVE the degree bound: the fit must also predict p at two
  // independent probes, so a secretly cubic/rational/transcendental
  // composition declines. Evaluated NUMERICALLY through the original ascii —
  // no string surgery to get wrong.
  interface Composition {
    freeVar: string;
    elimVar: string;
    h: (t: number) => number;
    a: number;
    b: number;
    c: number;
  }
  const compose = (
    freeVar: string,
    elimVar: string,
    cFree: number,
    cElim: number
  ): Composition | null => {
    if (Math.abs(cElim) < EPS) return null;
    const h = (t: number): number => (-k - cFree * t) / cElim;
    const p = (t: number): number => {
      const scope = { [freeVar]: t, [elimVar]: h(t) };
      return evalReal(other.lhs, scope) - evalReal(other.rhs, scope);
    };
    const p0 = p(0);
    const p1 = p(1);
    const pm1 = p(-1);
    if (![p0, p1, pm1].every(Number.isFinite)) return null;
    const c = p0;
    const a = (p1 + pm1) / 2 - c;
    const b = (p1 - pm1) / 2;
    for (const t of [2, -3]) {
      const actual = p(t);
      if (!Number.isFinite(actual)) return null;
      const predicted = a * t * t + b * t + c;
      const tol = 1e-6 * Math.max(1, Math.abs(actual), Math.abs(predicted));
      if (Math.abs(actual - predicted) > tol) return null;
    }
    // EXACT degree proof (the sampling fit alone is foolable: a ~1e-7 cubic
    // term — or a degree-7 residual engineered to vanish at the five sample
    // points — slips through and the "complete" root set silently misses a
    // real solution). Substitute the linear relation SYMBOLICALLY (an AST
    // transform, NOT text surgery — a regex \b boundary misses the x in
    // "0.0000001x^3" because digit→letter is no word boundary) and require
    // the third derivative to be identically zero: exact for any polynomial
    // composition, and any non-polynomial that survives the numeric fit is
    // rejected here too.
    try {
      const linNode = parse(`((${-k}) + (${-cFree}) * ${freeVar}) / (${cElim})`);
      const gNode = parse(`(${other.lhs}) - (${other.rhs})`);
      const gSub = gNode.transform((node) =>
        node.type === "SymbolNode" &&
        (node as { name?: string }).name === elimVar
          ? linNode.cloneDeep()
          : node
      );
      const d3 = derivative(
        derivative(derivative(gSub, freeVar), freeVar),
        freeVar
      ).toString();
      const scale = Math.max(1, Math.abs(p(2)), Math.abs(p(-3)));
      for (const t of [0.37, 1.91, -2.53]) {
        const v = evalReal(d3, { [freeVar]: t });
        if (!Number.isFinite(v) || Math.abs(v) > 1e-9 * scale) return null;
      }
    } catch {
      return null; // not symbolically differentiable → cannot prove the degree
    }
    return { freeVar, elimVar, h, a, b, c };
  };

  // COMPLETENESS GUARD: eliminating the larger-|coefficient| variable is the
  // better-conditioned substitution, but it can SCALE the composed quadratic's
  // leading term below EPS (e.g. 10⁶x + y = 2·10⁶ with y = x² gives a ≈ 10⁻¹²),
  // and treating that as linear would silently DROP a real solution pair. So
  // try both elimination orders and prefer whichever keeps a genuine
  // quadratic; only when every order collapses is the composition truly
  // linear (a real single-intersection problem).
  const orderings: [string, string, number, number][] =
    Math.abs(cv) >= Math.abs(cu)
      ? [
          [vars[0], vars[1], cu, cv],
          [vars[1], vars[0], cv, cu],
        ]
      : [
          [vars[1], vars[0], cv, cu],
          [vars[0], vars[1], cu, cv],
        ];
  let chosen: Composition | null = null;
  let linearFallback: Composition | null = null;
  for (const [freeVar, elimVar, cFree, cElim] of orderings) {
    const comp = compose(freeVar, elimVar, cFree, cElim);
    if (!comp) continue;
    if (Math.abs(comp.a) >= EPS) {
      chosen = comp;
      break;
    }
    linearFallback ??= comp;
  }
  const comp = chosen ?? linearFallback;
  if (!comp) return null;
  const { freeVar, elimVar, h, a, b, c } = comp;

  // All real roots of the composed polynomial (degree ≤ 2 ⇒ this enumeration
  // is COMPLETE — no solution pair can be missing).
  let roots: number[];
  if (Math.abs(a) < EPS) {
    if (Math.abs(b) < EPS) return null; // constant: either 0=0 (∞) or false (0)
    roots = [-c / b];
  } else {
    const disc = b * b - 4 * a * c;
    const scale = Math.max(1, b * b, Math.abs(4 * a * c));
    // No real intersection: "no solutions" can't be substitution-verified, so
    // it declines honestly rather than asserting a negative.
    if (disc < -1e-9 * scale) return null;
    const sq = Math.sqrt(Math.max(0, disc));
    roots = distinct([(-b - sq) / (2 * a), (-b + sq) / (2 * a)]);
  }

  const pairs = roots.map((t) => ({ [freeVar]: t, [elimVar]: h(t) }));
  if (pairs.length === 0) return null;
  if (!pairs.every((s) => Object.values(s).every(Number.isFinite))) return null;
  // THE GATE: every pair must satisfy BOTH original equations.
  if (!pairs.every((s) => verifySolution(parts, s))) return null;

  const answer = pairsAnswer(vars, pairs);
  const intercept = h(0);
  const slope = h(1) - intercept;
  return {
    answer,
    methods: [
      {
        id: "substitution",
        name: "Substitution",
        examPick: true,
        steps: [
          {
            ascii: `${elimVar} = ${slope}*${freeVar} + ${intercept}`,
            operationCode: "REARRANGE",
            latex: `${elimVar} = ${linearLatex(slope, intercept, freeVar)}`,
          },
          {
            ascii: `${a}*${freeVar}^2 + ${b}*${freeVar} + ${c} = 0`,
            operationCode: "SUBSTITUTE",
            latex: `${polyLatex(a, b, c, freeVar)} = 0`,
          },
          {
            ascii: roots.map((r) => `${freeVar} = ${numPlain(r)}`).join(" or "),
            operationCode: "FIND_ROOTS",
            latex: roots
              .map((r) => `${freeVar} = ${numLatex(r)}`)
              .join(",\\; "),
          },
          { ascii: answer.plain, operationCode: "RESULT", latex: answer.latex },
        ],
      },
    ],
    plotExpression: null,
    verify: () => pairs.every((s) => verifySolution(parts, s)),
  };
}

// ---- helpers ---------------------------------------------------------------

/** Dedupe near-equal values, ascending. */
function distinct(values: number[]): number[] {
  const out: number[] = [];
  for (const v of values) {
    if (!out.some((x) => Math.abs(x - v) < EPS)) out.push(v);
  }
  return out.sort((x, y) => x - y);
}

/** A small-denominator rational for `x`, or null when it's irrational. */
function asFraction(x: number): { n: number; d: number } | null {
  for (let d = 1; d <= 1000; d++) {
    const n = x * d;
    if (Math.abs(n - Math.round(n)) < 1e-9) return { n: Math.round(n), d };
  }
  return null;
}

/** Integer → literal, small rational → fraction, then the exact-form
 * recognizer (√r, π multiples), then a trimmed decimal. Display only — the
 * numeric value was already substitution-verified. */
function numPlain(x: number): string {
  const fr = asFraction(x);
  if (fr) return fr.d === 1 ? String(fr.n) : `${fr.n}/${fr.d}`;
  const ex = exactForm(x);
  if (ex) return ex.plain;
  return String(Math.round(x * 1e6) / 1e6);
}

function numLatex(x: number): string {
  const fr = asFraction(x);
  if (fr) {
    if (fr.d === 1) return String(fr.n);
    const sign = fr.n < 0 ? "-" : "";
    return `${sign}\\tfrac{${Math.abs(fr.n)}}{${fr.d}}`;
  }
  const ex = exactForm(x);
  if (ex) return ex.latex;
  return String(Math.round(x * 1e6) / 1e6);
}

/** Render `slope·v + intercept` naturally (1x → x, drop zero terms). */
function linearLatex(slope: number, intercept: number, v: string): string {
  const terms: string[] = [];
  if (Math.abs(slope) > EPS) {
    if (Math.abs(slope - 1) < EPS) terms.push(v);
    else if (Math.abs(slope + 1) < EPS) terms.push(`-${v}`);
    else terms.push(`${numLatex(slope)}${v}`);
  }
  if (Math.abs(intercept) > EPS || terms.length === 0) {
    const rendered = numLatex(Math.abs(intercept));
    if (terms.length === 0) terms.push(numLatex(intercept));
    else terms.push(intercept < 0 ? `- ${rendered}` : `+ ${rendered}`);
  }
  return terms.join(" ");
}

/** Render `a·v² + b·v + c` with signs folded and zero terms dropped. */
function polyLatex(a: number, b: number, c: number, v: string): string {
  const pieces: { value: number; suffix: string }[] = [
    { value: a, suffix: `${v}^2` },
    { value: b, suffix: v },
    { value: c, suffix: "" },
  ];
  let out = "";
  for (const { value, suffix } of pieces) {
    if (Math.abs(value) < EPS) continue;
    const mag = Math.abs(value);
    const coeff =
      suffix !== "" && Math.abs(mag - 1) < EPS ? "" : numLatex(mag);
    const term = `${coeff}${suffix}` || numLatex(mag);
    out = out === ""
      ? `${value < 0 ? "-" : ""}${term}`
      : `${out} ${value < 0 ? "-" : "+"} ${term}`;
  }
  return out === "" ? "0" : out;
}

/** "x = 5, y = 2 or x = -1/7, y = 2/7" (and its LaTeX twin). */
function pairsAnswer(
  vars: [string, string],
  pairs: Record<string, number>[]
): FinalAnswer {
  return {
    latex: pairs
      .map((s) => vars.map((v) => `${v} = ${numLatex(s[v])}`).join(",\\; "))
      .join("\\;\\text{ or }\\;"),
    plain: pairs
      .map((s) => vars.map((v) => `${v} = ${numPlain(s[v])}`).join(", "))
      .join(" or "),
  };
}
