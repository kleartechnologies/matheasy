/**
 * Checking a student's own handwritten working — deterministically (spec Part 12).
 *
 * A student photographs their working and asks "where did I go wrong?". The
 * tempting implementation is to hand the photo to the model and let it judge.
 * That breaks the app's golden rule twice over: the model would be inventing
 * arithmetic, and it would be asserting a verdict about the student's work with
 * nothing behind it — the single most damaging thing a tutor can get wrong.
 *
 * So the verdict is computed HERE, by the same machinery that gates every answer
 * the app ships:
 *
 *   * an equation problem has a VERIFIED solution set. Legal algebra preserves
 *     it, so every intermediate line the student writes must still be satisfied
 *     by at least one verified root. The first line that isn't is the first line
 *     that went wrong.
 *   * an expression problem has no roots, but every legal line must stay EQUAL
 *     to the original as a function — `verifyEquality` decides that.
 *
 * The model is then told the verdict as a fact it may narrate but must not
 * override. When nothing here can be decided the status is `unknown`, and the
 * directive tells Numi to say so honestly rather than guess — an honest "I can
 * read your working but I couldn't check the numbers" beats a confident wrong
 * "line 3 is your mistake".
 *
 * Pure — no Firebase, no OpenAI — so the whole contract is unit-testable.
 */
import { latexToAscii, splitEquation, variablesIn } from "../solver/latex";
import {
  evalReal,
  unknownInDenominator,
  verifyEquality,
  verifySolution,
} from "../solver/verify";

/** How many transcribed lines we will look at. Longer working is truncated. */
export const MAX_WORK_LINES = 12;
/** Per-line character cap on the untrusted transcription. */
const MAX_LINE_LEN = 200;

export type WorkStatus = "ok" | "error" | "unknown";

export interface WorkCheck {
  status: WorkStatus;
  /** 1-based index of the first line that contradicts the verified problem. */
  firstErrorLine: number | null;
  /** The student's own text for that line, echoed back so Numi can quote it. */
  firstErrorLatex: string | null;
  /** How many lines we could actually decide on. */
  checkedCount: number;
  /** How many lines were transcribed (after truncation). */
  totalLines: number;
  /** Why the check couldn't run, when `status` is "unknown". */
  reason?: string;
}

/** A `{x: 4}`-style assignment of values to unknowns. */
type Assignment = Record<string, number>;

/**
 * Sampling grid for the spurious-root test below. Offset off the integers so a
 * whole-number root falls strictly BETWEEN two samples and shows up as a sign
 * change rather than landing on one.
 */
const ROOT_GRID_MIN = -12.125;
const ROOT_GRID_STEP = 0.25;
const ROOT_GRID_COUNT = 98;
/** More roots than this and the expression is too wiggly to reason about. */
const MAX_TRACKED_ROOTS = 8;
/**
 * How close two roots must be to count as the same one. Loose enough to match a
 * verified answer that was rounded to a few decimals, far tighter than the gap
 * between a real root and a spurious one.
 */
const ROOT_TOL = 1e-3;

/**
 * Every root of `residual` in the sampling window, found by sign change +
 * bisection. Returns `null` — "don't reason about this" — when too much of the
 * window is outside the domain or the expression has too many roots to track.
 *
 * Poles are rejected: `1/(x-2)` flips sign across x=2 without having a root
 * there, so a converged point whose residual isn't ~0 is discarded.
 */
function residualRoots(residual: string, unknown: string): number[] | null {
  const values: number[] = [];
  let undefinedPoints = 0;
  for (let i = 0; i < ROOT_GRID_COUNT; i++) {
    const v = evalReal(residual, {
      [unknown]: ROOT_GRID_MIN + i * ROOT_GRID_STEP,
    });
    if (!Number.isFinite(v)) undefinedPoints++;
    values.push(v);
  }
  if (undefinedPoints > ROOT_GRID_COUNT / 4) return null;

  const roots: number[] = [];
  for (let i = 0; i + 1 < ROOT_GRID_COUNT; i++) {
    const a = values[i];
    const b = values[i + 1];
    if (!Number.isFinite(a) || !Number.isFinite(b) || a * b >= 0) continue;

    let lo = ROOT_GRID_MIN + i * ROOT_GRID_STEP;
    let hi = lo + ROOT_GRID_STEP;
    let low = a;
    for (let k = 0; k < 60; k++) {
      const mid = (lo + hi) / 2;
      const fm = evalReal(residual, { [unknown]: mid });
      if (!Number.isFinite(fm)) break;
      if (fm === 0) {
        lo = mid;
        hi = mid;
        break;
      }
      if (low < 0 !== fm < 0) hi = mid;
      else {
        lo = mid;
        low = fm;
      }
    }
    const root = (lo + hi) / 2;
    const at = evalReal(residual, { [unknown]: root });
    if (!Number.isFinite(at) || Math.abs(at) > ROOT_TOL) continue; // a pole
    if (!roots.some((r) => Math.abs(r - root) <= ROOT_TOL)) roots.push(root);
    if (roots.length > MAX_TRACKED_ROOTS) return null;
  }
  return roots;
}

/** Whether every root in `found` is one of `expected`. */
function rootsWithin(found: number[], expected: number[]): boolean {
  return found.every((r) => expected.some((e) => Math.abs(r - e) <= ROOT_TOL));
}

/** Any multi-letter identifier applied to a bracket — i.e. a function call. */
const FUNCTION_CALL = /[a-zA-Z]{2,}\s*\(/;
/** A power that is a plain non-negative integer: `^2` or `^(2)`. */
const INTEGER_POWER = /\^\s*(?:\(\s*\d+\s*\)|\d+)/g;

/**
 * Whether an ascii expression is an ordinary polynomial in `unknown`.
 *
 * The gate on the spurious-root test below, and the reason it can't misfire on
 * the one case where introducing a root is LEGAL: squaring both sides of a
 * radical equation ($\sqrt{x+3} = x+1$ gains the extraneous $x = -2$). Radicals,
 * logs, trig, absolute values and unknowns in a denominator all disqualify —
 * and none of them can appear in a polynomial, where every legal move preserves
 * the root set exactly.
 */
function isPolynomialIn(ascii: string, unknown: string): boolean {
  if (FUNCTION_CALL.test(ascii)) return false;
  if (unknownInDenominator(ascii, unknown)) return false;
  const powers = ascii.match(/\^/g)?.length ?? 0;
  const integerPowers = [...ascii.matchAll(INTEGER_POWER)].length;
  return powers === integerPowers;
}

/**
 * A student's line may not introduce a root the original problem doesn't have.
 *
 * Catches the error the "does a verified root still satisfy this?" test can't:
 * a wrong factorisation like $(x-2)(x-3)=0$ for $x^2+x-6=0$ keeps the root
 * $x=2$, so it survives that test, but it invents the root $x=3$.
 *
 * Only runs when the verified answer is provably the COMPLETE root set — we
 * re-find the original's own roots and require them to match what the app
 * verified. That self-calibration is what makes it safe for equations whose
 * answer is only a principal solution ($\sin x = 0.5$ has infinitely many
 * roots): the sets won't match, so the test simply steps aside.
 *
 * Returns true only when the line is DEFINITELY divergent.
 */
function introducesSpuriousRoot(
  originalResidual: string,
  lineAscii: string,
  unknown: string,
  verified: number[]
): boolean {
  const line = splitEquation(lineAscii);
  if (!line.isEquation) return false;
  for (const v of variablesIn(lineAscii)) {
    if (v !== unknown) return false; // a different letter — not comparable.
  }
  const lineResidual = `(${line.lhs}) - (${line.rhs})`;

  // Both sides of the comparison must be plain polynomials — see [isPolynomialIn].
  if (!isPolynomialIn(originalResidual, unknown)) return false;
  if (!isPolynomialIn(lineResidual, unknown)) return false;

  const originalRoots = residualRoots(originalResidual, unknown);
  if (
    originalRoots === null ||
    originalRoots.length !== verified.length ||
    !rootsWithin(originalRoots, verified)
  ) {
    return false; // the verified set isn't provably complete — stand down.
  }

  const lineRoots = residualRoots(lineResidual, unknown);
  if (lineRoots === null || lineRoots.length === 0) return false;
  return !rootsWithin(lineRoots, verified);
}

/** Trim + cap one untrusted transcription line. */
function line(value: unknown): string {
  return typeof value === "string" ? value.trim().slice(0, MAX_LINE_LEN) : "";
}

/** Normalize the untrusted `studentWork` array into usable lines. */
export function normalizeWorkLines(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const out: string[] = [];
  for (const item of value) {
    const s = line(item);
    if (s) out.push(s);
    if (out.length >= MAX_WORK_LINES) break;
  }
  return out;
}

/**
 * Read the verified final answer as the solution set it describes.
 *
 * Handles the three shapes the solver emits: a single root (`x = 4`), several
 * roots of one unknown (`x = 2, x = -3` / `x = 2 \text{ or } x = -3`), and a
 * system (`x = -1, y = 3`). Anything else — a bare value, an interval, a set —
 * returns `[]`, which downgrades the whole check to `unknown` rather than
 * guessing at what the answer means.
 */
export function parseAssignments(finalAnswerLatex: string): Assignment[] {
  const raw = finalAnswerLatex.trim();
  if (!raw) return [];

  // `\text{ or }` / `\text{ and }` are separators, not math — the pieces on
  // either side are independent statements.
  const pieces = raw
    .replace(/\\text(?:rm|it|bf|sf|tt)?\s*\{[^{}]*\}/g, ",")
    .replace(/\\quad|\\qquad|\\;|\\,/g, ",")
    .split(/[,;]|\bor\b|\band\b/);

  const parsed: { name: string; value: number }[] = [];
  for (const piece of pieces) {
    if (!piece.trim()) continue;
    const eq = splitEquation(latexToAscii(piece));
    if (!eq.isEquation) return [];
    const name = eq.lhs.trim();
    // Only a bare unknown on the left is an assignment we understand.
    if (!/^[a-zA-Z]$/.test(name)) return [];
    const value = evalReal(eq.rhs);
    if (!Number.isFinite(value)) return [];
    parsed.push({ name, value });
  }
  if (parsed.length === 0) return [];

  const names = new Set(parsed.map((p) => p.name));
  if (names.size === 1) {
    // Alternative roots of one unknown — each is a solution on its own.
    return parsed.map((p) => ({ [p.name]: p.value }));
  }
  if (names.size === parsed.length) {
    // A system — one assignment naming every unknown at once.
    const system: Assignment = {};
    for (const p of parsed) system[p.name] = p.value;
    return [system];
  }
  // Mixed (repeated AND distinct names) — ambiguous. Decline rather than guess.
  return [];
}

/**
 * Whether a student's line is consistent with the verified solution set.
 *
 * A ONE-SIDED test, deliberately: legal algebra can shrink the solution set
 * (dividing through by a factor) but never makes every verified root fail at
 * once, so "no verified root satisfies this line" is solid evidence of a real
 * slip, while "some root satisfies it" is not proof of correctness. We only ever
 * report the first *definite* error, and stay silent otherwise.
 *
 * Returns `null` when the line can't be decided (unparseable, mentions unknowns
 * the answer doesn't, or evaluates to nothing real at every assignment).
 */
function equationLineConsistent(
  ascii: string,
  assignments: Assignment[]
): boolean | null {
  const eq = splitEquation(ascii);
  if (!eq.isEquation || !eq.lhs || !eq.rhs) return null;

  const known = new Set(Object.keys(assignments[0] ?? {}));
  for (const v of variablesIn(ascii)) {
    if (!known.has(v)) return null; // a free unknown — nothing to substitute.
  }

  let decidable = false;
  for (const assignment of assignments) {
    const l = evalReal(eq.lhs, assignment);
    const r = evalReal(eq.rhs, assignment);
    if (!Number.isFinite(l) || !Number.isFinite(r)) continue;
    decidable = true;
    if (verifySolution([{ lhs: eq.lhs, rhs: eq.rhs }], assignment)) return true;
  }
  return decidable ? false : null;
}

/**
 * Whether a line of working on an EXPRESSION problem still equals the original.
 *
 * Each side of the student's line must be the same function as the original
 * expression. Returns `null` when neither side can be compared.
 */
function expressionLineConsistent(
  ascii: string,
  originalExpr: string
): boolean | null {
  const eq = splitEquation(ascii);
  const sides = eq.isEquation ? [eq.lhs, eq.rhs] : [eq.lhs];
  const vars = new Set([...variablesIn(originalExpr)]);
  let decidable = false;
  for (const side of sides) {
    if (!side.trim()) continue;
    for (const v of variablesIn(side)) {
      if (!vars.has(v)) return null; // introduces an unknown — can't compare.
    }
    decidable = true;
    if (!verifyEquality(originalExpr, side, [...vars])) return false;
  }
  return decidable ? true : null;
}

/**
 * Check a student's transcribed working against the verified problem.
 *
 * [problemLatex] and [finalAnswerLatex] come from the app's own verified solve —
 * never from the model — so a verdict here is as trustworthy as the answer the
 * app already stands behind.
 */
export function checkStudentWork(
  problemLatex: string,
  finalAnswerLatex: string,
  lines: string[]
): WorkCheck {
  const totalLines = lines.length;
  const empty: WorkCheck = {
    status: "unknown",
    firstErrorLine: null,
    firstErrorLatex: null,
    checkedCount: 0,
    totalLines,
  };
  if (totalLines === 0) return { ...empty, reason: "no working was transcribed" };

  const originalAscii = latexToAscii(problemLatex);
  if (!originalAscii.trim()) {
    return { ...empty, reason: "the original problem could not be read" };
  }
  const original = splitEquation(originalAscii);
  const assignments = original.isEquation
    ? parseAssignments(finalAnswerLatex)
    : [];

  if (original.isEquation && assignments.length === 0) {
    return { ...empty, reason: "there is no verified answer to check against" };
  }

  // The spurious-root test only makes sense for one unknown solved to a set of
  // plain values — i.e. every assignment names the same single letter.
  const names = new Set(assignments.flatMap((a) => Object.keys(a)));
  const singleUnknown =
    names.size === 1 && assignments.every((a) => Object.keys(a).length === 1)
      ? [...names][0]
      : null;
  const verifiedValues = singleUnknown
    ? assignments.map((a) => a[singleUnknown])
    : [];
  const originalResidual = `(${original.lhs}) - (${original.rhs})`;

  let checkedCount = 0;
  for (let i = 0; i < lines.length; i++) {
    const ascii = latexToAscii(lines[i]);
    if (!ascii.trim()) continue;
    let verdict: boolean | null;
    if (original.isEquation) {
      verdict = equationLineConsistent(ascii, assignments);
      // A line can satisfy one verified root and still be wrong — a mis-signed
      // factorisation keeps a root while inventing another. Catch that too.
      if (
        verdict !== false &&
        singleUnknown &&
        introducesSpuriousRoot(originalResidual, ascii, singleUnknown, verifiedValues)
      ) {
        verdict = false;
      }
    } else {
      verdict = expressionLineConsistent(ascii, original.lhs);
    }
    if (verdict === null) continue;
    checkedCount++;
    if (!verdict) {
      return {
        status: "error",
        firstErrorLine: i + 1,
        firstErrorLatex: lines[i],
        checkedCount,
        totalLines,
      };
    }
  }

  if (checkedCount === 0) {
    return { ...empty, reason: "none of the lines could be checked numerically" };
  }
  return {
    status: "ok",
    firstErrorLine: null,
    firstErrorLatex: null,
    checkedCount,
    totalLines,
  };
}

/**
 * Render the student's working plus the app's verdict as a system turn.
 *
 * The wording matters: the verdict is presented as something the APP computed
 * and Numi may not overrule, and the `unknown` branch explicitly forbids
 * asserting a line is right or wrong. That is what keeps a critique honest when
 * the deterministic check couldn't run.
 */
export function buildWorkContext(lines: string[], check: WorkCheck): string {
  if (lines.length === 0) return "";
  const out: string[] = [
    "THE STUDENT PHOTOGRAPHED THEIR OWN WORKING. This is what they wrote, line by line, exactly as transcribed:",
  ];
  lines.forEach((l, i) => out.push(`  Line ${i + 1}: ${l}`));

  out.push(
    "",
    "The transcription may contain OCR slips. If a line looks garbled rather than wrong, say so and ask them to check that line, rather than calling it a mistake."
  );

  switch (check.status) {
    case "error":
      out.push(
        "",
        `APP VERDICT (computed by Matheasy's verifier, NOT by you — state it, do not re-derive it or overrule it): line ${check.firstErrorLine} is the FIRST line that no longer agrees with the verified problem. Everything before it is consistent.`,
        `The line in question: ${check.firstErrorLatex}`,
        "",
        "Teach from that: name what they did RIGHT up to that point first, then point at line " +
          `${check.firstErrorLine} and help them see what slipped there. Do not list every later line as wrong — one error cascades, and the rest is usually correct work on a wrong number.`
      );
      break;
    case "ok":
      out.push(
        "",
        `APP VERDICT (computed by Matheasy's verifier, NOT by you): every line it could check (${check.checkedCount} of ${check.totalLines}) agrees with the verified problem. No arithmetic error was found.`,
        "Tell them their working holds up, and be specific about what was well done rather than just saying 'correct'. If some lines could not be checked, do not claim the whole thing is right — say what was checked."
      );
      break;
    case "unknown":
      out.push(
        "",
        `APP VERDICT: Matheasy could NOT check this working (${check.reason ?? "the lines could not be evaluated"}).`,
        "So you must NOT say any line is right or wrong, and must NOT invent a check. Say honestly that you can read their working but couldn't verify the numbers, comment on their METHOD and what you notice about the approach, and ask them what they got so you can talk it through together."
      );
      break;
  }
  return out.join("\n");
}
