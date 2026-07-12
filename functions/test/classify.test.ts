import { describe, expect, it } from "vitest";
import { classify, equationParts } from "../src/solver/classify";

describe("classify", () => {
  const cases: [string, string, string][] = [
    // input, problemType, strategy
    ["3 + 4 \\times 2", "arithmetic", "arithmetic"],
    ["2x + 3x + 5", "expression", "simplify"],
    ["2x + 5 = 15", "linear_equation", "equation"],
    ["5x^2 + 3x - 2 = 0", "quadratic_equation", "equation"],
    ["x^3 - 6x^2 + 11x - 6 = 0", "polynomial_equation", "llm_candidate"],
    ["\\sin(x) = 0.5", "trigonometric_equation", "llm_candidate"],
    ["2x + 3y = 6, x - y = 3", "system_of_equations", "llm_candidate"],
    ["\\frac{d}{dx}(x^3 + 2x)", "derivative", "derivative"],
    ["\\int x^2 dx", "integral", "llm_candidate"],
  ];
  for (const [input, type, strategy] of cases) {
    it(`${input} → ${type}/${strategy}`, () => {
      const c = classify(input);
      expect(c.problemType).toBe(type);
      expect(c.strategy).toBe(strategy);
    });
  }

  it("extracts the derivative operand", () => {
    expect(classify("\\frac{d}{dx}(\\sqrt{2}x + \\sin(3x))").derivativeTarget).toBe(
      "sqrt(2)x + sin(3x)"
    );
  });

  it("extracts the integrand", () => {
    expect(classify("\\int x^2 dx").integrand).toBe("x^2");
  });

  it("sets the right verify mode", () => {
    expect(classify("2x + 5 = 15").verifyMode).toBe("substitution");
    expect(classify("\\int x^2 dx").verifyMode).toBe("derivative_back");
    expect(classify("2x + 3x").verifyMode).toBe("equality");
  });
});

describe("equationParts", () => {
  it("splits a system into individual equations", () => {
    expect(equationParts("2x + 3y = 6, x - y = 3")).toEqual([
      { lhs: "2x + 3y", rhs: "6" },
      { lhs: "x - y", rhs: "3" },
    ]);
  });
  it("keeps a single equation as one part", () => {
    expect(equationParts("2x + 5 = 15")).toEqual([{ lhs: "2x + 5", rhs: "15" }]);
  });
});
