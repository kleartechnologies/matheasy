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

import { latexToAscii } from "./latex";
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
  if (!rawLatex.includes("=")) return null;

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
  // prime: y'' / y' — the independent variable is implicit (guess from the text)
  m = s.match(/([a-zA-Z])\s*''/);
  if (m) return { depVar: m[1], indepVar: guessIndep(s, m[1]), order: 2 };
  m = s.match(/([a-zA-Z])\s*'/);
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
  // Derivative operators → placeholders (2nd order before 1st).
  s = s.replace(
    /\\frac\s*\{\s*d\s*\^\s*\{?\s*2\s*\}?\s*[a-zA-Z]\s*\}\s*\{\s*d\s*[a-zA-Z]\s*\^\s*\{?\s*2\s*\}?\s*\}/g,
    " ddy "
  );
  s = s.replace(/d\s*\^\s*\{?\s*2\s*\}?\s*[a-zA-Z]\s*\/\s*d\s*[a-zA-Z]\s*\^\s*\{?\s*2\s*\}?/g, " ddy ");
  s = s.replace(/\\frac\s*\{\s*d\s*[a-zA-Z]\s*\}\s*\{\s*d\s*[a-zA-Z]\s*\}/g, " dy ");
  s = s.replace(/d\s*[a-zA-Z]\s*\/\s*d\s*[a-zA-Z]/g, " dy ");
  // prime, with an optional functional argument y''(x) / y'(x)
  s = s.replace(new RegExp(`${dep}\\s*''\\s*(?:\\(\\s*${indep}\\s*\\))?`, "g"), " ddy ");
  s = s.replace(new RegExp(`${dep}\\s*'\\s*(?:\\(\\s*${indep}\\s*\\))?`, "g"), " dy ");
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
 */
export function verifyOde(
  residual: string,
  depVar: string,
  indepVar: string,
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

  const consts = freeConstants(solution, indepVar);

  // Initial conditions require a PARTICULAR solution (no free constants left) —
  // an unresolved constant means the answer isn't pinned down, so decline.
  if (initial.length > 0) {
    if (consts.length > 0) return false;
    for (const ic of initial) {
      const expr = ic.order === 0 ? solution : ic.order === 1 ? dExpr : ddExpr;
      const got = evalReal(expr, { [indepVar]: ic.at });
      if (!Number.isFinite(got) || !near(got, ic.value)) return false;
    }
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

/** Free constants in `expr` — symbols that don't resolve (C1, C2, K…), minus the
 * independent variable and mathjs constants (e, pi). */
function freeConstants(expr: string, indep: string): string[] {
  const names = new Set<string>();
  try {
    parse(expr).traverse((node: unknown) => {
      const n = node as { type?: string; name?: string };
      if (n.type === "SymbolNode" && n.name) names.add(n.name);
    });
  } catch {
    return [];
  }
  return [...names].filter((name) => {
    if (name === indep) return false;
    try {
      parse(name).evaluate(); // e/pi/sin resolve → not a free constant
      return false;
    } catch {
      return true; // undefined symbol → a free constant to sample
    }
  });
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
