import { describe, expect, it } from "vitest";
import {
  asciiToLatex,
  cleanLatex,
  latexToAscii,
  splitEquation,
  stripOuterParens,
  variablesIn,
} from "../src/solver/latex";

describe("latexToAscii", () => {
  it("passes plain algebra through", () => {
    expect(latexToAscii("5x^2 + 3x - 2 = 0")).toBe("5x^2 + 3x - 2 = 0");
  });
  it("expands fractions", () => {
    expect(latexToAscii("\\frac{3}{4} + \\frac{1}{2}")).toBe(
      "((3)/(4)) + ((1)/(2))"
    );
  });
  it("converts sqrt, cdot and functions", () => {
    expect(latexToAscii("\\sqrt{2} \\cdot x + \\sin(3x)")).toBe(
      "sqrt(2) * x + sin(3x)"
    );
  });
  it("strips braces from exponents", () => {
    expect(latexToAscii("x^{2} - 5x + 6 = 0")).toBe("x^(2) - 5x + 6 = 0");
  });

  // Nested brace structures the math keyboard produces (spec §6). The
  // conversions must resolve INNERMOST-FIRST so a fraction whose numerator holds
  // an exponent/root isn't left mangled.
  describe("nested structures (keyboard §6)", () => {
    it("exponent inside a fraction numerator", () => {
      expect(latexToAscii(String.raw`\frac{x^{2}}{3}`)).toBe("((x^(2))/(3))");
    });
    it("exponent inside a fraction denominator", () => {
      expect(latexToAscii(String.raw`\frac{1}{x^{2}}`)).toBe("((1)/(x^(2)))");
    });
    it("root inside a fraction numerator", () => {
      expect(latexToAscii(String.raw`\frac{\sqrt{2}}{3}`)).toBe(
        "((sqrt(2))/(3))"
      );
    });
    it("fraction inside an exponent", () => {
      expect(latexToAscii(String.raw`x^{\frac{2}{3}}`)).toBe("x^(((2)/(3)))");
    });
    it("fraction inside a root", () => {
      expect(latexToAscii(String.raw`\sqrt{\frac{1}{2}}`)).toBe(
        "sqrt(((1)/(2)))"
      );
    });
    it("nested fractions", () => {
      expect(latexToAscii(String.raw`\frac{\frac{1}{2}}{3}`)).toBe(
        "((((1)/(2)))/(3))"
      );
    });
    it("quadratic-formula shape no longer mangles", () => {
      expect(latexToAscii(String.raw`\frac{-b+\sqrt{b^{2}-4ac}}{2a}`)).toBe(
        "((-b+sqrt(b^(2)-4ac))/(2a))"
      );
    });
  });
});

describe("cleanLatex", () => {
  it("drops delimiters and spacing macros", () => {
    expect(cleanLatex("$$ 2x + 5 = 15 $$")).toBe("2x + 5 = 15");
    expect(cleanLatex("\\left( x \\right)")).toBe("( x )");
  });
});

describe("splitEquation", () => {
  it("splits on a single top-level =", () => {
    expect(splitEquation("2x + 5 = 15")).toEqual({
      isEquation: true,
      lhs: "2x + 5",
      rhs: "15",
    });
  });
  it("treats a bare expression as non-equation", () => {
    expect(splitEquation("2x + 5").isEquation).toBe(false);
  });
  it("ignores relational operators that aren't equality", () => {
    expect(splitEquation("x >= 3").isEquation).toBe(false);
  });
});

describe("stripOuterParens", () => {
  it("removes a single wrapping pair", () => {
    expect(stripOuterParens("(x + 1)")).toBe("x + 1");
    expect(stripOuterParens("(sqrt(2)x + sin(3x))")).toBe(
      "sqrt(2)x + sin(3x)"
    );
  });
  it("leaves non-wrapping parens intact", () => {
    expect(stripOuterParens("(x) + (1)")).toBe("(x) + (1)");
  });
});

describe("variablesIn", () => {
  it("finds variables, excluding functions and constants", () => {
    expect(variablesIn("5x^2 + 3x - 2").sort()).toEqual(["x"]);
    expect(variablesIn("2x + 3y = 6").sort()).toEqual(["x", "y"]);
    expect(variablesIn("sin(x) + pi").sort()).toEqual(["x"]);
    expect(variablesIn("3 + 4 * 2")).toEqual([]);
  });
});

describe("asciiToLatex", () => {
  it("renders sqrt and explicit multiply", () => {
    expect(asciiToLatex("sqrt(2) * x")).toContain("\\sqrt{2}");
    expect(asciiToLatex("2 * x")).toContain("\\cdot");
  });
});
