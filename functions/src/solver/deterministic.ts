/**
 * The deterministic solver — the ONLY thing allowed to produce math.
 *
 * mathsteps drives equation solving + simplification; mathjs handles evaluation
 * and derivatives. Every path returns a `SolveCandidate` whose `verify()` closure
 * proves the answer against the original problem — the orchestrator trusts
 * nothing until that returns true. Returns `null` when no engine can produce a
 * candidate, so the caller can fall back to the LLM-candidate tier.
 */
import * as mathsteps from "mathsteps";
import { derivative, fraction, parse, rationalize, simplify } from "mathjs";

import { atomizeMethods } from "./atomize";
import { solveCalculus } from "./calculus";
import { solveComplex } from "./complex";
import { equationParts } from "./classify";
import {
  exactForm,
  quadraticSurdRoots,
  resymbolize,
  squareFreeSplit,
  type SurdRoot,
} from "./exact";
import { asciiToLatex, variablesIn } from "./latex";
import { solveLinalg, solveVectors } from "./linalg";
import { solveLinearSystem } from "./linsystem";
import { solveSimultaneous } from "./simultaneous";
import { solveStatistics } from "./statistics";
import { solveTaylor } from "./taylor";
import { solveVieta } from "./vieta";
import { solveArcLength } from "./arclength";
import { solveNumericRoot } from "./numroot";
import { solveParamDet } from "./paramdet";
import { solveModular } from "./modular";
import { solveChangeOfSubject } from "./subject";
import { solvePercent } from "./percent";
import { solveIntegral } from "./integral";
import {
  solveAbsoluteEquation,
  solveRadicalEquation,
  type RootsResult,
} from "./radical";
import {
  canonicalPolynomial,
  factorPolynomial,
  simplifyAlgebraic,
  univariateRealRoots,
} from "./polynomial";
import {
  evalReal,
  verifyDerivative,
  verifyEquality,
  verifyRoots,
} from "./verify";
import {
  Classification,
  FinalAnswer,
  RawMethod,
  RawStep,
  SolveCandidate,
} from "./types";

/**
 * Run the engine, then put its steps through the Atomic Step Engine.
 *
 * Refining centrally rather than per-engine matters: `DIFFERENTIATE → RESULT`
 * leaps over an entire product rule in a dozen calculus paths, and none of them
 * would have been reached by wiring one engine at a time. Sub-steps that fail
 * their claims are discarded and the coarse step ships exactly as before, so
 * this can add clarity but never change an answer.
 */
export function solveDeterministic(cls: Classification): SolveCandidate | null {
  const candidate = runEngine(cls);
  if (!candidate) return null;
  return {
    ...candidate,
    methods: atomizeMethods(candidate.methods, {
      unknown: cls.unknown,
      originalAscii: cls.ascii,
      roots: candidate.roots ?? [],
      quadratic: candidate.quadratic ?? null,
      stat:
        cls.statKind && cls.statData
          ? { kind: cls.statKind, data: cls.statData }
          : null,
      matrix:
        cls.linalgOp && cls.matrixData
          ? { op: cls.linalgOp, a: cls.matrixData, b: cls.matrixB ?? null }
          : null,
    }),
  };
}

function runEngine(cls: Classification): SolveCandidate | null {
  switch (cls.strategy) {
    case "equation":
      return solveEquation(cls);
    case "simplify":
      return solveSimplify(cls);
    case "arithmetic":
      return solveArithmetic(cls);
    case "derivative":
      return solveDerivative(cls);
    case "statistics":
      return solveStatistics(cls);
    case "linalg":
      return solveLinalg(cls) ?? solveVectors(cls);
    case "linsystem":
      return solveLinearSystem(cls);
    case "simultaneous":
      return solveSimultaneous(cls);
    case "taylor":
      return solveTaylor(cls);
    case "vieta":
      return solveVieta(cls);
    case "arc_length":
      return solveArcLength(cls);
    case "numeric_root":
      return solveNumericRoot(cls);
    case "param_det":
      return solveParamDet(cls);
    case "modular":
      return solveModular(cls);
    case "subject":
      return solveChangeOfSubject(cls);
    case "percent":
      return cls.percent ? solvePercent(cls.percent) : null;
    case "integral":
      return solveIntegral(cls);
    case "calculus":
      return solveCalculus(cls);
    case "complex":
      return solveComplex(cls);
    default:
      return null; // llm_candidate — handled by the orchestrator
  }
}

// --- Equations (mathsteps) --------------------------------------------------

function solveEquation(cls: Classification): SolveCandidate | null {
  const parts = equationParts(cls.ascii);
  if (parts.length !== 1) return null; // deterministic path is single-equation
  // mathsteps is the primary engine, but it can't rearrange every quadratic
  // (`(x+1)^2 = 4(x+4)` defeats it). Fall back to the formula over the sampled
  // coefficients so such problems still solve deterministically + verified,
  // rather than depending on the LLM to return a COMPLETE root set.
  // …and neither of those can clear a denominator that holds the unknown, so
  // `(2x+7)/(3x-2) = x` and `3 − 5/(x+1) = 1` both dead-ended at "couldn't
  // verify". The third tier multiplies the fractions out, which is what makes
  // those two a quadratic and a linear equation in the first place.
  //
  // A tier is skipped when it DECLINES — and also when what it produced does
  // not survive its own gate. mathsteps doesn't decline on `x − 1 = (6−3x)/2x`;
  // it returns an answer that is simply wrong, and a plain `??` chain would
  // stop there and never reach the tier that can do it. The last unverified
  // candidate is still returned if every tier fails, so the honest
  // "couldn't verify" state is unchanged.
  //
  // The last two tiers are for the shapes no amount of rearranging reaches: a
  // square root or a modulus has to be REMOVED first, and the move that removes
  // it can invent solutions. Those engines hand back roots + steps and are
  // wrapped here, so they share this file's answer formatting and gate.
  let fallback: SolveCandidate | null = null;
  for (const attempt of [
    solveViaMathsteps,
    solveQuadraticDirect,
    solveRationalEquation,
    viaRoots(solveRadicalEquation),
    viaRoots(solveAbsoluteEquation),
  ]) {
    const candidate = attempt(cls, parts);
    if (!candidate) continue;
    if (candidate.verify()) return candidate;
    fallback ??= candidate;
  }
  return fallback;
}

/** Adapt a roots-and-steps engine into the tier shape `solveEquation` iterates. */
function viaRoots(
  engine: (
    cls: Classification,
    parts: { lhs: string; rhs: string }[]
  ) => RootsResult | null
) {
  return (
    cls: Classification,
    parts: { lhs: string; rhs: string }[]
  ): SolveCandidate | null => {
    const found = engine(cls, parts);
    if (!found) return null;
    return {
      answer: exactRootsAnswer(cls.unknown, found.roots, found.surds),
      methods: found.methods,
      roots: found.roots,
      quadratic: found.quadratic ?? undefined,
      plotExpression: found.plotExpression,
      verify: () => verifyRoots(parts, cls.unknown, found.roots),
    };
  };
}

/**
 * An equation with the unknown under a fraction bar.
 *
 * Setting a quotient to zero is setting its NUMERATOR to zero, so put
 * `lhs − rhs` over a common denominator and solve the polynomial on top. That
 * step is not reversible — clearing `x+1` from `3 − 5/(x+1) = 1` invents a
 * solution at `x = −1`, where the printed equation says nothing at all — so
 * every root is checked against the ORIGINAL equation and a root that makes a
 * denominator vanish is dropped, not shipped.
 */
function solveRationalEquation(
  cls: Classification,
  parts: { lhs: string; rhs: string }[]
): SolveCandidate | null {
  const { lhs, rhs } = parts[0];
  let numerator: string;
  try {
    const r = rationalize(`(${lhs}) - (${rhs})`, {}, true) as unknown as {
      numerator: { toString(): string };
      denominator: { toString(): string };
    };
    // Only worth doing when there IS a denominator holding the unknown — ask
    // the common denominator itself rather than pattern-matching the source,
    // where `2x` hides the `x` from a word boundary.
    if (!variablesIn(r.denominator.toString()).includes(cls.unknown)) return null;
    numerator = r.numerator.toString();
  } catch {
    return null;
  }
  const canonical = canonicalPolynomial(numerator);
  if (!canonical) return null;
  if (variablesIn(canonical).join(",") !== cls.unknown) return null;

  const values = polynomialRoots(canonical, cls.unknown);
  if (!values || values.length === 0) return null;

  // The gate: each root must satisfy the equation AS PRINTED. A root the
  // clearing invented is exactly the one that fails here, and gets dropped.
  const kept = distinctSorted(
    values.filter((v) => verifyRoots(parts, cls.unknown, [v]))
  );
  if (kept.length === 0) return null;

  const steps: RawStep[] = [
    { ascii: `${lhs} = ${rhs}`, operationCode: "GIVEN" },
    { ascii: `${canonical} = 0`, operationCode: "MULTIPLY_BOTH_SIDES_BY_DENOMINATOR" },
  ];
  return {
    answer: exactRootsAnswer(cls.unknown, kept),
    methods: [
      { id: "clear_denominators", name: "Clear the fractions", examPick: true, steps },
    ],
    roots: kept,
    plotExpression: singleVarPolyPlot(parts[0], cls.unknown),
    verify: () => verifyRoots(parts, cls.unknown, kept),
  };
}

/** Exact real roots of a canonical univariate polynomial, of any degree that
 * factors into linear and quadratic pieces. */
function polynomialRoots(canonical: string, unknown: string): number[] | null {
  const roots = univariateRealRoots(canonical);
  if (!roots || roots.length === 0) return null;
  if (variablesIn(canonical).join(",") !== unknown) return null;
  return distinctSorted(roots);
}

/**
 * Solve a quadratic straight from its coefficients, recovered by sampling
 * `lhs - rhs` (extractQuadratic). Used only when mathsteps declines. Real roots
 * only; the substitution gate proves them like any other answer.
 */
function solveQuadraticDirect(
  cls: Classification,
  parts: { lhs: string; rhs: string }[]
): SolveCandidate | null {
  const quad = extractQuadratic(parts[0], cls.unknown);
  if (!quad) return null;
  const disc = quad.b * quad.b - 4 * quad.a * quad.c;
  if (disc < 0) return null; // complex roots → decline honestly
  const sq = Math.sqrt(disc);
  const values = distinctSorted([
    (-quad.b + sq) / (2 * quad.a),
    (-quad.b - sq) / (2 * quad.a),
  ]);
  if (!verifyRoots(parts, cls.unknown, values)) return null;

  const method = quadraticFormulaMethod(cls.unknown, quad);
  return {
    // Format each root by its EXACT symbolic form where recognizable (√2, a
    // fraction) — same as the LLM path — so an irrational root shows √2, not
    // 1.414. The gate still verifies the numeric values.
    answer: exactRootsAnswer(cls.unknown, values, quadraticSurdRoots(quad.a, quad.b, quad.c)),
    methods: method ? [{ ...method, examPick: true }] : [],
    roots: values,
    quadratic: quad,
    plotExpression: singleVarPolyPlot(parts[0], cls.unknown),
    verify: () => verifyRoots(parts, cls.unknown, values),
  };
}

/** A §4 answer from verified numeric roots, each in exact symbolic form.
 *
 * When the roots' surd forms are known — BUILT from the equation's integer
 * coefficients, never sniffed from the float — `x²+4x+1=0` answers `−2 ± √3`,
 * not `-3.732051`. Each value is matched to its surd numerically, so a caller
 * that kept only one root of the conjugate pair (a radical equation after
 * sifting) still formats it exactly. */
function exactRootsAnswer(
  unknown: string,
  values: number[],
  surds?: readonly SurdRoot[] | null
): FinalAnswer {
  const fmt = (n: number): { latex: string; plain: string } => {
    if (Number.isInteger(n)) return { latex: String(n), plain: String(n) };
    const surd = surds?.find((s) => Math.abs(s.value - n) < 1e-9);
    if (surd) return { latex: surd.latex, plain: surd.plain };
    const exact = exactForm(n);
    if (exact) return { latex: exact.latex, plain: exact.plain };
    // A worksheet's answer is `7/3`, not `2.333333`. The root came out of the
    // quadratic formula in full double precision, so the snap is tight — and
    // the caller has already put the VALUE through the substitution gate.
    const frac = rationalString(n, Math.max(1e-12, Math.abs(n) * 1e-10));
    if (frac) return { latex: numLatex(frac), plain: frac };
    const s = trimNum(n);
    return { latex: s, plain: s };
  };
  if (values.length === 1) {
    const f = fmt(values[0]);
    return { latex: `${unknown} = ${f.latex}`, plain: `${unknown} = ${f.plain}` };
  }
  return {
    latex: values
      .map((v, i) => `${unknown}_${i + 1} = ${fmt(v).latex}`)
      .join(",\\; "),
    plain: values.map((v) => `${unknown} = ${fmt(v).plain}`).join(" or "),
  };
}

/**
 * The exact small fraction a double is a rounded decimal OF, as `p/q` — or null
 * when it isn't one. Continued fractions, so `2.333333` finds `7/3` and a
 * genuine `0.317` finds nothing.
 */
function rationalString(x: number, tol: number): string | null {
  if (!Number.isFinite(x) || Number.isInteger(x)) return null;
  let [h0, h1, k0, k1] = [0, 1, 1, 0];
  let v = x;
  for (let i = 0; i < 24; i++) {
    const a = Math.floor(v);
    [h0, h1] = [h1, a * h1 + h0];
    [k0, k1] = [k1, a * k1 + k0];
    if (k1 === 0 || Math.abs(k1) > 1000) return null;
    if (Math.abs(h1 / k1 - x) <= tol) {
      return k1 === 1 ? String(h1) : `${h1}/${k1}`;
    }
    const frac = v - a;
    if (frac === 0) return null;
    v = 1 / frac;
  }
  return null;
}

/**
 * mathsteps prints a rational root ROUNDED — `-1.333333` where the worksheet
 * says `-4/3`. Snap each root back to the fraction it is a decimal of, but only
 * when every snapped value still satisfies the original equation: the display
 * and the proof have to be the same number.
 */
function snapRoots(
  parts: { lhs: string; rhs: string }[],
  unknown: string,
  roots: Roots
): Roots {
  const strings: string[] = [];
  const values: number[] = [];
  let changed = false;
  for (let i = 0; i < roots.values.length; i++) {
    const text = rationalString(roots.values[i], 5e-6);
    if (text === null) {
      strings.push(roots.strings[i]);
      values.push(roots.values[i]);
      continue;
    }
    changed = true;
    strings.push(text);
    values.push(evalReal(text));
  }
  if (!changed) return roots;
  return verifyRoots(parts, unknown, values) ? { strings, values } : roots;
}

/** Dedupe near-equal roots, ascending. */
function distinctSorted(values: number[]): number[] {
  const out: number[] = [];
  for (const v of values) {
    if (!out.some((x) => Math.abs(x - v) < 1e-9)) out.push(v);
  }
  return out.sort((a, b) => a - b);
}

/** Both sides re-printed without explicit ParenthesisNodes, or null. */
function stripExplicitParens(part: { lhs: string; rhs: string }): string | null {
  const clean = (side: string): string | null => {
    try {
      type Node = {
        type?: string;
        content?: Node;
        toString(): string;
        transform(cb: (n: Node) => Node): Node;
      };
      let node = parse(side) as unknown as Node;
      for (let changed = true; changed; ) {
        changed = false;
        node = node.transform((n) => {
          if (n.type === "ParenthesisNode" && n.content) {
            changed = true;
            return n.content;
          }
          return n;
        });
      }
      return node.toString();
    } catch {
      return null;
    }
  };
  const l = clean(part.lhs);
  const r = clean(part.rhs);
  return l !== null && r !== null ? `${l} = ${r}` : null;
}

function solveViaMathsteps(
  cls: Classification,
  parts: { lhs: string; rhs: string }[]
): SolveCandidate | null {
  let steps: mathsteps.MsStep[];
  try {
    steps = mathsteps.solveEquation(cls.ascii);
  } catch {
    // `\frac{x}{12} = \frac{3}{4}` arrives as `((x)/(12)) = ((3)/(4))` and
    // mathsteps throws "Unsupported node type: ParenthesisNode" on that
    // wrapping — which lost every plain proportion written with fraction bars.
    // Retry ONCE with the brackets rebuilt by mathjs (drop every explicit
    // ParenthesisNode; toString re-inserts only what precedence needs). Only on
    // throw, so input that already works keeps its exact byte form.
    const rebuilt = stripExplicitParens(parts[0]);
    if (!rebuilt) return null;
    try {
      steps = mathsteps.solveEquation(rebuilt);
    } catch {
      return null;
    }
  }
  if (!steps || steps.length === 0) return null;

  const finalEq = steps[steps.length - 1].newEquation;
  if (!finalEq) return null;
  const rawRoots = parseRoots(finalEq.ascii(), cls.unknown);
  if (!rawRoots) return null;
  const roots = snapRoots(parts, cls.unknown, rawRoots);

  const rawSteps: RawStep[] = steps
    .filter((s) => s.newEquation)
    .map((s) => ({
      ascii: s.newEquation!.ascii(),
      operationCode: s.changeType,
    }));

  const quad = extractQuadratic(parts[0], cls.unknown);
  const factored = steps.some((s) => /FACTOR/.test(s.changeType));
  const methods = buildEquationMethods(cls, rawSteps, quad, factored);

  return {
    answer: rootsAnswer(cls.unknown, roots),
    methods,
    roots: roots.values,
    quadratic: quad ?? undefined,
    plotExpression: singleVarPolyPlot(parts[0], cls.unknown),
    // The ONLY path with real equation MsStep[] — carried up for the flag-gated,
    // non-load-bearing animation sidecar (built in the orchestrator). Additive:
    // the verify/answer path never reads it.
    steps,
    verify: () => verifyRoots(parts, cls.unknown, roots.values),
  };
}

interface Roots {
  strings: string[];
  values: number[];
}

/** Parse a solved equation like `x = 5` or `x = [2 / 5, -1]` for `unknown`. */
function parseRoots(finalAscii: string, unknown: string): Roots | null {
  const idx = finalAscii.indexOf("=");
  if (idx === -1) return null;
  const left = finalAscii.slice(0, idx).trim();
  if (left !== unknown) return null; // e.g. `x^2 = -1` is NOT solved for x
  let right = finalAscii.slice(idx + 1).trim();

  let rootStrings: string[];
  if (right.startsWith("[") && right.endsWith("]")) {
    rootStrings = right
      .slice(1, -1)
      .split(",")
      .map((r) => r.trim())
      .filter(Boolean);
  } else {
    rootStrings = [right];
  }
  if (rootStrings.length === 0) return null;

  const pairs: { value: number; str: string }[] = [];
  for (const rs of rootStrings) {
    const v = evalReal(rs);
    if (Number.isNaN(v)) return null; // a non-numeric root ⇒ not really solved
    if (pairs.some((p) => Math.abs(p.value - v) < 1e-9)) continue; // dedup
    pairs.push({ value: v, str: rs.replace(/\s+/g, "") });
  }
  if (pairs.length === 0) return null;
  pairs.sort((a, b) => a.value - b.value); // ascending, like the §4 example
  return {
    strings: pairs.map((p) => p.str),
    values: pairs.map((p) => p.value),
  };
}

function buildEquationMethods(
  cls: Classification,
  rawSteps: RawStep[],
  quad: { a: number; b: number; c: number } | null,
  factored: boolean
): RawMethod[] {
  const primaryId = cls.problemType === "quadratic_equation"
    ? factored
      ? "factoring"
      : "solving"
    : "isolation";
  const primaryName = cls.problemType === "quadratic_equation"
    ? factored
      ? "Factoring"
      : "Solving"
    : "Isolate the variable";

  const methods: RawMethod[] = [
    {
      id: primaryId,
      name: primaryName,
      examPick: true,
      steps: rawSteps.map((s) => ({
        ascii: s.ascii,
        operationCode: s.operationCode,
      })),
    },
  ];

  // A deterministic quadratic-formula method — real math from real a,b,c.
  if (quad && cls.problemType === "quadratic_equation") {
    const qm = quadraticFormulaMethod(cls.unknown, quad);
    if (qm) methods.push(qm);
  }
  return methods;
}

/** Build the quadratic-formula method's steps deterministically from a,b,c. */
function quadraticFormulaMethod(
  unknown: string,
  q: { a: number; b: number; c: number }
): RawMethod | null {
  const disc = q.b * q.b - 4 * q.a * q.c;
  if (disc < 0) return null; // real-roots only
  const sqrtDisc = Math.sqrt(disc);
  const r1 = (-q.b + sqrtDisc) / (2 * q.a);
  const r2 = (-q.b - sqrtDisc) / (2 * q.a);
  const x = unknown;
  const { a, b, c } = q;
  const poly = `${fmt(a)}${x}^2 ${sign(b)} ${fmt(Math.abs(b))}${x} ${sign(c)} ${fmt(Math.abs(c))} = 0`;
  // The answer line shows the surd; the method's payoff step must agree with it,
  // not round it away.
  const surds = quadraticSurdRoots(a, b, c);
  const show = (v: number) =>
    surds?.find((s) => Math.abs(s.value - v) < 1e-9)?.latex ?? trimNum(v);
  const rootsLatex =
    Math.abs(r1 - r2) < 1e-9
      ? `${x} = ${show(r1)}`
      : `${x}_1 = ${show(r1)},\\; ${x}_2 = ${show(r2)}`;
  return {
    id: "quadratic_formula",
    name: "Quadratic formula",
    examPick: false,
    steps: [
      {
        ascii: poly,
        latex: poly,
        operationCode: "IDENTIFY_COEFFICIENTS",
      },
      {
        ascii: `${x} = (-(${fmt(b)}) ± sqrt((${fmt(b)})^2 - 4*${fmt(a)}*${fmt(c)})) / (2*${fmt(a)})`,
        latex: `${x} = \\dfrac{-(${fmt(b)}) \\pm \\sqrt{(${fmt(b)})^2 - 4(${fmt(a)})(${fmt(c)})}}{2(${fmt(a)})}`,
        operationCode: "APPLY_QUADRATIC_FORMULA",
      },
      {
        ascii: `${x} = (${fmt(-b)} ± sqrt(${fmt(disc)})) / ${fmt(2 * a)}`,
        latex: `${x} = \\dfrac{${fmt(-b)} \\pm \\sqrt{${fmt(disc)}}}{${fmt(2 * a)}}`,
        operationCode: "SIMPLIFY_DISCRIMINANT",
      },
      ...surdSteps(x, -b, disc, 2 * a),
      {
        ascii: `${x} = [${trimNum(r1)}, ${trimNum(r2)}]`,
        latex: rootsLatex,
        operationCode: "FIND_ROOTS",
      },
    ],
  };
}

/**
 * The two moves hidden between `x = (−4 ± √12)/2` and `x = −2 ± √3`: pull the
 * square factor out of the radical, then cancel what the whole fraction shares.
 * Each is emitted only when it actually changes something, so a discriminant
 * that is already square-free (or a fraction with nothing to cancel) adds no
 * step — and rational roots (perfect-square disc) add none at all, since the
 * plain arithmetic path already shows those.
 */
function surdSteps(x: string, p: number, disc: number, den: number): RawStep[] {
  const split = squareFreeSplit(disc);
  if (!split || split.m === 1) return [];
  const steps: RawStep[] = [];
  const over = (numAscii: string, numLatex: string, d: number): RawStep["latex"][] =>
    d === 1 ? [numAscii, numLatex] : [`(${numAscii}) / ${d}`, `\\dfrac{${numLatex}}{${d}}`];
  // `x² − 2 = 0` reaches here with p = 0, and `x = 0 ± √2` is not how anyone
  // writes it.
  const term = (q: number, k: number, m: number) => ({
    ascii: `${q === 0 ? "" : `${q} `}± ${k === 1 ? "" : `${k}*`}sqrt(${m})`,
    latex: `${q === 0 ? "" : `${q} `}\\pm ${k === 1 ? "" : k}\\sqrt{${m}}`,
  });
  if (split.k > 1) {
    const t = term(p, split.k, split.m);
    const [ascii, latex] = over(t.ascii, t.latex, den);
    steps.push({ ascii: `${x} = ${ascii}`, latex: `${x} = ${latex}`, operationCode: "SIMPLIFY_RADICAL" });
  }
  const g = [Math.abs(p), split.k, Math.abs(den)].reduce((u, v) => {
    while (v) [u, v] = [v, u % v];
    return u;
  });
  if (g > 1) {
    const t = term(p / g, split.k / g, split.m);
    const [ascii, latex] = over(t.ascii, t.latex, den / g);
    steps.push({ ascii: `${x} = ${ascii}`, latex: `${x} = ${latex}`, operationCode: "CANCEL_COMMON_FACTOR" });
  }
  return steps;
}

// --- Simplify (mathsteps / mathjs) ------------------------------------------

function solveSimplify(cls: Classification): SolveCandidate | null {
  let simplified: string | null = null;
  const rawSteps: RawStep[] = [];

  try {
    const steps = mathsteps.simplifyExpression(cls.ascii);
    for (const s of steps) {
      if (s.newNode) {
        rawSteps.push({
          ascii: s.newNode.toString(),
          operationCode: s.changeType,
        });
      }
    }
    if (rawSteps.length) simplified = rawSteps[rawSteps.length - 1].ascii;
  } catch {
    /* fall through to mathjs */
  }
  if (!simplified) {
    try {
      simplified = simplify(cls.ascii).toString();
    } catch {
      return null;
    }
  }
  if (!simplified) return null;

  // mathsteps/mathjs expand a product but never re-order a commutative one, so
  // `2x^2(4xy-5) - 8yx^3 + 9x` came back with its two cubic terms unmet and an
  // algebraic fraction came back as the sum it started as. Canonicalize: same
  // value, collected and reduced — and still proved by the gate below.
  //
  // Canonicalize BOTH the original and mathsteps' output: mathsteps sometimes
  // hands back a worse form than it was given (`15x/(4x-8) ÷ 3x/(x-2)^2` came
  // back as three fractions over a common denominator), and the original ascii
  // is the faithful source. Both candidates are equal in value, so take the
  // shorter — and never lengthen what mathsteps already had.
  const fromMathsteps = simplified;
  const canonical = [simplifyAlgebraic(cls.ascii), simplifyAlgebraic(fromMathsteps)]
    .filter((s): s is string => s !== null && s.length <= fromMathsteps.length)
    .sort((a, b) => a.length - b.length)[0];
  if (canonical && canonical !== simplified) {
    rawSteps.push({ ascii: canonical, operationCode: "COLLECT_LIKE_TERMS" });
    simplified = canonical;
  }

  const vars = variablesIn(cls.ascii);
  const finalAscii = simplified;
  // Exact symbolic form for DISPLAY (mathsteps/mathjs decimalize irrational
  // constants on simplify); `finalAscii` stays raw for the verify gate.
  const display = resymbolize(finalAscii);
  const steps: RawStep[] = rawSteps.length
    ? rawSteps.map((s) => ({ ascii: resymbolize(s.ascii), operationCode: s.operationCode }))
    : [{ ascii: display, operationCode: "SIMPLIFY" }];

  // The product form, when there is one. A worksheet's factorisation chapter
  // wants `(p − 2)(p + 8)`, not the sum it started as — and even when it wasn't
  // asked for, the factored form is worth offering as a second method.
  const factored = factorPolynomial(finalAscii);
  const wantFactored = Boolean(factored && cls.wantsFactor);
  const methods: SolveCandidate["methods"] = [
    { id: "simplify", name: "Simplify", examPick: !wantFactored, steps },
  ];
  if (factored) {
    methods.push({
      id: "factorise",
      name: "Factorise",
      examPick: wantFactored,
      steps: [
        { ascii: display, operationCode: "SIMPLIFY" },
        { ascii: factored, operationCode: "FACTORISE" },
      ],
    });
  }
  const answerAscii = wantFactored && factored ? factored : display;

  return {
    answer: {
      latex: asciiToLatex(answerAscii),
      plain: answerAscii.replace(/\s+/g, " ").trim(),
    },
    methods,
    plotExpression: vars.length === 1 ? cls.ascii : null,
    // Both printed forms go through the gate — a factorisation this file got
    // wrong must cost the answer, never be shown as one.
    verify: () =>
      verifyEquality(cls.ascii, finalAscii, vars) &&
      (!factored || verifyEquality(cls.ascii, factored, vars)),
  };
}

// --- Arithmetic (mathjs.evaluate) -------------------------------------------

function solveArithmetic(cls: Classification): SolveCandidate | null {
  const value = evalReal(cls.ascii);
  if (Number.isNaN(value)) return null;
  const nice = decimalAnswer(cls.ascii, value) ?? niceNumber(value);

  return {
    answer: nice,
    methods: [
      {
        id: "evaluate",
        name: "Evaluate",
        examPick: true,
        steps: [
          { ascii: cls.ascii, operationCode: "START" },
          { ascii: nice.plain, operationCode: "COMPUTE" },
        ],
      },
    ],
    plotExpression: null,
    verify: () => {
      const check = evalReal(cls.ascii);
      return !Number.isNaN(check) && Math.abs(check - value) <= 1e-6;
    },
  };
}

// --- Derivative (mathjs.derivative) -----------------------------------------

function solveDerivative(cls: Classification): SolveCandidate | null {
  const target = cls.derivativeTarget;
  if (!target) return null;
  const order = cls.derivativeOrder ?? 1;
  let d: string;
  // `penult` is the (order-1)th derivative; the answer is d/dx(penult). Verifying
  // the answer against penult reuses the first-order gate and still proves the
  // nth derivative, since d^n/dx^n(f) = d/dx( d^(n-1)/dx^(n-1)(f) ).
  let penult = target;
  try {
    for (let k = 0; k < order - 1; k++) {
      penult = derivative(penult, cls.unknown).toString();
    }
    d = derivative(penult, cls.unknown).toString();
  } catch {
    return null;
  }
  // mathjs evaluates irrational constants (`sqrt(2)` → 1.4142…) when it
  // differentiates. Restore exact symbolic form for DISPLAY; verification still
  // uses the raw `d` (numeric substitution), so the gate is unchanged.
  const display = resymbolize(d);
  const opLatex = order > 1 ? `d^${order}/d${cls.unknown}^${order}` : `d/d${cls.unknown}`;
  return {
    answer: { latex: asciiToLatex(display), plain: display },
    methods: [
      {
        id: "differentiate",
        name: "Differentiate",
        examPick: true,
        steps: [
          {
            ascii: `${opLatex}(${target})`,
            operationCode: "DIFFERENTIATE",
          },
          { ascii: display, operationCode: "RESULT" },
        ],
      },
    ],
    plotExpression: variablesIn(target).length === 1 ? target : null,
    verify: () => verifyDerivative(penult, d, cls.unknown),
  };
}

// --- Shared helpers ---------------------------------------------------------

/** Build the answer for a solved equation from its exact root strings. */
function rootsAnswer(unknown: string, roots: Roots): FinalAnswer {
  if (roots.strings.length === 1) {
    return {
      latex: `${unknown} = ${numLatex(roots.strings[0])}`,
      plain: `${unknown} = ${roots.strings[0]}`,
    };
  }
  const latex = roots.strings
    .map((r, i) => `${unknown}_${i + 1} = ${numLatex(r)}`)
    .join(",\\; ");
  const plain = roots.strings.map((r) => `${unknown} = ${r}`).join(" or ");
  return { latex, plain };
}

/** `2/5` → `\tfrac{2}{5}` (sign hoisted); anything else passes through. */
function numLatex(s: string): string {
  const m = s.match(/^(-?\d+)\/(-?\d+)$/);
  if (m) {
    const n = Number(m[1]);
    const d = Number(m[2]);
    const neg = n * d < 0;
    return `${neg ? "-" : ""}\\tfrac{${Math.abs(n)}}{${Math.abs(d)}}`;
  }
  return asciiToLatex(s);
}

/** Present a numeric value as an integer, small fraction, or decimal. */
/**
 * A problem written in decimals should be answered in decimals: `0.25 + 0.5` is
 * `0.75`, not `3/4`. Both are exact, so the golden rule is satisfied either way —
 * this is about answering in the notation the student used.
 *
 * Returns null (so `niceNumber` prints the fraction) whenever the decimal form
 * would NOT be exact — `0.1 / 0.3` recurs, and `1/3` is the only honest way to
 * write it. Termination is decided from the exact denominator, never from the
 * float: `0.1 + 0.2` is `0.30000000000000004` in binary, so the digits are built
 * by integer arithmetic on n/d rather than read off `toString()`.
 */
function decimalAnswer(source: string, val: number): FinalAnswer | null {
  if (!/\d\.\d/.test(source)) return null; // not written in decimals
  if (Number.isInteger(val)) return null; // niceNumber already prints these well
  let fr: { n: bigint; d: bigint; s: number };
  try {
    fr = fraction(val) as unknown as { n: bigint; d: bigint; s: number };
  } catch {
    return null;
  }
  const n = Number(fr.n);
  const den = Number(fr.d);
  if (!Number.isSafeInteger(n) || !Number.isSafeInteger(den)) return null;
  let rest = den;
  let twos = 0;
  let fives = 0;
  while (rest % 2 === 0) {
    rest /= 2;
    twos++;
  }
  while (rest % 5 === 0) {
    rest /= 5;
    fives++;
  }
  if (rest !== 1) return null; // recurring decimal — the fraction is the exact form
  const places = Math.max(twos, fives);
  if (places === 0 || places > 12) return null;
  const scaled = Math.round((n * 10 ** places) / den);
  if (!Number.isSafeInteger(scaled)) return null;
  const digits = String(scaled).padStart(places + 1, "0");
  const text = `${fr.s < 0 ? "-" : ""}${digits.slice(0, -places)}.${digits.slice(-places)}`;
  return { latex: text, plain: text };
}

function niceNumber(val: number): FinalAnswer {
  if (Number.isInteger(val)) {
    return { latex: String(val), plain: String(val) };
  }
  try {
    // mathjs 15 Fraction: n/d are bigint, s is the sign (±1).
    const fr = fraction(val) as unknown as { n: bigint; d: bigint; s: number };
    const n = Number(fr.n);
    const d = Number(fr.d);
    if (d !== 1 && d <= 10000) {
      const sign = fr.s < 0 ? "-" : "";
      return {
        latex: `${sign}\\tfrac{${n}}{${d}}`,
        plain: `${sign}${n}/${d}`,
      };
    }
  } catch {
    /* fall through */
  }
  const s = trimNum(val);
  return { latex: s, plain: s };
}

/** The `lhs - rhs` expression for plotting a single-variable polynomial. */
function singleVarPolyPlot(
  part: { lhs: string; rhs: string },
  unknown: string
): string | null {
  const vars = variablesIn(`${part.lhs} ${part.rhs}`);
  if (vars.length !== 1 || vars[0] !== unknown) return null;
  const rhs = part.rhs.trim() === "0" ? "" : ` - (${part.rhs})`;
  return `(${part.lhs})${rhs}`; // ascii — graph.ts evaluates it, then latex-izes
}

/**
 * Recover `a,b,c` of a quadratic `a x^2 + b x + c` by sampling p = lhs - rhs at
 * x ∈ {0, 1, -1}. Returns null unless the sampled points really are quadratic.
 */
function extractQuadratic(
  part: { lhs: string; rhs: string },
  unknown: string
): { a: number; b: number; c: number } | null {
  const vars = variablesIn(`${part.lhs} ${part.rhs}`);
  if (vars.length !== 1 || vars[0] !== unknown) return null;
  const p = (x: number) => {
    const l = evalReal(part.lhs, { [unknown]: x });
    const r = evalReal(part.rhs, { [unknown]: x });
    return l - r;
  };
  const p0 = p(0);
  const p1 = p(1);
  const pm1 = p(-1);
  const p2 = p(2);
  if ([p0, p1, pm1, p2].some((v) => Number.isNaN(v))) return null;
  const c = p0;
  const a = (p1 + pm1) / 2 - c;
  const b = (p1 - pm1) / 2;
  if (Math.abs(a) < 1e-9) return null; // not actually quadratic
  // Confirm the fit predicts p(2) — rejects non-polynomial shapes.
  const predicted = a * 4 + b * 2 + c;
  if (Math.abs(predicted - p2) > 1e-6) return null;
  return { a, b, c };
}

// --- number formatting ------------------------------------------------------

/** Trim floating fuzz: `0.4000000001` → `0.4`, `5` → `5`. */
function trimNum(n: number): string {
  if (Number.isInteger(n)) return String(n);
  return String(Number(n.toFixed(6)));
}

function fmt(n: number): string {
  return trimNum(n);
}

function sign(n: number): string {
  return n < 0 ? "-" : "+";
}
