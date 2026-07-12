import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solveDeterministic } from "../src/solver/deterministic";

/** Solve deterministically and assert the verify gate passes. */
function det(latex: string) {
  const cls = classify(latex);
  const c = solveDeterministic(cls);
  return { cls, candidate: c };
}

describe("solveDeterministic — verified answers", () => {
  it("linear equation", () => {
    const { candidate } = det("2x + 5 = 15");
    expect(candidate).not.toBeNull();
    expect(candidate!.verify()).toBe(true);
    expect(candidate!.answer.plain).toBe("x = 5");
  });

  it("quadratic equation with two rational roots", () => {
    const { candidate } = det("5x^2 + 3x - 2 = 0");
    expect(candidate).not.toBeNull();
    expect(candidate!.verify()).toBe(true);
    expect(candidate!.answer.plain).toBe("x = -1 or x = 2/5");
    // primary factoring method + a deterministic quadratic-formula method
    expect(candidate!.methods.map((m) => m.id)).toEqual([
      "factoring",
      "quadratic_formula",
    ]);
    expect(candidate!.methods.filter((m) => m.examPick)).toHaveLength(1);
    expect(candidate!.quadratic).toEqual({ a: 5, b: 3, c: -2 });
  });

  it("arithmetic evaluates to a fraction", () => {
    const { candidate } = det("\\frac{3}{4} + \\frac{1}{2}");
    expect(candidate).not.toBeNull();
    expect(candidate!.verify()).toBe(true);
    expect(candidate!.answer.plain).toBe("5/4");
  });

  it("simplify combines like terms", () => {
    const { candidate } = det("2x + 3x + 5");
    expect(candidate).not.toBeNull();
    expect(candidate!.verify()).toBe(true);
  });

  it("derivative via mathjs", () => {
    const { candidate } = det("\\frac{d}{dx}(x^3 + 2x)");
    expect(candidate).not.toBeNull();
    expect(candidate!.verify()).toBe(true);
  });
});

describe("solveDeterministic — returns null when it can't truly solve", () => {
  it("mathsteps 'gives up' (x^2 + 1 = 0) → null, not a fake x^2 = -1", () => {
    const { candidate } = det("x^2 + 1 = 0");
    expect(candidate).toBeNull();
  });

  it("cubic is out of the deterministic band → null", () => {
    // classified as polynomial_equation / llm_candidate, so det. returns null
    const { candidate } = det("x^3 - 6x^2 + 11x - 6 = 0");
    expect(candidate).toBeNull();
  });
});
