// Inequalities — the model proposes a solution SET; the interval-sampling gate
// proves every point inside satisfies it and every point outside doesn't, and
// checks the open/closed boundary. A wrong region OR a wrong boundary is caught.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { verifyInequality, type Interval } from "../src/solver/verify";
import type { JsonCompleter } from "../src/solver/narrate";

const completerWith = (c: Record<string, unknown>): JsonCompleter => async (s) =>
  s.includes("ALREADY-SOLVED") ? {} : c;

const open = (lo: number | null, hi: number | null): Interval => ({ lo, hi, loOpen: true, hiOpen: true });

async function verified(input: string, candidate: Record<string, unknown>): Promise<boolean> {
  return (await solve(classify(input), completerWith(candidate))).verified;
}

describe("classify — inequalities", () => {
  it("routes a single-variable inequality to the inequality gate", () => {
    const c = classify("2x + 3 < 7");
    expect(c.problemType).toBe("inequality");
    expect(c.verifyMode).toBe("inequality");
    expect(c.ineqOp).toBe("<");
  });
  it("declines a chained inequality (two operators) for now", () => {
    expect(classify("-3 < x < 5").problemType).not.toBe("inequality");
  });
});

describe("solve — inequalities", () => {
  it("verifies a linear solution set (2x+3<7 → x<2)", async () => {
    expect(await verified("2x + 3 < 7", {
      answerLatex: "x < 2", answerPlain: "x < 2",
      intervals: [{ lo: null, hi: 2, loOpen: true, hiOpen: true }], methods: [],
    })).toBe(true);
  });

  it("verifies a quadratic solution set (x²-5x+6>0 → x<2 or x>3)", async () => {
    expect(await verified("x^2 - 5x + 6 > 0", {
      answerLatex: "x < 2 \\text{ or } x > 3", answerPlain: "x<2 or x>3",
      intervals: [{ lo: null, hi: 2, loOpen: true, hiOpen: true }, { lo: 3, hi: null, loOpen: true, hiOpen: true }],
      methods: [],
    })).toBe(true);
  });

  it("verifies a non-strict boundary as CLOSED (2x≥4 → x≥2)", async () => {
    expect(await verified("2x \\geq 4", {
      answerLatex: "x \\ge 2", answerPlain: "x >= 2",
      intervals: [{ lo: 2, hi: null, loOpen: false, hiOpen: true }], methods: [],
    })).toBe(true);
  });

  it("REJECTS a wrong region (2x+3<7 claimed x>2)", async () => {
    expect(await verified("2x + 3 < 7", {
      answerLatex: "x > 2", answerPlain: "x > 2",
      intervals: [{ lo: 2, hi: null, loOpen: true, hiOpen: true }], methods: [],
    })).toBe(false);
  });

  it("REJECTS a wrong boundary type (strict < claimed as closed ≤)", async () => {
    expect(await verified("2x + 3 < 7", {
      answerLatex: "x \\le 2", answerPlain: "x <= 2",
      intervals: [{ lo: null, hi: 2, loOpen: true, hiOpen: false }], methods: [],
    })).toBe(false);
  });
});

describe("verifyInequality (the gate, directly)", () => {
  it("accepts the true set and rejects a shifted one", () => {
    // 2x+3 < 7  ⇔  x < 2
    expect(verifyInequality("2x+3", "7", "<", "x", [open(null, 2)])).toBe(true);
    expect(verifyInequality("2x+3", "7", "<", "x", [open(null, 1)])).toBe(false);
    expect(verifyInequality("2x+3", "7", "<", "x", [open(null, null)])).toBe(false); // all reals
  });
});
