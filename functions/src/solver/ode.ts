/**
 * Ordinary differential equations — the LLM-CANDIDATE path (Phase C).
 *
 * The golden rule holds without an engine that can integrate: the LLM PROPOSES a
 * solution y(x), and we PROVE it by substitution — differentiate the candidate
 * with mathjs and check the ODE's residual F(x, y, y', y'') ≈ 0 across many
 * sample points AND several values of the arbitrary constants (a general
 * solution must satisfy the ODE identically, for every constant). An initial
 * condition, when given, is checked directly. A candidate that isn't actually a
 * solution leaves a non-zero residual and is rejected → honest couldn't-verify.
 *
 * We never trust the model's answer; we re-derive and re-substitute it here.
 *
 * Scope: first- and second-order ODEs in Leibniz (dy/dx, d²y/dx²), prime (y', y''),
 * or slashed notation, optionally with numeric initial conditions. Anything the
 * parser can't read cleanly declines.
 */
import { derivative, parse } from "mathjs";

import { asciiToLatex, latexToAscii } from "./latex";
import { FinalAnswer } from "./types";
import { evalReal } from "./verify";

export interface OdeInitialCondition {
  order: number; // 0 = y(a), 1 = y'(a), 2 = y''(a)
  at: number;
  value: number;
}

export interface OdeQuery {
  residual: string; // ascii expression in tokens: indepVar, depVar, "dy", "ddy"
  depVar: string;
  indepVar: string;
  order: number;
  initial: OdeInitialCondition[];
}

/** Detect an ODE and build its residual + initial conditions, or null. */
export function parseOde(rawLatex: string): OdeQuery | null {
  // A real scanned/typed ODE is short; cap the length so a pathological
  // space-flood can't drive the derivative regexes into slow backtracking.
  if (!rawLatex.includes("=") || rawLatex.length > 2000) return null;

  // Pull out numeric initial conditions FIRST, then strip them so the ODE clause
  // is isolated (an IC like "y'(0)=1" also contains a derivative token).
  const depGuess = guessDepVar(rawLatex);
  if (!depGuess) return null;
  const initial = parseInitial(rawLatex, depGuess);
  const odeText = pickOdeClause(stripInitial(rawLatex, depGuess));

  const det = detectDerivative(odeText);
  if (!det) return null;
  const { depVar, indepVar, order } = det;
  if (depVar === indepVar || depVar === "d" || depVar === "e") return null;

  const residual = buildResidual(odeText, depVar, indepVar);
  if (!residual) return null;
  // A real ODE's residual must involve a derivative token, and must parse.
  if (!/\b(dy|ddy)\b/.test(residual)) return null;
  try {
    parse(residual);
  } catch {
    return null;
  }

  return { residual, depVar, indepVar, order, initial };
}

/** The dependent variable — the letter carrying a derivative (Leibniz or prime). */
function guessDepVar(s: string): string | null {
  const d = detectDerivative(s);
  return d ? d.depVar : null;
}

/** Identify dependent/independent variable + order from the first derivative. */
function detectDerivative(
  s: string
): { depVar: string; indepVar: string; order: number } | null {
  // 3rd+ order (triple prime, or d^3…/dx^3) is out of scope — decline cleanly.
  if (/[a-zA-Z]\s*'''/.test(s) || /d\s*\^\s*\{?\s*[3-9]/.test(s)) return null;
  let m: RegExpMatchArray | null;
  // 2nd-order Leibniz: \frac{d^2 y}{dx^2}
  m = s.match(
    /\\frac\s*\{\s*d\s*\^\s*\{?\s*2\s*\}?\s*([a-zA-Z])\s*\}\s*\{\s*d\s*([a-zA-Z])\s*\^\s*\{?\s*2\s*\}?\s*\}/
  );
  if (m) return { depVar: m[1], indepVar: m[2], order: 2 };
  // 2nd-order slashed: d^2y/dx^2
  m = s.match(/d\s*\^\s*\{?\s*2\s*\}?\s*([a-zA-Z])\s*\/\s*d\s*([a-zA-Z])\s*\^\s*\{?\s*2\s*\}?/);
  if (m) return { depVar: m[1], indepVar: m[2], order: 2 };
  // 1st-order Leibniz: \frac{dy}{dx}
  m = s.match(/\\frac\s*\{\s*d\s*([a-zA-Z])\s*\}\s*\{\s*d\s*([a-zA-Z])\s*\}/);
  if (m) return { depVar: m[1], indepVar: m[2], order: 1 };
  // 1st-order slashed: dy/dx
  m = s.match(/d\s*([a-zA-Z])\s*\/\s*d\s*([a-zA-Z])/);
  if (m) return { depVar: m[1], indepVar: m[2], order: 1 };
  // prime: y'' / y' — the independent variable is implicit (guess from the text).
  // The negative lookahead rejects an apostrophe inside prose ("it's", "Tom's"),
  // where the ' is followed by a letter, so a word problem isn't hijacked.
  m = s.match(/([a-zA-Z])\s*''(?![A-Za-z'])/);
  if (m) return { depVar: m[1], indepVar: guessIndep(s, m[1]), order: 2 };
  m = s.match(/([a-zA-Z])\s*'(?![A-Za-z'])/);
  if (m) return { depVar: m[1], indepVar: guessIndep(s, m[1]), order: 1 };
  return null;
}

/** For prime notation, pick the independent variable from the usual suspects. */
function guessIndep(s: string, dep: string): string {
  for (const v of ["x", "t", "s", "u"]) {
    if (v !== dep && new RegExp(`\\b${v}\\b`).test(s)) return v;
  }
  return "x";
}

/** Rewrite the ODE clause into `(lhs) - (rhs)` with dy/ddy placeholder tokens. */
function buildResidual(odeText: string, dep: string, indep: string): string | null {
  let s = odeText;
  // Derivative operators → placeholders (2nd order before 1st). CRITICAL: these
  // match ONLY THIS ODE's own dep/indep (d<dep>/d<indep>), never [a-zA-Z]
  // wildcards — otherwise a DIFFERENT derivative in the input (e.g. dx/dy, or an
  // OCR-typo dz/dx) would collapse to the same dy/ddy token and hand verifyOde an
  // identically-zero residual that accepts any candidate.
  s = s.replace(
    new RegExp(String.raw`\\frac\s*\{\s*d\s*\^\s*\{?\s*2\s*\}?\s*${dep}\s*\}\s*\{\s*d\s*${indep}\s*\^\s*\{?\s*2\s*\}?\s*\}`, "g"),
    " ddy "
  );
  s = s.replace(
    new RegExp(String.raw`d\s*\^\s*\{?\s*2\s*\}?\s*${dep}\s*\/\s*d\s*${indep}\s*\^\s*\{?\s*2\s*\}?`, "g"),
    " ddy "
  );
  s = s.replace(
    new RegExp(String.raw`\\frac\s*\{\s*d\s*${dep}\s*\}\s*\{\s*d\s*${indep}\s*\}`, "g"),
    " dy "
  );
  s = s.replace(new RegExp(String.raw`d\s*${dep}\s*\/\s*d\s*${indep}`, "g"), " dy ");
  // prime, with an optional functional argument y''(x) / y'(x); the negative
  // lookahead keeps a prose apostrophe from being turned into a derivative.
  s = s.replace(new RegExp(`${dep}\\s*''(?![A-Za-z'])\\s*(?:\\(\\s*${indep}\\s*\\))?`, "g"), " ddy ");
  s = s.replace(new RegExp(`${dep}\\s*'(?![A-Za-z'])\\s*(?:\\(\\s*${indep}\\s*\\))?`, "g"), " dy ");
  // dep value notation y(x) → y
  s = s.replace(new RegExp(`${dep}\\s*\\(\\s*${indep}\\s*\\)`, "g"), ` ${dep} `);

  const parts = s.split("=");
  if (parts.length !== 2) return null;
  const lhs = latexToAscii(parts[0]).trim();
  const rhs = latexToAscii(parts[1]).trim();
  if (!lhs || !rhs) return null;
  return `(${lhs}) - (${rhs})`;
}

/** Numeric initial conditions: y(a)=v, y'(a)=v, y''(a)=v. */
function parseInitial(rawLatex: string, dep: string): OdeInitialCondition[] {
  const re = new RegExp(
    `${dep}\\s*('{0,2})\\s*\\(\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\)\\s*=\\s*(-?\\d+(?:\\.\\d+)?)`,
    "g"
  );
  const out: OdeInitialCondition[] = [];
  for (const m of rawLatex.matchAll(re)) {
    out.push({ order: m[1].length, at: Number(m[2]), value: Number(m[3]) });
  }
  return out;
}

/** From comma/semicolon-separated clauses, the one that IS the ODE (an `=` and a
 * derivative of the dependent variable) — so a leftover ", " from a stripped IC
 * can't pollute the residual. */
function pickOdeClause(s: string): string {
  const clauses = s.split(/[,;]/).map((c) => c.trim()).filter(Boolean);
  for (const c of clauses) {
    if (c.includes("=") && detectDerivative(c)) return c;
  }
  return s.trim();
}

/** Remove IC clauses so only the ODE remains. */
function stripInitial(rawLatex: string, dep: string): string {
  const re = new RegExp(
    `${dep}\\s*'{0,2}\\s*\\(\\s*-?\\d+(?:\\.\\d+)?\\s*\\)\\s*=\\s*-?\\d+(?:\\.\\d+)?`,
    "g"
  );
  return rawLatex.replace(re, " ");
}

// ---- verification ----------------------------------------------------------

const XS = [-1.3, 0.37, 1.6, 2.9, -0.6, 0.9];
const CVALS = [1.7, -0.8, 2.3, 0.6];
const MIN_MATCHED = 4;

/**
 * Prove `solution` solves the ODE: differentiate it, then check the residual is
 * ≈0 across sample points and several constant values, plus any initial
 * conditions. Returns false (→ couldn't-verify) unless it genuinely checks out.
 *
 * Two gates beyond "residual ≈ 0" keep an INCOMPLETE or DEGENERATE answer from
 * passing (both are golden-rule holes — a wrong answer that still zeroes the
 * residual):
 *   • the residual must genuinely CONSTRAIN the highest derivative (else a
 *     mis-parsed `(dy)-(dy)` ≡ 0 would accept anything), and
 *   • without initial conditions, the candidate must be the GENERAL solution —
 *     exactly `order` INDEPENDENT arbitrary constants (so `C1 e^{2x}` for a
 *     2nd-order ODE, or a dropped constant, is rejected).
 */
export function verifyOde(
  residual: string,
  depVar: string,
  indepVar: string,
  order: number,
  solution: string,
  initial: OdeInitialCondition[]
): boolean {
  if (!solution || !solution.trim()) return false;
  let dExpr: string;
  let ddExpr: string;
  try {
    const y = parse(solution);
    const d = derivative(y, indepVar);
    dExpr = d.toString();
    ddExpr = derivative(d, indepVar).toString();
  } catch {
    return false;
  }

  // Degeneracy guard: the residual must actually depend on the top derivative.
  if (!residualConstrains(residual, depVar, indepVar, order)) return false;

  const consts = freeConstants(solution, indepVar);

  if (initial.length > 0) {
    // An IVP wants the PARTICULAR solution — no arbitrary constants left.
    if (consts.length > 0) return false;
    for (const ic of initial) {
      const expr = ic.order === 0 ? solution : ic.order === 1 ? dExpr : ddExpr;
      const got = evalReal(expr, { [indepVar]: ic.at });
      if (!Number.isFinite(got) || !near(got, ic.value)) return false;
    }
  } else if (!constantsIndependent(solution, indepVar, consts, order)) {
    // No ICs → require the full general solution: `order` independent constants.
    return false;
  }

  // Substitution check: residual ≈ 0 at every (x, constants) sample.
  const combos = constantScopes(consts);
  let matched = 0;
  for (const cs of combos) {
    for (const xv of XS) {
      const scope = { ...cs, [indepVar]: xv };
      const yv = evalReal(solution, scope);
      const dyv = evalReal(dExpr, scope);
      const ddyv = evalReal(ddExpr, scope);
      if (![yv, dyv, ddyv].every(Number.isFinite)) continue;
      const r = evalReal(residual, {
        [indepVar]: xv,
        [depVar]: yv,
        dy: dyv,
        ddy: ddyv,
      });
      if (!Number.isFinite(r)) continue;
      const scale = 1 + Math.abs(yv) + Math.abs(dyv) + Math.abs(ddyv) + Math.abs(xv);
      if (Math.abs(r) > 1e-6 * scale) return false;
      matched++;
    }
  }
  return matched >= MIN_MATCHED;
}

function near(a: number, b: number): boolean {
  return Math.abs(a - b) <= 1e-6 * Math.max(1, Math.abs(a), Math.abs(b)) + 1e-9;
}

/** Free constants in `expr` — its symbols (C1, C2, K, C…) minus the independent
 * variable, the math constants e/pi/i, and any function names. NB: we do NOT use
 * `parse(name).evaluate()` to filter — mathjs resolves a bare `C` to the Coulomb
 * UNIT, which would wrongly drop a constant named `C`. */
function freeConstants(expr: string, indep: string): string[] {
  const symbols = new Set<string>();
  const funcs = new Set<string>();
  try {
    parse(expr).traverse((node: unknown) => {
      const n = node as { type?: string; name?: string; fn?: { name?: string } };
      if (n.type === "FunctionNode" && n.fn?.name) funcs.add(n.fn.name);
      if (n.type === "SymbolNode" && n.name) symbols.add(n.name);
    });
  } catch {
    return [];
  }
  const reserved = new Set([indep, "e", "pi", "i", "Infinity", "NaN"]);
  return [...symbols].filter((name) => !reserved.has(name) && !funcs.has(name));
}

/** The residual must genuinely depend on the ODE's highest derivative — else a
 * mis-parse that produced an identically-zero residual (e.g. `(dy)-(dy)`) would
 * accept ANY candidate. Bumping that derivative token must change the value. */
function residualConstrains(
  residual: string,
  depVar: string,
  indepVar: string,
  order: number
): boolean {
  const base: Record<string, number> = { [indepVar]: 0.5, [depVar]: 0.7, dy: 1.1, ddy: 1.3 };
  const tok = order >= 2 ? "ddy" : "dy";
  const r0 = evalReal(residual, base);
  const r1 = evalReal(residual, { ...base, [tok]: base[tok] + 1 });
  return Number.isFinite(r0) && Number.isFinite(r1) && Math.abs(r0 - r1) > 1e-9;
}

/** Whether `solution` carries exactly `order` INDEPENDENT arbitrary constants —
 * the mark of the GENERAL solution. The columns ∂y/∂C_i (numeric) must be
 * linearly independent (rank == order); this rejects a dropped constant (too
 * few) and a rank-deficient family like `C1 e^x + C2 e^x` (two symbols, one
 * degree of freedom — the missing repeated-root branch). */
function constantsIndependent(
  solution: string,
  indep: string,
  consts: string[],
  order: number
): boolean {
  if (consts.length !== order) return false;
  if (order === 0) return true;
  const xs = [0.3, 0.8, 1.5, 2.1, -0.5];
  const base: Record<string, number> = {};
  consts.forEach((c, k) => {
    base[c] = CVALS[k % CVALS.length];
  });
  const h = 1e-4;
  const rows: number[][] = [];
  for (const c of consts) {
    const row: number[] = [];
    for (const xv of xs) {
      const up = evalReal(solution, { ...base, [c]: base[c] + h, [indep]: xv });
      const dn = evalReal(solution, { ...base, [c]: base[c] - h, [indep]: xv });
      if (!Number.isFinite(up) || !Number.isFinite(dn)) return false;
      row.push((up - dn) / (2 * h));
    }
    rows.push(row);
  }
  return matrixRank(rows) === order;
}

/** Numeric rank via Gaussian elimination with a scale-relative tolerance. */
function matrixRank(rows: number[][]): number {
  const m = rows.map((r) => [...r]);
  const nRows = m.length;
  const nCols = m[0]?.length ?? 0;
  const globalMax = Math.max(1, ...m.flat().map((v) => Math.abs(v)));
  const tol = 1e-8 * globalMax;
  let rank = 0;
  for (let col = 0; col < nCols && rank < nRows; col++) {
    let piv = -1;
    let best = tol;
    for (let r = rank; r < nRows; r++) {
      if (Math.abs(m[r][col]) > best) {
        best = Math.abs(m[r][col]);
        piv = r;
      }
    }
    if (piv === -1) continue;
    [m[rank], m[piv]] = [m[piv], m[rank]];
    const pivVal = m[rank][col];
    for (let r = 0; r < nRows; r++) {
      if (r === rank) continue;
      const f = m[r][col] / pivVal;
      for (let cc = col; cc < nCols; cc++) m[r][cc] -= f * m[rank][cc];
    }
    rank++;
  }
  return rank;
}

/** The DISPLAYED answer, rendered from the VERIFIED solution expression (never
 * the model's free-text answerLatex, which is never substitution-checked). */
export function odeAnswer(depVar: string, solution: string): FinalAnswer {
  return { latex: `${depVar} = ${asciiToLatex(solution)}`, plain: `${depVar} = ${solution}` };
}

/** A handful of scopes assigning each free constant distinct sample values. */
function constantScopes(consts: string[]): Record<string, number>[] {
  if (consts.length === 0) return [{}];
  const scopes: Record<string, number>[] = [];
  for (let i = 0; i < CVALS.length; i++) {
    const scope: Record<string, number> = {};
    consts.forEach((c, k) => {
      scope[c] = CVALS[(i + k) % CVALS.length];
    });
    scopes.push(scope);
  }
  return scopes;
}
