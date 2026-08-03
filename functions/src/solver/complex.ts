/**
 * Complex numbers — a domain the solver did not have at all.
 *
 * Before this module `(3+4i)(2-i)` was routed to the *arithmetic* engine (which
 * has no notion of i), "find the modulus and argument of z" dead-ended at
 * `beyond_solver`, and "solve e^z = −1" was read as a linear equation. Sheet 6
 * of a first-year course is essentially all of these.
 *
 * THE INDEPENDENT ORACLE. mathjs can evaluate complex arithmetic directly, but
 * an answer checked by the same library that produced it is not checked at all.
 * So every arithmetic result here is re-computed through a completely different
 * representation: the field isomorphism
 *
 *        a + bi  ≅  [ a  -b ]          i  ≅  [ 0  -1 ]
 *                   [ b   a ]                [ 1   0 ]
 *
 * Under it, complex addition/multiplication/division/powers are ORDINARY REAL
 * 2×2 MATRIX arithmetic — no complex code path is touched. Evaluating the
 * original expression in that representation and reading (a, b) back off the
 * first column must reproduce the answer. A slip in either implementation shows
 * up as a disagreement, and the engine declines.
 *
 * The other tasks are gated on their defining property rather than on a
 * recomputation:
 *   • modulus     — r ≥ 0 and r² = a² + b²
 *   • argument    — r·cos θ = a, r·sin θ = b, and θ is the PRINCIPAL value
 *   • conjugate   — z·z̄ = |z|² (real, ≥ 0) and z + z̄ = 2·Re z
 *   • polar form  — r(cos θ + i sin θ) reconstructs z exactly
 *   • nth roots   — every root w satisfies wⁿ = z, and there are n distinct ones
 *   • e^z / cos z / cosh z … = c — each member of the solution family is
 *     SUBSTITUTED BACK into the original equation across several n
 */
import {
  Complex,
  MathNode,
  abs,
  add,
  arg,
  complex,
  divide,
  evaluate,
  multiply,
  parse,
  subtract,
} from "mathjs";

import { exactForm } from "./exact";
import { latexToAscii, unwrapProse } from "./latex";
import { RawStep, SolveCandidate } from "./types";

const TOL = 1e-9;

// --- The parsed request -----------------------------------------------------

export type ComplexTask =
  /** "reduce to the form a + bi" — or a bare arithmetic expression in i. */
  | { kind: "standard_form" }
  /** |z| */
  | { kind: "modulus" }
  /** arg z, principal value in (−π, π]. */
  | { kind: "argument" }
  /** z̄ */
  | { kind: "conjugate" }
  /** r(cos θ + i sin θ) */
  | { kind: "polar" }
  /** The n distinct nth roots of z. */
  | { kind: "roots"; n: number }
  /** Re z / Im z */
  | { kind: "part"; part: "real" | "imaginary" }
  /** e^z = c, cos z = c, cosh z = c, … — an infinite family of roots. */
  | { kind: "solve"; fn: TranscendentalFn; rhs: string }
  /** az² + bz + c = 0 with COMPLEX coefficients — includes `ω² = −5 − 12i`. */
  | { kind: "quadratic"; unknown: string; unknownLatex: string };

export type TranscendentalFn = "exp" | "cos" | "sin" | "cosh" | "sinh";

export interface ComplexSpec {
  /** The complex expression, as ascii mathjs can evaluate (uses `i`). */
  expr: string;
  task: ComplexTask;
}

// --- The 2×2 real-matrix oracle ---------------------------------------------

/** A complex number as its real 2×2 matrix [[a,−b],[b,a]], carried as (a, b). */
interface M2 {
  a: number;
  b: number;
}

const M_ONE: M2 = { a: 1, b: 0 };
const M_I: M2 = { a: 0, b: 1 };

function mAdd(x: M2, y: M2): M2 {
  return { a: x.a + y.a, b: x.b + y.b };
}
function mSub(x: M2, y: M2): M2 {
  return { a: x.a - y.a, b: x.b - y.b };
}
/** Ordinary 2×2 matrix product, written out. */
function mMul(x: M2, y: M2): M2 {
  return { a: x.a * y.a - x.b * y.b, b: x.a * y.b + x.b * y.a };
}
/** Matrix inverse: adj(M)/det(M), with det = a² + b². */
function mInv(x: M2): M2 {
  const det = x.a * x.a + x.b * x.b;
  if (det === 0) throw new Error("singular");
  return { a: x.a / det, b: -x.b / det };
}
function mDiv(x: M2, y: M2): M2 {
  return mMul(x, mInv(y));
}
/** Integer powers by repeated multiplication — no exponential/log identity. */
function mPowInt(x: M2, n: number): M2 {
  if (!Number.isInteger(n)) throw new Error("non-integer power");
  if (n < 0) return mInv(mPowInt(x, -n));
  let acc = M_ONE;
  for (let k = 0; k < n; k++) acc = mMul(acc, x);
  return acc;
}

/**
 * Evaluate an expression in the matrix representation. Throws when it meets a
 * node this representation can't express — a free variable, a fractional power
 * (multivalued), an unsupported function — so the caller treats the oracle as
 * UNAVAILABLE and declines rather than accepting an unchecked answer.
 */
function oracleEval(node: MathNode, scope: Record<string, M2> = {}): M2 {
  const n = node as unknown as {
    type: string;
    value?: unknown;
    name?: string;
    op?: string;
    fn?: { name?: string } | string;
    args?: unknown[];
    content?: unknown;
    object?: unknown;
    index?: unknown;
  };
  switch (n.type) {
    case "ConstantNode": {
      const v = Number(n.value);
      if (!Number.isFinite(v)) throw new Error("bad constant");
      return { a: v, b: 0 };
    }
    case "SymbolNode":
      if (n.name === "i") return M_I;
      if (n.name === "pi") return { a: Math.PI, b: 0 };
      if (n.name === "e") return { a: Math.E, b: 0 };
      // A variable the caller BOUND to a value — substituting a root back into
      // the equation it came from. Anything else is free and the oracle, which
      // has no notion of an unknown, must say so rather than guess.
      if (n.name && Object.prototype.hasOwnProperty.call(scope, n.name)) return scope[n.name];
      throw new Error(`free symbol ${n.name}`);
    case "ParenthesisNode":
      return oracleEval(n.content as MathNode, scope);
    case "OperatorNode": {
      const args = (n.args ?? []).map((a) => oracleEval(a as MathNode, scope));
      switch (n.op) {
        case "+":
          return args.length === 1 ? args[0] : mAdd(args[0], args[1]);
        case "-":
          return args.length === 1 ? mSub({ a: 0, b: 0 }, args[0]) : mSub(args[0], args[1]);
        case "*":
          return mMul(args[0], args[1]);
        case "/":
          return mDiv(args[0], args[1]);
        case "^": {
          const exp = args[1];
          // Only a REAL INTEGER exponent is single-valued; z^(1/3) is not a
          // function, and the oracle must not pretend to pick a branch.
          if (Math.abs(exp.b) > 0) throw new Error("complex exponent");
          return mPowInt(args[0], exp.a);
        }
        default:
          throw new Error(`op ${n.op}`);
      }
    }
    case "FunctionNode": {
      const name = typeof n.fn === "string" ? n.fn : (n.fn?.name ?? "");
      const args = (n.args ?? []).map((a) => oracleEval(a as MathNode, scope));
      switch (name) {
        case "conj":
          return { a: args[0].a, b: -args[0].b };
        case "abs":
          return { a: Math.hypot(args[0].a, args[0].b), b: 0 };
        case "re":
          return { a: args[0].a, b: 0 };
        case "im":
          return { a: args[0].b, b: 0 };
        case "sqrt":
          // √ of a NON-NEGATIVE REAL is a single number, and `1 + i√3` needs it.
          // Of anything else it is a branch choice the oracle must not make for
          // itself — that is exactly the kind of silent disagreement it exists
          // to catch.
          if (Math.abs(args[0].b) > 0 || args[0].a < 0) throw new Error("sqrt is multivalued");
          return { a: Math.sqrt(args[0].a), b: 0 };
        case "exp": {
          // exp(aI + bJ) = e^a (cos b · I + sin b · J). This is Euler's formula
          // written for the matrix representation — a second implementation, in
          // real arithmetic, of what mathjs computes over its Complex type.
          const s = Math.exp(args[0].a);
          return { a: s * Math.cos(args[0].b), b: s * Math.sin(args[0].b) };
        }
        case "complex":
          return { a: args[0]?.a ?? 0, b: args[1]?.a ?? 0 };
        default:
          throw new Error(`fn ${name}`);
      }
    }
    default:
      throw new Error(`node ${n.type}`);
  }
}

/** The oracle's value for `expr`, or null when it can't represent it. */
function oracle(expr: string, scope: Record<string, M2> = {}): M2 | null {
  try {
    return oracleEval(parse(expr), scope);
  } catch {
    return null;
  }
}

// --- mathjs evaluation ------------------------------------------------------

/** Evaluate to a complex value, or null. `scope` binds the unknown when a
 * candidate root is being substituted back in. */
function evalComplex(expr: string, scope: Record<string, Complex> = {}): Complex | null {
  try {
    const v = evaluate(expr, { ...scope });
    if (typeof v === "number") return Number.isFinite(v) ? complex(v, 0) : null;
    if (v && typeof v === "object" && "re" in v && "im" in v) {
      const c = v as Complex;
      return Number.isFinite(c.re) && Number.isFinite(c.im) ? c : null;
    }
    return null;
  } catch {
    return null;
  }
}

function close(x: number, y: number, tol = TOL): boolean {
  return Math.abs(x - y) <= tol * Math.max(1, Math.abs(x), Math.abs(y));
}

/** The mathjs answer and the matrix oracle must agree. */
function oracleAgrees(expr: string, z: Complex): boolean {
  const m = oracle(expr);
  if (!m) return false;
  return close(m.a, z.re) && close(m.b, z.im);
}

// --- Display ----------------------------------------------------------------

/** A real, in exact form where one is recognisable. */
function realLatex(v: number): string {
  if (Math.abs(v - Math.round(v)) < 1e-12) return String(Math.round(v) + 0);
  const exact = exactForm(v);
  if (exact) return exact.latex;
  for (let d = 2; d <= 64; d++) {
    const n = v * d;
    if (Math.abs(n - Math.round(n)) < 1e-12) {
      const r = Math.round(n);
      const g = gcd(Math.abs(r), d);
      if (d / g === 1) break;
      return `${r < 0 ? "-" : ""}\\frac{${Math.abs(r) / g}}{${d / g}}`;
    }
  }
  return String(Number(v.toFixed(6)));
}

function realPlain(v: number): string {
  if (Math.abs(v - Math.round(v)) < 1e-12) return String(Math.round(v) + 0);
  const exact = exactForm(v);
  if (exact) return exact.plain;
  for (let d = 2; d <= 64; d++) {
    const n = v * d;
    if (Math.abs(n - Math.round(n)) < 1e-12) {
      const r = Math.round(n);
      const g = gcd(Math.abs(r), d);
      if (d / g === 1) break;
      return `${r / g}/${d / g}`;
    }
  }
  return String(Number(v.toFixed(6)));
}

function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

/** `a + bi` in standard form — the shape the question asks for. */
function standardLatex(z: Complex): string {
  const re = z.re;
  const im = z.im;
  if (Math.abs(im) < 1e-12) return realLatex(re);
  const imPart =
    Math.abs(Math.abs(im) - 1) < 1e-12 ? "i" : `${realLatex(Math.abs(im))}i`;
  if (Math.abs(re) < 1e-12) return `${im < 0 ? "-" : ""}${imPart}`;
  return `${realLatex(re)} ${im < 0 ? "-" : "+"} ${imPart}`;
}

function standardPlain(z: Complex): string {
  const re = z.re;
  const im = z.im;
  if (Math.abs(im) < 1e-12) return realPlain(re);
  const imPart = Math.abs(Math.abs(im) - 1) < 1e-12 ? "i" : `${realPlain(Math.abs(im))}i`;
  if (Math.abs(re) < 1e-12) return `${im < 0 ? "-" : ""}${imPart}`;
  return `${realPlain(re)} ${im < 0 ? "-" : "+"} ${imPart}`;
}

/** An angle, preferring an exact multiple of π. */
function angleLatex(theta: number): string {
  const exact = exactForm(theta);
  if (exact && /pi|\\pi/.test(exact.latex)) return exact.latex;
  for (let d = 1; d <= 24; d++) {
    const k = (theta * d) / Math.PI;
    if (Math.abs(k - Math.round(k)) < 1e-12) {
      const n = Math.round(k);
      if (n === 0) return "0";
      const g = gcd(Math.abs(n), d);
      const num = n / g;
      const den = d / g;
      const mag = Math.abs(num) === 1 ? "\\pi" : `${Math.abs(num)}\\pi`;
      const sign = num < 0 ? "-" : "";
      return den === 1 ? `${sign}${mag}` : `${sign}\\frac{${mag}}{${den}}`;
    }
  }
  return String(Number(theta.toFixed(6)));
}

// --- Parsing ----------------------------------------------------------------

/** LaTeX for a conjugate — `\bar{z}`, `\overline{z}` — has no ascii spelling,
 * so it is rewritten to mathjs's `conj(...)` before conversion. Left alone it
 * became the letters of the word "overline", read as a product of variables. */
function rewriteConjugates(s: string): string {
  let out = s;
  for (let pass = 0; pass < 4; pass++) {
    const next = out.replace(
      /\\(?:bar|overline|overbar)\s*\{([^{}]*)\}/g,
      (_m, inner) => `conj(${inner})`
    );
    // The un-braced form `\bar z`.
    const next2 = next.replace(/\\(?:bar|overline|overbar)\s+?([a-zA-Z0-9])/g, "conj($1)");
    if (next2 === out) return out;
    out = next2;
  }
  return out;
}

/**
 * True when `expr` genuinely uses the imaginary unit. A DIGIT may precede it —
 * `4i` is implicit multiplication, and the first version of this check rejected
 * it, which quietly killed every "3+4i" on the sheet. Only a LETTER before or
 * after means it is part of a longer name (`pi`, `sin`, `i_1`).
 */
function usesImaginaryUnit(ascii: string): boolean {
  return /(?<![A-Za-z_])i(?![A-Za-z0-9_])/.test(ascii);
}

/** The words that are MATH even though they are spelled with letters. */
const MATH_WORDS = new Set([
  "sqrt", "frac", "cdot", "times", "div", "pi", "infty", "infinity", "left", "right",
  "cos", "sin", "tan", "sec", "csc", "cot", "cosh", "sinh", "tanh", "exp", "log", "ln",
  "abs", "conj", "re", "im", "arg", "theta", "phi", "alpha", "beta", "gamma", "omega",
  "lambda", "mu", "operatorname", "mathrm", "circ", "deg", "nthRoot", "sqrtb",
]);

/**
 * Split prose into its MATHEMATICAL fragments by blanking out every English
 * word. Splitting on a fixed list of connective words (the first attempt) fails
 * the moment a sheet words the question differently — "Express in the form
 * a+bi: (3+4i)/(1-2i)" put the answer AFTER the connectives, so the split kept
 * the word "Express" and threw the maths away. A word is English unless it is a
 * LaTeX command (`\frac`) or a known math name (`sin`, `pi`, `conj`).
 */
function mathChunks(prose: string): string[] {
  const blanked = prose.replace(/(\\?)([A-Za-z]{2,})/g, (m, bs: string, w: string) =>
    bs || MATH_WORDS.has(w) || MATH_WORDS.has(w.toLowerCase()) ? m : " "
  );
  return blanked
    .split(" ")
    .map((s) => s.replace(/^[\s:;,.]+/, "").replace(/[\s:;,.]+$/, "").trim())
    .filter(Boolean);
}

/** `x = body` where the left side is a single letter — a DEFINITION, not the
 * thing being asked for. */
function asDefinition(chunk: string): { name: string; body: string } | null {
  const m = /^([a-zA-Z])\s*=\s*(.+)$/.exec(chunk.trim());
  return m ? { name: m[1], body: m[2] } : null;
}

/** Substitute each `name` by its bracketed body, as a standalone token. */
function substitute(ascii: string, defs: Map<string, string>): string {
  let out = ascii;
  for (const [name, body] of defs) {
    out = out.replace(new RegExp(`(?<![A-Za-z0-9_])${name}(?![A-Za-z0-9_])`, "g"), `(${body})`);
  }
  return out;
}

const TRANSCENDENTAL: [RegExp, TranscendentalFn][] = [
  [/\bcosh\b/, "cosh"],
  [/\bsinh\b/, "sinh"],
  [/\bcos\b/, "cos"],
  [/\bsin\b/, "sin"],
  [/\bexp\b|(?<![A-Za-z0-9])e\s*\^/, "exp"],
];

/**
 * Parse a complex-number request, or null. Two independent ways in:
 *   • the PROSE names a complex task ("modulus", "argument", "standard form",
 *     "conjugate", "complex roots"), or
 *   • the expression itself uses the imaginary unit, which no real-arithmetic
 *     problem does.
 * Everything else declines, so no real problem is pulled into this engine.
 */
export function parseComplex(rawLatex: string): ComplexSpec | null {
  const prose = rewriteConjugates(unwrapProse(rawLatex));
  // An integral, a limit, a matrix or a derivative belongs to another engine
  // even when an `i` appears somewhere inside it.
  if (/\\int|∫|\\lim|\\begin\s*\{[pbv]?matrix\}|\\frac\s*\{\s*d/.test(prose)) return null;

  // --- solve f(z) = c over ℂ ------------------------------------------------
  // "Find the complex roots of cosh z = 1" / "Solve e^z = −1".
  const wantsComplexRoots =
    /\bcomplex\b|\ball\s+(?:the\s+)?(?:roots|solutions)\b|\bover\s+(?:the\s+)?(?:complex|ℂ)\b/i.test(
      prose
    );
  const eq = splitTopLevelEquation(prose);
  if (eq) {
    // Take the maths on each side, not the sentence around it: "Solve cos z = 2"
    // must reduce to `cos(z)` and `2`, or the shape match below never fires.
    const lhsChunks = mathChunks(eq.lhs);
    const rhsChunks = mathChunks(eq.rhs);
    const lhsAscii = lhsChunks.length
      ? latexToAscii(lhsChunks[lhsChunks.length - 1]).trim()
      : "";
    const rhsAscii = rhsChunks.length ? latexToAscii(rhsChunks[0]).trim() : "";
    const applied = matchTranscendental(lhsAscii);
    // `z`/`w` is the conventional complex unknown. For any other letter the
    // question is a REAL one, and answering it with a complex family would be
    // changing the question — so that needs the prose to ask for it explicitly.
    if (
      applied &&
      (wantsComplexRoots || /^[zw]$/.test(applied.unknown)) &&
      (wantsComplexRoots || !realSolutionExists(applied.fn, rhsAscii))
    ) {
      if (evalComplex(rhsAscii)) {
        return { expr: rhsAscii, task: { kind: "solve", fn: applied.fn, rhs: rhsAscii } };
      }
    }
  }

  // --- a quadratic with COMPLEX coefficients --------------------------------
  // `z² − (4+i)z + (5+5i) = 0` went to the real quadratic engine, which has no
  // imaginary unit and died with "No term with symbol: z"; `ω² = −5 − 12i` is
  // the same problem with b = 0 and dead-ended at the tutor. Both are decided
  // here, ahead of the prose-named tasks, because the equation as a whole is
  // the question — a fragment of it that happens to evaluate is not.
  if (eq) {
    const power = parseComplexPower(eq, wantsComplexRoots);
    if (power) return power;
    const quad = parseComplexQuadratic(eq, wantsComplexRoots);
    if (quad) return quad;
  }

  // --- a task named in the prose -------------------------------------------
  const expr = extractComplexExpression(prose);
  if (!expr) return null;

  const nth = /\b(?:the\s+)?(\d+|square|cube|cubic|fourth|fifth|sixth)\s*(?:th|st|nd|rd)?\s*roots?\b/i.exec(
    prose
  );
  if (nth && /\broots?\b/i.test(prose)) {
    const n = rootCount(nth[1]);
    if (n && n >= 2 && n <= 12) return { expr, task: { kind: "roots", n } };
  }
  if (/\bmodulus\b|\bmagnitude\b/i.test(prose) && /\bargument\b/i.test(prose)) {
    return { expr, task: { kind: "polar" } };
  }
  if (/\bpolar\s+form\b|\bmodulus[-\s]argument\s+form\b|\btrigonometric\s+form\b/i.test(prose)) {
    return { expr, task: { kind: "polar" } };
  }
  if (/\bmodulus\b|\bmagnitude\b/i.test(prose)) return { expr, task: { kind: "modulus" } };
  if (/\bargument\b|\bamplitude\b/i.test(prose)) return { expr, task: { kind: "argument" } };
  if (/\bconjugate\b/i.test(prose)) return { expr, task: { kind: "conjugate" } };
  if (/\breal\s+part\b/i.test(prose)) return { expr, task: { kind: "part", part: "real" } };
  if (/\bimaginary\s+part\b/i.test(prose)) {
    return { expr, task: { kind: "part", part: "imaginary" } };
  }

  // --- reduce to standard form ---------------------------------------------
  // Either asked for by name, or simply a bare arithmetic expression in i,
  // which has exactly one sensible answer.
  const asksStandard =
    /\bstandard\s+form\b|\bform\s+a\s*\+\s*(?:b\s*i|ib)\b|\breduce\b|\bsimplify\b|\bexpress\b|\bevaluate\b|\bcalculate\b|\bcompute\b|\bfind\b/i.test(
      prose
    );
  if (usesImaginaryUnit(expr) && (asksStandard || !/[a-zA-Z]/.test(expr.replace(/i/g, "")))) {
    return { expr, task: { kind: "standard_form" } };
  }
  return null;
}

function rootCount(token: string): number | null {
  const word: Record<string, number> = {
    square: 2, cube: 3, cubic: 3, fourth: 4, fifth: 5, sixth: 6,
  };
  const w = word[token.toLowerCase()];
  if (w) return w;
  const n = parseInt(token, 10);
  return Number.isInteger(n) ? n : null;
}

/** `f(z) = c` where f is one of the transcendental functions, else null. */
function matchTranscendental(lhs: string): { fn: TranscendentalFn; unknown: string } | null {
  const s = lhs.trim();
  for (const [re, fn] of TRANSCENDENTAL) {
    if (!re.test(s)) continue;
    // The argument must be the BARE unknown — "cosh(2z+1) = 1" is a different
    // (still solvable, but not by this closed form) problem, and the family
    // below would be wrong for it.
    const m =
      fn === "exp"
        ? /^(?:exp\s*\(\s*([a-zA-Z])\s*\)|e\s*\^\s*\(?\s*([a-zA-Z])\s*\)?)$/.exec(s)
        : new RegExp(`^${fn}\\s*\\(\\s*([a-zA-Z])\\s*\\)$`).exec(s);
    if (!m) return null;
    return { fn, unknown: m[1] ?? m[2] ?? "" };
  }
  return null;
}

/** True when the equation already has a REAL solution — then it is an ordinary
 * trig/exponential problem and belongs to the existing engines, not here. */
function realSolutionExists(fn: TranscendentalFn, rhsAscii: string): boolean {
  const c = evalComplex(rhsAscii);
  if (!c || Math.abs(c.im) > 1e-12) return false;
  const v = c.re;
  switch (fn) {
    case "exp":
      return v > 0;
    case "cos":
    case "sin":
      return v >= -1 && v <= 1;
    case "cosh":
      return v >= 1;
    case "sinh":
      return true;
  }
}

/** Split on a top-level `=`, or null. */
function splitTopLevelEquation(s: string): { lhs: string; rhs: string } | null {
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === "(" || c === "{" || c === "[") depth++;
    else if (c === ")" || c === "}" || c === "]") depth--;
    else if (c === "=" && depth === 0 && s[i - 1] !== "<" && s[i - 1] !== ">" && s[i + 1] !== "=") {
      return { lhs: s.slice(0, i), rhs: s.slice(i + 1) };
    }
  }
  return null;
}

// --- a quadratic over ℂ -----------------------------------------------------

/** `\omega` is a variable name, but `latexToAscii` only de-backslashes `\theta`,
 * and mathjs cannot parse the backslash. */
const GREEK_COMMAND =
  /\\(alpha|beta|gamma|delta|epsilon|varepsilon|zeta|eta|theta|vartheta|iota|kappa|lambda|nu|xi|rho|varrho|sigma|tau|upsilon|phi|varphi|chi|psi|omega)(?![A-Za-z])/g;

function deGreek(s: string): string {
  return s.replace(GREEK_COMMAND, "$1");
}

/** Letter runs that are ONE name, not a product of variables. */
const RESERVED_RUNS = new Set<string>([
  ...MATH_WORDS,
  "delta", "epsilon", "varepsilon", "zeta", "eta", "vartheta", "iota", "kappa", "nu", "xi",
  "rho", "varrho", "sigma", "tau", "upsilon", "varphi", "chi", "psi",
  "arcsin", "arccos", "arctan", "asin", "acos", "atan", "log10", "sqrtm", "Inf", "NaN",
]);

/** `2iz` is `2·i·z`, but mathjs reads the glued run as a symbol called "iz" and
 * the imaginary unit disappears with it. Split every letter run that is not a
 * name in its own right. */
function unglueProducts(ascii: string): string {
  return ascii.replace(/[A-Za-z]+/g, (run) =>
    run.length > 1 && !RESERVED_RUNS.has(run) && !RESERVED_RUNS.has(run.toLowerCase())
      ? run.split("").join(" ")
      : run
  );
}

/** The two-letter English words a problem sheet's directive actually uses. */
const TWO_LETTER_WORDS = new Set([
  "of", "in", "is", "it", "to", "if", "at", "by", "on", "as", "we", "do", "an", "or", "be",
  "so", "no", "up", "us", "my", "he", "me", "for",
]);

/** Where the ENGLISH words are. A LaTeX command and a known math name are not
 * English, which is what keeps `\omega`, `sqrt` and `pi` inside the maths.
 * Neither is a run GLUED to an expression: the `iz` of `2iz` is two variables,
 * and reading it as a word threw the front of the equation away. */
function proseSpans(s: string): { start: number; end: number }[] {
  const out: { start: number; end: number }[] = [];
  for (const m of s.matchAll(/(\\?)([A-Za-z]{2,})/g)) {
    const [full, bs, w] = m;
    if (bs || MATH_WORDS.has(w) || MATH_WORDS.has(w.toLowerCase())) continue;
    const start = m.index ?? 0;
    const end = start + full.length;
    if (/[0-9)\]}^_]/.test(s[start - 1] ?? " ")) continue;
    if (/[0-9^_]/.test(s[end] ?? " ")) continue;
    // A bare PAIR of letters is far more often a product (`iz`, `xy`) than an
    // English word, so those have to be named to count as prose.
    if (w.length === 2 && !TWO_LETTER_WORDS.has(w.toLowerCase())) continue;
    out.push({ start, end });
  }
  return out;
}

/** The maths AFTER the last English word — a left-hand side's "Solve …". */
function mathTail(s: string): string {
  const spans = proseSpans(s);
  const cut = spans.length ? spans[spans.length - 1].end : 0;
  return s.slice(cut).replace(/^[\s:;,.]+/, "").trim();
}

/** The maths BEFORE the first English word — a right-hand side's "… , where". */
function mathHead(s: string): string {
  const spans = proseSpans(s);
  const cut = spans.length ? spans[0].start : s.length;
  return s.slice(0, cut).replace(/[\s:;,.]+$/, "").trim();
}

/** Every free variable in `expr`, with the constants that are not variables
 * (`i`, `pi`, `e`) removed. Function names come back too, which is deliberate:
 * a "quadratic" carrying a `sin` is not one, and the caller declines. */
function freeSymbols(expr: string): string[] {
  const out = new Set<string>();
  try {
    parse(expr).traverse((node) => {
      const n = node as unknown as { type: string; name?: string };
      if (n.type === "SymbolNode" && n.name && !["i", "pi", "e"].includes(n.name)) {
        out.add(n.name);
      }
    });
  } catch {
    return [];
  }
  return [...out];
}

const cAdd = (x: Complex, y: Complex): Complex => add(x, y) as Complex;
const cSub = (x: Complex, y: Complex): Complex => subtract(x, y) as Complex;
const cMul = (x: Complex, y: Complex): Complex => multiply(x, y) as Complex;
const cDiv = (x: Complex, y: Complex): Complex => divide(x, y) as Complex;

/**
 * F evaluated at a complex point, or null.
 *
 * The value is BOUND, not pasted in as text. Textual substitution put a literal
 * `(…)` straight after the `i` of `2i z`, which mathjs then read as a call to a
 * function named i — every evaluation failed and the whole family declined.
 */
function evalAt(expr: string, unknown: string, w: Complex): Complex | null {
  return evalComplex(expr, { [unknown]: w });
}

/** The same point, in the matrix representation — the independent route. */
function oracleAt(expr: string, unknown: string, w: Complex): M2 | null {
  return oracle(expr, { [unknown]: { a: w.re, b: w.im } });
}

/** The sample points the interpolation is CHECKED at — deliberately not the
 * three it was built from, and deliberately off the real axis. */
const PROBE_POINTS: [number, number][] = [
  [2, 3],
  [-1.3, 0.7],
  [0, 1],
  [0.5, -1.7],
  [-2.25, -0.4],
];

/**
 * `F` as `c2·z² + c1·z + c0`, or null when it is not a quadratic in `unknown`.
 *
 * The coefficients are read off three evaluations (z = 0, 1, −1) rather than by
 * walking the syntax tree, so any algebraic shape the sheet writes — expanded,
 * bracketed, with the terms on both sides — comes out the same. That alone
 * proves nothing, so the fit is then CHECKED at five further points off the
 * real axis: anything cubic, rational, or transcendental disagrees there and is
 * refused instead of being silently truncated to a quadratic.
 */
function quadraticCoefficients(
  expr: string,
  unknown: string
): { c2: Complex; c1: Complex; c0: Complex } | null {
  const f0 = evalAt(expr, unknown, complex(0, 0));
  const fp = evalAt(expr, unknown, complex(1, 0));
  const fm = evalAt(expr, unknown, complex(-1, 0));
  if (!f0 || !fp || !fm) return null;
  const half = complex(0.5, 0);
  const c0 = f0;
  const c2 = cSub(cMul(cAdd(fp, fm), half), c0);
  const c1 = cMul(cSub(fp, fm), half);
  const scale = Math.max(1, Math.hypot(c2.re, c2.im), Math.hypot(c1.re, c1.im), Math.hypot(c0.re, c0.im));
  // A genuine quadratic: the leading coefficient must not vanish, or this is a
  // linear equation wearing a quadratic's clothes.
  if (Math.hypot(c2.re, c2.im) < 1e-9 * scale) return null;
  for (const [re, im] of PROBE_POINTS) {
    const w = complex(re, im);
    const actual = evalAt(expr, unknown, w);
    if (!actual) return null;
    const model = cAdd(cAdd(cMul(c2, cMul(w, w)), cMul(c1, w)), c0);
    const tol = 1e-9 * scale * Math.max(1, Math.hypot(re, im)) ** 2;
    if (Math.abs(actual.re - model.re) > tol || Math.abs(actual.im - model.im) > tol) return null;
  }
  return { c2, c1, c0 };
}

/** Both sides of an equation as mathjs-readable ascii, with the sentence around
 * them removed and the raw LaTeX kept for the answer's display. */
function equationSides(eq: { lhs: string; rhs: string }): {
  lhs: string;
  rhs: string;
  lhsRaw: string;
  rhsRaw: string;
} | null {
  const lhsRaw = mathTail(eq.lhs);
  const rhsRaw = mathHead(eq.rhs);
  if (!lhsRaw || !rhsRaw) return null;
  const lhs = unglueProducts(deGreek(latexToAscii(lhsRaw))).trim();
  const rhs = unglueProducts(deGreek(latexToAscii(rhsRaw))).trim();
  return lhs && rhs ? { lhs, rhs, lhsRaw, rhsRaw } : null;
}

/** The LaTeX to print the unknown with — `\omega`, not the word "omega". */
function unknownLatexFor(unknown: string, raw: string): string {
  return new RegExp(`\\\\${unknown}(?![A-Za-z])`).test(raw) ? `\\${unknown}` : unknown;
}

/**
 * `zⁿ = c` for n ≥ 3 — De Moivre's problem, which the polynomial engine cannot
 * answer because all n of its roots are complex. It is the existing nth-roots
 * task with the equation unwrapped, so it inherits that gate: every root is
 * raised back to the nth power in the matrix representation.
 */
function parseComplexPower(
  eq: { lhs: string; rhs: string },
  wantsComplexRoots: boolean
): ComplexSpec | null {
  const sides = equationSides(eq);
  if (!sides) return null;
  const m = /^([A-Za-z][A-Za-z0-9]*)\s*\^\s*\(?\s*(\d+)\s*\)?$/.exec(sides.lhs);
  if (!m) return null;
  const n = parseInt(m[2], 10);
  if (!Number.isInteger(n) || n < 3 || n > 12) return null;
  if (!usesImaginaryUnit(sides.rhs) && !wantsComplexRoots && !/^[zw]$/.test(m[1])) return null;
  if (freeSymbols(sides.rhs).length) return null;
  if (!evalComplex(sides.rhs)) return null;
  return { expr: sides.rhs, task: { kind: "roots", n } };
}

/**
 * `az² + bz + c = 0` over ℂ. Gated on the equation genuinely using the
 * imaginary unit — a real quadratic keeps the engine it already had, which
 * factorises and gives exact surds.
 */
function parseComplexQuadratic(
  eq: { lhs: string; rhs: string },
  wantsComplexRoots: boolean
): ComplexSpec | null {
  const sides = equationSides(eq);
  if (!sides) return null;
  const { lhs, rhs, lhsRaw, rhsRaw } = sides;
  const expr = `(${lhs}) - (${rhs})`;

  const vars = freeSymbols(expr);
  if (vars.length !== 1) return null;
  const unknown = vars[0];
  if (!/^[A-Za-z][A-Za-z0-9]*$/.test(unknown)) return null;
  const co = quadraticCoefficients(expr, unknown);
  if (!co) return null;

  if (!usesImaginaryUnit(expr)) {
    // Real coefficients. `z` and `w` are the conventional complex unknowns, and
    // a sheet may also ask for complex roots outright — but a quadratic that HAS
    // real roots keeps the real engine, which factorises and gives exact surds.
    if (!wantsComplexRoots && !/^[zw]$/.test(unknown)) return null;
    const d = cSub(cMul(co.c1, co.c1), cMul(complex(4, 0), cMul(co.c2, co.c0)));
    if (Math.abs(d.im) > 1e-12 || d.re >= 0) return null;
  }

  return {
    expr,
    task: {
      kind: "quadratic",
      unknown,
      unknownLatex: unknownLatexFor(unknown, `${lhsRaw} ${rhsRaw}`),
    },
  };
}

/**
 * Pull the complex expression out of the prose. Any `x = …` chunk is taken as a
 * DEFINITION and substituted into the remaining chunks, so "simplify z̄ where
 * z = 2+3i" answers about z̄ rather than about z — the difference between 2−3i
 * and 2+3i, which is the whole question.
 *
 * A candidate has to survive two filters: it must actually use the imaginary
 * unit (or a conjugate), and it must EVALUATE to a number. A free variable
 * therefore never gets through — the matrix oracle could not check it anyway.
 */
function extractComplexExpression(prose: string): string | null {
  const chunks = mathChunks(prose);
  const defs = new Map<string, string>();
  const targets: string[] = [];
  for (const chunk of chunks) {
    const def = asDefinition(chunk);
    if (def) {
      const body = latexToAscii(def.body).trim();
      if (body && evalComplex(body)) defs.set(def.name, body);
      continue;
    }
    targets.push(chunk);
  }

  const viable: string[] = [];
  for (const chunk of targets) {
    const ascii = substitute(latexToAscii(chunk).trim(), defs);
    if (!ascii) continue;
    if (!usesImaginaryUnit(ascii) && !/conj\s*\(/.test(ascii)) continue;
    if (!evalComplex(ascii)) continue;
    viable.push(ascii);
  }
  // The richest evaluable fragment is the one the question is about; a stray
  // "a+bi" from the phrase "in the form a + bi" never evaluates, so it is gone
  // by this point.
  if (viable.length) {
    return viable.reduce((best, s) => (s.length > best.length ? s : best));
  }
  // Nothing but a definition — then the definition IS the number in question.
  for (const body of defs.values()) {
    if (usesImaginaryUnit(body)) return body;
  }
  return null;
}

// --- Solving ----------------------------------------------------------------

export function solveComplex(cls: { complex?: ComplexSpec }): SolveCandidate | null {
  const spec = cls.complex;
  if (!spec) return null;
  switch (spec.task.kind) {
    case "standard_form":
      return solveStandardForm(spec);
    case "modulus":
      return solveModulus(spec);
    case "argument":
      return solveArgument(spec);
    case "conjugate":
      return solveConjugate(spec);
    case "polar":
      return solvePolar(spec);
    case "part":
      return solvePart(spec, spec.task.part);
    case "roots":
      return solveRoots(spec, spec.task.n);
    case "solve":
      return solveTranscendental(spec.task.fn, spec.task.rhs);
    case "quadratic":
      return solveComplexQuadratic(spec, spec.task.unknown, spec.task.unknownLatex);
  }
}

function step(ascii: string, latex: string, operationCode: string): RawStep {
  return { ascii, latex, operationCode };
}

function solveStandardForm(spec: ComplexSpec): SolveCandidate | null {
  const z = evalComplex(spec.expr);
  if (!z) return null;
  const proved = () => oracleAgrees(spec.expr, z);
  if (!proved()) return null;
  const latex = standardLatex(z);
  const plain = standardPlain(z);
  return {
    answer: { latex, plain },
    methods: [
      {
        id: "complex_standard_form",
        name: "Reduce to a + bi",
        examPick: true,
        steps: [
          step(spec.expr, spec.expr, "IDENTIFY_EXPRESSION"),
          step(
            `Re = ${realPlain(z.re)}, Im = ${realPlain(z.im)}`,
            `\\operatorname{Re} = ${realLatex(z.re)},\\; \\operatorname{Im} = ${realLatex(z.im)}`,
            "SEPARATE_PARTS"
          ),
          step(plain, latex, "RESULT"),
        ],
      },
    ],
    verify: proved,
  };
}

function solveModulus(spec: ComplexSpec): SolveCandidate | null {
  const z = evalComplex(spec.expr);
  if (!z) return null;
  const m = oracle(spec.expr);
  if (!m) return null;
  const r = Number(abs(z));
  // |z| is non-negative and its SQUARE is a² + b² — the defining property,
  // checked against the oracle's parts rather than against mathjs's own abs.
  const proved = () =>
    oracleAgrees(spec.expr, z) && r >= 0 && close(r * r, m.a * m.a + m.b * m.b);
  if (!proved()) return null;
  return {
    answer: { latex: `|z| = ${realLatex(r)}`, plain: `|z| = ${realPlain(r)}` },
    methods: [
      {
        id: "complex_modulus",
        name: "Modulus",
        examPick: true,
        steps: [
          step(`z = ${standardPlain(z)}`, `z = ${standardLatex(z)}`, "IDENTIFY_EXPRESSION"),
          step(
            `|z| = sqrt(${realPlain(z.re)}^2 + ${realPlain(z.im)}^2)`,
            `|z| = \\sqrt{(${realLatex(z.re)})^2 + (${realLatex(z.im)})^2}`,
            "APPLY_MODULUS",
          ),
          step(`|z| = ${realPlain(r)}`, `|z| = ${realLatex(r)}`, "RESULT"),
        ],
      },
    ],
    verify: proved,
  };
}

function solveArgument(spec: ComplexSpec): SolveCandidate | null {
  const z = evalComplex(spec.expr);
  if (!z) return null;
  if (Math.abs(z.re) < 1e-14 && Math.abs(z.im) < 1e-14) return null; // arg 0 undefined
  const theta = Number(arg(z));
  const r = Number(abs(z));
  // The PRINCIPAL argument lies in (−π, π] and must reconstruct z.
  const proved = () =>
    oracleAgrees(spec.expr, z) &&
    theta > -Math.PI - 1e-12 &&
    theta <= Math.PI + 1e-12 &&
    close(r * Math.cos(theta), z.re, 1e-9) &&
    close(r * Math.sin(theta), z.im, 1e-9);
  if (!proved()) return null;
  const deg = String(Number(((theta * 180) / Math.PI).toFixed(4)));
  return {
    answer: {
      latex: `\\arg z = ${angleLatex(theta)}`,
      plain: `arg z = ${Number(theta.toFixed(6))} rad (${deg} degrees)`,
    },
    methods: [
      {
        id: "complex_argument",
        name: "Principal argument",
        examPick: true,
        steps: [
          step(`z = ${standardPlain(z)}`, `z = ${standardLatex(z)}`, "IDENTIFY_EXPRESSION"),
          step(
            `tan(arg z) = ${realPlain(z.im)}/${realPlain(z.re)}`,
            `\\tan(\\arg z) = \\frac{${realLatex(z.im)}}{${realLatex(z.re)}}`,
            "APPLY_ARGUMENT"
          ),
          step(
            `arg z = ${angleLatex(theta)}`,
            `\\arg z = ${angleLatex(theta)} \\quad (${deg}^{\\circ})`,
            "RESULT"
          ),
        ],
      },
    ],
    verify: proved,
  };
}

function solveConjugate(spec: ComplexSpec): SolveCandidate | null {
  const z = evalComplex(spec.expr);
  if (!z) return null;
  const zbar = complex(z.re, -z.im);
  const product = multiply(z, zbar) as Complex;
  const sum = add(z, zbar) as Complex;
  // z·z̄ is real and equals |z|², and z + z̄ = 2·Re z. Both are the DEFINING
  // properties of the conjugate, so neither reuses the computation above.
  const proved = () =>
    oracleAgrees(spec.expr, z) &&
    Math.abs(product.im) < 1e-9 &&
    close(product.re, z.re * z.re + z.im * z.im) &&
    Math.abs(sum.im) < 1e-9 &&
    close(sum.re, 2 * z.re);
  if (!proved()) return null;
  return {
    answer: { latex: `\\bar{z} = ${standardLatex(zbar)}`, plain: `conj(z) = ${standardPlain(zbar)}` },
    methods: [
      {
        id: "complex_conjugate",
        name: "Conjugate",
        examPick: true,
        steps: [
          step(`z = ${standardPlain(z)}`, `z = ${standardLatex(z)}`, "IDENTIFY_EXPRESSION"),
          step(
            `flip the sign of the imaginary part`,
            `\\overline{a + bi} = a - bi`,
            "APPLY_CONJUGATE"
          ),
          step(standardPlain(zbar), `\\bar{z} = ${standardLatex(zbar)}`, "RESULT"),
        ],
      },
    ],
    verify: proved,
  };
}

function solvePolar(spec: ComplexSpec): SolveCandidate | null {
  const z = evalComplex(spec.expr);
  if (!z) return null;
  if (Math.abs(z.re) < 1e-14 && Math.abs(z.im) < 1e-14) return null;
  const r = Number(abs(z));
  const theta = Number(arg(z));
  // The polar form must RECONSTRUCT z exactly — that is the whole claim.
  const proved = () =>
    oracleAgrees(spec.expr, z) &&
    r >= 0 &&
    close(r * Math.cos(theta), z.re, 1e-9) &&
    close(r * Math.sin(theta), z.im, 1e-9);
  if (!proved()) return null;
  const a = angleLatex(theta);
  const latex = `${realLatex(r)}\\left(\\cos ${a} + i\\sin ${a}\\right)`;
  return {
    answer: {
      latex,
      plain: `|z| = ${realPlain(r)}, arg z = ${Number(theta.toFixed(6))}`,
    },
    methods: [
      {
        id: "complex_polar",
        name: "Modulus–argument form",
        examPick: true,
        steps: [
          step(`z = ${standardPlain(z)}`, `z = ${standardLatex(z)}`, "IDENTIFY_EXPRESSION"),
          step(`|z| = ${realPlain(r)}`, `r = |z| = ${realLatex(r)}`, "APPLY_MODULUS"),
          step(`arg z = ${angleLatex(theta)}`, `\\theta = \\arg z = ${a}`, "APPLY_ARGUMENT"),
          step(`z = ${realPlain(r)}(cos ${a} + i sin ${a})`, `z = ${latex}`, "RESULT"),
        ],
      },
    ],
    verify: proved,
  };
}

function solvePart(spec: ComplexSpec, part: "real" | "imaginary"): SolveCandidate | null {
  const z = evalComplex(spec.expr);
  if (!z) return null;
  const proved = () => oracleAgrees(spec.expr, z);
  if (!proved()) return null;
  const v = part === "real" ? z.re : z.im;
  const op = part === "real" ? "\\operatorname{Re}" : "\\operatorname{Im}";
  return {
    answer: { latex: `${op} z = ${realLatex(v)}`, plain: `${part} part = ${realPlain(v)}` },
    methods: [
      {
        id: "complex_part",
        name: part === "real" ? "Real part" : "Imaginary part",
        examPick: true,
        steps: [
          step(spec.expr, spec.expr, "IDENTIFY_EXPRESSION"),
          step(standardPlain(z), `z = ${standardLatex(z)}`, "REDUCE_TO_STANDARD_FORM"),
          step(`${part} part = ${realPlain(v)}`, `${op} z = ${realLatex(v)}`, "RESULT"),
        ],
      },
    ],
    verify: proved,
  };
}

function solveRoots(spec: ComplexSpec, n: number): SolveCandidate | null {
  const z = evalComplex(spec.expr);
  if (!z) return null;
  const r = Number(abs(z));
  if (r < 1e-14) return null; // every root of 0 is 0 — nothing to enumerate
  const theta = Number(arg(z));
  const rootR = Math.pow(r, 1 / n);
  const roots: Complex[] = [];
  for (let k = 0; k < n; k++) {
    const a = (theta + 2 * Math.PI * k) / n;
    roots.push(complex(rootR * Math.cos(a), rootR * Math.sin(a)));
  }
  // THE gate: each root, raised to the nth power by repeated multiplication in
  // the matrix representation, must return to z — and the n roots must be
  // distinct, or the list is not the full set it claims to be.
  const proved = () => {
    if (!oracleAgrees(spec.expr, z)) return false;
    for (const w of roots) {
      const back = mPowInt({ a: w.re, b: w.im }, n);
      if (!close(back.a, z.re, 1e-7) || !close(back.b, z.im, 1e-7)) return false;
    }
    for (let p = 0; p < roots.length; p++) {
      for (let q = p + 1; q < roots.length; q++) {
        if (
          Math.abs(roots[p].re - roots[q].re) < 1e-7 &&
          Math.abs(roots[p].im - roots[q].im) < 1e-7
        ) {
          return false;
        }
      }
    }
    return true;
  };
  if (!proved()) return null;
  const listLatex = roots.map((w, k) => `z_{${k}} = ${standardLatex(w)}`).join(",\\; ");
  return {
    answer: {
      latex: listLatex,
      plain: roots.map((w, k) => `z${k} = ${standardPlain(w)}`).join(", "),
    },
    methods: [
      {
        id: "complex_roots",
        name: `The ${n} ${n === 2 ? "square" : n === 3 ? "cube" : `${n}th`} roots`,
        examPick: true,
        steps: [
          step(`z = ${standardPlain(z)}`, `z = ${standardLatex(z)}`, "IDENTIFY_EXPRESSION"),
          step(
            `z = ${realPlain(r)}(cos ${angleLatex(theta)} + i sin ${angleLatex(theta)})`,
            `z = ${realLatex(r)}\\left(\\cos ${angleLatex(theta)} + i\\sin ${angleLatex(theta)}\\right)`,
            "CONVERT_TO_POLAR"
          ),
          step(
            `roots have modulus ${realPlain(rootR)}`,
            `|z_k| = ${realLatex(r)}^{1/${n}} = ${realLatex(rootR)},\\quad \\theta_k = \\frac{${angleLatex(theta)} + 2k\\pi}{${n}}`,
            "APPLY_DE_MOIVRE"
          ),
          step(roots.map((w) => standardPlain(w)).join(", "), listLatex, "RESULT"),
        ],
      },
    ],
    verify: proved,
  };
}

/** The principal square root of a complex number, by halving its argument. */
function complexSqrt(d: Complex): Complex {
  const r = Math.hypot(d.re, d.im);
  const t = Math.atan2(d.im, d.re);
  const s = Math.sqrt(r);
  return complex(s * Math.cos(t / 2), s * Math.sin(t / 2));
}

/**
 * `az² + bz + c = 0` over ℂ.
 *
 * THE GATE. The answer comes from the quadratic formula and a polar square
 * root; the check shares none of it. Each root is SUBSTITUTED BACK into the
 * original equation and evaluated in the real 2×2 matrix representation, where
 * there is no complex type and no square root at all — a slip in the formula,
 * in the discriminant, or in the branch of √D shows up as a non-zero residual.
 *
 * Completeness is proven separately: `a(z − r₁)(z − r₂)` must reproduce F at
 * every probe point, so the two roots are not merely roots but ALL of them.
 */
function solveComplexQuadratic(
  spec: ComplexSpec,
  unknown: string,
  unknownLatex: string
): SolveCandidate | null {
  const co = quadraticCoefficients(spec.expr, unknown);
  if (!co) return null;
  const { c2, c1, c0 } = co;
  const scale = Math.max(
    1,
    Math.hypot(c2.re, c2.im),
    Math.hypot(c1.re, c1.im),
    Math.hypot(c0.re, c0.im)
  );

  const disc = cSub(cMul(c1, c1), cMul(complex(4, 0), cMul(c2, c0)));
  const root = complexSqrt(disc);
  const twoA = cMul(complex(2, 0), c2);
  const vertex = cDiv(cSub(complex(0, 0), c1), twoA);
  let r1 = cAdd(vertex, cDiv(root, twoA));
  let r2 = cSub(vertex, cDiv(root, twoA));
  if (![r1.re, r1.im, r2.re, r2.im].every(Number.isFinite)) return null;
  const repeated =
    Math.hypot(r1.re - r2.re, r1.im - r2.im) < 1e-7 * Math.max(1, Math.hypot(r1.re, r1.im));
  // A zero discriminant computes as ~1e-16, whose square root is ~1e-8 — big
  // enough to print `0 + 1i` where the answer is `i`. The repeated root is
  // −b/2a exactly, so take that instead of either signed branch.
  if (repeated) {
    r1 = vertex;
    r2 = vertex;
  }
  const roots = repeated ? [r1] : [r1, r2];

  const proved = () => {
    // 1. Each root really is one — checked by the matrix oracle, not by mathjs.
    for (const w of roots) {
      const m = oracleAt(spec.expr, unknown, w);
      if (!m) return false;
      const tol = 1e-7 * scale * Math.max(1, Math.hypot(w.re, w.im)) ** 2;
      if (Math.abs(m.a) > tol || Math.abs(m.b) > tol) return false;
    }
    // 2. There are no OTHERS — the factorisation reproduces the equation.
    for (const [re, im] of PROBE_POINTS) {
      const z = complex(re, im);
      const actual = oracleAt(spec.expr, unknown, z);
      if (!actual) return false;
      const model = cMul(c2, cMul(cSub(z, r1), cSub(z, r2)));
      const tol = 1e-7 * scale * Math.max(1, Math.hypot(re, im)) ** 2;
      if (Math.abs(actual.a - model.re) > tol || Math.abs(actual.b - model.im) > tol) return false;
    }
    return true;
  };
  if (!proved()) return null;

  const u = unknownLatex;
  const listLatex = repeated
    ? `${u} = ${standardLatex(r1)} \\text{ (repeated)}`
    : roots.map((w) => `${u} = ${standardLatex(w)}`).join(",\\; ");
  const listPlain = repeated
    ? `${unknown} = ${standardPlain(r1)} (repeated)`
    : roots.map((w) => `${unknown} = ${standardPlain(w)}`).join(", ");

  // `ω² = k` reads as "take square roots", not as "apply the formula with b = 0".
  const pureSquare = Math.hypot(c1.re, c1.im) < 1e-12 * scale;
  const k = cDiv(cSub(complex(0, 0), c0), c2);
  const kr = Math.hypot(k.re, k.im);
  const kt = Math.atan2(k.im, k.re);

  const steps: RawStep[] = pureSquare
    ? [
        step(
          `${unknown}^2 = ${standardPlain(k)}`,
          `${u}^2 = ${standardLatex(k)}`,
          "IDENTIFY_EQUATION"
        ),
        step(
          `${standardPlain(k)} = ${realPlain(kr)}(cos ${angleLatex(kt)} + i sin ${angleLatex(kt)})`,
          `${standardLatex(k)} = ${realLatex(kr)}\\left(\\cos ${angleLatex(kt)} + i\\sin ${angleLatex(kt)}\\right)`,
          "CONVERT_TO_POLAR"
        ),
        step(
          `${unknown} = ±${realPlain(Math.sqrt(kr))}(cos ${angleLatex(kt / 2)} + i sin ${angleLatex(kt / 2)})`,
          `${u} = \\pm ${realLatex(Math.sqrt(kr))}\\left(\\cos ${angleLatex(kt / 2)} + i\\sin ${angleLatex(kt / 2)}\\right)`,
          "APPLY_DE_MOIVRE"
        ),
        step(listPlain, listLatex, "RESULT"),
      ]
    : [
        step(
          `a = ${standardPlain(c2)}, b = ${standardPlain(c1)}, c = ${standardPlain(c0)}`,
          `a = ${standardLatex(c2)},\\quad b = ${standardLatex(c1)},\\quad c = ${standardLatex(c0)}`,
          "IDENTIFY_COEFFICIENTS"
        ),
        step(
          `b^2 - 4ac = ${standardPlain(disc)}`,
          `b^2 - 4ac = ${standardLatex(disc)}`,
          "COMPUTE_DISCRIMINANT"
        ),
        step(
          `sqrt(${standardPlain(disc)}) = ±${standardPlain(root)}`,
          `\\sqrt{${standardLatex(disc)}} = \\pm\\left(${standardLatex(root)}\\right)`,
          "COMPLEX_SQUARE_ROOT"
        ),
        step(
          `${unknown} = (-b ± sqrt(b^2 - 4ac)) / (2a)`,
          `${u} = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}`,
          "APPLY_QUADRATIC_FORMULA"
        ),
        step(listPlain, listLatex, "RESULT"),
      ];

  return {
    answer: { latex: listLatex, plain: listPlain },
    methods: [
      {
        id: "complex_quadratic",
        name: pureSquare ? "Square roots over ℂ" : "The quadratic formula over ℂ",
        examPick: true,
        steps,
      },
    ],
    verify: proved,
  };
}

/**
 * Solve `f(z) = c` over ℂ, where f ∈ {exp, cos, sin, cosh, sinh}. The solution
 * set is an infinite FAMILY, so the answer is symbolic in n — and the gate
 * substitutes several concrete members back into the original equation.
 */
function solveTranscendental(fn: TranscendentalFn, rhs: string): SolveCandidate | null {
  const c = evalComplex(rhs);
  if (!c) return null;

  /** The principal branch value(s) and the period added by each integer n. */
  let branches: Complex[];
  let period: Complex;
  try {
    switch (fn) {
      case "exp": {
        const l = evalComplex(`log(complex(${c.re}, ${c.im}))`);
        if (!l) return null;
        branches = [l];
        period = complex(0, 2 * Math.PI); // e^z is 2πi-periodic
        break;
      }
      case "cos": {
        const a = evalComplex(`acos(complex(${c.re}, ${c.im}))`);
        if (!a) return null;
        branches = [a, complex(-a.re, -a.im)]; // cos is even
        period = complex(2 * Math.PI, 0);
        break;
      }
      case "sin": {
        const a = evalComplex(`asin(complex(${c.re}, ${c.im}))`);
        if (!a) return null;
        branches = [a, complex(Math.PI - a.re, -a.im)]; // sin(π − z) = sin z
        period = complex(2 * Math.PI, 0);
        break;
      }
      case "cosh": {
        const a = evalComplex(`acosh(complex(${c.re}, ${c.im}))`);
        if (!a) return null;
        branches = [a, complex(-a.re, -a.im)]; // cosh is even
        period = complex(0, 2 * Math.PI);
        break;
      }
      case "sinh": {
        const a = evalComplex(`asinh(complex(${c.re}, ${c.im}))`);
        if (!a) return null;
        branches = [a, complex(-a.re, Math.PI - a.im)]; // sinh(iπ − z) = sinh z
        period = complex(0, 2 * Math.PI);
        break;
      }
    }
  } catch {
    return null;
  }

  const apply = (z: Complex): Complex | null =>
    evalComplex(`${fn}(complex(${z.re}, ${z.im}))`);

  // THE gate — substitution, exactly as everywhere else in this app: every
  // branch, at several values of n, must satisfy the ORIGINAL equation.
  const proved = () => {
    for (const b of branches) {
      for (const n of [-2, -1, 0, 1, 2]) {
        const z = complex(b.re + n * period.re, b.im + n * period.im);
        const got = apply(z);
        if (!got) return false;
        if (!close(got.re, c.re, 1e-7) || !close(got.im, c.im, 1e-7)) return false;
      }
    }
    // The branches must be genuinely different solutions, or the "±" is a lie.
    if (branches.length === 2) {
      const d = complex(branches[0].re - branches[1].re, branches[0].im - branches[1].im);
      const k = period.re !== 0 ? d.re / period.re : d.im / period.im;
      if (Math.abs(k - Math.round(k)) < 1e-9) branches = [branches[0]];
    }
    return true;
  };
  if (!proved()) return null;

  const periodLatex = period.re !== 0 ? "2n\\pi" : "2n\\pi i";
  const parts = branches.map((b) => {
    const head = standardLatex(complex(b.re, b.im));
    return `${head} + ${periodLatex}`;
  });
  const latex = `z = ${parts.join(",\\quad z = ")} \\quad (n \\in \\mathbb{Z})`;
  const plain = branches
    .map((b) => `z = ${standardPlain(complex(b.re, b.im))} + ${period.re !== 0 ? "2npi" : "2npi i"}`)
    .join(", ");
  const fnLatex = fn === "exp" ? "e^{z}" : `\\${fn} z`;
  return {
    answer: { latex, plain: `${plain} (n integer)` },
    methods: [
      {
        id: "complex_solve",
        name: "Solve over the complex numbers",
        examPick: true,
        steps: [
          step(`${fn}(z) = ${standardPlain(c)}`, `${fnLatex} = ${standardLatex(c)}`, "IDENTIFY_EQUATION"),
          step(
            `principal solution`,
            `z_{0} = \\operatorname{${fn === "exp" ? "log" : `a${fn}`}}\\left(${standardLatex(c)}\\right)`,
            "INVERT_FUNCTION"
          ),
          step(
            `add the period ${period.re !== 0 ? "2npi" : "2npi i"}`,
            `${fnLatex} \\text{ has period } ${period.re !== 0 ? "2\\pi" : "2\\pi i"}`,
            "ADD_PERIOD"
          ),
          step(plain, latex, "RESULT"),
        ],
      },
    ],
    verify: proved,
  };
}

/** The §4 problemType for a complex task. */
export function complexProblemType(task: ComplexTask): string {
  switch (task.kind) {
    case "standard_form":
      return "complex_standard_form";
    case "modulus":
      return "complex_modulus";
    case "argument":
      return "complex_argument";
    case "conjugate":
      return "complex_conjugate";
    case "polar":
      return "complex_polar_form";
    case "part":
      return "complex_part";
    case "roots":
      return "complex_roots";
    case "solve":
      return "complex_equation";
    case "quadratic":
      return "complex_quadratic";
  }
}
