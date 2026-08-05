import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solveDeterministic } from "../src/solver/deterministic";
import { parsePercent } from "../src/solver/percent";
import type { RawMethod } from "../src/solver/types";

function solve(latex: string) {
  const cls = classify(latex);
  expect(cls.strategy, `wrong strategy for ${latex}`).toBe("percent");
  const c = solveDeterministic(cls);
  expect(c, `no candidate for ${latex}`).not.toBeNull();
  expect(c!.verify(), `verify failed for ${latex}`).toBe(true);
  const m = c!.methods.find((x) => x.examPick) ?? c!.methods[0];
  return { method: m, candidate: c!, cls };
}

const codes = (m: RawMethod) => m.steps.map((s) => s.operationCode);

describe("percent — the fraction meaning is the lesson, not the shortcut", () => {
  it("percent-of walks percent → fraction → product → answer", () => {
    const { method, candidate } = solve("What is 20% of 80?");
    expect(candidate.answer.plain).toBe("16");
    expect(codes(method)).toEqual([
      "START",
      "PERCENT_MEANS",
      "WRITE_PRODUCT",
      "MULTIPLY_OUT",
      "COMPUTE",
    ]);
    expect(method.steps[1].latex).toBe("20\\% = \\tfrac{20}{100}");
  });

  it("accepts the latex the scanner produces", () => {
    expect(solve("20\\% \\text{ of } 80").candidate.answer.plain).toBe("16");
    expect(solve("Find 25\\% of 320").candidate.answer.plain).toBe("80");
  });

  it("what-percent simplifies the fraction before scaling to 100", () => {
    const { method, candidate } = solve("30 is what percent of 120?");
    expect(candidate.answer.plain).toBe("25%");
    expect(codes(method)).toEqual([
      "START",
      "WRITE_FRACTION",
      "SIMPLIFY_FRACTION",
      "TIMES_100",
      "COMPUTE",
    ]);
    expect(method.steps[2].latex).toBe("\\tfrac{1}{4}");
  });

  it("both phrasings of what-percent agree", () => {
    expect(solve("What percentage of 50 is 30?").candidate.answer.plain).toBe(
      "60%"
    );
    expect(solve("30 is what percent of 50?").candidate.answer.plain).toBe(
      "60%"
    );
  });

  it("increase finds the part first, then adds it on", () => {
    const { method, candidate } = solve("Increase 240 by 15\\%");
    expect(candidate.answer.plain).toBe("276");
    expect(codes(method)).toEqual([
      "START",
      "PERCENT_MEANS",
      "FIND_PART",
      "ADD_PART",
      "COMPUTE",
    ]);
    expect(method.steps[3].ascii).toBe("240 + 36 = 276");
  });

  it("decrease subtracts the same part", () => {
    const { method, candidate } = solve("Decrease 80 by 25\\%");
    expect(candidate.answer.plain).toBe("60");
    expect(codes(method)).toContain("SUBTRACT_PART");
    expect(method.steps[3].ascii).toBe("80 - 20 = 60");
  });
});

describe("ratio — parts, shares, and the simplest form", () => {
  it("shares by counting parts, valuing one, then scaling each", () => {
    const { method, candidate } = solve("Divide 60 in the ratio 2:3");
    expect(candidate.answer.plain).toBe("24 : 36");
    expect(codes(method)).toEqual([
      "START",
      "TOTAL_PARTS",
      "ONE_PART",
      "EACH_SHARE",
      "EACH_SHARE",
      "RESULT",
    ]);
    expect(method.steps[1].ascii).toBe("2 + 3 = 5");
    expect(method.steps[2].ascii).toBe("60 / 5 = 12");
  });

  it("handles a three-part ratio", () => {
    const { candidate } = solve("Share 120 in the ratio 1:2:3");
    expect(candidate.answer.plain).toBe("20 : 40 : 60");
  });

  it("shares that do not divide evenly still verify", () => {
    // 7 parts of 13 each — the check is sum + cross-ratio, not integer-ness.
    expect(solve("Share 91 in the ratio 3:4").candidate.answer.plain).toBe(
      "39 : 52"
    );
  });

  it("simplifies a ratio by its gcd, shown as a step", () => {
    const { method, candidate } = solve("Simplify the ratio 12:18");
    expect(candidate.answer.plain).toBe("2 : 3");
    expect(codes(method)).toEqual([
      "START",
      "FIND_GCD",
      "DIVIDE_ALL_PARTS",
      "RESULT",
    ]);
    expect(method.steps[1].ascii).toBe("GCD(12, 18) = 6");
  });

  it("solves a colon proportion from either side", () => {
    const { method, candidate } = solve("x : 12 = 3 : 4");
    expect(candidate.answer.plain).toBe("x = 9");
    expect(codes(method)).toEqual([
      "GIVEN",
      "WRITE_AS_FRACTIONS",
      "CROSS_MULTIPLY",
      "DIVIDE_BOTH_SIDES",
      "FIND_ROOTS",
    ]);
    expect(method.steps[2].ascii).toBe("4x = 36");
    // Unknown in a denominator slot works too.
    expect(solve("15 : y = 5 : 2").candidate.answer.plain).toBe("y = 6");
  });
});

describe("the parse gate declines what it cannot own", () => {
  it("returns null on everything else", () => {
    for (const p of [
      "2x + 5 = 15",
      "Simplify 2x + 3x",
      "20 of 80",
      "x : 12 = y : 4", // two unknowns
      "Simplify the ratio 12:0", // zero part
      "A shirt costs $40 and is discounted 30%. What is the sale price?",
    ]) {
      expect(parsePercent(p), p).toBeNull();
    }
  });

  it("leaves the shipped strategies untouched", () => {
    expect(classify("2x + 5 = 15").strategy).toBe("equation");
    expect(classify("Simplify 2x + 3x").strategy).toBe("simplify");
    expect(classify("\\frac{1}{2} + \\frac{1}{3}").strategy).toBe("arithmetic");
  });

  it("declines a ratio already in simplest form rather than parrot it", () => {
    const cls = classify("Simplify the ratio 2:3");
    expect(cls.strategy).toBe("percent");
    expect(solveDeterministic(cls)).toBeNull();
  });
});

describe("proportions written with fraction bars reach mathsteps again", () => {
  it("solves the \\frac form that used to throw on ParenthesisNode", () => {
    const cls = classify("\\frac{x}{12} = \\frac{3}{4}");
    const c = solveDeterministic(cls);
    expect(c).not.toBeNull();
    expect(c!.verify()).toBe(true);
    expect(c!.answer.plain).toBe("x = 9");
  });

  it("a two-sided fraction equation solves too", () => {
    const c = solveDeterministic(classify("\\frac{x+1}{3} = \\frac{x-1}{2}"));
    expect(c).not.toBeNull();
    expect(c!.answer.plain).toBe("x = 5");
  });
});
