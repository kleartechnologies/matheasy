/**
 * Exact-form recognizer for DISPLAY (spec §1 correctness — the exact form IS the
 * right answer for SPM/IGCSE; a teacher marks the decimal wrong).
 *
 * mathjs/mathsteps evaluate irrational constants to floating point when they
 * simplify or differentiate (`sqrt(2)` → `1.4142135623730951`), and the roots
 * path builds the displayed answer from the verified NUMERIC value. This module
 * turns such a value back into its exact symbolic form (√r, π multiples, and
 * rational multiples of them) purely for what the student sees.
 *
 * It is DISPLAY-ONLY: verification keeps substituting the numeric value, so this
 * never affects whether an answer is accepted — only how a verified answer reads.
 * It returns `null` for anything it can't confidently identify (plain decimals,
 * integers, simple fractions), leaving the caller's existing formatting.
 */

export interface ExactForm {
  ascii: string;
  latex: string;
  plain: string;
}

/** Square-free radicands worth recognizing (√4, √8… are caught as 2√2 etc.). */
const RADICANDS = [2, 3, 5, 6, 7, 10, 11, 13, 14, 15, 17, 19, 21, 22, 23, 26, 29, 30];

/** Match tolerance on the RECONSTRUCTED value — comfortably catches a 5–6
 * sig-fig model value, tight enough that a plain decimal (2.5) or another
 * constant (π) never collides with a spurious `(p/q)√r`. */
const TOL = 1e-5;
const MAX_DEN = 12;
const MAX_NUM = 24;

function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

/**
 * If `a ≈ (p/q)·unit` for small p,q (checked against the RECONSTRUCTED value, so
 * the tolerance is uniform regardless of how large `unit` is — this is what
 * stops big radicands from loosely matching everything), returns the reduced
 * p/q; else null.
 */
function rationalMultiple(a: number, unit: number): { num: number; den: number } | null {
  for (let den = 1; den <= MAX_DEN; den++) {
    const num = Math.round((a / unit) * den);
    if (num === 0 || num > MAX_NUM * den) continue;
    if (Math.abs(a - (num / den) * unit) < TOL) {
      const g = gcd(num, den) || 1;
      return { num: num / g, den: den / g };
    }
  }
  return null;
}

/** Render `(num/den) · <unit>` in ascii / LaTeX / plain. */
function withUnit(
  sign: string,
  num: number,
  den: number,
  unitAscii: string,
  unitLatex: string,
  unitPlain: string
): ExactForm {
  const nAscii = num === 1 ? unitAscii : `${num}*${unitAscii}`;
  const nLatex = num === 1 ? unitLatex : `${num}${unitLatex}`;
  const nPlain = num === 1 ? unitPlain : `${num}${unitPlain}`;
  if (den === 1) {
    return { ascii: `${sign}${nAscii}`, latex: `${sign}${nLatex}`, plain: `${sign}${nPlain}` };
  }
  return {
    ascii: `${sign}(${nAscii})/${den}`,
    latex: `${sign}\\tfrac{${nLatex}}{${den}}`,
    plain: `${sign}${nPlain}/${den}`,
  };
}

/**
 * The exact symbolic form of [x] — a rational multiple of √r or of π — or null
 * when [x] isn't confidently one of those (integers and simple decimals return
 * null so the caller renders them its usual way).
 */
export function exactForm(x: number): ExactForm | null {
  if (!Number.isFinite(x) || Math.abs(x) < TOL) return null;
  if (Math.abs(x - Math.round(x)) < TOL) return null; // integer → caller handles
  const sign = x < 0 ? "-" : "";
  const a = Math.abs(x);

  // (p/q)·√r — the common exam form; check before π so √2 etc. resolve first.
  for (const r of RADICANDS) {
    const fr = rationalMultiple(a, Math.sqrt(r));
    if (fr) return withUnit(sign, fr.num, fr.den, `sqrt(${r})`, `\\sqrt{${r}}`, `√${r}`);
  }

  // (p/q)·π
  const rp = rationalMultiple(a, Math.PI);
  if (rp) return withUnit(sign, rp.num, rp.den, "pi", "\\pi", "π");

  return null;
}

// --- Quadratic roots, built from the coefficients ---------------------------
//
// `exactForm` works backwards from a float, so it can only find things that are
// a single multiple of one unit. A quadratic root is usually a SUM — `x²+4x+1=0`
// has roots −2 ± √3 — and searching floats for sums is both slow and prone to
// finding coincidences. The algebra already knows the answer: the roots ARE
// (−b ± √(b²−4ac)) / 2a, so build the surd from a, b, c and never sniff at all.

/** `√48 = 4√3`: the largest square dividing `d`, and what is left. */
export function squareFreeSplit(d: number): { k: number; m: number } | null {
  if (!Number.isInteger(d) || d <= 0 || d > 1e8) return null;
  for (let k = Math.floor(Math.sqrt(d)); k >= 1; k--) {
    if (d % (k * k) === 0) return { k, m: d / (k * k) };
  }
  return null;
}

export interface SurdRoot {
  value: number;
  ascii: string;
  latex: string;
  plain: string;
}

/**
 * The two roots of `ax² + bx + c` in exact surd form, or null when there is
 * nothing a surd would add — a negative or zero discriminant (no two real
 * roots), a perfect square (the roots are rational, and the caller's fraction
 * form is already the exact answer), or non-integer coefficients.
 */
export function quadraticSurdRoots(
  a: number,
  b: number,
  c: number
): [SurdRoot, SurdRoot] | null {
  if (![a, b, c].every((v) => Number.isInteger(v)) || a === 0) return null;
  const disc = b * b - 4 * a * c;
  if (disc <= 0) return null;
  const split = squareFreeSplit(disc);
  if (!split || split.m === 1) return null;

  // Normalise so the denominator is positive, then cancel the common factor —
  // `(−4 ± 2√3)/2` is not an answer, `−2 ± √3` is.
  let p = -b;
  let k = split.k;
  let den = 2 * a;
  if (den < 0) {
    p = -p;
    k = -k;
    den = -den;
  }
  const g = gcd(gcd(Math.abs(p), Math.abs(k)), den) || 1;
  p /= g;
  k /= g;
  den /= g;
  const flip = k < 0; // a negative √-coefficient just swaps which root is which
  const mag = Math.abs(k);

  const build = (plus: boolean): SurdRoot => {
    const positive = flip ? !plus : plus;
    const surdAscii = mag === 1 ? `sqrt(${split.m})` : `${mag}*sqrt(${split.m})`;
    const surdLatex = mag === 1 ? `\\sqrt{${split.m}}` : `${mag}\\sqrt{${split.m}}`;
    const surdPlain = mag === 1 ? `√${split.m}` : `${mag}√${split.m}`;
    const op = positive ? "+" : "-";
    const numAscii =
      p === 0 ? `${positive ? "" : "-"}${surdAscii}` : `${p} ${op} ${surdAscii}`;
    const numLatex =
      p === 0 ? `${positive ? "" : "-"}${surdLatex}` : `${p} ${op} ${surdLatex}`;
    const numPlain =
      p === 0 ? `${positive ? "" : "-"}${surdPlain}` : `${p} ${op} ${surdPlain}`;
    const value = (p + (positive ? mag : -mag) * Math.sqrt(split.m)) / den;
    if (den === 1) {
      return { value, ascii: numAscii, latex: numLatex, plain: numPlain };
    }
    return {
      value,
      ascii: `(${numAscii})/${den}`,
      latex: `\\tfrac{${numLatex}}{${den}}`,
      plain: p === 0 ? `${numPlain}/${den}` : `(${numPlain})/${den}`,
    };
  };
  const pair: [SurdRoot, SurdRoot] = [build(false), build(true)];
  // `flip` swaps which branch is smaller; every caller matches by value, and the
  // answer line lists roots ascending, so hand them over already ordered.
  pair.sort((u, v) => u.value - v.value);
  return pair;
}

/**
 * Replace mathjs-emitted irrational decimals inside an ascii expression with
 * their exact form (so a differentiated / simplified result shows `sqrt(2)`, not
 * `1.4142135623730951`). Only LONG decimals (≥6 fractional digits — mathjs's
 * full-precision constants) are candidates, so an intended short decimal like
 * `0.5` or `3.2` is never touched.
 */
export function resymbolize(ascii: string): string {
  return ascii.replace(/\d+\.\d{6,}/g, (match) => {
    const form = exactForm(Number(match));
    return form ? form.ascii : match;
  });
}
