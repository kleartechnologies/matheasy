/**
 * Radical and absolute-value equations — the two shapes whose entire lesson is
 * that the move which removes the symbol is NOT reversible.
 *
 * Squaring `x − 1 = √(x+1)` gives a quadratic with roots 0 and 3, but only 3
 * solves the equation that was written: at x = 0 the left side is −1 and a
 * square root is never negative. Splitting `|2x − 3| = 7` into two cases has the
 * same hazard whenever the right side holds the unknown. So both engines here
 * produce CANDIDATES and then check every one of them against the ORIGINAL
 * equation — the rejection is a visible step, because that check is the thing a
 * student has to learn to do.
 *
 * Neither engine formats the answer: they hand back roots and steps, and
 * `deterministic.ts` wraps them with the same `exactRootsAnswer` + `verifyRoots`
 * gate every other equation path goes through.
 */
import { parse, simplify } from "mathjs";

import { quadraticSurdRoots, type SurdRoot } from "./exact";
import { asciiToLatex, variablesIn } from "./latex";
import {
  canonicalPolynomial,
  factorPolynomial,
  univariateRealRoots,
} from "./polynomial";
import { evalReal, verifySolution, type EquationPart } from "./verify";
import type { Classification, RawMethod, RawStep } from "./types";

/** What both engines return; `deterministic.ts` turns it into a SolveCandidate. */
export interface RootsResult {
  roots: number[];
  methods: RawMethod[];
  plotExpression: string | null;
  /**
   * The integer quadratic the candidates came from, when there is one — so the
   * answer formatter can build a surd (`(1 + √5)/2`) instead of printing the
   * float, even when sifting kept only one root of the conjugate pair.
   */
  quadratic?: { a: number; b: number; c: number } | null;
  /** Exact surd forms for whichever roots have one, from ALL cases' quadratics —
   * an absolute value can split into two different quadratics. */
  surds?: SurdRoot[];
}

/** The integer quadratic `canonical` is, read off by sampling — or null. */
function quadraticOf(
  canonical: string,
  unknown: string
): { a: number; b: number; c: number } | null {
  const p = (x: number) => evalReal(canonical, { [unknown]: x });
  const c = p(0);
  const a = (p(1) + p(-1)) / 2 - c;
  const b = (p(1) - p(-1)) / 2;
  if (![a, b, c].every((v) => Number.isInteger(v)) || a === 0) return null;
  if (Math.abs(a * 4 + b * 2 + c - p(2)) > 1e-9) return null; // degree > 2
  return { a, b, c };
}

/** Stand-in symbol for the radical (or the absolute value) while it is isolated. */
const BOX = "R_";

/** Sample points for the residual checks — deliberately non-integer, so a step
 * that happens to agree at whole numbers cannot pass by luck. */
const SAMPLES = [0.37, 1.21, 2.73, 4.11, 5.53, 7.19, 9.87];

type LooseNode = {
  type?: string;
  fn?: { name?: string };
  name?: string;
  args?: LooseNode[];
  toString(): string;
  traverse: (cb: (n: LooseNode) => void) => void;
  transform: (cb: (n: LooseNode) => unknown) => LooseNode;
};

/**
 * `lhs − rhs` rewritten with the single `fn(…)` call replaced by a box, plus the
 * thing that was inside it. Declines on zero or two calls: two radicals need a
 * second squaring, which is a different lesson and is not built here.
 */
function boxOne(
  lhs: string,
  rhs: string,
  fn: string
): { boxed: string; inner: string } | null {
  let tree: LooseNode;
  try {
    tree = parse(`(${lhs}) - (${rhs})`) as unknown as LooseNode;
  } catch {
    return null;
  }
  let target: LooseNode | null = null;
  let count = 0;
  tree.traverse((n) => {
    if (n.type === "FunctionNode" && n.fn?.name === fn) {
      count++;
      target = n;
    }
  });
  if (count !== 1 || target === null) return null;
  const hit: LooseNode = target;
  const inner = hit.args?.[0]?.toString();
  if (!inner) return null;
  // A nested call would survive the swap and break every step below it.
  if (new RegExp(`\\b${fn}\\s*\\(`).test(inner)) return null;
  const boxed = tree.transform((n) => (n === hit ? parse(BOX) : n)).toString();
  return { boxed, inner };
}

/**
 * Isolate the box: `lhs − rhs` must be `k·BOX + c(x)`, which makes the equation
 * `BOX = −c/k`. Linearity is measured, not assumed — `√x · x` is linear in the
 * box too, but its coefficient is not constant, and shipping `√x = …` for it
 * would be a lie.
 */
function isolate(boxed: string, unknown: string): string | null {
  let k: number | null = null;
  let checked = 0;
  for (const x of SAMPLES) {
    const at = (r: number) => evalReal(boxed, { [unknown]: x, [BOX]: r });
    const d0 = at(0);
    const d1 = at(1);
    const d2 = at(2);
    if ([d0, d1, d2].some((v) => Number.isNaN(v))) continue;
    if (Math.abs(d2 - 2 * d1 + d0) > 1e-7) return null; // not linear in the box
    const slope = d1 - d0;
    if (k === null) k = slope;
    else if (Math.abs(slope - k) > 1e-7) return null; // coefficient depends on x
    checked++;
  }
  if (k === null || checked < 3 || Math.abs(k) < 1e-9) return null;
  let constant: string;
  try {
    const zeroed = (parse(boxed) as unknown as LooseNode).transform((n) =>
      n.type === "SymbolNode" && n.name === BOX ? parse("0") : n
    );
    constant = simplify(zeroed.toString()).toString();
  } catch {
    return null;
  }
  try {
    const w = simplify(`-(${constant}) / (${k})`).toString();
    return variablesIn(w).every((v) => v === unknown) ? w : null;
  } catch {
    return null;
  }
}

/**
 * True when two equations have the same solution set, tested the way the atomic
 * step engine tests it: their residuals must stay in constant proportion across
 * the samples. Sharing roots is not enough — `(x−2)(x−3)(x−9) = 0` vanishes
 * wherever `(x−2)(x−3) = 0` does.
 */
function samePrinted(a: EquationPart, b: EquationPart, unknown: string): boolean {
  let k: number | null = null;
  let checked = 0;
  for (const x of SAMPLES) {
    const ra =
      evalReal(a.lhs, { [unknown]: x }) - evalReal(a.rhs, { [unknown]: x });
    const rb =
      evalReal(b.lhs, { [unknown]: x }) - evalReal(b.rhs, { [unknown]: x });
    if (Number.isNaN(ra) || Number.isNaN(rb)) continue;
    if (Math.abs(ra) < 1e-9) {
      if (Math.abs(rb) > 1e-6) return false;
      continue;
    }
    const ratio = rb / ra;
    if (k === null) k = ratio;
    else if (Math.abs(ratio - k) > 1e-6) return false;
    checked++;
  }
  return k !== null && Math.abs(k) > 1e-9 && checked >= 3;
}

function eq(text: string): EquationPart {
  const i = text.indexOf("=");
  return { lhs: text.slice(0, i), rhs: text.slice(i + 1) };
}

function step(operationCode: string, ascii: string, latex?: string): RawStep {
  return { ascii, operationCode, latex: latex ?? asciiToLatex(ascii) };
}

/** The candidate substituted into the original equation, printed as the student
 * would write it — the numbers put in, before either side is worked out. A root
 * with a known surd form is substituted AS the surd (`√((1+√5)/2 + 1) = …`); the
 * evaluated `⇒` comparison stays numeric, rounded, which is exactly the check a
 * student would do on a calculator. */
function checkStep(
  parts: EquationPart[],
  unknown: string,
  value: number,
  kept: boolean,
  surd?: SurdRoot
): RawStep {
  // A surd or a negative substitutes in parentheses; a plain positive number
  // substitutes bare — `sqrt(3 + 1)`, not `sqrt((3) + 1)`.
  const r0 = round(value);
  const shownValue = surd ? `(${surd.ascii})` : r0 < 0 ? `(${r0})` : String(r0);
  const put = (side: string) => {
    try {
      return (parse(side) as unknown as LooseNode)
        .transform((n) =>
          n.type === "SymbolNode" && n.name === unknown
            ? parse(shownValue)
            : n
        )
        .toString();
    } catch {
      return side;
    }
  };
  const { lhs, rhs } = parts[0];
  const ascii = `${put(lhs)} = ${put(rhs)}`;
  const l = evalReal(lhs, { [unknown]: value });
  const r = evalReal(rhs, { [unknown]: value });
  const shown = `${asciiToLatex(String(round(l)))} ${kept ? "=" : "\\ne"} ${asciiToLatex(String(round(r)))}`;
  const name = surd ? surd.latex : String(round(value));
  const verdict = kept
    ? `\\quad\\text{true, so } ${unknown} = ${name} \\text{ is a solution}`
    : `\\quad\\text{false, so } ${unknown} = ${name} \\text{ is extraneous}`;
  return {
    ascii,
    operationCode: kept ? "CHECK_KEEPS_ROOT" : "CHECK_REJECTS_ROOT",
    latex: `${asciiToLatex(ascii)} \\;\\Rightarrow\\; ${shown}${verdict}`,
  };
}

function round(v: number): number {
  return Math.round(v * 1e6) / 1e6;
}

/**
 * The roots step. `ascii` keeps the `x = [a, b]` array shape every other engine
 * uses; `latex` is built here rather than left to the atomic step engine's
 * repair, which only fires when the previous step is a product set to zero —
 * here it is a substitution check, so the array syntax would reach the student.
 */
function rootsStep(
  operationCode: string,
  unknown: string,
  values: number[],
  surds?: SurdRoot[]
): RawStep {
  return {
    ascii: `${unknown} = [${values.map((v) => round(v)).join(", ")}]`,
    operationCode,
    latex: values
      .map((v) => `${unknown} = ${surdShow(surds, v)}`)
      .join("\\quad\\text{or}\\quad "),
  };
}

/** The exact surd latex for `v` when one is known, else the rounded decimal. */
function surdShow(surds: SurdRoot[] | undefined, v: number): string {
  return (
    surds?.find((s) => Math.abs(s.value - v) < 1e-9)?.latex ?? String(round(v))
  );
}

/**
 * The same equation with a positive leading coefficient. `x + 1 = (x−1)²`
 * collects to `−x² + 3x = 0`, and no worksheet writes it that way — multiplying
 * through by −1 changes nothing about the solutions and everything about
 * whether the next line is readable.
 */
function leadingPositive(canonical: string): string {
  if (!canonical.trimStart().startsWith("-")) return canonical;
  return canonicalPolynomial(`-(${canonical})`) ?? canonical;
}

/**
 * `x(x − 3) = 0` → `x = 0 or x − 3 = 0`. Returns null when the factorisation
 * isn't a plain product of factors in the unknown, so the step is simply not
 * shown rather than shown wrongly.
 */
function zeroProduct(factored: string, unknown: string): string | null {
  let tree: LooseNode;
  try {
    tree = parse(factored) as unknown as LooseNode;
  } catch {
    return null;
  }
  const factors: string[] = [];
  const walk = (n: LooseNode): void => {
    const op = (n as { op?: string }).op;
    if (n.type === "OperatorNode" && op === "*" && n.args?.length === 2) {
      walk(n.args[0]);
      walk(n.args[1]);
      return;
    }
    // A ParenthesisNode holds its child on `content`, not `args` — reading `args`
    // silently fell through and printed the brackets: `(x - 1) = 0`.
    const inner = (n as { content?: LooseNode }).content;
    if (n.type === "ParenthesisNode" && inner) return walk(inner);
    // `-(x-1)(x-6)`: the sign is a constant factor, and a constant is never zero.
    if (
      n.type === "OperatorNode" &&
      op === "-" &&
      n.args?.length === 1 &&
      n.args[0]
    ) {
      return walk(n.args[0]);
    }
    const text = n.toString();
    if (variablesIn(text).includes(unknown)) factors.push(text);
  };
  walk(tree);
  const distinct = factors.filter((f, i) => factors.indexOf(f) === i);
  if (distinct.length < 2) return null;
  return distinct.map((f) => `${f} = 0`).join(" or ");
}

/**
 * Candidate roots of the polynomial that replaced the original equation, plus
 * the steps that got there. Shared by both engines: once the symbol is gone,
 * what is left is an ordinary polynomial.
 */
function polynomialTail(
  canonicalSource: string,
  unknown: string
): {
  canonical: string;
  candidates: number[];
  steps: RawStep[];
  quad: { a: number; b: number; c: number } | null;
  surds: SurdRoot[];
} | null {
  const raw = canonicalPolynomial(canonicalSource);
  if (!raw) return null;
  const canonical = leadingPositive(raw);
  if (variablesIn(canonical).join(",") !== unknown) return null;
  const candidates = univariateRealRoots(canonical);
  if (!candidates || candidates.length === 0) return null;

  const steps: RawStep[] = [step("COLLECT_TERMS", `${canonical} = 0`)];
  const factored = factorPolynomial(canonical);
  if (factored && factored !== canonical) {
    steps.push(step("FACTORISE", `${factored} = 0`));
    const cases = zeroProduct(factored, unknown);
    if (cases) {
      steps.push({
        ascii: cases,
        operationCode: "ZERO_PRODUCT",
        latex: cases
          .split(" or ")
          .map((c) => asciiToLatex(c))
          .join("\\quad\\text{or}\\quad "),
      });
    }
  }
  const distinct: number[] = [];
  for (const v of candidates) {
    if (!distinct.some((u) => Math.abs(u - v) < 1e-9)) distinct.push(v);
  }
  distinct.sort((a, b) => a - b);
  const quad = quadraticOf(canonical, unknown);
  const surds = quad ? quadraticSurdRoots(quad.a, quad.b, quad.c) ?? [] : [];
  steps.push(rootsStep("CANDIDATE_ROOTS", unknown, distinct, surds));
  return { canonical, candidates: distinct, steps, quad, surds };
}

/** Keep the candidates the ORIGINAL equation actually accepts, and show every
 * check — including the ones that fail. */
function sift(
  parts: EquationPart[],
  unknown: string,
  candidates: number[],
  surds: SurdRoot[]
): { kept: number[]; steps: RawStep[] } {
  const kept: number[] = [];
  const steps: RawStep[] = [];
  for (const v of candidates) {
    const ok = verifySolution(parts, { [unknown]: v });
    if (ok) kept.push(v);
    const surd = surds.find((u) => Math.abs(u.value - v) < 1e-9);
    steps.push(checkStep(parts, unknown, v, ok, surd));
  }
  return { kept, steps };
}

function assemble(
  unknown: string,
  parts: EquationPart[],
  id: string,
  name: string,
  granular: RawStep[],
  trustworthy: boolean,
  kept: number[],
  quadratic: { a: number; b: number; c: number } | null = null,
  surds: SurdRoot[] = []
): RootsResult {
  const given = step("GIVEN", `${parts[0].lhs} = ${parts[0].rhs}`);
  const answer = rootsStep("FIND_ROOTS", unknown, kept, surds);
  // Same posture as the atomic step engine: if the working cannot be proved, the
  // ANSWER still ships — just without the walkthrough. Granularity never costs
  // correctness.
  const steps = trustworthy ? [given, ...granular, answer] : [given, answer];
  return {
    roots: kept,
    methods: [{ id, name, examPick: true, steps }],
    plotExpression: null,
    quadratic,
    surds,
  };
}

/** `√(u) = w` — isolate, square, solve, then throw out what squaring invented. */
export function solveRadicalEquation(
  cls: Classification,
  parts: EquationPart[]
): RootsResult | null {
  if (parts.length !== 1) return null;
  const { lhs, rhs } = parts[0];
  const boxed = boxOne(lhs, rhs, "sqrt");
  if (!boxed) return null;
  const unknown = cls.unknown;
  if (!variablesIn(boxed.inner).includes(unknown)) return null;

  const w = isolate(boxed.boxed, unknown);
  if (w === null) return null;

  const isolated = `sqrt(${boxed.inner}) = ${w}`;
  const squared = `${boxed.inner} = (${w})^2`;
  const tail = polynomialTail(`(${boxed.inner}) - ((${w})^2)`, unknown);
  if (!tail) return null;

  const { kept, steps: checks } = sift(parts, unknown, tail.candidates, tail.surds);
  if (kept.length === 0) return null; // "no solution" has no shipped answer shape

  // Expanding the bracket and collecting to one side are two different changes,
  // and a student who is shown only the second has to do the first in their head.
  const expanded = canonicalPolynomial(`(${w})^2`);
  const expandStep =
    expanded && expanded !== w && `${boxed.inner} = ${expanded}` !== squared
      ? [step("EXPAND_SQUARE", `${boxed.inner} = ${expanded}`)]
      : [];

  const granular: RawStep[] = [
    step("ISOLATE_RADICAL", isolated),
    step(
      "SQUARE_BOTH_SIDES",
      `(sqrt(${boxed.inner}))^2 = (${w})^2`,
      `\\left(\\sqrt{${asciiToLatex(boxed.inner)}}\\right)^2 = \\left(${asciiToLatex(w)}\\right)^2`
    ),
    step("RADICAL_CANCELS", squared),
    ...expandStep,
    ...tail.steps,
    ...checks,
  ];

  // Isolating must not change the equation, and collecting must not change the
  // squared one. Squaring itself DOES change the solution set — that is the
  // point, and `sift` is what contains it.
  const trustworthy =
    samePrinted(parts[0], eq(isolated), unknown) &&
    samePrinted(eq(squared), eq(`${tail.canonical} = 0`), unknown) &&
    expandStep.every((s) => samePrinted(eq(squared), eq(s.ascii), unknown));

  return assemble(
    unknown,
    parts,
    "square_both_sides",
    "Square both sides",
    granular,
    trustworthy,
    kept,
    tail.quad,
    tail.surds
  );
}

/** `|u| = w` — two cases, then the same check, because a w that holds the
 * unknown can make a case produce a root the modulus never had. */
export function solveAbsoluteEquation(
  cls: Classification,
  parts: EquationPart[]
): RootsResult | null {
  if (parts.length !== 1) return null;
  const { lhs, rhs } = parts[0];
  const boxed = boxOne(lhs, rhs, "abs");
  if (!boxed) return null;
  const unknown = cls.unknown;
  if (!variablesIn(boxed.inner).includes(unknown)) return null;

  const w = isolate(boxed.boxed, unknown);
  if (w === null) return null;

  const positive = `(${boxed.inner}) - (${w})`;
  const negative = `(${boxed.inner}) + (${w})`;
  const up = polynomialTail(positive, unknown);
  const down = polynomialTail(negative, unknown);
  if (!up || !down) return null;

  const merged: number[] = [];
  for (const v of [...up.candidates, ...down.candidates]) {
    if (!merged.some((u) => Math.abs(u - v) < 1e-9)) merged.push(v);
  }
  merged.sort((a, b) => a - b);
  // Two cases can mean two different quadratics, so the surd pool is the union.
  const surds = [...up.surds, ...down.surds];

  const { kept, steps: checks } = sift(parts, unknown, merged, surds);
  if (kept.length === 0) return null;

  const isolated = `abs(${boxed.inner}) = ${w}`;
  // `|x − 4| = 0` has only one case: zero is the one value whose distance from
  // zero is zero. Printing "or" twice over the same equation would teach a split
  // that isn't there.
  const oneCase = up.canonical === down.canonical;
  const granular: RawStep[] = [
    step("ISOLATE_ABSOLUTE", isolated),
    oneCase
      ? step("ZERO_MODULUS", `${boxed.inner} = 0`)
      : step(
          "ABSOLUTE_CASES",
          `${boxed.inner} = ${w} or ${boxed.inner} = -(${w})`,
          `${asciiToLatex(boxed.inner)} = ${asciiToLatex(w)} \\quad\\text{or}\\quad ${asciiToLatex(boxed.inner)} = -\\left(${asciiToLatex(w)}\\right)`
        ),
    ...(oneCase
      ? []
      : [
          step("CASE_POSITIVE", `${up.canonical} = 0`),
          step("CASE_NEGATIVE", `${down.canonical} = 0`),
        ]),
    rootsStep("CANDIDATE_ROOTS", unknown, merged, surds),
    ...checks,
  ];

  // Each case must be the equation it claims to be. The split itself is where
  // the solution set widens, and `sift` is what closes it again.
  const trustworthy =
    samePrinted(eq(`${boxed.inner} = ${w}`), eq(`${up.canonical} = 0`), unknown) &&
    samePrinted(
      eq(`${boxed.inner} = -(${w})`),
      eq(`${down.canonical} = 0`),
      unknown
    );

  return assemble(
    unknown,
    parts,
    "absolute_cases",
    "Split into two cases",
    granular,
    trustworthy,
    kept,
    null,
    surds
  );
}
