/**
 * Taylor / Maclaurin series — a DETERMINISTIC path (Phase C).
 *
 * mathjs differentiates f repeatedly; we evaluate each derivative at the center a
 * to build the coefficients c_k = f^(k)(a) / k!. The result is then proven by an
 * INDEPENDENT contact-order test (numeric, never re-using the symbolic
 * derivatives that built it):
 *
 *   The order-n Taylor polynomial is the UNIQUE degree-≤n polynomial whose error
 *   f(x) − T(x) is O((x−a)^{n+1}). So the scaled residual |f−T| / δ^n must → 0 as
 *   δ shrinks. A wrong coefficient c_k (k ≤ n) leaves a (x−a)^k term in the error:
 *     • k < n  → the scaled residual GROWS as δ→0  (δ^{k−n} → ∞)
 *     • k = n  → it tends to a nonzero constant (doesn't decay)
 *   so no wrong coefficient can pass, while a correct series always decays like δ
 *   — even when some terms vanish (e.g. cos has no odd terms). c_0 = f(a) is also
 *   checked directly.
 *
 * Scope: single-variable real functions, center 0 (Maclaurin) or a numeric / π
 * center, order 1..6. Anything else declines honestly (couldn't-verify).
 */
import { derivative, parse } from "mathjs";

import { asciiToLatex, latexToAscii, variablesIn } from "./latex";
import { FinalAnswer, RawStep, SolveCandidate } from "./types";
import { evalReal } from "./verify";

const FACT = [1, 1, 2, 6, 24, 120, 720]; // 0!..6!
const MAX_ORDER = 6;
/** Constants mathjs recognizes — never treated as the expansion variable. */
const CONSTS = new Set(["e", "pi"]);

export interface TaylorQuery {
  fn: string; // the function, as ascii-math
  variable: string;
  center: number;
  centerLatex: string;
  order: number;
}

/** A named center token → { numeric value, LaTeX display }. */
const CENTERS: Record<string, { value: number; latex: string }> = {
  "0": { value: 0, latex: "0" },
  origin: { value: 0, latex: "0" },
  pi: { value: Math.PI, latex: "\\pi" },
  "\\pi": { value: Math.PI, latex: "\\pi" },
  "π": { value: Math.PI, latex: "\\pi" },
};

/** Parse a Taylor/Maclaurin request → { fn, variable, center, order } or null. */
export function parseTaylor(rawLatex: string): TaylorQuery | null {
  const lower = rawLatex.toLowerCase();
  const isMaclaurin = /maclaurin/.test(lower);
  if (!isMaclaurin && !/taylor/.test(lower)) return null;

  // --- order: "order 4" / "degree 4" / "4th order" / "5 terms" (→ degree 4) ---
  const om =
    lower.match(/(?:order|degree)\s*(\d+)/) ||
    lower.match(/(\d+)\s*(?:st|nd|rd|th)?[-\s]*(?:order|degree)/) ||
    lower.match(/(?:first\s+)?(\d+)\s*terms?/);
  if (!om) return null;
  let order = parseInt(om[1], 10);
  if (/terms?/.test(om[0])) order -= 1; // "n terms" → degree n−1
  if (!Number.isInteger(order) || order < 1 || order > MAX_ORDER) return null;

  // --- center: Maclaurin ⇒ 0; else "around/about/at [x=] value" -----------
  let center = 0;
  let centerLatex = "0";
  if (!isMaclaurin) {
    const cm = rawLatex.match(
      /(?:around|about|centered\s+at|center(?:ed)?(?:\s+at)?|at)\s+(?:[a-zA-Z]\s*=\s*)?(\\pi|π|pi|origin|-?\d+(?:\.\d+)?)/i
    );
    if (cm) {
      const tok = cm[1];
      const known = CENTERS[tok] ?? CENTERS[tok.toLowerCase()];
      if (known) {
        center = known.value;
        centerLatex = known.latex;
      } else {
        const v = Number(tok);
        if (!Number.isFinite(v)) return null;
        center = v;
        centerLatex = String(Math.abs(v)); // sign handled at display time
      }
    }
    // No explicit center on a "Taylor series" ⇒ treat as Maclaurin (center 0).
  }

  // --- function ------------------------------------------------------------
  const fn = extractFunction(rawLatex);
  if (!fn) return null;
  const vars = variablesIn(fn).filter((v) => !CONSTS.has(v));
  if (vars.length > 1) return null; // single-variable only
  const variable = vars.includes("x") ? "x" : vars[0] ?? "x";
  // f must be a finite real at the center, or there's nothing to expand.
  if (!Number.isFinite(evalReal(fn, { [variable]: center }))) return null;

  return { fn, variable, center, centerLatex, order };
}

/**
 * Pull the function expression out of the prose, as ascii-math, or null. The
 * function follows "of" or "for" (or "f(x) ="), but so can a qualifier
 * ("polynomial OF degree 2 FOR sqrt(x)"), so we try every such tail and take the
 * first that trims to a real, variable-bearing expression.
 */
function extractFunction(rawLatex: string): string | null {
  const tails: string[] = [];
  const eq = rawLatex.match(/f\s*\(\s*[a-zA-Z]\s*\)\s*=\s*(.+)/);
  if (eq) tails.push(eq[1]); // "f(x) = <expr>" is the strongest signal
  // Each "of"/"for" position independently — a greedy `(.+)` on the first "of"
  // would swallow a later "for <fn>", so take the substring after each keyword.
  for (const m of rawLatex.matchAll(/\b(?:of|for)\b/gi)) {
    tails.push(rawLatex.slice((m.index ?? 0) + m[0].length));
  }

  for (const raw of tails) {
    // Cut at the first center/order qualifier so only the function remains.
    const cut = raw
      .split(
        /,|\b(?:first|around|about|centered|center|at|to\s+order|up\s+to|order|degree|terms?)\b/i
      )[0]
      .replace(/[,.;:]+\s*$/, "")
      .trim();
    if (!cut) continue;
    const ascii = latexToAscii(cut).trim();
    if (!ascii || !/[a-zA-Z]/.test(ascii)) continue; // must carry a var / function
    try {
      parse(ascii); // must be a real, parseable expression
    } catch {
      continue;
    }
    return ascii;
  }
  return null;
}

/** Solve a Taylor/Maclaurin request, gated by the contact-order verifier. */
export function solveTaylor(cls: {
  taylorFn?: string;
  unknown?: string;
  taylorCenter?: number;
  taylorCenterLatex?: string;
  taylorOrder?: number;
}): SolveCandidate | null {
  const fn = cls.taylorFn;
  const variable = cls.unknown ?? "x";
  const center = cls.taylorCenter;
  const order = cls.taylorOrder;
  const centerLatex = cls.taylorCenterLatex ?? String(center);
  if (!fn || center === undefined || order === undefined) return null;
  if (order < 1 || order > MAX_ORDER) return null;

  // Coefficients c_k = f^(k)(center) / k! via mathjs repeated differentiation.
  const coeffs: number[] = [];
  try {
    let node = parse(fn);
    for (let k = 0; k <= order; k++) {
      if (k > 0) node = derivative(node, variable);
      const val = node.evaluate({ [variable]: center });
      if (typeof val !== "number" || !Number.isFinite(val)) return null;
      coeffs.push(val / FACT[k]);
    }
  } catch {
    return null;
  }

  const verify = (): boolean =>
    verifyTaylor(fn, variable, center, order, coeffs);
  if (!verify()) return null; // never return an unverified candidate

  const answer = buildAnswer(coeffs, variable, center, centerLatex);
  const name = center === 0 ? "Maclaurin series" : "Taylor series";
  const steps: RawStep[] = [
    {
      ascii: `f(${variable}) = ${fn}`,
      operationCode: "START",
      latex: `f(${variable}) = ${asciiToLatex(fn)}`,
    },
    { ascii: answer.plain, operationCode: "RESULT", latex: answer.latex },
  ];
  return {
    answer,
    methods: [{ id: "taylor", name, examPick: true, steps }],
    plotExpression: null,
    verify,
  };
}

/**
 * Independent contact-order verification (see the module header). Returns true
 * only if the scaled residual |f−T|/δ^n decays like a correct order-n series.
 */
export function verifyTaylor(
  fn: string,
  variable: string,
  center: number,
  order: number,
  coeffs: number[]
): boolean {
  const f = (x: number): number => evalReal(fn, { [variable]: x });
  const T = (x: number): number =>
    coeffs.reduce((s, c, k) => s + c * Math.pow(x - center, k), 0);

  // c_0 must be f(a) exactly.
  const f0 = f(center);
  if (!Number.isFinite(f0)) return false;
  if (Math.abs(f0 - coeffs[0]) > 1e-6 * Math.max(1, Math.abs(f0)) + 1e-9) {
    return false;
  }

  // Scaled residual at shrinking offsets (both sides; use whichever is defined).
  const deltas = [0.2, 0.1, 0.05];
  const g: number[] = [];
  for (const d of deltas) {
    let best = -1;
    for (const x of [center + d, center - d]) {
      const r = f(x) - T(x);
      if (Number.isFinite(r)) best = Math.max(best, Math.abs(r) / Math.pow(d, order));
    }
    if (best < 0) return false; // f undefined on both sides at this offset
    g.push(best);
  }

  const tiny = 1e-7;
  // f is exactly a polynomial of degree ≤ order → residual is ~0 everywhere.
  if (g.every((v) => v < tiny)) return true;
  // Otherwise the scaled residual must shrink geometrically (≈ ½ per halving);
  // 0.75 leaves generous headroom for higher-order corrections. A wrong
  // coefficient makes g flat (k=n) or growing (k<n), so it can't clear this.
  return g[1] <= g[0] * 0.75 + tiny && g[2] <= g[1] * 0.75 + tiny;
}

// ---- display ---------------------------------------------------------------

/** Build the polynomial answer (LaTeX + plain), skipping zero terms. */
function buildAnswer(
  coeffs: number[],
  variable: string,
  center: number,
  centerLatex: string
): FinalAnswer {
  const absC = centerLatex.replace(/^-/, "");
  const baseLatex =
    center === 0 ? variable : `\\left(${variable} ${center < 0 ? "+" : "-"} ${absC}\\right)`;
  const basePlain =
    center === 0 ? variable : `(${variable} ${center < 0 ? "+" : "-"} ${absC})`;

  let latex = "";
  let plain = "";
  for (let k = 0; k < coeffs.length; k++) {
    const c = coeffs[k];
    if (Math.abs(c) < 1e-12) continue;
    const neg = c < 0;
    const mag = Math.abs(c);
    const first = latex === "";

    latex += first ? (neg ? "-" : "") : neg ? " - " : " + ";
    plain += first ? (neg ? "-" : "") : neg ? " - " : " + ";
    latex += termLatex(mag, k, baseLatex);
    plain += termPlain(mag, k, basePlain);
  }
  if (latex === "") return { latex: "0", plain: "0" };
  return { latex, plain };
}

function powLatex(k: number, base: string): string {
  if (k === 0) return "";
  if (k === 1) return base;
  return `${base}^{${k}}`;
}
function powPlain(k: number, base: string): string {
  if (k === 0) return "";
  if (k === 1) return base;
  return `${base}^${k}`;
}

function termLatex(mag: number, k: number, base: string): string {
  const fr = asFraction(mag);
  const p = powLatex(k, base);
  if (k === 0) return numLatex(mag, fr);
  // coefficient of 1 in front of a power is implicit
  if (fr && fr.d === 1 && fr.n === 1) return p;
  return numLatex(mag, fr) + p;
}
function termPlain(mag: number, k: number, base: string): string {
  const fr = asFraction(mag);
  const p = powPlain(k, base);
  if (k === 0) return numPlain(mag, fr);
  if (fr && fr.d === 1 && fr.n === 1) return p;
  const coeff = numPlain(mag, fr);
  return fr && fr.d !== 1 ? `(${coeff})${p}` : `${coeff}${p}`;
}

function numLatex(mag: number, fr: { n: number; d: number } | null): string {
  if (fr) return fr.d === 1 ? String(fr.n) : `\\frac{${fr.n}}{${fr.d}}`;
  return trimDecimal(mag);
}
function numPlain(mag: number, fr: { n: number; d: number } | null): string {
  if (fr) return fr.d === 1 ? String(fr.n) : `${fr.n}/${fr.d}`;
  return trimDecimal(mag);
}

/** A small-denominator rational for `x`, or null when it's irrational. */
function asFraction(x: number): { n: number; d: number } | null {
  for (let d = 1; d <= 5040; d++) {
    const n = x * d;
    if (Math.abs(n - Math.round(n)) < 1e-9) return { n: Math.round(n), d };
  }
  return null;
}

function trimDecimal(x: number): string {
  return String(Math.round(x * 1e6) / 1e6);
}
