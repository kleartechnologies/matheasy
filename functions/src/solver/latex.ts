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

/**
 * Fold rendered/scanned LaTeX variants onto their canonical macro so the rest of
 * the pipeline sees ONE spelling. Applied to the raw problem (in `classify`, so
 * the `\int` / `\frac{d}{dx}` detectors match) AND inside `cleanLatex` (so the
 * ascii conversion + any LLM answer benefit). Idempotent, so double-application
 * is harmless. Purely a spelling normalization — no structure is removed.
 */
export function normalizeMacros(s: string): string {
  return (
    s
      // \dfrac / \tfrac (display/text-style fractions) are just \frac.
      .replace(/\\[dt]frac\b/g, "\\frac")
      // Upright styling wrappers around MATH carry no meaning — keep the CONTENT:
      //   \mathrm{d}x → dx (the physics/EU differential), \operatorname{sin} → sin.
      // `\text{…}` is deliberately NOT unwrapped: the OCR uses it to mark PROSE,
      // and that marker is what lets latexToAscii drop the words before the
      // engines see them (otherwise "Solve the equation" becomes the variables
      // S,o,l,v,e… and a one-line problem misreads as a multi-variable system).
      .replace(
        /\\(?:mathrm|mathit|mathbf|mathsf|mathtt|mathnormal|operatorname\*?|boldsymbol|mathchoice)\s*\{([^{}]*)\}/g,
        "$1"
      )
      // …and a bare styling macro with no braces (e.g. `\mathrm dx`).
      .replace(/\\(?:mathrm|mathit|mathbf|mathsf|mathtt|mathnormal|boldsymbol)\b/g, "")
  );
  // NOTE: unicode operators (· × ÷ −) are NOT folded here — that would run before
  // classify's raw-LaTeX vector/matrix detectors (which read `×` as a cross
  // product), turning a cross into a multiply. They're converted in latexToAscii
  // instead, on the mathjs-bound path only, AFTER that structural detection.
}

/** Strip cosmetic LaTeX that never carries meaning. */
export function cleanLatex(latex: string): string {
  return (
    normalizeMacros(latex)
      .replace(/\$\$?|\\\[|\\\]|\\\(|\\\)/g, "") // math delimiters
      .replace(/\\left|\\right/g, "")
      // Spacing macros. `\ ` (escaped space) must NOT eat half of a `\\` ROW
      // BREAK: in "17 \\ 6x" it would match the second backslash + the space and
      // leave a stray "\", so the row break vanished and a two-line system never
      // split into its equations. The lookbehind skips a backslash that is itself
      // preceded by one.
      .replace(/\\!|\\,|\\;|\\:|(?<!\\)\\ |\\quad|\\qquad|\\displaystyle/g, " ")
      .replace(/\s+/g, " ")
      // A scanned prompt often ends in an empty "= ?" / "= □" / bare "=" — the
      // "compute this" placeholder ("∫ … dx = ?", "d/dx(…) = ?"). It carries no
      // math, but left in it makes the integrand/derivative operand unparseable
      // (the target becomes "… = ?") and every such scan declines. Strip a
      // trailing equals whose RHS is empty or a question/box placeholder ONLY —
      // a real equation ("2x+5 = 15") keeps its "=" because 15 isn't a placeholder.
      .replace(/=\s*(?:\?+|\\square|\\Box|\\ldots|\\dots|\\cdots|_+|\.{2,})?\s*$/, "")
      .replace(/\s+/g, " ")
      .trim()
  );
}

/**
 * Convert delimiter-free LaTeX to an ascii-math string mathjs/mathsteps parse.
 * `\frac{a}{b}` → `((a)/(b))`, `\sqrt{a}` → `sqrt(a)`, `x^{2}` → `x^(2)`, etc.
 */
export function latexToAscii(latex: string): string {
  let s = cleanLatex(latex);

  // Drop PROSE. The OCR marks words with `\text{…}` ("Solve the equation.",
  // "(i) Find …"), which is instruction — not math. The engines must never see
  // it: `variablesIn` would read every letter of "Solve" as a variable, turning
  // a one-line equation into a bogus multi-variable system. Display keeps the
  // prose (cleanLatex leaves \text intact); only this solving path drops it.
  // A pure word problem is all prose → this leaves nothing, and classify has
  // already routed it by then (looksLikeWordProblem reads the raw text).
  s = s.replace(/\\text(?:rm|it|bf|sf|tt)?\s*\{[^{}]*\}/g, " ");

  // A backslash is LaTeX's own token boundary: `x\ln x`, `x\cos x`, `x\sqrt{…}`,
  // `2\pi`, `\sin x\cos x` all mean an implicit MULTIPLY across the `\`. But the
  // macro strips below drop the backslash, gluing the preceding symbol onto the
  // name (`x\cos`→`xcos`, `x\ln`→`xlog`) into one undefined identifier — so every
  // `∫x·(trig/ln/√) dx` and by-parts antiderivative silently failed the gate.
  // Re-insert the boundary as a space wherever a `\macro` follows a symbol/`)`.
  s = s.replace(/([A-Za-z0-9)}])\s*\\([a-zA-Z])/g, "$1 \\$2");

  s = s.replace(/\\times/g, "*").replace(/\\cdot/g, "*").replace(/\\div/g, "/");
  // Unicode operators OCR / rendered math emit — folded here (not in
  // normalizeMacros) so classify's raw-LaTeX vector/matrix detectors still see a
  // cross `×`/dot `·` before this multiply conversion. `−`/`–`/`—` → ascii `-`.
  s = s
    .replace(/[·∙⋅]/g, "*")
    .replace(/×/g, "*")
    .replace(/÷/g, "/")
    .replace(/[−–—]/g, "-");
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
    /(\d+)\s*\\frac\s*\{\s*(\d+)\s*\}\s*\{\s*(\d+)\s*\}/g,
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

  // Give every trig/log function an explicit parenthesized argument. LaTeX writes
  // `\sin x`, `\sin 2x`, `\sin^2 x`, `\sin^{-1} x` — but mathjs can't parse a bare
  // `sin x` (it throws) and reads `sin^2 x` as garbage, so a `∫\sin x\cos x\,dx`
  // integrand and any `\sin^2 x` antiderivative silently failed the gate. This
  // rewrites `sin x`→`sin(x)`, `sin 2x`→`sin(2x)`, `sin^2 x`→`sin(x)^2`, and the
  // inverse form `\sin^{-1} x`→`asin(x)` (NOT `sin(x)^-1`=csc — that would verify
  // a DIFFERENT problem than asked, a golden-rule break). Already-parenthesized
  // args (`sin(x)`, `\sin\frac{x}{2}`→`sin((x)/(2))`) are preserved.
  s = wrapFunctionArgs(s);

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

  // Implicit multiply between a VARIABLE and a bracket: mathjs reads `x(x-1)` as
  // a call of a function named x, so `3x(x-1)=…` evaluated to NaN and its own
  // correct roots were rejected. Insert the `*`. Only for a STANDALONE letter
  // (not one inside a name like `sin(`), and never f/g/h — those are the
  // conventional function names, where `f(x)` really is an application.
  s = s.replace(/(^|[^A-Za-z])([a-eijkm-rt-z])\s*\(/g, "$1$2*(");

  return s.replace(/\s+/g, " ").trim();
}

/** Single-argument functions written prefix-style in LaTeX (`\sin x`). `sqrt`/
 * `nthRoot`/`abs` are excluded — those already carry parenthesized arguments by
 * the time this runs. `log10` is listed before `log` so the longer name wins. */
const UNARY_FUNCTIONS = [
  "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
  "asin", "acos", "atan", "acot", "asec", "acsc",
  "log10", "log", "sin", "cos", "tan", "cot", "sec", "csc",
];
/** Trig/hyperbolic → inverse-function name, for the `f^{-1}` (arc) spelling. */
const INVERSE_FUNCTION: Record<string, string> = {
  sin: "asin", cos: "acos", tan: "atan", cot: "acot", sec: "asec", csc: "acsc",
  sinh: "asinh", cosh: "acosh", tanh: "atanh",
};

/** Read a balanced `(...)` group starting at `i` (s[i] === "("); returns the
 * index just past the matching `)`, or -1 if unbalanced. */
function readGroup(s: string, i: number): number {
  let depth = 0;
  for (let k = i; k < s.length; k++) {
    if (s[k] === "(") depth++;
    else if (s[k] === ")") {
      depth--;
      if (depth === 0) return k + 1;
    }
  }
  return -1;
}

/** Read a bare atom (number/identifier run, plus an optional trailing `^power`)
 * starting at `i`; returns the index just past it, or `i` if none. So
 * `x` → past `x`, `2x` → past `2x`, `x^2` → past `x^2`, `x^(2)` → past the group. */
function readAtom(s: string, i: number): number {
  const m = /^[A-Za-z0-9.]+/.exec(s.slice(i));
  if (!m) return i;
  let k = i + m[0].length;
  if (s[k] === "^") {
    k++;
    if (s[k] === "(") {
      const g = readGroup(s, k);
      if (g !== -1) k = g;
    } else {
      const p = /^-?[A-Za-z0-9.]+/.exec(s.slice(k));
      if (p) k += p[0].length;
    }
  }
  return k;
}

/**
 * Wrap the argument of every prefix-style function call in parentheses so mathjs
 * can parse it — see the call site in `latexToAscii`. A hand-written scan (not a
 * regex) because a function's argument may be a balanced, arbitrarily-nested
 * `(...)` group that no regular expression can match.
 */
function wrapFunctionArgs(s: string): string {
  let out = "";
  let i = 0;
  while (i < s.length) {
    const prev = i > 0 ? s[i - 1] : "";
    let fn: string | null = null;
    // The name must not be glued to a LETTER on either side, so `sin` isn't
    // peeled out of `asin` / a variable. A DIGIT before is fine — it's a
    // coefficient (`2\sin x` → `2sin(x)` = 2·sin x), so only letters block here.
    if (!/[A-Za-z]/.test(prev)) {
      for (const cand of UNARY_FUNCTIONS) {
        if (s.startsWith(cand, i) && !/[A-Za-z0-9]/.test(s[i + cand.length] ?? "")) {
          fn = cand;
          break;
        }
      }
    }
    if (!fn) {
      out += s[i];
      i++;
      continue;
    }

    let j = i + fn.length;
    // Optional power immediately after the name: `^2`, `^(2)`, `^{-1}`→`^-1`.
    let power: string | null = null;
    let k = j;
    while (s[k] === " ") k++;
    if (s[k] === "^") {
      let p = k + 1;
      while (s[p] === " ") p++;
      if (s[p] === "(") {
        const g = readGroup(s, p);
        if (g !== -1) {
          power = s.slice(p, g);
          k = g;
        }
      } else {
        const pm = /^-?[A-Za-z0-9.]+/.exec(s.slice(p));
        if (pm) {
          power = pm[0];
          k = p + pm[0].length;
        }
      }
      if (power !== null) j = k;
    }

    // The argument: a `(...)` group or a bare atom.
    let a = j;
    while (s[a] === " ") a++;
    let arg: string | null = null;
    if (s[a] === "(") {
      const g = readGroup(s, a);
      if (g !== -1) {
        arg = s.slice(a, g);
        a = g;
      }
    } else {
      const end = readAtom(s, a);
      if (end > a) {
        arg = s.slice(a, end);
        a = end;
      }
    }

    if (arg === null) {
      // No argument to bind (e.g. a stray `sin` before an operator) — leave the
      // name untouched; mathjs will decline it and the gate keeps us honest.
      out += fn;
      i += fn.length;
      continue;
    }

    const wrapped = arg.startsWith("(") ? arg : `(${arg})`;
    // Normalize the power for the inverse test: strip whitespace AND one layer of
    // wrapping parens, so `^{-1}` (→`^(-1)`) reads as "-1" and `\sin^{-1} x`
    // becomes the INVERSE function asin(x), never sin(x)^(-1)=csc (wrong problem).
    const powNorm =
      power === null ? null : power.replace(/\s+/g, "").replace(/^\((.*)\)$/, "$1");
    if (powNorm === "-1" && INVERSE_FUNCTION[fn]) {
      out += `${INVERSE_FUNCTION[fn]}${wrapped}`;
    } else if (powNorm !== null) {
      out += `${fn}${wrapped}^(${powNorm})`;
    } else {
      out += `${fn}${wrapped}`;
    }
    i = a;
  }
  return out;
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
