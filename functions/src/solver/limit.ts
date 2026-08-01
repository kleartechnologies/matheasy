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
 *
 * Adversarial-hardening history (three review rounds): a numeric oracle is
 * genuinely fragile, so every gate below biases HARD toward declining.
 *   • R1 — geometric-decay + multi-estimate agreement (log growth / harmonic
 *     tails are NOT convergence, they just have shrinking differences).
 *   • R2 — an off-phase companion ladder to break power-of-10 lattice aliasing.
 *   • R3 — this file. The single 1/√2 companion was defeated by QUADRATIC/LOG
 *     phase (cos(2πx²), cos(2π·k·log x)) because (1/√2)²=½ is rational and
 *     re-aliases; a leading coefficient/sign in the LaTeX was silently DROPPED
 *     (`-lim x²`→+9 sign flip); a saturating tail (tanh(1e6·x)) fell back to a
 *     coarse plateau; and a small jump on a large baseline slipped the relative
 *     two-sided tolerance. Fixes, in order: fold/decline the LaTeX prefix; a
 *     DENSE off-lattice irrational audit (replaces the single companion); a
 *     fine-anchored converge() that will not fall back past an unsettled tail;
 *     and a spread-aware two-sided tolerance.
 */
import { fraction, parse } from "mathjs";

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
  /** A leading numeric coefficient/sign folded from the LaTeX before `\lim`
   * (`-\lim`→-1, `2\lim`→2, `\pi\lim`→π). 1 when there is no prefix. A prefix
   * that is not a PURE multiplicative constant — an additive one whether dangling
   * (`10-\lim`) or complete (`10 - 3\lim`, `1 + ½\lim`), or symbolic (`a\lim`) —
   * yields a NON-FINITE factor so evaluateLimit declines rather than fold the
   * whole prefix as one coefficient and compute the wrong expression. */
  factor: number;
}

/**
 * True when `ascii` has a binary +/- at bracket-depth 0 — an ADDITIVE term, as
 * opposed to a pure multiplicative coefficient (`-3`, `((1)/(2))`, `2*pi`). A
 * leading sign is not additive. Used to reject an additive prefix before `\lim`:
 * `10 - 3\lim x` must be `10 − 3·L`, never `(10−3)·L`, so its whole value cannot
 * be folded as one factor.
 */
function hasTopLevelAdditive(ascii: string): boolean {
  let depth = 0;
  let seenValue = false; // a value/token has appeared at depth 0 → a later +/- is binary
  for (let i = 0; i < ascii.length; i++) {
    const ch = ascii[i];
    if (ch === "(" || ch === "[" || ch === "{") {
      depth++;
      seenValue = true;
      continue;
    }
    if (ch === ")" || ch === "]" || ch === "}") {
      if (depth > 0) depth--;
      continue;
    }
    if (ch === " " || ch === "\t") continue;
    if (depth === 0 && (ch === "+" || ch === "-")) {
      if (seenValue) return true; // binary +/- at the top level ⇒ additive
      continue; // a leading sign is fine
    }
    if (depth === 0) seenValue = true;
  }
  return false;
}

/**
 * Parse `\lim_{x \to a} f(x)` (also `\to a^+`/`a^-` one-sided, and `a = \infty`).
 * Returns null when there is no `\lim`, the `x \to a` subscript is malformed, the
 * approach point / function can't be read, OR there is a leading prefix before
 * `\lim` that is not a bare finite constant coefficient (see `factor`).
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

  // Anything BEFORE `\lim` is a coefficient/sign on the whole limit — it must be
  // folded onto the result, never dropped. (Dropping it shipped `-\lim_{x→3}x²`
  // as +9 instead of −9, and `2\lim…` as 1.) We fold only a bare finite constant
  // (a sign, an integer/decimal, a fraction, π, …). An additive prefix (`10-`),
  // a symbolic one (`a`), or anything evalReal can't turn into a finite number
  // means we CANNOT compose the answer safely — so we flag it with a NON-FINITE
  // factor. The classifier still routes it to the (deterministic) limit engine,
  // which declines honestly on the bad factor: a `\lim` input never falls through
  // to the paid LLM tier, and never answers the wrong sub-expression.
  const prefixRaw = rawLatex
    .slice(0, m.index ?? 0)
    .replace(/\\displaystyle|\\textstyle|\\limits|\\,|\\;|\\!/g, " ")
    .replace(/\\cdot|\\times|\*/g, " ")
    .trim();
  let factor = 1;
  if (prefixRaw !== "") {
    if (prefixRaw === "-") factor = -1;
    else if (prefixRaw === "+") factor = 1;
    else {
      const ascii = latexToAscii(prefixRaw);
      // A COMPLETE additive prefix (`10 - 3`, `1 + \frac12`, `5 - 2\frac12`)
      // evaluates finite, so the old `!Number.isFinite` guard let it through and
      // it was folded as one multiplicative factor — shipping (10−3)·L = 14 for
      // `10 - 3\lim_{x→2}x` (true 4). Reject any prefix with a top-level +/- so
      // only a PURE coefficient (sign / number / fraction / π / product) is
      // folded; everything else declines. (A dangling operator still → NaN.)
      factor = hasTopLevelAdditive(ascii) ? NaN : evalReal(ascii);
    }
  }

  // The function is everything AFTER the `\lim_{…}` block.
  const fnLatex = rawLatex.slice((m.index ?? 0) + m[0].length).trim();
  const fn = latexToAscii(fnLatex).trim();
  if (!fn || !/[a-zA-Z0-9]/.test(fn)) return null;
  return { variable, point, dir, fn, factor };
}

/** A converged approach: the value, plus `spread` — how much the tail still
 * wiggles (the disagreement between the two Aitken estimates). An EXACT flat
 * tail has spread 0; this lets the two-sided check use a tolerance derived from
 * real convergence noise instead of a fixed relative one (which waved a small
 * jump through at a large baseline). */
interface Converged {
  value: number;
  spread: number;
}

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
 * From a sequence approaching the point (coarse → fine), decide whether it
 * CONVERGES and to what. We Aitken-extrapolate every consecutive triple from the
 * FINE end inward and require the two finest trustworthy (geometric) estimates to
 * AGREE.
 *
 * The subtlety is what to do when a fine triple is REJECTED (non-geometric). Two
 * very different things produce that:
 *   • float-cancellation JITTER at the very fine tail ((1−cos x)/x² at h≤1e-6) —
 *     small-amplitude noise ABOUT the real value; the clean coarser triples still
 *     carry the true limit, so we fall back to them; versus
 *   • a real DEPARTURE — divergence (ln x, 1/x), a harmonic tail (1/ln x), or a
 *     saturated plateau breaking below the step floor (tanh(1e6·x): …,1,1,0.76,
 *     true 0). Here the coarse samples LIE, so falling back would ship a wrong
 *     value.
 * We tell them apart by the rejected triple's SPAN: tiny span ⇒ fp jitter, skip
 * and fall back; large span ⇒ real departure, DECLINE. Bias: a false decline is
 * honest, a wrong value is not.
 */
function converge(vals: number[]): Converged | null {
  const n = vals.length;
  if (n < 4) return null;
  const estimates: number[] = [];
  for (let i = n - 1; i >= 2 && estimates.length < 2; i--) {
    const v0 = vals[i - 2];
    const v1 = vals[i - 1];
    const v2 = vals[i];
    const L = aitkenTriple(v0, v1, v2);
    if (L === null) {
      const span = Math.max(
        Math.abs(v0 - v1),
        Math.abs(v1 - v2),
        Math.abs(v0 - v2)
      );
      // Small-amplitude fp jitter ⇒ skip and fall back to a cleaner triple.
      // A large swing at this scale is a genuine departure ⇒ decline.
      if (span <= 1e-3 * (1 + Math.abs(v2)) + 1e-6) continue;
      return null;
    }
    estimates.push(L);
  }
  if (estimates.length < 2) return null;
  const [a, b] = estimates;
  const spread = Math.abs(a - b);
  if (spread > 1e-4 * (1 + Math.abs(a)) + 1e-7) return null;
  return { value: a, spread };
}

/** Sample f along ONE geometric approach and return the converged value +
 * spread, or null. The primary ladder is the power-of-10 lattice; the anti-
 * oscillation defense is now the dense off-lattice audit in `sampleSide`. */
function sampleLadder(
  fn: string,
  variable: string,
  point: number,
  side: 1 | -1
): Converged | null {
  const finite = Number.isFinite(point);
  // Jitter the geometric ladder OFF the power-of-10 (integer) lattice by an
  // irrational factor. On the round lattice cos(2π·10^k)=1 EXACTLY at every rung
  // (and likewise for quadratic/log phase), so an oscillation looks perfectly
  // flat and the engine ships a DNE limit as its crest (100+cos(2πx) → 101).
  // Scaling every rung by φ (whose powers φ^k and log ln φ are all irrational)
  // lands each rung on a different phase, so the ladder ITSELF oscillates and
  // converge() declines at the source — before the audit's tolerance can be
  // out-scaled by a large baseline. A genuine limit is unaffected: only that the
  // rungs approach the point GEOMETRICALLY matters, not their exact values.
  const J = (1 + Math.sqrt(5)) / 2; // golden ratio φ ≈ 1.618…
  // Approach points: a ± φ·{1e-1 … 1e-6} for a finite point (1e-6·φ stays above
  // the floor where float cancellation bites), or growing |x| for ±∞.
  const xs = finite
    ? [1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6].map((h) => point + side * J * h)
    : [1e2, 1e3, 1e4, 1e6, 1e8, 1e10].map((v) => (point > 0 ? J * v : -J * v));

  const vals: number[] = [];
  for (const x of xs) {
    const v = evalReal(fn, { [variable]: x });
    if (Number.isFinite(v)) vals.push(v);
  }
  if (vals.length < 4) return null; // too few finite samples to trust
  return converge(vals);
}

/** Low-discrepancy fractional part via the golden-ratio additive recurrence —
 * scatters audit points irrationally so no single quadratic/logarithmic phase
 * can align them all. */
const PHI = (Math.sqrt(5) - 1) / 2; // ≈ 0.6180339887…, irrational

/**
 * Confirm the converged value is a genuine limit and NOT a sample-lattice
 * artifact, by re-sampling at DENSE, off-lattice, mutually-incommensurate points
 * across the FINE part of the approach region. A periodic / oscillating function
 * (cos(2πx), cos(2πx²), cos(2π·k·log x), cos(2π/x)) lands on the SAME phase on
 * the power-of-10 lattice and looks constant, but at these irrational points it
 * hits every phase and deviates by O(1) — far past the audit tolerance — so the
 * non-existent limit is declined. A truly converging function (even a decaying
 * one like sin(x)/x → 0) stays within tolerance at every audit point.
 *
 * This replaces the single 1/√2 companion ladder, whose one irrational scale
 * squared to a rational (½) and re-aliased under quadratic/log phase.
 */
function auditStable(
  fn: string,
  variable: string,
  point: number,
  side: 1 | -1,
  value: number,
  spread: number
): boolean {
  const finite = Number.isFinite(point);
  const N = 32;
  // O(1) oscillation deviates by ≈1; genuine geometric convergence is already
  // very close in the fine region, so this generous tolerance never false-
  // declines a real limit yet is ~50× below an oscillation's swing. This GROSS
  // check fires anywhere; the FAR-settled check below is the finer net.
  const looseTol = Math.max(2e-2 * (1 + Math.abs(value)), 16 * spread + 1e-9);

  // A BOUNDED saturating transcendental (tanh → ±1, atan/arctan → ±π/2, erf →
  // ±1) can hide its transition on a flat plateau when the crossover sits past
  // the ladder's 1.6e6 edge: `tanh(ln x − 40)` reads −1 out to 1e17 yet is +1
  // (true) far beyond, and `999999 + tanh(x − 3e5)` reads the −1 plateau 999998
  // below x=3e5. A HAND-ROLLED sigmoid/logistic dodges the name-list entirely —
  // `1/(1+e^{-(ln x − 600)})` → 1 has its crossover at x=e⁶⁰⁰≈10²⁶¹, so the ladder
  // reads a flat 0 and shipped the WRONG 0; matching a raw `e^`/`exp(` catches it.
  // These forms saturate to a constant or their argument overflows (→ skipped),
  // so we push the audit to 1e300 to expose the real tail (or, for a masked
  // logistic, force an honest DECLINE when far ≠ near). A pure ALGEBRAIC form like
  // √(x²+x)−x is deliberately NOT extended: past ~1e15 it hits catastrophic float
  // cancellation (reads 0, true ½) and would false-decline, and a bounded plateau
  // can't hide an algebraic feature anyway. (A cancellation form that merely
  // CONTAINS e^, e.g. x·(e^{1/x}−1), over-declines here — honest, acceptable.)
  // An ALGEBRAIC sigmoid A/√(A²+1) saturates to ±1 exactly like tanh but matches
  // none of the names above. Its sign-flip crossover sits where the variable part
  // cancels a large constant — (∛x−10⁶)/√((∛x−10⁶)²+1) flips at x=10¹⁸, and
  // (x·10⁻¹²−10⁶)/√(…) at x=10¹⁸ — far beyond the 1e12 reach, so the ladder read
  // one plateau and shipped the WRONG sign (−1 for a true +1; a φ-gate R9 hit).
  // Extend the reach when the function DIVIDES BY A √ AND carries a large (≥1e3)
  // constant that pushes the crossover out. A bare x/√(x²+1) (crossover at 0, no
  // large const) needs no extension, and a √-MINUS form like √(x²+x)−x is NOT a
  // division so it stays at 1e12 and dodges its own catastrophic cancellation.
  // A √ in the denominator can ALSO be written as a NEGATIVE-HALF POWER —
  // `(u²+1)^(-1/2)` is the same 1/√ but dodges the `/sqrt(` shape (a φ-gate R9 hit:
  // (x^0.1−100000)·((x^0.1−100000)²+1)^(-1/2) → −1 shipped for a true +1, crossover
  // at x=1e50) — so match `^(-1/2)` / `^(-0.5)` too.
  const dividesBySqrt =
    /\/\s*\(?\s*sqrt\s*\(/.test(fn) ||
    /\^\s*\(?\s*-\s*(?:1\s*\/\s*2|0?\.5)\b/.test(fn);
  const bigConst = dividesBySqrt && constMagnitudeRange(fn, variable).max >= 1e3;
  const saturating =
    /\b(?:tanh|arctan|arctanh|atanh|atan|erf)\b/.test(fn) ||
    /e\s*\^|\bexp\s*\(/.test(fn) ||
    bigConst;
  const farMag = saturating ? 1e300 : 1e12;

  // (proximity into the settling direction, deviation) for every finite sample.
  const devs: { prox: number; dev: number }[] = [];
  for (let j = 1; j <= N; j++) {
    const u = (j + 1) * PHI - Math.floor((j + 1) * PHI); // frac() → (0,1)
    let x: number;
    let prox: number;
    if (finite) {
      const h = 1e-6 * Math.pow(100, u); // 1e-6 … 1e-4, log-spaced, off-lattice
      x = point + side * h;
      prox = -h; // smaller h ⇒ closer to the point ⇒ more settled ⇒ larger prox
    } else {
      // 1e5 … farMag, log-spaced off-lattice. The low end (1e5) is where even a
      // slow real 1/x tail like (x+1000)/x is already within 0.01 (auditing from
      // 1e4 false-declined those). The high end reaches far past the ladder's
      // 1.6e6 edge to expose a masked saturation tail (see `saturating`).
      const mag = 1e5 * Math.pow(farMag / 1e5, u);
      x = point > 0 ? mag : -mag;
      prox = mag; // larger |x| ⇒ deeper into the tail ⇒ more settled ⇒ larger prox
    }
    const v = evalReal(fn, { [variable]: x });
    if (!Number.isFinite(v)) continue; // skip an undefined/overflowed sample
    const dev = Math.abs(v - value);
    if (dev > looseTol) return false; // gross disagreement anywhere ⇒ decline
    devs.push({ prox, dev });
  }
  if (devs.length < 6) return true; // too few finite samples to judge settling

  // Sort least-settled → most-settled and take each half's worst deviation.
  devs.sort((a, b) => a.prox - b.prox);
  const mid = Math.floor(devs.length / 2);
  let nearDev = 0;
  let farDev = 0;
  for (let i = 0; i < mid; i++) nearDev = Math.max(nearDev, devs[i].dev);
  for (let i = mid; i < devs.length; i++) farDev = Math.max(farDev, devs[i].dev);

  if (finite) {
    // At a FINITE point the "settled" half (finest h) is exactly where float
    // CANCELLATION bites — (1−cos x)/x² loses digits at h≈1e-6 — so a genuine
    // limit's far-dev EXCEEDS its near-dev and a DECAY ratio would false-decline
    // it. Judge that settled half against a relative floor instead: cancellation
    // jitter stays small (≲1e-3·|value|) while a finite log-periodic oscillation
    // (0.005·cos(2π log x) @0⁺) still swings O(amplitude) there and is DECLINED.
    const farTol = Math.max(3e-3 * (1 + Math.abs(value)), 64 * spread + 1e-9);
    if (farDev > farTol) return false;
    return true;
  }
  // At ∞ the tail genuinely settles, so DECAY (a ratio) is the right test — and,
  // unlike an absolute or |value|-relative farTol, it is immune to a large
  // baseline out-scaling the tolerance: 999999 + cos(2π log x) (amplitude 1 on a
  // 1e6 baseline) sailed through a 1e-3·|value| ≈ 1000 farTol but fails far > ½·near.
  // A genuine limit's far half is well under half its near half; a log-periodic
  // DNE, a masked saturation's newly-exposed opposite plateau, and a value that
  // converged to the WRONG plateau (a constant offset) all keep far ≈ near. The
  // floor keeps a DEAD-FLAT genuine saturation (near = far = 0) from declining:
  // the oracle's own noise (64·spread) and a few ulps on |value| — NOT scaled to
  // |value| beyond ulp size, or a big baseline would hide the oscillation again.
  const decayFloor = Math.max(64 * spread, 1e-13 * (1 + Math.abs(value)), 1e-9);
  if (farDev > 0.5 * nearDev + decayFloor) return false;
  // A log-periodic BEAT can park its far half near an envelope NODE so far < ½·near
  // and slip the decay ratio: 100 + 0.1·cos(2π log x)·(1+0.99·cos(2π/14·log x+3π/2))
  // shipped a flat 100 for a DNE oscillation (a φ-gate R9 hit). But a GENUINE ∞
  // limit is dead-settled deep in the tail — its far half deviates only by the
  // tail's residual, and a const-bounded (≤1e6) 1/x tail is ≤3e-3 even at the
  // shallowest far sample (~10^8·⁵), a moderate 1/√x tail ≤~1e-2. So an ABSOLUTE
  // far cap of 2e-2 declines the beat (its far half still swings ≳3e-2) while
  // passing every genuine tail; the small |value|-relative term lets a real
  // oscillation on a large baseline (999999+cos… → DNE) still trip it. (A
  // tiny-amplitude oscillation on a huge baseline can slip — contrived, and below
  // the baseline's meaningful precision.)
  const farCap = Math.max(2e-2, 3e-7 * (1 + Math.abs(value)));
  if (farDev > farCap) return false;
  return true;
}

/**
 * Converge along one approach, then AUDIT it against oscillation / lattice
 * aliasing (see `auditStable`). Returns the converged value + spread, or null.
 */
function sampleSide(
  fn: string,
  variable: string,
  point: number,
  side: 1 | -1
): Converged | null {
  const c = sampleLadder(fn, variable, point, side);
  if (c === null) return null;
  if (!auditStable(fn, variable, point, side, c.value, c.spread)) return null;
  return c;
}

/**
 * The largest and smallest-nonzero |value| among the function's CONSTANT
 * sub-expressions (a numeric literal, or a constant compound like `10^12`,
 * `5*10^6`, `10^{-13}`). A constant OUTSIDE the sampling window's reach places a
 * feature at a scale the fixed window ([~1e-6 … ~1e6]) cannot see, so the ladder
 * reads a dead-flat plateau and would ship it confidently:
 *   • TOO LARGE (≳ 1e6) — a sigmoid/tanh transition or sign flip beyond the far
 *     edge: `tanh(x−10^8) → −1` not +1, `cos(x/10^12) → 1` for a DNE limit.
 *   • TOO SMALL (≲ 1e-9, nonzero) — a very-low-FREQUENCY oscillation whose phase
 *     barely moves across the whole window, so every sample sits on one crest:
 *     `cos(10^{-13} x) → 1` and `cos(10^{-13}/x) → 1` are DNE, not 1. (A tiny
 *     ADDITIVE constant like `x + 10^{-13}` is harmless, but rejecting it too is
 *     an honest over-decline — golden-rule-safe — and such inputs are contrived.)
 * The caller declines on either. Ordinary limits use moderate constants; both
 * extremes are the contrived/adversarial case. Unparseable ⇒ {max: Infinity}
 * (decline — never guess).
 */
function constMagnitudeRange(
  fn: string,
  variable: string
): { max: number; minNonzero: number } {
  let root;
  try {
    root = parse(fn);
  } catch {
    return { max: Infinity, minNonzero: Infinity };
  }
  let max = 0;
  let minNonzero = Infinity;
  root.traverse((node: unknown) => {
    const n = node as {
      filter: (p: (x: { isSymbolNode?: boolean; name?: string }) => boolean) => unknown[];
      evaluate: () => unknown;
    };
    // A sub-expression that never references the limit variable is constant.
    const dependsOnVar =
      n.filter((x) => x.isSymbolNode === true && x.name === variable).length > 0;
    if (dependsOnVar) return;
    try {
      const v = n.evaluate();
      if (typeof v === "number" && Number.isFinite(v)) {
        const a = Math.abs(v);
        max = Math.max(max, a);
        if (a > 0) minNonzero = Math.min(minNonzero, a);
      }
    } catch {
      /* an unevaluable / non-numeric constant node — ignore */
    }
  });
  return { max, minNonzero };
}

/**
 * Snap tiny numeric noise to an integer, else round to 6 dp. The snap threshold
 * is tied SOLELY to the run's actual convergence noise (`spread`), NOT a fixed
 * window and NOT the point's resolution: a genuine integer limit lands within
 * ~1× the spread of the integer (measured: ≤ 8e-10 for the standard rational/trig
 * limits), whereas a real non-integer like `lim sin(1.00005x)/x = 1.00005` sits a
 * true 5e-5 away and converges CLEANLY (spread ≈ 0). `max(1e-11·(1+|v|), 32·spread)`
 * snaps the former, never the latter (the ulp-scale floor only absorbs FP rounding
 * of a true integer/rational; it is NOT a resolution window — a magnitude-scaled
 * floor of 1e-8·(1+|v|) was found to swallow genuine few-ppm offsets at large |v|).
 *
 * A fixed resolution FLOOR (~1e-5 for a finite point) was tried and REVERTED: it
 * snapped genuine well-conditioned limits (sin(0.500004x)/x → 0.500004, spread
 * 2e-16) onto the nearby rational, a wrong value. Empirically the two populations
 * separate by ~9 orders of magnitude in `spread` — the cases that SHOULD snap are
 * ILL-conditioned (a squeeze limit x·sin(1/x) lands at value ≈ 2.6e-6 with spread
 * ≈ 1.3e-7, only ~20× the spread from 0, so it is INDISTINGUISHABLE from its true
 * 0), the ones that must NOT snap are well-conditioned (spread ≤ 2.2e-16, offset
 * ≥ 3e-6 = 10¹⁰× the spread). So `spread` alone is the correct discriminator, and
 * a 32× window snaps the squeeze limit onto its true 0 with a 9-OOM safety margin
 * from every genuine near-rational.
 */
/**
 * FIXED ABSOLUTE ceilings on the spread-driven snap window, split by REGIME.
 * `k·spread` alone is unbounded, and an ILL-CONDITIONED limit can carry a spread
 * whose window is enormous — large enough to swallow a genuine offset and snap to a
 * WRONG clean number. A φ-gate R9 confirmed such over-snaps that these caps close.
 *
 * The regimes separate because the two populations that MUST snap live at different
 * points, and the WRONG snaps cluster differently by point kind:
 *   • FINITE point — the genuine snap can be badly ill-conditioned: an oscillatory
 *     squeeze x·sin(1/x) → 0 ALIASES to ~2.6e-6 (only ~20× its spread), and a
 *     deep-cancellation (ln(1+2x)−2x)/x² → −2 lands ~2.5e-5 short. Both need a
 *     GENEROUS window (32·spread, capped 1e-4). A well-conditioned near-integer
 *     (sin(1.00005x)/x → 1.00005, spread≈0) sits a true 5e-5 out and is NOT snapped.
 *   • INFINITE point — the tail SETTLES: a genuine integer/rational limit lands
 *     ≤ 1e-10 out (measured), while a real few-ppm fractional tail (999999.000007
 *     ·x/(x+1) → 999999.000007) must be PRESERVED. The two populations are ~4 OOM
 *     apart, so a TIGHT window (8·spread, capped 1e-6) snaps the genuine ones and
 *     rejects the real tails (999999.000007 → 999999 was the R9 hit).
 */
const SNAP_ABS_CAP_FINITE = 1e-4;
const SNAP_ABS_CAP_INFINITE = 1e-6;

function cleanValue(v: number, spread = 0, finite = true): number {
  // The floor is a TRUE ULP-scale FP-rounding budget (~few hundred ulps of |v|),
  // NOT a resolution window: it absorbs the rounding of a genuine integer/rational
  // computed to magnitude |v| but must never swallow a real few-ppm offset. The old
  // 1e-11·(1+|v|) grew to 1e-5 at |v|≈1e6 and swallowed a real 7e-6 tail
  // (999999.000007 → 999999, a φ-gate R9 hit); 64·EPSILON·(1+|v|) is ~1.4e-8 there,
  // far below that tail yet still above the ~1e-10 rounding of a true 1e6 integer.
  const fpFloor = 64 * Number.EPSILON * (1 + Math.abs(v));
  // The snap factor + cap depend on the regime (see SNAP_ABS_CAP_* above). The
  // spread term still does the real work — it is what tells an ill-conditioned
  // limit that SHOULD snap (large noise) from a clean near-rational that must NOT
  // (spread≈0, only the ulp floor applies, far below any genuine offset).
  const factor = finite ? 32 : 8;
  const absCap = finite ? SNAP_ABS_CAP_FINITE : SNAP_ABS_CAP_INFINITE;
  const r = Math.round(v);
  const snapTol = Math.max(fpFloor, Math.min(factor * spread, absCap));
  if (Math.abs(v - r) <= snapTol) return r;
  // Snap to a SIMPLE rational when the estimate lands within the run's convergence
  // noise of one. A cancellation-prone limit like (eˣ−1−x)/x² → ½ converges cleanly
  // in SHAPE but a true ~7e-6 short of 0.5 (Δ²/x² loses digits), and the raw 0.499993
  // reads as a wrong answer; 12.50003 → 25/2 the same way. Those genuine estimates sit
  // INSIDE the noise (offset ≤ 0.55·spread); a REAL constant added (0.5 + 5e-5) sits
  // OUTSIDE it (offset ≥ 1.1·spread). So a TIGHT 0.8·spread window (capped 4e-5) snaps
  // the genuine cancellations and rejects a shifted one — a φ-gate R9 hit was
  // (eˣ−1−x)/x² + 0.00005 → ½ (true 0.50005), which 32·spread had swallowed.
  const ratTol = Math.max(fpFloor, Math.min(0.8 * spread, 4e-5));
  for (const q of [2, 3, 4, 5, 6, 8, 10, 12]) {
    const p = Math.round(v * q);
    if (p % q === 0) continue; // an integer in disguise — already handled above
    if (Math.abs(v - p / q) <= ratTol) return p / q;
  }
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
  // A non-finite factor is parseLimit's flag for an un-foldable LaTeX prefix
  // (additive `10-\lim`, symbolic `a\lim`) — decline rather than answer the bare
  // sub-expression and drop the prefix.
  const factor = cls.limitFactor ?? 1;
  if (!Number.isFinite(factor)) return null;

  // A feature governed by a constant OUTSIDE the sampling window ([~1e-6 … ~1e6])
  // hides on a flat plateau the ladder reads confidently: a huge constant (≳1e6)
  // puts a saturation/sign transition beyond the far edge; a tiny nonzero one
  // (≲1e-9) makes a very-low-frequency oscillation whose whole visible arc is one
  // crest (`cos(1e-13 x)` looks like the constant 1). We can't sample far/close
  // enough to see the truth — decline on either.
  const constRange = constMagnitudeRange(limitFn, limitVar);
  if (constRange.max > 1e6) return null;
  if (constRange.minNonzero < 1e-9) return null;

  let inner: number | null;
  let innerSpread = 0; // the run's convergence noise, forwarded to cleanValue
  if (!Number.isFinite(limitPoint)) {
    // At ±∞ there is only one "side" — sample growing |x|.
    const c = sampleSide(limitFn, limitVar, limitPoint, 1);
    inner = c ? c.value : null;
    innerSpread = c ? c.spread : 0;
  } else if (limitDir === "right") {
    const c = sampleSide(limitFn, limitVar, limitPoint, 1);
    inner = c ? c.value : null;
    innerSpread = c ? c.spread : 0;
  } else if (limitDir === "left") {
    const c = sampleSide(limitFn, limitVar, limitPoint, -1);
    inner = c ? c.value : null;
    innerSpread = c ? c.spread : 0;
  } else {
    // Two-sided: both sides must converge AND agree (else a jump — DNE).
    const r = sampleSide(limitFn, limitVar, limitPoint, 1);
    const l = sampleSide(limitFn, limitVar, limitPoint, -1);
    if (r === null || l === null) return null;
    // MIRROR-DIFFERENCE DECAY. A two-sided limit exists iff f(a+h) − f(a−h) → 0
    // as h → 0; a jump keeps that difference at the (constant) jump. Comparing the
    // extrapolated side VALUES alone is defeated when a slow EVEN tail (e.g.
    // +k|x|^0.4) inflates each side's spread — a genuine 40-unit jump on a 1e5
    // baseline then hides under a 16·spread ≈ 72 tolerance. The mirror difference
    // is immune: the common tail CANCELS, so d(h) measures the jump directly and
    // its DECAY (not its size against a spread-scaled tol) distinguishes a limit
    // (d shrinks) from a jump (d stays ≈ constant).
    if (Number.isFinite(limitPoint)) {
      const J = (1 + Math.sqrt(5)) / 2; // same φ jitter as the ladder
      const ds: number[] = [];
      for (const h of [1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6]) {
        const vr = evalReal(limitFn, { [limitVar]: limitPoint + J * h });
        const vl = evalReal(limitFn, { [limitVar]: limitPoint - J * h });
        if (Number.isFinite(vr) && Number.isFinite(vl)) ds.push(Math.abs(vr - vl));
      }
      if (ds.length >= 3) {
        const dFine = ds[ds.length - 1];
        let dCoarse = 0;
        for (let i = 0; i < ds.length - 1; i++) dCoarse = Math.max(dCoarse, ds[i]);
        // A limit's mirror difference decays toward 0; a jump's stays ≈ constant.
        // Decline when the finest difference NEITHER shrank well below the coarse
        // ones (still ≳ ¼ of them) NOR is float-noise small. The floor tracks the
        // side values' magnitude for genuine cancellation jitter — deliberately
        // NOT the (tail-inflated) spread, which is exactly the trap being closed.
        const jumpFloor = 1e-9 * (1 + Math.abs(r.value) + Math.abs(l.value));
        if (dFine > jumpFloor && dFine > 0.25 * dCoarse) return null; // jump → DNE
        // A slow sub-linear EVEN tail (40|x−2|^0.31) inflates the COARSE
        // differences so the finest still sits under ¼ of them and a masked odd
        // JUMP slips the check above (a φ-gate R9 hit: ½·sgn(x−2) + sgn(x−2)·
        // (40|x−2|^0.31+40|x−2|^0.49) shipped 1000 for a two-sided DNE). The
        // CONSECUTIVE-SCALE ratio is immune to the coarse inflation: across one
        // decade of h a genuine odd cusp's mirror difference drops by its power
        // (cube root ⇒ ×0.46, h^0.4 ⇒ ×0.40), while a true jump's stays ≈ flat
        // (ratio → 1). Decline when the finest barely shrank from the next-finest.
        // The FLOOR must clear float cancellation, not just ulp noise: at the
        // finest h a deep-cancellation limit ((eˣ−1−x)/x² → ½) has a NOISE-driven
        // mirror difference that can tick UP (measured dFine ≤ 6e-5, a spurious
        // ratio ≫ 1) — so guard the ratio behind a floor that sits above that noise
        // yet well below a genuine masked jump (dFine ≈ the jump size). But a
        // |value|-relative floor 3e-4·(1+|r|+|l|) INFLATES on a large baseline: at a
        // 1e5–5e5 baseline it reaches 60–300 and swallows a real ~2 mirror-difference,
        // so a masked jump on a huge additive constant slipped (a φ-gate R9 hit:
        // 100000 + sgn(x−2)·(0.5 + 40|x−2|^0.31 + 40|x−2|^0.49) shipped 100000 for a
        // two-sided DNE). The mirror difference CANCELS the common baseline, so its
        // float-cancellation noise tracks the ulp of the baseline, NOT 3e-4·|value| —
        // cap the floor at an absolute 5e-4 (8× above the worst measured cancellation
        // noise ~6e-5, far below any real jump), with a ulp-scaled term that only
        // rises for a contrived ≳1e12 baseline.
        const ratioFloor = Math.min(
          3e-4 * (1 + Math.abs(r.value) + Math.abs(l.value)),
          Math.max(5e-4, 256 * Number.EPSILON * (1 + Math.abs(r.value) + Math.abs(l.value)))
        );
        const dPrev = ds[ds.length - 2];
        if (dFine > ratioFloor && dPrev > 0 && dFine > 0.5 * dPrev) return null; // jump → DNE
      }
    }
    // The tolerance is derived from the sides' actual convergence noise, not a
    // fixed relative one. Two EXACT flat sides (a jump: 1000.04 vs 999.96) have
    // spread≈0 → a ~1e-9 tolerance catches any real jump; genuinely noisy sides
    // scale the tolerance up so a real two-sided limit is not false-declined.
    const tol = Math.max(1e-9, 16 * (r.spread + l.spread));
    if (Math.abs(r.value - l.value) > tol) return null; // sides disagree → DNE
    inner = (r.value + l.value) / 2;
    // Noise = each side's own wiggle PLUS how far the two sides sit apart.
    innerSpread = r.spread + l.spread + Math.abs(r.value - l.value);
  }
  if (inner === null || !Number.isFinite(inner)) return null;

  const value = factor * inner;
  if (!Number.isFinite(value)) return null;

  // The value inherits the inner noise scaled by |factor| (e.g. 2·L doubles it).
  // Snapping is governed ONLY by that noise (see cleanValue): a fixed resolution
  // floor wrongly snapped well-conditioned near-rational limits onto the rational.
  // The point's finiteness picks the snap regime: a FINITE point can carry a
  // genuine ill-conditioned integer snap (an oscillatory squeeze x·sin(1/x) → 0
  // aliases to ~2.6e-6, a cancellation (ln(1+2x)−2x)/x² → −2 lands 2.5e-5 out),
  // so it needs a GENEROUS spread-scaled window; an ∞ point's tail settles cleanly
  // (a genuine integer limit lands ≤ 1e-10 out) so a real few-ppm fractional tail
  // (999999.000007) must be PRESERVED under a tight window.
  const clean = cleanValue(
    value,
    Math.abs(factor) * innerSpread,
    Number.isFinite(limitPoint)
  );
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
