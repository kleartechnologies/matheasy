/**
 * Symmetric functions of the roots — "the cubic 2x³ − 3x² + 4x − 5 = 0 has roots
 * α, β, γ; find α + β + γ" and its whole family (Σα², Σ1/α, αβγ, Σαβ).
 *
 * The question is never asking you to SOLVE the cubic. Most of these cubics have
 * one real root and an irrational pair, so the equation route had nothing to say
 * and the whole family dead-ended at the tutor.
 *
 * TWO ROUTES, and they share no step:
 *
 *  • The ANSWER comes from the roots themselves — Durand–Kerner converges to all
 *    n complex roots at once, and the requested expression is evaluated on them.
 *  • The GATE never finds a root. It multiplies the root set back out —
 *    a·∏(x − rₖ) — and demands it reproduce the polynomial that was printed,
 *    coefficient for coefficient. That is the substitution-back the golden rule
 *    asks for, run in the opposite direction from the iteration that produced
 *    the roots. Then Newton's identities, computed from the COEFFICIENTS with no
 *    root-finding anywhere, confirm the power sums a second time whenever the
 *    ask is one.
 *
 * And a third thing has to hold before any of it means anything: the value must
 * be the SAME under every relabelling of the roots. "α + β" for a cubic is not a
 * number — it depends on which root you called γ — so it is declined rather than
 * answered with whichever labelling the root-finder happened to produce.
 */
import { Complex, MathNode, add, complex, divide, evaluate, multiply, parse, subtract } from "mathjs";

import { latexToAscii, unwrapProse } from "./latex";
import { FinalAnswer, RawStep, SolveCandidate } from "./types";

/** Degrees worth attempting: below 2 there is nothing symmetric to ask, and
 * above 6 the permutation check stops being exhaustive. */
const MIN_DEGREE = 2;
const MAX_DEGREE = 6;

/** The letters a sheet uses to name roots. Latin singles are allowed but must
 * not collide with the polynomial's own variable. */
const GREEK_ROOT_NAMES = new Set([
  "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta",
  "theta", "lambda", "mu", "nu", "xi", "rho", "sigma", "tau", "phi", "chi",
  "psi", "omega",
]);

export interface VietaQuery {
  /** Ascending: `coeffs[k]` multiplies xᵏ. */
  coeffs: number[];
  variable: string;
  /** One name per root, in the order they were declared. */
  symbols: string[];
  /** The requested expression, as mathjs-parsable ascii over `symbols`. */
  exprAscii: string;
  exprLatex: string;
  polyLatex: string;
}

// ---------------------------------------------------------------------------
// parse
// ---------------------------------------------------------------------------

/** `\alpha` → `alpha`, so mathjs sees a symbol rather than a stray backslash. */
function deGreek(s: string): string {
  return s.replace(/\\([a-zA-Z]+)/g, (full, word: string) =>
    GREEK_ROOT_NAMES.has(word) ? word : full
  );
}

/** Letter runs that belong to the maths rather than to the sentence. */
const MATH_WORDS = new Set(["sin", "cos", "tan", "ln", "log", "exp", "sqrt", "abs", "pi"]);

/**
 * The maths AFTER the last English word.
 *
 * "The cubic 2x³ − 3x² + 4x − 5 = 0" hands back the whole clause, prose and all,
 * and mathjs then reads "The cubic" as three more variables — three symbols, so
 * the parse gave up on a polynomial it can read perfectly well.
 */
function mathTail(s: string): string {
  let cut = 0;
  for (const m of s.matchAll(/(\\?)([A-Za-z]{2,})/g)) {
    if (m[1]) continue; // a LaTeX command, not a word
    if (MATH_WORDS.has(m[2].toLowerCase())) continue;
    cut = (m.index ?? 0) + m[0].length;
  }
  return s.slice(cut).trim();
}

const DIRECTIVE =
  /\b(?:find|determine|evaluate|calculate|compute|state|write\s+down)\b(?:\s+the\s+value\s+of)?(?:\s+the\s+exact\s+value\s+of)?/i;

/** The root names in "…has roots α, β and γ". */
function parseRootSymbols(rawLatex: string, variable: string): string[] | null {
  const m = /\b(?:has|have|with|whose|are\s+the)\s+roots?\b(?:\s+are)?\s*:?\s*/i.exec(rawLatex);
  if (!m) return null;
  const tail = rawLatex.slice(m.index + m[0].length);
  // Stop at the sentence end or at the directive — "…roots α, β, γ. Find α+β+γ"
  // would otherwise collect the ask's symbols a second time.
  const stop = tail.search(/\.|\bfind\b|\bdetermine\b|\bevaluate\b|\bcalculate\b|\bcompute\b|\bshow\b|\bprove\b/i);
  const list = stop >= 0 ? tail.slice(0, stop) : tail;
  const names: string[] = [];
  for (const t of list.matchAll(/\\?([a-zA-Z]+)(?:_\{?(\d+)\}?)?/g)) {
    const word = t[1];
    const sub = t[2];
    if (/^(?:and|are|the|of|equation|cubic|quartic|quadratic|polynomial|text)$/i.test(word)) continue;
    const isRootName = GREEK_ROOT_NAMES.has(word.toLowerCase()) || word.length === 1;
    if (!isRootName) return null; // a word we can't read is a parse we shouldn't trust
    const name = sub ? `${word}_${sub}` : word;
    if (name === variable) return null; // the unknown is not one of its own roots
    if (names.includes(name)) return null;
    names.push(name);
  }
  return names.length >= MIN_DEGREE ? names : null;
}

/** Ascending coefficients of `expr` in `variable`, or null when it isn't a
 * polynomial with numeric coefficients. */
function polynomialCoefficients(ascii: string, variable: string): number[] | null {
  let node: MathNode;
  try {
    node = parse(ascii);
  } catch {
    return null;
  }
  // Every symbol must be the unknown — a parameter would make the coefficients
  // symbolic and Vieta would return an expression, not a number.
  let clean = true;
  node.traverse((n) => {
    const s = n as unknown as { type: string; name?: string };
    if (s.type === "SymbolNode" && s.name !== variable && s.name !== "e" && s.name !== "pi") {
      clean = false;
    }
  });
  if (!clean) return null;

  // Read the coefficients off n+1 sample points by exact Lagrange over integer
  // nodes. Degree is bounded, so this is cheap and needs no algebra package.
  const degree = polynomialDegree(node, variable);
  if (degree === null || degree < MIN_DEGREE || degree > MAX_DEGREE) return null;
  const xs = Array.from({ length: degree + 1 }, (_, i) => i - Math.floor(degree / 2));
  const ys: number[] = [];
  for (const x of xs) {
    let y: number;
    try {
      y = Number(evaluate(ascii, { [variable]: x }));
    } catch {
      return null;
    }
    if (!Number.isFinite(y)) return null;
    ys.push(y);
  }
  const coeffs = lagrangeCoefficients(xs, ys);
  if (!coeffs) return null;
  // The interpolation is only the polynomial if it AGREES away from its nodes.
  for (const x of [0.37, -1.83, 2.6]) {
    let y: number;
    try {
      y = Number(evaluate(ascii, { [variable]: x }));
    } catch {
      return null;
    }
    const model = coeffs.reduce((s, c, k) => s + c * x ** k, 0);
    if (!Number.isFinite(y) || Math.abs(y - model) > 1e-7 * Math.max(1, Math.abs(y))) return null;
  }
  return coeffs;
}

/** The highest power of `variable` appearing, or null if the shape isn't a plain
 * polynomial (a division by the variable, a function of it, a fractional power). */
function polynomialDegree(node: MathNode, variable: string): number | null {
  let degree = 0;
  let ok = true;
  node.traverse((n) => {
    const s = n as unknown as {
      type: string;
      op?: string;
      fn?: unknown;
      args?: unknown[];
      name?: string;
      value?: unknown;
    };
    if (s.type === "FunctionNode") ok = false;
    if (s.type === "OperatorNode" && (s.op === "/" || s.op === "%")) {
      // A variable in the denominator is not polynomial.
      const den = (s.args?.[1] ?? null) as { traverse?: (f: (x: unknown) => void) => void } | null;
      den?.traverse?.((d) => {
        const t = d as { type?: string; name?: string };
        if (t.type === "SymbolNode" && t.name === variable) ok = false;
      });
    }
    if (s.type === "OperatorNode" && s.op === "^") {
      const base = s.args?.[0] as { type?: string; name?: string } | undefined;
      const exp = s.args?.[1] as { type?: string; value?: unknown } | undefined;
      const p = Number(exp?.value);
      if (!Number.isInteger(p) || p < 0 || p > MAX_DEGREE) ok = false;
      else if (base?.type === "SymbolNode" && base.name === variable) degree = Math.max(degree, p);
    }
    if (s.type === "SymbolNode" && s.name === variable) degree = Math.max(degree, 1);
  });
  return ok ? degree : null;
}

/** Ascending coefficients of the polynomial through (xs, ys). */
function lagrangeCoefficients(xs: number[], ys: number[]): number[] | null {
  const n = xs.length;
  const out = new Array<number>(n).fill(0);
  for (let i = 0; i < n; i++) {
    // The basis polynomial ∏_{j≠i} (x − xⱼ) / (xᵢ − xⱼ), built up term by term.
    let basis = [1];
    let denom = 1;
    for (let j = 0; j < n; j++) {
      if (j === i) continue;
      denom *= xs[i] - xs[j];
      const next = new Array<number>(basis.length + 1).fill(0);
      for (let k = 0; k < basis.length; k++) {
        next[k + 1] += basis[k];
        next[k] -= basis[k] * xs[j];
      }
      basis = next;
    }
    if (!Number.isFinite(denom) || denom === 0) return null;
    for (let k = 0; k < basis.length; k++) out[k] += (ys[i] * basis[k]) / denom;
  }
  return out.every(Number.isFinite) ? out : null;
}

export function parseVieta(rawLatex: string): VietaQuery | null {
  const prose = unwrapProse(rawLatex);
  if (!/\broots?\b/i.test(prose)) return null;
  const dir = DIRECTIVE.exec(prose);
  if (!dir) return null;

  // The polynomial: the "… = 0" that comes BEFORE the ask.
  const head = prose.slice(0, dir.index);
  const eq = /([^.:;]*?)\s*=\s*0\b/.exec(head);
  if (!eq) return null;
  const polyLatex = mathTail(eq[1]);
  const polyAscii = latexToAscii(polyLatex).trim();
  if (!polyAscii) return null;
  const vars = new Set<string>();
  try {
    parse(polyAscii).traverse((n) => {
      const s = n as unknown as { type: string; name?: string };
      if (s.type === "SymbolNode" && s.name && !["e", "pi", "i"].includes(s.name)) vars.add(s.name);
    });
  } catch {
    return null;
  }
  if (vars.size !== 1) return null;
  const variable = [...vars][0];
  const coeffs = polynomialCoefficients(polyAscii, variable);
  if (!coeffs) return null;

  const symbols = parseRootSymbols(head, variable);
  if (!symbols) return null;
  if (symbols.length !== coeffs.length - 1) return null; // n roots for degree n

  // The ask: everything after the directive.
  const exprLatex = prose
    .slice(dir.index + dir[0].length)
    .replace(/[.?]\s*$/, "")
    .trim();
  if (!exprLatex) return null;
  const exprAscii = deGreek(latexToAscii(exprLatex)).trim();
  if (!exprAscii) return null;

  // It has to be an expression in the ROOT NAMES and nothing else — otherwise
  // it is a different question that merely followed a sentence about roots.
  const used = new Set<string>();
  try {
    parse(exprAscii).traverse((n) => {
      const s = n as unknown as { type: string; name?: string };
      if (s.type === "SymbolNode" && s.name) used.add(s.name);
    });
  } catch {
    return null;
  }
  if (used.size === 0) return null;
  for (const u of used) {
    if (!symbols.includes(u)) return null;
  }
  // Every root has to appear. A symmetric function of all n roots always names
  // all n of them, so "the cubic has roots α, β, γ — find α + β" is caught here
  // and handed to the tutor, rather than answered with a number that depends on
  // which root the solver happened to call γ.
  for (const sym of symbols) {
    if (!used.has(sym)) return null;
  }

  return { coeffs, variable, symbols, exprAscii, exprLatex, polyLatex };
}

// ---------------------------------------------------------------------------
// solve
// ---------------------------------------------------------------------------

const cAdd = (x: Complex, y: Complex): Complex => add(x, y) as Complex;
const cSub = (x: Complex, y: Complex): Complex => subtract(x, y) as Complex;
const cMul = (x: Complex, y: Complex): Complex => multiply(x, y) as Complex;
const cDiv = (x: Complex, y: Complex): Complex => divide(x, y) as Complex;

/** All n complex roots at once (Durand–Kerner), or null when it hasn't settled. */
function allRoots(coeffs: number[]): Complex[] | null {
  const n = coeffs.length - 1;
  const lead = coeffs[n];
  if (!(Math.abs(lead) > 0)) return null;
  const a = coeffs.map((c) => c / lead);
  const at = (z: Complex): Complex => {
    let p = complex(0, 0);
    for (let i = n; i >= 0; i--) p = cAdd(cMul(p, z), complex(a[i], 0));
    return p;
  };
  // Seeded off the unit circle at an angle that is no low-order root of unity,
  // so no two starting points ever collide.
  let z = Array.from({ length: n }, (_, k) =>
    complex(0.4 * Math.cos(0.9 + (2 * Math.PI * k) / n), 0.4 * Math.sin(0.9 + (2 * Math.PI * k) / n))
  );
  for (let iter = 0; iter < 600; iter++) {
    let moved = 0;
    const next = [...z];
    for (let k = 0; k < n; k++) {
      let d = at(z[k]);
      for (let j = 0; j < n; j++) {
        if (j === k) continue;
        const gap = cSub(z[k], z[j]);
        if (Math.hypot(gap.re, gap.im) < 1e-15) return null; // no clean split
        d = cDiv(d, gap);
      }
      next[k] = cSub(z[k], d);
      moved = Math.max(moved, Math.hypot(d.re, d.im));
    }
    z = next;
    if (!z.every((w) => Number.isFinite(w.re) && Number.isFinite(w.im))) return null;
    if (moved < 1e-14) break;
  }
  return z;
}

/**
 * The gate: multiply the roots back out and require them to rebuild the
 * polynomial that was printed. No root-finding happens here — this is pure
 * coefficient arithmetic, and it is what makes the root list trustworthy.
 */
function rootsRebuildPolynomial(roots: Complex[], coeffs: number[]): boolean {
  const lead = coeffs[coeffs.length - 1];
  let poly: Complex[] = [complex(1, 0)]; // ascending
  for (const r of roots) {
    const next: Complex[] = Array.from({ length: poly.length + 1 }, () => complex(0, 0));
    for (let k = 0; k < poly.length; k++) {
      next[k + 1] = cAdd(next[k + 1], poly[k]);
      next[k] = cSub(next[k], cMul(poly[k], r));
    }
    poly = next;
  }
  if (poly.length !== coeffs.length) return false;
  const scale = Math.max(1, ...coeffs.map(Math.abs));
  for (let k = 0; k < coeffs.length; k++) {
    const want = coeffs[k];
    const got = cMul(poly[k], complex(lead, 0));
    if (Math.abs(got.re - want) > 1e-7 * scale) return false;
    if (Math.abs(got.im) > 1e-7 * scale) return false;
  }
  return true;
}

/** Every permutation of `xs`, for n ≤ 6 (720 at worst). */
function permutations<T>(xs: T[]): T[][] {
  if (xs.length <= 1) return [xs];
  const out: T[][] = [];
  for (let i = 0; i < xs.length; i++) {
    const rest = [...xs.slice(0, i), ...xs.slice(i + 1)];
    for (const p of permutations(rest)) out.push([xs[i], ...p]);
  }
  return out;
}

type Compiled = { evaluate: (scope: Record<string, Complex>) => unknown };

/** Compiled once — a degree-6 symmetry check evaluates the same expression 720
 * times, and re-parsing it each time is the whole cost. */
function compileExpr(exprAscii: string): Compiled | null {
  try {
    return parse(exprAscii).compile();
  } catch {
    return null;
  }
}

function evalOn(expr: Compiled, symbols: string[], roots: Complex[]): Complex | null {
  const scope: Record<string, Complex> = {};
  symbols.forEach((s, i) => (scope[s] = roots[i]));
  try {
    const v = expr.evaluate(scope) as unknown;
    const c =
      typeof v === "number"
        ? complex(v, 0)
        : v && typeof v === "object" && "re" in (v as Complex)
          ? (v as Complex)
          : null;
    return c && Number.isFinite(c.re) && Number.isFinite(c.im) ? c : null;
  } catch {
    return null;
  }
}

/** Elementary symmetric functions e₁…eₙ, straight off the coefficients. */
function elementarySymmetric(coeffs: number[]): number[] {
  const n = coeffs.length - 1;
  const lead = coeffs[n];
  const e = [1];
  for (let k = 1; k <= n; k++) e.push(((-1) ** k * coeffs[n - k]) / lead);
  return e;
}

/**
 * Power sums p₁…p_m by Newton's identities — computed from the COEFFICIENTS, so
 * it touches no root and confirms the root-based answer independently.
 */
function powerSums(coeffs: number[], m: number): number[] {
  const n = coeffs.length - 1;
  const e = elementarySymmetric(coeffs);
  const p = [n]; // p₀ = n
  for (let k = 1; k <= m; k++) {
    // Up to degree n the identity carries a `k·e_k` tail and the sum stops one
    // short; past it the tail is gone and the sum runs the full n. Running both
    // at once double-counts the last term — p₃ of a QUADRATIC came out wrong and
    // nothing else did, because that is the first k where the two disagree.
    const top = k <= n ? k - 1 : n;
    let s = 0;
    for (let i = 1; i <= top; i++) s += (-1) ** (i - 1) * e[i] * p[k - i];
    if (k <= n) s += (-1) ** (k - 1) * k * e[k];
    p.push(s);
  }
  return p;
}

/** `α^k + β^k + …` — the ask this whole family is usually about. If it is one,
 * return k so Newton's identities can confirm the answer. */
function powerSumExponent(exprAscii: string, symbols: string[]): number | null {
  const terms = exprAscii.split("+").map((t) => t.trim());
  if (terms.length !== symbols.length) return null;
  const seen = new Set<string>();
  let k: number | null = null;
  for (const t of terms) {
    const m = /^([a-zA-Z][a-zA-Z0-9_]*)(?:\s*\^\s*\(?\s*(\d+)\s*\)?)?$/.exec(t);
    if (!m) return null;
    if (!symbols.includes(m[1]) || seen.has(m[1])) return null;
    seen.add(m[1]);
    const p = m[2] ? parseInt(m[2], 10) : 1;
    if (k === null) k = p;
    else if (k !== p) return null;
  }
  return k;
}

/** A rational spelling of a value that really is one. */
function asRational(v: number): { num: number; den: number } | null {
  for (let den = 1; den <= 5040; den++) {
    const num = Math.round(v * den);
    if (Math.abs(v - num / den) < 1e-9 * Math.max(1, Math.abs(v))) {
      const g = gcd(Math.abs(num), den) || 1;
      return { num: num / g, den: den / g };
    }
  }
  return null;
}
function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

function answerOf(v: number): FinalAnswer {
  const r = asRational(v);
  if (r && r.den !== 1) {
    const sign = r.num < 0 ? "-" : "";
    return {
      latex: `${sign}\\frac{${Math.abs(r.num)}}{${r.den}}`,
      plain: `${r.num}/${r.den}`,
    };
  }
  const s = String(Math.round(v * 1e10) / 1e10);
  return { latex: s, plain: s };
}

function step(latex: string, code: string): RawStep {
  return { ascii: latex, operationCode: code, latex };
}

export function solveVieta(cls: { vieta?: VietaQuery }): SolveCandidate | null {
  const q = cls.vieta;
  if (!q) return null;
  const roots = allRoots(q.coeffs);
  if (!roots) return null;
  if (!rootsRebuildPolynomial(roots, q.coeffs)) return null;

  const expr = compileExpr(q.exprAscii);
  if (!expr) return null;
  const value = evalOn(expr, q.symbols, roots);
  if (!value) return null;
  const scale = Math.max(1, Math.abs(value.re));
  // A symmetric function of the roots of a REAL polynomial is real. An
  // imaginary part left over means the expression wasn't symmetric.
  if (Math.abs(value.im) > 1e-6 * scale) return null;

  // Relabelling the roots must not change the answer — otherwise the question
  // has no single answer and whichever one the root-finder produced is an
  // accident of its seeding, not a result.
  for (const perm of permutations(roots)) {
    const v = evalOn(expr, q.symbols, perm);
    if (!v) return null;
    if (Math.abs(v.re - value.re) > 1e-6 * scale) return null;
    if (Math.abs(v.im) > 1e-6 * scale) return null;
  }

  // Newton's identities, from the coefficients alone, for the power-sum asks.
  const k = powerSumExponent(q.exprAscii, q.symbols);
  const steps: RawStep[] = [
    step(`${q.polyLatex} = 0`, "START"),
    step(
      `e_1 = ${fmt(elementarySymmetric(q.coeffs)[1])},\\quad e_n = ${fmt(
        elementarySymmetric(q.coeffs)[q.coeffs.length - 1]
      )}`,
      "IDENTIFY_COEFFICIENTS"
    ),
  ];
  if (k !== null && k >= 1 && k <= 12) {
    const p = powerSums(q.coeffs, k)[k];
    if (!Number.isFinite(p) || Math.abs(p - value.re) > 1e-6 * scale) return null;
    steps.push(step(`p_{${k}} = ${fmt(p)} \\text{ (Newton's identities)}`, "APPLY_RULE"));
  }
  steps.push(step(`${q.exprLatex} = ${answerOf(value.re).latex}`, "RESULT"));

  return {
    answer: answerOf(value.re),
    methods: [{ id: "vieta", name: "Symmetric functions of the roots", examPick: true, steps }],
    plotExpression: null,
    verify: () => true,
  };
}

function fmt(v: number): string {
  return String(Math.round(v * 1e10) / 1e10);
}
