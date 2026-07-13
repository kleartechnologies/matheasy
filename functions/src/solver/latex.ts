/**
 * LaTeX ⇄ ascii-math conversion.
 *
 * `recognizeEquation` returns delimiter-free LaTeX. Both mathsteps and mathjs
 * want plain infix (`5x^2 + 3x - 2 = 0`, `sqrt(2)*x`, `(3)/(4)`), so we convert
 * in, run the engines, then convert the results back to LaTeX for rendering.
 *
 * These are deliberately conservative string transforms — they cover the shapes
 * the OCR/keyboard realistically emit. Anything they mangle simply fails the
 * mathsteps parse or (ultimately) the substitution gate, which routes the
 * problem to the LLM-candidate tier — never to a wrong answer.
 */

/** Function names both LaTeX (`\sin`) and ascii (`sin`) share. */
const FUNCTIONS = [
  "sin",
  "cos",
  "tan",
  "cot",
  "sec",
  "csc",
  "arcsin",
  "arccos",
  "arctan",
  "asin",
  "acos",
  "atan",
  "sinh",
  "cosh",
  "tanh",
  "log",
  "ln",
  "sqrt",
];

/** Strip cosmetic LaTeX that never carries meaning. */
export function cleanLatex(latex: string): string {
  return latex
    .replace(/\$\$?|\\\[|\\\]|\\\(|\\\)/g, "") // math delimiters
    .replace(/\\left|\\right/g, "")
    .replace(/\\!|\\,|\\;|\\:|\\ |\\quad|\\qquad|\\displaystyle|\\;/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Convert delimiter-free LaTeX to an ascii-math string mathjs/mathsteps parse.
 * `\frac{a}{b}` → `((a)/(b))`, `\sqrt{a}` → `sqrt(a)`, `x^{2}` → `x^(2)`, etc.
 */
export function latexToAscii(latex: string): string {
  let s = cleanLatex(latex);

  s = s.replace(/\\times/g, "*").replace(/\\cdot/g, "*").replace(/\\div/g, "/");
  s = s.replace(/\\pi\b/g, "pi").replace(/\\theta\b/g, "theta");

  // Logarithms: mathjs's natural log is `log`, base-10 is `log10`.
  //   \ln → log ;  \log_b(arg) → (log(arg)/log(b)) ;  bare \log → log10
  // Order matters: resolve \ln and explicit-base \log_b BEFORE bare \log.
  s = s.replace(/\\ln\b/g, "log");
  s = s.replace(/\\log\s*_\s*\{?\s*(\d+)\s*\}?\s*\(([^()]*)\)/g, "(log($2)/log($1))");
  s = s.replace(/\\log\b/g, "log10");

  // Mixed numbers: "2\frac{1}{2}" means 2½ = 2.5, NOT 2×(1/2). Only fire when
  // the fraction is purely numeric, so genuine implicit multiply like a coeff
  // times \frac{x}{3} is untouched. The WHOLE mixed number is wrapped in parens
  // so precedence holds in context: "2½x" → (2+½)x, "5-2½" → 5-(2+½). Runs
  // before the general \frac rewrite.
  s = s.replace(
    /(\d)\s*\\frac\s*\{\s*(\d+)\s*\}\s*\{\s*(\d+)\s*\}/g,
    "($1+\\frac{$2}{$3})"
  );

  // Convert brace groups INNERMOST-FIRST, repeating until stable, so nesting
  // across frac/sqrt/^/_ resolves inside-out. Each rule matches only brace-free
  // content (`[^{}]*`), so one pass peels the deepest layer; the loop repeats
  // until nothing changes. This is what makes `\frac{x^{2}}{3}` work: the `^{2}`
  // becomes `^(2)` first, THEN the frac's numerator is brace-free and matches.
  // (Running each rule in its own separate pass, as before, left a fraction
  // whose numerator held an exponent/root unconverted — and it got mangled.)
  let prev = "";
  for (let i = 0; i < 32 && prev !== s; i++) {
    prev = s;
    s = s
      .replace(/\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/g, "(($1)/($2))")
      .replace(/\\sqrt\s*\[([^\][{}]*)\]\s*\{([^{}]*)\}/g, "nthRoot($2, $1)")
      .replace(/\\sqrt\s*\{([^{}]*)\}/g, "sqrt($1)")
      .replace(/\^\s*\{([^{}]*)\}/g, "^($1)")
      .replace(/_\s*\{([^{}]*)\}/g, "_$1");
  }

  // Drop the backslash from function names (\sin → sin).
  for (const fn of FUNCTIONS) {
    s = s.replace(new RegExp(`\\\\${fn}\\b`, "g"), fn);
  }

  // Inverse trig → mathjs's names: `arcsin/arccos/arctan` → `asin/acos/atan`.
  // mathjs's `derivative()`/`evalReal` THROW on `arctan`, silently killing both
  // inverse-trig evaluation and every correct `∫1/(1+x²)=arctan x`.
  s = s.replace(/arc(sin|cos|tan)/g, "a$1");

  // Absolute value → abs(): `\lvert…\rvert` / `\vert` macros first, then the
  // bar pair (`\left|…\right|` already lost its \left/\right in cleanLatex).
  // Wrapped in parens so a preceding function/coefficient binds: `log|x+3|` →
  // `log(abs(x+3))`, `5|x|` → `5(abs(x))`. mathjs can't parse a bare `|`, and
  // its symbolic derivative DOES handle abs — so a `\ln|…|` antiderivative (the
  // natural form for ∫ of a rational function) now verifies instead of throwing.
  s = s.replace(/\\[lr]?[vV]ert/g, "|");
  s = s.replace(/\|([^|]+)\|/g, (_, inner) => `(abs(${inner.trim()}))`);

  s = s.replace(/[{}]/g, ""); // any braces the conversions left behind
  s = s.replace(/\\\\/g, " "); // row breaks
  return s.replace(/\s+/g, " ").trim();
}

/**
 * Strip a single pair of parentheses that wraps the WHOLE string, e.g.
 * `(x + 1)` → `x + 1`, but leaves `(x) + (1)` untouched (those parens aren't a
 * single wrapping pair). Idempotent-safe for one level.
 */
export function stripOuterParens(s: string): string {
  const t = s.trim();
  if (!t.startsWith("(") || !t.endsWith(")")) return t;
  let depth = 0;
  for (let i = 0; i < t.length; i++) {
    if (t[i] === "(") depth++;
    else if (t[i] === ")") {
      depth--;
      // If depth hits 0 before the last char, the first "(" closes early —
      // the outer parens are NOT a single wrapping pair.
      if (depth === 0 && i < t.length - 1) return t;
    }
  }
  return t.slice(1, -1).trim();
}

/** A parsed `lhs = rhs` equation (or a bare expression). */
export interface SplitEquation {
  isEquation: boolean;
  lhs: string;
  rhs: string;
}

/**
 * Split ascii math on its top-level `=`. mathjs treats `=` as assignment, so
 * verification must compare `lhs` and `rhs` as separate expressions. Returns the
 * whole string as `lhs` (with `rhs = ""`) when there is no equation.
 */
export function splitEquation(ascii: string): SplitEquation {
  // Only a single, top-level equals — ignore ==, <=, >=, !=.
  const cleaned = ascii.replace(/==|<=|>=|!=|≤|≥|≠/g, "");
  const idx = cleaned.indexOf("=");
  if (idx === -1) return { isEquation: false, lhs: ascii.trim(), rhs: "" };
  return {
    isEquation: true,
    lhs: cleaned.slice(0, idx).trim(),
    rhs: cleaned.slice(idx + 1).trim(),
  };
}

/** All single-letter variables used in an ascii expression (excludes functions/consts). */
export function variablesIn(ascii: string): string[] {
  const reserved = new Set([...FUNCTIONS, "pi", "e", "theta", "i"]);
  const found = new Set<string>();
  // Strip function names so their letters don't count as variables. LONGEST
  // first, so a short name isn't peeled out of a longer one (`sin` out of
  // `asin`/`arcsin`, leaking a/r/c) before the full name is matched.
  let stripped = ascii;
  const byLenDesc = [...FUNCTIONS].sort((a, b) => b.length - a.length);
  for (const fn of byLenDesc) stripped = stripped.replace(new RegExp(fn, "g"), " ");
  stripped = stripped.replace(/pi|theta/g, " ");
  for (const m of stripped.matchAll(/[a-zA-Z]/g)) {
    const v = m[0];
    if (!reserved.has(v)) found.add(v);
  }
  return [...found];
}

/**
 * Best-effort ascii-math → LaTeX for rendering step expressions. The final
 * answer LaTeX is built precisely elsewhere; this only needs to render cleanly
 * in `flutter_math_fork`.
 */
export function asciiToLatex(ascii: string): string {
  let s = ascii.trim();
  s = s.replace(/\bnthRoot\(([^,()]*),\s*([^()]*)\)/g, "\\sqrt[$2]{$1}");
  s = s.replace(/\bsqrt\(([^()]*)\)/g, "\\sqrt{$1}");
  // sin(...) → \sin(...) for nicer typesetting.
  for (const fn of ["sin", "cos", "tan", "cot", "sec", "csc"]) {
    s = s.replace(new RegExp(`\\b${fn}\\b`, "g"), `\\${fn} `);
  }
  // Log display: mathjs `log` is the natural log (→ \ln), `log10` is base-10
  // (→ \log). Do natural log first — `\blog\b` never matches inside `log10`.
  s = s.replace(/\blog\b/g, "\\ln ");
  s = s.replace(/\blog10\b/g, "\\log ");
  s = s.replace(/\^\(([^()]*)\)/g, "^{$1}");
  s = s.replace(/\bpi\b/g, "\\pi ").replace(/\btheta\b/g, "\\theta ");
  s = s.replace(/±/g, " \\pm ").replace(/∓/g, " \\mp ");
  s = s.replace(/\s*\*\s*/g, " \\cdot "); // explicit multiply
  return s.replace(/\s+/g, " ").trim();
}
