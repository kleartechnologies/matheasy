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

import { asciiToLatex, latexToAscii, unwrapProse, variablesIn } from "./latex";
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

/** Parse a Taylor/Maclaurin request → { fn, variable, center, order } or null. */
/** Spelled-out counts, for "the four-term Taylor polynomial". */
const WORD_NUMBERS = new Map<string, number>([
  ["one", 1], ["two", 2], ["three", 3], ["four", 4], ["five", 5], ["six", 6],
  ["seven", 7], ["eight", 8], ["nine", 9], ["ten", 10], ["eleven", 11],
  ["twelve", 12],
]);

export function parseTaylor(rawLatex: string): TaylorQuery | null {
  // Read the prose and the math as ONE string. A scanned sheet arrives as
  // "\\text{Obtain the four-term Taylor polynomial near } x = 0 \\text{ for }
  // (1+x)^{1/2}", where the braces cut the sentence in three: the centre cue
  // captured a bare "}", `parseCenter` rejected it, and a question the engine
  // can answer exactly declined instead.
  rawLatex = unwrapProse(rawLatex);
  // The keyword must be a SERIES keyword — "taylor" alone is a common surname, so
  // require it adjacent to series/polynomial/expansion/approximation. "maclaurin"
  // is unambiguous. This stops a word problem ("Taylor drew a 5° angle…") from
  // being hijacked into a bogus series.
  const isMaclaurin = /\bmaclaurin\b/i.test(rawLatex);
  const isTaylor =
    /\btaylor'?s?\s+(?:series|polynomial|expansion|approximation)\b/i.test(rawLatex);
  if (!isMaclaurin && !isTaylor) return null;

  // --- order: "order 4" / "degree 4" / "4th order" / "5 terms" (→ degree 4) ---
  // A problem sheet spells the count as a WORD at least as often as a digit —
  // "obtain the four-term Taylor polynomial". Without the word forms that
  // question found no order and declined outright.
  //
  // Two DIFFERENT things get spelled here and the number means the opposite in
  // each: "5 terms" is a COUNT (degree 4), while "up to x^5" names the DEGREE
  // itself. The degree patterns are tried FIRST and are exempt from the −1 —
  // "…including the x^2 term" contains the word "term", so read as a count it
  // silently returned one degree short of the question that was asked.
  const orderRes: { re: RegExp; count: boolean }[] = [
    // "…about x = 0 UP TO x⁴" is how a problem sheet actually states the order,
    // and none of the count patterns sees it. Without these the whole family —
    // sec, tan, sin, e^x, all of them — found no order, declined, and fell
    // through to be read as a POLYNOMIAL EQUATION, which is not what was asked.
    {
      re: /(?:up\s+to|as\s+far\s+as|includ(?:ing|e))\s+(?:and\s+including\s+)?(?:the\s+)?(?:terms?\s+in\s+)?[a-zA-Z]\s*\^\s*\{?\s*(\d+)\s*\}?/i,
      count: false,
    },
    {
      re: /(?:terms?\s+)?(?:up\s+to|in)\s+(?:and\s+including\s+)?(?:the\s+)?[a-zA-Z]\s*\^\s*\{?\s*(\d+)\s*\}?\s*terms?/i,
      count: false,
    },
    { re: /(?:order|degree)\s*(\d+)/i, count: false },
    { re: /(\d+)\s*(?:st|nd|rd|th)?[-\s]*(?:order|degree)/i, count: false },
    { re: /(?:first\s+)?(\d+)\s*[-\s]*terms?/i, count: true },
    {
      re: new RegExp(`(?:first\\s+)?(${[...WORD_NUMBERS.keys()].join("|")})\\s*[-\\s]*terms?`, "i"),
      count: true,
    },
    {
      re: new RegExp(`(${[...WORD_NUMBERS.keys()].join("|")})[-\\s]*(?:order|degree)`, "i"),
      count: false,
    },
  ];
  let om: RegExpMatchArray | null = null;
  let isCount = false;
  for (const { re, count } of orderRes) {
    const m = rawLatex.match(re);
    if (m) {
      om = m;
      isCount = count;
      break;
    }
  }
  if (!om) return null;
  let order = WORD_NUMBERS.get(om[1].toLowerCase()) ?? parseInt(om[1], 10);
  if (isCount) order -= 1; // "n terms" → degree n−1
  if (!Number.isInteger(order) || order < 1 || order > MAX_ORDER) return null;

  // Blank out the order phrase so "at 3rd order" / "at 4 terms" can never be
  // misread as a center of 3 / 4.
  const idx = om.index ?? 0;
  const withoutOrder =
    rawLatex.slice(0, idx) + " ".repeat(om[0].length) + rawLatex.slice(idx + om[0].length);

  // --- center: Maclaurin ⇒ 0; else parse the WHOLE center expression ---------
  // No center cue ⇒ Maclaurin (center 0). A cue that's present but unparseable
  // (a symbolic center, a bad token) DECLINES — it must never silently fall back
  // to 0 and answer a different problem than was asked.
  let center = 0;
  let centerLatex = "0";
  if (!isMaclaurin) {
    // "NEAR x = 0" is the standard problem-sheet wording and it MUST be a centre
    // cue. While it wasn't, "near x = 1" matched no cue, silently fell back to
    // centre 0, and returned a confident expansion about the wrong point.
    const cm = withoutOrder.match(
      /(?:around|about|near|centered\s+(?:at|on)|center(?:ed)?(?:\s+(?:at|on))?|at)\s+(?:the\s+point\s+)?(?:[a-zA-Z]\s*=\s*)?([^\s,;]+(?:\s*[\/*]\s*[^\s,;]+)*)/i
    );
    if (cm) {
      const parsed = parseCenter(cm[1]);
      if (!parsed) return null; // center cue present but unparseable → decline
      center = parsed.value;
      centerLatex = parsed.latex;
    }
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
 * Evaluate a center expression (`\pi/6`, `1/2`, `2\pi/3`, `-3`, `\pi`) to a
 * numeric value + a LaTeX display, or null when it isn't a finite real — a bare
 * variable ("a") or garbage returns null so the caller DECLINES rather than
 * expanding about the wrong point.
 */
function parseCenter(raw: string): { value: number; latex: string } | null {
  // A centre written as a LaTeX fraction — "about x = \frac{\pi}{3}" — survives
  // none of the stripping below (`frac{pi}{3}` is not an expression), so try the
  // real converter first and keep the strip as the fallback it always was.
  const viaLatex = evalReal(latexToAscii(raw).replace(/\\pi/gi, "pi").replace(/π/g, "pi"));
  if (Number.isFinite(viaLatex)) return { value: viaLatex, latex: centerLatexOf(raw) };
  const norm = raw.trim().replace(/\\pi/gi, "pi").replace(/π/g, "pi").replace(/\\/g, "");
  const value = evalReal(norm);
  if (!Number.isFinite(value)) return null;
  return { value, latex: centerLatexOf(raw) };
}

/** A tidy LaTeX rendering of a center expression (fractions → \frac, π kept). */
function centerLatexOf(raw: string): string {
  // Already LaTeX — stripping backslashes would turn `\frac{\pi}{3}` into the
  // literal text "frac{\pi}{3}", which renders as the word "frac".
  if (/\\(?:frac|dfrac|tfrac|sqrt)\b/.test(raw)) return raw.trim().replace(/\s+/g, "");
  let s = raw.trim().replace(/\s+/g, "").replace(/\*/g, "");
  s = s.replace(/\\pi|π|pi/gi, "π").replace(/\\/g, "").replace(/π/g, "\\pi");
  const frac = s.match(/^(-?)(.+?)\/(.+)$/);
  if (frac) return `${frac[1]}\\frac{${frac[2]}}{${frac[3]}}`;
  return s;
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
  // "EXPAND √(1+x) as a Maclaurin series" names the function with no preposition
  // at all, so the verb has to be a keyword too.
  for (const m of rawLatex.matchAll(/\b(?:of|for|expand)\b/gi)) {
    tails.push(rawLatex.slice((m.index ?? 0) + m[0].length));
  }

  for (const raw of tails) {
    // Cut at the first center/order/series qualifier so only the function
    // remains. The SERIES vocabulary has to be here too: in "the first 4 terms
    // of the Maclaurin series for e^x" the tail after "of" is "the Maclaurin
    // series for e^x", and without a cut that whole phrase survived — see the
    // prose guard below for why that was worse than it looks.
    const cut = raw
      .split(
        /,|\b(?:first|around|about|near|centered|center|at|as|to\s+order|up\s+to|order|degree|terms?|with|where|valid|includ(?:ing|e)|maclaurin|taylor|series|polynomial|expansion|expand|approximation)\b/i
      )[0]
      .replace(/[,.;:]+\s*$/, "")
      // A leading determiner is English, not a product of three variables. Left
      // in, "the" survived every check below — `latexToAscii` reads it as t·h·e,
      // whose letters are all single-character and so look exactly like real
      // variables — and it was returned as the function to expand.
      .replace(/^\s*(?:the|a|an|its|this|that)\s+/i, "")
      .trim();
    if (!cut) continue;
    const ascii = latexToAscii(cut).trim();
    if (!ascii || !/[a-zA-Z]/.test(ascii)) continue; // must carry a var / function
    try {
      parse(ascii); // must be a real, parseable expression
    } catch {
      continue;
    }
    if (looksLikeProse(ascii)) continue;
    return ascii;
  }
  return null;
}

/**
 * True when an "expression" is really leftover English. mathjs parses adjacent
 * identifiers as implicit multiplication, so `parse()` ACCEPTS "the Maclaurin
 * series for e^x" as the product the·Maclaurin·series·for·eˣ — it never throws,
 * and the phrase sailed past the parse check above. Real math variables are
 * single letters (or a named Greek/constant), so a multi-letter symbol that
 * isn't one of those is a word, and the candidate must be rejected.
 */
function looksLikeProse(ascii: string): boolean {
  const named = new Set([
    ...CONSTS,
    "theta", "phi", "alpha", "beta", "gamma", "lambda", "mu", "nu", "omega",
    "sigma", "delta", "epsilon", "tau", "rho", "psi", "chi", "xi", "eta", "zeta",
    "infinity", "Inf",
  ]);
  return variablesIn(ascii).some((v) => v.length > 1 && !named.has(v));
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
  // The plain answer is read as text, not rendered — a `\frac{\pi}{3}` in it is
  // just noise where "π/3" is the thing a student would write.
  const absPlain = centerPlainOf(absC);
  const basePlain =
    center === 0 ? variable : `(${variable} ${center < 0 ? "+" : "-"} ${absPlain})`;

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

/** A centre built for LaTeX, respelled as plain text. */
function centerPlainOf(latex: string): string {
  return latex
    .replace(/\\(?:d|t)?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/g, "$1/$2")
    .replace(/\\pi/g, "π")
    .replace(/[{}]/g, "")
    .replace(/\\/g, "");
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
