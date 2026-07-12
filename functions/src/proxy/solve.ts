/**
 * `solveEquation` — the deterministic solver proxy (spec §1, §1.1, §4).
 *
 * The golden rule: the LLM never invents arithmetic. The answer is computed by a
 * symbolic engine (mathsteps + mathjs), substituted back into the ORIGINAL
 * problem to verify, and only then returned. When engines can't solve a problem,
 * a constrained LLM proposes a CANDIDATE that must still pass the same
 * verification gate — otherwise we return a `verified:false` "couldn't verify"
 * state, never a confident wrong answer.
 *
 * Returns EXACTLY the §4 schema (plus an out-of-band `usage` field the app's
 * quota meter reads, matching the existing recognize/solve contract). Downstream
 * of `recognizeEquation`, so by default it does NOT charge a scan again — pass
 * `countAsScan: true` for the manual-entry path so it still meters.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { fraction } from "mathjs";

import { OPENAI_API_KEY, OPENAI_MODEL } from "../config";
import { requireUid } from "../lib/auth";
import {
  assertWithinQuota,
  ensureUserDoc,
  incrementUsage,
} from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import { getCachedSolve, putCachedSolve } from "../lib/solveCache";
import { chatJson, createOpenAI } from "../lib/openai";

import { classify, equationParts } from "../solver/classify";
import { solveDeterministic } from "../solver/deterministic";
import { exactForm } from "../solver/exact";
import { buildGraph, GraphInput } from "../solver/graph";
import { variablesIn } from "../solver/latex";
import {
  assembleMethods,
  generateLlmCandidate,
  JsonCompleter,
  LlmCandidate,
  narrateDeterministic,
} from "../solver/narrate";
import {
  Classification,
  FinalAnswer,
  MethodData,
  SolvePayload,
} from "../solver/types";
import {
  closeEnough,
  countSignChangeRoots,
  evalReal,
  numericIntegrate,
  stripIntegrationConstant,
  unknownInDenominator,
  verifyDerivative,
  verifyEquality,
  verifyRoots,
  verifySolution,
} from "../solver/verify";

interface SolveRequest {
  latex?: string;
  countAsScan?: boolean;
}

/** A `verified:false` payload — an honest "couldn't verify", never a guess. */
function couldNotVerify(cls: Classification): SolvePayload {
  return {
    problemLatex: cls.latex,
    problemType: cls.problemType,
    finalAnswer: null,
    verified: false,
    methods: [],
    graph: null,
  };
}

export const solveEquation = onCall(
  { secrets: [OPENAI_API_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const { latex, countAsScan = false } = (request.data ?? {}) as SolveRequest;

    if (!latex || typeof latex !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "latex (the problem to solve) is required."
      );
    }

    await ensureUserDoc(uid);
    // Rate limit BEFORE the paid path, for EVERY user — this is what caps the
    // otherwise-uncapped `countAsScan:false` path (a scan already metered, but
    // the LLM narration call still costs money) and any retry loop (spec §10).
    await assertWithinRateLimit(uid, "solve");
    if (countAsScan) {
      await assertWithinQuota(uid, "scans");
    }

    // Server result cache (spec §10): a repeat of an already-solved problem
    // returns the VERIFIED payload with no LLM call. Collision-safe key, so a
    // hit is always the same problem; we swap in the caller's own rendering of
    // the problem LaTeX for display.
    const cached = await getCachedSolve(latex);
    let payload: SolvePayload;
    if (cached) {
      payload = { ...cached, problemLatex: latex };
    } else {
      const cls = classify(latex);
      const complete: JsonCompleter = (system, user, maxTokens) => {
        const client = createOpenAI(OPENAI_API_KEY.value());
        return chatJson<Record<string, unknown>>(
          client,
          OPENAI_MODEL.value(),
          system,
          user,
          { temperature: 0.2, maxTokens }
        );
      };

      try {
        payload = await solve(cls, complete);
      } catch (err) {
        logger.error("solveEquation failed", { uid, err: String(err) });
        throw new HttpsError(
          "internal",
          "Matheasy couldn't solve that one. Please try again."
        );
      }
      // Cache verified answers only (putCachedSolve no-ops on couldn't-verify).
      await putCachedSolve(latex, payload);
    }

    // Meter ONLY the manual-entry path (a scan already paid for OCR-sourced
    // problems). We charge whether or not the answer verified, and whether or
    // not it was a cache hit: the user's allowance tracks solves they ask for.
    const quota = countAsScan ? await incrementUsage(uid, "scans") : null;

    return { ...payload, usage: quota };
  }
);

/** The pure solve pipeline — testable without Firebase. */
export async function solve(
  cls: Classification,
  complete: JsonCompleter
): Promise<SolvePayload> {
  // 1) Deterministic engine, gated by the verifier.
  const candidate = solveDeterministic(cls);
  if (candidate && candidate.verify()) {
    const narration = await narrateDeterministic(complete, cls, candidate.methods);
    const methods = assembleMethods(candidate.methods, narration);
    const graph = buildGraph({
      plotExpression: candidate.plotExpression,
      roots: candidate.roots,
      quadratic: candidate.quadratic,
    });
    return {
      problemLatex: cls.latex,
      problemType: cls.problemType,
      finalAnswer: candidate.answer,
      verified: true,
      methods,
      graph,
    };
  }

  // 2) Constrained LLM candidate — still must pass the verification gate.
  if (cls.verifyMode === "none") return couldNotVerify(cls);

  const llm = await generateLlmCandidate(complete, cls);
  if (!llm) return couldNotVerify(cls);

  const outcome = verifyCandidate(cls, llm);
  if (!outcome.ok) return couldNotVerify(cls);

  return {
    problemLatex: cls.latex,
    problemType: cls.problemType,
    finalAnswer: outcome.answer,
    verified: true,
    methods: ensureMethods(llm, outcome.answer),
    graph: llmGraph(cls, llm),
  };
}

type VerifyOutcome = { ok: true; answer: FinalAnswer } | { ok: false };

/**
 * Prove an LLM candidate against the ORIGINAL problem per its verify mode.
 *
 * `substitution` mode returns an answer BUILT FROM the verified numeric
 * solutions — never the model's free-text `answerLatex` — so the answer the
 * student sees (and that we label "checked ✓") is provably the one substituted
 * back. `equality`/`derivative_back` verify the displayed answer itself
 * (`answerAscii`), so they return it directly.
 */
function verifyCandidate(cls: Classification, llm: LlmCandidate): VerifyOutcome {
  switch (cls.verifyMode) {
    case "substitution": {
      const parts = equationParts(cls.ascii);
      if (parts.length === 0 || llm.assignments.length === 0) {
        return { ok: false };
      }
      const byVar = new Map<string, number[]>();
      for (const a of llm.assignments) {
        const list = byVar.get(a.variable) ?? [];
        list.push(a.value);
        byVar.set(a.variable, list);
      }

      if (byVar.size === 1) {
        const [variable, raw] = [...byVar.entries()][0];
        const values = distinct(raw);
        if (!verifyRoots(parts, variable, values)) return { ok: false };
        // Completeness: a candidate that omits real roots of a polynomial is an
        // incomplete (wrong) answer. Require at least as many distinct roots as
        // the equation demonstrably has (a sign-change lower bound). Only valid
        // for genuine polynomials — a pole would inject phantom sign changes, so
        // skip when the unknown sits in a denominator.
        if (
          parts.length === 1 &&
          (cls.problemType === "polynomial_equation" ||
            cls.problemType === "quadratic_equation") &&
          !unknownInDenominator(
            `(${parts[0].lhs}) - (${parts[0].rhs})`,
            variable
          )
        ) {
          if (values.length < countSignChangeRoots(parts[0], variable)) {
            return { ok: false };
          }
        }
        return { ok: true, answer: rootsAnswer(variable, values) };
      }

      // System: one verified value per variable satisfying every equation.
      const scope: Record<string, number> = {};
      for (const [v, values] of byVar) scope[v] = values[0];
      if (!verifySolution(parts, scope)) return { ok: false };
      return { ok: true, answer: systemAnswer(scope) };
    }
    case "equality":
      return verifyEquality(cls.ascii, llm.answerAscii, variablesIn(cls.ascii))
        ? { ok: true, answer: llm.answer }
        : { ok: false };
    case "derivative_back": {
      // The antiderivative is correct iff d/dx(answer) equals the integrand:
      // target = the candidate antiderivative, expected = the integrand.
      const integrand = cls.integrand;
      if (!integrand) return { ok: false };
      return verifyDerivative(
        stripIntegrationConstant(llm.answerAscii),
        integrand,
        cls.unknown
      )
        ? { ok: true, answer: llm.answer }
        : { ok: false };
    }
    case "definite_integral": {
      // Deterministic numeric integration is the source of truth; the candidate
      // value must agree with it (guards both a misparse and an LLM error).
      const { integrand, lowerBound, upperBound } = cls;
      if (!integrand || lowerBound === undefined || upperBound === undefined) {
        return { ok: false };
      }
      const value = numericIntegrate(integrand, cls.unknown, lowerBound, upperBound);
      if (Number.isNaN(value)) return { ok: false };
      const candidate = evalReal(llm.answerAscii);
      if (Number.isNaN(candidate) || !closeEnough(candidate, value)) {
        return { ok: false };
      }
      return { ok: true, answer: llm.answer };
    }
    case "trig": {
      // Verify each principal solution AND that ±2π also satisfy (periodicity),
      // then DISPLAY a general form built from OUR verified values — never the
      // model's free-text general solution.
      const parts = equationParts(cls.ascii);
      if (parts.length === 0 || llm.assignments.length === 0) return { ok: false };
      const TWO_PI = 2 * Math.PI;
      const principals: number[] = [];
      for (const a of llm.assignments) {
        const satisfies =
          verifySolution(parts, { [a.variable]: a.value }) &&
          verifySolution(parts, { [a.variable]: a.value + TWO_PI }) &&
          verifySolution(parts, { [a.variable]: a.value - TWO_PI });
        if (!satisfies) return { ok: false };
        principals.push(a.value);
      }
      return { ok: true, answer: trigAnswer(cls.unknown, distinct(principals)) };
    }
    default:
      return { ok: false };
  }
}

/** Build "x = π/6 + 2πn, x = 5π/6 + 2πn" from verified principal values. */
function trigAnswer(variable: string, principals: number[]): FinalAnswer {
  const parts = principals.map((v) => {
    const p = prettyRadian(v);
    return {
      latex: `${variable} = ${p.latex} + 2\\pi n`,
      plain: `${variable} = ${p.plain} + 2πn`,
    };
  });
  return {
    latex: parts.map((p) => p.latex).join(",\\; "),
    plain: parts.map((p) => p.plain).join(", "),
  };
}

/** Render a radian value as a multiple of π/12 when recognizable, else decimal. */
function prettyRadian(v: number): { latex: string; plain: string } {
  const unit = Math.PI / 12;
  const k = Math.round(v / unit);
  if (k !== 0 && Math.abs(v - k * unit) < 3e-3) return piFraction(k);
  if (Math.abs(v) < 1e-9) return { latex: "0", plain: "0" };
  const s = String(Number(v.toFixed(4)));
  return { latex: s, plain: s };
}

/** Simplify k/12 and render `kπ/12` as a nice π-fraction. */
function piFraction(k: number): { latex: string; plain: string } {
  const gcd = (a: number, b: number): number => (b === 0 ? a : gcd(b, a % b));
  const g = gcd(Math.abs(k), 12);
  const n = Math.abs(k) / g;
  const d = 12 / g;
  const sign = k < 0 ? "-" : "";
  if (d === 1) {
    return n === 1
      ? { latex: `${sign}\\pi`, plain: `${sign}π` }
      : { latex: `${sign}${n}\\pi`, plain: `${sign}${n}π` };
  }
  const numTex = n === 1 ? "\\pi" : `${n}\\pi`;
  const numPlain = n === 1 ? "π" : `${n}π`;
  return {
    latex: `${sign}\\frac{${numTex}}{${d}}`,
    plain: `${sign}${numPlain}/${d}`,
  };
}

/** Dedupe near-equal values and sort ascending. */
function distinct(values: number[]): number[] {
  const out: number[] = [];
  for (const v of values) {
    if (!out.some((x) => Math.abs(x - v) < 1e-9)) out.push(v);
  }
  return out.sort((a, b) => a - b);
}

/** A §4 answer for a single variable, built from verified numeric root(s). */
function rootsAnswer(variable: string, values: number[]): FinalAnswer {
  if (values.length === 1) {
    const f = formatValue(values[0]);
    return { latex: `${variable} = ${f.latex}`, plain: `${variable} = ${f.plain}` };
  }
  return {
    latex: values
      .map((v, i) => `${variable}_${i + 1} = ${formatValue(v).latex}`)
      .join(",\\; "),
    plain: values.map((v) => `${variable} = ${formatValue(v).plain}`).join(" or "),
  };
}

/** A §4 answer for a system, built from verified variable→value assignments. */
function systemAnswer(scope: Record<string, number>): FinalAnswer {
  const entries = Object.entries(scope);
  return {
    latex: entries.map(([v, n]) => `${v} = ${formatValue(n).latex}`).join(",\\; "),
    plain: entries.map(([v, n]) => `${v} = ${formatValue(n).plain}`).join(", "),
  };
}

/** Present a verified numeric value as an integer, exact irrational, small
 * fraction, or decimal. The exact-form recognition is DISPLAY only — the value
 * was already verified numerically by substitution (the gate is untouched). */
function formatValue(n: number): FinalAnswer {
  if (Number.isInteger(n)) return { latex: String(n), plain: String(n) };
  // Irrational roots (x²−2=0 → x = ±√2) — show the exact form, never a decimal.
  const exact = exactForm(n);
  if (exact) return { latex: exact.latex, plain: exact.plain };
  const rounded = Number(n.toFixed(6));
  try {
    const fr = fraction(rounded) as unknown as { n: bigint; d: bigint; s: number };
    const num = Number(fr.n);
    const den = Number(fr.d);
    if (den !== 1 && den <= 1000) {
      const sign = fr.s < 0 ? "-" : "";
      return { latex: `${sign}\\tfrac{${num}}{${den}}`, plain: `${sign}${num}/${den}` };
    }
  } catch {
    /* fall through to decimal */
  }
  return { latex: String(rounded), plain: String(rounded) };
}

/** Never return a verified answer with zero methods; uses the VERIFIED answer. */
function ensureMethods(llm: LlmCandidate, answer: FinalAnswer): MethodData[] {
  if (llm.methods.length) return llm.methods;
  return [
    {
      id: "solution",
      name: "Solution",
      examPick: true,
      steps: [{ expression: answer.latex, operation: "Answer", why: "" }],
    },
  ];
}

/** Graph an LLM-solved single-variable equation from its verified roots. */
function llmGraph(cls: Classification, llm: LlmCandidate) {
  if (!cls.isEquation) return null;
  const parts = equationParts(cls.ascii);
  if (parts.length !== 1) return null;
  const vars = variablesIn(cls.ascii);
  if (vars.length !== 1) return null;
  const variable = vars[0];
  const roots = llm.assignments
    .filter((a) => a.variable === variable)
    .map((a) => a.value);
  if (roots.length === 0) return null;
  const rhs = parts[0].rhs.trim() === "0" ? "" : ` - (${parts[0].rhs})`;
  const input: GraphInput = {
    plotExpression: `(${parts[0].lhs})${rhs}`,
    roots,
  };
  return buildGraph(input);
}
