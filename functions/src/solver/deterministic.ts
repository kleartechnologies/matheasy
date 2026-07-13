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
import { derivative, fraction, simplify } from "mathjs";

import { equationParts } from "./classify";
import { resymbolize } from "./exact";
import { asciiToLatex, variablesIn } from "./latex";
import { solveLinalg } from "./linalg";
import { solveStatistics } from "./statistics";
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

export function solveDeterministic(cls: Classification): SolveCandidate | null {
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
      return solveLinalg(cls);
    default:
      return null; // llm_candidate — handled by the orchestrator
  }
}

// --- Equations (mathsteps) --------------------------------------------------

function solveEquation(cls: Classification): SolveCandidate | null {
  const parts = equationParts(cls.ascii);
  if (parts.length !== 1) return null; // deterministic path is single-equation

  let steps: mathsteps.MsStep[];
  try {
    steps = mathsteps.solveEquation(cls.ascii);
  } catch {
    return null;
  }
  if (!steps || steps.length === 0) return null;

  const finalEq = steps[steps.length - 1].newEquation;
  if (!finalEq) return null;
  const roots = parseRoots(finalEq.ascii(), cls.unknown);
  if (!roots) return null;

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
  const rootsLatex =
    Math.abs(r1 - r2) < 1e-9
      ? `${x} = ${trimNum(r1)}`
      : `${x}_1 = ${trimNum(r1)},\\; ${x}_2 = ${trimNum(r2)}`;
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
      {
        ascii: `${x} = [${trimNum(r1)}, ${trimNum(r2)}]`,
        latex: rootsLatex,
        operationCode: "FIND_ROOTS",
      },
    ],
  };
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

  const vars = variablesIn(cls.ascii);
  const finalAscii = simplified;
  // Exact symbolic form for DISPLAY (mathsteps/mathjs decimalize irrational
  // constants on simplify); `finalAscii` stays raw for the verify gate.
  const display = resymbolize(finalAscii);
  const steps: RawStep[] = rawSteps.length
    ? rawSteps.map((s) => ({ ascii: resymbolize(s.ascii), operationCode: s.operationCode }))
    : [{ ascii: display, operationCode: "SIMPLIFY" }];

  return {
    answer: {
      latex: asciiToLatex(display),
      plain: display.replace(/\s+/g, " ").trim(),
    },
    methods: [
      { id: "simplify", name: "Simplify", examPick: true, steps },
    ],
    plotExpression: vars.length === 1 ? cls.ascii : null,
    verify: () => verifyEquality(cls.ascii, finalAscii, vars),
  };
}

// --- Arithmetic (mathjs.evaluate) -------------------------------------------

function solveArithmetic(cls: Classification): SolveCandidate | null {
  const value = evalReal(cls.ascii);
  if (Number.isNaN(value)) return null;
  const nice = niceNumber(value);

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
  let d: string;
  try {
    d = derivative(target, cls.unknown).toString();
  } catch {
    return null;
  }
  // mathjs evaluates irrational constants (`sqrt(2)` → 1.4142…) when it
  // differentiates. Restore exact symbolic form for DISPLAY; verification still
  // uses the raw `d` (numeric substitution), so the gate is unchanged.
  const display = resymbolize(d);
  return {
    answer: { latex: asciiToLatex(display), plain: display },
    methods: [
      {
        id: "differentiate",
        name: "Differentiate",
        examPick: true,
        steps: [
          {
            ascii: `d/d${cls.unknown}(${target})`,
            operationCode: "DIFFERENTIATE",
          },
          { ascii: display, operationCode: "RESULT" },
        ],
      },
    ],
    plotExpression: variablesIn(target).length === 1 ? target : null,
    verify: () => verifyDerivative(target, d, cls.unknown),
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
