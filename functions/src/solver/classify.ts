/**
 * Classify a recognized problem → a solving strategy.
 *
 * This routes to a deterministic engine where one exists (arithmetic, simplify,
 * linear/quadratic equations, derivatives) and to the constrained LLM-candidate
 * tier otherwise (integrals, higher-degree/trig equations, systems). Every path
 * carries a `verifyMode`: the answer is proven before it is ever returned.
 */
import { parseLinalg, parseVectors } from "./linalg";
import { parseLinearSystem } from "./linsystem";
import { parseOde } from "./ode";
import { parseStatistics } from "./statistics";
import { parseTaylor } from "./taylor";
import { Classification, Strategy, VerifyMode } from "./types";
import {
  cleanLatex,
  latexToAscii,
  normalizeMacros,
  splitEquation,
  stripOuterParens,
  variablesIn,
} from "./latex";

/** Preferred unknown when several variables are present. */
function pickUnknown(vars: string[]): string {
  if (vars.length === 0) return "x";
  for (const pref of ["x", "y", "z", "t", "n"]) {
    if (vars.includes(pref)) return pref;
  }
  return vars[0];
}

/** Split a (possibly multi-) equation ascii string into `lhs = rhs` parts. */
export function equationParts(ascii: string): { lhs: string; rhs: string }[] {
  // Latex row breaks were turned into spaces already; split on ; and newlines,
  // and on commas only when every resulting part is itself an equation.
  let chunks = ascii.split(/[;\n]/).map((c) => c.trim()).filter(Boolean);
  if (chunks.length === 1 && ascii.includes(",")) {
    const commaParts = ascii.split(",").map((c) => c.trim()).filter(Boolean);
    if (commaParts.length > 1 && commaParts.every((p) => p.includes("="))) {
      chunks = commaParts;
    }
  }
  return chunks
    .filter((c) => c.includes("="))
    .map((c) => splitEquation(c))
    .map(({ lhs, rhs }) => ({ lhs, rhs }));
}

export function classify(rawLatex: string): Classification {
  // Fold display/text macro variants (\dfrac, \mathrm{d}x, \operatorname, unicode
  // ·×÷) onto their canonical spelling FIRST, so every raw-LaTeX detector below
  // (\int, \frac{d}{dx}, ODE, …) sees one form. cleanLatex re-applies it for the
  // ascii path; it's idempotent.
  rawLatex = normalizeMacros(rawLatex);
  const latex = cleanLatex(rawLatex);
  // A cases/aligned system writes its equations with `\\` row breaks; turn those
  // into `;` (and drop the wrapper + `&` alignment tabs) so equationParts can
  // split them. Only when such an environment is present — matrices (pmatrix,
  // handled separately from rawLatex) are untouched.
  const rawForAscii =
    /\\begin\s*\{\s*(?:cases|aligned|split|gather)/i.test(rawLatex)
      ? rawLatex
          .replace(/\\begin\s*\{\s*(?:cases|aligned|split|gather)\s*\}/gi, " ")
          .replace(/\\end\s*\{\s*(?:cases|aligned|split|gather)\s*\}/gi, " ")
          .replace(/\\\\/g, " ; ")
          .replace(/&/g, " ")
      : rawLatex;
  const ascii = latexToAscii(rawForAscii);

  const base = (
    problemType: string,
    strategy: Strategy,
    unknown: string,
    isEquation: boolean,
    verifyMode: VerifyMode,
    extra: Partial<Classification> = {}
  ): Classification => ({
    problemType,
    strategy,
    unknown,
    isEquation,
    ascii,
    latex,
    verifyMode,
    ...extra,
  });

  // --- Proofs / abstract algebra / real analysis → the AI tutor -----------
  // Detected FIRST: these have no answer to compute-and-verify, so instead of
  // faking one (or a misleading "couldn't verify"), classify marks them so solve
  // returns a routeToTutor state and the client offers to work through it.
  if (looksLikeConceptual(rawLatex)) {
    return base("conceptual", "conceptual", "x", false, "none");
  }

  // --- Taylor / Maclaurin series (deterministic via mathjs) ---------------
  // Distinctive keyword, so detected first. Coefficients are built by repeated
  // differentiation and proven by an independent contact-order test; verifyMode
  // "none" so an unparsed request declines rather than hitting the LLM tier.
  const taylor = parseTaylor(rawLatex);
  if (taylor) {
    return base(
      taylor.center === 0 ? "maclaurin_series" : "taylor_series",
      "taylor",
      taylor.variable,
      false,
      "none",
      {
        taylorFn: taylor.fn,
        taylorCenter: taylor.center,
        taylorCenterLatex: taylor.centerLatex,
        taylorOrder: taylor.order,
      }
    );
  }

  // --- Integral: ∫ f dx (indefinite) or ∫_a^b f dx (definite) -----------
  if (/\\int|∫/.test(rawLatex)) {
    const parsed = parseIntegral(rawLatex);
    if (parsed.definite) {
      // Verified by NUMERIC integration (a deterministic engine) agreeing with
      // the candidate value — see verifyCandidate.
      return base(
        "definite_integral",
        "llm_candidate",
        parsed.unknown,
        false,
        "definite_integral",
        {
          integrand: parsed.integrand,
          lowerBound: parsed.lower,
          upperBound: parsed.upper,
        }
      );
    }
    // Indefinite: verified by differentiating the antiderivative back.
    return base("integral", "llm_candidate", parsed.unknown, false, "derivative_back", {
      integrand: parsed.integrand,
    });
  }

  // --- ODEs (y' = 2y, y'' + y = 0, \frac{dy}{dx} = …) ---------------------
  // A differential equation (a derivative OF the dependent variable, with an `=`)
  // must be caught BEFORE the plain d/dx block. No engine integrates it, so the
  // LLM proposes a solution y(x) and the "ode" gate substitutes it back in.
  const ode = parseOde(rawLatex);
  if (ode) {
    return base("differential_equation", "llm_candidate", ode.depVar, true, "ode", {
      odeResidual: ode.residual,
      odeDepVar: ode.depVar,
      odeIndepVar: ode.indepVar,
      odeOrder: ode.order,
      odeInitial: ode.initial,
    });
  }

  // --- Derivative: d/dx(...) --------------------------------------------
  // Match the operator on the ORIGINAL LaTeX and take the operand from the text
  // that follows it — deriving the operand from the ascii is fragile because the
  // `\frac{d}{dx}` conversion introduces stray parentheses.
  // Ordinary d/dx AND partial ∂/∂x share ONE path: mathjs `derivative(f, v)`
  // already differentiates w.r.t. v holding every other symbol constant (that IS
  // the partial derivative), and verifyDerivative samples all free variables — so
  // a partial verifies exactly like a single-variable derivative.
  // A HIGHER-ORDER Leibniz operator (d²/dx², d³/dx³) is matched first — its `d^n`
  // carries the order. Without this it fell through to the algebra path where
  // mathjs read `dx` as a phantom variable and every candidate was rejected.
  const higherRe = new RegExp(
    [
      // \frac{d^2}{dx^2}
      String.raw`\\frac\s*\{\s*d\s*\^\s*\{?\s*(\d+)\s*\}?\s*\}\s*\{\s*d\s*([a-zA-Z])\s*\^\s*\{?\s*\d+\s*\}?\s*\}`,
      // d^2/dx^2
      String.raw`\bd\s*\^\s*\{?\s*(\d+)\s*\}?\s*\/\s*d\s*([a-zA-Z])\s*\^\s*\{?\s*\d+\s*\}?`,
    ].join("|")
  );
  const derivRe = new RegExp(
    [
      String.raw`\\frac\s*\{\s*d\s*\}\s*\{\s*d\s*([a-zA-Z])\s*\}`, // \frac{d}{dx}
      String.raw`\\frac\s*\{\s*\\partial\s*\}\s*\{\s*\\partial\s*([a-zA-Z])\s*\}`, // \frac{\partial}{\partial x}
      String.raw`\bd\s*\/\s*d\s*([a-zA-Z])`, // d/dx
      String.raw`\\partial\s*\/\s*\\partial\s*([a-zA-Z])`, // \partial/\partial x
      String.raw`\\partial\s*_\s*\{?\s*([a-zA-Z])\s*\}?`, // \partial_x
      String.raw`∂\s*\/\s*∂\s*([a-zA-Z])`, // ∂/∂x
      String.raw`∂\s*_\s*([a-zA-Z])`, // ∂_x
    ].join("|")
  );
  const higher = rawLatex.match(higherRe);
  const deriv = higher ?? rawLatex.match(derivRe);
  if (deriv) {
    let order = 1;
    let unknown: string;
    if (higher) {
      const groups = deriv.slice(1).filter((g): g is string => Boolean(g));
      order = Number(groups.find((g) => /^\d+$/.test(g)) ?? 1);
      unknown = groups.find((g) => /^[a-zA-Z]$/.test(g)) ?? "x";
    } else {
      unknown = deriv.slice(1).find((g) => g) ?? "x";
    }
    const isPartial = /\\partial|∂/.test(deriv[0]);
    const derivType = isPartial ? "partial_derivative" : "derivative";
    const before = rawLatex.slice(0, deriv.index ?? 0).trim();
    // Square-bracket grouping (`d/dx[f]`, `\left[…\right]`) is common textbook
    // notation — normalize `[ ]` to `( )` so stripOuterParens + mathjs accept it.
    const afterLatex = cleanLatex(
      rawLatex.slice((deriv.index ?? 0) + deriv[0].length)
    )
      .replace(/\[/g, "(")
      .replace(/\]/g, ")");
    const stripped = stripOuterParens(afterLatex);
    const wasWrapped = stripped !== afterLatex;
    const target = latexToAscii(stripped);
    // Only a BARE derivative is safe to differentiate directly: nothing before
    // the operator (a coefficient like `2·d/dx(...)` would be silently dropped),
    // and the operand must be the whole remainder — either fully parenthesized
    // or a single term with no top-level +/- the operator wouldn't scope over.
    // Anything else would let a wrong answer pass its own gate, so route it to
    // the verified-candidate tier (here: couldn't-verify).
    if (
      before !== "" ||
      (!wasWrapped && hasTopLevelAddSub(target)) ||
      order < 1 ||
      order > 6
    ) {
      return base(derivType, "llm_candidate", unknown, false, "none");
    }
    return base(derivType, "derivative", unknown, false, "derivative_back", {
      derivativeTarget: target,
      derivativeOrder: order,
    });
  }

  // --- Descriptive statistics over a data set (mean/median/std of a list) ---
  // A DETERMINISTIC path: the engine computes it and cross-checks by an
  // independent recompute, so it needs no equation. Detected before the
  // expression/equation split (a stats query usually has no `=`).
  const statQuery = parseStatistics(rawLatex);
  if (statQuery) {
    // verifyMode "none": the deterministic path IS the verification (compute +
    // independent recompute). If it can't handle a case, decline — don't hand a
    // stats query to the generic LLM tier, which has no stats verification.
    return base("statistics", "statistics", "x", false, "none", {
      statKind: statQuery.stat,
      statData: statQuery.data,
    });
  }

  // --- Inequalities (2x+3 < 7, x²-5x+6 ≥ 0) --------------------------------
  // splitEquation strips the comparison operator, so a bare inequality used to
  // fall into simplify and only echo an expression. Route it to the verified
  // LLM tier: the model proposes a solution SET, and the interval-sampling gate
  // proves every point inside satisfies it (and every point outside doesn't).
  const ineq = parseInequality(rawLatex);
  if (ineq) {
    return base("inequality", "llm_candidate", ineq.unknown, true, "inequality", {
      ineqLhs: ineq.lhs,
      ineqRhs: ineq.rhs,
      ineqOp: ineq.op,
    });
  }

  // --- Linear algebra (determinant / inverse / eigenvalues / product) ------
  // DETERMINISTIC via mathjs; the gap was parsing the matrix + a verify gate.
  // Property-checked (A·A⁻¹=I, det(A−λI)=0, independent cofactor det, and an
  // independent row×column recompute for the product).
  const linalg = parseLinalg(rawLatex);
  if (linalg) {
    const linalgType: Record<string, string> = {
      multiply: "matrix_product",
      add: "matrix_sum",
      subtract: "matrix_difference",
    };
    return base(
      linalgType[linalg.op] ?? "linalg",
      "linalg",
      "x",
      false,
      "none",
      { linalgOp: linalg.op, matrixData: linalg.matrix, matrixB: linalg.matrixB }
    );
  }

  // --- Vectors (dot / cross / magnitude) ----------------------------------
  // Also deterministic: mathjs computes it, then an independent recompute
  // agrees (cross also proven ⊥ to both operands).
  const vectors = parseVectors(rawLatex);
  if (vectors) {
    return base("vector_" + vectors.op, "linalg", "x", false, "none", {
      vectorOp: vectors.op,
      vectorData: vectors.vectors,
    });
  }

  // --- Word problems (natural language) -----------------------------------
  // Prose can't be parsed into an equation directly. The LLM EXTRACTS the model
  // equation and solves it; the gate then confirms the answer satisfies that
  // extracted equation (so the arithmetic is verified — though the reading is
  // not, which is why the interpretation is shown to the learner).
  if (looksLikeWordProblem(rawLatex)) {
    return base("word_problem", "llm_candidate", "x", false, "word_problem");
  }

  const { isEquation } = splitEquation(ascii);

  // --- Expressions (no '=') --------------------------------------------
  if (!isEquation) {
    const vars = variablesIn(ascii);
    if (vars.length === 0) {
      return base("arithmetic", "arithmetic", "x", false, "equality");
    }
    return base("expression", "simplify", pickUnknown(vars), false, "equality");
  }

  // --- Equations --------------------------------------------------------
  const parts = equationParts(ascii);
  const vars = variablesIn(ascii);
  const multiEquation = parts.length > 1;

  if (multiEquation || vars.length >= 2) {
    // A square LINEAR system solves deterministically (mathjs, verified A·x=b).
    // Only when that declines (non-linear, non-square, singular) fall back to the
    // verified LLM tier.
    if (multiEquation) {
      const sys = parseLinearSystem(parts, vars);
      if (sys) {
        return base("linear_system", "linsystem", sys.vars[0], true, "none", {
          system: sys,
        });
      }
    }
    return base(
      "system_of_equations",
      "llm_candidate",
      pickUnknown(vars),
      true,
      "substitution"
    );
  }

  const unknown = pickUnknown(vars);

  // Exponential / transcendental: the unknown sits in an EXPONENT (3^x,
  // 2^(x-1), 3^{2x+1}). mathsteps/mathjs can't solve these, and labelling them
  // "linear"/"quadratic" misleads both the engine (wasted attempt) and the LLM
  // (wrong context). Route to the verified LLM-candidate tier with an honest
  // type; the substitution gate still proves any candidate before it ships.
  if (unknownInExponent(ascii, unknown)) {
    return base(
      "exponential_equation",
      "llm_candidate",
      unknown,
      true,
      "substitution"
    );
  }

  // Logarithmic: the unknown sits inside a log — log(x)=2, ln(x)+ln(x-3)=ln10.
  // (After latexToAscii, \ln→log, \log→log10, \log_b→(log/log).) mathsteps can't
  // solve these; route to the verified LLM tier with an honest type (mirrors the
  // exponential route). The substitution gate proves the root — and rejects any
  // extraneous root outside the log's domain (arg>0), where evalReal → NaN.
  if (unknownInLog(ascii, unknown)) {
    return base(
      "logarithmic_equation",
      "llm_candidate",
      unknown,
      true,
      "substitution"
    );
  }

  const degree = detectDegree(ascii, unknown);

  if (degree >= 2) {
    const type = degree === 2 ? "quadratic_equation" : "polynomial_equation";
    // Quadratics go to mathsteps; higher degree to the verified LLM tier.
    const strategy: Strategy = degree === 2 ? "equation" : "llm_candidate";
    return base(type, strategy, unknown, true, "substitution");
  }

  // Trig equations (sin/cos/tan present) aren't mathsteps' forte. They have
  // infinitely many solutions, so the gate verifies the principal numeric
  // solutions plus 2π-periodicity (verifyMode "trig"), not a single value.
  // Use letter-boundary lookarounds (not \b): "2cos(x)" has NO word boundary
  // before "cos" because a digit is a word char, so \b would miss it.
  if (/(?<![a-zA-Z])(sin|cos|tan|cot|sec|csc)(?![a-zA-Z])/.test(ascii)) {
    return base("trigonometric_equation", "llm_candidate", unknown, true, "trig");
  }

  return base("linear_equation", "equation", unknown, true, "substitution");
}

interface ParsedIntegral {
  definite: boolean;
  lower?: string;
  upper?: string;
  integrand: string;
  unknown: string;
}

/**
 * Read a bound token after a `_`/`^`: a BALANCED `{…}` group (returning its
 * inside) or a single bare token. A regex `\{[^{}]*\}` couldn't match a group
 * with nested braces, so a `\frac`-valued bound like `^{\frac{\pi}{2}}` was
 * dropped and the integral misread as indefinite. Returns the value and how many
 * chars were consumed, or null.
 */
function readBoundToken(s: string): { value: string; consumed: number } | null {
  if (s[0] === "{") {
    let depth = 0;
    for (let i = 0; i < s.length; i++) {
      if (s[i] === "{") depth++;
      else if (s[i] === "}") {
        depth--;
        if (depth === 0) return { value: s.slice(1, i).trim(), consumed: i + 1 };
      }
    }
    return null; // unbalanced
  }
  const t = s.match(/^[^\s{}^_]+/);
  return t ? { value: t[0], consumed: t[0].length } : null;
}

/**
 * Rewrite `\frac{[NUM] d<var>}{DEN}` → `(NUM)/(DEN) d<var>` so the standard
 * trailing-differential extractor finds it. Reads BALANCED brace groups (a regex
 * couldn't, because DEN may nest braces like `x^{2}` or `\sqrt{x}`). Leaves a
 * fraction whose numerator is NOT a differential (e.g. the `\frac{d}{dx}`
 * operator, whose numerator `d` has no variable after it) untouched.
 */
function hoistFractionDifferential(s: string): string {
  const idx = s.indexOf("\\frac");
  if (idx === -1) return s;
  let i = idx + "\\frac".length;
  while (s[i] === " ") i++;
  const num = readBraceGroup(s, i);
  if (!num) return s;
  let j = num.end;
  while (s[j] === " ") j++;
  const den = readBraceGroup(s, j);
  if (!den) return s;
  // Numerator must END in a differential d<var> (after an optional factor/space).
  const dm = num.value.match(/^(.*?)(?:\\[,;:! ])?\s*d\s*([a-zA-Z])\s*$/s);
  if (!dm) return s;
  const factor = dm[1].replace(/\\[,;:! ]/g, "").trim();
  return `${s.slice(0, idx)} (${factor || "1"})/(${den.value}) d${dm[2]} ${s.slice(den.end)}`;
}

/** Read a balanced `{…}` group at index `i` (s[i] must be `{`); returns its inner
 * text and the index just past the closing brace, or null. */
function readBraceGroup(
  s: string,
  i: number
): { value: string; end: number } | null {
  if (s[i] !== "{") return null;
  let depth = 0;
  for (let k = i; k < s.length; k++) {
    if (s[k] === "{") depth++;
    else if (s[k] === "}") {
      depth--;
      if (depth === 0) return { value: s.slice(i + 1, k), end: k + 1 };
    }
  }
  return null;
}

/**
 * Parse `\int f dx` / `\int_a^b f dx` from LaTeX. Bounds are read (in either
 * `_a^b` or `^b_a` order) BEFORE latexToAscii, which would otherwise mangle the
 * sub/superscripts; the integrand and bounds are then converted to ascii.
 */
function parseIntegral(rawLatex: string): ParsedIntegral {
  const intMatch = rawLatex.match(/\\int|∫/);
  let rest = intMatch
    ? rawLatex.slice((intMatch.index ?? 0) + intMatch[0].length)
    : rawLatex.replace(/\bintegral\b/gi, "");

  let lower: string | undefined;
  let upper: string | undefined;
  for (let i = 0; i < 2; i++) {
    const m = rest.match(/^\s*([_^])\s*/);
    if (!m) break;
    const tok = readBoundToken(rest.slice(m[0].length));
    if (!tok) break;
    if (m[1] === "_") lower = tok.value;
    else upper = tok.value;
    rest = rest.slice(m[0].length + tok.consumed);
  }

  // A differential written INSIDE a fraction numerator — ∫ dx/x, ∫ (2x dx)/(x²+1),
  // ∫ dx/(1+x²)=arctan x — means ∫ (numerator-without-dx / denominator) dx. The
  // trailing-d<var> extractor below only finds a differential at the very end, so
  // hoist it out of the fraction first (numerator without the dx → 1 if empty).
  rest = hoistFractionDifferential(rest);

  const cleaned = latexToAscii(rest);
  const m = cleaned.match(/^(.*?)\s*d\s*([a-zA-Z])\s*$/);
  const integrand = (m ? m[1] : cleaned).trim();
  const unknown = m ? m[2] : "x";
  const definite = lower !== undefined && upper !== undefined;

  return {
    definite,
    lower: lower !== undefined ? latexToAscii(lower) : undefined,
    upper: upper !== undefined ? latexToAscii(upper) : undefined,
    integrand,
    unknown,
  };
}

/** True if the ascii has a `+`/`-` at paren depth 0 (ignoring signs/exponents). */
function hasTopLevelAddSub(ascii: string): boolean {
  let depth = 0;
  for (let i = 0; i < ascii.length; i++) {
    const c = ascii[i];
    if (c === "(") depth++;
    else if (c === ")") depth--;
    else if ((c === "+" || c === "-") && depth === 0 && i > 0) {
      const prev = ascii[i - 1];
      // Skip a leading/operator sign and exponent signs (e.g. 1e-3).
      if (!"(*/^eE".includes(prev)) return true;
    }
  }
  return false;
}

/**
 * True if `unknown` appears in an EXPONENT (e.g. `3^x`, `3^(2x+1)`, `x^x`) — an
 * exponential/transcendental equation, not a polynomial. Matches a `^` followed
 * by either a parenthesized exponent mentioning the unknown, or a bare exponent
 * token starting with (an optional coefficient then) the unknown. Excludes
 * `x^2` / `(x+1)^3` (unknown in the BASE, numeric exponent).
 */
function unknownInExponent(ascii: string, unknown: string): boolean {
  const u = unknown.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`\\^\\s*(?:\\([^()]*${u}[^()]*\\)|-?[0-9.]*\\s*\\*?\\s*${u})`);
  return re.test(ascii);
}

/**
 * True if `unknown` appears inside a logarithm's argument (e.g. `log(x)=2`,
 * `log10(x-3)`) — a logarithmic equation. After latexToAscii, `\ln`→`log` and
 * `\log`→`log10`, so both spellings are covered (log10 tried first).
 */
function unknownInLog(ascii: string, unknown: string): boolean {
  const u = unknown.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(?:log10|log)\\s*\\([^()]*${u}`).test(ascii);
}

// Math directives / operators / function words that are NOT narrative content.
const NON_NARRATIVE = new Set([
  "solve", "find", "for", "the", "value", "values", "simplify", "evaluate",
  "calculate", "compute", "determine", "what", "and", "are", "where", "given",
  "let", "sin", "cos", "tan", "cot", "sec", "csc", "log", "sqrt", "arcsin",
  "arccos", "arctan", "sinh", "cosh", "tanh", "pi", "theta",
]);

/**
 * Conservative prose detector: does the input read like a word problem? Strips
 * LaTeX commands + math, then counts NARRATIVE words (≥3 letters, not a math
 * directive/function). Requires several such words AND a digit, so a directive
 * like "solve for the value of x" and any structured math stay OUT.
 */
function looksLikeWordProblem(rawLatex: string): boolean {
  const text = cleanLatex(rawLatex).replace(/\\[a-zA-Z]+/g, " ");
  if (!/\d/.test(text)) return false; // a computable word problem has numbers
  const words = (text.match(/[a-zA-Z]{3,}/g) ?? []).filter(
    (w) => !NON_NARRATIVE.has(w.toLowerCase())
  );
  return words.length >= 4;
}

/** An explicit request to PROVE/DISPROVE something (unambiguous — these are never
 * a compute-and-verify task). Deliberately excludes bare "show that", which often
 * fronts a computation the solver CAN do. */
const PROOF_CUES =
  /\b(prove|disprove|proof\s+(?:that|of|by)|by\s+(?:induction|contradiction)|q\.?e\.?d\.?)\b/i;
/** Abstract-algebra / real-analysis / logic terms whose answer is a proof or a
 * concept, not a number — so the solver can't substitution-verify them. Each is
 * specific enough not to collide with a computational problem (e.g. "cyclic
 * group", not bare "group"; "is continuous", not bare "continuous"). */
const CONCEPT_TERMS =
  /\b(homomorphism|isomorphi(?:sm|c)|automorphism|abelian|(?:sub|normal\s+sub|quotient|cyclic)\s*group|group\s+(?:is|of\s+order|homomorphism)|coset|kernel\s+of|generator\s+of|ring\s+homomorphism|integral\s+domain|(?:principal|maximal|prime)\s+ideal|polynomial\s+ring|field\s+extension|vector\s+space\s+axiom|supremum|infimum|least\s+upper\s+bound|greatest\s+lower\s+bound|epsilon[-\s]*delta|cauchy\s+sequence|uniformly\s+continuous|is\s+continuous|converges?|diverges?|monotone\s+sequence|bounded\s+(?:above|below)|injective|surjective|bijecti(?:ve|on)|equivalence\s+relation|well[-\s]*defined|countably|uncountabl)/i;

/** A proof / abstract-algebra / real-analysis prompt — there's no answer to
 * compute-and-verify, so it's routed to the AI tutor rather than the solver
 * (spec §1: we never fabricate a proof). */
function looksLikeConceptual(rawLatex: string): boolean {
  return PROOF_CUES.test(rawLatex) || CONCEPT_TERMS.test(rawLatex);
}

/**
 * A single-variable inequality: normalize the comparison macro, then split on
 * the ONE top-level operator into ascii `lhs`/`rhs`. Returns null for a plain
 * equation (no operator), a numeric comparison (no variable), a chained
 * inequality (two operators), or a multi-variable relation.
 */
function parseInequality(
  rawLatex: string
): { lhs: string; rhs: string; op: "<" | ">" | "<=" | ">="; unknown: string } | null {
  const s = rawLatex
    .replace(/\\leq|\\le(?![a-z])|≤/g, "<=")
    .replace(/\\geq|\\ge(?![a-z])|≥/g, ">=")
    .replace(/\\lt(?![a-z])/g, "<")
    .replace(/\\gt(?![a-z])/g, ">");
  const ops = s.match(/<=|>=|<|>/g);
  if (!ops || ops.length !== 1) return null;
  const op = ops[0] as "<" | ">" | "<=" | ">=";
  const idx = s.indexOf(op);
  const lhs = latexToAscii(s.slice(0, idx));
  const rhs = latexToAscii(s.slice(idx + op.length));
  const vars = variablesIn(`${lhs} ${rhs}`);
  if (vars.length !== 1) return null; // solve single-variable inequalities only
  return { lhs, rhs, op, unknown: pickUnknown(vars) };
}

/**
 * Rough polynomial degree in `unknown`, from the highest `^n` on that variable
 * AND on parenthesized groups that contain it. A bare `x^n` contributes `n`; a
 * group `(…)^n` contributes `degree(inside) * n` — so `(x+1)^3` → 3,
 * `(2x-5)^4` → 4 and `(x^2+1)^5` → 10. Without the group rule the exponent sits
 * on a `)`, not on `x`, so a higher-degree/rational equation was mislabelled
 * `linear` (see the `\frac{x+2}{(x+1)^3}=…` regression).
 */
function detectDegree(ascii: string, unknown: string): number {
  if (!ascii.includes(unknown)) return 0;
  let degree = 1;
  // Bare variable: `x^n` (or `x^(n)`).
  const bare = new RegExp(`${unknown}\\s*\\^\\s*\\(?\\s*(\\d+)`, "g");
  for (const m of ascii.matchAll(bare)) {
    degree = Math.max(degree, Number(m[1]));
  }
  // A parenthesized group raised to a power: `(…)^n` → degree(inside) * n. The
  // inner group carries no nested parens (matched by `[^()]+`), which covers
  // OCR output like `(x + 1)^3`; the inside's degree is measured recursively.
  const group = /\(([^()]+)\)\s*\^\s*\(?\s*(\d+)/g;
  for (const m of ascii.matchAll(group)) {
    const inside = m[1];
    if (!inside.includes(unknown)) continue;
    degree = Math.max(degree, detectDegree(inside, unknown) * Number(m[2]));
  }
  return degree;
}
