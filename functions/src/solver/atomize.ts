/**
 * Atomic Step Engine — the granularity layer between the verified solver and the
 * teaching engine (spec §3 "one transformation = one step").
 *
 * WHY THIS EXISTS. The teaching engine (`teach.ts`) may only narrate steps the
 * solver already emitted — it is forbidden from doing arithmetic. So when a
 * bespoke engine leaps (mathsteps hands back `x^2-5x+6=0 → (x-2)(x-3)=0` as ONE
 * step), no prompt can recover the reasoning that was never computed: the
 * intermediate states do not exist. This module computes them, deterministically.
 *
 * THE GOLDEN RULE, EXTENDED TO GRANULARITY. Every sub-step this module emits is
 * a claim that must PROVE OUT before it ships:
 *
 *   - `equation`    — same solution set as the coarse step it refines, checked by
 *                     proportional residuals over sampled points (not just at the
 *                     roots, so a bogus factorisation that happens to vanish at
 *                     the roots is still caught).
 *   - `identity`    — a closed arithmetic claim; both sides evaluated and compared.
 *   - `disjunction` — the union of the branches' roots must equal the verified
 *                     root set exactly (no root invented, none dropped).
 *
 * and every expansion must END on the coarse step's own `ascii`, byte-for-byte,
 * so refining a step can never change where it lands.
 *
 * If ANY claim fails, the expansion is discarded and the ORIGINAL coarse step
 * ships unchanged. A granularity failure is therefore invisible to correctness —
 * it degrades to exactly today's output, the same posture as the teaching
 * firewall in `teach.ts`.
 */

import { derivative, parse, type MathNode } from "mathjs";

import { asciiToLatex } from "./latex";
import { evalReal } from "./verify";
import type { RawMethod, RawStep } from "./types";

/** What the expanders are allowed to know — all of it already verified. */
export interface AtomizeContext {
  unknown: string;
  /** The problem as it arrived, ascii. Used as the `START` step. */
  originalAscii: string;
  /** Roots the verify gate proved. An expansion may never add to or drop from this. */
  roots: number[];
  quadratic?: { a: number; b: number; c: number } | null;
  /**
   * The statistic being computed and its data, passed through from the
   * classification. Handed over as TYPED VALUES rather than sniffed out of the
   * `COMPUTE` step's label — that label is display prose ("population standard
   * deviation (σ)") and parsing it would make the lesson depend on wording.
   */
  stat?: { kind: string; data: number[] } | null;
  /** The linear-algebra operation and its operands, same reasoning as `stat`. */
  matrix?: { op: string; a: number[][]; b?: number[][] | null } | null;
}

/** The provable assertion a sub-step makes. `none` is for pure labels. */
type Claim =
  /** `ascii` has the same solution set as `equivalentTo`. Both are named
   *  explicitly so a step can never be "proved" by comparing it to itself. */
  | { kind: "equation"; ascii: string; equivalentTo: string }
  | { kind: "identity"; pairs: [number, number][] }
  | { kind: "disjunction"; branches: string[] }
  /** Two EXPRESSIONS (not equations) agree pointwise — the gate for calculus,
   *  where a step rewrites a quantity rather than transforming an equation. */
  | { kind: "expression"; ascii: string; equivalentTo: string }
  /** `d/dx(of) == is`, checked against a central difference quotient — an
   *  INDEPENDENT check, not mathjs agreeing with itself. */
  | { kind: "derivative"; is: string; of: string }
  | { kind: "none" };

interface AtomicStep extends RawStep {
  claim: Claim;
}

type Expander = (
  coarse: RawStep,
  prev: RawStep | null,
  ctx: AtomizeContext,
) => AtomicStep[] | null;

const TOL = 1e-7;
/** Deliberately non-integer so a sample never lands on a root and hides a mismatch. */
const SAMPLES = [-2.7, -1.3, 0.4, 1.6, 2.9, 4.2];

// --- equivalence checking ---------------------------------------------------

/** `lhs - rhs` of an ascii equation, evaluated at `unknown = at`. NaN if unusable. */
function residual(ascii: string, unknown: string, at: number): number {
  const i = ascii.indexOf("=");
  if (i === -1) return NaN;
  const l = evalReal(ascii.slice(0, i), { [unknown]: at });
  const r = evalReal(ascii.slice(i + 1), { [unknown]: at });
  return l - r;
}

/**
 * True when two equations have the same solution set, established by their
 * residuals staying in constant nonzero proportion across the samples. This
 * accepts `2x-2=4` ≡ `x-1=2` (ratio 2) and rejects a factorisation that only
 * agrees at the roots.
 */
function sameSolutionSet(a: string, b: string, unknown: string): boolean {
  let ratio: number | null = null;
  let seen = 0;
  for (const x of SAMPLES) {
    const ra = residual(a, unknown, x);
    const rb = residual(b, unknown, x);
    if (!Number.isFinite(ra) || !Number.isFinite(rb)) continue;
    if (Math.abs(rb) < TOL) {
      if (Math.abs(ra) > 1e-5) return false; // b vanishes where a does not
      continue;
    }
    const k = ra / rb;
    if (ratio === null) ratio = k;
    else if (Math.abs(k - ratio) > 1e-6 * Math.max(1, Math.abs(ratio))) return false;
    seen++;
  }
  return seen >= 3 && ratio !== null && Math.abs(ratio) > TOL;
}

/**
 * Points for comparing EXPRESSIONS. Kept positive and non-integer so `log`,
 * `sqrt` and `1/x` stay defined and no sample lands on a nice value that could
 * mask a mismatch.
 */
const X_SAMPLES = [0.7, 1.3, 2.1, 2.8, 3.4, 4.6];

/** Two expressions agree wherever both are defined (≥3 usable samples). */
function sameExpression(a: string, b: string, unknown: string): boolean {
  let seen = 0;
  for (const x of X_SAMPLES) {
    const va = evalReal(a, { [unknown]: x });
    const vb = evalReal(b, { [unknown]: x });
    if (!Number.isFinite(va) || !Number.isFinite(vb)) continue;
    if (Math.abs(va - vb) > 1e-6 * Math.max(1, Math.abs(va), Math.abs(vb))) return false;
    seen++;
  }
  return seen >= 3;
}

/**
 * `is` really is the derivative of `of`, checked with a central difference
 * quotient. This is deliberately NOT another mathjs `derivative()` call — a
 * symbolic engine agreeing with itself proves nothing about the decomposition.
 */
function isDerivativeOf(is: string, of: string, unknown: string): boolean {
  const h = 1e-5;
  let seen = 0;
  for (const x of X_SAMPLES) {
    const claimed = evalReal(is, { [unknown]: x });
    const up = evalReal(of, { [unknown]: x + h });
    const down = evalReal(of, { [unknown]: x - h });
    if (![claimed, up, down].every(Number.isFinite)) continue;
    const numeric = (up - down) / (2 * h);
    // Loose tolerance: a difference quotient is only ~1e-8 accurate, and this is
    // a sanity gate on the DECOMPOSITION, not a precision test.
    if (Math.abs(claimed - numeric) > 1e-4 * Math.max(1, Math.abs(numeric))) return false;
    seen++;
  }
  return seen >= 3;
}

/** Every verified root satisfies the equation. */
function holdsAtRoots(ascii: string, ctx: AtomizeContext): boolean {
  return ctx.roots.every((r) => {
    const v = residual(ascii, ctx.unknown, r);
    return Number.isFinite(v) && Math.abs(v) < 1e-6;
  });
}

function proves(step: AtomicStep, ctx: AtomizeContext): boolean {
  const c = step.claim;
  switch (c.kind) {
    case "none":
      return true;
    case "identity":
      return c.pairs.every(
        ([l, r]) => Number.isFinite(l) && Number.isFinite(r) && Math.abs(l - r) < 1e-9,
      );
    case "equation":
      // A step compared to itself proves nothing — reject rather than wave through.
      if (c.ascii === c.equivalentTo) return false;
      return (
        holdsAtRoots(c.ascii, ctx) &&
        sameSolutionSet(c.ascii, c.equivalentTo, ctx.unknown)
      );
    case "expression":
      // Unlike `equation`, an identical string here is a real (if trivial) proof:
      // the reference is always a DIFFERENT step's expression, so matching it
      // exactly means the decomposition reproduced the function verbatim.
      if (c.ascii === c.equivalentTo) return true;
      return sameExpression(c.ascii, c.equivalentTo, ctx.unknown);
    case "derivative":
      return isDerivativeOf(c.is, c.of, ctx.unknown);
    case "disjunction": {
      // Solution-set equality: no branch introduces a root, no verified root is lost.
      const branchRoots: number[] = [];
      for (const b of c.branches) {
        const q = evalReal(b, { [ctx.unknown]: 0 });
        const p = evalReal(b, { [ctx.unknown]: 1 }) - q;
        if (!Number.isFinite(p) || !Number.isFinite(q) || Math.abs(p) < TOL) return false;
        branchRoots.push(-q / p);
      }
      const near = (a: number, b: number) => Math.abs(a - b) < 1e-6;
      return (
        branchRoots.every((r) => ctx.roots.some((v) => near(r, v))) &&
        ctx.roots.every((v) => branchRoots.some((r) => near(r, v)))
      );
    }
  }
}

// --- formatting -------------------------------------------------------------

function num(n: number): string {
  const r = Math.round(n);
  return Math.abs(n - r) < 1e-9 ? String(r) : String(Number(n.toFixed(6)));
}

/** Wrap negatives so `-2 + -3` reads as `(-2) + (-3)`, the way a teacher writes it. */
function signed(n: number): string {
  return n < 0 ? `(${num(n)})` : num(n);
}

// --- factor parsing ---------------------------------------------------------

interface LinearFactor {
  /** The factor's own text, e.g. `x - 2`. */
  text: string;
  p: number;
  q: number;
}

/** Split `(x - 2) * (x - 3)` on top-level `*`, ignoring `*` inside parentheses. */
function splitProduct(s: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let cur = "";
  for (const ch of s) {
    if (ch === "(") depth++;
    else if (ch === ")") depth--;
    if (ch === "*" && depth === 0) {
      parts.push(cur);
      cur = "";
    } else cur += ch;
  }
  parts.push(cur);
  return parts.map((p) => p.trim()).filter(Boolean);
}

function stripParens(s: string): string {
  let t = s.trim();
  while (t.startsWith("(") && t.endsWith(")")) {
    let depth = 0;
    let matched = true;
    for (let i = 0; i < t.length; i++) {
      if (t[i] === "(") depth++;
      else if (t[i] === ")") depth--;
      if (depth === 0 && i < t.length - 1) {
        matched = false;
        break;
      }
    }
    if (!matched) break;
    t = t.slice(1, -1).trim();
  }
  return t;
}

/**
 * Read a product of LINEAR factors by sampling rather than by AST shape — robust
 * to however mathsteps chose to print it. Returns null if any factor is not
 * linear in `unknown`, which is exactly when we must not pretend to teach it.
 */
function linearFactors(lhs: string, unknown: string): LinearFactor[] | null {
  // `(x - 1)^2` is a product too — a repeated factor, and the repetition is the
  // whole lesson (one root, not two), so expand it rather than bail.
  const parts = splitProduct(lhs).flatMap((raw) => {
    const pow = /^\((.+)\)\s*\^\s*(\d+)$/.exec(raw.trim());
    if (!pow) return [raw];
    const n = Number(pow[2]);
    if (!Number.isInteger(n) || n < 2 || n > 4) return [raw];
    return Array.from({ length: n }, () => `(${pow[1]})`);
  });
  if (parts.length < 2) return null;
  const out: LinearFactor[] = [];
  for (const raw of parts) {
    const text = stripParens(raw);
    const q = evalReal(text, { [unknown]: 0 });
    const p = evalReal(text, { [unknown]: 1 }) - q;
    if (!Number.isFinite(p) || !Number.isFinite(q)) return null;
    if (Math.abs(p) < TOL) return null; // constant factor — not a linear factor
    // Prove linearity: a quadratic factor would break this at a third point.
    for (const x of [2.3, -1.7]) {
      const v = evalReal(text, { [unknown]: x });
      if (!Number.isFinite(v) || Math.abs(v - (p * x + q)) > 1e-6) return null;
    }
    out.push({ text, p, q });
  }
  return out;
}

// --- expanders --------------------------------------------------------------

/**
 * `x^2 - 5x + 6 = 0  →  (x-2)(x-3) = 0` becomes
 *   START            x^2 - 5x + 6 = 0
 *   FIND_FACTOR_PAIR (-2) x (-3) = 6 and (-2) + (-3) = -5      [monic]
 *   SPLIT_MIDDLE     two numbers multiplying to a*c            [non-monic]
 *   WRITE_FACTORS    (x-2)(x-3) = 0                            [= the coarse step]
 */
const expandFactor: Expander = (coarse, prev, ctx) => {
  const eq = coarse.ascii.indexOf("=");
  if (eq === -1) return null;
  const factors = linearFactors(coarse.ascii.slice(0, eq), ctx.unknown);
  if (!factors) return null;

  const steps: AtomicStep[] = [];
  // What the factored form must be equivalent TO: the step it replaced, or the
  // problem itself when it opens the method.
  const source = prev?.ascii ?? ctx.originalAscii;

  // Only open with START when nothing precedes this step, so we never duplicate.
  if (!prev) {
    steps.push({
      ascii: ctx.originalAscii,
      operationCode: "START",
      claim: { kind: "equation", ascii: ctx.originalAscii, equivalentTo: coarse.ascii },
    });
  }

  const monic = factors.every((f) => Math.abs(f.p - 1) < TOL);
  const q = ctx.quadratic;
  if (monic && factors.length === 2 && q && Math.abs(q.a - 1) < TOL) {
    // The sum-product reasoning the coarse step skipped: which pair, and why.
    const [f1, f2] = factors;
    const sum = f1.q + f2.q;
    const product = f1.q * f2.q;
    steps.push({
      ascii: `${signed(f1.q)} * ${signed(f2.q)} = ${num(product)}, ${signed(f1.q)} + ${signed(f2.q)} = ${num(sum)}`,
      latex: `${signed(f1.q)} \\times ${signed(f2.q)} = ${num(product)}\\quad\\text{and}\\quad ${signed(f1.q)} + ${signed(f2.q)} = ${num(sum)}`,
      operationCode: "FIND_FACTOR_PAIR",
      // The pair is only the right pair if it reproduces b and c.
      claim: { kind: "identity", pairs: [[product, q.c], [sum, q.b]] },
    });
  } else if (factors.length === 2 && q && Math.abs(q.a) > TOL) {
    // Non-monic: the trick moves to a*c, and the middle term splits. Only a pair
    // of factors has a "middle term" to split — more than two and this claim
    // would be arithmetic that means nothing.
    const ac = q.a * q.c;
    const m1 = factors[0].p * factors[1].q;
    const m2 = factors[1].p * factors[0].q;
    if (!Number.isFinite(m1) || !Number.isFinite(m2)) return null;
    steps.push({
      ascii: `${signed(m1)} * ${signed(m2)} = ${num(ac)}, ${signed(m1)} + ${signed(m2)} = ${num(q.b)}`,
      latex: `${signed(m1)} \\times ${signed(m2)} = ${num(ac)}\\quad\\text{and}\\quad ${signed(m1)} + ${signed(m2)} = ${num(q.b)}`,
      operationCode: "SPLIT_MIDDLE_TERM",
      claim: { kind: "identity", pairs: [[m1 * m2, ac], [m1 + m2, q.b]] },
    });
  }

  steps.push({
    ...coarse,
    operationCode: "WRITE_FACTORS",
    // The real claim: this factorisation is the same equation as what it replaced.
    claim: { kind: "equation", ascii: coarse.ascii, equivalentTo: source },
  });
  return steps;
};

/**
 * `(x-2)(x-3) = 0  →  x = [2, 3]` becomes
 *   ZERO_PRODUCT   x - 2 = 0 or x - 3 = 0
 *   FIND_ROOTS     x = [2, 3]                                  [= the coarse step]
 *
 * The zero-product step is the one students are told to skip and then lose a
 * root to, so it earns its own line.
 */
const expandRoots: Expander = (coarse, prev, ctx) => {
  if (!prev) return null;
  const eq = prev.ascii.indexOf("=");
  if (eq === -1) return null;
  // Only meaningful when the previous step really is `product = 0`.
  if (Math.abs(evalReal(prev.ascii.slice(eq + 1), { [ctx.unknown]: 0 })) > TOL) return null;
  const factors = linearFactors(prev.ascii.slice(0, eq), ctx.unknown);
  if (!factors) return null;

  const branches = factors.map((f) => f.text);
  // A repeated factor gives the same case twice — show it once.
  const shown = branches.filter((b, i) => branches.indexOf(b) === i);
  return [
    {
      ascii: shown.map((b) => `${b} = 0`).join(" or "),
      latex: shown
        .map((b) => `${asciiFactorToLatex(b)} = 0`)
        .join("\\quad\\text{or}\\quad "),
      operationCode: "ZERO_PRODUCT",
      claim: { kind: "disjunction", branches },
    },
    // `ascii` stays byte-identical to the coarse step (the invariant is about the
    // math); only DISPLAY is repaired, so the payoff step reads `x = 2 or x = 3`
    // instead of leaking mathsteps' `x = [2, 3]` array syntax.
    { ...coarse, latex: rootListLatex(coarse.ascii, ctx) ?? coarse.latex, claim: { kind: "none" } },
  ];
};

/**
 * Render `x = [2, 3]` as `x = 2 \quad or \quad x = 3`, keeping each root's own
 * exact form (`1/2` stays `\frac{1}{2}`) by re-rendering the parsed text rather
 * than the float. Returns null — leaving display untouched — unless every parsed
 * root evaluates to a verified one and the counts agree.
 */
function rootListLatex(ascii: string, ctx: AtomizeContext): string | null {
  const eq = ascii.indexOf("=");
  if (eq === -1) return null;
  if (ascii.slice(0, eq).trim() !== ctx.unknown) return null;
  const rhs = ascii.slice(eq + 1).trim();
  if (!rhs.startsWith("[") || !rhs.endsWith("]")) return null;

  const parts = rhs.slice(1, -1).split(",").map((s) => s.trim()).filter(Boolean);
  if (!parts.length) return null;
  const values = parts.map((p) => evalReal(p, {}));
  if (values.some((v) => !Number.isFinite(v))) return null;
  // Every displayed root must be a verified root, and every verified root shown.
  const near = (a: number, b: number) => Math.abs(a - b) < 1e-6;
  if (!values.every((v) => ctx.roots.some((r) => near(v, r)))) return null;
  if (!ctx.roots.every((r) => values.some((v) => near(v, r)))) return null;

  const seen: number[] = [];
  const uniq = parts.filter((_, i) => {
    if (seen.some((v) => near(v, values[i]))) return false;
    seen.push(values[i]);
    return true;
  });
  return uniq
    .map((p) => `${ctx.unknown} = ${asciiToLatex(p)}`)
    .join("\\quad\\text{or}\\quad ");
}

/** Minimal ascii→LaTeX for a linear factor (`2x - 1`); no fractions can occur here. */
function asciiFactorToLatex(s: string): string {
  return s.replace(/\*/g, " \\cdot ").replace(/\s+/g, " ").trim();
}

// --- calculus ---------------------------------------------------------------

/** The pieces a differentiation rule breaks a function into. */
interface Decomposition {
  /** Operation code — carries the rule's NAME to the teaching layer. */
  code: "RULE_PRODUCT" | "RULE_QUOTIENT" | "RULE_CHAIN";
  /** `(uv)' = u'v + uv'` — the rule as a student writes it. */
  ruleLatex: string;
  /** `u`/`v` (or the chain rule's inner `u`), as ascii. Each gets differentiated. */
  parts: { name: string; expr: string }[];
  /**
   * The parts put back together as the ORIGINAL function. Proving this equals
   * the target is what stops a decomposition from quietly changing the problem.
   */
  recombine: string;
  /** The whole assembled derivative, ascii, built from the parts' derivatives. */
  assemble: (d: string[]) => string;
}

function dependsOn(expr: string, unknown: string): boolean {
  const a = evalReal(expr, { [unknown]: 1.7 });
  const b = evalReal(expr, { [unknown]: 3.1 });
  if (!Number.isFinite(a) || !Number.isFinite(b)) return true; // assume it does
  return Math.abs(a - b) > 1e-9;
}

/** Drop `ParenthesisNode` wrappers so the top-level operator is visible. */
function unwrap(n: MathNode): MathNode {
  let node = n;
  while (node.type === "ParenthesisNode") {
    node = (node as unknown as { content: MathNode }).content;
  }
  return node;
}

/**
 * The chain rule, built from an outer function written against a placeholder.
 * Differentiating the outer at the placeholder and putting the inner function
 * back IS the `f'(u)` factor — the same move a student makes on paper.
 */
function chainOn(
  outer: (u: string) => string,
  inner: string,
  unknown: string,
): Decomposition | null {
  if (inner === unknown || !dependsOn(inner, unknown)) return null;
  const PH = "chainu";
  let outerD: string;
  try {
    outerD = derivative(outer(PH), PH).toString();
  } catch {
    return null;
  }
  if (!outerD.includes(PH)) return null; // outer derivative is constant: no lesson
  return {
    code: "RULE_CHAIN",
    ruleLatex: "\\big(f(u)\\big)' = f'(u)\\cdot u'",
    parts: [{ name: "u", expr: inner }],
    recombine: outer(`(${inner})`),
    assemble: ([du]) => `(${outerD.split(PH).join(`(${inner})`)}) * (${du})`,
  };
}

/**
 * Which rule the top level of `target` calls for. Reads the mathjs AST rather
 * than the string, because `x^3 sin(x)` is a product with no `*` in it at all.
 *
 * Returns null for a standard derivative (`d/dx(x^3)`, `d/dx(sin x)`) — those
 * are already one honest step, and splitting them would be noise, not teaching.
 */
function decompose(target: string, unknown: string): Decomposition | null {
  let node: MathNode;
  try {
    node = unwrap(parse(target));
  } catch {
    return null;
  }
  const src = (n: MathNode) => unwrap(n).toString();

  if (node.type === "OperatorNode") {
    const op = node as unknown as { op: string; args: MathNode[] };
    if (op.args.length !== 2) return null;
    const [a, b] = op.args.map(src);

    if (op.op === "/" && dependsOn(b, unknown)) {
      return {
        code: "RULE_QUOTIENT",
        ruleLatex: "\\left(\\frac{u}{v}\\right)' = \\frac{u'v - uv'}{v^2}",
        parts: [
          { name: "u", expr: a },
          { name: "v", expr: b },
        ],
        recombine: `(${a}) / (${b})`,
        assemble: ([du, dv]) => `((${du}) * (${b}) - (${a}) * (${dv})) / (${b})^2`,
      };
    }

    if (op.op === "*" && dependsOn(a, unknown) && dependsOn(b, unknown)) {
      return {
        code: "RULE_PRODUCT",
        ruleLatex: "(uv)' = u'v + uv'",
        parts: [
          { name: "u", expr: a },
          { name: "v", expr: b },
        ],
        recombine: `(${a}) * (${b})`,
        assemble: ([du, dv]) => `(${du}) * (${b}) + (${a}) * (${dv})`,
      };
    }

    // `(inner)^k` is the power-with-a-chain case; `k^(inner)` the exponential one.
    if (op.op === "^") {
      if (!dependsOn(b, unknown)) return chainOn((u) => `(${u})^(${b})`, a, unknown);
      if (!dependsOn(a, unknown)) return chainOn((u) => `(${a})^(${u})`, b, unknown);
      return null; // x^x — neither rule alone explains it
    }
    return null;
  }

  // `f(inner)` — chain rule whenever the argument is not the bare variable.
  if (node.type !== "FunctionNode") return null;
  const fn = node as unknown as { fn: { name?: string }; args: MathNode[] };
  const name = fn.fn?.name;
  if (!name || fn.args.length !== 1) return null;
  return chainOn((u) => `${name}(${u})`, src(fn.args[0]), unknown);
}

/**
 * The rule, written out: name it, differentiate each piece, assemble.
 *
 *   RULE_PRODUCT        (uv)' = u'v + uv' with u = x^3, v = sin(x)
 *   DIFFERENTIATE_PARTS u' = 3x^2, v' = cos(x)
 *   APPLY_RULE          u'v + uv', assembled
 *   <coarse>            the engine's own answer, untouched
 *
 * `answer` is what the coarse step lands on and `lhs` the label it wears
 * (`dy/dx`), so the same three steps serve both step shapes below.
 *
 * Note the DIFFERENTIATE_PARTS claim: mathjs produced those part derivatives,
 * but they are checked against a difference quotient, so mathjs is never the
 * thing agreeing with itself.
 */
function ruleSteps(
  target: string,
  answer: string,
  lhs: string | null,
  coarse: RawStep,
  ctx: AtomizeContext,
): AtomicStep[] | null {
  const d = decompose(target, ctx.unknown);
  if (!d) return null;

  const partDs: string[] = [];
  for (const p of d.parts) {
    try {
      partDs.push(derivative(p.expr, ctx.unknown).toString());
    } catch {
      return null;
    }
  }
  // Every part derivative is independently proved before any of it is shown.
  if (!d.parts.every((p, i) => isDerivativeOf(partDs[i], p.expr, ctx.unknown))) {
    return null;
  }
  const assembled = d.assemble(partDs);
  const named = (n: string, e: string) => `${n} = ${e}`;
  const namedLatex = (n: string, e: string) => `${n} = ${asciiToLatex(e)}`;
  const prefix = lhs ? `${lhs} = ` : "";

  return [
    {
      ascii: d.parts.map((p) => named(p.name, p.expr)).join(", "),
      latex: `${d.ruleLatex}\\quad\\text{with}\\quad ${d.parts
        .map((p) => namedLatex(p.name, p.expr))
        .join(",\\; ")}`,
      operationCode: d.code,
      // The decomposition must rebuild the function it came from — otherwise the
      // rest of the walkthrough would be teaching a different problem.
      claim: { kind: "expression", ascii: d.recombine, equivalentTo: target },
    },
    {
      ascii: d.parts.map((p, i) => named(`${p.name}'`, partDs[i])).join(", "),
      latex: d.parts.map((p, i) => namedLatex(`${p.name}'`, partDs[i])).join(",\\; "),
      operationCode: "DIFFERENTIATE_PARTS",
      claim: { kind: "derivative", is: partDs[0], of: d.parts[0].expr },
    },
    {
      ascii: `${prefix}${assembled}`,
      latex: `${lhs ? `${lhs} = ` : ""}${asciiToLatex(assembled)}`,
      operationCode: "APPLY_RULE",
      // The payoff check: the rule, assembled by hand, equals the VERIFIED answer.
      claim: { kind: "expression", ascii: assembled, equivalentTo: answer },
    },
    { ...coarse, claim: { kind: "none" } },
  ];
}

/**
 * `d/dx(x^3 sin(x))` then `3x^2 sin(x) + x^3 cos(x)` — the plain derivative
 * engine. The leap sits BETWEEN the two steps, so the RESULT step is the one
 * expanded, reading its target off the `d/dx(...)` step before it.
 */
const expandDerivativeResult: Expander = (coarse, prev, ctx) => {
  if (!prev || prev.operationCode !== "DIFFERENTIATE") return null;
  // Higher-order (`d^2/dx^2`) leaps over several differentiations at once; one
  // rule application can't land on that answer, so leave it unrefined.
  const m = /^d\/d[a-z]\s*\((.+)\)$/i.exec(prev.ascii.trim());
  if (!m) return null;
  return ruleSteps(m[1], coarse.ascii, null, coarse, ctx);
};

/**
 * `y = x^2 sin(x)` then `dy/dx = 2x sin(x) + x^2 cos(x)` — the shape the
 * calculus engines use (tangent lines, stationary points, optimisation). Here
 * the whole rule is inside ONE step, so that step is what gets expanded.
 */
const expandDerivativeAssignment: Expander = (coarse, prev, ctx) => {
  if (!prev) return null;
  const eq = coarse.ascii.indexOf("=");
  const src = prev.ascii.indexOf("=");
  if (eq === -1 || src === -1) return null;
  const lhs = coarse.ascii.slice(0, eq).trim();
  // First order only, and only when the previous step really is `y = f(x)`.
  if (!/^\\?(frac\{)?d\s*y?/i.test(lhs.replace(/\\/g, "")) || /\^\s*\{?[2-9]/.test(lhs)) {
    return null;
  }
  return ruleSteps(
    prev.ascii.slice(src + 1).trim(),
    coarse.ascii.slice(eq + 1).trim(),
    lhs,
    coarse,
    ctx,
  );
};

// --- arithmetic -------------------------------------------------------------

function gcd(a: number, b: number): number {
  let x = Math.abs(a);
  let y = Math.abs(b);
  while (y) [x, y] = [y, x % y];
  return x || 1;
}
const lcm = (a: number, b: number) => Math.abs(a * b) / gcd(a, b);

/** An integer node's value, seeing through parentheses. Null if it isn't one. */
function intValue(n: MathNode): number | null {
  const node = unwrap(n);
  if (node.type === "UnaryNode" || node.type === "OperatorNode") {
    const op = node as unknown as { op: string; args: MathNode[] };
    if (op.op === "-" && op.args.length === 1) {
      const inner = intValue(op.args[0]);
      return inner === null ? null : -inner;
    }
    return null;
  }
  if (node.type !== "ConstantNode") return null;
  const v = (node as unknown as { value: unknown }).value;
  return typeof v === "number" && Number.isInteger(v) ? v : null;
}

interface Term {
  n: number;
  d: number;
}

/** `1/2 + 1/3 - 1` as signed integer fractions. Null if any term isn't one. */
function fractionTerms(node: MathNode, sign = 1): Term[] | null {
  const n = unwrap(node);
  if (n.type === "OperatorNode") {
    const op = n as unknown as { op: string; args: MathNode[] };
    if (op.args.length === 2 && (op.op === "+" || op.op === "-")) {
      const l = fractionTerms(op.args[0], sign);
      const r = fractionTerms(op.args[1], op.op === "-" ? -sign : sign);
      return l && r ? [...l, ...r] : null;
    }
    if (op.args.length === 2 && op.op === "/") {
      const a = intValue(op.args[0]);
      const b = intValue(op.args[1]);
      if (a === null || b === null || b === 0) return null;
      return [{ n: sign * a, d: b }];
    }
    if (op.args.length === 1 && op.op === "-") return fractionTerms(op.args[0], -sign);
    return null;
  }
  const v = intValue(n);
  return v === null ? null : [{ n: sign * v, d: 1 }];
}

const fracLatex = (n: number, d: number) =>
  d === 1 ? String(n) : `${n < 0 ? "-" : ""}\\frac{${Math.abs(n)}}{${d}}`;

/** `a/b + c/d` joined with the signs a student would write. */
const termsLatex = (ts: Term[]) =>
  ts
    .map((t, i) =>
      i === 0
        ? fracLatex(t.n, t.d)
        : `${t.n < 0 ? " - " : " + "}${fracLatex(Math.abs(t.n), t.d)}`,
    )
    .join("");

const termsAscii = (ts: Term[]) =>
  ts
    .map((t, i) => {
      const body = t.d === 1 ? String(Math.abs(t.n)) : `${Math.abs(t.n)}/${t.d}`;
      if (i === 0) return t.n < 0 ? `-${body}` : body;
      return `${t.n < 0 ? " - " : " + "}${body}`;
    })
    .join("");

/**
 * The lesson `1/2 + 1/3 → 5/6` skips entirely: find the common denominator,
 * rewrite both fractions over it, then add the numerators. Without those the
 * student is shown an answer with no way to reach it.
 */
function fractionSteps(source: string, coarse: RawStep, ctx: AtomizeContext): AtomicStep[] | null {
  let terms: Term[] | null;
  try {
    terms = fractionTerms(parse(source));
  } catch {
    return null;
  }
  if (!terms || terms.length < 2) return null;
  if (!terms.some((t) => t.d > 1)) return null; // whole numbers: not this lesson

  const denominators = terms.map((t) => t.d);
  const common = denominators.reduce(lcm, 1);
  if (!Number.isFinite(common) || common > 10_000) return null;

  const steps: AtomicStep[] = [];
  const rewritten = terms.map((t) => ({ n: (t.n * common) / t.d, d: common }));

  // Only worth stating when the denominators actually differ.
  if (new Set(denominators).size > 1) {
    steps.push({
      ascii: `LCM(${denominators.join(", ")}) = ${common}`,
      latex: `\\text{LCM}(${denominators.join(", ")}) = ${common}`,
      operationCode: "COMMON_DENOMINATOR",
      // Divisibility by every denominator, and leastness, both checked.
      claim: {
        kind: "identity",
        pairs: [
          ...denominators.map((d) => [common % d, 0] as [number, number]),
          [common, denominators.reduce(lcm, 1)],
        ],
      },
    });
    steps.push({
      ascii: termsAscii(rewritten),
      latex: termsLatex(rewritten),
      operationCode: "REWRITE_EQUIVALENT",
      claim: { kind: "expression", ascii: termsAscii(rewritten), equivalentTo: source },
    });
  }

  // `(3 + 2)/6` — the numerators lined up over the shared denominator.
  const sum = rewritten.reduce((a, t) => a + t.n, 0);
  const numerators = rewritten
    .map((t, i) => (i === 0 ? String(t.n) : `${t.n < 0 ? "- " : "+ "}${Math.abs(t.n)}`))
    .join(" ");
  steps.push({
    ascii: `(${numerators})/${common}`,
    latex: `\\frac{${numerators}}{${common}}`,
    operationCode: "COMBINE_NUMERATORS",
    claim: { kind: "expression", ascii: `(${numerators})/${common}`, equivalentTo: source },
  });

  // If it doesn't reduce, the coarse step already IS this — don't say it twice.
  const g = gcd(sum, common);
  if (g > 1 || Math.abs(sum) % common === 0) {
    steps.push({
      ascii: `${sum}/${common}`,
      latex: fracLatex(sum, common),
      operationCode: "ADD_NUMERATORS",
      claim: { kind: "expression", ascii: `${sum}/${common}`, equivalentTo: source },
    });
    // The coarse step is now doing one job — cancelling — so label it that way.
    steps.push({ ...coarse, operationCode: "SIMPLIFY_FRACTION", claim: { kind: "none" } });
  } else {
    steps.push({ ...coarse, claim: { kind: "none" } });
  }
  void ctx;
  return steps;
}

/** One fraction, or null if the node is a sum, a variable, or anything messier. */
function singleFraction(node: MathNode): Term | null {
  const ts = fractionTerms(node);
  return ts && ts.length === 1 ? ts[0] : null;
}

/**
 * `2/3 × 3/5` and `2/3 ÷ 4/9`. Dividing by a fraction is the one every student
 * gets wrong, and "flip the second fraction and multiply" is the step that was
 * missing entirely — the old method jumped from the question to `3/2`.
 */
function fractionProductSteps(
  source: string,
  coarse: RawStep,
  ctx: AtomizeContext,
): AtomicStep[] | null {
  let root: MathNode;
  try {
    root = unwrap(parse(source));
  } catch {
    return null;
  }
  if (root.type !== "OperatorNode") return null;
  const op = root as unknown as { op: string; args: MathNode[] };
  if (op.args.length !== 2 || (op.op !== "*" && op.op !== "/")) return null;
  const a = singleFraction(op.args[0]);
  let b = singleFraction(op.args[1]);
  if (!a || !b) return null;
  if (a.d === 1 && b.d === 1) return null; // whole numbers: nothing to teach here

  const steps: AtomicStep[] = [];
  if (op.op === "/") {
    if (b.n === 0) return null;
    b = { n: b.d * Math.sign(b.n), d: Math.abs(b.n) }; // flip, keeping the sign on top
    steps.push({
      ascii: `${termsAscii([a])} * ${termsAscii([b])}`,
      latex: `${fracLatex(a.n, a.d)} \\times ${fracLatex(b.n, b.d)}`,
      operationCode: "MULTIPLY_BY_RECIPROCAL",
      claim: {
        kind: "expression",
        ascii: `(${a.n}/${a.d}) * (${b.n}/${b.d})`,
        equivalentTo: source,
      },
    });
  }

  const n = a.n * b.n;
  const d = a.d * b.d;
  steps.push({
    ascii: `(${a.n} * ${b.n})/(${a.d} * ${b.d})`,
    latex: `\\frac{${a.n} \\times ${b.n}}{${a.d} \\times ${b.d}}`,
    operationCode: "MULTIPLY_FRACTIONS",
    claim: {
      kind: "expression",
      ascii: `(${a.n} * ${b.n})/(${a.d} * ${b.d})`,
      equivalentTo: source,
    },
  });

  if (gcd(n, d) > 1) {
    steps.push({
      ascii: `${n}/${d}`,
      latex: fracLatex(n, d),
      operationCode: "MULTIPLY_OUT",
      claim: { kind: "expression", ascii: `${n}/${d}`, equivalentTo: source },
    });
    steps.push({ ...coarse, operationCode: "SIMPLIFY_FRACTION", claim: { kind: "none" } });
  } else {
    steps.push({ ...coarse, claim: { kind: "none" } });
  }
  void ctx;
  return steps;
}

const PRECEDENCE: Record<string, number> = {
  "^": 3,
  "*": 2,
  "/": 2,
  "+": 1,
  "-": 1,
};

/**
 * Integers only. A fractional intermediate would have to be substituted back as
 * `(3/4)`, which is itself a division of two constants — the walk would pick it
 * up again next pass and reduce forever. Fraction arithmetic has its own lesson
 * above; this one is for whole numbers, which is where it is actually taught.
 */
function constText(v: number): string | null {
  return Number.isFinite(v) && Number.isInteger(v) ? String(v) : null;
}

interface Reducible {
  node: MathNode;
  op: string;
  depth: number;
  /** True when the operation sits inside brackets — BIDMAS does those first. */
  bracketed: boolean;
}

/** The one operation order-of-operations says to do next, or null when done. */
function nextOperation(root: MathNode): Reducible | null {
  const found: Reducible[] = [];
  const walk = (n: MathNode, depth: number, bracketed: boolean) => {
    if (n.type === "ParenthesisNode") {
      walk((n as unknown as { content: MathNode }).content, depth + 1, true);
      return;
    }
    if (n.type === "OperatorNode") {
      const op = n as unknown as { op: string; args: MathNode[] };
      for (const a of op.args) walk(a, depth + 1, bracketed);
      if (op.args.length === 2 && op.args.every((a) => intValue(a) !== null || isConst(a))) {
        found.push({ node: n, op: op.op, depth, bracketed });
      }
    }
  };
  walk(root, 0, false);
  if (!found.length) return null;
  // Deepest first (that IS "innermost brackets first"), then by precedence,
  // then leftmost — exactly the order BIDMAS prescribes.
  found.sort(
    (a, b) => b.depth - a.depth || (PRECEDENCE[b.op] ?? 0) - (PRECEDENCE[a.op] ?? 0),
  );
  return found[0];
}

function isConst(n: MathNode): boolean {
  const node = unwrap(n);
  return node.type === "ConstantNode" || intValue(node) !== null;
}

const REDUCTION_CODE: Record<string, string> = {
  "^": "INDICES",
  "*": "MULTIPLY_DIVIDE",
  "/": "MULTIPLY_DIVIDE",
  "+": "ADD_SUBTRACT",
  "-": "ADD_SUBTRACT",
};

/**
 * `2^3 + 4 × (7 − 5) → 16` in one step teaches nothing about the order the
 * operations had to happen in. This performs exactly ONE of them per step,
 * brackets → indices → ×÷ → +−, which is the whole lesson.
 */
function orderOfOperationsSteps(
  source: string,
  coarse: RawStep,
  ctx: AtomizeContext,
): AtomicStep[] | null {
  let node: MathNode;
  try {
    node = parse(source);
  } catch {
    return null;
  }
  const steps: AtomicStep[] = [];
  for (let guard = 0; guard < 12; guard++) {
    const next = nextOperation(node);
    if (!next) break;
    const value = evalReal(next.node.toString());
    const text = constText(value);
    if (text === null) return null; // an ugly intermediate helps nobody
    try {
      // Negatives keep their brackets (`5 * (-3)`); positives never need them.
      const sub = parse(value < 0 ? `(${text})` : text);
      node = node.transform((n: MathNode) => (n === next.node ? sub : n)) as MathNode;
      // A bracket around a lone positive number has stopped meaning anything;
      // drop it in the same step rather than spending a step on punctuation.
      node = node.transform((n: MathNode) => {
        if (n.type !== "ParenthesisNode") return n;
        const inner = (n as unknown as { content: MathNode }).content;
        const v = intValue(inner);
        return v !== null && v >= 0 ? inner : n;
      }) as MathNode;
    } catch {
      return null;
    }
    const ascii = node.toString();
    // The last reduction lands on a bare number — that IS the coarse step.
    if (isConst(node)) break;
    steps.push({
      ascii,
      latex: asciiToLatex(ascii),
      operationCode: next.bracketed ? "BRACKETS_FIRST" : REDUCTION_CODE[next.op] ?? "COMPUTE",
      // Every intermediate state must still be worth the same as the problem.
      claim: { kind: "expression", ascii, equivalentTo: source },
    });
  }
  if (!steps.length) return null;
  void ctx;
  return [...steps, { ...coarse, claim: { kind: "none" } }];
}

// --- decimals ---------------------------------------------------------------

/** Digits after the point, or null if this isn't a plain decimal literal. */
function decimalPlaces(text: string): number | null {
  if (!/^-?\d+(?:\.\d+)?$/.test(text)) return null;
  const dot = text.indexOf(".");
  return dot === -1 ? 0 : text.length - dot - 1;
}

/** The two operands of a top-level `a op b`, as they were WRITTEN. */
function binaryLiterals(
  source: string,
): { op: string; left: string; right: string; lp: number; rp: number } | null {
  const m = /^\s*(-?\d+(?:\.\d+)?)\s*([+\-*/])\s*(-?\d+(?:\.\d+)?)\s*$/.exec(source);
  if (!m) return null;
  const [, left, op, right] = m;
  const lp = decimalPlaces(left);
  const rp = decimalPlaces(right);
  if (lp === null || rp === null) return null;
  if (lp === 0 && rp === 0) return null; // whole numbers are a different lesson
  return { op, left, right, lp, rp };
}

/**
 * `0.25 + 0.5` used to be `START → COMPUTE`, with the whole of decimal arithmetic
 * — the part students actually get wrong — invisible.
 *
 * The lesson is the same one in every textbook: scale the decimals up to whole
 * numbers, do the easy arithmetic, then scale back. Written that way the "count
 * the decimal places" rule for × stops being a trick to memorise and becomes
 * visibly just the ÷100.
 *
 * Deliberately ONE binary operation. Mixing decimals into the BIDMAS reducer
 * would reintroduce the non-terminating substitution that made `constText`
 * integers-only in the first place.
 */
function decimalSteps(source: string, coarse: RawStep): AtomicStep[] | null {
  const b = binaryLiterals(source);
  if (!b) return null;
  const { op, left, right, lp, rp } = b;

  const steps: AtomicStep[] = [];
  /** Don't restate the coarse step: `0.1 + 0.2` reaches `3 / 10`, which IS `3/10`. */
  const bare = (s: string) => s.replace(/\s+/g, "");
  const pushUnlessCoarse = (step: AtomicStep) => {
    if (bare(step.ascii) !== bare(coarse.ascii)) steps.push(step);
  };
  let scaled: string;
  let scale: number;

  if (op === "+" || op === "-") {
    const places = Math.max(lp, rp);
    scale = 10 ** places;
    const L = Math.round(Number(left) * scale);
    const R = Math.round(Number(right) * scale);
    // Same number of decimal places first — the alignment IS the lesson for ±.
    if (lp !== rp) {
      const pad = (v: string, p: number) =>
        (p === 0 ? `${v}.` : v) + "0".repeat(places - p);
      const aligned = `${pad(left, lp)} ${op} ${pad(right, rp)}`;
      pushUnlessCoarse({
        ascii: aligned,
        latex: aligned,
        operationCode: "ALIGN_DECIMALS",
        claim: { kind: "identity", pairs: [[evalReal(aligned), evalReal(source)]] },
      });
    }
    scaled = `(${L} ${op} ${R}) / ${scale}`;
    pushUnlessCoarse({
      ascii: scaled,
      latex: `\\frac{${L} ${op} ${R}}{${scale}}`,
      operationCode: "SCALE_TO_WHOLE",
      claim: { kind: "identity", pairs: [[evalReal(scaled), evalReal(source)]] },
    });
    const combined = `${L + (op === "+" ? R : -R)} / ${scale}`;
    pushUnlessCoarse({
      ascii: combined,
      latex: `\\frac{${L + (op === "+" ? R : -R)}}{${scale}}`,
      operationCode: "COMPUTE_WHOLE",
      claim: { kind: "identity", pairs: [[evalReal(combined), evalReal(source)]] },
    });
  } else if (op === "*") {
    scale = 10 ** (lp + rp);
    const L = Math.round(Number(left) * 10 ** lp);
    const R = Math.round(Number(right) * 10 ** rp);
    scaled = `(${L} * ${R}) / ${scale}`;
    pushUnlessCoarse({
      ascii: scaled,
      latex: `\\frac{${L} \\times ${R}}{${scale}}`,
      operationCode: "SCALE_TO_WHOLE",
      claim: { kind: "identity", pairs: [[evalReal(scaled), evalReal(source)]] },
    });
    const product = `${L * R} / ${scale}`;
    pushUnlessCoarse({
      ascii: product,
      latex: `\\frac{${L * R}}{${scale}}`,
      operationCode: "COMPUTE_WHOLE",
      claim: { kind: "identity", pairs: [[evalReal(product), evalReal(source)]] },
    });
  } else {
    // Division: scale BOTH by the same power, so the quotient is unchanged and
    // the divisor becomes a whole number — "move both points the same way".
    const places = Math.max(lp, rp);
    scale = 10 ** places;
    const L = Math.round(Number(left) * scale);
    const R = Math.round(Number(right) * scale);
    if (R === 0) return null;
    scaled = `${L} / ${R}`;
    pushUnlessCoarse({
      ascii: scaled,
      latex: `\\frac{${L}}{${R}}`,
      operationCode: "SCALE_TO_WHOLE",
      claim: { kind: "identity", pairs: [[evalReal(scaled), evalReal(source)]] },
    });
  }

  if (steps.length === 0) return null;
  steps.push({ ...coarse, claim: { kind: "none" } });
  return steps;
}

/**
 * `START → COMPUTE` is the entire arithmetic method today. Which lesson is
 * missing depends on the problem: adding fractions is about the common
 * denominator, decimals are about scaling to whole numbers, and everything else
 * is about the order the operations happen in.
 */
const expandArithmetic: Expander = (coarse, prev, ctx) => {
  if (!prev || prev.operationCode !== "START") return null;
  const source = prev.ascii;
  return (
    fractionSteps(source, coarse, ctx) ??
    fractionProductSteps(source, coarse, ctx) ??
    decimalSteps(source, coarse) ??
    orderOfOperationsSteps(source, coarse, ctx)
  );
};

// --- statistics -------------------------------------------------------------

/**
 * Matches `statistics.ts`'s own formatter exactly. The landing sub-step has to be
 * byte-identical to the coarse answer, so a second rounding rule here would fail
 * the gate on every problem whose result is not an integer.
 */
function statNum(v: number): string {
  return String(Math.round(v * 1e10) / 1e10);
}

/** `4 + 8 - 3`, never `4 + 8 + -3`. */
function joinSum(values: number[]): string {
  return values
    .map((v, i) => (i === 0 ? statNum(v) : v < 0 ? `- ${statNum(-v)}` : `+ ${statNum(v)}`))
    .join(" ");
}

/**
 * Prove the line EXACTLY as printed: split it on `=` and evaluate both sides.
 * A line with no `=` yields a claim that cannot hold, so it is rejected rather
 * than waved through — a sub-step that asserts nothing must not ship as if it did.
 */
function printedIdentity(ascii: string): Claim {
  const i = ascii.indexOf("=");
  if (i === -1) return { kind: "identity", pairs: [[0, 1]] };
  return {
    kind: "identity",
    pairs: [[evalReal(ascii.slice(0, i)), evalReal(ascii.slice(i + 1))]],
  };
}

/** A step whose printed line is its own proof. */
function shownStep(operationCode: string, ascii: string, latex: string): AtomicStep {
  return { operationCode, ascii, latex, claim: printedIdentity(ascii) };
}

function texList(values: number[]): string {
  return values.map(statNum).join(",\\; ");
}

/**
 * The mean, shown as work rather than asserted. Returned as sub-steps so both the
 * `mean` lesson and the variance/σ lessons (which need the mean first) share it.
 */
function meanSteps(data: number[]): { steps: AtomicStep[]; mean: number } | null {
  const total = data.reduce((a, b) => a + b, 0);
  const m = total / data.length;
  if (!Number.isFinite(m)) return null;
  const sumLine = `${joinSum(data)} = ${statNum(total)}`;
  return {
    mean: Number(statNum(m)),
    steps: [
      shownStep("ADD_VALUES", sumLine, `\\sum x = ${sumLine.replace("=", "=")}`),
      shownStep(
        "DIVIDE_BY_COUNT",
        `${statNum(total)} / ${data.length} = ${statNum(m)}`,
        `\\bar{x} = \\frac{${statNum(total)}}{${data.length}} = ${statNum(m)}`,
      ),
    ],
  };
}

/**
 * `START → COMPUTE(formula) → RESULT(answer)` hides the whole calculation inside
 * the last step. This replaces that one step with the working, leaving the formula
 * above it: state the rule, then carry it out.
 *
 * Declines for `mode` (the answer is a set, not a value, so the identity machinery
 * does not apply) and for `min`/`max` (picking the smallest number is not a
 * calculation a step could usefully split).
 */
const expandStatistic: Expander = (coarse, prev, ctx) => {
  const stat = ctx.stat;
  if (!stat || !prev || prev.operationCode !== "COMPUTE") return null;
  const data = stat.data;
  if (data.length < 2 || !data.every(Number.isFinite)) return null;

  const body: AtomicStep[] = [];
  /** What the working arrives at — checked against the already-verified answer. */
  let value: number;

  switch (stat.kind) {
    case "sum": {
      const total = data.reduce((a, b) => a + b, 0);
      const line = `${joinSum(data)} = ${statNum(total)}`;
      body.push(shownStep("ADD_VALUES", line, `\\sum x = ${line}`));
      value = total;
      break;
    }
    case "mean": {
      const built = meanSteps(data);
      if (!built) return null;
      body.push(...built.steps);
      value = built.mean;
      break;
    }
    case "range": {
      const hi = Math.max(...data);
      const lo = Math.min(...data);
      body.push({
        operationCode: "FIND_EXTREMES",
        ascii: `max = ${statNum(hi)}, min = ${statNum(lo)}`,
        latex: `\\max = ${statNum(hi)},\\quad \\min = ${statNum(lo)}`,
        // Not an `=` line: proved by construction below, where the subtraction
        // that uses these two numbers is itself checked as printed.
        claim: { kind: "none" },
      });
      const line = `${statNum(hi)} - ${statNum(lo)} = ${statNum(hi - lo)}`;
      body.push(shownStep("SUBTRACT_EXTREMES", line, `\\max - \\min = ${line}`));
      value = hi - lo;
      break;
    }
    case "median": {
      // A permutation by construction, so there is no arithmetic claim to make —
      // what the sort has to earn is the value it puts in the middle, and that is
      // what the landing check below tests.
      const sorted = [...data].sort((a, b) => a - b);
      body.push({
        operationCode: "SORT_DATA",
        ascii: sorted.map(statNum).join(", "),
        latex: `${texList(sorted)}`,
        claim: { kind: "none" },
      });
      const mid = Math.floor(sorted.length / 2);
      if (sorted.length % 2) {
        // Pure arithmetic — a printed line is only proved if every token in it
        // evaluates, so the word "position" belongs in the LaTeX, not the ascii.
        const line = `(${sorted.length} + 1) / 2 = ${mid + 1}`;
        body.push(
          shownStep(
            "PICK_MIDDLE",
            line,
            `\\text{middle position} = \\frac{${sorted.length} + 1}{2} = ${mid + 1}`,
          ),
        );
        value = sorted[mid];
      } else {
        const a = sorted[mid - 1];
        const b = sorted[mid];
        const line = `(${statNum(a)} + ${statNum(b)}) / 2 = ${statNum((a + b) / 2)}`;
        body.push(
          shownStep(
            "PICK_MIDDLE",
            line,
            `\\frac{${statNum(a)} + ${statNum(b)}}{2} = ${statNum((a + b) / 2)}`,
          ),
        );
        value = (a + b) / 2;
      }
      break;
    }
    case "variance":
    case "std": {
      const built = meanSteps(data);
      if (!built) return null;
      body.push(...built.steps);
      const m = built.mean;
      const devs = data.map((x) => Number(statNum(x - m)));
      const squares = devs.map((d) => Number(statNum(d * d)));
      body.push({
        operationCode: "DEVIATIONS",
        ascii: devs.map(statNum).join(", "),
        latex: `x - \\bar{x}:\\quad ${texList(devs)}`,
        claim: { kind: "identity", pairs: data.map((x, i) => [x - m, devs[i]] as [number, number]) },
      });
      body.push({
        operationCode: "SQUARE_DEVIATIONS",
        ascii: squares.map(statNum).join(", "),
        latex: `(x - \\bar{x})^2:\\quad ${texList(squares)}`,
        claim: {
          kind: "identity",
          pairs: devs.map((d, i) => [d * d, squares[i]] as [number, number]),
        },
      });
      const total = squares.reduce((a, b) => a + b, 0);
      const sumLine = `${joinSum(squares)} = ${statNum(total)}`;
      body.push(
        shownStep("SUM_SQUARES", sumLine, `\\sum (x - \\bar{x})^2 = ${sumLine}`),
      );
      const varLine = `${statNum(total)} / ${data.length} = ${statNum(total / data.length)}`;
      body.push(
        shownStep(
          "DIVIDE_BY_COUNT",
          varLine,
          `\\sigma^2 = \\frac{${statNum(total)}}{${data.length}} = ${statNum(total / data.length)}`,
        ),
      );
      const v = Number(statNum(total / data.length));
      value = v;
      if (stat.kind === "std") {
        const line = `sqrt(${statNum(v)}) = ${statNum(Math.sqrt(v))}`;
        body.push(
          shownStep(
            "SQUARE_ROOT",
            line,
            `\\sigma = \\sqrt{${statNum(v)}} = ${statNum(Math.sqrt(v))}`,
          ),
        );
        value = Math.sqrt(v);
      }
      break;
    }
    default:
      return null;
  }

  // The working must arrive at the answer that was already verified. When it does
  // not — data whose mean is non-terminating, so the printed deviations round away
  // from the exact result — the lesson is discarded and the coarse step ships. A
  // walkthrough that ends somewhere other than the answer teaches the wrong thing.
  if (statNum(value) !== coarse.ascii) return null;

  body.push({ ...coarse, claim: { kind: "none" } });
  return body;
};

// --- linear algebra ---------------------------------------------------------

/** Matches `linalg.ts`'s formatter — the working has to land on its exact strings. */
function matNum(v: number): string {
  return String(Math.round(v * 1e10) / 1e10);
}

function matTex(g: number[][]): string {
  return (
    "\\begin{pmatrix}" +
    g.map((row) => row.map(matNum).join(" & ")).join(" \\\\ ") +
    "\\end{pmatrix}"
  );
}

/** `2 * 5` for a positive entry, `2 * (-5)` for a negative one. */
function factor(v: number): string {
  return v < 0 ? `(${matNum(v)})` : matNum(v);
}

/** A running sum written the way it is read: `1 * 5 + 2 * 7`. */
function dotLine(left: number[], right: number[]): string {
  return left.map((v, k) => `${factor(v)} * ${factor(right[k])}`).join(" + ");
}

/**
 * More entries than this and the walkthrough stops teaching and starts repeating —
 * a 4×4 product is sixteen indistinguishable dot-product lines. Past the cap the
 * coarse step ships, exactly as it does today.
 */
const MAX_SHOWN_ENTRIES = 9;

/** The 2×2 determinant, as the line a student would write. */
function det2Line(m: number[][]): { line: string; value: number } {
  const v = m[0][0] * m[1][1] - m[0][1] * m[1][0];
  return {
    line: `${factor(m[0][0])} * ${factor(m[1][1])} - ${factor(m[0][1])} * ${factor(m[1][0])} = ${matNum(v)}`,
    value: v,
  };
}

function minorAt(m: number[][], row: number, col: number): number[][] {
  return m.filter((_, i) => i !== row).map((r) => r.filter((_, j) => j !== col));
}

/**
 * `START(A) → RESULT(the answer)` is the whole of every matrix method, so the
 * row-by-column work — which IS the topic — is never shown. This expands the
 * result into that work, and shows `B` on the way, which the coarse steps omit
 * entirely for the two-operand operations.
 */
const expandMatrix: Expander = (coarse, prev, ctx) => {
  const mx = ctx.matrix;
  if (!mx || !prev || prev.operationCode !== "START") return null;
  const A = mx.a;
  const B = mx.b ?? null;
  if (!A.length || !A[0].length) return null;

  const body: AtomicStep[] = [];
  /** The answer this working arrives at, formatted as `linalg.ts` formats it. */
  let landed: string;

  const showB = () =>
    body.push({
      operationCode: "SECOND_MATRIX",
      ascii: "B",
      latex: "B = " + matTex(B!),
      // A restatement of an operand, not a claim about it.
      claim: { kind: "none" },
    });

  switch (mx.op) {
    case "multiply": {
      if (!B || A[0].length !== B.length) return null;
      const rows = A.length;
      const cols = B[0].length;
      if (rows * cols > MAX_SHOWN_ENTRIES) return null;
      showB();
      const out: number[][] = [];
      for (let i = 0; i < rows; i++) {
        out.push([]);
        for (let j = 0; j < cols; j++) {
          const col = B.map((r) => r[j]);
          const v = A[i].reduce((acc, x, k) => acc + x * col[k], 0);
          out[i].push(v);
          const line = `${dotLine(A[i], col)} = ${matNum(v)}`;
          body.push(
            shownStep(
              "ENTRY_ROW_BY_COLUMN",
              line,
              `c_{${i + 1}${j + 1}} = ${line.replace(/\*/g, "\\cdot ")}`,
            ),
          );
        }
      }
      landed = matTex(out);
      break;
    }
    case "add":
    case "subtract": {
      if (!B || A.length !== B.length || A[0].length !== B[0].length) return null;
      if (A.length * A[0].length > MAX_SHOWN_ENTRIES) return null;
      showB();
      const sign = mx.op === "add" ? 1 : -1;
      const symbol = mx.op === "add" ? "+" : "-";
      const out = A.map((row, i) => row.map((v, j) => v + sign * B[i][j]));
      for (let i = 0; i < A.length; i++) {
        for (let j = 0; j < A[0].length; j++) {
          const line = `${matNum(A[i][j])} ${symbol} ${factor(B[i][j])} = ${matNum(out[i][j])}`;
          body.push(shownStep("COMBINE_ENTRY", line, `c_{${i + 1}${j + 1}} = ${line}`));
        }
      }
      landed = matTex(out);
      break;
    }
    case "determinant": {
      if (A.length !== A[0].length) return null;
      if (A.length === 2) {
        const { line, value } = det2Line(A);
        body.push(
          shownStep("CROSS_MULTIPLY", line, `\\det = ad - bc = ${line.replace(/\*/g, "\\cdot ")}`),
        );
        landed = matNum(value);
      } else if (A.length === 3) {
        // Cofactor expansion along the first row: each 2×2 minor gets its own
        // step, then one line combines them with the alternating signs.
        const minors = [0, 1, 2].map((j) => det2Line(minorAt(A, 0, j)));
        minors.forEach((m, j) => {
          body.push(
            shownStep("MINOR", m.line, `M_{1${j + 1}} = ${m.line.replace(/\*/g, "\\cdot ")}`),
          );
        });
        const value =
          A[0][0] * minors[0].value - A[0][1] * minors[1].value + A[0][2] * minors[2].value;
        const line =
          `${factor(A[0][0])} * ${factor(minors[0].value)}` +
          ` - ${factor(A[0][1])} * ${factor(minors[1].value)}` +
          ` + ${factor(A[0][2])} * ${factor(minors[2].value)} = ${matNum(value)}`;
        body.push(
          shownStep(
            "COFACTOR_EXPANSION",
            line,
            `\\det = a_{11}M_{11} - a_{12}M_{12} + a_{13}M_{13} = ${line.replace(/\*/g, "\\cdot ")}`,
          ),
        );
        landed = matNum(value);
      } else {
        return null;
      }
      break;
    }
    case "inverse": {
      // Only 2×2: the swap-and-negate formula IS the lesson. Larger inverses go
      // by row reduction, which is a different walkthrough entirely.
      if (A.length !== 2 || A[0].length !== 2) return null;
      const { line, value: d } = det2Line(A);
      if (Math.abs(d) < 1e-12) return null;
      body.push(
        shownStep("CROSS_MULTIPLY", line, `\\det = ad - bc = ${line.replace(/\*/g, "\\cdot ")}`),
      );
      const adj = [
        [A[1][1], -A[0][1]],
        [-A[1][0], A[0][0]],
      ];
      body.push({
        operationCode: "ADJUGATE",
        ascii: adj.map((r) => r.map(matNum).join(", ")).join("; "),
        latex:
          `\\operatorname{adj}(A) = \\begin{pmatrix}d & -b \\\\ -c & a\\end{pmatrix} = ` +
          matTex(adj),
        // Each entry is a claim about where it came from in A, not free-floating.
        claim: {
          kind: "identity",
          pairs: [
            [A[1][1], adj[0][0]],
            [-A[0][1], adj[0][1]],
            [-A[1][0], adj[1][0]],
            [A[0][0], adj[1][1]],
          ] as [number, number][],
        },
      });
      const out = adj.map((r) => r.map((v) => v / d));
      for (let i = 0; i < 2; i++) {
        for (let j = 0; j < 2; j++) {
          const l = `${factor(adj[i][j])} / ${factor(d)} = ${matNum(out[i][j])}`;
          body.push(shownStep("DIVIDE_BY_DET", l, `\\frac{${matNum(adj[i][j])}}{${matNum(d)}} = ${matNum(out[i][j])}`));
        }
      }
      landed = matTex(out);
      break;
    }
    case "trace": {
      if (A.length !== A[0].length || A.length < 2) return null;
      const diag = A.map((row, i) => row[i]);
      const value = diag.reduce((a, b) => a + b, 0);
      const line = `${joinSum(diag)} = ${matNum(value)}`;
      body.push(
        shownStep("SUM_DIAGONAL", line, `\\operatorname{tr}(A) = ${line}`),
      );
      landed = matNum(value);
      break;
    }
    default:
      return null;
  }

  // The coarse result carries its own prefix (`AB = `, `\det = `, …). Requiring
  // the working to end in exactly that answer ties the lesson to the shipped,
  // already-verified result without re-deriving how the prefix is written.
  if (!coarse.ascii.endsWith(landed)) return null;

  body.push({ ...coarse, claim: { kind: "none" } });
  return body;
};

const EXPANDERS: Record<string, Expander> = {
  RESULT: (coarse, prev, ctx) =>
    expandDerivativeResult(coarse, prev, ctx) ??
    expandStatistic(coarse, prev, ctx) ??
    expandMatrix(coarse, prev, ctx),
  DIFFERENTIATE: expandDerivativeAssignment,
  COMPUTE: expandArithmetic,
  FACTOR_SUM_PRODUCT_RULE: expandFactor,
  FACTOR_DIFFERENCE_OF_SQUARES: expandFactor,
  FACTOR_PERFECT_SQUARE: expandFactor,
  FACTORISE: expandFactor,
  FIND_ROOTS: expandRoots,
};

// --- entry point ------------------------------------------------------------

/**
 * Refine a method's steps into atomic ones. Each coarse step is replaced only if
 * its expansion proves out AND lands on the coarse step's own `ascii`; otherwise
 * that step ships exactly as it arrived.
 */
export function atomizeMethod(m: RawMethod, ctx: AtomizeContext): RawMethod {
  const out: RawStep[] = [];
  for (let i = 0; i < m.steps.length; i++) {
    const coarse = m.steps[i];
    const expander = EXPANDERS[coarse.operationCode];
    // `prev` is the coarse predecessor: expanders reason about the step they
    // refine, never about sub-steps a sibling expander happened to emit.
    const prev = i > 0 ? m.steps[i - 1] : null;
    const expanded = expander ? expander(coarse, prev, ctx) : null;

    if (
      expanded &&
      expanded.length > 1 &&
      expanded[expanded.length - 1].ascii === coarse.ascii &&
      expanded.every((s) => proves(s, ctx))
    ) {
      for (const s of expanded) {
        const { claim: _claim, ...step } = s;
        out.push(step);
      }
    } else {
      out.push(coarse);
    }
  }
  return { ...m, steps: out };
}

export function atomizeMethods(methods: RawMethod[], ctx: AtomizeContext): RawMethod[] {
  return methods.map((m) => {
    try {
      return atomizeMethod(m, ctx);
    } catch {
      return m; // never let a granularity failure cost a verified answer
    }
  });
}
