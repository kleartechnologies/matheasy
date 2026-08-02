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
import type { MsStep } from "mathsteps";

import {
  OPENAI_API_KEY,
  REVENUECAT_SECRET_KEY,
  animationSchemaEnabled,
} from "../config";
import { requireUid } from "../lib/auth";
import {
  assertWithinQuota,
  ensureUserDoc,
  incrementUsage,
  recordSolveFailure,
} from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import { getCachedSolve, putCachedSolve } from "../lib/solveCache";
import { chatJson, createOpenAI } from "../lib/openai";
import { languageDirective } from "../lib/language";

// Namespace import (not destructured) so the call site stays a runtime property
// access — this is what lets the wiring test spy on buildAnimationSchema to prove
// a thrown animation can never break a verified solve.
import * as animation from "../solver/animationSchema";
import { classify, equationParts } from "../solver/classify";
import { solveDeterministic } from "../solver/deterministic";
import { evaluateLimit } from "../solver/limit";
import { solveBoundedTrig } from "../solver/boundedTrig";
import { solveCircle } from "../solver/circle";
import { solveOdePointEval } from "../solver/odePointEval";
import { odeAnswer, verifyOde } from "../solver/ode";
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
  SOLVE_SCHEMA_VERSION,
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
  verifyInequality,
  verifyRoots,
  verifySolution,
} from "../solver/verify";

/**
 * HELD ENGINES — two numeric-sampling oracles, committed but DISABLED.
 *
 * The circle and bounded-trig engines are CLOSED-FORM / substitution-verified: an
 * exact formula whose rendered coefficient is re-checked against an independent
 * recompute, or enumerated roots each re-substituted into the original equation.
 * Their proof is EXACT, so they ship.
 *
 * The limit and ODE-point-eval engines are different in kind: each PROVES its answer
 * only by numeric SAMPLING (a convergence oracle; two independent integrators that
 * must agree). A sampling oracle cannot be proven golden-rule-clean against a
 * code-reading adversary, because a feature narrower than the sample spacing is
 * invisible to it — and both the offending function AND the verifier that samples it
 * inherit the same blind spot:
 *   • LIMIT — an additive offset hides below the ill-conditioning noise floor, a
 *     sign-flip sits beyond any finite reach (a confirmed case flips at x≈1e5000, past
 *     `double`), a log-periodic function aliases the deterministic lattice. Gates
 *     R1…R9 each surfaced fresh violations of these kinds — it never converged clean.
 *   • ODE POINT-EVAL — two integrators that step over the SAME sub-grid spike agree on
 *     a value that misses it (a confirmed case: y′ = 5.64e6·e^{−1e14(x−c)²} integrates
 *     to 0, true ≈ 1). To GUARANTEE catching a width-w spike a fixed grid needs spacing
 *     < w, but the adversary picks w below any fixed grid and encodes the narrowness in
 *     small literals (…/1e−11) or products that defeat any magnitude cap — it is
 *     information-theoretically irreducible for a black-box sampler. Gate round 3 closed
 *     the parse/linearity holes (symbolic-point over-determination via a broadened
 *     clause counter; product-of-sines nonlinearity via a SYMBOLIC affine-in-top-
 *     derivative check that no sampling lattice can dodge), but this spike class stands.
 *
 * Decision (2026-07-27): ship the two closed-form engines (circle, bounded-trig) and
 * HOLD both samplers, each to be revisited as its own scoped project (narrowed to a
 * subset it can verify EXACTLY — e.g. interval arithmetic, or a closed-form subclass).
 * Flipping a flag to `true` re-enables that engine's routing below; every engine and
 * its tests remain committed and intact meanwhile. While held, a `\lim` or an ODE IVP
 * point-eval is an honest couldn't-verify — it never falls through to the LLM tier.
 */
export const LIMIT_ENGINE_ENABLED = false;
export const ODE_POINTEVAL_ENABLED = false;

interface SolveRequest {
  latex?: string;
  countAsScan?: boolean;
  /** BCP-47 language the step narration must be written in (math stays universal). */
  language?: string;
}

/** A `verified:false` payload — an honest "couldn't verify", never a guess. */
function couldNotVerify(
  cls: Classification,
  reason: string,
  onFail?: (reason: string) => void
): SolvePayload {
  // Observability: record WHICH branch declined, so in production an honest
  // refusal is distinguishable from an OpenAI outage or a rejected candidate
  // (they otherwise all surface as the same "couldn't solve" to the user).
  logger.info("solve.couldNotVerify", {
    reason,
    problemType: cls.problemType,
    strategy: cls.strategy,
    verifyMode: cls.verifyMode,
  });
  onFail?.(reason); // persist to the failure-analytics store (wrapper-provided)
  return {
    problemLatex: cls.latex,
    problemType: cls.problemType,
    finalAnswer: null,
    verified: false,
    methods: [],
    graph: null,
  };
}

/**
 * Attach the OPTIONAL animation sidecar to an ALREADY-verified payload. Runs on
 * the fresh-solve path only, AFTER the solve is complete. STRICTLY ADDITIVE and
 * STRICTLY NON-LOAD-BEARING: a no-op unless the flag is ON and the mathsteps path
 * produced real equation steps, and ANY throw — including the module's golden-rule
 * firewall — is caught and logged so the verified solve returns normally. A broken
 * animation must never turn a correct verified solve into an error.
 */
function attachAnimationSchema(payload: SolvePayload, steps?: MsStep[]): void {
  if (!animationSchemaEnabled() || !steps || steps.length === 0) return;
  try {
    const schema = animation.buildAnimationSchema(steps);
    if (schema.length > 0) payload.animationSchema = schema;
  } catch (err) {
    logger.warn("animationSchema build failed — omitting the additive sidecar", {
      problemType: payload.problemType,
      err: String(err),
    });
  }
}

/**
 * Finalize the animation sidecar on an OUTGOING payload (egress), given the flag.
 * The rollback is asymmetric BY DESIGN:
 *   • flag OFF → actively STRIP any `animationSchema`, even one a cache entry still
 *     carries from when the flag was ON — so OFF is a true no-op with zero behavior
 *     change vs today.
 *   • flag ON → do NOTHING here: no cache backfill. The field is whatever the
 *     payload already carries (from the fresh-solve build, or a cache hit). A
 *     pre-feature cache entry stays scheme-less until it naturally expires and
 *     re-solves — the cache-HIT path never re-solves or builds a schema.
 * Pure + synchronous, so it's unit-testable without Firebase.
 */
export function finalizeAnimationSidecar(payload: SolvePayload, enabled: boolean): void {
  if (!enabled && payload.animationSchema !== undefined) {
    delete payload.animationSchema;
  }
}

export const solveEquation = onCall(
  { secrets: [OPENAI_API_KEY, REVENUECAT_SECRET_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const { latex, countAsScan = false, language } = (request.data ??
      {}) as SolveRequest;

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
    const cached = await getCachedSolve(latex, language);
    let payload: SolvePayload;
    if (cached) {
      payload = { ...cached, problemLatex: latex };
    } else {
      const cls = classify(latex);
      // OpenAI JSON completer for the solve narration + any LLM-candidate solve.
      // Only the fresh-solve branch calls OpenAI (a cache hit does not), so it's
      // allocated here — teaching moved to its own `enrichTeaching` callable.
      const complete: JsonCompleter = (system, user, maxTokens, attempt) => {
        const client = createOpenAI(OPENAI_API_KEY.value());
        return chatJson<Record<string, unknown>>(
          client,
          // A retry only happens after the verification gate REJECTED the first
          // candidate, so that problem has already proven to need more thinking
          // than the default effort gave it. `solveRetry` escalates to maximum
          // effort (and the token headroom to match).
          attempt === "retry" ? "solveRetry" : "solve",
          // Narrate the steps in the learner's language (math stays universal).
          system + languageDirective(language),
          user,
          { temperature: 0.2, maxTokens }
        );
      };
      try {
        payload = await solve(cls, complete, (reason) => {
          // Fire-and-forget: turn every unverified solve into analytics data
          // (recordSolveFailure swallows its own errors + never blocks).
          void recordSolveFailure({
            latex: cls.latex,
            problemType: cls.problemType,
            strategy: cls.strategy,
            verifyMode: cls.verifyMode,
            reason,
          });
        });
      } catch (err) {
        logger.error("solveEquation failed", { uid, err: String(err) });
        throw new HttpsError(
          "internal",
          "Matheasy couldn't solve that one. Please try again."
        );
      }
      // Cache verified answers only (putCachedSolve no-ops on couldn't-verify).
      await putCachedSolve(latex, payload, language);
    }

    // Animation sidecar egress (asymmetric kill switch): OFF strips any schema —
    // even one a cache entry carries from when the flag was ON — so OFF is a true
    // no-op; ON leaves whatever the payload already has (fresh-built or cached),
    // with NO backfill on the cache-hit path.
    finalizeAnimationSidecar(payload, animationSchemaEnabled());

    // Meter ONLY the manual-entry path (a scan already paid for OCR-sourced
    // problems). We charge whether or not the answer verified, and whether or
    // not it was a cache hit: the user's allowance tracks solves they ask for.
    const quota = countAsScan ? await incrementUsage(uid, "scans") : null;

    // Stamp the wire schema version on egress (spec §2.3) — TELEMETRY ONLY, never a
    // client render gate. The v2 teaching layer is fetched SEPARATELY by the client
    // (the `enrichTeaching` callable) so solving stays instant — this fast response
    // carries no teaching; the client loads it progressively.
    return { ...payload, schemaVersion: SOLVE_SCHEMA_VERSION, usage: quota };
  }
);

/**
 * The pure solve pipeline — testable without Firebase. [onCouldNotVerify] is
 * invoked (with the failing branch's reason) whenever the result is
 * `verified:false`, so the caller can persist it for the failure analytics.
 */
export async function solve(
  cls: Classification,
  complete: JsonCompleter,
  onCouldNotVerify?: (reason: string) => void
): Promise<SolvePayload> {
  // 0) A proof / abstract-algebra / analysis prompt: there's nothing to compute
  // and substitution-verify. Hand it to the tutor instead of faking an answer.
  // The HONEST problemType rides along ("conceptual", "multi_part",
  // "system_of_equations") so the client can say what the problem actually is
  // — a solvable-looking system must not be presented as "a proof".
  if (cls.strategy === "conceptual") {
    return {
      problemLatex: cls.latex,
      problemType: cls.problemType,
      finalAnswer: null,
      verified: false,
      methods: [],
      graph: null,
      routeToTutor: true,
    };
  }

  // 0b) Limit — a deterministic numeric-convergence oracle (no LLM). Returns a
  // verified value, or an honest couldn't-verify when it diverges / oscillates /
  // the two sides disagree. Placed before the algebra engine so `\lim` never
  // falls through to a mis-parse.
  if (cls.strategy === "limit") {
    // HELD: while LIMIT_ENGINE_ENABLED is false the oracle is bypassed and every
    // `\lim` is an honest couldn't-verify (see the flag's note above). It stays a
    // terminal decline here — a `\lim` never falls through to the LLM tier.
    const result = LIMIT_ENGINE_ENABLED ? evaluateLimit(cls) : null;
    if (!result) return couldNotVerify(cls, "limit_no_converge", onCouldNotVerify);
    return {
      problemLatex: cls.latex,
      problemType: cls.problemType,
      finalAnswer: result.answer,
      verified: true,
      methods: result.methods,
      graph: null,
    };
  }

  if (cls.strategy === "bounded_trig") {
    // The enumerate-and-verify IS the proof: every root is re-substituted into
    // the original equation, so a null means empty/inconsistent → decline.
    const result = cls.boundedTrig ? solveBoundedTrig(cls.boundedTrig) : null;
    if (!result) return couldNotVerify(cls, "bounded_trig_no_solution", onCouldNotVerify);
    return {
      problemLatex: cls.latex,
      problemType: cls.problemType,
      finalAnswer: result.answer,
      verified: true,
      methods: result.methods,
      graph: null,
    };
  }

  // Circle mensuration — an exact closed-form answer. solveCircle re-checks the
  // rendered π-coefficient against an independent numeric recompute INTERNALLY and
  // returns null if it disagrees, so a null here is an honest couldn't-verify.
  if (cls.strategy === "circle") {
    const result = cls.circle ? solveCircle(cls.circle) : null;
    if (!result) return couldNotVerify(cls, "circle_no_verify", onCouldNotVerify);
    return {
      problemLatex: cls.latex,
      problemType: cls.problemType,
      finalAnswer: result.answer,
      verified: true,
      methods: result.methods,
      graph: null,
    };
  }

  // ODE initial-value point evaluation — two independent integrators (RK4+Richardson
  // and DP5) must converge AND agree, else null. That cross-check IS the proof, so a
  // null here is an honest couldn't-verify (divergence / stiffness / a singularity on
  // the path / an underdetermined or boundary-value problem).
  if (cls.strategy === "ode_point_eval") {
    // HELD: while ODE_POINTEVAL_ENABLED is false the integrators are bypassed and every
    // ODE IVP point-eval is an honest couldn't-verify (see the flag's note above — the
    // sub-grid-spike hole is irreducible for a numeric sampler). It stays a terminal
    // decline here: an ODE point-eval never falls through to the LLM tier.
    const result =
      ODE_POINTEVAL_ENABLED && cls.odePointEval ? solveOdePointEval(cls.odePointEval) : null;
    if (!result) return couldNotVerify(cls, "ode_point_eval_no_verify", onCouldNotVerify);
    return {
      problemLatex: cls.latex,
      problemType: cls.problemType,
      finalAnswer: result.answer,
      verified: true,
      methods: result.methods,
      graph: null,
    };
  }

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
    const payload: SolvePayload = {
      problemLatex: cls.latex,
      problemType: cls.problemType,
      finalAnswer: candidate.answer,
      verified: true,
      methods,
      graph,
    };
    // Additive sidecar over the now-complete verified payload (flag-gated, wrapped
    // so a failure can never break the solve). Runs BEFORE the caller caches the
    // payload, so a fresh solve caches the schema WITH it.
    attachAnimationSchema(payload, candidate.steps);
    return payload;
  }

  // 1b) A simultaneous system the engine could NOT complete (composition not
  // degree ≤ 2, a pole at a probe, no real intersection) is still a SYSTEM —
  // before this strategy existed these inputs classified as
  // system_of_equations → tutor, and that invite remains the honest outcome.
  // A bare couldn't-verify here would regress the UX the tutor route fixed.
  if (cls.strategy === "simultaneous") {
    return {
      problemLatex: cls.latex,
      problemType: "system_of_equations",
      finalAnswer: null,
      verified: false,
      methods: [],
      graph: null,
      routeToTutor: true,
    };
  }

  // 2) Constrained LLM candidate — still must pass the verification gate.
  if (cls.verifyMode === "none") {
    return couldNotVerify(cls, "no_verify_mode", onCouldNotVerify);
  }

  let llm = await generateLlmCandidate(complete, cls);
  if (!llm) return couldNotVerify(cls, "llm_no_candidate", onCouldNotVerify);

  let outcome = verifyCandidate(cls, llm);

  if (!outcome.ok) {
    // Log WHAT the model returned so a rejection reads as "model was wrong /
    // imprecise" vs a gate problem — the substitution check itself is trusted.
    logger.info("solve.candidateRejected", {
      problemType: cls.problemType,
      answer: llm.answer.plain,
      values: llm.assignments.map((a) => a.value),
    });

    // ONE retry, at maximum reasoning effort and told exactly which answer just
    // failed. A large share of rejections are not "this problem is unsolvable"
    // but a recoverable slip — a root rounded too coarsely to survive
    // substitution, a missed second root, an extraneous log root left in. Giving
    // up after a single sample throws those away.
    //
    // The golden rule is untouched: the retry's candidate goes through the SAME
    // `verifyCandidate` gate. This can only convert a rejected answer into a
    // proven one or leave the honest couldn't-verify exactly as it was — it can
    // never let an unverified answer through.
    //
    // COST: bounded at 2 candidate calls per solve, and only on the minority
    // path where the first was rejected. Note `RATE_LIMITS.solve` meters
    // REQUESTS, not OpenAI calls, so a user's worst-case call ceiling doubles on
    // rejections — the same trade-off already documented for teaching enrichment.
    const retry = await generateLlmCandidate(complete, cls, "retry", llm.answer.plain);
    const retryOutcome = retry ? verifyCandidate(cls, retry) : null;

    if (retry && retryOutcome?.ok) {
      logger.info("solve.retryVerified", {
        problemType: cls.problemType,
        rejected: llm.answer.plain,
        answer: retry.answer.plain,
      });
      llm = retry;
      outcome = retryOutcome;
    } else {
      logger.info("solve.retryRejected", {
        problemType: cls.problemType,
        firstAnswer: llm.answer.plain,
        retryAnswer: retry?.answer.plain ?? null,
      });
      return couldNotVerify(cls, "verify_gate_failed", onCouldNotVerify);
    }
  }

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
    case "inequality": {
      // The candidate solution SET is proven by sampling: inside ⟺ the
      // inequality holds. The answer is the model's (now-verified) interval form.
      if (!cls.ineqLhs || !cls.ineqRhs || !cls.ineqOp) return { ok: false };
      return verifyInequality(
        cls.ineqLhs,
        cls.ineqRhs,
        cls.ineqOp,
        cls.unknown,
        llm.intervals
      )
        ? { ok: true, answer: llm.answer }
        : { ok: false };
    }
    case "ode": {
      // Substitute the model's candidate solution back into the ODE: differentiate
      // it and check the residual ≈ 0 across samples + constant values (+ any
      // initial conditions). A non-solution leaves a residual and is rejected.
      if (!cls.odeResidual || !cls.odeDepVar || !cls.odeIndepVar) return { ok: false };
      return verifyOde(
        cls.odeResidual,
        cls.odeDepVar,
        cls.odeIndepVar,
        cls.odeOrder ?? 1,
        llm.odeSolution,
        cls.odeInitial ?? []
      )
        ? // Display the VERIFIED solution, not the model's free-text answerLatex
          // (which the gate never checks) — mirrors substitution/trig answers.
          { ok: true, answer: odeAnswer(cls.odeDepVar, llm.odeSolution) }
        : { ok: false };
    }
    case "word_problem": {
      // We can't verify the READING, but we can verify the ARITHMETIC: the
      // answer must satisfy the equation the model extracted (setupEquation).
      // A self-consistent setup+answer passes; an arithmetic slip fails.
      const parts = equationParts(llm.setupEquation);
      const values = llm.assignments.map((a) => a.value);
      if (parts.length === 0 || values.length === 0) return { ok: false };
      const variable = llm.assignments[0]?.variable ?? cls.unknown;
      return verifyRoots(parts, variable, values)
        ? { ok: true, answer: llm.answer }
        : { ok: false };
    }
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
