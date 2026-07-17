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
import { parseSimultaneous } from "./simultaneous";
import { parseOde } from "./ode";
import { parseStatistics } from "./statistics";
import { parseTaylor } from "./taylor";
import {
  Classification,
  Strategy,
  TeachingCategory,
  TeachingDifficulty,
  TeachingMeta,
  VerifyMode,
} from "./types";
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
    .flatMap((c) => {
      // A CHAINED equality A = B = C (one printed statement, two relations —
      // the exam form "2(x-y) = x+y-1 = 2x²-11y²") is really the equation
      // pair {A = B, B = C}. splitEquation alone would bury "B = C" inside
      // the rhs, where every verifier's evalReal chokes on the '='. Expand
      // consecutive segments instead; a degenerate empty segment ("x = = 5")
      // falls back to splitEquation's original first-'=' behavior.
      const segs = c.split("=").map((s) => s.trim());
      if (segs.length >= 3 && segs.every(Boolean)) {
        const pairs: { lhs: string; rhs: string }[] = [];
        for (let i = 0; i + 1 < segs.length; i++) {
          pairs.push({ lhs: segs[i], rhs: segs[i + 1] });
        }
        return pairs;
      }
      const { lhs, rhs } = splitEquation(c);
      return [{ lhs, rhs }];
    });
}

export function classify(rawLatex: string): Classification {
  // Fold display/text macro variants (\dfrac, \mathrm{d}x, \operatorname, unicode
  // ·×÷) onto their canonical spelling FIRST, so every raw-LaTeX detector below
  // (\int, \frac{d}{dx}, ODE, …) sees one form. cleanLatex re-applies it for the
  // ascii path; it's idempotent.
  rawLatex = normalizeMacros(rawLatex);
  // A trailing answer BLANK — a separate line that is just "<var> =" (the "x = __"
  // slot on a worksheet) — carries no math. Drop it so it doesn't merge into the
  // equation on the line above (`5x=20 \n x =` was read as one broken equation).
  rawLatex = rawLatex.replace(/(?:\\\\|[\n;])\s*[a-zA-Z]\s*=\s*$/, "").trim();
  // The DISPLAY latex keeps the whole problem as read (directives + prose).
  const latex = cleanLatex(rawLatex);

  // The tutor-routing checks need the FULL text (they look for "find x²", sub-
  // parts, "hence"); compute them BEFORE stripping the leading directive below.
  const conceptual = looksLikeConceptual(rawLatex);
  const multiPart = !conceptual && looksLikeMultiPart(rawLatex);

  // With the OCR now capturing prose, a single problem often arrives with a
  // leading imperative — "Solve 2x+5=15", "Find x: …", "Calculate the value of
  // …". Those directive words would pollute classification (their letters read
  // as variables → a bogus system → decline). Strip a leading directive from the
  // SOLVING representation (never a conceptual / multi-part one) so the clean
  // math underneath classifies normally; the display `latex` above is untouched.
  if (!conceptual && !multiPart) {
    rawLatex = stripLeadingDirective(rawLatex);
  }

  // A `\\` ROW BREAK separates statements — in a cases/aligned system, and also
  // bare (the OCR puts each printed line on its own row, so a two-line system
  // arrives as "5x-2y=17 \\ 6x+2y=16"). Turn every row break into `;` so
  // equationParts can split them; otherwise the two equations ran together, the
  // system never parsed, and it fell through to the tutor. Matrices are parsed
  // from rawLatex (parseLinalg), so their `\\` rows are unaffected by this.
  const rawForAscii = rawLatex
    .replace(/\\begin\s*\{\s*(?:cases|aligned|split|gather)\s*\}/gi, " ")
    .replace(/\\end\s*\{\s*(?:cases|aligned|split|gather)\s*\}/gi, " ")
    .replace(/\\\\/g, " ; ")
    .replace(/&/g, " ");
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
  // These have no answer to compute-and-verify, so instead of faking one (or a
  // misleading "couldn't verify"), route to the tutor (routeToTutor state).
  if (conceptual) {
    return base("conceptual", "conceptual", "x", false, "none");
  }

  // --- Multi-part / derived-question problems → the AI tutor --------------
  // A single problem gets ONE verified answer; a MULTI-PART question does not.
  // With the OCR now capturing the whole problem, inputs like "given 2x+5=15,
  // find x²", "(i) … (ii) …", or "solve the system, find xy" reach the solver.
  // The single-answer engines would solve the equation and confidently show its
  // ROOT — the WRONG quantity for a question that asks for x² / xy / sin 2x /
  // part (b). There's no single value to substitution-verify, so (like a proof)
  // route it to the tutor rather than ship a confident wrong answer.
  if (multiPart) {
    return base("multi_part", "conceptual", "x", false, "none");
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
  // …but only when the problem really IS prose. A printed exercise often labels
  // its math with a directive ("iii. Simplify the algebraic expression below
  // (4x²+…)²"), which reads as narrative yet leaves a COMPLETE expression outside
  // the words. `ascii` has the prose dropped, so if a real expression survives
  // there, this is directive+math — let the normal engines solve it.
  if (looksLikeWordProblem(rawLatex) && !hasStandaloneMath(ascii)) {
    return base("word_problem", "llm_candidate", "x", false, "word_problem");
  }

  const { isEquation } = splitEquation(ascii);

  // --- Expressions (no '=') --------------------------------------------
  if (!isEquation) {
    const vars = variablesIn(ascii);
    // Nothing computable survived the prose-drop: a scanned "Find X" arrives
    // here as the bare ascii "X", a figure-only problem as "" or "y y.". A
    // bare symbol "simplifies" to itself and passes the equality gate
    // trivially — a verified echo of nothing, which is exactly the confident
    // non-answer the golden rule forbids. Decline honestly instead: verifyMode
    // "none" yields the couldn't-verify state without ever calling the LLM.
    const hasOperation = /[+\-*/^(!]/.test(ascii);
    // A LONE unknown — even signed or subscripted ("x", "-x", "x_1") — is
    // still nothing to compute, though the sign/subscript smuggles in an
    // operator/digit character the coarse checks below would accept.
    const bareUnknown =
      /^[+-]?\s*[A-Za-z](?:_\{?[A-Za-z0-9]+\}?)?\s*\.?\s*$/.test(ascii);
    if (vars.length === 0) {
      // Constant arithmetic needs a number (or a bare constant like pi) to
      // evaluate; an empty/prose-only ascii has nothing to compute.
      if (!/\d/.test(ascii) && !/\b(?:pi|e)\b/.test(ascii)) {
        return base("arithmetic", "llm_candidate", "x", false, "none");
      }
      return base("arithmetic", "arithmetic", "x", false, "equality");
    }
    if (bareUnknown || (!/\d/.test(ascii) && !hasOperation)) {
      return base("expression", "llm_candidate", pickUnknown(vars), false, "none");
    }
    return base("expression", "simplify", pickUnknown(vars), false, "equality");
  }

  // --- Equations --------------------------------------------------------
  const parts = equationParts(ascii);
  const vars = variablesIn(ascii);
  const multiEquation = parts.length > 1;

  // A varless chain ("2+3 = 5 = 5") is an identity check, not a system —
  // decline honestly rather than inviting the tutor to "solve a system".
  if (multiEquation && vars.length === 0) {
    return base("arithmetic", "llm_candidate", "x", true, "none");
  }

  if (multiEquation || vars.length >= 2) {
    // A square LINEAR system solves deterministically (mathjs, verified A·x=b) and
    // is provably UNIQUE — keep that path.
    if (multiEquation) {
      const sys = parseLinearSystem(parts, vars);
      if (sys) {
        return base("linear_system", "linsystem", sys.vars[0], true, "none", {
          system: sys,
        });
      }
      // A 2-variable LINEAR + QUADRATIC pair (a line meeting a curve — the
      // GCSE staple, including the chained exam form A=B=C split above)
      // solves deterministically by substitution: the composed polynomial is
      // PROVEN degree ≤ 2, so enumerating its roots is complete, and every
      // (x, y) pair is substitution-verified against BOTH original equations.
      const simul = parseSimultaneous(parts, vars);
      if (simul) {
        return base(
          "simultaneous_equations",
          "simultaneous",
          simul.vars[0],
          true,
          "none",
          { simul }
        );
      }
    }
    // Anything else here is a NON-linear or NON-square/underdetermined system
    // (y=x² & y=x+2 has two solutions; x+y+z=6 & x−y=0 has infinitely many). The
    // substitution gate can only confirm that ONE assignment satisfies the
    // equations — it can't prove that assignment is unique or complete — so
    // shipping it would be a confident wrong/partial answer. Route to the tutor.
    return base("system_of_equations", "conceptual", pickUnknown(vars), true, "none");
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

/**
 * Deterministically map a §4 `problemType` → the ENGINE-owned teaching header
 * fields (spec §2, §4). The LLM is FORBIDDEN to choose these; `validateTeaching`
 * re-derives them and rejects any enrichment that disagrees, so the category and
 * difficulty a student sees can never be a model guess.
 *
 * Difficulty is a coarse schooling-level heuristic (steers tone/depth, not
 * scoring). Takes the bare `problemType` string so it works from both a
 * `Classification` (`cls.problemType`) and a returned `SolvePayload`
 * (`payload.problemType`).
 */
export function deriveTeachingMeta(problemType: string): TeachingMeta {
  const [category, difficulty] = TEACHING_META[problemType] ?? DEFAULT_META;
  return { category, difficulty };
}

const DEFAULT_META: [TeachingCategory, TeachingDifficulty] = ["other", "secondary"];

/** problemType → [category, difficulty]. Every value `classify()` can emit is
 * listed; an unknown type falls back to [DEFAULT_META]. */
const TEACHING_META: Record<string, [TeachingCategory, TeachingDifficulty]> = {
  // arithmetic / expressions
  arithmetic: ["arithmetic", "primary"],
  expression: ["algebra", "secondary"],
  // equations
  linear_equation: ["equations", "secondary"],
  quadratic_equation: ["equations", "secondary"],
  polynomial_equation: ["equations", "preUniversity"],
  exponential_equation: ["equations", "preUniversity"],
  logarithmic_equation: ["equations", "preUniversity"],
  linear_system: ["equations", "secondary"],
  simultaneous_equations: ["equations", "preUniversity"],
  system_of_equations: ["equations", "preUniversity"],
  // inequalities
  inequality: ["inequalities", "secondary"],
  // trigonometry
  trigonometric_equation: ["trigonometry", "preUniversity"],
  // word problems
  word_problem: ["word_problem", "secondary"],
  // statistics — the common scan is mean/median/mode of a small set (primary);
  // advanced descriptive stats still render, just pitched a touch simply.
  statistics: ["statistics", "primary"],
  // calculus
  derivative: ["calculus", "preUniversity"],
  partial_derivative: ["calculus", "university"],
  integral: ["calculus", "preUniversity"],
  definite_integral: ["calculus", "preUniversity"],
  maclaurin_series: ["calculus", "university"],
  taylor_series: ["calculus", "university"],
  // differential equations
  differential_equation: ["differential_equations", "university"],
  // linear algebra
  matrix_product: ["linear_algebra", "university"],
  matrix_sum: ["linear_algebra", "university"],
  matrix_difference: ["linear_algebra", "university"],
  linalg: ["linear_algebra", "university"],
  vector_dot: ["linear_algebra", "university"],
  vector_cross: ["linear_algebra", "university"],
  vector_magnitude: ["linear_algebra", "university"],
  vector_independent: ["linear_algebra", "university"],
  vector_spans: ["linear_algebra", "university"],
  // conceptual (proofs / multi-part → tutor)
  conceptual: ["conceptual", "university"],
  multi_part: ["conceptual", "secondary"],
};

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
  // A coefficient or sign BEFORE the integral sign — `-\int`, `2\int`,
  // `\frac{1}{2}\int` — scales the whole integral. Fold it into the integrand so
  // the gate (which numerically integrates / differentiates the integrand) sees
  // it; otherwise it was silently dropped and `-\int_0^1 x²dx` verified as +1/3.
  const prefixRaw = intMatch ? rawLatex.slice(0, intMatch.index ?? 0).trim() : "";
  const coefficient = prefixRaw ? latexToAscii(prefixRaw).trim() : "";
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
  let integrand = (m ? m[1] : cleaned).trim();
  const unknown = m ? m[2] : "x";
  const definite = lower !== undefined && upper !== undefined;

  // Apply the leading coefficient/sign as a factor on the integrand.
  if (coefficient === "-" || coefficient === "+") {
    integrand = `${coefficient}(${integrand})`;
  } else if (coefficient) {
    integrand = `(${coefficient})*(${integrand})`;
  }

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
/**
 * True when the prose-free ascii still holds a real math STATEMENT — an equation,
 * or an expression combining a variable with an operator. A genuine word problem
 * carries its numbers inside the sentence (its prose-free ascii is empty or a
 * bare number), so this stays false for it.
 */
function hasStandaloneMath(ascii: string): boolean {
  return /=/.test(ascii) || (/[a-zA-Z]/.test(ascii) && /[-+*/^]/.test(ascii));
}

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

/** Imperatives that pose a question part ("find …", "hence …", "sketch …"). */
const ASK_VERBS =
  /\b(find|evaluate|determine|calculate|compute|work\s*out|factori[sz]e|expand|simplify|sketch|state|prove|verify|show\s+that|write\s+down|hence)\b/gi;

/**
 * True when the input is a MULTI-PART or DERIVED-QUANTITY question rather than a
 * single solvable problem — see the call site. The single-answer engines would
 * confidently return one equation's root, which is the wrong quantity when the
 * question asks for a derived expression (x², xy, sin 2x) or has several parts.
 * Conservative: it fires on explicit multi-part structure, never on a bare
 * "solve …" / "find x" / "find the roots" / an integral / a derivative.
 */
function looksLikeMultiPart(rawLatex: string): boolean {
  // 1) Sub-part labels: (i) (ii) (iii) (iv) (a) (b) (c) (d). The "(" must not be
  //    glued to a symbol, so a function value like f(a) or a point (a,b) is safe.
  if (/(?:^|[\s\\}])\(\s*(?:i{1,3}|iv|v|[a-d])\s*\)/i.test(rawLatex)) return true;
  // 2) "hence" always chains a second part off the first.
  if (/\bhence\b/i.test(rawLatex)) return true;
  // 3) Two or more distinct asks ⇒ multi-part. Counts ASK_VERBS, their PAST-
  //    PARTICIPLE forms ("… should also be computed / is required"), and multi-
  //    STEP instruction verbs ("multiply by 3 … add 4").
  const asks =
    (rawLatex.match(ASK_VERBS) ?? []).length +
    (rawLatex.match(/\b(computed?|required|determined|calculated|evaluated|needed|wanted)\b/gi) ?? []).length +
    (rawLatex.match(/\b(multiply|divide|add|subtract|double|triple|halve|increase|decrease)\b/gi) ?? []).length;
  if (asks >= 2) return true;
  // A single ask followed by a sequencer ("… then double that", "… also …") is a
  // second step, so it's multi-part too.
  if (asks >= 1 && /\b(then|also|too|as\s+well|next|after\s+that)\b/i.test(rawLatex)) return true;
  // 3b) A word problem that asks SEVERAL things — two "?" / question phrases
  //     ("what is its area? what is its perimeter?"), or "find X and the Y".
  const questionMarks = (rawLatex.match(/\?/g) ?? []).length;
  const questionPhrases = (
    rawLatex.match(/\b(what\s+(?:is|are)|how\s+(?:many|much|far|fast|long|old|big))\b/gi) ?? []
  ).length;
  if (Math.max(questionMarks, questionPhrases) >= 2) return true;
  if (
    /\b(?:find|calculate|determine|work\s*out|what\s+(?:is|are))\b[^.?]*\b(?:and\s+(?:the|also|her|his|its|their)|as\s+well\s+as|along\s+with|together\s+with)\b/i.test(
      rawLatex
    )
  ) {
    return true;
  }
  // A SOLUTION CONSTRAINT stated in prose that the arithmetic gate can't enforce
  // — an angle qualifier, an interval, or a smallest/largest/quadrant selector.
  // The gate would verify a root of the bare equation on the WRONG branch (e.g.
  // "the obtuse angle x: cos x = −½" → 4π/3 instead of 2π/3). Route to the tutor.
  if (
    /\b(obtuse|acute|reflex|right)\s+angle|\bbetween\b[^.]*\band\b|\bin\s+the\s+(?:range|interval)\b|\b(?:smallest|largest|first|second|third|fourth)\b[^.]*\b(?:positive|negative|angle|value|quadrant|solution|root)\b|\bquadrant\b/i.test(
      rawLatex
    )
  ) {
    return true;
  }
  // 4) A separate "<expression> =" question line alongside another equation (a
  //    GIVEN): a "= ?" / "= □" placeholder, OR a trailing bare "=" left after a
  //    derived expression ("… \\ x·y =", "cos x = 3/5 \\ sin 2x = ?"). A plain
  //    "<var> =" answer blank was already stripped above, so a surviving trailing
  //    "=" marks a derived quantity to compute, distinct from solving the given.
  if (
    (/=\s*(?:\?|\\square|\\Box)/.test(rawLatex) || /\S\s*=\s*$/.test(rawLatex)) &&
    (rawLatex.match(/=/g) ?? []).length >= 2
  ) {
    return true;
  }
  // 5) Two separated statements that mix a standalone EXPRESSION (no "=") with an
  //    EQUATION — two different problems run together (e.g. "factor x²-5x+6" and
  //    "solve x-2=0"), which flattening would merge into one wrong equation.
  const segments = rawLatex
    .split(/\\\\|[;\n\r]|\\begin\s*\{[^}]*\}|\\end\s*\{[^}]*\}/)
    .map((seg) => seg.replace(/\\text\s*\{[^{}]*\}/g, " ").trim())
    .filter((seg) => /[a-zA-Z0-9]/.test(seg));
  if (segments.length >= 2) {
    // Each side must START as its own statement (an alphanumeric, "(", or a
    // function macro like \cos) — not a binary operator, which would mark a
    // wrapped continuation of one equation ("x²+2x  \\  +1=0"), not two problems.
    const statement = (seg: string) => /^(?:[a-zA-Z0-9(]|\\[a-zA-Z])/.test(seg);
    const hasBareExpr = segments.some(
      (seg) =>
        statement(seg) &&
        !seg.includes("=") &&
        // A standalone expression the "=" question is derived from: a polynomial
        // (x²-5x+6), a coefficient·variable (2x), a product/sum of variables
        // (x+y, x·y), OR a trig/log function (cos x — "given sin x=0.5, find
        // cos x" splits its ask onto its own line).
        /[a-zA-Z].*[-+*/^].*\d|\d.*[-+*/^].*[a-zA-Z]|[a-zA-Z]\s*[-+*/·]\s*[a-zA-Z]|\b(sin|cos|tan|cot|sec|csc|log|ln|sqrt)\b/i.test(
          seg
        )
    );
    const hasEquation = segments.some(
      (seg) => statement(seg) && /[a-zA-Z0-9]\s*=\s*\S/.test(seg)
    );
    if (hasBareExpr && hasEquation) return true;
  }
  // 6) A "find/evaluate <derived expression>" alongside an equation/given: the
  //    ask is for something COMPUTED FROM the solution (x², xy, 1/x, sin 2x,
  //    2x+1), not the plain solution itself. `find x` / `find the roots` / `find
  //    the value of x` are the plain solution and DON'T count.
  return asksForDerivedQuantity(rawLatex);
}

/** Does the input pair an equation/given with a "find <derived expression>"? */
function asksForDerivedQuantity(rawLatex: string): boolean {
  // Needs a relation to solve first (an "=", excluding a blank "= □" placeholder).
  if (!/=/.test(rawLatex.replace(/\\square|\\Box|=\s*\?/g, ""))) return false;
  // Grab the text right after a "find / evaluate / what is / how many" ask
  // (keep words; drop \text braces and environment delimiters).
  const s = rawLatex
    .replace(/\\(?:begin|end)\s*\{[^{}]*\}/g, " ")
    .replace(/\\text\s*\{([^{}]*)\}/g, " $1 ");
  const m =
    /\b(?:find|evaluate|determine|calculate|compute|work\s*out|what\s+(?:is|are)|how\s+(?:many|much))\b\s+(.*)$/is.exec(
      s
    );
  if (!m) return false;
  // Cut at the first clause end — a ":", sentence stop, or row break — so a
  // trailing "…: 2x+5=15" equation isn't mistaken for the ask target.
  let target = (m[1] ?? "").split(/[:.?;]|\\\\/)[0].trim();
  // A request for a Taylor/Maclaurin SERIES, an INTEGRAL, a DERIVATIVE, or a
  // LIMIT is not a derived-quantity ask — it has its own deterministic engine
  // ("find the Taylor series of e^x about x=2"). Leave it for that parser.
  if (
    /\b(series|expansion|maclaurin|taylor|integral|antiderivative|derivative|limit)\b/i.test(
      target
    )
  ) {
    return false;
  }
  // Strip a "(the) (exact) value(s) of" / leading "the" lead-in.
  target = target
    .replace(/^(?:the\s+)?(?:exact\s+)?values?\s+of\s+/i, "")
    .replace(/^the\s+/i, "")
    .trim();
  if (!target) return false;
  // The plain SOLUTION — not derived, so a normal solve handles it: the roots /
  // solutions, a bare variable, or a variable list ("x and y", "x, y").
  if (/^(?:roots?|solutions?)\b/i.test(target)) return false;
  if (/^[a-zA-Z]$/.test(target)) return false;
  if (/^[a-zA-Z](?:\s*(?:,|and)\s*[a-zA-Z])+$/i.test(target)) return false;
  // A short all-letter token that isn't a common word is a VARIABLE PRODUCT (xy,
  // pq) — a derived quantity.
  if (/^[a-z]{2,4}$/i.test(target) && !NON_PRODUCT_WORDS.has(target.toLowerCase())) {
    return true;
  }
  // Derived if the ask target applies an OPERATION to a variable: a power (x²,
  // x^2), a trig/log function, a product/ratio, an added term (2x+1), a function
  // evaluated at a point (f(2)), or the words squared/cubed/product.
  return /[a-zA-Z]\s*\^|[a-zA-Z][²³]|\bsquared\b|\bcubed\b|\bproduct\b|\b(sin|cos|tan|cot|sec|csc|log|ln|sqrt)\b|\\frac|[a-zA-Z]\s*[/*]|[a-zA-Z]\s*\(\s*-?\d|\d\s*[a-zA-Z]|[a-zA-Z]\s+[a-zA-Z]/i.test(
    target
  );
}

/**
 * Strip a leading imperative directive ("Solve …", "Find x: …", "Calculate the
 * value of …", "Evaluate …") when it's immediately followed by the MATH to work
 * on, so the directive words don't pollute classification. Only strips when what
 * remains starts as math — a word problem ("Find the number of apples John …")
 * has prose after the verb and is left untouched.
 */
function stripLeadingDirective(rawLatex: string): string {
  let s = rawLatex;
  // A leading `\text{…}` block that IS the directive ("Solve the algebraic
  // equation.", "iii. Simplify the expression below") — drop the whole block.
  const block = /^\s*\\text(?:rm|it|bf|sf|tt)?\s*\{([^{}]*)\}\s*/.exec(s);
  if (
    block &&
    /\b(?:solve|find|calculate|evaluate|determine|compute|work\s*out|simplify|factori[sz]e|expand)\b/i.test(
      block[1]
    )
  ) {
    s = s.slice(block[0].length);
  }
  // The bare directive ("Solve 2x+5=15") when it isn't wrapped in \text.
  const m =
    /^\s*(?:solve|find|calculate|evaluate|determine|compute|work\s*out|simplify|factori[sz]e|expand)\b(?:\s+(?:for|the|exact|values?|of|roots?|solutions?))*(?:\s+[a-z](?=\s*[:.}]))?\s*[:.]?\s*\}?\s*/i.exec(
      s
    );
  if (m) s = s.slice(m[0].length);
  // A leftover target from "find x: …" — the "x:" survives when the verb sat
  // inside a \text block and the variable outside it.
  s = s.replace(/^\s*[a-zA-Z]\s*:\s*/, "");
  if (s === rawLatex) return rawLatex;
  const rest = s.trim();
  // Keep the strip only if the remainder begins as a math expression, not more
  // prose — a number, a fraction/integral/function macro, a parenthesis, or a
  // variable next to an operator (`x =`, `2x`, `x^2`).
  if (
    /^(?:[-(]?\d|\\frac|\\d?frac|\\int|∫|\\sqrt|\\sin|\\cos|\\tan|\\log|\\ln|\(|[a-zA-Z]\s*[=+\-*/^]|[a-zA-Z]\s*\()/.test(
      rest
    )
  ) {
    return rest;
  }
  return rawLatex;
}

/** Short words that are NOT a variable product (so "find the sum" isn't derived). */
const NON_PRODUCT_WORDS = new Set([
  "the", "and", "for", "all", "any", "one", "two", "six", "ten", "sum", "set",
  "let", "get", "see", "are", "its", "new", "area", "cost", "rate", "mean",
  "mode", "size", "time", "term", "each", "them", "this", "that", "then",
]);

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
