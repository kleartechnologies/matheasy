/**
 * The drawing Numi points at while she explains (spec Part 9 — interactive
 * visuals).
 *
 * The golden rule reaches drawings too, and harder than it reaches prose: a
 * picture is read as fact instantly and can't be hedged. A parabola drawn one
 * unit off, an integral shaded over the wrong interval, a bar showing 3/5 when
 * the fraction is 3/4 — each is a confident wrong answer, just told in pixels.
 *
 * So the model contributes NO numbers. It names a KIND of drawing ("a fraction
 * bar would help here") and nothing else; every coordinate is then derived by
 * this module from the focus LaTeX, which `verifyTutorFocus` has already
 * replaced with the app's own verified copy. If the derivation can't recover
 * the numbers with certainty — the expression isn't the shape it claims, a
 * bound won't evaluate, a denominator is absurd — the sketch is dropped and the
 * turn renders with the equation alone. A missing picture costs a little
 * clarity; a wrong one costs the student the concept.
 *
 * Pure — no Firebase/OpenAI imports — so every derivation is unit-testable.
 */

import {
  latexToAscii,
  normalizeMacros,
  splitEquation,
  variablesIn,
} from "../solver/latex";
import { evalReal } from "../solver/verify";

/**
 * The drawings the client can paint from numbers alone. Each maps to a
 * `VisualConceptKind` the Tier-3 concept painter already knows, so a sketch is
 * rendered by the same code (and looks like) every other drawing in the app.
 */
export const SKETCH_KINDS = [
  /** A partitioned bar: `numerator` of `denominator` shaded. */
  "fraction",
  /** A number line with `value` marked between `min` and `max`. */
  "numberLine",
  /** `y = slope·x + intercept`, with the intercept and root marked. */
  "line",
  /** `y = a·x² + b·x + c`, with the real roots marked. */
  "parabola",
  /** The area under `a·x² + b·x + c` shaded from `from` to `to`. */
  "area",
  /** The unit circle with `angleDegrees` marked, and its sin/cos legs. */
  "unitCircle",
] as const;

export type SketchKind = (typeof SKETCH_KINDS)[number];

const KIND_SET = new Set<string>(SKETCH_KINDS);

export interface TutorSketchOut {
  kind: SketchKind;
  /** Every value derived here from verified maths — never from the model. */
  params: Record<string, number>;
}

/** Longest focus LaTeX worth parsing; matches the focus gate's own cap. */
const MAX_LATEX = 300;

/** Beyond this a coordinate is a bug, not a drawing. */
const MAX_MAGNITUDE = 1e6;

/** How far a sample may drift from the fitted polynomial and still count. */
const FIT_TOL = 1e-6;

/**
 * Derive the sketch for a verified equation.
 *
 * [latex] must already be the app's verified copy (see `verifyTutorFocus`);
 * [requested] is the model's raw kind name, trusted only as far as "which of
 * the six pictures did you have in mind".
 */
export function deriveTutorSketch(
  latex: string,
  requested: unknown
): TutorSketchOut | null {
  const kind = kindName(requested);
  if (!KIND_SET.has(kind)) return null;
  if (!latex || latex.length > MAX_LATEX) return null;

  const source = normalizeMacros(latex);
  const params = derive(kind as SketchKind, source);
  if (!params) return null;

  // One last gate: a non-finite or absurd coordinate would paint nonsense (or
  // nothing) rather than a lesson.
  for (const value of Object.values(params)) {
    if (!Number.isFinite(value) || Math.abs(value) > MAX_MAGNITUDE) return null;
  }
  return { kind: kind as SketchKind, params: rounded(params) };
}

/**
 * The kind the model asked for. A bare name is the documented form, but models
 * mirror output schemas, so `{"kind":"parabola"}` is read the same way — and
 * any numbers it tried to send with it are ignored either way.
 */
function kindName(requested: unknown): string {
  if (typeof requested === "string") return requested.trim();
  if (requested && typeof requested === "object") {
    const { kind } = requested as { kind?: unknown };
    if (typeof kind === "string") return kind.trim();
  }
  return "";
}

function derive(kind: SketchKind, source: string): Record<string, number> | null {
  switch (kind) {
    case "fraction":
      return fraction(source);
    case "numberLine":
      return numberLine(source);
    case "line":
      return line(source);
    case "parabola":
      return parabola(source);
    case "area":
      return area(source);
    case "unitCircle":
      return unitCircle(source);
  }
}

// --- the six derivations ----------------------------------------------------

/** `\frac{3}{4}` → three of four parts shaded. */
function fraction(source: string): Record<string, number> | null {
  const m = source.match(/\\frac\s*\{\s*(-?\d+)\s*\}\s*\{\s*(-?\d+)\s*\}/);
  if (!m) return null;
  const numerator = Number(m[1]);
  const denominator = Number(m[2]);
  // A bar of one cell shows nothing; a bar of fifty is a grey smear. And a
  // negative part-count has no shading to mean.
  if (!Number.isInteger(denominator) || denominator < 2 || denominator > 24) {
    return null;
  }
  if (numerator < 0 || numerator > denominator) return null;
  return { numerator, denominator };
}

/** `x = 4` → a single point on a line, framed to keep zero in view. */
function numberLine(source: string): Record<string, number> | null {
  const ascii = latexToAscii(source);
  const { isEquation, lhs, rhs } = splitEquation(ascii);
  // Either a bare number, or an equation that NAMES a value: one side a lone
  // unknown, the other purely numeric. `x^2 + 8x + 4 = 0` is not that — its
  // right-hand side is a zero, not an answer, and marking it would point the
  // student at the wrong number entirely.
  let value: number | null = null;
  if (!isEquation) {
    value = numericAscii(ascii);
  } else {
    for (const [name, other] of [
      [lhs, rhs],
      [rhs, lhs],
    ]) {
      if (!/^[a-zA-Z]$/.test(name.trim())) continue;
      value = numericAscii(other);
      if (value !== null) break;
    }
  }
  if (value === null) return null;

  // Frame it with room either side, and always include zero: a number line
  // that starts at 3.5 hides the very thing it exists to show — where the
  // value sits relative to nothing.
  const pad = Math.max(1, Math.ceil(Math.abs(value) * 0.6));
  const min = Math.min(0, Math.floor(value - pad));
  const max = Math.max(0, Math.ceil(value + pad));
  if (!(max > min)) return null;
  return { value, min, max };
}

/** `y = 2x + 3` → the straight line it names. */
function line(source: string): Record<string, number> | null {
  const fit = polynomialOf(source);
  if (!fit) return null;
  const { a, b, c } = fit;
  if (Math.abs(a) > FIT_TOL) return null; // curved — that's a parabola
  if (Math.abs(b) < FIT_TOL) return null; // flat — a horizontal line teaches nothing
  // Frame the intercept and the root, with breathing room around both.
  const root = -c / b;
  const span = Math.max(5, Math.abs(root) + 2);
  return { slope: b, intercept: c, xMin: -span, xMax: span };
}

/** `x^2 + 8x + 4 = 0` → the curve whose roots are the answer. */
function parabola(source: string): Record<string, number> | null {
  const fit = polynomialOf(source);
  if (!fit || Math.abs(fit.a) < FIT_TOL) return null;
  return { a: fit.a, b: fit.b, c: fit.c };
}

/** `\int_{0}^{2} x^2 dx` → the region whose area is the answer. */
function area(source: string): Record<string, number> | null {
  const bounds = source.match(
    /\\int\s*_\s*(\{[^{}]*\}|\\?[^\s^{}]+)\s*\^\s*(\{[^{}]*\}|\\?[^\s^{}]+)/
  );
  if (!bounds) return null;
  const from = numericLatex(bounds[1]);
  const to = numericLatex(bounds[2]);
  if (from === null || to === null || !(to > from)) return null;

  // The integrand is what sits between the bounds and the `dx`.
  const rest = source.slice((bounds.index ?? 0) + bounds[0].length);
  const integrand = rest.replace(/\\[,;: ]|\\mathrm|\bd\s*[a-zA-Z]\b.*$/g, "").trim();
  const fit = polynomialOf(integrand);
  if (!fit) return null;
  // Pin the window explicitly. The client sweeps the shading from `from` to
  // `to` as it appears (Part 9: "integrals — animate area"), and a window
  // derived from the bounds would rescale under the animation instead of
  // letting the region fill a fixed frame.
  const pad = Math.max(0.5, (to - from) * 0.25);
  return { a: fit.a, b: fit.b, c: fit.c, from, to, xMin: from - pad, xMax: to + pad };
}

/** `\sin(30^\circ)` → where that angle lands on the unit circle. */
function unitCircle(source: string): Record<string, number> | null {
  // `\sin` or a bare `sin`, both of which the scanner emits. The word boundary
  // keeps `arcsin` from matching as `sin`.
  const m = source.match(
    /(?:\\|\b)(?:sin|cos|tan)\s*(?:\(([^()]*)\)|\{([^{}]*)\}|(-?[\d.]+\s*(?:\^\s*\{?\s*\\circ\s*\}?|°)?))/
  );
  if (!m) return null;
  const arg = (m[1] ?? m[2] ?? m[3] ?? "").trim();
  if (!arg) return null;

  const degreeMarked = /\\circ|°/.test(arg);
  const stripped = arg.replace(/\^\s*\{?\s*\\circ\s*\}?|°/g, "");
  const value = numericLatex(stripped);
  if (value === null) return null;

  // `\sin 30` is degrees in school notation; `\sin(\pi/6)` is radians. The π is
  // the only reliable signal, so a bare number stays degrees.
  const radians = !degreeMarked && /\\?pi/.test(stripped);
  const degrees = radians ? (value * 180) / Math.PI : value;
  if (!Number.isFinite(degrees)) return null;
  // Wrap into a single turn so the drawn arc is the angle a student sees.
  const wrapped = ((degrees % 360) + 360) % 360;
  return { angleDegrees: wrapped };
}

// --- shared machinery -------------------------------------------------------

/**
 * The single-variable function a piece of LaTeX describes, as ascii math.
 *
 * Three readings, in order: a bare expression in one variable; an equation in
 * one variable, which graphs as `lhs - rhs` (so `x^2 + 8x + 4 = 0` draws the
 * curve whose roots are the answer); and `y = f(x)`, where one side is a bare
 * output name. Anything else — two-variable relations, `f(x) = …`, implicit
 * curves — is declined rather than guessed at.
 */
function functionOf(source: string): { expr: string; v: string } | null {
  const ascii = latexToAscii(source).trim();
  if (!ascii) return null;
  const { isEquation, lhs, rhs } = splitEquation(ascii);
  const vars = variablesIn(ascii);

  if (!isEquation) {
    return vars.length === 1 ? { expr: ascii, v: vars[0] } : null;
  }
  if (vars.length === 1) return { expr: `(${lhs}) - (${rhs})`, v: vars[0] };
  if (vars.length === 2) {
    for (const [out, body] of [
      [lhs, rhs],
      [rhs, lhs],
    ]) {
      if (!/^[a-zA-Z]$/.test(out.trim())) continue;
      const bodyVars = variablesIn(body);
      if (bodyVars.length === 1 && bodyVars[0] !== out.trim()) {
        return { expr: body, v: bodyVars[0] };
      }
    }
  }
  return null;
}

/**
 * Recover `a, b, c` of `a·x² + b·x + c` by sampling — the same trick the
 * deterministic quadratic solver uses.
 *
 * Three samples fix a parabola exactly; two more then have to agree, and that
 * is what separates a genuine polynomial from `\sin x`, `1/x` or `e^x`, which
 * would otherwise be drawn as a smooth curve that is simply the wrong shape.
 */
function polynomialOf(
  source: string
): { a: number; b: number; c: number } | null {
  const fn = functionOf(source);
  if (!fn) return null;
  return sample(fn.expr, fn.v);
}

function sample(
  expr: string,
  v: string
): { a: number; b: number; c: number } | null {
  const at = (x: number) => evalReal(expr, { [v]: x });
  const p0 = at(0);
  const p1 = at(1);
  const pm1 = at(-1);
  if ([p0, p1, pm1].some((n) => Number.isNaN(n))) return null;

  const c = p0;
  const a = (p1 + pm1) / 2 - c;
  const b = (p1 - pm1) / 2;

  for (const x of [2, -3]) {
    const actual = at(x);
    if (Number.isNaN(actual)) return null;
    const predicted = a * x * x + b * x + c;
    const scale = Math.max(1, Math.abs(actual));
    if (Math.abs(predicted - actual) > FIT_TOL * scale) return null;
  }
  return { a, b, c };
}

/** A LaTeX fragment (`{2}`, `\pi`, `-1`, `\frac{\pi}{3}`) as a number, or null. */
function numericLatex(fragment: string): number | null {
  let inner = fragment.trim();
  // Only unwrap a group that IS the whole fragment — stripping the trailing
  // brace of `\frac{\pi}{3}` would leave nonsense.
  if (inner.startsWith("{") && inner.endsWith("}")) inner = inner.slice(1, -1);
  return numericAscii(latexToAscii(inner));
}

/** An ascii expression as a number — only when it holds no unknowns. */
function numericAscii(expr: string): number | null {
  const text = expr.trim();
  if (!text) return null;
  if (variablesIn(text).length > 0) return null;
  const value = evalReal(text);
  return Number.isFinite(value) ? value : null;
}

/** Trim floating fuzz so `0.30000000000000004` reaches the client as `0.3`. */
function rounded(params: Record<string, number>): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [key, value] of Object.entries(params)) {
    out[key] = Number(value.toFixed(6));
  }
  return out;
}
