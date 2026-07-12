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
