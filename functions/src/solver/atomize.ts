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

import { derivative } from "mathjs";
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

/** Split `a * b` / `a / b` at the TOP level only, respecting parentheses. */
function splitBinary(s: string, op: "*" | "/"): [string, string] | null {
  let depth = 0;
  for (let i = s.length - 1; i >= 0; i--) {
    const ch = s[i];
    if (ch === ")") depth++;
    else if (ch === "(") depth--;
    else if (ch === op && depth === 0) {
      const l = s.slice(0, i).trim();
      const r = s.slice(i + 1).trim();
      if (l && r) return [l, r];
    }
  }
  return null;
}

/**
 * Which rule the top level of `target` calls for. Returns null when it is a
 * standard derivative (power/trig/exp) that a single step already teaches
 * honestly — refining `d/dx(x^3)` into sub-steps would be noise, not teaching.
 */
function decompose(target: string, unknown: string): Decomposition | null {
  const t = stripParens(target);

  const quot = splitBinary(t, "/");
  if (quot && dependsOn(quot[1], unknown)) {
    const [u, v] = quot;
    return {
      code: "RULE_QUOTIENT",
      ruleLatex: "\\left(\\frac{u}{v}\\right)' = \\frac{u'v - uv'}{v^2}",
      parts: [
        { name: "u", expr: u },
        { name: "v", expr: v },
      ],
      recombine: `(${u}) / (${v})`,
      assemble: ([du, dv]) => `((${du}) * (${v}) - (${u}) * (${dv})) / (${v})^2`,
    };
  }

  const prod = splitBinary(t, "*");
  if (prod && dependsOn(prod[0], unknown) && dependsOn(prod[1], unknown)) {
    const [u, v] = prod;
    return {
      code: "RULE_PRODUCT",
      ruleLatex: "(uv)' = u'v + uv'",
      parts: [
        { name: "u", expr: u },
        { name: "v", expr: v },
      ],
      recombine: `(${u}) * (${v})`,
      assemble: ([du, dv]) => `(${du}) * (${v}) + (${u}) * (${dv})`,
    };
  }

  // Chain rule: `f(u)` where the argument is not the bare variable.
  const fn = /^([a-z]+)\s*\((.+)\)$/i.exec(t);
  if (fn) {
    const inner = stripParens(fn[2].trim());
    if (inner !== unknown && dependsOn(inner, unknown)) {
      // Differentiate the OUTER function at a placeholder, then put the inner
      // function back — that substitution IS the chain rule's first factor.
      const PH = "chainu";
      let outerD: string;
      try {
        outerD = derivative(`${fn[1]}(${PH})`, PH).toString();
      } catch {
        return null;
      }
      if (!outerD.includes(PH)) return null; // outer derivative is constant: no lesson
      return {
        code: "RULE_CHAIN",
        ruleLatex: "\\big(f(u)\\big)' = f'(u)\\cdot u'",
        parts: [{ name: "u", expr: inner }],
        recombine: `${fn[1]}(${inner})`,
        assemble: ([du]) => `(${outerD.split(PH).join(`(${inner})`)}) * (${du})`,
      };
    }
  }
  return null;
}

/**
 * `d/dx(x^3 * sin(x)) → 3x^2 sin(x) + x^3 cos(x)` becomes
 *   RULE_PRODUCT        (uv)' = u'v + uv' with u = x^3, v = sin(x)
 *   DIFFERENTIATE_PARTS u' = 3x^2, v' = cos(x)
 *   APPLY_RULE          u'v + uv', assembled
 *   RESULT              the engine's own answer            [= the coarse step]
 *
 * Expands the RESULT step (reading the preceding `d/dx(...)` step for its
 * target), because the leap happens BETWEEN those two, not inside either one.
 *
 * Note the DIFFERENTIATE_PARTS claim: mathjs produced those part derivatives,
 * but they are checked against a difference quotient, so mathjs is never the
 * thing agreeing with itself.
 */
const expandDerivative: Expander = (coarse, prev, ctx) => {
  if (!prev || prev.operationCode !== "DIFFERENTIATE") return null;
  const raw = prev.ascii.trim();
  // Higher-order (`d^2/dx^2`) leaps over several differentiations at once; one
  // rule application can't land on that answer, so leave it unrefined.
  const m = /^d\/d[a-z]\s*\((.+)\)$/i.exec(raw);
  if (!m) return null;
  const target = m[1];
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
      ascii: assembled,
      latex: asciiToLatex(assembled),
      operationCode: "APPLY_RULE",
      // The payoff check: the rule, assembled by hand, equals the VERIFIED answer.
      claim: { kind: "expression", ascii: assembled, equivalentTo: coarse.ascii },
    },
    { ...coarse, claim: { kind: "none" } },
  ];
};

const EXPANDERS: Record<string, Expander> = {
  RESULT: expandDerivative,
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
