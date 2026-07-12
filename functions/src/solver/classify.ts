/**
 * Classify a recognized problem → a solving strategy.
 *
 * This routes to a deterministic engine where one exists (arithmetic, simplify,
 * linear/quadratic equations, derivatives) and to the constrained LLM-candidate
 * tier otherwise (integrals, higher-degree/trig equations, systems). Every path
 * carries a `verifyMode`: the answer is proven before it is ever returned.
 */
import { Classification, Strategy, VerifyMode } from "./types";
import {
  cleanLatex,
  latexToAscii,
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
  const latex = cleanLatex(rawLatex);
  const ascii = latexToAscii(rawLatex);

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

  // --- Derivative: d/dx(...) --------------------------------------------
  // Match the operator on the ORIGINAL LaTeX and take the operand from the text
  // that follows it — deriving the operand from the ascii is fragile because the
  // `\frac{d}{dx}` conversion introduces stray parentheses.
  const derivRe =
    /\\frac\s*\{\s*d\s*\}\s*\{\s*d\s*([a-zA-Z])\s*\}|\bd\s*\/\s*d\s*([a-zA-Z])/;
  const deriv = rawLatex.match(derivRe);
  if (deriv) {
    const unknown = deriv[1] ?? deriv[2] ?? "x";
    const before = rawLatex.slice(0, deriv.index ?? 0).trim();
    const afterLatex = cleanLatex(
      rawLatex.slice((deriv.index ?? 0) + deriv[0].length)
    );
    const stripped = stripOuterParens(afterLatex);
    const wasWrapped = stripped !== afterLatex;
    const target = latexToAscii(stripped);
    // Only a BARE derivative is safe to differentiate directly: nothing before
    // the operator (a coefficient like `2·d/dx(...)` would be silently dropped),
    // and the operand must be the whole remainder — either fully parenthesized
    // or a single term with no top-level +/- the operator wouldn't scope over.
    // Anything else would let a wrong answer pass its own gate, so route it to
    // the verified-candidate tier (here: couldn't-verify).
    if (before !== "" || (!wasWrapped && hasTopLevelAddSub(target))) {
      return base("derivative", "llm_candidate", unknown, false, "none");
    }
    return base("derivative", "derivative", unknown, false, "derivative_back", {
      derivativeTarget: target,
    });
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
    return base(
      "system_of_equations",
      "llm_candidate",
      pickUnknown(vars),
      true,
      "substitution"
    );
  }

  const unknown = pickUnknown(vars);
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

/** Strip one wrapping brace pair: `{0}` → `0`. */
function stripBraces(s: string): string {
  return s.replace(/^\s*\{|\}\s*$/g, "").trim();
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
    const b = rest.match(/^\s*([_^])\s*(\{[^{}]*\}|[^\s{}^_]+)/);
    if (!b) break;
    const val = stripBraces(b[2]);
    if (b[1] === "_") lower = val;
    else upper = val;
    rest = rest.slice(b[0].length);
  }

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

/** Rough polynomial degree in `unknown` from the highest `^n` on that variable. */
function detectDegree(ascii: string, unknown: string): number {
  let degree = ascii.includes(unknown) ? 1 : 0;
  const re = new RegExp(`${unknown}\\s*\\^\\s*\\(?\\s*(\\d+)`, "g");
  for (const m of ascii.matchAll(re)) {
    degree = Math.max(degree, Number(m[1]));
  }
  return degree;
}
