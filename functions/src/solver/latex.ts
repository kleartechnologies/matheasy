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

/** Function names both LaTeX (`\sin`) and ascii (`sin`) share.
 *
 * The INVERSE and HYPERBOLIC-INVERSE names (`asinh`, `acot`, …) and `log10` must
 * be listed too: `variablesIn` strips these names longest-first so their letters
 * aren't read as variables, and without `asinh` here the shorter `asin` was
 * peeled out of it, leaving a phantom variable `h` in every `\sinh^{-1} x`
 * problem. */
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
  "acot",
  "asec",
  "acsc",
  "sinh",
  "cosh",
  "tanh",
  "asinh",
  "acosh",
  "atanh",
  "log",
  "log10",
  "ln",
  "sqrt",
  "abs",
  "nthRoot",
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

/**
 * Unwrap `\text{…}` so the PROSE and the math read as one plain string.
 *
 * Word-problem parsers key off English ("find the slope", "near x = 0", "for
 * <fn>"), and the OCR wraps every English run in `\text{}`. Left in, the braces
 * split the sentence: "near } x = 0 \text{ for" made the centre cue capture a
 * bare `}` and the whole request declined. This is a PARSING view only — the
 * display LaTeX keeps its `\text{}` untouched.
 */
export function unwrapProse(rawLatex: string): string {
  return normalizeMacros(rawLatex)
    .replace(/\\text(?:rm|it|bf|sf|tt|normal)?\s*\{([^{}]*)\}/g, " $1 ")
    .replace(/\\mbox\s*\{([^{}]*)\}/g, " $1 ")
    .replace(/\\left|\\right/g, "")
    .replace(/\s+/g, " ")
    .trim();
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
export function latexToAscii(
  latex: string,
  opts: { splitProducts?: boolean } = {}
): string {
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

  // Degree marks. `\sin 30^\circ` used to shatter into `sin(30^)\circ` — an
  // unparseable string, so the ONE form that states its unit unambiguously was
  // the one form that could not be solved.
  //
  // The conversion is written out as `(30 * pi / 180)` rather than handed to
  // mathjs as its `30 deg` unit, because `deg` is three letters: `variablesIn`
  // reads them as variables (flipping the problem to the "simplify" strategy) and
  // the implicit-product splitter shatters them into `d*e*g`. Spelling the
  // conversion in ordinary arithmetic keeps every downstream stage working, and
  // it shows the student the step they are meant to learn. Applied here, before
  // trig arguments are wrapped, so `\sin 30^\circ` becomes `\sin (30*pi/180)`.
  // Gated on the problem actually containing trigonometry. Outside a trig call a
  // degree mark is an angle MEASURE — "the angle is 30°" wants 30 back, not
  // 0.5236 — so converting it there would corrupt the answer rather than fix it.
  if (/\\?(?:sin|cos|tan|sec|csc|cot)\b/.test(s)) {
    const DEGREE_MARK = /(\d+(?:\.\d+)?)\s*(?:\^\s*\{?\s*(?:\\circ|\\degree)\s*\}?|°)/g;
    s = s.replace(DEGREE_MARK, "($1 * pi / 180)");
  }

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

  // Split a glued run of variables into an explicit product — see
  // `splitGluedVariables`. Must run BEFORE the variable-bracket rule below:
  // `xy(x-1)` has to become `x*y*(x-1)`, and that rule only fires on a letter
  // that isn't glued to another letter.
  //
  // `splitProducts: false` is for callers that must read the ascii as PROSE —
  // unwrapped narrative ("John has 3 apples…") is letters too, and splitting it
  // sprays `*` through the sentence, which reads back as standalone math.
  if (opts.splitProducts !== false) s = splitGluedVariables(s);

  // Implicit multiply between a VARIABLE and a bracket: mathjs reads `x(x-1)` as
  // a call of a function named x, so `3x(x-1)=…` evaluated to NaN and its own
  // correct roots were rejected. Insert the `*`. Only for a STANDALONE letter
  // (not one inside a name like `sin(`), and never f/g/h — those are the
  // conventional function names, where `f(x)` really is an application.
  s = s.replace(/(^|[^A-Za-z])([a-eijkm-rt-z])\s*\(/g, "$1$2*(");

  return s.replace(/\s+/g, " ").trim();
}

/** A run of letters that is ONE symbol, never a product of variables: every
 * function name, the spelled-out Greek letters, and mathjs's own constants. */
const RESERVED_RUN = new Set([
  ...FUNCTIONS,
  "exp", "lg",
  "pi", "theta", "phi", "alpha", "beta", "gamma", "delta", "epsilon", "zeta",
  "eta", "iota", "kappa", "lambda", "mu", "nu", "xi", "rho", "sigma", "tau",
  "upsilon", "chi", "psi", "omega",
  "Inf", "NaN", "Infinity", "true", "false", "null",
]);

/**
 * `xy + 3yx` → `x*y + 3*y*x`. Handwriting and print both write a product of
 * variables with nothing between them, but mathjs reads a glued run of letters
 * as ONE identifier — so `xy` and `yx` became two DIFFERENT unknowns, the
 * simplify never combined them, and the substitution gate declined a problem
 * the engine can do perfectly (`2x^2(4xy-5) - 8yx^3 + 9x`, `ax - ay + 2x - 2y`,
 * every algebraic fraction with a two-variable numerator). Digit-then-letter
 * (`2b`) already parsed; only letter-then-letter was glued.
 *
 * Kept whole:
 *  - a reserved run (`sin`, `sqrt`, `theta`, `Inf`) — one symbol by name;
 *  - anything preceded by a backslash, so an unconverted `\alpha` isn't
 *    shredded into `a*l*p*h*a`;
 *  - a subscripted identifier (`x_1`, `_max`) — the subscript names the symbol;
 *  - a differential/derivative token `dx`, `dy`, `ddy` — `∫ … dx` reads the
 *    pair as one token, and `buildResidual` encodes y′/y″ as the literal
 *    symbols `dy`/`ddy` before converting, so splitting them hid the
 *    derivative and every second-order ODE stopped parsing.
 */
function splitGluedVariables(s: string): string {
  return s.replace(/[A-Za-z]+/g, (run, offset: number, whole: string) => {
    if (run.length < 2) return run;
    if (RESERVED_RUN.has(run)) return run;
    const before = offset > 0 ? whole[offset - 1] : "";
    if (before === "\\" || before === "_") return run;
    if (whole[offset + run.length] === "_") return run;
    // A differential / ODE token — but only where one can actually stand. A
    // digit in front makes it a coefficient (`3dc^2` is 3·d·c², not a `dc`),
    // and that is the shape every algebraic-fraction product is written in.
    if (/^d{1,2}[A-Za-z]$/.test(run) && !/[0-9]/.test(before)) return run;
    return run.split("").join("*");
  });
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

    // A PARENTHESIZED argument is copied past the scan head (`i = a` below), so
    // any prefix-style call NESTED inside it would never be wrapped — which is
    // why `\cos^{-1}(\sin x)` came out as the unparseable `acos(sin x)`. Recurse
    // into the group so inner calls get their parentheses too.
    const wrapped = arg.startsWith("(")
      ? `(${wrapFunctionArgs(arg.slice(1, -1))})`
      : `(${arg})`;
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
  let s = fracify(ascii.trim());
  s = s.replace(/\bnthRoot\(([^,()]*),\s*([^()]*)\)/g, "\\sqrt[$2]{$1}");
  s = sqrtify(s);
  s = absify(s);
  // sin(...) → \sin(...) for nicer typesetting.
  for (const fn of ["sin", "cos", "tan", "cot", "sec", "csc"]) {
    s = s.replace(new RegExp(`\\b${fn}\\b`, "g"), `\\${fn} `);
  }
  // Log display: mathjs `log` is the natural log (→ \ln), `log10` is base-10
  // (→ \log). Do natural log first — `\blog\b` never matches inside `log10`.
  s = s.replace(/\blog\b/g, "\\ln ");
  s = s.replace(/\blog10\b/g, "\\log ");
  s = s.replace(/\^\s*\(([^()]*)\)/g, "^{$1}");
  s = s.replace(/\bpi\b/g, "\\pi ").replace(/\btheta\b/g, "\\theta ");
  s = s.replace(/±/g, " \\pm ").replace(/∓/g, " \\mp ");
  // A textbook writes `5x`, not `5 · x`. Juxtapose when the right operand is a
  // symbol, or when neither side could be read as a function applied to a
  // bracket (`x \cdot (y+1)` must not become `x(y+1)`). Everything else — a
  // product of two numbers above all — keeps the dot.
  s = s.replace(/\s*\*\s*(?=[A-Za-z\\])/g, "");
  s = s.replace(/([)\d])\s*\*\s*(?=\()/g, "$1");
  s = s.replace(/\s*\*\s*/g, " \\cdot "); // explicit multiply
  return s.replace(/\s+/g, " ").trim();
}

// --- `a/b` → \frac{a}{b} -----------------------------------------------------
//
// A worksheet prints a quotient stacked, and so should we: `(5x - 10)/4` should
// reach the student as a fraction bar, not as a slash. This is a scan and not a
// parser, because the strings arriving here are only mostly ascii-math — some
// already carry LaTeX a caller built itself. Anything it cannot read with
// confidence it leaves exactly as it found it, so the worst case is the slash
// that was being shown anyway.
//
// Precedence is why this can't be a regex. `2*x/3` is `(2x)/3`, so the
// numerator reaches BACK across a whole multiplication chain; `1/2*x` is
// `(1/2)*x`, so the denominator takes ONE operand and stops.

const WORD = /[A-Za-z0-9_.]/;
const CLOSERS: Record<string, string> = { ")": "(", "}": "{", "]": "[" };

/** Index of the bracket opening the one that closes at `i`, or -1. */
function matchBackward(s: string, i: number): number {
  const open = CLOSERS[s[i]];
  let depth = 0;
  for (let j = i; j >= 0; j--) {
    if (s[j] === s[i]) depth++;
    else if (s[j] === open && --depth === 0) return j;
  }
  return -1;
}

/** Index of the bracket closing the one that opens at `i`, or -1. */
function matchForward(s: string, i: number): number {
  const close = Object.keys(CLOSERS).find((c) => CLOSERS[c] === s[i]);
  if (!close) return -1;
  let depth = 0;
  for (let j = i; j < s.length; j++) {
    if (s[j] === s[i]) depth++;
    else if (s[j] === close && --depth === 0) return j;
  }
  return -1;
}

/** Start of the single operand ending at `end` (exclusive), or -1. */
function primaryStart(s: string, end: number): number {
  let j = end;
  while (j > 0 && s[j - 1] === " ") j--;
  if (j === 0) return -1;
  const c = s[j - 1];
  let start: number;
  if (c === ")" || c === "]") {
    const open = matchBackward(s, j - 1);
    if (open < 0) return -1;
    start = open;
    // A call keeps its name: `sqrt(x)`, `f(t)`.
    while (start > 0 && WORD.test(s[start - 1])) start--;
  } else if (c === "}") {
    // The brace groups, then the command that owns them: `\frac{a}{b}`.
    let k = j;
    while (k > 0 && s[k - 1] === "}") {
      const open = matchBackward(s, k - 1);
      if (open < 0) return -1;
      k = open;
    }
    while (k > 0 && WORD.test(s[k - 1])) k--;
    if (k > 0 && s[k - 1] === "\\") k--;
    start = k;
  } else if (WORD.test(c)) {
    start = j;
    while (start > 0 && WORD.test(s[start - 1])) start--;
    if (start > 0 && s[start - 1] === "\\") start--;
  } else {
    return -1;
  }
  // A power belongs to its base: the operand of `x^2/3` is `x^2`, not `2` —
  // and mathsteps prints it spaced, `x ^ 2 / 3`. Reading the exponent alone
  // would move the fraction INTO it and change what the step says.
  for (;;) {
    let k = start;
    while (k > 0 && s[k - 1] === " ") k--;
    if (k === 0 || s[k - 1] !== "^") return start;
    const base = primaryStart(s, k - 1);
    if (base < 0) return start;
    start = base;
  }
}

/** Start of the NUMERATOR ending at `end` — the whole multiplication chain. */
function numeratorStart(s: string, end: number): number {
  let j = end;
  let start = -1;
  for (;;) {
    const p = primaryStart(s, j);
    if (p < 0) return start;
    start = p;
    let k = p;
    while (k > 0 && s[k - 1] === " ") k--;
    if (k === 0) return start;
    // `*` or bare juxtaposition (`5 r`) continues the chain; `+ - = / (` end it.
    if (s[k - 1] === "*") j = k - 1;
    else if (WORD.test(s[k - 1]) || s[k - 1] === ")" || s[k - 1] === "}") j = k;
    else return start;
  }
}

/** End (exclusive) of the single operand starting at `start`, or -1. */
function primaryEnd(s: string, start: number): number {
  let j = start;
  while (j < s.length && s[j] === " ") j++;
  if (j >= s.length) return -1;
  const c = s[j];
  let end: number;
  if (c === "(" || c === "[") {
    const close = matchForward(s, j);
    if (close < 0) return -1;
    end = close + 1;
  } else if (c === "\\") {
    let k = j + 1;
    while (k < s.length && WORD.test(s[k])) k++;
    while (k < s.length && s[k] === "{") {
      const close = matchForward(s, k);
      if (close < 0) break;
      k = close + 1;
    }
    end = k;
  } else if (WORD.test(c)) {
    let k = j;
    while (k < s.length && WORD.test(s[k])) k++;
    if (k < s.length && s[k] === "(") {
      const close = matchForward(s, k);
      if (close >= 0) k = close + 1;
    }
    end = k;
  } else {
    return -1; // a sign or an operator — not something to put under the bar
  }
  for (;;) {
    let k = end;
    while (k < s.length && s[k] === " ") k++;
    if (s[k] !== "^") return end;
    const next = primaryEnd(s, k + 1);
    if (next < 0) return end;
    end = next;
  }
}

/** Drop parentheses wrapping the whole operand — the bar already groups it. */
function unwrap(text: string): string {
  const t = text.trim();
  if (t.startsWith("(") && matchForward(t, 0) === t.length - 1) {
    return t.slice(1, -1).trim();
  }
  return t;
}

/**
 * `sqrt(…)` → `\sqrt{…}`, matching the closing bracket rather than assuming
 * there is nothing bracketed inside. The radicand of a rearranged formula is
 * routinely a fraction in brackets, and a regex that stopped at the first `)`
 * left `sqrt(` on the screen.
 */
function sqrtify(input: string): string {
  let s = input;
  for (let i = 0; (i = s.indexOf("sqrt(", i)) >= 0; ) {
    if (i > 0 && WORD.test(s[i - 1])) {
      i += 5; // part of a longer name
      continue;
    }
    const close = matchForward(s, i + 4);
    if (close < 0) {
      i += 5;
      continue;
    }
    // Recurse into the radicand: `sqrt((1 - sqrt(5))/2)` carries a nested call,
    // and the outer replacement used to skip straight past it.
    const radicand = `\\sqrt{${sqrtify(unwrap(s.slice(i + 5, close)))}}`;
    s = s.slice(0, i) + radicand + s.slice(close + 1);
    i += radicand.length;
  }
  return s;
}

/**
 * `abs(x + 1)` → `\left|x + 1\right|`.
 *
 * `latexToAscii` turns every `|…|` into `abs(…)` so mathjs can parse it, and
 * nothing turned it back — so any absolute-value problem printed the function
 * name at the student. Balanced-paren scan rather than a regex, for the same
 * reason `sqrtify` is one: the argument can contain brackets of its own.
 */
function absify(input: string): string {
  let s = input;
  for (let i = 0; (i = s.indexOf("abs(", i)) >= 0; ) {
    if (i > 0 && WORD.test(s[i - 1])) {
      i += 4; // part of a longer name
      continue;
    }
    const close = matchForward(s, i + 3);
    if (close < 0) {
      i += 4;
      continue;
    }
    const bars = `\\left|${unwrap(s.slice(i + 4, close))}\\right|`;
    // `latexToAscii` wraps the call as `(abs(x))` so that `5|x|` keeps its
    // precedence. Bars carry that grouping themselves, so the wrapper would only
    // print as a stray pair of brackets around the modulus.
    const wrapped =
      i > 0 && s[i - 1] === "(" && matchForward(s, i - 1) === close + 1;
    const from = wrapped ? i - 1 : i;
    const to = wrapped ? close + 2 : close + 1;
    s = s.slice(0, from) + bars + s.slice(to);
    i = from + bars.length;
  }
  return s;
}

function fracify(input: string): string {
  // `\text{…}` is prose, and a slash inside prose is a slash. Park it behind a
  // word-shaped token so the scan treats it as one opaque symbol.
  const prose: string[] = [];
  let s = input.replace(/\\text\{[^{}]*\}/g, (m) => {
    prose.push(m);
    return `PROSE${prose.length - 1}TOKEN`;
  });

  for (let i = 0; i < s.length; i++) {
    if (s[i] !== "/") continue;
    const numStart = numeratorStart(s, i);
    const denEnd = primaryEnd(s, i + 1);
    if (numStart < 0 || denEnd < 0) continue;
    const num = unwrap(s.slice(numStart, i));
    const den = unwrap(s.slice(i + 1, denEnd));
    if (!num || !den) continue;
    const frac = `\\frac{${num}}{${den}}`;
    s = s.slice(0, numStart) + frac + s.slice(denEnd);
    i = numStart + frac.length - 1;
  }

  return s.replace(/PROSE(\d+)TOKEN/g, (_, n) => prose[Number(n)]);
}

/**
 * `sin(30)` means 30 DEGREES to the student who typed it and 30 RADIANS to
 * mathjs — and the substitution gate cannot tell them apart, because it
 * re-evaluates under the same convention it was given. So `\sin(30) + \cos(60)`
 * shipped as `-1.940445` marked `verified: true`: a confidently wrong answer,
 * which is exactly what the golden rule exists to prevent.
 *
 * The repo's own precedent (`boundedTrig.detectUnit`) is to decline rather than
 * guess. That is right for SOLVING, where a wrong unit yields wrong roots over
 * an interval. For EVALUATING a constant this rule is narrow enough to be safe
 * instead: one full turn is 2π ≈ 6.28, so a whole-number argument of 7 or more
 * is beyond a complete revolution and no one writes that in radians without a π.
 * Below 7, and for every non-integer, radians stand — `sin(1)` and `sin(0.5)`
 * are untouched, as is `sin(pi/6)` (the argument is not a bare integer).
 *
 * The conversion is written out rather than folded into a number, so the
 * assumption appears in the working where a student can see and correct it.
 */
export function assumeDegreesForBareTrig(ascii: string): string {
  return ascii.replace(
    /\b(sin|cos|tan|sec|csc|cot)\s*\(\s*(-?\d+)\s*\)/g,
    (whole, fn: string, arg: string) =>
      Math.abs(Number(arg)) >= 7 ? `${fn}((${arg} * pi / 180))` : whole,
  );
}
