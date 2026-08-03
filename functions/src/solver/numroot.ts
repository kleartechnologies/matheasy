/**
 * A root asked for as a NUMBER — "find the positive root of sin x = ½x to 6
 * decimal places", "use Newton–Raphson to solve x³ − x − 1 = 0 to 5 d.p."
 *
 * These were split between two wrong answers. The transcendental ones reached
 * the tutor; the polynomial ones were handed to the exact-equation route, which
 * answers with a closed form when the question asked for six digits. Neither is
 * the thing on the mark scheme.
 *
 * TWO ROUTES, and they share no step:
 *  • The ANSWER comes from bisection — a bracket where the sign changes, halved
 *    until it closes. It uses nothing but the sign of `f`, and no derivative.
 *  • The GATE re-finds the same root with Newton–Raphson, started from the far
 *    end of the bracket and driven by mathjs's symbolic derivative. A tangent
 *    line and a sign test have no machinery in common, so agreeing to 1e-9 is
 *    real evidence rather than the same arithmetic run twice.
 *
 * And rounding is part of the answer, not a display detail. A root that sits on
 * the rounding boundary of the requested digit has no correct N-place spelling,
 * so it is declined rather than rounded one way and asserted.
 */
import { derivative, parse } from "mathjs";

import { latexToAscii, unwrapProse } from "./latex";
import { FinalAnswer, RawStep, SolveCandidate } from "./types";
import { evalReal } from "./verify";

const WORD_DIGITS = new Map<string, number>([
  ["one", 1], ["two", 2], ["three", 3], ["four", 4], ["five", 5],
  ["six", 6], ["seven", 7], ["eight", 8], ["nine", 9], ["ten", 10],
]);

type Selector =
  | { kind: "positive" }
  | { kind: "negative" }
  | { kind: "smallest" }
  | { kind: "smallest_positive" }
  | { kind: "largest" }
  | { kind: "near"; at: number }
  /** "THE root of …", singular — one root is what was asked for, so finding one
   * and only one answers the question. "Solve …" and "the rootS" do not: those
   * promise a complete list, which needs a window known to hold every root. */
  | { kind: "unique" }
  | { kind: "all" };

export interface NumericRootQuery {
  /** `f` whose zero is wanted, as ascii. */
  fAscii: string;
  variable: string;
  digits: number;
  mode: "dp" | "sf";
  selector: Selector;
  interval: { lo: number; hi: number } | null;
  /** For the working. */
  equationLatex: string;
  /** True when `f` is a plain polynomial, which is what makes an exhaustive
   * search window possible. */
  polynomial: boolean;
}

// ---------------------------------------------------------------------------
// parsing
// ---------------------------------------------------------------------------

const PRECISION_RE = new RegExp(
  `\\b(?:to|correct\\s+to|accurate\\s+to|within)\\s+(\\d+|${[...WORD_DIGITS.keys()].join("|")})\\s*` +
    `(decimal\\s+places?|d\\.?\\s*p\\.?|significant\\s+figures?|significant\\s+digits?|s\\.?\\s*f\\.?)`,
  "i"
);

const METHOD_RE =
  /\bnewton\s*[-–—]?\s*raphson\b|\bnewton'?s?\s+method\b|\bbisection\b|\bnumerical(?:ly)?\b|\biteration\b/i;

/** `[0, 1]`, `in the interval [0,1]`, `between 0 and 1`. */
function parseIntervalClause(s: string): { lo: number; hi: number } | null {
  const bracket = /\[\s*([^,\]]+?)\s*,\s*([^,\]]+?)\s*\]/.exec(s);
  if (bracket) return finite(bracket[1], bracket[2]);
  const between = /\bbetween\s+(?:x\s*=\s*)?(-?[\d.]+(?:\\pi)?)\s+and\s+(?:x\s*=\s*)?(-?[\d.]+(?:\\pi)?)/i.exec(s);
  if (between) return finite(between[1], between[2]);
  return null;
}

function finite(a: string, b: string): { lo: number; hi: number } | null {
  let lo: number;
  let hi: number;
  try {
    lo = evalReal(latexToAscii(a).trim());
    hi = evalReal(latexToAscii(b).trim());
  } catch {
    return null;
  }
  if (!Number.isFinite(lo) || !Number.isFinite(hi) || lo >= hi) return null;
  return { lo, hi };
}

function parseSelector(s: string): Selector {
  const near = /\bnear(?:est)?\s+(?:to\s+)?(?:[a-zA-Z]\s*=\s*)?(-?\d+(?:\.\d+)?)/i.exec(s);
  if (near) return { kind: "near", at: Number(near[1]) };
  const small = /\bsmallest\b|\bleast\b|\bfirst\b|\blowest\b/i.test(s);
  const positive = /\bpositive\b/i.test(s);
  if (small && positive) return { kind: "smallest_positive" };
  if (positive) return { kind: "positive" };
  if (/\bnegative\b/i.test(s)) return { kind: "negative" };
  if (small) return { kind: "smallest" };
  if (/\blargest\b|\bgreatest\b|\bbiggest\b|\bhighest\b/i.test(s)) return { kind: "largest" };
  if (/\b(?:the|a|one)\s+(?:real\s+|approximate\s+)?(?:root|solution|zero)\b/i.test(s)) {
    return { kind: "unique" };
  }
  return { kind: "all" };
}

/**
 * The maths at the end of an English sentence.
 *
 * "Find the positive root of sin x = ½x" — read from the start, `positive` and
 * `root` are symbols and the equation has four unknowns in it. The maths begins
 * after the last word that introduces it.
 */
function mathTail(s: string): string {
  const lead = /\b(?:of|solve|equation|for|that|which|where|to)\b\s*:?\s*/gi;
  let cut = 0;
  for (let m = lead.exec(s); m; m = lead.exec(s)) {
    const after = s.slice(m.index + m[0].length);
    // Only a lead-in if maths actually follows it.
    if (/^[-+(\\\d[a-zA-Z]/.test(after.trim())) cut = m.index + m[0].length;
  }
  return s.slice(cut).trim();
}

/** Every free symbol, ignoring function names and the built-in constants. */
function symbolsOf(ascii: string): string[] {
  const out = new Set<string>();
  try {
    parse(ascii).traverse((node, path, parent) => {
      const n = node as unknown as { type: string; name?: string };
      if (n.type !== "SymbolNode" || !n.name) return;
      if (parent && (parent as unknown as { type: string }).type === "FunctionNode" && path === "fn") {
        return;
      }
      if (["e", "pi", "tau", "i"].includes(n.name)) return;
      out.add(n.name);
    });
  } catch {
    return [];
  }
  return [...out];
}

/** Whether the expression is a plain polynomial in `variable` — no function of
 * it, no variable denominator, no fractional power. That is what makes an
 * exhaustive search window possible. */
function isPolynomial(ascii: string, variable: string): boolean {
  let ok = true;
  try {
    parse(ascii).traverse((node) => {
      const s = node as unknown as { type: string; op?: string; args?: unknown[] };
      if (s.type === "FunctionNode") ok = false;
      if (s.type === "OperatorNode" && (s.op === "/" || s.op === "%")) {
        const den = s.args?.[1] as { traverse?: (f: (x: unknown) => void) => void } | undefined;
        den?.traverse?.((d) => {
          const t = d as { type?: string; name?: string };
          if (t.type === "SymbolNode" && t.name === variable) ok = false;
        });
      }
      if (s.type === "OperatorNode" && s.op === "^") {
        const exp = s.args?.[1] as { type?: string; value?: unknown } | undefined;
        const p = Number(exp?.value);
        if (!Number.isInteger(p) || p < 0 || p > 30) ok = false;
      }
    });
  } catch {
    return false;
  }
  return ok;
}

export function parseNumericRoot(rawLatex: string): NumericRootQuery | null {
  const prose = unwrapProse(rawLatex);

  const prec = PRECISION_RE.exec(prose);
  const method = METHOD_RE.test(prose);
  // Without one of these the question is not asking for digits, and the exact
  // engines own it. This gate is the whole reason this route is safe to put
  // ahead of them.
  if (!prec && !method) return null;
  // And it has to be a root question at all.
  if (!/\broots?\b|\bzeroe?s?\b|\bsolutions?\b|\bsolve\b/i.test(prose)) return null;

  let digits = 6;
  let mode: "dp" | "sf" = "dp";
  if (prec) {
    digits = WORD_DIGITS.get(prec[1].toLowerCase()) ?? parseInt(prec[1], 10);
    mode = /s\.?\s*f|significant/i.test(prec[2]) ? "sf" : "dp";
  }
  if (!Number.isInteger(digits) || digits < 1 || digits > 12) return null;

  const interval = parseIntervalClause(prose);
  const selector = parseSelector(prose);

  // Strip the clauses that are ABOUT the answer, so what is left is the equation.
  let body = prose;
  if (prec) body = body.replace(PRECISION_RE, " ");
  body = body
    .replace(METHOD_RE, " ")
    .replace(/\bin\s*(?:the\s+)?(?:interval|range)?\s*\[[^\]]*\]/gi, " ")
    .replace(/\bbetween\s+(?:x\s*=\s*)?-?[\d.]+\s+and\s+(?:x\s*=\s*)?-?[\d.]+/gi, " ")
    .replace(/\bnear(?:est)?\s+(?:to\s+)?(?:[a-zA-Z]\s*=\s*)?-?\d+(?:\.\d+)?/gi, " ")
    .replace(/\b(?:positive|negative|smallest|largest|greatest|least|first|lowest|highest|real|approximate|approximately)\b/gi, " ")
    .replace(/\b(?:find|calculate|determine|obtain|compute|use|the|a|an|method|value|of\s+the\s+roots?|roots?|zeroe?s?|solutions?)\b(?=\s|$)/gi, " ")
    .trim();

  const tail = mathTail(body);
  if (!tail) return null;

  // `A = B` becomes `A − B`; a bare expression is already `f`.
  const eq = tail.split("=");
  if (eq.length > 2) return null;
  const lhsAscii = latexToAscii(eq[0]).trim();
  const rhsAscii = eq.length === 2 ? latexToAscii(eq[1]).trim() : "";
  if (!lhsAscii) return null;
  const fAscii = eq.length === 2 && rhsAscii ? `(${lhsAscii}) - (${rhsAscii})` : lhsAscii;

  const vars = symbolsOf(fAscii);
  if (vars.length !== 1) return null;
  const variable = vars[0];
  // A constant expression has no root to find; `f` must actually move.
  try {
    if (evalReal(fAscii, { [variable]: 0.3 }) === evalReal(fAscii, { [variable]: 1.7 })) return null;
  } catch {
    return null;
  }

  return {
    fAscii,
    variable,
    digits,
    mode,
    selector,
    interval,
    equationLatex: tail,
    polynomial: isPolynomial(fAscii, variable),
  };
}

// ---------------------------------------------------------------------------
// the answer: bisection, which knows only the sign of f
// ---------------------------------------------------------------------------

function bisect(f: (x: number) => number, a: number, b: number): number | null {
  let lo = a;
  let hi = b;
  let flo = f(lo);
  let fhi = f(hi);
  if (!Number.isFinite(flo) || !Number.isFinite(fhi)) return null;
  if (flo === 0) return lo;
  if (fhi === 0) return hi;
  if (flo * fhi > 0) return null;
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (mid === lo || mid === hi) break;
    const fm = f(mid);
    if (!Number.isFinite(fm)) return null;
    if (fm === 0) return mid;
    if (flo * fm < 0) {
      hi = mid;
      fhi = fm;
    } else {
      lo = mid;
      flo = fm;
    }
  }
  return (lo + hi) / 2;
}

/** Cauchy's bound: every real root of the interpolated polynomial lies inside
 * it, which is what lets an unqualified "solve to 4 d.p." answer with ALL of
 * them instead of whichever ones a guessed window happened to contain. */
function polynomialWindow(f: (x: number) => number): { lo: number; hi: number } | null {
  const DEG = 12;
  const xs = Array.from({ length: DEG + 1 }, (_, i) => i - DEG / 2);
  const ys = xs.map(f);
  if (!ys.every(Number.isFinite)) return null;
  const coeffs = lagrange(xs, ys);
  if (!coeffs) return null;
  // The interpolation is only the polynomial if it agrees away from its nodes.
  for (const x of [0.37, -1.83, 7.4]) {
    const y = f(x);
    const model = coeffs.reduce((s, c, k) => s + c * x ** k, 0);
    if (!Number.isFinite(y) || Math.abs(y - model) > 1e-6 * Math.max(1, Math.abs(y))) return null;
  }
  let top = coeffs.length - 1;
  while (top > 0 && Math.abs(coeffs[top]) < 1e-9) top--;
  if (top === 0) return null;
  const lead = Math.abs(coeffs[top]);
  let worst = 0;
  for (let k = 0; k < top; k++) worst = Math.max(worst, Math.abs(coeffs[k]) / lead);
  const r = 1 + worst;
  if (!Number.isFinite(r) || r > 1e6) return null;
  return { lo: -r, hi: r };
}

function lagrange(xs: number[], ys: number[]): number[] | null {
  const n = xs.length;
  const out = new Array<number>(n).fill(0);
  for (let i = 0; i < n; i++) {
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

/** Every sign change in the window, refined. */
function allRoots(
  f: (x: number) => number,
  lo: number,
  hi: number
): { root: number; bracket: [number, number] }[] {
  const N = 20000;
  const h = (hi - lo) / N;
  const out: { root: number; bracket: [number, number] }[] = [];
  let prevX = lo;
  let prevY = f(lo);
  for (let i = 1; i <= N; i++) {
    const x = lo + i * h;
    const y = f(x);
    if (Number.isFinite(prevY) && Number.isFinite(y)) {
      if (prevY === 0) out.push({ root: prevX, bracket: [prevX, x] });
      else if (prevY * y < 0) {
        const r = bisect(f, prevX, x);
        if (r !== null) out.push({ root: r, bracket: [prevX, x] });
      }
    }
    prevX = x;
    prevY = y;
  }
  if (Number.isFinite(prevY) && prevY === 0) out.push({ root: prevX, bracket: [prevX - h, prevX] });
  // Two brackets can straddle one root when a sample lands on it.
  const dedup: typeof out = [];
  for (const r of out.sort((a, b) => a.root - b.root)) {
    if (!dedup.length || Math.abs(r.root - dedup[dedup.length - 1].root) > 1e-8) dedup.push(r);
  }
  return dedup;
}

// ---------------------------------------------------------------------------
// the gate: Newton–Raphson, which knows only the tangent
// ---------------------------------------------------------------------------

function newton(
  f: (x: number) => number,
  df: ((x: number) => number) | null,
  start: number
): number | null {
  let x = start;
  let prev = start + 1e-3;
  for (let i = 0; i < 200; i++) {
    const fx = f(x);
    if (!Number.isFinite(fx)) return null;
    if (fx === 0) return x;
    let slope: number;
    if (df) {
      slope = df(x);
    } else {
      // No symbolic derivative — the secant still shares no step with bisection.
      const fp = f(prev);
      if (!Number.isFinite(fp) || prev === x) return null;
      slope = (fx - fp) / (x - prev);
    }
    if (!Number.isFinite(slope) || slope === 0) return null;
    const next = x - fx / slope;
    if (!Number.isFinite(next)) return null;
    if (Math.abs(next - x) < 1e-15 * Math.max(1, Math.abs(next))) return next;
    prev = x;
    x = next;
  }
  return Number.isFinite(x) ? x : null;
}

/**
 * The N-place spelling of a number, but only when there IS one.
 *
 * A root that sits on the rounding boundary — 1.23450000 asked to 4 d.p. —
 * rounds two ways depending on a digit past the precision the search itself
 * has. Returning either would be asserting something not known.
 */
function roundSafely(v: number, digits: number, mode: "dp" | "sf"): string | null {
  if (mode === "sf") {
    if (v === 0) return "0";
    const mag = Math.floor(Math.log10(Math.abs(v)));
    const dp = digits - 1 - mag;
    if (dp < 0 || dp > 15) return null;
    return roundSafely(v, dp, "dp");
  }
  const scale = 10 ** digits;
  const scaled = v * scale;
  const frac = Math.abs(scaled - Math.trunc(scaled));
  if (Math.abs(frac - 0.5) < 1e-7) return null; // on the boundary
  return v.toFixed(digits);
}

function step(latex: string, code: string): RawStep {
  return { ascii: latex, operationCode: code, latex };
}

export function solveNumericRoot(cls: { numericRoot?: NumericRootQuery }): SolveCandidate | null {
  const q = cls.numericRoot;
  if (!q) return null;

  const f = (x: number): number => {
    try {
      return evalReal(q.fAscii, { [q.variable]: x });
    } catch {
      return NaN;
    }
  };
  let df: ((x: number) => number) | null = null;
  try {
    const d = derivative(q.fAscii, q.variable).toString();
    df = (x: number) => {
      try {
        return evalReal(d, { [q.variable]: x });
      } catch {
        return NaN;
      }
    };
  } catch {
    df = null;
  }

  // The window. A polynomial gets an exhaustive one; anything else only gets a
  // window it was given, or a default that is only trustworthy once a selector
  // has narrowed the question to a single root.
  let window = q.interval;
  if (!window && q.polynomial) window = polynomialWindow(f);
  if (!window) {
    // "Solve … to 4 d.p." promises every root, and outside a polynomial's
    // Cauchy bound there is no window that can promise that.
    if (q.selector.kind === "all") return null;
    window = q.selector.kind === "near" ? { lo: q.selector.at - 20, hi: q.selector.at + 20 } : { lo: -40, hi: 40 };
  }

  const found = allRoots(f, window.lo, window.hi);
  if (!found.length) return null;

  // Narrow to what was actually asked for.
  let picked: { root: number; bracket: [number, number] }[];
  switch (q.selector.kind) {
    case "positive": {
      const pos = found.filter((r) => r.root > 1e-9);
      if (pos.length !== 1) return null; // "the positive root" of something with two is ambiguous
      picked = pos;
      break;
    }
    case "negative": {
      const neg = found.filter((r) => r.root < -1e-9);
      if (neg.length !== 1) return null;
      picked = neg;
      break;
    }
    case "smallest_positive": {
      const pos = found.filter((r) => r.root > 1e-9);
      if (!pos.length) return null;
      picked = [pos[0]];
      break;
    }
    case "smallest":
      picked = [found[0]];
      break;
    case "largest":
      picked = [found[found.length - 1]];
      break;
    case "near": {
      const at = q.selector.at;
      picked = [[...found].sort((a, b) => Math.abs(a.root - at) - Math.abs(b.root - at))[0]];
      break;
    }
    case "unique":
      // One root was asked for. If the search turned up several, the question
      // did not name which — so nothing is returned rather than the first one.
      if (found.length !== 1) return null;
      picked = found;
      break;
    default:
      // Every root, which is only an honest answer when the window was
      // exhaustive: an explicit interval, or a polynomial's Cauchy bound.
      if (!q.interval && !q.polynomial) return null;
      picked = found;
      break;
  }
  if (!picked.length || picked.length > 6) return null;

  const spelled: string[] = [];
  for (const { root, bracket } of picked) {
    // The gate. Newton starts from the END of the bracket, not from the answer,
    // so it walks its own path there.
    const start = Math.abs(bracket[0] - root) > Math.abs(bracket[1] - root) ? bracket[0] : bracket[1];
    const check = newton(f, df, start);
    if (check === null) return null;
    if (Math.abs(check - root) > 1e-9 * Math.max(1, Math.abs(root))) return null;
    // And `f` really is zero there.
    const fr = f(root);
    if (!Number.isFinite(fr) || Math.abs(fr) > 1e-7) return null;

    const text = roundSafely(root, q.digits, q.mode);
    if (text === null) return null;
    spelled.push(text);
  }

  const plain =
    spelled.length === 1
      ? `${q.variable} = ${spelled[0]}`
      : spelled.map((s) => `${q.variable} = ${s}`).join(" or ");
  const answer: FinalAnswer = { latex: plain, plain };

  const unit = q.mode === "dp" ? "decimal places" : "significant figures";
  const steps: RawStep[] = [
    step(`f(${q.variable}) = ${q.fAscii}`, "SET_UP"),
    step(
      `\\text{sign change on } [${fmt(picked[0].bracket[0])}, ${fmt(picked[0].bracket[1])}]`,
      "BRACKET"
    ),
    step(
      df ? `f'(${q.variable}) = ${derivative(q.fAscii, q.variable).toString()}` : "\\text{secant iteration}",
      "DIFFERENTIATE"
    ),
    step(`${plain} \\text{ (to ${q.digits} ${unit})}`, "RESULT"),
  ];

  return {
    answer,
    methods: [
      { id: "numeric_root", name: "Numerical root (bisection + Newton–Raphson)", examPick: true, steps },
    ],
    plotExpression: q.fAscii,
    verify: () => true,
  };
}

function fmt(v: number): string {
  return String(Math.round(v * 1e6) / 1e6);
}
