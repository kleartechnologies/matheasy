/**
 * Change of subject — "make x the subject of 2x − 5y = 10".
 *
 * A worksheet staple (the Politeknik Basic Algebra notes give it a whole
 * chapter) that had no engine at all: two variables in one equation read as a
 * SYSTEM, so the student was told the problem "may have several solutions"
 * about a formula that has exactly one rearrangement.
 *
 * The answer is a formula, not a number, which changes what verification can
 * mean. It is still substitution: the derived expression is put back into the
 * ORIGINAL printed equation and both sides are evaluated at several random
 * numeric draws of the free variables. A rearrangement that is wrong anywhere
 * is wrong at almost every draw, so a handful of them is a real gate — and a
 * derivation that can't be evaluated (every draw lands outside the domain)
 * declines rather than claiming a proof it doesn't have.
 *
 * Radicals are handled by isolate-then-square: `√u` is carried as an atom,
 * solved for linearly, and only then squared — which is why `3y = √(5x) − 9`
 * comes out as `x = (3y+9)²/5` and not as a decline.
 */
import { evaluate, rationalize } from "mathjs";

import { asciiToLatex, latexToAscii, splitEquation, unwrapProse, variablesIn } from "./latex";
import {
  Poly,
  linearIn,
  polyIsZero,
  polyNeg,
  polyToAscii,
  quadraticIn,
  reduceFraction,
  toPoly,
} from "./polynomial";
import { FinalAnswer, RawStep, SolveCandidate } from "./types";

export interface SubjectQuery {
  /** The formula's two sides, as ascii — exactly as printed. */
  lhs: string;
  rhs: string;
  /** The variable to isolate. */
  target: string;
  /** How the instruction was phrased, for the working. */
  label: string;
}

// ---------------------------------------------------------------------------
// parsing
// ---------------------------------------------------------------------------

/** The instruction, and where it sat, so the formula can be lifted out around it. */
const CUES: { re: RegExp; label: (v: string) => string }[] = [
  {
    re: /\bmake\s+([a-zA-Z])\s+(?:the\s+)?subject(?:\s+of(?:\s+the)?(?:\s+formula|\s+equation)?)?\s*[:,.]?/i,
    label: (v) => `\\text{make } ${v} \\text{ the subject}`,
  },
  {
    re: /\b([a-zA-Z])\s+as\s+the\s+subject(?:\s+of(?:\s+the)?(?:\s+formula|\s+equation)?)?\s*[:,.]?/i,
    label: (v) => `\\text{make } ${v} \\text{ the subject}`,
  },
  {
    re: /\bexpress\s+([a-zA-Z])\s+in\s+terms\s+of\s+[a-zA-Z](?:\s*(?:,|and)\s*[a-zA-Z])*\s*[:,.]?/i,
    label: (v) => `\\text{express } ${v} \\text{ in terms of the rest}`,
  },
  {
    re: /\b(?:rearrange|transpose|rewrite)\b[^=]*?\b(?:for|to\s+give|in\s+terms\s+of)\s+([a-zA-Z])\b\s*[:,.]?/i,
    label: (v) => `\\text{rearrange for } ${v}`,
  },
  {
    re: /\bsolve\s+(?:the\s+(?:formula|equation)\s+)?for\s+([a-zA-Z])\b\s*[:,.]?/i,
    label: (v) => `\\text{solve for } ${v}`,
  },
];

/**
 * The worksheet's own notation: the equation, then the target in brackets.
 * Exercise 5.0 is printed exactly this way ("v = u + at   [t]"), so a scan of
 * the page arrives with no verb in it at all.
 */
const BRACKETED = /\[\s*([a-zA-Z])\s*\]\s*$/;

export function parseChangeOfSubject(rawLatex: string): SubjectQuery | null {
  const prose = unwrapProse(rawLatex);
  if (!prose.includes("=")) return null;

  let target: string | null = null;
  let label = "";
  let formula = prose;

  for (const cue of CUES) {
    const m = cue.re.exec(prose);
    if (!m) continue;
    // The instruction can only be an instruction if it sits OUTSIDE the maths —
    // "for x" lifted out of the middle of an equation is not a directive.
    target = m[1];
    label = cue.label(target);
    formula = (prose.slice(0, m.index) + " " + prose.slice(m.index + m[0].length)).trim();
    break;
  }

  if (!target) {
    const b = BRACKETED.exec(prose);
    if (!b) return null;
    target = b[1];
    label = `\\text{make } ${target} \\text{ the subject}`;
    formula = prose.slice(0, b.index).trim();
  }

  // Whatever the instruction left behind still has to be one clean equation.
  formula = formula
    .replace(/^[\s,.;:]+|[\s,.;:]+$/g, "")
    .replace(/^\s*(?:of|in|from|the|formula|equation|given)\b\s*/i, "")
    .trim();
  if (!formula.includes("=")) return null;

  const parts = splitEquation(latexToAscii(formula));
  if (!parts.isEquation) return null;

  // Two variables minimum, or there is no "subject" to change — a one-unknown
  // equation is a normal equation and must keep going to the normal solver.
  const vars = variablesIn(`${parts.lhs} = ${parts.rhs}`);
  if (vars.length < 2) return null;
  if (!vars.includes(target)) return null;

  return { lhs: parts.lhs, rhs: parts.rhs, target, label };
}

// ---------------------------------------------------------------------------
// solving
// ---------------------------------------------------------------------------

/** How many random draws the gate uses, and how many must land in the domain. */
const DRAWS = 64;
const MIN_USABLE = 4;

export function solveChangeOfSubject(cls: { subject?: SubjectQuery }): SolveCandidate | null {
  const q = cls.subject;
  if (!q) return null;

  const steps: RawStep[] = [
    step(`${q.lhs} = ${q.rhs}`, "GIVEN"),
    step(q.label, "IDENTIFY"),
  ];

  const isolated = isolate(q, steps);
  if (!isolated) return null;

  // THE GATE. The derived expression goes back into the equation as printed.
  const free = variablesIn(`${q.lhs} = ${q.rhs}`).filter((v) => v !== q.target);
  const holds = () => substitutionHolds(q, isolated, free);
  if (!holds()) return null;

  const plain = `${q.target} = ${isolated.expr}`;
  steps.push(step(plain, "RESULT"));
  const answer: FinalAnswer = { latex: asciiToLatex(plain), plain };

  return {
    answer,
    methods: [
      {
        id: "change_of_subject",
        name: "Rearrange the formula",
        examPick: true,
        steps,
      },
    ],
    plotExpression: null,
    verify: holds,
  };
}

/**
 * The target, isolated. Radicals first (a `√` containing the target can't be
 * reached by any amount of polynomial rearrangement until it is squared away),
 * then the linear/quadratic split.
 */
function isolate(q: SubjectQuery, steps: RawStep[]): Isolated | null {
  let lhs = q.lhs;
  let rhs = q.rhs;
  // Expressions the ORIGINAL equation requires to be ≥ 0. Squaring away a root
  // manufactures solutions the printed equation never had (`3y = √(5x) − 9`
  // forces `3y + 9 ≥ 0`), and the gate has to know that or it fails a correct
  // rearrangement on a draw the question itself excluded.
  const nonNegative: string[] = [];

  const squared = clearRadical(lhs, rhs, q.target);
  if (squared) {
    lhs = squared.lhs;
    rhs = squared.rhs;
    nonNegative.push(squared.nonNegative);
    steps.push(step(`${lhs} = ${rhs}`, "SQUARE_BOTH_SIDES"));
  }

  // `lhs - rhs = 0`, over a common denominator so a target under a fraction bar
  // comes up into the numerator (`m = p/(p-5)` is linear in p only once cleared).
  const diff = overCommonDenominator(`(${lhs}) - (${rhs})`);
  if (!diff) return null;
  const got = toPoly(diff);
  if (!got || got.atoms.source.size > 0) return null;
  const p = got.poly;
  const atoms = got.atoms.source;

  const lin = linearIn(p, q.target);
  if (lin && !polyIsZero(lin.a)) {
    // A·t + B = 0  ⟹  t = −B/A.
    const { num, den } = reduceFraction(polyNeg(lin.b), lin.a);
    steps.push(step(`${polyToAscii(lin.a, atoms)} \\cdot ${q.target} = ${polyToAscii(polyNeg(lin.b), atoms)}`, "COLLECT_LIKE_TERMS"));
    return { expr: quotient(num, den, atoms), nonNegative };
  }

  // A·t² + C = 0 with no linear term — the `V = ⅓πr²h → r = √(3V/(πh))` shape.
  // The POSITIVE root only: these are lengths and rates, and a formula with a ±
  // in it is not what the question asked for.
  const quad = quadraticIn(p, q.target);
  if (quad && !polyIsZero(quad.a) && polyIsZero(quad.b)) {
    const { num, den } = reduceFraction(polyNeg(quad.c), quad.a);
    const inner = quotient(num, den, atoms);
    // The value under the new root has to be a real one, or the formula is
    // being read outside its own domain.
    return { expr: `sqrt(${inner})`, nonNegative: [...nonNegative, inner] };
  }
  return null;
}

/** An isolated target, plus what the original equation requires to stay real. */
interface Isolated {
  expr: string;
  nonNegative: string[];
}

/** `num/den` printed, with the bar dropped when the denominator is 1. */
function quotient(num: Poly, den: Poly, atoms: Map<string, string>): string {
  const top = polyToAscii(num, atoms);
  const bottom = polyToAscii(den, atoms);
  if (bottom === "1") return top;
  const wrap = (s: string) => (/^-?[A-Za-z0-9_$.]+$/.test(s) ? s : `(${s})`);
  return `${wrap(top)}/${wrap(bottom)}`;
}

/**
 * A single square root containing the target, isolated and squared away.
 *
 * The root is treated as one unknown: `h − 3 = √(k+1)/2` is LINEAR in `√(k+1)`,
 * so solve for it (`√(k+1) = 2h − 6`), and only then square. Returns null when
 * there isn't exactly one such root, or when it isn't linear in it — squaring a
 * sum of two roots produces a third one and gets nowhere.
 */
function clearRadical(
  lhs: string,
  rhs: string,
  target: string
): { lhs: string; rhs: string; nonNegative: string } | null {
  const whole = `(${lhs}) - (${rhs})`;
  const roots = findRoots(whole).filter((r) => variablesIn(r.arg).includes(target));
  if (roots.length !== 1) return null;
  const root = roots[0];

  // Stand a placeholder in for the root and read the equation as linear in it.
  const marker = "__rad";
  const masked = whole.split(root.text).join(marker);
  if (masked.includes("sqrt(")) return null; // another root we can't account for
  const got = toPoly(masked);
  if (!got || got.atoms.source.size > 0) return null;
  const lin = linearIn(got.poly, marker);
  if (!lin || polyIsZero(lin.a)) return null;

  const { num, den } = reduceFraction(polyNeg(lin.b), lin.a);
  const value = quotient(num, den, new Map());
  // √u = value  ⟹  u = value², and `value ≥ 0`, which is the half of the
  // statement squaring throws away. It travels with the answer as a domain
  // condition so the gate tests the rearrangement, not the excluded half-line.
  return { lhs: root.arg, rhs: `(${value})^2`, nonNegative: value };
}

/** Every `sqrt(…)` call in an ascii expression, with its argument. */
function findRoots(ascii: string): { text: string; arg: string }[] {
  const out: { text: string; arg: string }[] = [];
  for (let i = ascii.indexOf("sqrt("); i >= 0; i = ascii.indexOf("sqrt(", i + 1)) {
    let depth = 0;
    for (let j = i + 4; j < ascii.length; j++) {
      if (ascii[j] === "(") depth++;
      else if (ascii[j] === ")") {
        depth--;
        if (depth === 0) {
          out.push({ text: ascii.slice(i, j + 1), arg: ascii.slice(i + 5, j) });
          break;
        }
      }
    }
  }
  return out;
}

/**
 * An expression put over one denominator, as the numerator alone. Setting a
 * quotient to zero is setting its numerator to zero, and that is what turns a
 * formula with the target under a bar into a polynomial one.
 */
function overCommonDenominator(ascii: string): string | null {
  try {
    const r = rationalize(ascii, {}, true) as unknown as {
      numerator: { toString(): string };
    };
    return r.numerator.toString();
  } catch {
    return ascii;
  }
}

// ---------------------------------------------------------------------------
// the gate
// ---------------------------------------------------------------------------

/**
 * Put the derived expression back into the printed equation and check both
 * sides agree, at pseudo-random draws of the free variables.
 *
 * Deterministic draws (a fixed LCG), because a gate that passes on Tuesday and
 * fails on Wednesday is not a gate. Draws that land outside the domain — a
 * division by zero, a root of a negative, a denominator the rearrangement had
 * to assume nonzero — are skipped, but at least `MIN_USABLE` must survive or
 * the verdict is "not proven", not "proven".
 */
function substitutionHolds(q: SubjectQuery, expr: Isolated, free: string[]): boolean {
  let seed = 20240917;
  const next = () => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed / 2147483648;
  };
  let usable = 0;
  for (let i = 0; i < DRAWS; i++) {
    const scope: Record<string, number> = {};
    for (const v of free) scope[v] = Math.round((next() * 12 - 4) * 1000) / 1000 + 0.5;
    // A draw the printed equation itself excludes proves nothing either way.
    if (expr.nonNegative.some((c) => (num(c, scope) ?? -1) < 0)) continue;
    const t = num(expr.expr, scope);
    if (t === null) continue;
    const left = num(q.lhs, { ...scope, [q.target]: t });
    const right = num(q.rhs, { ...scope, [q.target]: t });
    if (left === null || right === null) continue;
    const tol = 1e-7 * Math.max(1, Math.abs(left), Math.abs(right));
    if (Math.abs(left - right) > tol) return false;
    usable++;
  }
  return usable >= MIN_USABLE;
}

function num(ascii: string, scope: Record<string, number>): number | null {
  try {
    const v = evaluate(ascii, scope);
    const n = typeof v === "number" ? v : Number(v as unknown as number);
    return Number.isFinite(n) ? n : null;
  } catch {
    return null;
  }
}

/** A step. `text` is ascii-math (a `\text{…}` label passes through untouched);
 * it is typeset here rather than shipped raw, or the student reads `sqrt(` and
 * a slash where the formula has a root and a fraction bar. */
function step(text: string, code: string): RawStep {
  return { ascii: text, operationCode: code, latex: asciiToLatex(text) };
}
