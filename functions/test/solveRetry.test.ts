/**
 * The verification RETRY: when the substitution gate rejects the LLM's first
 * candidate, the solver gets one more attempt at maximum reasoning effort before
 * falling back to the honest couldn't-verify state.
 *
 * The thing these tests actually guard is the golden rule. A retry loop is a
 * plausible place to accidentally weaken the gate — "it failed twice, ship the
 * closer one" — so the central assertions are the NEGATIVE ones: two wrong
 * candidates must still produce `verified:false`, and the retry must never be
 * able to return an answer that did not itself pass verification.
 */
import { describe, expect, it, vi } from "vitest";

import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { JsonCompleter } from "../src/solver/narrate";

/**
 * A completer that serves a different candidate per attempt.
 *
 * Narration prompts (the "ALREADY-SOLVED" system prompt) are answered with `{}`
 * so they fall back to canned steps and never consume a candidate.
 */
function candidateSequence(...candidates: Record<string, unknown>[]): {
  completer: JsonCompleter;
  calls: () => { attempt: string | undefined; user: string }[];
} {
  const calls: { attempt: string | undefined; user: string }[] = [];
  let i = 0;
  const completer: JsonCompleter = async (system, user, _maxTokens, attempt) => {
    if (system.includes("ALREADY-SOLVED")) return {};
    calls.push({ attempt, user });
    return candidates[Math.min(i++, candidates.length - 1)];
  };
  return { completer, calls: () => calls };
}

/** `x^2 + 1 = 0` has no real root, so any real candidate is rejected by the gate. */
const NO_REAL_ROOTS = "x^2 + 1 = 0";
/** An indefinite integral — verified by differentiating the answer back. */
const INTEGRAL = "\\int 2x \\, dx";

async function run(latex: string, completer: JsonCompleter) {
  return solve(classify(latex), completer);
}

describe("solve — retry after a failed verification", () => {
  it("accepts a retry candidate that passes the gate the first one failed", async () => {
    const { completer, calls } = candidateSequence(
      // Wrong antiderivative: d/dx(x^2 + x) = 2x + 1 ≠ 2x → rejected.
      { answerLatex: "x^2 + x", answerPlain: "x^2 + x" },
      // Correct: d/dx(x^2) = 2x → passes.
      { answerLatex: "x^2", answerPlain: "x^2" }
    );

    const p = await run(INTEGRAL, completer);

    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x^2");
    expect(calls()).toHaveLength(2);
  });

  it("marks the second attempt as a retry so the proxy can escalate the model", async () => {
    const { completer, calls } = candidateSequence(
      { answerLatex: "x^2 + x", answerPlain: "x^2 + x" },
      { answerLatex: "x^2", answerPlain: "x^2" }
    );

    await run(INTEGRAL, completer);

    expect(calls()[0].attempt).toBe("first");
    expect(calls()[1].attempt).toBe("retry");
  });

  it("tells the retry which answer was rejected, so it cannot just repeat it", async () => {
    const { completer, calls } = candidateSequence(
      { answerLatex: "x^2 + x", answerPlain: "x^2 + x" },
      { answerLatex: "x^2", answerPlain: "x^2" }
    );

    await run(INTEGRAL, completer);

    const retryPrompt = calls()[1].user;
    expect(retryPrompt).toContain("x^2 + x");
    expect(retryPrompt).toContain("FAILED verification");
    // The first attempt must NOT carry the correction text.
    expect(calls()[0].user).not.toContain("FAILED verification");
  });

  it("still returns an honest couldn't-verify when BOTH candidates fail", async () => {
    // The core guarantee: a retry adds an attempt, never a lower bar.
    const { completer, calls } = candidateSequence(
      { answerLatex: "x = 1", answerPlain: "x = 1", solutions: [{ variable: "x", value: 1 }] },
      { answerLatex: "x = 2", answerPlain: "x = 2", solutions: [{ variable: "x", value: 2 }] }
    );

    const p = await run(NO_REAL_ROOTS, completer);

    expect(p.verified).toBe(false);
    expect(p.finalAnswer).toBeNull();
    expect(calls()).toHaveLength(2);
  });

  it("never returns the retry's answer unless the retry itself verified", async () => {
    // Second candidate is also wrong (d/dx(3x^2) = 6x ≠ 2x). Neither may surface.
    const { completer } = candidateSequence(
      { answerLatex: "x^2 + x", answerPlain: "x^2 + x" },
      { answerLatex: "3x^2", answerPlain: "3x^2" }
    );

    const p = await run(INTEGRAL, completer);

    expect(p.verified).toBe(false);
    expect(p.finalAnswer).toBeNull();
  });

  it("stops at exactly two attempts — no unbounded retry loop", async () => {
    const { completer, calls } = candidateSequence({
      answerLatex: "x = 1",
      answerPlain: "x = 1",
      solutions: [{ variable: "x", value: 1 }],
    });

    await run(NO_REAL_ROOTS, completer);

    expect(calls()).toHaveLength(2);
  });

  it("does not retry when the FIRST candidate already verified", async () => {
    // The retry is a failure path only; a good first answer must cost one call.
    const { completer, calls } = candidateSequence({
      answerLatex: "x^2",
      answerPlain: "x^2",
    });

    const p = await run(INTEGRAL, completer);

    expect(p.verified).toBe(true);
    expect(calls()).toHaveLength(1);
  });

  it("reports the failure to the analytics hook exactly once", async () => {
    const { completer } = candidateSequence({
      answerLatex: "x = 1",
      answerPlain: "x = 1",
      solutions: [{ variable: "x", value: 1 }],
    });
    const onCouldNotVerify = vi.fn();

    await solve(classify(NO_REAL_ROOTS), completer, onCouldNotVerify);

    expect(onCouldNotVerify).toHaveBeenCalledTimes(1);
    expect(onCouldNotVerify).toHaveBeenCalledWith("verify_gate_failed");
  });

  it("survives a retry that throws, falling back to couldn't-verify", async () => {
    // An OpenAI 429/timeout on the retry must degrade honestly, not 500 the solve.
    let call = 0;
    const completer: JsonCompleter = async (system) => {
      if (system.includes("ALREADY-SOLVED")) return {};
      if (++call === 1) {
        return { answerLatex: "x = 1", answerPlain: "x = 1", solutions: [{ variable: "x", value: 1 }] };
      }
      throw new Error("upstream exploded");
    };

    const p = await run(NO_REAL_ROOTS, completer);

    expect(p.verified).toBe(false);
    expect(p.finalAnswer).toBeNull();
  });

  it("does not spend a retry on the deterministic path", async () => {
    // mathsteps solves this without an LLM candidate at all; a retry here would
    // be pure wasted spend.
    const NEVER: JsonCompleter = async (system) => {
      if (system.includes("ALREADY-SOLVED")) return {};
      throw new Error("no candidate call expected on the deterministic path");
    };

    const p = await run("2x + 5 = 15", NEVER);

    expect(p.verified).toBe(true);
  });
});
