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
    // Grouped exponents: the power sits on a `)`, not on `x`. Regression —
    // these used to fall through to "linear_equation" (detectDegree missed them).
    ["(x + 1)^3 = 0", "polynomial_equation", "llm_candidate"], // degree 3
    ["(2x - 5)^4 = 0", "polynomial_equation", "llm_candidate"], // degree 4
    ["(x^2 + 1)^5 = 0", "polynomial_equation", "llm_candidate"], // degree 2*5 = 10
    ["(x + 1)^2 = 4", "quadratic_equation", "equation"], // squared group → degree 2
    // Exponential: the unknown is in the EXPONENT (not the base). Regression —
    // these were mislabelled linear_equation and fed to mathsteps + the model
    // as "linear". (x^2 / (x+1)^3 above stay polynomial: unknown in the base.)
    ["3^{2x+1} + 4(3^x) - 15 = 0", "exponential_equation", "llm_candidate"],
    ["2^x = 8", "exponential_equation", "llm_candidate"],
    // Logarithmic: the unknown is inside a log (not the base/exponent).
    ["\\ln(x) = 2", "logarithmic_equation", "llm_candidate"],
    ["\\ln(x) + \\ln(x-3) = \\ln(10)", "logarithmic_equation", "llm_candidate"],
    ["\\log_2(x) = 5", "logarithmic_equation", "llm_candidate"],
    ["\\sin(x) = 0.5", "trigonometric_equation", "llm_candidate"],
    // Descriptive statistics — deterministic (keyword + a comma-separated list).
    ["mean of 2, 4, 6, 8", "statistics", "statistics"],
    ["standard deviation of 2, 4, 4, 4, 5, 5, 7, 9", "statistics", "statistics"],
    // Inequalities — solution set via the verified LLM tier.
    ["2x + 3 < 7", "inequality", "llm_candidate"],
    ["x^2 - 5x + 6 \\geq 0", "inequality", "llm_candidate"],
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

  // Regression: a rational equation whose exponent is on `(x+1)`, not on `x`,
  // was mislabelled `linear_equation` and fed to mathsteps + the model as
  // "linear". It has a real root (x = -6/5) the LLM tier can find, so it must
  // reach that tier with an HONEST (non-linear) problem type.
  describe("\\frac{x+2}{(x+1)^3} = \\frac{120}{x} (regression)", () => {
    const EQ = "\\frac{x + 2}{(x + 1)^3} = \\frac{120}{x}";
    it("is no longer classified linear_equation", () => {
      const c = classify(EQ);
      expect(c.problemType).not.toBe("linear_equation");
      expect(c.problemType).toBe("polynomial_equation");
    });
    it("routes to the verified LLM-candidate tier with substitution", () => {
      const c = classify(EQ);
      expect(c.strategy).toBe("llm_candidate");
      expect(c.isEquation).toBe(true);
      expect(c.verifyMode).toBe("substitution");
    });
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
