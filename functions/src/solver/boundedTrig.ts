/**
 * Bounded-range trigonometric equation engine — DETERMINISTIC, golden-rule.
 *
 * Solves the exam staple `T(x) = c` on a closed interval `[lo, hi]` (degrees or
 * radians) — e.g. "sin x = 1/2 for 0 ≤ x ≤ 360". It ENUMERATES the closed-form
 * solution family (asin/acos/atan + periodicity), then VERIFIES every candidate
 * by substitution into the ORIGINAL equation (radians) — the same substitution
 * gate the rest of the solver uses. The LLM is never called.
 *
 * Golden-rule safety:
 *  - Correctness of every INCLUDED root is guaranteed: each is re-substituted
 *    into the original equation and dropped unless lhs ≈ rhs.
 *  - COMPLETENESS is guaranteed by the strict shape gate: the equation must be
 *    exactly `A·T(x) + B = C` (one trig term, bare-variable argument, affine in
 *    T(x)), for which the asin/acos/atan families are the complete real
 *    solution set. Any richer shape (sin 2x, sin²x, sin x + cos x, …) DECLINES.
 *  - If a generated in-range candidate fails to verify, the shape/normalization
 *    is inconsistent → DECLINE (never emit a partial set as if complete).
 *  - Unit is only accepted on an explicit signal (° / π) or a textbook-degree
 *    bound; otherwise DECLINE rather than guess degrees-vs-radians.
 *  - An empty in-interval result DECLINES (honest "couldn't verify") rather than
 *    asserting "no solutions".
 */
import { parse } from "mathjs";

import { latexToAscii, normalizeMacros, splitEquation } from "./latex";
import { evalReal, verifySolution, closeEnough } from "./verify";
import { FinalAnswer, MethodData } from "./types";

const TWO_PI = 2 * Math.PI;

export interface BoundedTrigSpec {
  fn: "sin" | "cos" | "tan";
  variable: string;
  /** RHS constant of the normalized `T(x) = c`. */
  c: number;
  /** Interval in radians (what verify + enumeration use). */
  loRad: number;
  hiRad: number;
  /** Endpoint strictness: an OPEN bound (`<`) excludes its endpoint root. */
  loStrict: boolean;
  hiStrict: boolean;
  /** Display unit + the interval in that unit (for the answer + narration). */
  unit: "deg" | "rad";
  loDisplay: number;
  hiDisplay: number;
  /** The ORIGINAL equation (ascii, radian trig) — the substitution gate target. */
  parts: { lhs: string; rhs: string }[];
  /** The cleaned LaTeX of just the equation, for narration. */
  latexEq: string;
}

/** Evaluate a bound sub-expression (e.g. `2\pi`, `\frac{\pi}{2}`, `360`) → real. */
function evalBound(raw: string): number {
  const fixed = raw.replace(/\\sqrt\s*(\d)/g, "\\sqrt{$1}");
  return evalReal(latexToAscii(normalizeMacros(fixed)));
}

/**
 * A bound token: an integer/decimal, a `\frac{…}{…}`, or a π-multiple/fraction
 * (`2\pi`, `\pi`, `\pi/2`, `3\pi/2`). Kept deliberately narrow so interval
 * detection never swallows the equation's own numbers.
 */
const BOUND =
  "(?:\\\\frac\\s*\\{[^{}]*\\}\\s*\\{[^{}]*\\}|" +
  "-?\\d+(?:\\.\\d+)?\\s*\\\\pi(?:\\s*\\/\\s*\\d+)?|" +
  "-?\\\\pi(?:\\s*\\/\\s*\\d+)?|" +
  "-?\\d+(?:\\.\\d+)?)";

interface Interval {
  lo: number;
  hi: number;
  /** Endpoint STRICTNESS: a `<` bound is OPEN (excludes the endpoint), a `≤`/`\le`
   * bound is CLOSED. Losing this shipped spurious endpoint roots — e.g. cos x = 1
   * on the OPEN `0 < x < 360` was answered {0°, 360°} when the true set is empty. */
  loStrict: boolean;
  hiStrict: boolean;
  /** True when a bound literally contained π (a radian signal). */
  sawPi: boolean;
  /** The matched clause, so the caller can strip it off the equation. */
  clause: string;
}

/** True for a STRICT "<"-style relation (open endpoint); false for ≤/\le (closed). */
function isStrictOp(op: string): boolean {
  return op === "<" || op === "\\lt";
}

/** Parse the interval `[lo, hi]` (with per-endpoint open/closed) from the prose, or null. */
function parseInterval(s: string): Interval | null {
  // 0 ≤ x ≤ 360  /  0 < x < 2\pi  — captures BOTH relation ops so we can tell an
  // open bound from a closed one (var: latin OR greek macro).
  const ineq = new RegExp(
    `(${BOUND})\\s*(\\\\le|\\\\leq|\\\\lt|<=|≤|<)\\s*(?:[a-zA-Z]|\\\\[a-zA-Z]+)\\s*(\\\\le|\\\\leq|\\\\lt|<=|≤|<)\\s*(${BOUND})`,
    "i"
  );
  const mi = s.match(ineq);
  if (mi) {
    const lo = evalBound(mi[1]);
    const hi = evalBound(mi[4]);
    if (Number.isFinite(lo) && Number.isFinite(hi) && hi > lo) {
      return {
        lo,
        hi,
        loStrict: isStrictOp(mi[2]),
        hiStrict: isStrictOp(mi[3]),
        sawPi: /\\pi/.test(mi[1]) || /\\pi/.test(mi[4]),
        clause: mi[0],
      };
    }
  }
  // Prose forms are CLOSED (inclusive) by convention.
  const closedPatterns = [
    // between 0 and 360
    new RegExp(`between\\s+(${BOUND})\\s+and\\s+(${BOUND})`, "i"),
    // in the interval/range 0 to 2\pi   /   from 0 to 360
    new RegExp(
      `(?:in\\s+the\\s+(?:interval|range)|from|interval|range)\\s+(${BOUND})\\s+(?:to|and|,)\\s+(${BOUND})`,
      "i"
    ),
  ];
  for (const re of closedPatterns) {
    const m = s.match(re);
    if (!m) continue;
    const lo = evalBound(m[1]);
    const hi = evalBound(m[2]);
    if (!Number.isFinite(lo) || !Number.isFinite(hi) || hi <= lo) continue;
    const sawPi = /\\pi/.test(m[1]) || /\\pi/.test(m[2]);
    return { lo, hi, loStrict: false, hiStrict: false, sawPi, clause: m[0] };
  }
  return null;
}

/** Decide degrees vs radians, or null when genuinely ambiguous (→ decline). */
function detectUnit(s: string, iv: Interval): "deg" | "rad" | null {
  const hasDegreeMark = /°|\\circ|\\degree|\\deg\b|\bdegrees?\b/i.test(s);
  const hasRadianWord = /\bradians?\b/i.test(s);
  if (hasDegreeMark && !iv.sawPi) return "deg";
  if (iv.sawPi || hasRadianWord) return "rad";
  // No explicit marker: accept only a textbook DEGREE bound (a multiple of 45 ≥
  // 90), which is unmistakably degrees. Everything else is ambiguous → decline.
  // Test BOTH endpoints' magnitudes: a negative-range interval like −360 ≤ x ≤ 0
  // has hi = 0, so keying on hi alone misread it as radians and enumerated ~114
  // spurious roots. |lo| = 360 is the unmistakable degree tell.
  const degreeBounds = new Set([90, 135, 180, 270, 360, 450, 540, 720]);
  if (degreeBounds.has(Math.abs(iv.hi)) || degreeBounds.has(Math.abs(iv.lo)))
    return "deg";
  // Radians only when BOTH endpoints sit within one turn (±2π + a hair); a large
  // ambiguous magnitude (e.g. −10 ≤ x ≤ 0) is neither → decline.
  if (Math.abs(iv.lo) <= TWO_PI + 0.05 && Math.abs(iv.hi) <= TWO_PI + 0.05)
    return "rad";
  return null;
}

interface Loose {
  type?: string;
  name?: string;
  op?: string;
  fn?: { name?: string };
  args?: Loose[];
  traverse: (cb: (n: Loose) => void) => void;
}

const SUPPORTED = new Set(["sin", "cos", "tan"]);
const ALL_TRIG = new Set([
  "sin",
  "cos",
  "tan",
  "cot",
  "sec",
  "csc",
  "asin",
  "acos",
  "atan",
]);

/**
 * Confirm the equation is exactly `A·T(x) + B = C` and extract (fn, c). Returns
 * null for any richer shape — that is what keeps the enumeration COMPLETE.
 */
function extractShape(
  lhs: string,
  rhs: string,
  variable: string
): { fn: "sin" | "cos" | "tan"; c: number } | null {
  let root: Loose;
  try {
    root = parse(`(${lhs}) - (${rhs})`) as unknown as Loose;
  } catch {
    return null;
  }

  // Collect trig function nodes + reject any unsupported trig (cot/sec/csc/inverse).
  const trigNodes: Loose[] = [];
  let sawUnsupportedTrig = false;
  root.traverse((n) => {
    if (n.type === "FunctionNode") {
      const name = n.fn?.name ?? "";
      if (SUPPORTED.has(name)) trigNodes.push(n);
      else if (ALL_TRIG.has(name)) sawUnsupportedTrig = true;
    }
  });
  if (sawUnsupportedTrig) return null;
  if (trigNodes.length !== 1) return null;

  const trig = trigNodes[0];
  const fn = (trig.fn?.name ?? "") as "sin" | "cos" | "tan";
  // Its argument must be the BARE variable (rejects sin 2x, sin(x+30), sin(x²)).
  const arg = trig.args?.[0];
  if (!arg || arg.type !== "SymbolNode" || arg.name !== variable) return null;

  // The variable may appear ONLY inside that argument — no bare x elsewhere,
  // and not raised to a power inside another op (sin²x has the trig under `^`).
  let varCount = 0;
  root.traverse((n) => {
    if (n.type === "SymbolNode" && n.name === variable) varCount++;
  });
  if (varCount !== 1) return null;

  // No function may WRAP the trig (or otherwise enclose the variable): the shape
  // must be A·T(x)+B, affine in T(x). `|sin x|` parses to abs(sin(x)); the 3-point
  // affine sample below sits where sin>0, so the abs is invisible and only the +c
  // branch (asin(+c)) is later enumerated — the sin=−c roots (210°, 330°) silently
  // vanish, an INCOMPLETE set shipped verified:true. Any FunctionNode other than
  // the single trig call that contains the variable (abs/sqrt/floor/exp/… of the
  // trig) breaks the affine form → decline. A constant wrapper like √3 is fine
  // (no variable inside), so we reject only wrappers that actually enclose x.
  let wrapsVar = false;
  root.traverse((n) => {
    if (n.type === "FunctionNode" && n !== trig) {
      let hasVar = false;
      (n as Loose).traverse((m) => {
        if (m.type === "SymbolNode" && m.name === variable) hasVar = true;
      });
      if (hasVar) wrapsVar = true;
    }
  });
  if (wrapsVar) return null;

  // A var-containing subexpression raised to ANY power is non-affine — or an abs in
  // disguise. `((tan x − 3)^2)^{1/2}` = |tan x − 3| parses as NESTED `^` OperatorNodes
  // (no FunctionNode), so wrapsVar never sees it, and the affine sampler is fooled when
  // the inner sign never flips across the fixed samples: for |tan x − c| with a large c,
  // tan x > c only in a thin sliver near the asymptote that none of the 6 samples hit,
  // so |tan x − c| looks exactly like c − tan x (affine) and only ONE branch is
  // enumerated — the other (tan x = c + …) silently dropped, an incomplete set shipped
  // verified:true. Reject structurally: any power whose BASE encloses the variable
  // (this also covers (tan x)², (tan x)^{1/2}, √(sin²x)-as-pow, …).
  let varUnderPower = false;
  root.traverse((n) => {
    if (n.type === "OperatorNode" && (n as Loose).op === "^") {
      const base = (n as Loose).args?.[0] as Loose | undefined;
      base?.traverse((m: Loose) => {
        if (m.type === "SymbolNode" && m.name === variable) varUnderPower = true;
      });
    }
  });
  if (varUnderPower) return null;

  // Affine check: E(x) must equal A·T(x) + B. Sample across a FULL period so T(x)
  // takes BOTH signs, solve A,B from the two most-distinct T(x), and confirm the
  // fit at EVERY sample. Sampling both signs is what catches a SIGN-DEPENDENT form
  // the structural gate misses: `(sin²x)^{1/2}` parses as (sin(x)^2)^(1/2) — a
  // power, not a FunctionNode, so `wrapsVar` never sees it — and it equals |sin x|,
  // which fits A·sin x+B perfectly on the old all-positive samples (0.3,0.9,1.7) yet
  // is NOT affine: the sin<0 samples break the fit, so we decline instead of
  // shipping the incomplete +c-only set (210°/330° silently dropped). Ordinary
  // A·T(x)+B fits at every point. (This also rejects sin²x, 1/sin x, e^{sin x}, ….)
  const trigFn = fn === "sin" ? Math.sin : fn === "cos" ? Math.cos : Math.tan;
  const xs = [0.3, 0.9, 1.7, 2.5, 4.0, 5.5];
  const E: number[] = [];
  const U: number[] = [];
  for (const x of xs) {
    const e = evalReal(`(${lhs}) - (${rhs})`, { [variable]: x });
    if (!Number.isFinite(e)) return null;
    E.push(e);
    U.push(trigFn(x));
  }
  // Solve A,B from the pair with the most-distinct T(x) (best-conditioned).
  let i0 = 0;
  let i1 = 1;
  let bestDu = -1;
  for (let a = 0; a < xs.length; a++) {
    for (let b = a + 1; b < xs.length; b++) {
      const d = Math.abs(U[b] - U[a]);
      if (d > bestDu) {
        bestDu = d;
        i0 = a;
        i1 = b;
      }
    }
  }
  if (bestDu < 1e-9) return null;
  const A = (E[i1] - E[i0]) / (U[i1] - U[i0]);
  const B = E[i0] - A * U[i0];
  if (Math.abs(A) < 1e-9) return null; // no real dependence on T(x)
  for (let k = 0; k < xs.length; k++) {
    const predicted = A * U[k] + B;
    if (Math.abs(predicted - E[k]) > 1e-6 * (1 + Math.abs(E[k]))) return null;
  }

  // A·T(x) + B = 0  ⇒  T(x) = -B/A = c
  const c = -B / A;
  if (!Number.isFinite(c)) return null;
  return { fn, c };
}

/** Parse a bounded-range trig equation, or null (→ not our engine). */
export function parseBoundedTrig(rawLatex: string): BoundedTrigSpec | null {
  let s = normalizeMacros(rawLatex);
  // Unwrap \text{…} so prose (for / between / degrees) reads as one string.
  s = s.replace(/\\text\s*\{([^{}]*)\}/g, " $1 ");
  s = s.replace(/[≤]/g, " \\le ").replace(/[≥]/g, " \\ge ");
  // Brace a bare \sqrt argument (\sqrt3 → \sqrt{3}) so it evaluates, not NaN.
  s = s.replace(/\\sqrt\s*(\d)/g, "\\sqrt{$1}");

  // A BRANCH/SELECTOR qualifier (obtuse/acute/reflex/smallest/largest/quadrant)
  // asks for ONE chosen root, not the whole interval set. Leave those to the
  // tutor route — enumerating all roots would over-answer the question.
  if (
    /\b(obtuse|acute|reflex|smallest|largest|first|second|third|fourth|principal)\b/i.test(
      s
    ) ||
    /\bquadrant\b/i.test(s)
  ) {
    return null;
  }

  const iv = parseInterval(s);
  if (!iv) return null;

  const unit = detectUnit(s, iv);
  if (!unit) return null;

  // Strip the interval clause, then the surrounding prose directives, so the
  // equation parse sees only `T(x) = c`. None of these words is a valid math
  // token in a bare trig equation, so removing them globally is safe (done
  // AFTER interval detection, which relies on "for/between/in/to/and").
  const eqRaw = s
    .replace(iv.clause, " ")
    .replace(
      /\b(?:solve|find|calculate|determine|evaluate|work|out|give|state|list|the|equation|all|values?|of|for|where|when|given|such|that|if|please|hence|in|on|over|radians?|degrees?)\b/gi,
      " "
    )
    // Drop spacing macros + stray separators the interval clause left behind
    // (`\tan x = 1, \; …` → `\tan x = 1`), so the equation parses cleanly.
    .replace(/\\(?:quad|qquad|,|;|:|!)/g, " ")
    .replace(/[,;]/g, " ");
  // Must contain exactly one top-level equation.
  const ascii = latexToAscii(eqRaw);
  if ((ascii.match(/=/g) ?? []).length !== 1) return null;
  const { lhs, rhs } = splitEquation(ascii);
  if (!lhs.trim() || !rhs.trim()) return null;

  // The variable is whichever of x/θ/t/etc. sits inside the trig call. Detect it
  // from the trig argument rather than guessing.
  const variable = detectTrigVariable(`(${lhs}) - (${rhs})`);
  if (!variable) return null;

  const shape = extractShape(lhs, rhs, variable);
  if (!shape) return null;

  // Convert the display interval to radians for enumeration + verification.
  const toRad = unit === "deg" ? Math.PI / 180 : 1;
  const loRad = iv.lo * toRad;
  const hiRad = iv.hi * toRad;

  return {
    fn: shape.fn,
    variable,
    c: shape.c,
    loRad,
    hiRad,
    loStrict: iv.loStrict,
    hiStrict: iv.hiStrict,
    unit,
    loDisplay: iv.lo,
    hiDisplay: iv.hi,
    parts: [{ lhs, rhs }],
    latexEq: `${cleanEqLatex(rawLatex)}`,
  };
}

/** The variable inside the single trig call, or null. */
function detectTrigVariable(expr: string): string | null {
  let root: Loose;
  try {
    root = parse(expr) as unknown as Loose;
  } catch {
    return null;
  }
  let variable: string | null = null;
  let count = 0;
  root.traverse((n) => {
    if (n.type === "FunctionNode" && SUPPORTED.has(n.fn?.name ?? "")) {
      count++;
      const arg = n.args?.[0];
      if (arg && arg.type === "SymbolNode" && arg.name) variable = arg.name;
    }
  });
  return count === 1 ? variable : null;
}

/** Just the equation portion of the LaTeX, best-effort, for display. */
function cleanEqLatex(rawLatex: string): string {
  return rawLatex
    .replace(/\\text\s*\{[^{}]*\}/g, " ")
    .replace(/\b(?:for|where|when|given|solve|find)\b/gi, " ")
    .trim();
}

/**
 * Enumerate + verify the solution set on the interval. Returns the answer +
 * method, or null (→ couldn't-verify) when empty or inconsistent.
 */
export function solveBoundedTrig(
  spec: BoundedTrigSpec
): { answer: FinalAnswer; methods: MethodData[] } | null {
  const { fn, c, loRad, hiRad, variable, parts } = spec;

  // sin/cos have no real solution when |c| > 1 — decline honestly.
  if ((fn === "sin" || fn === "cos") && Math.abs(c) > 1 + 1e-9) return null;

  const period = fn === "tan" ? Math.PI : TWO_PI;
  const bases: number[] = [];
  if (fn === "sin") {
    const b = Math.asin(Math.max(-1, Math.min(1, c)));
    bases.push(b, Math.PI - b);
  } else if (fn === "cos") {
    const b = Math.acos(Math.max(-1, Math.min(1, c)));
    bases.push(b, -b);
  } else {
    bases.push(Math.atan(c));
  }

  const eps = 1e-7;
  // Generously bracket the interval with whole periods on both sides.
  const kMin = Math.floor((loRad - period) / period) - 1;
  const kMax = Math.ceil((hiRad + period) / period) + 1;

  const generated: number[] = [];
  for (const base of bases) {
    for (let k = kMin; k <= kMax; k++) {
      generated.push(base + k * period);
    }
  }

  // Respect OPEN endpoints: a strict `<` bound excludes a root sitting ON it, so
  // cos x = 1 on `0 < x < 360` yields {} (not {0°, 360°}) and `0 ≤ x < 360` drops
  // only the 360° copy. A closed bound keeps the endpoint (within eps).
  const inRange = generated.filter((v) => {
    const aboveLo = spec.loStrict ? v > loRad + eps : v >= loRad - eps;
    const belowHi = spec.hiStrict ? v < hiRad - eps : v <= hiRad + eps;
    return aboveLo && belowHi;
  });
  // Dedupe only TRUE coincidences (identical roots reached by two family branches,
  // ~1e-15 apart). The tolerance must stay far below the gap between two DISTINCT
  // near-peak roots — for `sin x = 1−ε` the two solutions sit ~2√(2ε) apart, which
  // for ε≈1e-13 is ~9e-7. A 1e-6 tol would MERGE them into one, hiding the fact that
  // the equation has two roots that both round to the SAME degree string; keeping
  // them separate lets the distinctness guard (below) catch it and decline.
  inRange.sort((a, b) => a - b);
  const deduped: number[] = [];
  for (const v of inRange) {
    if (deduped.length === 0 || Math.abs(v - deduped[deduped.length - 1]) > 1e-9) {
      deduped.push(v);
    }
  }

  // Every in-range generated candidate MUST verify against the ORIGINAL
  // equation; if one does not, the shape/normalization is inconsistent → decline
  // rather than emit a partial (possibly wrong) set.
  const verified: number[] = [];
  for (const v of deduped) {
    if (verifySolution(parts, { [variable]: v })) verified.push(v);
    else return null;
  }
  if (verified.length === 0) return null;

  // Keep FULL precision into the display layer (degrees converted, radians as-is)
  // so the display can choose a precision that STILL satisfies the equation. Early
  // truncation both defeats the π-multiple detector AND — the golden-rule bug a
  // φ-gate caught — can round a tan root onto its asymptote (tan x = 200 has a root
  // at 269.7135°, which 3 s.f. rounds to 270° where tan is UNDEFINED).
  const displayVals = (
    spec.unit === "deg"
      ? verified.map((v) => (v * 180) / Math.PI)
      : verified.slice()
  ).sort((a, b) => a - b);

  const answer = formatSolutions(displayVals, spec.unit, variable, spec.fn, spec.c);
  // A root so pinned against an asymptote that no ≤8-s.f. display re-verifies →
  // decline honestly rather than show a value that doesn't solve the equation.
  if (!answer) return null;
  const methods = buildMethods(spec, displayVals, answer.latex);
  return { answer, methods };
}

/** The trig value at an angle (radians) — for re-checking a DISPLAY rounding. */
function trigValue(fn: "sin" | "cos" | "tan", angleRad: number): number {
  return fn === "sin"
    ? Math.sin(angleRad)
    : fn === "cos"
      ? Math.cos(angleRad)
      : Math.tan(angleRad);
}

/**
 * A displayed angle is safe iff, substituted back, it STILL solves T(x) = c to the
 * SAME tolerance the substitution gate uses everywhere else (`closeEnough`, ABS/REL
 * 1e-4). Anchoring the display check to the verify gate — rather than a looser
 * hand-picked band — closes the gap where a display was "safe" but not actually a
 * solution: the old 3e-3 band still admitted `tan x = −0.002` shown as `180°, 360°`
 * (tan = 0 there, |0−(−0.002)| = 2e-3 < 3e-3) even though 0 ≠ −0.002 under the real
 * gate. A well-conditioned root re-verifies far inside 1e-4 within one extra s.f.
 * (sin/cos are bounded by 1; a tan root away from an asymptote barely moves), so this
 * only bites near an asymptote / for spurious roots, where it FORCES more precision
 * or declines. (Earlier the 50% band let `tan 269°` pass for `tan x = 100`.)
 */
function displaySafe(fn: "sin" | "cos" | "tan", c: number, angleRad: number): boolean {
  const t = trigValue(fn, angleRad);
  return Number.isFinite(t) && closeEnough(t, c);
}

/**
 * The fewest-significant-figures (≥3) decimal string whose value still solves the
 * equation, or null if none up to 8 s.f. does. `toRad` maps the display value back
 * to radians for the safety check. Normal roots keep 3 s.f.; a root hard against a
 * tan asymptote gains just enough precision to stay a valid, verifiable solution.
 */
function safeDecimal(
  v: number,
  fn: "sin" | "cos" | "tan",
  c: number,
  toRad: (shown: number) => number
): string | null {
  for (let p = 3; p <= 8; p++) {
    const shown = Number(v.toPrecision(p));
    if (displaySafe(fn, c, toRad(shown))) return String(shown);
  }
  return null;
}

/** Format a radian value as a π-multiple when clean, else a safe decimal; null if
 * no ≤8-s.f. decimal re-verifies (asymptote-pinned root). */
function formatRadian(
  v: number,
  fn: "sin" | "cos" | "tan",
  c: number
): { latex: string; plain: string } | null {
  if (Math.abs(v) < 1e-9) return { latex: "0", plain: "0" };
  const over = v / Math.PI;
  // k/n · π for small n — an exact root, always a valid solution when it matches.
  for (const den of [1, 2, 3, 4, 6, 8, 12]) {
    const num = over * den;
    const rn = Math.round(num);
    if (rn === 0 || Math.abs(num - rn) > 1e-6) continue;
    // Re-verify the value we'd ACTUALLY SHOW — the π-multiple itself, not the true
    // root v. A root a hair off π/2 (e.g. atan(1e6) ≈ π/2 − 1e-6) snaps to π/2, but
    // tan(π/2) is undefined: checking v would pass while the DISPLAYED π/2 is an
    // asymptote. Verifying the rendered value forces that case down to a safe decimal.
    const rendered = (rn / den) * Math.PI;
    if (!displaySafe(fn, c, rendered)) continue;
    const g = gcd(Math.abs(rn), den);
    const n2 = rn / g;
    const d2 = den / g;
    const numPart = n2 === 1 ? "" : n2 === -1 ? "-" : String(n2);
    if (d2 === 1) return { latex: `${numPart}\\pi`, plain: `${numPart}pi` };
    return {
      latex: `\\tfrac{${numPart}\\pi}{${d2}}`,
      plain: `${numPart}pi/${d2}`,
    };
  }
  const dec = safeDecimal(v, fn, c, (x) => x);
  if (dec === null) return null;
  return { latex: dec, plain: dec };
}

function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

/** Assemble the final answer string in the display unit. Returns null if any root
 * cannot be displayed at a precision that re-verifies (→ caller declines). */
function formatSolutions(
  vals: number[],
  unit: "deg" | "rad",
  variable: string,
  fn: "sin" | "cos" | "tan",
  c: number
): FinalAnswer | null {
  if (unit === "deg") {
    const toRad = (d: number) => (d * Math.PI) / 180;
    const strs: (string | null)[] = vals.map((v) => {
      const r = Math.round(v);
      // Whole degrees when the root is one AND that whole degree still solves it
      // (guards against a rounding that lands on a tan asymptote at 90°/270°).
      if (Math.abs(v - r) <= 1e-6 && displaySafe(fn, c, toRad(r))) return String(r);
      return safeDecimal(v, fn, c, toRad);
    });
    if (strs.some((s) => s === null)) return null;
    // Distinct roots must render to distinct strings. Two roots that collapse to the
    // same display (e.g. a near-peak sin=0.9999999 whose two roots both round to 90°)
    // would show a bogus repeated solution — decline rather than mislead.
    if (new Set(strs as string[]).size !== strs.length) return null;
    const parts = (strs as string[]).map((s) => ({
      latex: `${s}^\\circ`,
      plain: `${s}°`,
    }));
    return {
      latex: parts.map((p) => `${variable} = ${p.latex}`).join(",\\; "),
      plain: parts.map((p) => `${variable} = ${p.plain}`).join(", "),
    };
  }
  const parts = vals.map((v) => formatRadian(v, fn, c));
  if (parts.some((p) => p === null)) return null;
  const ok = parts as { latex: string; plain: string }[];
  // Same distinctness guard for the radian branch.
  if (new Set(ok.map((p) => p.plain)).size !== ok.length) return null;
  return {
    latex: ok.map((p) => `${variable} = ${p.latex}`).join(",\\; "),
    plain: ok.map((p) => `${variable} = ${p.plain}`).join(", "),
  };
}

function buildMethods(
  spec: BoundedTrigSpec,
  vals: number[],
  solutionsLatex: string
): MethodData[] {
  const { fn, c, unit, loDisplay, hiDisplay, variable } = spec;
  const interval =
    unit === "deg"
      ? `${loDisplay}° ≤ ${variable} ≤ ${hiDisplay}°`
      : `${loDisplay} ≤ ${variable} ≤ ${hiDisplay}`;
  return [
    {
      id: "bounded_trig",
      name: "Solve on the interval",
      examPick: true,
      steps: [
        {
          expression: spec.latexEq,
          operation: "The equation to solve",
          why: `Find every ${variable} in ${interval} with ${fn} ${variable} = ${round3(
            c
          )}.`,
        },
        {
          expression: `${variable} = \\text{${fn}}^{-1}(${round3(c)})`,
          operation: "Take the inverse, then add every period in range",
          why: `The inverse gives one base angle; ${
            fn === "tan" ? "adding whole multiples of 180°" : "reflection and adding whole turns"
          } gives every solution in the interval.`,
        },
        {
          expression: solutionsLatex,
          operation: "Solutions in the interval",
          why: `Each value was substituted back into the equation to confirm ${fn} of it equals ${round3(
            c
          )} — ${vals.length} solution${vals.length === 1 ? "" : "s"} in ${interval.replace(
            /≤/g,
            "to"
          )}.`,
        },
      ],
    },
  ];
}

function round3(n: number): string {
  if (Number.isInteger(n)) return String(n);
  return String(Number(n.toPrecision(3)));
}
