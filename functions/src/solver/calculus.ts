/**
 * Applied differentiation — the university/A-level differentiation staples that
 * the bare `\frac{d}{dx}(…)` operator path never saw, because a real problem
 * sheet writes them the OTHER way round: it DEFINES a function ("y = ln(1+x²)")
 * and then asks a question ABOUT its derivative in Leibniz notation ("find
 * dy/dx", "show that dy/dx = …", "find the slope at (0,1)", "classify the
 * stationary points").
 *
 * Before this module those inputs classified as `beyond_solver` — or worse, as a
 * differential equation — so the app declined problems it can answer exactly.
 *
 * Every task here is DETERMINISTIC (mathjs `derivative`) and every answer is
 * proven before it ships, by a check that is INDEPENDENT of the engine that
 * produced it:
 *
 *   • derivative           — `verifyDerivative` (mathjs re-derives + samples)
 *   • show-that identity   — the PRINTED claim must equal the computed derivative
 *                            at many sampled points; a misread digit fails here
 *   • slope / velocity …   — the symbolic derivative's value at the point must
 *                            match a CENTRAL FINITE DIFFERENCE of the original
 *                            function (no symbolic step in common)
 *   • tangent / normal     — the line must pass through the stated point AND its
 *                            gradient must match that same finite difference
 *   • angle of inclination — tan(answer) must reproduce the gradient
 *   • stationary points    — f′ ≈ 0 at each, classified by f″ (or by the sign of
 *                            f′ either side when f″ vanishes), and the set is
 *                            only returned when its COMPLETENESS is provable
 *
 * Anything the strict parse doesn't recognise returns null and falls through the
 * classifier unchanged — this module never widens what the app claims to know.
 */
import { derivative, rationalize, simplify } from "mathjs";

import { exactForm, resymbolize } from "./exact";
import { asciiToLatex, latexToAscii, unwrapProse, variablesIn } from "./latex";
import { evalReal, verifyDerivative } from "./verify";
import { RawStep, SolveCandidate } from "./types";

// --- The parsed request -----------------------------------------------------

/** Which physical quantity a point-evaluation is asking for (picks the wording
 * and the derivative order; the math is identical). */
export type PointLabel = "slope" | "velocity" | "acceleration" | "derivative";

export type CalculusTask =
  /** "find dy/dx" / "find d²y/dx²" — the derivative as an expression. */
  | { kind: "derivative"; order: number }
  /** "show that dy/dx = <claim>" — the answer is printed; we must PROVE it. */
  | { kind: "show_derivative"; order: number; claim: string; claimLatex: string }
  /** "the slope at (0,1)" / "the acceleration at t = 4" — a NUMBER. */
  | {
      kind: "point_derivative";
      order: number;
      at: number;
      atLatex: string;
      /** The y-coordinate the problem printed, when it gave a full point. */
      statedValue?: number;
      label: PointLabel;
    }
  /** "the equation of the tangent/normal to the curve at (1,1)" — a LINE. */
  | {
      kind: "line";
      line: "tangent" | "normal";
      at: number;
      atLatex: string;
      statedValue?: number;
    }
  /** "the angle of inclination of the tangent at (0,1)" — an ANGLE. */
  | { kind: "inclination"; at: number; atLatex: string; statedValue?: number }
  /** "classify the stationary point(s)" — points + max/min/inflection. */
  | { kind: "stationary"; singular: boolean }
  /** "sketch the curve, stating its asymptotes" — the vertical asymptotes plus
   * the horizontal or oblique one the curve approaches at infinity. */
  | { kind: "asymptotes" }
  /** A POLAR curve `r = f(θ)`: the CARTESIAN gradient dy/dx along it. */
  | { kind: "polar_gradient"; at?: number; atLatex?: string }
  /** "find the times at which the particle is at rest" — v = 0, whose answer is
   * usually an infinite PERIODIC FAMILY (`t = 2nπ`), not a finite list. */
  | { kind: "rest_times" }
  /** `x² + xy + y² = 1` → `dy/dx`. The curve is a RELATION, not a function, so
   * `fn` holds `F(x, y)` (the equation moved to one side) rather than a body in
   * one variable. With a point, the gradient THERE — which needs both
   * coordinates, since one x can sit on several branches. */
  | { kind: "implicit_derivative"; at?: number; atLatex?: string; statedValue?: number };

export interface CalculusSpec {
  /** The function body as ascii, in `variable` only. */
  fn: string;
  /** The independent variable (x, t, …). */
  variable: string;
  /** The dependent variable as printed (y, f, s, …) — display only. */
  depVar: string;
  task: CalculusTask;
  /** A stated domain restriction, e.g. "where x > 0". Narrows root search. */
  domain?: { min?: number; max?: number };
}

// --- Parsing ----------------------------------------------------------------

/** Words that end a function body — a directive, a qualifier, or a locator. The
 * body is cut at the first of these at brace/paren depth 0. Every entry is ≥3
 * letters and unambiguous, so a LaTeX macro (`\sin`, `\theta`, `\hat`) can never
 * be mistaken for one. */
const BODY_TERMINATORS = [
  "at", "for", "where", "when", "while", "show", "showing", "find", "determine",
  "calculate", "compute", "classify", "sketch", "obtain", "hence", "then",
  "valid", "and", "with", "given", "verify", "state", "what", "its", "the",
  // The trailing clause a sketching question hangs off the function — "…, stating
  // the asymptotes", "…, giving its turning points". Without these the clause
  // stayed glued to the body and its letters read as extra variables, which made
  // the whole question decline.
  "stating", "giving", "noting", "indicating", "including", "marking",
  "labelling", "labeling", "asymptote", "asymptotes",
  "finding", "determining", "classifying", "locating", "calculating",
  "computing", "showing",
];

/** Cut `s` at the first BODY_TERMINATOR word (or `,`/`.`/`;` followed by one) at
 * depth 0. Returns the LaTeX of the function body. */
function cutBody(s: string): string {
  const terminators = new Set(BODY_TERMINATORS);
  let depth = 0;
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    if (c === "(" || c === "{" || c === "[") depth++;
    else if (c === ")" || c === "}" || c === "]") depth--;
    // A sentence break at depth 0 always ends the body.
    else if (depth <= 0 && (c === "." || c === ";" || c === ":") && !/\d/.test(s[i + 1] ?? "")) {
      return s.slice(0, i);
    } else if (depth <= 0 && /[A-Za-z]/.test(c) && !/[A-Za-z\\]/.test(s[i - 1] ?? "")) {
      const word = /^[A-Za-z]+/.exec(s.slice(i))?.[0] ?? "";
      if (terminators.has(word.toLowerCase())) {
        // Trim a comma/conjunction that introduced the terminator.
        return s.slice(0, i).replace(/[,;\s]+$/, "");
      }
      i += word.length;
      continue;
    }
    i++;
  }
  return s;
}

/** A printed derivative: `\frac{d^2y}{dx^2}`, `dy/dx`, `y''`. */
const DERIV_TOKEN =
  /\\frac\s*\{\s*d(?:[^{}]|\{[^{}]*\})*\}\s*\{\s*d(?:[^{}]|\{[^{}]*\})*\}|(?<![A-Za-z])d\s*(?:\^\s*\{?\d+\}?)?\s*[a-zA-Z]\s*\/\s*d\s*[a-zA-Z]\s*(?:\^\s*\{?\d+\}?)?|(?<![A-Za-z\\])[a-zA-Z]\s*''?/g;

/**
 * True when the `=` starting at `start` belongs to an equation that already
 * contains a derivative — `\frac{d^2y}{dx^2} + 3\frac{dy}{dx} + 2y = x`. That
 * `2y =` looks exactly like a definition, and reading it as one answers
 * "y = x", a question nobody asked. The test is that nothing but math glue
 * (operators, coefficients, brackets) separates the nearest preceding
 * derivative from this term — that is what makes the two summands of a single
 * expression. In "find dy/dx where y = x^2" the words in between say the
 * derivative and the definition are separate clauses, so that still parses.
 */
function inDerivativeEquation(head: string): boolean {
  let last = -1;
  for (const m of head.matchAll(DERIV_TOKEN)) last = (m.index ?? 0) + m[0].length;
  if (last < 0) return false;
  return /^[\s+\-−*/^()\d.,]*$/.test(head.slice(last));
}

/**
 * Find the function DEFINITION — `y = …`, `y(t) = …`, `f(x) = …`, or the
 * textbook-sloppy `\sinh x = …` (sheet 2.1/2.2 defines sinh and then asks for
 * "dy/dx", meaning y = sinh x). Returns the body as ascii plus the printed
 * dependent-variable name. Declines when the body still mentions the dependent
 * variable — that is an implicit relation or an ODE, not a function definition.
 */
function parseDefinition(
  prose: string
): { fn: string; depVar: string; declaredVar: string | null } | null {
  // `y =`, `y(t) =`, `f(x) =` — the `y` must not be glued to a preceding letter
  // or backslash, which is what keeps the `dy` of `dy/dx` from matching.
  const re = /(?<![A-Za-z\\])([a-zA-Z])\s*(?:\(\s*([a-zA-Z])\s*\)\s*)?=/g;
  const candidates: {
    depVar: string;
    declaredVar: string | null;
    index: number;
    start: number;
  }[] = [];
  for (const m of prose.matchAll(re)) {
    // A `d`/`∂` immediately before is a differential, never a function name.
    candidates.push({
      depVar: m[1],
      declaredVar: m[2] ?? null,
      index: (m.index ?? 0) + m[0].length,
      start: m.index ?? 0,
    });
  }
  // The hyperbolic/named-function definition form: `\sinh x = …`.
  const named = /\\?(sinh|cosh|tanh|sin|cos|tan|f|g)\s*\(?\s*([a-zA-Z])\s*\)?\s*=/.exec(prose);
  if (named) {
    candidates.push({
      depVar: named[1],
      declaredVar: named[2],
      index: (named.index ?? 0) + named[0].length,
      start: named.index ?? 0,
    });
  }
  for (const cand of candidates) {
    // A term of a differential equation, not a definition of anything.
    if (inDerivativeEquation(prose.slice(0, cand.start))) continue;
    const bodyLatex = cutBody(prose.slice(cand.index)).trim();
    if (!bodyLatex) continue;
    // Square brackets are grouping in printed math (`\frac12[e^x - e^{-x}]`).
    const fn = latexToAscii(bodyLatex.replace(/\[/g, "(").replace(/\]/g, ")"));
    if (!fn || !/[a-zA-Z0-9]/.test(fn)) continue;
    if (/=/.test(fn)) continue; // ran into another relation — not a clean body
    const vars = variablesIn(fn);
    // The body must not restate the dependent variable (implicit relation / ODE).
    if (vars.includes(cand.depVar)) continue;
    return { fn, depVar: cand.depVar, declaredVar: cand.declaredVar };
  }
  return null;
}

/** The Leibniz operator in the prose: `dy/dx`, `\frac{d^2y}{dx^2}`, `y''`. */
function parseLeibniz(prose: string): { order: number; variable: string } | null {
  const frac =
    /\\frac\s*\{\s*d\s*(?:\^\s*\{?\s*(\d+)\s*\}?)?\s*[a-zA-Z]?\s*\}\s*\{\s*d\s*([a-zA-Z])\s*(?:\^\s*\{?\s*(\d+)\s*\}?)?\s*\}/.exec(
      prose
    );
  if (frac) {
    const order = Number(frac[1] ?? frac[3] ?? 1);
    return { order, variable: frac[2] };
  }
  const slash =
    /(?<![A-Za-z])d\s*(?:\^\s*\{?(\d+)\}?)?\s*[a-zA-Z]?\s*\/\s*d\s*([a-zA-Z])\s*(?:\^\s*\{?(\d+)\}?)?/.exec(
      prose
    );
  if (slash) {
    const order = Number(slash[1] ?? slash[3] ?? 1);
    return { order, variable: slash[2] };
  }
  return null;
}

/** Read a numeric value from LaTeX (`4`, `\pi/4`, `-2`), or NaN. */
function numFrom(latex: string): number {
  return evalReal(latexToAscii(latex));
}

/**
 * The evaluation point. Accepts an ordered pair `at (1, 1)` (x₀ and the stated
 * y₀), or a named assignment `at t = 4` / `at x = 2` / `at \theta = \pi/4`.
 */
function parsePoint(
  prose: string,
  variable: string
): { at: number; atLatex: string; statedValue?: number } | null {
  const pair = /\bat\s+(?:the\s+point\s+)?\(\s*([^(),]+?)\s*,\s*([^(),]+?)\s*\)/i.exec(prose);
  if (pair) {
    const x = numFrom(pair[1]);
    const y = numFrom(pair[2]);
    if (Number.isFinite(x)) {
      return {
        at: x,
        atLatex: pair[1].trim(),
        statedValue: Number.isFinite(y) ? y : undefined,
      };
    }
  }
  const named = new RegExp(
    `\\b(?:at|when|for)\\s+(?:time\\s+)?(?:${variable}|\\\\?${variable})\\s*=\\s*([^,.;]+)`,
    "i"
  ).exec(prose);
  if (named) {
    const raw = named[1].trim().replace(/\s*(seconds?|s|metres?|m|units?)\s*$/i, "");
    const v = numFrom(raw);
    if (Number.isFinite(v)) return { at: v, atLatex: raw };
  }
  return null;
}

/** A stated domain restriction — "where x > 0", "for x > 0". */
function parseDomain(
  prose: string,
  variable: string
): { min?: number; max?: number } | undefined {
  const re = new RegExp(
    `\\b${variable}\\s*(>|<|\\\\geq|\\\\leq|>=|<=|≥|≤)\\s*(-?[0-9.]+)`,
    "i"
  );
  const m = re.exec(prose);
  if (!m) return undefined;
  const v = Number(m[2]);
  if (!Number.isFinite(v)) return undefined;
  return /[<≤]/.test(m[1]) || /leq/.test(m[1]) ? { max: v } : { min: v };
}

/**
 * A polar curve `r = f(θ)` whose question is the CARTESIAN gradient — sheet 3.9
 * ("r = 1 + sin²θ; find dy/dx at θ = π/4"). All three cues are required: the
 * `r =` definition, a body that actually depends on θ, and an ask for dy/dx (not
 * dr/dθ, which is an ordinary derivative and belongs to the parse below).
 */
function parsePolarGradient(prose: string): CalculusSpec | null {
  if (!/\\theta|θ/.test(prose)) return null;
  const m = /(?<![A-Za-z\\])r\s*=\s*/.exec(prose);
  if (!m) return null;
  const bodyLatex = cutBody(prose.slice(m.index + m[0].length)).trim();
  if (!bodyLatex) return null;
  const fn = latexToAscii(bodyLatex.replace(/\[/g, "(").replace(/\]/g, ")"));
  if (!fn || /=/.test(fn)) return null;
  if (!/\btheta\b/.test(fn)) return null; // an r that ignores θ is a circle, not this
  // `variablesIn` treats θ as a reserved angle, so anything it DOES report is a
  // free parameter — and a gradient with a free parameter is a family, not an
  // answer.
  if (variablesIn(fn).length > 0) return null;

  const leibniz = parseLeibniz(prose);
  // dr/dθ is an ordinary derivative; only dy/dx is the polar question.
  if (leibniz && leibniz.variable !== "x") return null;
  const wantsGradient =
    (leibniz && leibniz.variable === "x") ||
    /\bgradient\b|\bslope\b|\bangle\s+of\s+inclination\b/i.test(prose);
  if (!wantsGradient) return null;

  const pt = parsePoint(prose, "theta");
  return {
    fn,
    variable: "theta",
    depVar: "r",
    task: { kind: "polar_gradient", at: pt?.at, atLatex: pt?.atLatex },
  };
}

/** Function names that look like a prose word but are not one. */
const FUNCTION_WORDS =
  /^(?:sin|cos|tan|cot|sec|csc|sinh|cosh|tanh|arcsin|arccos|arctan|log|ln|lg|exp|sqrt|abs)$/i;

/** A run of letters that is ONE symbol, not a product of variables. */
const RESERVED_RUN =
  /^(?:pi|theta|phi|alpha|beta|gamma|delta|lambda|mu|omega|Inf|NaN|sin|cos|tan|cot|sec|csc|sinh|cosh|tanh|asin|acos|atan|acot|asec|acsc|asinh|acosh|atanh|log|log10|ln|exp|sqrt|nthRoot|abs)$/;

/**
 * `x^2 + xy` → `x^2 + x y`. mathjs reads a glued run of letters as ONE symbol
 * and throws "Undefined symbol xy", so the relation evaluated to NaN and the
 * gate declined a curve it can handle perfectly. An implicit relation is the
 * only place two variables sit side by side, which is why this lives here.
 */
function spaceOutProducts(ascii: string): string {
  return ascii.replace(/[a-zA-Z]+/g, (run) =>
    run.length > 1 && !RESERVED_RUN.test(run) ? run.split("").join(" ") : run
  );
}

/** Drop the English lead-in from the front of a math run ("The curve has
 * equation x^2 + xy = 1" → "x^2 + xy = 1"). Only whole multi-letter words go,
 * and never a function name — a single letter is always a variable. */
function trimProseHead(s: string): string {
  let out = s.trim();
  for (;;) {
    const w = /^([A-Za-z]{2,})\b[\s,]*/.exec(out);
    if (!w || FUNCTION_WORDS.test(w[1])) return out;
    out = out.slice(w[0].length);
  }
}

/**
 * An IMPLICIT relation plus a request for its gradient: "The curve has equation
 * x² + xy + y² = 1. Find dy/dx."
 *
 * y is not a function of x here — the relation defines a curve, so the
 * single-variable definition parse below can never see it, and the whole family
 * used to classify as `beyond_solver`. Needs all three cues: a `dy/dx` ask, an
 * equation elsewhere in the prose, and that equation using EXACTLY the two
 * variables the operator names.
 */
function parseImplicit(prose: string): CalculusSpec | null {
  const leibniz = parseLeibniz(prose);
  if (!leibniz || leibniz.order !== 1) return null;
  const depVar =
    /\\frac\s*\{\s*d\s*(?:\^\s*\{?\d+\}?)?\s*([a-zA-Z])\s*\}/.exec(prose)?.[1] ??
    /(?<![A-Za-z])d\s*(?:\^\s*\{?\d+\}?)?\s*([a-zA-Z])\s*\//.exec(prose)?.[1] ??
    null;
  if (!depVar || depVar === leibniz.variable) return null;

  // The operator itself is an equation-looking thing; take it out of the way.
  const body = prose.replace(DERIV_TOKEN, " ");
  // Clauses, split on sentence stops and row breaks (a decimal point is not one).
  for (const clause of body.split(/(?<!\d)\.(?!\d)|[;]|\\\\/)) {
    const parts = clause.split("=");
    if (parts.length !== 2) continue;
    const lhs = spaceOutProducts(latexToAscii(trimProseHead(parts[0])));
    const rhs = spaceOutProducts(
      latexToAscii(cutBody(parts[1]).replace(/[.,;]\s*$/, "").trim())
    );
    if (!lhs || !rhs) continue;
    // `y = f(x)` is an EXPLICIT definition — the ordinary derivative route owns
    // it, and reading it as a relation would answer the same question the long
    // way round while bypassing that route's own checks. `sin y + x² = y` is
    // NOT that: y appears on both sides, so it is still a genuine relation.
    if (lhs === depVar && !variablesIn(rhs).includes(depVar)) continue;
    if (rhs === depVar && !variablesIn(lhs).includes(depVar)) continue;
    const relation = `(${lhs}) - (${rhs})`;
    const vars = variablesIn(relation).sort();
    const want = [depVar, leibniz.variable].sort();
    if (vars.length !== 2 || vars[0] !== want[0] || vars[1] !== want[1]) continue;
    // A relation the gradient can't be read off (unparseable) is caught here,
    // before anything claims an answer.
    if (!Number.isFinite(evalReal(relation, { [depVar]: 0.37, [leibniz.variable]: 0.53 }))) {
      continue;
    }
    const pt = parsePoint(prose, leibniz.variable);
    // An x with no y names a vertical line, not a point on the curve — several
    // branches can cross it with different gradients. Decline rather than pick.
    if (pt && pt.statedValue === undefined) return null;
    return {
      fn: relation,
      variable: leibniz.variable,
      depVar,
      task: { kind: "implicit_derivative", ...(pt ?? {}) },
    };
  }
  return null;
}

/**
 * Parse an applied-differentiation request, or null. Deliberately strict: it
 * needs an explicit function definition AND a recognised ask. Every ambiguous
 * shape declines so the classifier's existing routes are untouched.
 */
export function parseCalculus(rawLatex: string): CalculusSpec | null {
  const prose = unwrapProse(rawLatex);
  // An INTEGRAL, a LIMIT, or a matrix is another engine's problem entirely.
  if (/\\int|∫|\\lim|\\begin\s*\{[pbv]?matrix\}/.test(prose)) return null;

  // A POLAR curve is asked about in two variables at once — it is defined in
  // (r, θ) and the question is about (x, y) — so it can never satisfy the
  // single-variable definition parse below. It gets its own reading.
  const polar = parsePolarGradient(prose);
  if (polar) return polar;

  // Same reason as polar: an implicit relation is stated in TWO variables, so
  // the single-variable definition parse below can never see it.
  const implicit = parseImplicit(prose);
  if (implicit) return implicit;

  const def = parseDefinition(prose);
  if (!def) return null;

  const fnVars = variablesIn(def.fn);
  const leibniz = parseLeibniz(prose);
  // The independent variable: the one the derivative is taken against, else the
  // one declared in `y(t)`, else the single variable the body actually uses.
  const variable =
    leibniz?.variable ??
    def.declaredVar ??
    (fnVars.length === 1 ? fnVars[0] : null) ??
    "";
  if (!variable) return null;
  // A body in MORE than the independent variable carries a free parameter; the
  // gate samples it, but "the tangent at (1,1)" would be a family of lines, not
  // an answer. Single-variable only.
  if (fnVars.length !== 1 || fnVars[0] !== variable) return null;

  const domain = parseDomain(prose, variable);
  const spec = (task: CalculusTask): CalculusSpec => ({
    fn: def.fn,
    variable,
    depVar: def.depVar,
    task,
    domain,
  });

  // --- stationary points ---------------------------------------------------
  // The participle forms matter: a sketching question asks for them as a
  // trailing clause ("…, finding its stationary points"), and `\bfind\b` does
  // not match "finding".
  const stationary =
    /\b(?:classif(?:y|ying)|find(?:ing)?|determin(?:e|ing)|locat(?:e|ing))\b[^.]*\b(stationary|turning|critical)\s+point/i.exec(
      prose
    );
  if (stationary) {
    return spec({ kind: "stationary", singular: /point\b(?!s)/i.test(stationary[0]) });
  }

  // --- asymptotes / curve sketching -----------------------------------------
  // "Sketch the curve y = (x+1)/(x-2), stating the equations of its asymptotes."
  // Below the stationary block on purpose: a sketch that ALSO asks for the
  // turning points is answered as turning points, which is the harder half.
  if (
    /\basymptot/i.test(prose) ||
    /\bsketch\b[^.]*\b(?:curve|graph)\b/i.test(prose)
  ) {
    return spec({ kind: "asymptotes" });
  }

  // --- tangent / normal LINE ------------------------------------------------
  const line = /\bequation\s+of\s+the\s+(tangent|normal)\b/i.exec(prose);
  if (line) {
    const pt = parsePoint(prose, variable);
    if (!pt) return null;
    return spec({
      kind: "line",
      line: line[1].toLowerCase() as "tangent" | "normal",
      ...pt,
    });
  }

  // --- angle of inclination -------------------------------------------------
  if (/\bangle\s+of\s+inclination\b/i.test(prose)) {
    const pt = parsePoint(prose, variable);
    if (!pt) return null;
    return spec({ kind: "inclination", ...pt });
  }

  // --- "when is the particle at rest?" --------------------------------------
  // v = 0 solved for t. Ahead of the kinematics branch below, which needs a
  // stated time; this is the question that ASKS for the times. Only when no time
  // is stated, so "the velocity at t = 2" still takes its own route.
  if (
    (/\b(?:at|to)\s+rest\b/i.test(prose) ||
      /\bvelocity\s+is\s+zero\b/i.test(prose) ||
      /\binstantaneously\s+stationary\b/i.test(prose)) &&
    !parsePoint(prose, variable)
  ) {
    return spec({ kind: "rest_times" });
  }

  // --- kinematics: velocity / acceleration at a time ------------------------
  const kinematic = /\b(acceleration|velocity|speed)\b/i.exec(prose);
  if (kinematic) {
    const pt = parsePoint(prose, variable);
    if (!pt) return null;
    const word = kinematic[1].toLowerCase();
    const order = word === "acceleration" ? 2 : 1;
    return spec({
      kind: "point_derivative",
      order,
      label: order === 2 ? "acceleration" : "velocity",
      ...pt,
    });
  }

  // --- slope / gradient at a point ------------------------------------------
  if (/\b(slope|gradient)\b/i.test(prose)) {
    const pt = parsePoint(prose, variable);
    if (!pt) return null;
    return spec({ kind: "point_derivative", order: 1, label: "slope", ...pt });
  }

  // Everything below is about the derivative itself, so it needs the operator.
  if (!leibniz) return null;
  const order = leibniz.order;
  if (order < 1 || order > 8) return null;

  // --- "show that dy/dx = <claim>" ------------------------------------------
  // The claim is what follows the Leibniz operator's `=`. It is the ANSWER the
  // sheet printed; the engine must reproduce it, never assume it.
  const opIndex = prose.search(
    /\\frac\s*\{\s*d[^{}]*\}\s*\{\s*d[^{}]*\}|(?<![A-Za-z])d\s*(?:\^\s*\{?\d+\}?)?\s*[a-zA-Z]?\s*\/\s*d\s*[a-zA-Z]/
  );
  if (/\bshow\s+that\b|\bverify\s+that\b|\bprove\s+that\b/i.test(prose) && opIndex >= 0) {
    const after = prose.slice(opIndex);
    const eq = after.indexOf("=");
    if (eq !== -1) {
      const claimLatex = cutBody(after.slice(eq + 1)).replace(/[.,;]\s*$/, "").trim();
      const claim = latexToAscii(claimLatex.replace(/\[/g, "(").replace(/\]/g, ")"));
      if (claim && !/=/.test(claim)) {
        return spec({ kind: "show_derivative", order, claim, claimLatex });
      }
    }
  }

  // --- plain "find dy/dx" ----------------------------------------------------
  if (/\b(find|determine|calculate|compute|obtain|evaluate)\b/i.test(prose)) {
    // A derivative asked AT a point is a point-evaluation, not an expression.
    const pt = parsePoint(prose, variable);
    if (pt) {
      return spec({ kind: "point_derivative", order, label: "derivative", ...pt });
    }
    return spec({ kind: "derivative", order });
  }
  return null;
}

// --- Solving ----------------------------------------------------------------

/** The nth derivative of `fn` as ascii, plus the (n−1)th (the verify anchor). */
function differentiate(
  fn: string,
  variable: string,
  order: number
): { d: string; penult: string } | null {
  let penult = fn;
  try {
    for (let k = 0; k < order - 1; k++) {
      penult = derivative(penult, variable).toString();
    }
    return { d: derivative(penult, variable).toString(), penult };
  } catch {
    return null;
  }
}

/**
 * A CENTRAL FINITE DIFFERENCE of the original function at `a` — the independent
 * check for every point-evaluation. It never touches mathjs's symbolic
 * derivative, so a symbolic slip cannot verify itself. Richardson-extrapolated
 * over two step sizes so smooth functions match to ~1e-9.
 */
function finiteDifference(
  fn: string,
  variable: string,
  a: number,
  order: number
): number {
  const d1 = (h: number): number => {
    const f = (x: number) => evalReal(fn, { [variable]: x });
    return (f(a + h) - f(a - h)) / (2 * h);
  };
  const d2 = (h: number): number => {
    const f = (x: number) => evalReal(fn, { [variable]: x });
    return (f(a + h) - 2 * f(a) + f(a - h)) / (h * h);
  };
  if (order === 1) {
    const h = 1e-4;
    // Richardson: (4·D(h/2) − D(h)) / 3 cancels the leading O(h²) error term.
    return (4 * d1(h / 2) - d1(h)) / 3;
  }
  if (order === 2) {
    const h = 1e-3;
    return (4 * d2(h / 2) - d2(h)) / 3;
  }
  return NaN;
}

/** Loose agreement, scaled to magnitude — finite differences carry real error. */
function agrees(a: number, b: number, tol = 1e-5): boolean {
  if (!Number.isFinite(a) || !Number.isFinite(b)) return false;
  return Math.abs(a - b) <= tol * Math.max(1, Math.abs(a), Math.abs(b));
}

/**
 * Format a real for display, preserving EXACT form wherever one exists — a
 * tangent gradient of −¼ must read `-\frac{1}{4}`, not `-0.25`. Tries a
 * recognisable closed form (π, √n, …) first, then a small-denominator rational,
 * and only then falls back to a rounded decimal.
 */
function niceValue(v: number): { latex: string; plain: string } {
  // A root recovered by bisection lands within ~1e-13 of the true value, never
  // exactly on it, so an integer root arrives as 0.9999999999999. Snap it, or
  // every stationary point would read as a fraction.
  if (Math.abs(v - Math.round(v)) < 1e-9) {
    const r = Math.round(v) + 0; // +0 normalises -0 to 0
    return { latex: String(r), plain: String(r) };
  }
  const exact = exactForm(v);
  if (exact) return { latex: exact.latex, plain: exact.plain };
  const rational = asRational(v);
  if (rational) {
    const { n, d } = rational;
    const sign = n < 0 ? "-" : "";
    return {
      latex: `${sign}\\frac{${Math.abs(n)}}{${d}}`,
      plain: `${n}/${d}`,
    };
  }
  const s = String(Number(v.toFixed(6)));
  return { latex: s, plain: s };
}

/** `v` as a fraction with a denominator ≤ 64, exactly — else null. */
function asRational(v: number): { n: number; d: number } | null {
  for (let d = 2; d <= 64; d++) {
    const n = v * d;
    if (Math.abs(n - Math.round(n)) < 1e-12) {
      const r = Math.round(n);
      // Reduce, so 2/4 never ships as 2/4.
      const g = gcd(Math.abs(r), d);
      const den = d / g;
      // Reduced to a whole number — the integer branch above already covers it.
      if (den === 1) return null;
      return { n: r / g, d: den };
    }
  }
  return null;
}

function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

/** `\frac{dy}{dx}` / `\frac{d^2y}{dx^2}` for display. */
function opLatex(depVar: string, variable: string, order: number): string {
  return order > 1
    ? `\\frac{d^{${order}}${depVar}}{d${variable}^{${order}}}`
    : `\\frac{d${depVar}}{d${variable}}`;
}

/** The same operator in the screen-reader / copy-paste form. It must carry the
 * ORDER too — a second derivative announced as "dy/dx" is a wrong statement. */
function opPlain(depVar: string, variable: string, order: number): string {
  return order > 1
    ? `d^${order}${depVar}/d${variable}^${order}`
    : `d${depVar}/d${variable}`;
}

export function solveCalculus(cls: { calculus?: CalculusSpec }): SolveCandidate | null {
  const spec = cls.calculus;
  if (!spec) return null;
  switch (spec.task.kind) {
    case "derivative":
      return solveDerivativeExpression(spec, spec.task.order);
    case "show_derivative":
      return solveShowDerivative(spec, spec.task);
    case "point_derivative":
      return solvePointDerivative(spec, spec.task);
    case "line":
      return solveLine(spec, spec.task);
    case "inclination":
      return solveInclination(spec, spec.task);
    case "stationary":
      return solveStationary(spec, spec.task);
    case "asymptotes":
      return solveAsymptotes(spec);
    case "polar_gradient":
      return solvePolarGradient(spec, spec.task);
    case "rest_times":
      return solveRestTimes(spec);
    case "implicit_derivative":
      return solveImplicitDerivative(spec, spec.task);
  }
}

// --- implicit differentiation -------------------------------------------------

/**
 * `dy/dx` for a curve given as a relation `F(x, y) = 0`.
 *
 * Differentiating term by term gives `F_x + F_y · y′ = 0`, so `y′ = −F_x/F_y`.
 * That is a symbolic route, so it proves nothing on its own — the gate here
 * never touches `F_x` or `F_y`. It walks the CURVE numerically instead: at
 * several x it bisects `F(x, ·) = 0` for a y ON the curve, then re-bisects at
 * `x ± h` inside a small bracket around that y and takes a central difference of
 * the branch. Only F is ever evaluated, so a mis-differentiation cannot hide.
 * Points where `F_y ≈ 0` (a vertical tangent) are skipped rather than fudged,
 * and fewer than three surviving checks means no answer ships.
 */
function solveImplicitDerivative(
  spec: CalculusSpec,
  task: Extract<CalculusTask, { kind: "implicit_derivative" }>
): SolveCandidate | null {
  const x = spec.variable;
  const y = spec.depVar;
  const F = spec.fn;
  let Fx: string;
  let Fy: string;
  let dydx: string;
  try {
    Fx = derivative(F, x).toString();
    Fy = derivative(F, y).toString();
    dydx = simplify(`-(${Fx})/(${Fy})`).toString();
  } catch {
    return null;
  }
  // A y that has fallen out of F_y entirely means y never really appeared.
  if (!variablesIn(`(${Fy})`).includes(y)) return null;

  const op = `\\frac{d${y}}{d${x}}`;
  const opPlainStr = `d${y}/d${x}`;
  const shown = resymbolize(dydx);

  const proved = (): boolean => {
    let checks = 0;
    for (const x0 of [0.31, -0.73, 1.13, -1.47, 0.57, 1.91, -0.19, 2.37]) {
      for (const y0 of curveBranches(F, x, y, x0)) {
        const slope = evalReal(dydx, { [x]: x0, [y]: y0 });
        const fy = evalReal(Fy, { [x]: x0, [y]: y0 });
        // A vertical tangent has no finite gradient — not a counterexample.
        if (!Number.isFinite(slope) || !Number.isFinite(fy) || Math.abs(fy) < 1e-3) continue;
        const h = 1e-4;
        const yPlus = branchNear(F, x, y, x0 + h, y0);
        const yMinus = branchNear(F, x, y, x0 - h, y0);
        if (yPlus === null || yMinus === null) continue;
        const fd = (yPlus - yMinus) / (2 * h);
        if (!Number.isFinite(fd)) continue;
        if (Math.abs(fd - slope) > 1e-3 * (1 + Math.abs(slope))) return false;
        checks++;
      }
    }
    return checks >= 3;
  };
  if (!proved()) return null;

  const steps: RawStep[] = [
    {
      ascii: `${F} = 0`,
      latex: `${asciiToLatex(resymbolize(F))} = 0`,
      operationCode: "IDENTIFY_FUNCTION",
    },
    {
      // Every term differentiated with respect to x, y treated as y(x) — the
      // chain rule is what puts dy/dx beside the y-terms.
      ascii: `${resymbolize(Fx)} + (${resymbolize(Fy)})·${opPlainStr} = 0`,
      latex: `${asciiToLatex(resymbolize(Fx))} + \\left(${asciiToLatex(
        resymbolize(Fy)
      )}\\right)${op} = 0`,
      operationCode: "DIFFERENTIATE",
    },
    {
      ascii: `${opPlainStr} = ${shown}`,
      latex: `${op} = ${asciiToLatex(shown)}`,
      operationCode: "SOLVE_FOR_DERIVATIVE",
    },
  ];

  if (task.statedValue === undefined || task.at === undefined) {
    return {
      answer: { latex: `${op} = ${asciiToLatex(shown)}`, plain: `${opPlainStr} = ${shown}` },
      methods: [
        { id: "implicit", name: "Differentiate implicitly", examPick: true, steps },
      ],
      verify: proved,
    };
  }

  // At a stated point — which must actually LIE on the curve, or the question
  // itself is inconsistent and no gradient there means anything.
  const x0 = task.at;
  const y0 = task.statedValue;
  const scale = Math.max(1, Math.abs(evalReal(F, { [x]: x0 + 1, [y]: y0 + 1 })) || 1);
  if (Math.abs(evalReal(F, { [x]: x0, [y]: y0 })) > 1e-9 * scale) return null;
  const at = evalReal(dydx, { [x]: x0, [y]: y0 });
  if (!Number.isFinite(at)) return null;
  const nice = niceValue(at);
  const pointLatex = `\\left(${task.atLatex ?? x0}, ${niceValue(y0).latex}\\right)`;
  steps.push({
    ascii: `${opPlainStr} at (${x0}, ${y0}) = ${nice.plain}`,
    latex: `\\left.${op}\\right|_{${pointLatex}} = ${nice.latex}`,
    operationCode: "RESULT",
  });
  return {
    answer: { latex: nice.latex, plain: nice.plain },
    methods: [{ id: "implicit", name: "Differentiate implicitly", examPick: true, steps }],
    // The general expression still has to survive its own gate, and the point
    // value has to match a finite difference of the branch through it.
    verify: () => {
      if (!proved()) return false;
      const h = 1e-4;
      const yPlus = branchNear(F, x, y, x0 + h, y0);
      const yMinus = branchNear(F, x, y, x0 - h, y0);
      if (yPlus === null || yMinus === null) return false;
      return Math.abs((yPlus - yMinus) / (2 * h) - at) <= 1e-3 * (1 + Math.abs(at));
    },
  };
}

/** Every y with `F(x0, y) = 0` found by a sign-change scan of [-6, 6]. */
function curveBranches(F: string, x: string, y: string, x0: number): number[] {
  const f = (t: number) => evalReal(F, { [x]: x0, [y]: t });
  const out: number[] = [];
  const N = 600;
  let prev = f(-6);
  for (let i = 1; i <= N; i++) {
    const b = -6 + (12 * i) / N;
    const cur = f(b);
    if (Number.isFinite(prev) && Number.isFinite(cur) && ((prev < 0) !== (cur < 0))) {
      const r = bisect(f, b - 12 / N, b);
      if (r !== null) out.push(r);
    }
    prev = cur;
  }
  return out;
}

/** The y on the SAME branch as `guess` solving `F(x1, y) = 0`, or null. */
function branchNear(
  F: string,
  x: string,
  y: string,
  x1: number,
  guess: number
): number | null {
  const f = (t: number) => evalReal(F, { [x]: x1, [y]: t });
  for (const w of [1e-3, 1e-2, 1e-1]) {
    const a = f(guess - w);
    const b = f(guess + w);
    if (Number.isFinite(a) && Number.isFinite(b) && (a < 0) !== (b < 0)) {
      return bisect(f, guess - w, guess + w);
    }
  }
  return null;
}

// --- when is it at rest? ------------------------------------------------------

/**
 * The times at which v = ds/dt is zero.
 *
 * The existing stationary-point route can't answer this: it proves completeness
 * from a POLYNOMIAL degree, and a particle on `s = t + cos t` is at rest at
 * `t = 2nπ` — infinitely many times, so it declined a question with a perfectly
 * ordinary answer.
 *
 * So the completeness argument here is periodicity instead. When the velocity is
 * provably periodic with period P (checked by sampling f(t) against f(t+P) and
 * f(t+2P) across a wide window), the whole solution set is the roots inside ONE
 * period repeated forever — and those roots are complete because a dense scan of
 * that period finds no near-zero that isn't already on the list, which is what
 * catches a root the sign-change search would step over.
 *
 * Every member of the family is then substituted back: |v| must vanish at
 * `r + nP` for several n, confirmed independently by a finite difference of the
 * ORIGINAL displacement.
 */
function solveRestTimes(spec: CalculusSpec): SolveCandidate | null {
  const v = spec.variable;
  const d1 = differentiate(spec.fn, v, 1);
  if (!d1) return null;

  const period = fundamentalPeriod(d1.d, v);
  const roots = period
    ? rootsInWindow(d1.d, v, 0, period)
    : findRoots(d1.d, v, spec.domain);
  if (roots === null || roots.length === 0) return null;

  if (!period) {
    // No periodicity to lean on — fall back to the polynomial degree bound, the
    // only other way this set is provably complete.
    const degree = polynomialDegree(d1.d, spec.variable);
    if (degree === null || roots.length < degree) return null;
  }

  const proved = (): boolean => {
    if (!verifyDerivative(spec.fn, d1.d, v)) return false;
    const ns = period ? [-2, -1, 0, 1, 2, 3] : [0];
    for (const r of roots) {
      for (const n of ns) {
        const t = r + n * (period ?? 0);
        const vel = evalReal(d1.d, { [v]: t });
        const fd = finiteDifference(spec.fn, v, t, 1);
        if (!Number.isFinite(vel) || Math.abs(vel) > 1e-7) return false;
        if (!Number.isFinite(fd) || Math.abs(fd) > 1e-5) return false;
      }
    }
    return true;
  };
  if (!proved()) return null;

  const family = roots.map((r) => ({
    latex: `${v} = ${familyLatex(r, period)}`,
    plain: `${v} = ${familyPlain(r, period)}`,
  }));
  const tail = period ? ",\\quad n \\in \\mathbb{Z}" : "";
  const tailPlain = period ? " for every integer n" : "";

  const steps: RawStep[] = [
    {
      ascii: `${spec.depVar} = ${spec.fn}`,
      latex: `${spec.depVar} = ${asciiToLatex(spec.fn)}`,
      operationCode: "IDENTIFY_FUNCTION",
    },
    {
      ascii: `v = d${spec.depVar}/d${v} = ${resymbolize(d1.d)}`,
      latex: `v = ${opLatex(spec.depVar, v, 1)} = ${asciiToLatex(resymbolize(d1.d))}`,
      operationCode: "DIFFERENTIATE",
    },
    {
      ascii: `${resymbolize(d1.d)} = 0`,
      latex: `${asciiToLatex(resymbolize(d1.d))} = 0`,
      operationCode: "SET_DERIVATIVE_ZERO",
    },
    ...(period
      ? [
          {
            ascii: `v has period ${niceValue(period).plain}`,
            latex: `\\text{the velocity has period } ${niceValue(period).latex}`,
            operationCode: "PERIODICITY",
          } as RawStep,
        ]
      : []),
    {
      ascii: family.map((f) => f.plain).join(", ") + tailPlain,
      latex: family.map((f) => f.latex).join(",\\; ") + tail,
      operationCode: "RESULT",
    },
  ];

  return {
    answer: {
      latex: family.map((f) => f.latex).join(",\\; ") + tail,
      plain: family.map((f) => f.plain).join(", ") + tailPlain,
    },
    methods: [{ id: "at_rest", name: "Solve v = 0", examPick: true, steps }],
    roots,
    plotExpression: spec.fn,
    verify: proved,
  };
}

/** `r + nP` as LaTeX, in exact π terms wherever the numbers allow it. */
function familyLatex(r: number, period: number | null): string {
  if (period === null) return niceValue(r).latex;
  const term = periodTermLatex(period);
  if (Math.abs(r) < 1e-9) return term;
  return `${niceValue(r).latex} + ${term}`;
}

function familyPlain(r: number, period: number | null): string {
  if (period === null) return niceValue(r).plain;
  const term = periodTermPlain(period);
  if (Math.abs(r) < 1e-9) return term;
  return `${niceValue(r).plain} + ${term}`;
}

/** `P` written as a multiple of n — `2n\pi`, `\frac{n\pi}{2}`, `3n`. */
function periodTermLatex(P: number): string {
  const pr = piRational(P);
  if (!pr) return `${niceValue(P).latex}n`;
  const { n, d } = pr;
  const head = n === 1 ? "n\\pi" : `${n}n\\pi`;
  return d === 1 ? head : `\\frac{${head}}{${d}}`;
}

function periodTermPlain(P: number): string {
  const pr = piRational(P);
  if (!pr) return `${niceValue(P).plain}n`;
  const { n, d } = pr;
  const head = n === 1 ? "nπ" : `${n}nπ`;
  return d === 1 ? head : `${head}/${d}`;
}

/** `v = n·π/d` with small whole n, d — or null when v isn't a rational multiple
 * of π at all. */
function piRational(v: number): { n: number; d: number } | null {
  const k = v / Math.PI;
  for (let d = 1; d <= 12; d++) {
    const n = k * d;
    if (Math.abs(n - Math.round(n)) < 1e-9) {
      const r = Math.round(n);
      if (r <= 0) return null;
      const g = gcd(r, d);
      return { n: r / g, d: d / g };
    }
  }
  return null;
}

/**
 * The smallest period of `expr`, or null. Candidates are the rational multiples
 * of π and the small whole numbers — the periods a problem sheet actually has —
 * and each is confirmed against f(t+P) AND f(t+2P) at 30+ scattered points, so a
 * near-miss can't pass. A CONSTANT expression is refused: everything is a period
 * of it, and "at rest at t = anything" is not the shape of this answer.
 */
function fundamentalPeriod(expr: string, variable: string): number | null {
  const f = (x: number) => evalReal(expr, { [variable]: x });
  const probes: number[] = [];
  for (let i = 0; i < 80; i++) {
    const x = -8 + i * 0.2137;
    if (Number.isFinite(f(x))) probes.push(x);
  }
  if (probes.length < 40) return null;
  const values = probes.map(f);
  const scale = Math.max(1, ...values.map(Math.abs));
  const spread = Math.max(...values) - Math.min(...values);
  if (spread < 1e-6 * scale) return null; // constant — no fundamental period

  const candidates: number[] = [];
  for (let k = 1; k <= 16; k++) {
    for (const d of [1, 2, 3, 4, 6]) candidates.push((k * Math.PI) / d);
  }
  for (let k = 1; k <= 24; k++) candidates.push(k);
  candidates.sort((a, b) => a - b);

  for (const P of candidates) {
    if (P < 1e-3) continue;
    let ok = true;
    for (let i = 0; i < probes.length; i++) {
      const a = values[i];
      const b = f(probes[i] + P);
      const c = f(probes[i] + 2 * P);
      if (!Number.isFinite(b) || !Number.isFinite(c)) {
        ok = false;
        break;
      }
      if (Math.abs(a - b) > 1e-9 * scale || Math.abs(a - c) > 1e-9 * scale) {
        ok = false;
        break;
      }
    }
    if (ok) return P;
  }
  return null;
}

/**
 * The roots of `expr` in `[lo, hi)`, refusing (null) unless the set is provably
 * complete over that interval.
 *
 * A sign-change search on its own is the wrong tool here, and the reason is the
 * whole point of the question: a particle at rest is usually at a TOUCH point.
 * `s = t − sin t` gives `v = 1 − cos t ≥ 0`, which reaches zero at `t = 2nπ`
 * without ever changing sign, so a crossing search finds nothing and the answer
 * that the sheet prints would be missed entirely.
 *
 * So this scans for local minima of |f| as well as for crossings, refines each by
 * ternary search, and then re-scans densely: any sample sitting near zero that
 * isn't near a listed root means the list is incomplete, and an incomplete list
 * is a wrong answer, not a partial one — decline.
 */
function rootsInWindow(
  expr: string,
  variable: string,
  lo: number,
  hi: number
): number[] | null {
  const f = (x: number) => evalReal(expr, { [variable]: x });
  const N = 6000;
  const width = (hi - lo) / N;
  const xs: number[] = [];
  const ys: number[] = [];
  for (let i = 0; i <= N; i++) {
    const x = lo + i * width;
    const y = f(x);
    if (!Number.isFinite(y)) return null;
    xs.push(x);
    ys.push(y);
  }
  const scale = Math.max(...ys.map(Math.abs));
  if (!(scale > 0)) return null; // identically zero — "at rest always", not this

  const roots: number[] = [];
  const add = (raw: number) => {
    if (!Number.isFinite(raw)) return;
    // Wrap into `[lo, hi)`. A root on the far edge is the same point as one at
    // `lo` a period earlier, and a ternary search across the flat bottom of a
    // touch point can settle a hair outside the window — both are the same root.
    let r = raw;
    if (r >= hi - 1e-6) r -= hi - lo;
    if (r < lo && r > lo - 1e-6) r = lo;
    if (r < lo || r >= hi) return;
    if (Math.abs(f(r)) > 1e-8 * scale) return;
    if (roots.some((q) => Math.abs(q - r) < 1e-6)) return;
    roots.push(r);
  };
  for (let i = 1; i <= N; i++) {
    if ((ys[i - 1] < 0 && ys[i] > 0) || (ys[i - 1] > 0 && ys[i] < 0)) {
      const r = bisect(f, xs[i - 1], xs[i]);
      if (r !== null) add(r);
    }
    // A local minimum of |f| that dips near zero is a touch point.
    if (i < N && Math.abs(ys[i]) <= Math.abs(ys[i - 1]) && Math.abs(ys[i]) <= Math.abs(ys[i + 1])) {
      if (Math.abs(ys[i]) < 1e-3 * scale) add(minimizeAbs(f, xs[i - 1], xs[i + 1]));
    }
  }
  // The endpoints are minima the interior loop never examines.
  if (Math.abs(ys[0]) < 1e-3 * scale) add(minimizeAbs(f, lo - width, lo + width));
  if (Math.abs(ys[N]) < 1e-3 * scale) add(minimizeAbs(f, hi - width, hi + width));

  for (let i = 0; i <= N; i++) {
    if (Math.abs(ys[i]) >= 1e-6 * scale) continue;
    const near = roots.some(
      (r) => Math.abs(r - xs[i]) < 4 * width || Math.abs(r + (hi - lo) - xs[i]) < 4 * width
    );
    if (!near) return null;
  }
  return roots.sort((a, b) => a - b);
}

/** The x minimising |f| on `[a, b]` — ternary search, which needs no derivative
 * and doesn't care that |f| has a corner at the root. */
function minimizeAbs(f: (x: number) => number, a: number, b: number): number {
  let lo = a;
  let hi = b;
  for (let k = 0; k < 200; k++) {
    const m1 = lo + (hi - lo) / 3;
    const m2 = hi - (hi - lo) / 3;
    if (Math.abs(f(m1)) <= Math.abs(f(m2))) hi = m2;
    else lo = m1;
  }
  return (lo + hi) / 2;
}

// --- dy/dx along a polar curve -----------------------------------------------

/**
 * `r = f(θ)` in cartesian terms is x = r cos θ, y = r sin θ, so
 *
 *      dy/dx = (r′ sin θ + r cos θ) / (r′ cos θ − r sin θ).
 *
 * The gate never touches that formula: it takes a CENTRAL FINITE DIFFERENCE of
 * x(θ) and y(θ) themselves and divides, so a slipped sign in the chain rule has
 * nothing to hide behind. A near-vertical tangent (the denominator ≈ 0) declines
 * rather than shipping a number the finite difference can't confirm.
 */
function solvePolarGradient(
  spec: CalculusSpec,
  task: Extract<CalculusTask, { kind: "polar_gradient" }>
): SolveCandidate | null {
  const t = spec.variable; // "theta"
  let rp: string;
  try {
    rp = derivative(spec.fn, t).toString();
  } catch {
    return null;
  }
  const r = `(${spec.fn})`;
  const numer = `(${rp}) * sin(${t}) + ${r} * cos(${t})`;
  const denom = `(${rp}) * cos(${t}) - ${r} * sin(${t})`;
  const xExpr = `${r} * cos(${t})`;
  const yExpr = `${r} * sin(${t})`;

  /** The gradient at one θ, plus the finite-difference value it must match. */
  const at = (theta: number): { symbolic: number; numeric: number } | null => {
    const dn = evalReal(denom, { [t]: theta });
    const nu = evalReal(numer, { [t]: theta });
    if (!Number.isFinite(dn) || !Number.isFinite(nu)) return null;
    if (Math.abs(dn) < 1e-6) return null; // vertical tangent — no gradient to state
    const dx = finiteDifference(xExpr, t, theta, 1);
    const dy = finiteDifference(yExpr, t, theta, 1);
    if (!Number.isFinite(dx) || !Number.isFinite(dy) || Math.abs(dx) < 1e-9) return null;
    return { symbolic: nu / dn, numeric: dy / dx };
  };

  const identify: RawStep = {
    ascii: `r = ${spec.fn}`,
    latex: `r = ${asciiToLatex(spec.fn)}`,
    operationCode: "IDENTIFY_FUNCTION",
  };
  const setup: RawStep = {
    ascii: `x = r cos(${t}), y = r sin(${t})`,
    latex: `x = r\\cos\\theta,\\; y = r\\sin\\theta`,
    operationCode: "POLAR_TO_CARTESIAN",
  };
  const chain: RawStep = {
    ascii: `dy/dx = (dr/d${t} sin ${t} + r cos ${t}) / (dr/d${t} cos ${t} - r sin ${t})`,
    latex:
      "\\frac{dy}{dx} = \\frac{\\frac{dr}{d\\theta}\\sin\\theta + r\\cos\\theta}" +
      "{\\frac{dr}{d\\theta}\\cos\\theta - r\\sin\\theta}",
    operationCode: "CHAIN_RULE",
  };
  const derivStep: RawStep = {
    ascii: `dr/d${t} = ${resymbolize(rp)}`,
    latex: `\\frac{dr}{d\\theta} = ${asciiToLatex(resymbolize(rp))}`,
    operationCode: "DIFFERENTIATE",
  };

  if (task.at !== undefined) {
    const v = at(task.at);
    if (!v) return null;
    const proved = () => {
      const w = at(task.at as number);
      return !!w && agrees(w.symbolic, w.numeric, 1e-5);
    };
    if (!proved()) return null;
    const value = niceValue(v.symbolic);
    const point = task.atLatex ?? String(task.at);
    return {
      answer: {
        latex: `\\left.\\frac{dy}{dx}\\right|_{\\theta = ${point}} = ${value.latex}`,
        plain: `dy/dx = ${value.plain} at theta = ${point}`,
      },
      methods: [
        {
          id: "polar_gradient",
          name: "Gradient of a polar curve",
          examPick: true,
          steps: [
            identify,
            setup,
            derivStep,
            chain,
            {
              ascii: `dy/dx = ${value.plain}`,
              latex: `\\left.\\frac{dy}{dx}\\right|_{\\theta = ${point}} = ${value.latex}`,
              operationCode: "RESULT",
            },
          ],
        },
      ],
      plotExpression: null,
      verify: proved,
    };
  }

  // No point given — the gradient as an expression in θ, checked at a spread of
  // angles rather than at one convenient one.
  const SAMPLES = [0.31, 0.83, 1.27, 2.11, 2.73, 3.61, 4.29, 5.17];
  const proved = () => {
    let matched = 0;
    for (const theta of SAMPLES) {
      const v = at(theta);
      if (!v) continue;
      if (!agrees(v.symbolic, v.numeric, 1e-5)) return false;
      matched++;
    }
    return matched >= 4;
  };
  if (!proved()) return null;
  const shown = resymbolize(`(${numer}) / (${denom})`);
  return {
    answer: {
      latex: `\\frac{dy}{dx} = ${asciiToLatex(shown)}`,
      plain: `dy/dx = ${shown}`,
    },
    methods: [
      {
        id: "polar_gradient",
        name: "Gradient of a polar curve",
        examPick: true,
        steps: [
          identify,
          setup,
          derivStep,
          chain,
          {
            ascii: `dy/dx = ${shown}`,
            latex: `\\frac{dy}{dx} = ${asciiToLatex(shown)}`,
            operationCode: "RESULT",
          },
        ],
      },
    ],
    plotExpression: null,
    verify: proved,
  };
}

// --- find dy/dx --------------------------------------------------------------

function solveDerivativeExpression(
  spec: CalculusSpec,
  order: number
): SolveCandidate | null {
  const dd = differentiate(spec.fn, spec.variable, order);
  if (!dd) return null;
  const display = resymbolize(dd.d);
  const op = opLatex(spec.depVar, spec.variable, order);
  const steps: RawStep[] = [
    {
      ascii: `${spec.depVar} = ${spec.fn}`,
      latex: `${spec.depVar} = ${asciiToLatex(spec.fn)}`,
      operationCode: "IDENTIFY_FUNCTION",
    },
    ...intermediateSteps(spec, order),
    {
      ascii: `${op} = ${display}`,
      latex: `${op} = ${asciiToLatex(display)}`,
      operationCode: "RESULT",
    },
  ];
  return {
    answer: {
      latex: `${op} = ${asciiToLatex(display)}`,
      plain: `${opPlain(spec.depVar, spec.variable, order)} = ${display}`,
    },
    methods: [{ id: "differentiate", name: "Differentiate", examPick: true, steps }],
    plotExpression: spec.fn,
    verify: () => verifyDerivative(dd.penult, dd.d, spec.variable),
  };
}

/** For a 2nd/3rd derivative, show each intermediate derivative as its own step. */
function intermediateSteps(spec: CalculusSpec, order: number): RawStep[] {
  const out: RawStep[] = [];
  let cur = spec.fn;
  for (let k = 1; k < order; k++) {
    try {
      cur = derivative(cur, spec.variable).toString();
    } catch {
      return out;
    }
    const shown = resymbolize(cur);
    out.push({
      ascii: `${opLatex(spec.depVar, spec.variable, k)} = ${shown}`,
      latex: `${opLatex(spec.depVar, spec.variable, k)} = ${asciiToLatex(shown)}`,
      operationCode: "DIFFERENTIATE",
    });
  }
  return out;
}

// --- show that dy/dx = <claim> ----------------------------------------------

function solveShowDerivative(
  spec: CalculusSpec,
  task: Extract<CalculusTask, { kind: "show_derivative" }>
): SolveCandidate | null {
  const dd = differentiate(spec.fn, spec.variable, task.order);
  if (!dd) return null;
  // The GATE: the printed claim must agree with the computed derivative
  // everywhere it is defined. A misread digit or a mis-scoped bracket lands here
  // and declines — the app never "proves" a claim it hasn't reproduced.
  const proved = () =>
    verifyDerivative(dd.penult, dd.d, spec.variable) &&
    sameFunction(task.claim, dd.d, spec.variable);
  if (!proved()) return null;

  const op = opLatex(spec.depVar, spec.variable, task.order);
  const display = resymbolize(dd.d);
  const steps: RawStep[] = [
    {
      ascii: `${spec.depVar} = ${spec.fn}`,
      latex: `${spec.depVar} = ${asciiToLatex(spec.fn)}`,
      operationCode: "IDENTIFY_FUNCTION",
    },
    ...intermediateSteps(spec, task.order),
    {
      ascii: `${op} = ${display}`,
      latex: `${op} = ${asciiToLatex(display)}`,
      operationCode: "DIFFERENTIATE",
    },
    {
      ascii: `${display} = ${task.claim}`,
      latex: `${asciiToLatex(display)} = ${task.claimLatex}`,
      operationCode: "MATCH_REQUIRED_FORM",
    },
  ];
  return {
    answer: {
      latex: `${op} = ${task.claimLatex}`,
      // The engine's own simplified form reads better than the raw claim ascii,
      // and the gate above has already proven the two are the same function.
      plain: `${opPlain(spec.depVar, spec.variable, task.order)} = ${display}`,
    },
    methods: [
      { id: "show_derivative", name: "Differentiate and compare", examPick: true, steps },
    ],
    plotExpression: spec.fn,
    verify: proved,
  };
}

/** Two expressions agree at every sampled point where both are real. Used to
 * check a PRINTED claim against the computed derivative. */
function sameFunction(a: string, b: string, variable: string): boolean {
  const points = [0.31, 0.57, 0.83, 1.27, 1.61, 2.13, 2.71, 3.37, 4.19, 5.23, 6.11, 7.53];
  let matched = 0;
  for (const p of points) {
    for (const x of [p, -p]) {
      const va = evalReal(a, { [variable]: x });
      const vb = evalReal(b, { [variable]: x });
      if (!Number.isFinite(va) || !Number.isFinite(vb)) continue;
      if (!agrees(va, vb, 1e-7)) return false;
      matched++;
    }
  }
  return matched >= 4;
}

// --- slope / velocity / acceleration at a point ------------------------------

function solvePointDerivative(
  spec: CalculusSpec,
  task: Extract<CalculusTask, { kind: "point_derivative" }>
): SolveCandidate | null {
  const dd = differentiate(spec.fn, spec.variable, task.order);
  if (!dd) return null;
  const value = evalReal(dd.d, { [spec.variable]: task.at });
  if (!Number.isFinite(value)) return null;
  // Independent check: the finite difference of the ORIGINAL function.
  const fd = finiteDifference(spec.fn, spec.variable, task.at, task.order);
  const pointConsistent = statedPointHolds(spec, task.at, task.statedValue);
  const proved = () =>
    verifyDerivative(dd.penult, dd.d, spec.variable) &&
    agrees(value, fd, task.order === 1 ? 1e-6 : 1e-4) &&
    pointConsistent;
  if (!proved()) return null;

  const nice = niceValue(value);
  const op = opLatex(spec.depVar, spec.variable, task.order);
  const display = resymbolize(dd.d);
  const label =
    task.label === "acceleration"
      ? "Acceleration"
      : task.label === "velocity"
        ? "Velocity"
        : task.label === "slope"
          ? "Slope"
          : "Value";
  const steps: RawStep[] = [
    {
      ascii: `${spec.depVar} = ${spec.fn}`,
      latex: `${spec.depVar} = ${asciiToLatex(spec.fn)}`,
      operationCode: "IDENTIFY_FUNCTION",
    },
    ...intermediateSteps(spec, task.order),
    {
      ascii: `${op} = ${display}`,
      latex: `${op} = ${asciiToLatex(display)}`,
      operationCode: "DIFFERENTIATE",
    },
    {
      ascii: `${spec.variable} = ${task.atLatex}`,
      latex: `\\text{At } ${spec.variable} = ${task.atLatex}`,
      operationCode: "SUBSTITUTE_POINT",
    },
    {
      ascii: `${label} = ${nice.plain}`,
      latex: `${op}\\Big|_{${spec.variable} = ${task.atLatex}} = ${nice.latex}`,
      operationCode: "RESULT",
    },
  ];
  return {
    answer: { latex: nice.latex, plain: `${label.toLowerCase()} = ${nice.plain}` },
    methods: [
      { id: "evaluate_derivative", name: `Differentiate, then substitute`, examPick: true, steps },
    ],
    plotExpression: spec.fn,
    verify: proved,
  };
}

/** When the sheet printed the FULL point (1, 1), the curve must actually pass
 * through it. A mismatch means we misread the curve or the point — decline. */
function statedPointHolds(
  spec: CalculusSpec,
  at: number,
  statedValue: number | undefined
): boolean {
  if (statedValue === undefined) return true;
  const y = evalReal(spec.fn, { [spec.variable]: at });
  return Number.isFinite(y) && agrees(y, statedValue, 1e-6);
}

// --- tangent / normal line ---------------------------------------------------

function solveLine(
  spec: CalculusSpec,
  task: Extract<CalculusTask, { kind: "line" }>
): SolveCandidate | null {
  const dd = differentiate(spec.fn, spec.variable, 1);
  if (!dd) return null;
  const slope = evalReal(dd.d, { [spec.variable]: task.at });
  const y0 = evalReal(spec.fn, { [spec.variable]: task.at });
  if (!Number.isFinite(slope) || !Number.isFinite(y0)) return null;
  // A normal to a horizontal tangent is vertical — no `y = mx + c` form.
  if (task.line === "normal" && Math.abs(slope) < 1e-12) return null;
  const m = task.line === "tangent" ? slope : -1 / slope;
  const c = y0 - m * task.at;
  const fd = finiteDifference(spec.fn, spec.variable, task.at, 1);

  const proved = () =>
    verifyDerivative(dd.penult, dd.d, spec.variable) &&
    agrees(slope, fd) &&
    statedPointHolds(spec, task.at, task.statedValue) &&
    // The line must pass through the point of contact.
    agrees(m * task.at + c, y0, 1e-9);
  if (!proved()) return null;

  const mN = niceValue(m);
  const rhs =
    Math.abs(c) < 1e-12
      ? `${coeff(m, spec.variable)}`
      : `${coeff(m, spec.variable)} ${c < 0 ? "-" : "+"} ${niceValue(Math.abs(c)).latex}`;
  const rhsPlain =
    Math.abs(c) < 1e-12
      ? `${coeffPlain(m, spec.variable)}`
      : `${coeffPlain(m, spec.variable)} ${c < 0 ? "-" : "+"} ${niceValue(Math.abs(c)).plain}`;
  const name = task.line === "tangent" ? "Tangent line" : "Normal line";
  const steps: RawStep[] = [
    {
      ascii: `${spec.depVar} = ${spec.fn}`,
      latex: `${spec.depVar} = ${asciiToLatex(spec.fn)}`,
      operationCode: "IDENTIFY_FUNCTION",
    },
    {
      ascii: `${opLatex(spec.depVar, spec.variable, 1)} = ${resymbolize(dd.d)}`,
      latex: `${opLatex(spec.depVar, spec.variable, 1)} = ${asciiToLatex(resymbolize(dd.d))}`,
      operationCode: "DIFFERENTIATE",
    },
    {
      ascii: `slope = ${niceValue(slope).plain}`,
      latex: `m_{\\text{tangent}} = ${niceValue(slope).latex}`,
      operationCode: "GRADIENT_AT_POINT",
    },
    ...(task.line === "normal"
      ? [
          {
            ascii: `normal slope = -1/(${niceValue(slope).plain}) = ${mN.plain}`,
            latex: `m_{\\text{normal}} = -\\frac{1}{${niceValue(slope).latex}} = ${mN.latex}`,
            operationCode: "PERPENDICULAR_GRADIENT",
          },
        ]
      : []),
    {
      ascii: `${spec.depVar} - ${niceValue(y0).plain} = ${mN.plain}(${spec.variable} - ${task.atLatex})`,
      latex: `${spec.depVar} - ${niceValue(y0).latex} = ${mN.latex}\\left(${spec.variable} - ${task.atLatex}\\right)`,
      operationCode: "POINT_SLOPE_FORM",
    },
    {
      ascii: `${spec.depVar} = ${rhsPlain}`,
      latex: `${spec.depVar} = ${rhs}`,
      operationCode: "RESULT",
    },
  ];
  return {
    answer: { latex: `${spec.depVar} = ${rhs}`, plain: `${spec.depVar} = ${rhsPlain}` },
    methods: [{ id: "tangent_line", name, examPick: true, steps }],
    plotExpression: spec.fn,
    verify: proved,
  };
}

/** `m·x` rendered without a redundant 1 / with a bare minus for −1. */
function coeff(m: number, variable: string): string {
  if (Math.abs(m - 1) < 1e-12) return variable;
  if (Math.abs(m + 1) < 1e-12) return `-${variable}`;
  if (Math.abs(m) < 1e-12) return "0";
  return `${niceValue(m).latex}${variable}`;
}

function coeffPlain(m: number, variable: string): string {
  if (Math.abs(m - 1) < 1e-12) return variable;
  if (Math.abs(m + 1) < 1e-12) return `-${variable}`;
  if (Math.abs(m) < 1e-12) return "0";
  return `${niceValue(m).plain}${variable}`;
}

// --- angle of inclination ----------------------------------------------------

function solveInclination(
  spec: CalculusSpec,
  task: Extract<CalculusTask, { kind: "inclination" }>
): SolveCandidate | null {
  const dd = differentiate(spec.fn, spec.variable, 1);
  if (!dd) return null;
  const slope = evalReal(dd.d, { [spec.variable]: task.at });
  if (!Number.isFinite(slope)) return null;
  const radians = Math.atan(slope);
  const degrees = (radians * 180) / Math.PI;
  const fd = finiteDifference(spec.fn, spec.variable, task.at, 1);
  const proved = () =>
    verifyDerivative(dd.penult, dd.d, spec.variable) &&
    agrees(slope, fd) &&
    statedPointHolds(spec, task.at, task.statedValue) &&
    // The angle must reproduce the gradient: tan θ = m.
    agrees(Math.tan(radians), slope, 1e-9);
  if (!proved()) return null;

  const degStr = String(Number(degrees.toFixed(4)));
  const radExact = exactForm(radians);
  const radStr = radExact ? radExact.latex : String(Number(radians.toFixed(6)));
  const steps: RawStep[] = [
    {
      ascii: `${spec.depVar} = ${spec.fn}`,
      latex: `${spec.depVar} = ${asciiToLatex(spec.fn)}`,
      operationCode: "IDENTIFY_FUNCTION",
    },
    {
      ascii: `${opLatex(spec.depVar, spec.variable, 1)} = ${resymbolize(dd.d)}`,
      latex: `${opLatex(spec.depVar, spec.variable, 1)} = ${asciiToLatex(resymbolize(dd.d))}`,
      operationCode: "DIFFERENTIATE",
    },
    {
      ascii: `m = ${niceValue(slope).plain}`,
      latex: `m = ${opLatex(spec.depVar, spec.variable, 1)}\\Big|_{${spec.variable}=${task.atLatex}} = ${niceValue(slope).latex}`,
      operationCode: "GRADIENT_AT_POINT",
    },
    {
      ascii: `theta = atan(${niceValue(slope).plain})`,
      latex: `\\tan\\theta = ${niceValue(slope).latex} \\Rightarrow \\theta = \\arctan\\left(${niceValue(slope).latex}\\right)`,
      operationCode: "INVERT_TANGENT",
    },
    {
      ascii: `theta = ${degStr} degrees`,
      latex: `\\theta = ${radStr} \\text{ rad} = ${degStr}^{\\circ}`,
      operationCode: "RESULT",
    },
  ];
  return {
    answer: {
      latex: `\\theta = ${radStr}\\text{ rad} \\approx ${degStr}^{\\circ}`,
      plain: `theta = ${degStr} degrees`,
    },
    methods: [
      { id: "inclination", name: "Gradient, then inverse tangent", examPick: true, steps },
    ],
    plotExpression: spec.fn,
    verify: proved,
  };
}

// --- stationary points -------------------------------------------------------

interface StationaryPoint {
  x: number;
  y: number;
  nature: "minimum" | "maximum" | "inflection";
}

function solveStationary(
  spec: CalculusSpec,
  task: Extract<CalculusTask, { kind: "stationary" }>
): SolveCandidate | null {
  const d1 = differentiate(spec.fn, spec.variable, 1);
  const d2 = differentiate(spec.fn, spec.variable, 2);
  if (!d1 || !d2) return null;

  // A RATIONAL curve's derivative is a fraction, so the degree bound below can't
  // read it — which is why "find the turning points of (x²+1)/((x−1)(x−2))"
  // used to decline. Its stationary points are the roots of the NUMERATOR, and
  // Durand–Kerner returns all of them, so that list is complete by construction.
  const fromNumerator = rationalStationaryRoots(spec.fn, spec.variable, spec.domain);
  const roots = fromNumerator ?? findRoots(d1.d, spec.variable, spec.domain);
  if (roots === null || roots.length === 0) return null;
  // COMPLETENESS: a set of stationary points is only an answer if we can prove
  // none were missed. Provable when the derivative is a polynomial (its degree
  // bounds the root count), when it is a fraction whose numerator's roots we
  // have all of — or when the sheet itself states there is exactly one and we
  // found exactly one.
  const degree = polynomialDegree(d1.d, spec.variable);
  const complete =
    fromNumerator !== null ||
    (degree !== null && roots.length >= degree) ||
    (task.singular && roots.length === 1);
  if (!complete) return null;

  const points: StationaryPoint[] = [];
  for (const x of roots) {
    const y = evalReal(spec.fn, { [spec.variable]: x });
    const second = evalReal(d2.d, { [spec.variable]: x });
    if (!Number.isFinite(y) || !Number.isFinite(second)) return null;
    let nature: StationaryPoint["nature"];
    if (second > 1e-9) nature = "minimum";
    else if (second < -1e-9) nature = "maximum";
    else {
      // f″ = 0 is inconclusive — fall back to the FIRST-derivative sign test.
      const left = evalReal(d1.d, { [spec.variable]: x - 1e-3 });
      const right = evalReal(d1.d, { [spec.variable]: x + 1e-3 });
      if (!Number.isFinite(left) || !Number.isFinite(right)) return null;
      if (left < 0 && right > 0) nature = "minimum";
      else if (left > 0 && right < 0) nature = "maximum";
      else nature = "inflection";
    }
    points.push({ x, y, nature });
  }

  const proved = () =>
    verifyDerivative(spec.fn, d1.d, spec.variable) &&
    verifyDerivative(d1.d, d2.d, spec.variable) &&
    points.every((p) => {
      const slope = evalReal(d1.d, { [spec.variable]: p.x });
      // The gradient really is zero there, confirmed independently by the
      // finite difference of the original function.
      const fd = finiteDifference(spec.fn, spec.variable, p.x, 1);
      return Math.abs(slope) < 1e-7 && Math.abs(fd) < 1e-5;
    });
  if (!proved()) return null;

  const describe = (p: StationaryPoint): string =>
    `(${niceValue(p.x).latex}, ${niceValue(p.y).latex}) \\text{ — ${p.nature}}`;
  const steps: RawStep[] = [
    {
      ascii: `${spec.depVar} = ${spec.fn}`,
      latex: `${spec.depVar} = ${asciiToLatex(spec.fn)}`,
      operationCode: "IDENTIFY_FUNCTION",
    },
    {
      ascii: `${opLatex(spec.depVar, spec.variable, 1)} = ${resymbolize(d1.d)}`,
      latex: `${opLatex(spec.depVar, spec.variable, 1)} = ${asciiToLatex(resymbolize(d1.d))}`,
      operationCode: "DIFFERENTIATE",
    },
    {
      ascii: `${resymbolize(d1.d)} = 0`,
      latex: `${asciiToLatex(resymbolize(d1.d))} = 0`,
      operationCode: "SET_DERIVATIVE_ZERO",
    },
    {
      ascii: points.map((p) => `${spec.variable} = ${niceValue(p.x).plain}`).join(", "),
      latex: points.map((p) => `${spec.variable} = ${niceValue(p.x).latex}`).join(",\\; "),
      operationCode: "SOLVE_FOR_STATIONARY",
    },
    {
      ascii: `${opLatex(spec.depVar, spec.variable, 2)} = ${resymbolize(d2.d)}`,
      latex: `${opLatex(spec.depVar, spec.variable, 2)} = ${asciiToLatex(resymbolize(d2.d))}`,
      operationCode: "SECOND_DERIVATIVE_TEST",
    },
    {
      ascii: points.map((p) => `(${niceValue(p.x).plain}, ${niceValue(p.y).plain}) ${p.nature}`).join("; "),
      latex: points.map(describe).join(",\\; "),
      operationCode: "RESULT",
    },
  ];
  return {
    answer: {
      latex: points.map(describe).join(",\\; "),
      plain: points
        .map((p) => `(${niceValue(p.x).plain}, ${niceValue(p.y).plain}) is a ${p.nature}`)
        .join("; "),
    },
    methods: [
      {
        id: "stationary_points",
        name: "Second-derivative test",
        examPick: true,
        steps,
      },
    ],
    roots: points.map((p) => p.x),
    plotExpression: spec.fn,
    verify: proved,
  };
}

/**
 * Real roots of `expr` inside the (optionally restricted) window, by a dense
 * sign-change scan followed by bisection. Returns null if the expression can't
 * be sampled at all. Deliberately a SEARCH, not a solver — completeness is
 * established separately by the caller.
 */
function findRoots(
  expr: string,
  variable: string,
  domain?: { min?: number; max?: number }
): number[] | null {
  const lo = Math.max(domain?.min ?? -50, -50);
  const hi = Math.min(domain?.max ?? 50, 50);
  if (!(hi > lo)) return null;
  const steps = 20000;
  const step = (hi - lo) / steps;
  const f = (x: number) => evalReal(expr, { [variable]: x });
  const roots: number[] = [];
  let sampled = 0;
  let prevX = NaN;
  let prevY = NaN;
  for (let i = 0; i <= steps; i++) {
    // A tiny offset keeps the grid off exact rational roots, where the value is
    // 0 and neither sign — which would hide the crossing.
    const x = lo + i * step + step * 0.137;
    if (x > hi) break;
    const y = f(x);
    if (!Number.isFinite(y)) {
      prevX = NaN;
      prevY = NaN;
      continue;
    }
    sampled++;
    if (Number.isFinite(prevY) && ((prevY < 0 && y > 0) || (prevY > 0 && y < 0))) {
      const r = bisect(f, prevX, x);
      if (r !== null && !roots.some((q) => Math.abs(q - r) < 1e-6)) roots.push(r);
    }
    prevX = x;
    prevY = y;
  }
  if (sampled < 100) return null;
  return roots.sort((a, b) => a - b);
}

/**
 * The stationary points of a RATIONAL curve `f = p/q`, or null when f isn't one.
 *
 * `f′ = (p′q − pq′)/q²`, so the stationary points are the real roots of the
 * POLYNOMIAL `p′q − pq′` that q doesn't kill. Building that top line from the
 * coefficient arrays — rather than asking mathjs to rationalize the printed
 * derivative, which it refuses to do for a nested quotient — is what makes the
 * shape reachable at all.
 *
 * The completeness argument is the asymptote engine's: Durand–Kerner returns
 * ALL roots of that polynomial, so "these are the stationary points" is a
 * statement about the whole curve rather than about the ones a scan stepped on.
 */
function rationalStationaryRoots(
  fn: string,
  variable: string,
  domain?: { min?: number; max?: number }
): number[] | null {
  let num: string;
  let den: string;
  try {
    const r = rationalize(fn, {}, true) as unknown as {
      numerator: { toString(): string };
      denominator: { toString(): string } | null;
    };
    if (!r.denominator) return null; // a polynomial — the degree bound handles it
    num = r.numerator.toString();
    den = r.denominator.toString();
  } catch {
    return null;
  }
  const p = polyCoefficients(num, variable);
  const q = polyCoefficients(den, variable);
  if (!p || !q || q.length < 2) return null;
  const top = trimPoly(polySub(polyMul(polyDeriv(p), q), polyMul(p, polyDeriv(q))));
  if (top.length < 2) return []; // a constant top line — no stationary point at all
  const roots = realRootsOfPolynomial(top);
  if (roots === null) return null;
  return roots
    .filter((x) => Math.abs(evalReal(den, { [variable]: x })) > 1e-9)
    .filter((x) => domain?.min === undefined || x >= domain.min)
    .filter((x) => domain?.max === undefined || x <= domain.max)
    .sort((a, b) => a - b);
}

/** Coefficient arrays, ascending powers. */
function polyDeriv(a: number[]): number[] {
  return a.slice(1).map((c, i) => c * (i + 1));
}

function polyMul(a: number[], b: number[]): number[] {
  const out = new Array<number>(a.length + b.length - 1).fill(0);
  for (let i = 0; i < a.length; i++) {
    for (let j = 0; j < b.length; j++) out[i + j] += a[i] * b[j];
  }
  return out;
}

function polySub(a: number[], b: number[]): number[] {
  const out = new Array<number>(Math.max(a.length, b.length)).fill(0);
  for (let i = 0; i < out.length; i++) out[i] = (a[i] ?? 0) - (b[i] ?? 0);
  return out;
}

/** Drop leading zero coefficients, which would make the degree a lie. */
function trimPoly(a: number[]): number[] {
  const scale = Math.max(1, ...a.map(Math.abs));
  let n = a.length;
  while (n > 1 && Math.abs(a[n - 1]) < 1e-12 * scale) n--;
  return a.slice(0, n);
}

function bisect(f: (x: number) => number, a: number, b: number): number | null {
  let lo = a;
  let hi = b;
  let flo = f(lo);
  if (!Number.isFinite(flo)) return null;
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    const fm = f(mid);
    if (!Number.isFinite(fm)) return null;
    if (Math.abs(fm) < 1e-14 || hi - lo < 1e-13) return mid;
    if ((flo < 0 && fm < 0) || (flo > 0 && fm > 0)) {
      lo = mid;
      flo = fm;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/**
 * The polynomial degree of `expr` in `variable`, or null if it isn't a
 * polynomial. Recovered by finite differences over integer samples: the nth
 * forward difference of a degree-n polynomial is constant. A null answer is what
 * makes the caller refuse to claim a COMPLETE set of stationary points.
 */
function polynomialDegree(expr: string, variable: string): number | null {
  const MAX = 8;
  const values: number[] = [];
  for (let i = 0; i <= MAX + 2; i++) {
    const v = evalReal(expr, { [variable]: i });
    if (!Number.isFinite(v)) return null;
    values.push(v);
  }
  let diffs = values;
  for (let order = 0; order <= MAX; order++) {
    const spread = Math.max(...diffs.map(Math.abs));
    if (spread < 1e-9) return Math.max(0, order - 1);
    if (diffs.length < 2) return null;
    const next: number[] = [];
    for (let i = 1; i < diffs.length; i++) next.push(diffs[i] - diffs[i - 1]);
    // A constant run at this level means degree = order.
    const cmax = Math.max(...next.map(Math.abs));
    if (cmax < 1e-9 * Math.max(1, spread)) return order;
    diffs = next;
  }
  return null;
}

// --- asymptotes --------------------------------------------------------------

/** `y = mx + c` at infinity, or `y = c` when m is 0. */
interface EndBehaviour {
  m: number;
  c: number;
}

/**
 * The asymptotes of a RATIONAL curve.
 *
 * The parse gate is mathjs's `rationalize`, which throws on anything that isn't
 * a ratio of polynomials — so `sin x / x` and `e^x/(x-1)` decline here rather
 * than getting a made-up answer. That leaves a shape whose asymptotes are
 * genuinely decidable:
 *
 *   • vertical   — the real roots of the denominator, found COMPLETELY (all n
 *                  complex roots by Durand–Kerner, then the real ones kept), and
 *                  each one proven by the function blowing up beside it
 *   • horizontal — deg p < deg q → y = 0; deg p = deg q → the ratio of the
 *                  leading coefficients
 *   • oblique    — deg p = deg q + 1 → the quotient of the long division
 *
 * Nothing ships until the numbers are re-checked against the FUNCTION itself:
 * the residual |f(X) − (mX + c)| must actually shrink as X grows, every listed
 * pole must actually be a pole, and a dense scan must find no blow-up that isn't
 * on the list. A shared factor (a hole, not an asymptote) declines outright.
 */
function solveAsymptotes(spec: CalculusSpec): SolveCandidate | null {
  const v = spec.variable;
  let num: string;
  let den: string;
  try {
    const r = rationalize(spec.fn, {}, true) as unknown as {
      numerator: { toString(): string };
      denominator: { toString(): string } | null;
    };
    if (!r.denominator) return null; // a polynomial — no asymptote to state
    num = r.numerator.toString();
    den = r.denominator.toString();
  } catch {
    return null;
  }

  const p = polyCoefficients(num, v);
  const q = polyCoefficients(den, v);
  if (!p || !q || q.length < 2) return null; // a constant denominator is no denominator

  // Every root of q lies inside Cauchy's bound, so a scan of that window is a
  // scan of ALL of them — which is what makes "these are the asymptotes"
  // a complete statement rather than a list of the ones we happened to find.
  const lead = q[q.length - 1];
  if (!(Math.abs(lead) > 1e-12)) return null;
  const cauchy = 1 + Math.max(...q.slice(0, -1).map((a) => Math.abs(a / lead)));
  if (!Number.isFinite(cauchy) || cauchy > 1e4) return null;

  const roots = realRootsOfPolynomial(q);
  if (roots === null) return null;
  for (const x of roots) {
    // A shared factor is a HOLE, not an asymptote. Saying "x = 1 is an
    // asymptote" of (x²−1)/(x−1) — a straight line — would be plainly false.
    if (Math.abs(evalReal(num, { [v]: x })) < 1e-9) return null;
  }

  const dp = p.length - 1;
  const dq = q.length - 1;
  let end: EndBehaviour | null = null;
  if (dp < dq) end = { m: 0, c: 0 };
  else if (dp === dq) end = { m: 0, c: p[dp] / q[dq] };
  else if (dp === dq + 1) {
    const quotient = polyDivide(p, q);
    if (!quotient || quotient.length !== 2) return null;
    end = { m: quotient[1], c: quotient[0] };
  }
  // deg p ≥ deg q + 2 — the curve runs away like a parabola or worse. There IS
  // no linear asymptote, and `end` stays null rather than inventing one.

  const f = (x: number) => evalReal(spec.fn, { [v]: x });

  const proved = (): boolean => {
    // 1. Every listed vertical asymptote really is one — the function blows up
    //    on both sides of it.
    for (const a of roots) {
      const scale = Math.max(1, Math.abs(a));
      const l = f(a - 1e-7 * scale);
      const r = f(a + 1e-7 * scale);
      if (!(Math.abs(l) > 1e5) || !(Math.abs(r) > 1e5)) return false;
    }
    // 2. No blow-up anywhere in the window is missing from the list.
    const lo = -(cauchy + 1);
    const hi = cauchy + 1;
    const N = 20000;
    for (let i = 0; i <= N; i++) {
      const x = lo + ((hi - lo) * i) / N + 1e-3;
      if (x > hi) break;
      const y = f(x);
      if (!Number.isFinite(y) || Math.abs(y) > 1e6) {
        if (!roots.some((a) => Math.abs(a - x) < 1e-2 * Math.max(1, Math.abs(a)))) return false;
      }
    }
    // 3. The end behaviour is checked by DECAY, not by one lucky sample: the
    //    residual f(X) − (mX + c) must be small AND get smaller as X grows, in
    //    both directions. That catches a wrong leading coefficient, which a
    //    single-point tolerance would wave through.
    if (end) {
      for (const sign of [1, -1]) {
        const r1 = Math.abs(f(sign * 1e3) - (end.m * sign * 1e3 + end.c));
        const r2 = Math.abs(f(sign * 1e4) - (end.m * sign * 1e4 + end.c));
        if (!Number.isFinite(r1) || !Number.isFinite(r2)) return false;
        if (r1 > 0.5 || r2 > r1 + 1e-6) return false;
      }
    }
    return true;
  };
  if (!proved()) return null;
  if (roots.length === 0 && !end) return null; // nothing to state

  const vertLatex = roots.map((a) => `${v} = ${niceValue(a).latex}`);
  const vertPlain = roots.map((a) => `${v} = ${niceValue(a).plain}`);
  const endLatex = end ? [`${spec.depVar} = ${lineLatex(end, v)}`] : [];
  const endPlain = end ? [`${spec.depVar} = ${linePlain(end, v)}`] : [];

  const steps: RawStep[] = [
    {
      ascii: `${spec.depVar} = ${spec.fn}`,
      latex: `${spec.depVar} = ${asciiToLatex(spec.fn)}`,
      operationCode: "IDENTIFY_FUNCTION",
    },
    {
      ascii: `denominator = ${den}`,
      latex: `\\text{denominator: } ${asciiToLatex(den)} = 0`,
      operationCode: "FIND_VERTICAL_ASYMPTOTES",
    },
    {
      ascii: roots.length ? vertPlain.join(", ") : "no vertical asymptote",
      latex: roots.length ? vertLatex.join(",\\; ") : "\\text{no vertical asymptote}",
      operationCode: "VERTICAL_ASYMPTOTES",
    },
    ...(end
      ? [
          {
            ascii: `as ${v} -> ±infinity, ${spec.depVar} -> ${linePlain(end, v)}`,
            latex: `${v} \\to \\pm\\infty:\\; ${spec.depVar} \\to ${lineLatex(end, v)}`,
            operationCode: end.m === 0 ? "HORIZONTAL_ASYMPTOTE" : "OBLIQUE_ASYMPTOTE",
          } as RawStep,
        ]
      : []),
    {
      ascii: [...vertPlain, ...endPlain].join(", "),
      latex: [...vertLatex, ...endLatex].join(",\\; "),
      operationCode: "RESULT",
    },
  ];

  return {
    answer: {
      latex: [...vertLatex, ...endLatex].join(",\\; "),
      plain: [...vertPlain, ...endPlain].join(", "),
    },
    methods: [{ id: "asymptotes", name: "Asymptotes", examPick: true, steps }],
    plotExpression: spec.fn,
    verify: proved,
  };
}

function lineLatex(end: EndBehaviour, v: string): string {
  if (end.m === 0) return niceValue(end.c).latex;
  const slope =
    end.m === 1 ? v : end.m === -1 ? `-${v}` : `${niceValue(end.m).latex}${v}`;
  if (Math.abs(end.c) < 1e-12) return slope;
  return `${slope} ${end.c > 0 ? "+" : "-"} ${niceValue(Math.abs(end.c)).latex}`;
}

function linePlain(end: EndBehaviour, v: string): string {
  if (end.m === 0) return niceValue(end.c).plain;
  const slope =
    end.m === 1 ? v : end.m === -1 ? `-${v}` : `${niceValue(end.m).plain}${v}`;
  if (Math.abs(end.c) < 1e-12) return slope;
  return `${slope} ${end.c > 0 ? "+" : "-"} ${niceValue(Math.abs(end.c)).plain}`;
}

/** Ascending coefficients of a single-variable polynomial, or null when `expr`
 * isn't one in `variable`. */
function polyCoefficients(expr: string, variable: string): number[] | null {
  const vars = variablesIn(expr);
  if (vars.length > 1 || (vars.length === 1 && vars[0] !== variable)) return null;
  if (vars.length === 0) {
    const c = evalReal(expr);
    return Number.isFinite(c) ? [c] : null;
  }
  try {
    const r = rationalize(expr, {}, true) as unknown as { coefficients: number[] };
    const co = r.coefficients;
    if (!Array.isArray(co) || co.length === 0) return null;
    if (!co.every((x) => typeof x === "number" && Number.isFinite(x))) return null;
    // Independent check: the coefficients must reproduce the expression's own
    // value at several points, or they describe a different polynomial.
    for (const x of [0.37, -1.29, 2.71]) {
      const viaCoeffs = co.reduce((s, a, i) => s + a * x ** i, 0);
      const direct = evalReal(expr, { [variable]: x });
      if (!agrees(viaCoeffs, direct, 1e-9)) return null;
    }
    return co;
  } catch {
    return null;
  }
}

/** The QUOTIENT of p ÷ q (ascending coefficients), remainder discarded. */
function polyDivide(p: number[], q: number[]): number[] | null {
  const dq = q.length - 1;
  const lead = q[dq];
  if (!(Math.abs(lead) > 1e-12)) return null;
  const rem = [...p];
  const out: number[] = [];
  for (let k = p.length - 1 - dq; k >= 0; k--) {
    const factor = rem[k + dq] / lead;
    out[k] = factor;
    for (let i = 0; i <= dq; i++) rem[k + i] -= factor * q[i];
  }
  return out.map((x) => x ?? 0);
}

/**
 * The real roots of a polynomial, COMPLETELY — Durand–Kerner converges to all n
 * complex roots simultaneously, so "these are the real ones" is a statement
 * about the whole factorisation rather than about a scan that might have stepped
 * over something. Returns null when it hasn't converged, which is a decline.
 */
function realRootsOfPolynomial(coeffs: number[]): number[] | null {
  const n = coeffs.length - 1;
  if (n < 1) return null;
  const lead = coeffs[n];
  const a = coeffs.map((c) => c / lead); // monic
  // Seed off the unit circle at an angle that is not a root of unity of any low
  // order, so no two starting points collide.
  let re = Array.from({ length: n }, (_, k) => 0.4 * Math.cos(0.9 + (2 * Math.PI * k) / n));
  let im = Array.from({ length: n }, (_, k) => 0.4 * Math.sin(0.9 + (2 * Math.PI * k) / n));
  const evalPoly = (x: number, y: number): [number, number] => {
    let pr = 0;
    let pi = 0;
    for (let i = n; i >= 0; i--) {
      const nr = pr * x - pi * y + a[i];
      pi = pr * y + pi * x;
      pr = nr;
    }
    return [pr, pi];
  };
  for (let iter = 0; iter < 500; iter++) {
    let moved = 0;
    const nre = [...re];
    const nim = [...im];
    for (let k = 0; k < n; k++) {
      let [dr, di] = evalPoly(re[k], im[k]);
      for (let j = 0; j < n; j++) {
        if (j === k) continue;
        const xr = re[k] - re[j];
        const xi = im[k] - im[j];
        const den = xr * xr + xi * xi;
        if (den < 1e-30) return null; // two roots collapsed — no clean split
        const qr = (dr * xr + di * xi) / den;
        const qi = (di * xr - dr * xi) / den;
        dr = qr;
        di = qi;
      }
      nre[k] = re[k] - dr;
      nim[k] = im[k] - di;
      moved = Math.max(moved, Math.hypot(dr, di));
    }
    re = nre;
    im = nim;
    if (moved < 1e-14) break;
    if (!re.every(Number.isFinite) || !im.every(Number.isFinite)) return null;
  }
  // Each root must actually be one — checked against the polynomial itself.
  for (let k = 0; k < n; k++) {
    const [pr, pi] = evalPoly(re[k], im[k]);
    const scale = Math.max(1, Math.hypot(re[k], im[k])) ** n;
    if (Math.hypot(pr, pi) > 1e-6 * scale) return null;
  }
  const out: number[] = [];
  for (let k = 0; k < n; k++) {
    if (Math.abs(im[k]) > 1e-7 * Math.max(1, Math.abs(re[k]))) continue;
    const x = Math.abs(re[k] - Math.round(re[k])) < 1e-9 ? Math.round(re[k]) : re[k];
    if (!out.some((y) => Math.abs(y - x) < 1e-6 * Math.max(1, Math.abs(x)))) out.push(x);
  }
  return out.sort((x, y) => x - y);
}

/** Exposed for the classifier's display line. */
export function calculusProblemType(task: CalculusTask): string {
  switch (task.kind) {
    case "derivative":
      return "derivative";
    case "show_derivative":
      return "derivative_identity";
    case "point_derivative":
      return task.label === "acceleration" || task.label === "velocity"
        ? "kinematics"
        : "curve_gradient";
    case "line":
      return task.line === "tangent" ? "tangent_line" : "normal_line";
    case "inclination":
      return "angle_of_inclination";
    case "stationary":
      return "stationary_points";
    case "asymptotes":
      return "curve_asymptotes";
    case "polar_gradient":
      return "polar_gradient";
    case "rest_times":
      return "rest_times";
    case "implicit_derivative":
      return "implicit_derivative";
  }
}
