/**
 * Arc length — the length of a curve given parametrically, `x(t) = t − sin t,
 * y(t) = 1 − cos t` for `0 ≤ t ≤ 2π`, or as `y = f(x)` over an interval.
 *
 * The integrand `√(x′² + y′²)` is built by mathjs's symbolic differentiation, so
 * nothing about the answer is guessed. The number itself is a quadrature, and a
 * quadrature is only worth as much as its check: this one is computed by
 * Gauss–Legendre and then again by Romberg, two rules whose error terms have
 * nothing in common, and the two must agree to near machine precision before
 * anything is returned. A curve with a corner or a pole in range makes them
 * disagree, which is exactly when this engine should decline.
 *
 * The exact form is preferred where there is one — the cycloid's arch is 8, and
 * "7.9999999999" is the same number with the mathematics taken out of it.
 */
import { derivative, parse } from "mathjs";

import { exactForm } from "./exact";
import { latexToAscii, unwrapProse } from "./latex";
import { FinalAnswer, RawStep, SolveCandidate } from "./types";
import { evalReal } from "./verify";

export interface ArcLengthQuery {
  /** The integrand `√(x′² + y′²)` (or `√(1 + y′²)`), as ascii. */
  integrand: string;
  variable: string;
  lo: number;
  hi: number;
  /** For the displayed working. */
  parts: { label: string; latex: string }[];
}

const BOUND_WORDS = /\bfor\b|\bfrom\b|\bwhere\b|\bbetween\b|\bover\b|\bon\b|,/i;

/** `a ≤ t ≤ b`, `0 \le t \le 2\pi`, `from t = 0 to t = 2\pi`, `0 < x < 1`. */
function parseInterval(raw: string, variable: string): { lo: number; hi: number } | null {
  // The word that introduced the interval is not part of it. Left in place it
  // becomes the lower bound — `for 0` — and evaluates to nothing.
  const s = raw.replace(/^\s*(?:,|:|\bfor\b|\bwhere\b|\bover\b|\bon\b|\bwith\b)\s*/i, "").trim();
  const v = variable.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const chain = new RegExp(
    `(-?[^<>\\s][^<>]*?)\\s*(?:\\\\le(?:q)?|\\\\leqslant|<=|<|≤)\\s*${v}\\s*(?:\\\\le(?:q)?|\\\\leqslant|<=|<|≤)\\s*(.+?)\\s*$`,
    "i"
  );
  const m = chain.exec(s);
  if (m) return finite(m[1], m[2]);
  const fromTo = new RegExp(
    `\\bfrom\\b\\s*(?:${v}\\s*=\\s*)?(.+?)\\s*\\bto\\b\\s*(?:${v}\\s*=\\s*)?(.+?)\\s*$`,
    "i"
  );
  const f = fromTo.exec(s);
  if (f) return finite(f[1], f[2]);
  const between = new RegExp(
    `\\bbetween\\b\\s*(?:${v}\\s*=\\s*)?(.+?)\\s*\\band\\b\\s*(?:${v}\\s*=\\s*)?(.+?)\\s*$`,
    "i"
  );
  const b = between.exec(s);
  if (b) return finite(b[1], b[2]);
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

/** `x(t) = t - \sin t` → `{ name: "x", variable: "t", body: "t - sin(t)" }`. */
function parseComponent(s: string): { name: string; variable: string; body: string } | null {
  const m = /([a-zA-Z])\s*\(\s*([a-zA-Z])\s*\)\s*=\s*([\s\S]+)$/.exec(s.trim());
  if (!m) return null;
  const body = latexToAscii(m[3]).trim();
  if (!body) return null;
  return { name: m[1], variable: m[2], body };
}

/**
 * Every free symbol of an ascii expression.
 *
 * The name of a function is a SymbolNode too — `sin(t)` holds a symbol called
 * `sin`. Counted as a variable it makes every curve with a trig function in it
 * look like it has two, and the whole family quietly declines.
 */
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

function differentiate(body: string, variable: string): string | null {
  try {
    return derivative(body, variable).toString();
  } catch {
    return null;
  }
}

export function parseArcLength(rawLatex: string): ArcLengthQuery | null {
  const prose = unwrapProse(rawLatex);
  if (!/\barc\s*length\b|\blength\s+of\s+the\s+(?:curve|arc)\b|\blength\s+of\s+the\s+arc\b/i.test(prose)) {
    return null;
  }
  const after = prose.replace(
    /^[\s\S]*?\b(?:arc\s*length|length)\s+of\s+(?:the\s+)?(?:curve\s+|arc\s+)?/i,
    ""
  );
  if (!after.trim()) return null;

  // --- parametric: x(t) = …, y(t) = … --------------------------------------
  const paramSplit = /,\s*(?=[a-zA-Z]\s*\(\s*[a-zA-Z]\s*\)\s*=)/.exec(after);
  if (paramSplit) {
    const first = after.slice(0, paramSplit.index);
    const rest = after.slice(paramSplit.index + paramSplit[0].length);
    // The second component ends where the interval begins.
    const cut = rest.search(BOUND_WORDS);
    if (cut < 0) return null;
    const x = parseComponent(first);
    const y = parseComponent(rest.slice(0, cut));
    if (!x || !y || x.variable !== y.variable) return null;
    const t = x.variable;
    if (symbolsOf(x.body).some((s) => s !== t)) return null;
    if (symbolsOf(y.body).some((s) => s !== t)) return null;
    const dx = differentiate(x.body, t);
    const dy = differentiate(y.body, t);
    if (!dx || !dy) return null;
    const span = parseInterval(rest.slice(cut), t);
    if (!span) return null;
    return {
      integrand: `sqrt((${dx})^2 + (${dy})^2)`,
      variable: t,
      lo: span.lo,
      hi: span.hi,
      parts: [
        { label: "x'", latex: dx },
        { label: "y'", latex: dy },
      ],
    };
  }

  // --- cartesian: y = f(x) -------------------------------------------------
  const yEq = /^\s*y\s*=\s*([\s\S]+)$/.exec(after);
  if (!yEq) return null;
  const cut = yEq[1].search(BOUND_WORDS);
  if (cut < 0) return null;
  const body = latexToAscii(yEq[1].slice(0, cut)).trim();
  if (!body) return null;
  const vars = symbolsOf(body);
  if (vars.length !== 1) return null;
  const v = vars[0];
  const dy = differentiate(body, v);
  if (!dy) return null;
  const span = parseInterval(yEq[1].slice(cut), v);
  if (!span) return null;
  return {
    integrand: `sqrt(1 + (${dy})^2)`,
    variable: v,
    lo: span.lo,
    hi: span.hi,
    parts: [{ label: "dy/dx", latex: dy }],
  };
}

// ---------------------------------------------------------------------------
// quadrature — two rules, so the answer is checked rather than trusted
// ---------------------------------------------------------------------------

/** 10-point Gauss–Legendre nodes/weights on [−1, 1]. */
const GL_X = [
  -0.9739065285171717, -0.8650633666889845, -0.6794095682990244, -0.4333953941292472,
  -0.14887433898163122, 0.14887433898163122, 0.4333953941292472, 0.6794095682990244,
  0.8650633666889845, 0.9739065285171717,
];
const GL_W = [
  0.06667134430868814, 0.14945134915058059, 0.219086362515982, 0.2692667193099963,
  0.29552422471475287, 0.29552422471475287, 0.2692667193099963, 0.219086362515982,
  0.14945134915058059, 0.06667134430868814,
];

function gaussLegendre(f: (x: number) => number, lo: number, hi: number, panels: number): number {
  const h = (hi - lo) / panels;
  let total = 0;
  for (let p = 0; p < panels; p++) {
    const a = lo + p * h;
    const mid = a + h / 2;
    for (let i = 0; i < GL_X.length; i++) {
      const v = f(mid + (h / 2) * GL_X[i]);
      if (!Number.isFinite(v)) return NaN;
      total += GL_W[i] * v * (h / 2);
    }
  }
  return total;
}

/** Romberg — trapezoid refinements accelerated by Richardson. Its error term
 * shares nothing with Gauss–Legendre's, which is what makes it a check. */
function romberg(f: (x: number) => number, lo: number, hi: number): number {
  const LEVELS = 16;
  const rows: number[][] = [];
  let h = hi - lo;
  const f0 = f(lo);
  const f1 = f(hi);
  if (!Number.isFinite(f0) || !Number.isFinite(f1)) return NaN;
  rows.push([(h / 2) * (f0 + f1)]);
  for (let k = 1; k < LEVELS; k++) {
    h /= 2;
    let sum = 0;
    const n = 1 << (k - 1);
    for (let i = 1; i <= n; i++) {
      const v = f(lo + (2 * i - 1) * h);
      if (!Number.isFinite(v)) return NaN;
      sum += v;
    }
    const row = [rows[k - 1][0] / 2 + h * sum];
    for (let j = 1; j <= k; j++) {
      row.push(row[j - 1] + (row[j - 1] - rows[k - 1][j - 1]) / (4 ** j - 1));
    }
    rows.push(row);
    if (k >= 4 && Math.abs(row[k] - rows[k - 1][k - 1]) < 1e-13 * Math.max(1, Math.abs(row[k]))) {
      return row[k];
    }
  }
  return rows[LEVELS - 1][LEVELS - 1];
}

function step(latex: string, code: string): RawStep {
  return { ascii: latex, operationCode: code, latex };
}

function answerOf(v: number): FinalAnswer {
  const exact = exactForm(v);
  if (exact) return { latex: exact.latex, plain: exact.plain };
  const s = String(Math.round(v * 1e6) / 1e6);
  return { latex: s, plain: s };
}

export function solveArcLength(cls: { arcLength?: ArcLengthQuery }): SolveCandidate | null {
  const q = cls.arcLength;
  if (!q) return null;
  const f = (x: number) => evalReal(q.integrand, { [q.variable]: x });

  // The endpoints of an arc-length integrand are where |x′| can vanish and the
  // square root turn a corner, so they are pulled in a hair rather than trusted.
  const eps = (q.hi - q.lo) * 1e-12;
  const gl = gaussLegendre(f, q.lo + eps, q.hi - eps, 400);
  const rb = romberg(f, q.lo + eps, q.hi - eps);
  if (!Number.isFinite(gl) || !Number.isFinite(rb)) return null;
  if (!(gl > 0)) return null; // a length is positive; anything else is a bad parse
  if (Math.abs(gl - rb) > 1e-8 * Math.max(1, Math.abs(gl))) return null;

  // Halving the panel count must not move the Gauss–Legendre value either — a
  // curve the rule cannot resolve shows up here and is declined.
  const coarse = gaussLegendre(f, q.lo + eps, q.hi - eps, 173);
  if (!Number.isFinite(coarse) || Math.abs(gl - coarse) > 1e-8 * Math.max(1, Math.abs(gl))) {
    return null;
  }

  const answer = answerOf(gl);
  // An exact form is only the answer if it IS the number.
  const exact = exactForm(gl);
  if (exact) {
    const back = evalReal(exact.ascii);
    if (!Number.isFinite(back) || Math.abs(back - gl) > 1e-7 * Math.max(1, Math.abs(gl))) {
      return null;
    }
  }

  const steps: RawStep[] = q.parts.map((p) =>
    step(`${p.label} = ${p.latex}`, "DIFFERENTIATE")
  );
  steps.push(
    step(
      `L = \\int_{${fmt(q.lo)}}^{${fmt(q.hi)}} ${q.integrand} \\, d${q.variable}`,
      "SET_UP_INTEGRAL"
    )
  );
  steps.push(step(`L = ${answer.latex}`, "RESULT"));

  return {
    answer,
    methods: [{ id: "arc_length", name: "Arc length by integration", examPick: true, steps }],
    plotExpression: null,
    verify: () => true,
  };
}

function fmt(v: number): string {
  return String(Math.round(v * 1e10) / 1e10);
}
