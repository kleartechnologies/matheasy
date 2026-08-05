import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solveDeterministic } from "../src/solver/deterministic";
import { antiderivative } from "../src/solver/integral";
import { verifyDerivative } from "../src/solver/verify";
import type { RawMethod } from "../src/solver/types";

function solve(latex: string) {
  const cls = classify(latex);
  expect(cls.strategy, `wrong strategy for ${latex}`).toBe("integral");
  const c = solveDeterministic(cls);
  expect(c, `no candidate for ${latex}`).not.toBeNull();
  expect(c!.verify(), `verify failed for ${latex}`).toBe(true);
  const m = c!.methods.find((x) => x.examPick) ?? c!.methods[0];
  return { method: m, candidate: c!, cls };
}

const codes = (m: RawMethod) => m.steps.map((s) => s.operationCode);

describe("indefinite integrals — every rule application is a visible step", () => {
  it("power rule keeps the coefficient exact — never 3·x³/3", () => {
    const { candidate } = solve("\\int (3x^2 + 2x) dx");
    expect(candidate.answer.plain).toBe("x^3 + x^2 + C");
  });

  it("splits a sum and shows one rule per term", () => {
    const { method, candidate } = solve("Find \\int (4x^3 - 2x + 5) dx");
    expect(candidate.answer.plain).toBe("x^4 - x^2 + 5*x + C");
    expect(codes(method)).toEqual([
      "START",
      "SPLIT_TERMS",
      "POWER_RULE",
      "POWER_RULE",
      "CONSTANT_RULE",
      "COMBINE_TERMS",
      "ADD_CONSTANT",
    ]);
    // The subtracted term keeps its sign in the split, not buried in a wrapper.
    expect(method.steps[1].latex).toContain("- \\int 2 x");
  });

  it("knows the standard integrals", () => {
    expect(solve("\\int \\sin x \\, dx").candidate.answer.plain).toBe(
      "-cos(x) + C"
    );
    expect(solve("\\int e^x dx").candidate.answer.plain).toBe("e^x + C");
    expect(solve("\\int \\frac{1}{x} dx").candidate.answer.plain).toBe(
      "log(abs(x)) + C"
    );
  });

  it("divides by the inner slope for a linear inside", () => {
    expect(solve("\\int \\cos(2x) dx").candidate.answer.plain).toBe(
      "(1/2)*sin(2 x) + C"
    );
    expect(solve("\\int e^{3x} dx").candidate.answer.plain).toBe(
      "(1/3)*e^(3 x) + C"
    );
    expect(solve("\\int \\frac{1}{2x+1} dx").candidate.answer.plain).toBe(
      "(1/2)*log(abs(2 x + 1)) + C"
    );
    expect(solve("\\int (2x+1)^3 dx").candidate.answer.plain).toBe(
      "(1/8)*(2 x + 1)^4 + C"
    );
  });

  it("handles roots and negative powers through the same power rule", () => {
    expect(solve("\\int \\sqrt{x} dx").candidate.answer.plain).toBe(
      "(2/3)*x^(3/2) + C"
    );
    expect(solve("\\int \\frac{1}{x^2} dx").candidate.answer.plain).toBe(
      "-x^(-1) + C"
    );
  });

  it("every answer differentiates back to its own integrand", () => {
    for (const [latex, integrand] of [
      ["\\int (3x^2 + 2x) dx", "3x^2 + 2x"],
      ["\\int \\cos(2x) dx", "cos(2x)"],
      ["\\int \\sqrt{x} dx", "sqrt(x)"],
    ] as const) {
      const { candidate } = solve(latex);
      const F = candidate.answer.plain.replace(/\s*\+\s*C$/, "");
      expect(verifyDerivative(F, integrand, "x"), latex).toBe(true);
    }
  });
});

describe("definite integrals — antiderivative vs independent quadrature", () => {
  it("computes ∫₀¹ x² dx = 1/3 with the bounds as steps", () => {
    const { method, candidate } = solve("\\int_0^1 x^2 \\, dx");
    expect(candidate.answer.plain).toBe("1/3");
    expect(codes(method)).toEqual([
      "START",
      "POWER_RULE",
      "FUNDAMENTAL_THEOREM",
      "EVALUATE_UPPER",
      "EVALUATE_LOWER",
      "SUBTRACT_BOUNDS",
    ]);
  });

  it("computes ∫₁³ (2x+1) dx = 10", () => {
    expect(solve("\\int_1^3 (2x + 1) dx").candidate.answer.plain).toBe("10");
  });

  it("handles a π bound exactly", () => {
    const { method, candidate } = solve("\\int_0^{\\pi} \\sin x \\, dx");
    expect(candidate.answer.plain).toBe("2");
    const sub = method.steps.find((s) => s.operationCode === "SUBTRACT_BOUNDS");
    expect(sub!.ascii).toBe("1 - (-1) = 2");
  });
});

describe("the engine declines what it cannot integrate honestly", () => {
  it("returns null on parts / substitution / rational shapes", () => {
    for (const [integrand, unknown] of [
      ["x * e^(x^2)", "x"], // substitution
      ["x * cos(x)", "x"], // parts
      ["x / (x^2 + 1)", "x"], // rational
      ["sin(x^2)", "x"], // non-linear inner
      ["pi * x", "x"], // irrational coefficient
    ] as const) {
      expect(antiderivative(integrand, unknown), integrand).toBeNull();
    }
  });

  it("a declined integral still classifies for the LLM tier with its gate", () => {
    const cls = classify("\\int x \\cos x \\, dx");
    expect(cls.strategy).toBe("integral");
    expect(cls.verifyMode).toBe("derivative_back");
    expect(solveDeterministic(cls)).toBeNull();
  });

  it("keeps the definite gate for declined definite integrals", () => {
    const cls = classify("\\int_0^1 x e^{x^2} dx");
    expect(cls.verifyMode).toBe("definite_integral");
    expect(solveDeterministic(cls)).toBeNull();
  });
});

describe("integration variable other than x", () => {
  it("integrates in the written variable", () => {
    const { candidate } = solve("\\int t^2 \\, dt");
    expect(candidate.answer.plain).toBe("(1/3)*t^3 + C");
  });
});
