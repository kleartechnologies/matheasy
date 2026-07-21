/**
 * Limit engine — `lim_{x→a} f(x)`.
 *
 * Golden rule (spec §1): the answer is computed deterministically and proven,
 * never invented. Here the PROOF is a numeric oracle: we evaluate f at a
 * geometric sequence of points approaching `a` from the allowed side(s) and
 * require the samples to CONVERGE — and, for a two-sided limit, to converge to
 * the SAME value from both sides. A limit that diverges, oscillates, or has a
 * jump (the two sides disagree) is DECLINED honestly (couldn't-verify), never
 * guessed. This mirrors how `numericIntegrate` is the source of truth for a
 * definite integral — no LLM is involved.
 */
import { fraction } from "mathjs";

import { exactForm } from "./exact";
import { latexToAscii } from "./latex";
import type { Classification, FinalAnswer, MethodData } from "./types";
import { evalReal } from "./verify";

export interface ParsedLimit {
  variable: string;
  /** A finite approach point, or ±Infinity. */
  point: number;
  dir: "both" | "left" | "right";
  /** The function, as ascii (what mathjs evaluates). */
  fn: string;
}

/**
 * Parse `\lim_{x \to a} f(x)` (also `\to a^+`/`a^-` one-sided, and `a = \infty`).
 * Returns null when there is no `\lim`, the `x \to a` subscript is malformed, or
 * the approach point / function can't be read.
 */
export function parseLimit(rawLatex: string): ParsedLimit | null {
  const braced = /\\lim\s*_\s*\{([^{}]*)\}/.exec(rawLatex);
  const bare = /\\lim\s*_\s*([^\s{]+)/.exec(rawLatex);
  const m = braced ?? bare;
  if (!m) return null;
  const sub = m[1];

  // "x \to a" / "x \rightarrow a" / "x → a" / "x -> a".
  const tm = /([a-zA-Z])\s*(?:\\to|\\rightarrow|→|-\s*>)\s*(.+)$/.exec(sub);
  if (!tm) return null;
  const variable = tm[1];
  let pointRaw = tm[2].trim();

  // A trailing ^+ / ^- makes it one-sided.
  let dir: "both" | "left" | "right" = "both";
  const dm = /\^\s*\{?\s*([+-])\s*\}?\s*$/.exec(pointRaw);
  if (dm) {
    dir = dm[1] === "+" ? "right" : "left";
    pointRaw = pointRaw.slice(0, dm.index).trim();
  }

  let point: number;
  if (/\\infty|∞/.test(pointRaw)) {
    point = /^-/.test(pointRaw.replace(/\s+/g, "")) ? -Infinity : Infinity;
  } else {
    point = evalReal(latexToAscii(pointRaw));
    if (!Number.isFinite(point)) return null;
  }

  // The function is everything AFTER the `\lim_{…}` block.
  const fnLatex = rawLatex.slice((m.index ?? 0) + m[0].length).trim();
  const fn = latexToAscii(fnLatex).trim();
  if (!fn || !/[a-zA-Z0-9]/.test(fn)) return null;
  return { variable, point, dir, fn };
}

/**
 * From a sequence of samples approaching the point, decide whether it CONVERGES
 * and, if so, to what value — accelerating slow (geometric) convergence with
 * Aitken's Δ². Returns null for a diverging, oscillating, or too-slow tail. The
 * bias is toward null: a false decline is honest, a wrong value is not.
 */
/** Aitken Δ² on ONE consecutive triple, but ONLY when the triple's tail is
 * geometric (its difference ratio is comfortably below 1). Returns the
 * extrapolated limit, or null when the triple isn't a trustworthy geometric
 * tail. A flat triple returns its value. */
function aitkenTriple(v0: number, v1: number, v2: number): number | null {
  const d1 = v1 - v0;
  const d2 = v2 - v1;
  const a1 = Math.abs(d1);
  const a2 = Math.abs(d2);
  if (a2 < 1e-12 && a1 < 1e-9) return v2; // flat to precision ⇒ converged
  if (a1 < 1e-15) return null; // can't form a ratio
  // GEOMETRIC decay only. A ratio ≈ 1 (constant steps) is LINEAR growth — a
  // divergent limit under geometric sampling (ln x, log x). A ratio drifting up
  // toward 1 is a harmonic / one-over-log tail Aitken can't model.
  if (a2 / a1 > 0.5) return null;
  const secondDiff = v2 - 2 * v1 + v0;
  if (Math.abs(secondDiff) < 1e-14) return v2;
  const L = v2 - (d2 * d2) / secondDiff;
  if (!Number.isFinite(L)) return null;
  // A geometric tail (ρ ≤ 0.5) corrects v2 by ρ/(1−ρ)·|Δv| ≤ |Δv|; a bigger
  // correction means the tail isn't really geometric — reject.
  if (Math.abs(L - v2) > 3 * a2 + 1e-9) return null;
  return L;
}

/**
 * From a sequence approaching the point, decide whether it CONVERGES and to
 * what. Aitken-extrapolates every consecutive triple from the tail inward and
 * requires the two most-recent trustworthy (geometric) estimates to AGREE. This:
 *   • rejects DIVERGENCE (ln x, x²) and non-geometric tails (harmonic 1/ln x,
 *     ln(ln x)) — their per-triple estimates never form two that agree; and
 *   • tolerates a single noise-dominated tail sample from floating-point
 *     cancellation ((1−cos x)/x²), because the clean earlier triples still agree.
 * The bias is toward null: a false decline is honest, a wrong value is not.
 */
function converge(vals: number[]): number | null {
  const n = vals.length;
  if (n < 4) return null;
  const estimates: number[] = [];
  for (let i = n - 1; i >= 2 && estimates.length < 3; i--) {
    const L = aitkenTriple(vals[i - 2], vals[i - 1], vals[i]);
    if (L !== null) estimates.push(L);
  }
  if (estimates.length < 2) return null;
  const [a, b] = estimates;
  if (Math.abs(a - b) > 1e-4 * (1 + Math.abs(a)) + 1e-7) return null;
  return a;
}

/** Evaluate f along one approach and return the converged value, or null when
 * that side diverges / oscillates / can't be sampled. */
function sampleSide(
  fn: string,
  variable: string,
  point: number,
  side: 1 | -1
): number | null {
  const finite = Number.isFinite(point);
  // Approach points: a ± {1e-1 … 1e-6} for a finite point (1e-6 is the floor —
  // smaller h invites floating-point cancellation), or growing |x| for ±∞.
  const xs = finite
    ? [1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6].map((h) => point + side * h)
    : [10, 100, 1e3, 1e4, 1e5, 1e6].map((v) => (point > 0 ? v : -v));

  const vals: number[] = [];
  for (const x of xs) {
    const v = evalReal(fn, { [variable]: x });
    if (Number.isFinite(v)) vals.push(v);
  }
  if (vals.length < 4) return null; // too few finite samples to trust
  return converge(vals);
}

/** Snap tiny numeric noise: an integer within 1e-4, else round to 6 dp. */
function cleanValue(v: number): number {
  const r = Math.round(v);
  if (Math.abs(v - r) < 1e-4) return r;
  return Number(v.toFixed(6));
}

/** Present the verified limit value (integer / exact irrational / fraction /
 * decimal) — mirrors the solver's own value formatting. */
function formatLimit(n: number): FinalAnswer {
  if (Number.isInteger(n)) return { latex: String(n), plain: String(n) };
  const exact = exactForm(n);
  if (exact) return { latex: exact.latex, plain: exact.plain };
  try {
    const fr = fraction(n) as unknown as { n: bigint; d: bigint; s: number };
    const num = Number(fr.n);
    const den = Number(fr.d);
    if (den !== 1 && den <= 1000) {
      const sign = fr.s < 0 ? "-" : "";
      return { latex: `${sign}\\tfrac{${num}}{${den}}`, plain: `${sign}${num}/${den}` };
    }
  } catch {
    /* fall through to decimal */
  }
  return { latex: String(n), plain: String(n) };
}

/** A short human label for the approach point, used in the narration. */
function pointLabel(point: number, dir: "both" | "left" | "right"): string {
  const base =
    point === Infinity ? "∞" : point === -Infinity ? "−∞" : String(point);
  if (dir === "right") return `${base}⁺`;
  if (dir === "left") return `${base}⁻`;
  return base;
}

/**
 * Compute-and-verify the limit. Returns the verified value + engine-authored
 * steps, or null when it diverges / oscillates / the two sides disagree (the
 * caller then declines honestly). Deterministic — no LLM.
 */
export function evaluateLimit(
  cls: Classification
): { answer: FinalAnswer; methods: MethodData[] } | null {
  const { limitVar, limitPoint, limitDir, limitFn } = cls;
  if (
    !limitVar ||
    limitFn === undefined ||
    limitPoint === undefined ||
    limitDir === undefined
  ) {
    return null;
  }

  let value: number | null;
  if (!Number.isFinite(limitPoint)) {
    // At ±∞ there is only one "side" — sample growing |x|.
    value = sampleSide(limitFn, limitVar, limitPoint, 1);
  } else if (limitDir === "right") {
    value = sampleSide(limitFn, limitVar, limitPoint, 1);
  } else if (limitDir === "left") {
    value = sampleSide(limitFn, limitVar, limitPoint, -1);
  } else {
    // Two-sided: both sides must converge AND agree (else a jump — DNE).
    const r = sampleSide(limitFn, limitVar, limitPoint, 1);
    const l = sampleSide(limitFn, limitVar, limitPoint, -1);
    if (r === null || l === null) return null;
    // Both sides are already converged values, so a genuine two-sided limit has
    // them agreeing to convergence precision — a TIGHT tolerance. (The old 1e-3
    // relative tol scaled up with |value|, waving through a jump of ~1 at a
    // value of ~1000: 999.5 vs 1000.5. 1e-4 relative catches it.)
    const tol = 1e-4 * (1 + Math.abs(r));
    if (Math.abs(r - l) > tol) return null; // the two sides disagree → DNE
    value = (r + l) / 2;
  }
  if (value === null || !Number.isFinite(value)) return null;

  const clean = cleanValue(value);
  const answer = formatLimit(clean);
  const where = pointLabel(limitPoint, limitDir);
  const fnDisplay = cls.latex;

  const methods: MethodData[] = [
    {
      id: "limit_numeric",
      name: "Evaluate the limit",
      examPick: true,
      steps: [
        {
          expression: fnDisplay,
          operation: "The limit to evaluate",
          why: `We want the value the expression approaches as ${limitVar} → ${where}.`,
        },
        {
          expression: `${limitVar} \\to ${where}`,
          operation: "Approach the point",
          why:
            limitDir === "both"
              ? `Take ${limitVar} closer and closer to ${where} from both sides.`
              : `Take ${limitVar} closer and closer to ${where} from the ${limitDir}.`,
        },
        {
          expression: `${answer.latex}`,
          operation: "Answer",
          why: `The expression settles on ${answer.plain}${
            limitDir === "both" ? " from both sides" : ""
          }.`,
        },
      ],
    },
  ];
  return { answer, methods };
}
