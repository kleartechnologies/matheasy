import { describe, expect, it } from "vitest";
import {
  asciiToLatex,
  assumeDegreesForBareTrig,
  cleanLatex,
  latexToAscii,
  normalizeMacros,
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
  it("reads a mixed number's FULL whole part (multi-digit), not just the last digit", () => {
    // Regression: "10\frac{1}{2}" is 10.5, not 1×(0+½)=0.5.
    expect(latexToAscii("10\\frac{1}{2}")).toBe("(10+((1)/(2)))");
    expect(latexToAscii("2\\frac{1}{2}")).toBe("(2+((1)/(2)))");
  });
  it("converts sqrt, cdot and functions", () => {
    expect(latexToAscii("\\sqrt{2} \\cdot x + \\sin(3x)")).toBe(
      "sqrt(2) * x + sin(3x)"
    );
  });
  it("converts absolute-value bars to abs() (so ln|…| antiderivatives verify)", () => {
    // Bars, wrapped so a preceding function/coefficient binds correctly.
    expect(latexToAscii("5\\ln|x+3| + 4\\ln|x-2|")).toBe(
      "5 log(abs(x+3)) + 4 log(abs(x-2))"
    );
    // \left|…\right| loses its \left/\right in cleanLatex, then the bars fold.
    expect(latexToAscii("\\left|x-2\\right|")).toBe("(abs(x-2))");
    // \lvert…\rvert / \vert macros too.
    expect(latexToAscii("\\lvert x \\rvert")).toBe("(abs(x))");
  });

  it("rewrites inverse trig to mathjs names (arcsin→asin) so they differentiate", () => {
    expect(latexToAscii("\\arctan(x)")).toBe("atan(x)");
    expect(latexToAscii("\\arcsin(2x)")).toBe("asin(2x)");
    expect(latexToAscii("\\arccos(x)")).toBe("acos(x)");
    // …and their letters no longer leak into variable detection (sin⊄asin).
    expect(variablesIn(latexToAscii("\\arctan(x)"))).toEqual(["x"]);
    expect(variablesIn(latexToAscii("\\arcsin(2x)"))).toEqual(["x"]);
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
        // `4ac` is a PRODUCT — mathjs read the glued run as one symbol `ac`.
        "((-b+sqrt(b^(2)-4a*c))/(2a))"
      );
    });
  });
});

describe("normalizeMacros — scanner/rendered-LaTeX spelling variants", () => {
  it("folds \\dfrac / \\tfrac onto \\frac", () => {
    expect(normalizeMacros("\\dfrac{1}{2}")).toBe("\\frac{1}{2}");
    expect(normalizeMacros("\\tfrac{d}{dx}")).toBe("\\frac{d}{dx}");
  });
  it("keeps the content of MATH styling wrappers (\\mathrm{d}x → dx, \\operatorname{sin} → sin)", () => {
    expect(normalizeMacros("\\mathrm{d}x")).toBe("dx");
    expect(normalizeMacros("\\operatorname{sin} x")).toBe("sin x");
  });
  it("leaves \\text{…} intact — it MARKS prose, which latexToAscii drops", () => {
    // Unwrapping it here would merge "Solve the equation" into the math, and
    // every letter would read as a variable.
    expect(normalizeMacros("\\text{if } x")).toBe("\\text{if } x");
  });
  it("does NOT fold unicode operators (× stays for the raw cross-product detector)", () => {
    // Unicode ·×÷ are converted on the ascii path (latexToAscii), NOT here, so
    // classify's raw-LaTeX vector detector still reads `×` as a cross product.
    expect(normalizeMacros("2×x")).toBe("2×x");
  });
});

describe("latexToAscii — unicode operators OCR emits", () => {
  it("folds · × ÷ − onto * * / - so mathjs can parse them", () => {
    expect(latexToAscii("2·x")).toBe("2*x");
    expect(latexToAscii("3×4")).toBe("3*4");
    expect(latexToAscii("6÷2")).toBe("6/2");
    expect(latexToAscii("x − 3")).toBe("x - 3"); // U+2212 minus
  });
});

describe("latexToAscii — implicit multiply across a macro boundary (scanner fix)", () => {
  it("keeps a variable×function product parseable (x\\ln x → x log(x))", () => {
    // The `\` was LaTeX's token boundary; dropping it glued `x\cos`→`xcos`
    // (undefined) and broke every ∫x·(trig/ln/√)dx and by-parts antiderivative.
    expect(latexToAscii("x\\ln x")).toBe("x log(x)");
    expect(latexToAscii("x\\cos x")).toBe("x cos(x)");
    expect(latexToAscii("x\\sqrt{x^2+1}")).toBe("x sqrt(x^2+1)");
    expect(latexToAscii("\\sin x\\cos x")).toBe("sin(x) cos(x)"); // no space before \cos
  });
});

describe("latexToAscii — prefix-style function arguments (scanner fix)", () => {
  it("wraps a bare trig argument so mathjs can parse it", () => {
    // `\sin x` alone THREW in mathjs; `\sin x \cos x` (the ∫sin x cos x dx
    // integrand) was unparseable — now both become explicit calls.
    expect(latexToAscii("\\sin x")).toBe("sin(x)");
    expect(latexToAscii("\\sin x \\cos x")).toBe("sin(x) cos(x)");
    expect(latexToAscii("\\tan x")).toBe("tan(x)");
    expect(latexToAscii("\\ln x")).toBe("log(x)");
  });
  it("moves a power off the function onto its argument (\\sin^2 x → sin(x)^2)", () => {
    expect(latexToAscii("\\sin^2 x")).toBe("sin(x)^(2)");
    expect(latexToAscii("\\sec^2 x")).toBe("sec(x)^(2)");
    expect(latexToAscii("\\cos^{2} x")).toBe("cos(x)^(2)");
  });
  it("reads f^{-1} as the INVERSE function, never (f)^-1=csc (golden rule)", () => {
    // \sin^{-1} x is arcsin, NOT 1/sin — the wrong reading would verify a
    // different problem than asked.
    expect(latexToAscii("\\sin^{-1} x")).toBe("asin(x)");
    expect(latexToAscii("\\cos^{-1}(x)")).toBe("acos(x)");
    expect(latexToAscii("\\tan^{-1} x")).toBe("atan(x)");
  });
  it("keeps a coefficient multiplying the function (2\\sin x → 2 sin(x))", () => {
    // The `\` is LaTeX's own token boundary and an implicit multiply, preserved
    // as a space (mathjs reads `2 sin(x)` as 2·sin x).
    expect(latexToAscii("2\\sin x + 1")).toBe("2 sin(x) + 1");
    expect(latexToAscii("3\\cos x")).toBe("3 cos(x)");
  });
  it("binds only the next atom, not a following +/- term", () => {
    expect(latexToAscii("\\sin x + 1")).toBe("sin(x) + 1"); // NOT sin(x+1)
    expect(latexToAscii("\\sin 2x")).toBe("sin(2x)");
  });
  it("preserves an already-parenthesized (possibly nested) argument", () => {
    expect(latexToAscii("\\sin(x)")).toBe("sin(x)");
    expect(latexToAscii("\\ln(x^2+1)")).toBe("log(x^2+1)");
    expect(latexToAscii("\\sin\\frac{x}{2}")).toBe("sin((x)/(2))");
  });
});

describe("cleanLatex", () => {
  it("drops delimiters and spacing macros", () => {
    expect(cleanLatex("$$ 2x + 5 = 15 $$")).toBe("2x + 5 = 15");
    expect(cleanLatex("\\left( x \\right)")).toBe("( x )");
  });
  it("strips an empty 'compute this' trailer (= ?, =?, = □) but keeps a real RHS", () => {
    // A scanned "∫ … dx = ?" / "d/dx(…) = ?" placeholder made the target
    // unparseable ("… = ?") and every such scan declined — now it's dropped.
    expect(cleanLatex("\\int \\sin x \\, dx = ?")).toBe("\\int \\sin x dx");
    expect(cleanLatex("\\frac{d}{dx}(x^2) =?")).toBe("\\frac{d}{dx}(x^2)");
    expect(cleanLatex("f(x) = \\square")).toBe("f(x)");
    expect(cleanLatex("x =")).toBe("x");
    // A genuine equation's "=" is untouched (the RHS is real math, not a blank).
    expect(cleanLatex("2x + 5 = 15")).toBe("2x + 5 = 15");
    expect(cleanLatex("x^2 - 4 = 0")).toBe("x^2 - 4 = 0");
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
  it("renders sqrt, and multiplies the way a textbook does", () => {
    expect(asciiToLatex("sqrt(2) * x")).toBe("\\sqrt{2}x");
    expect(asciiToLatex("2 * x")).toBe("2x");
    // A product of two NUMBERS still needs the dot, or it reads as one number.
    expect(asciiToLatex("2 * 3")).toBe("2 \\cdot 3");
    // `x(y + 1)` would read as a function applied to a bracket.
    expect(asciiToLatex("x * (y + 1)")).toBe("x \\cdot (y + 1)");
    expect(asciiToLatex("2 * (y + 1)")).toBe("2(y + 1)");
  });

  it("stacks a quotient into a fraction", () => {
    expect(asciiToLatex("(5*x - 10)/4")).toBe("\\frac{5x - 10}{4}");
    expect(asciiToLatex("x = 3/2")).toBe("x = \\frac{3}{2}");
    expect(asciiToLatex("sqrt(2)/2")).toBe("\\frac{\\sqrt{2}}{2}");
    expect(asciiToLatex("1 - 1/(x + 1)")).toBe("1 - \\frac{1}{x + 1}");
  });

  it("keeps the precedence the slash had", () => {
    // `2*x/3` is (2x)/3 — the numerator reaches back over the product…
    expect(asciiToLatex("2*x/3")).toBe("\\frac{2x}{3}");
    // …but `1/2*x` is (1/2)·x, so the denominator stops at one operand.
    expect(asciiToLatex("1/2*x")).toBe("\\frac{1}{2}x");
    expect(asciiToLatex("x^2/3")).toBe("\\frac{x^2}{3}");
    expect(asciiToLatex("a/b/c")).toBe("\\frac{\\frac{a}{b}}{c}");
  });

  it("leaves a slash inside prose alone", () => {
    expect(asciiToLatex("\\text{a/b in words} + 1/2")).toBe(
      "\\text{a/b in words} + \\frac{1}{2}"
    );
  });
});

describe("degrees vs radians", () => {
  it("converts a degree mark inside a trig problem", () => {
    // `\sin 30^\circ` used to shatter into the unparseable `sin(30^)\circ`, so
    // the one form that states its unit was the one form that couldn't be solved.
    expect(latexToAscii("\\sin 30^\\circ")).toBe("sin(30 * pi / 180)");
    expect(latexToAscii("\\cos(60^{\\circ})")).toBe("cos((60 * pi / 180))");
    expect(latexToAscii("\\tan 45°")).toBe("tan(45 * pi / 180)");
  });

  it("leaves a degree mark alone when there is no trigonometry", () => {
    // "the angle is 30°" wants 30 back, not 0.5236 — converting an angle MEASURE
    // would corrupt the answer rather than fix it.
    expect(latexToAscii("30^\\circ + 45^\\circ")).toContain("30^");
    expect(latexToAscii("30^\\circ + 45^\\circ")).not.toContain("pi");
  });

  it("reads a bare integer argument beyond one turn as degrees", () => {
    // 2π ≈ 6.28, so a whole number of 7 or more is past a full revolution and
    // nobody writes that in radians without a π.
    expect(assumeDegreesForBareTrig("sin(30) + cos(60)")).toBe(
      "sin((30 * pi / 180)) + cos((60 * pi / 180))",
    );
    expect(assumeDegreesForBareTrig("tan(45)")).toBe("tan((45 * pi / 180))");
  });

  it("leaves genuine radian arguments untouched", () => {
    for (const a of ["sin(1)", "cos(2)", "sin(0.5)", "sin(pi/6)", "cos(6)", "asin(30)"]) {
      expect(assumeDegreesForBareTrig(a), a).toBe(a);
    }
  });
});

describe("absolute value survives the round trip", () => {
  it("renders abs() back as bars", () => {
    // latexToAscii turns every |…| into abs(…) so mathjs can parse it; nothing
    // turned it back, so any modulus problem printed the function name.
    expect(asciiToLatex("abs(x + 1) = 3")).toBe("\\left|x + 1\\right| = 3");
    expect(asciiToLatex("abs(2x - 3)")).toBe("\\left|2x - 3\\right|");
  });

  it("drops the grouping bracket the ascii form needs", () => {
    // `5|x|` has to become `5(abs(x))` to keep its precedence; bars group on
    // their own, so the wrapper would print as stray brackets.
    expect(asciiToLatex("(abs(x - 4)) = 0")).toBe("\\left|x - 4\\right| = 0");
    expect(asciiToLatex("(abs(x)) + 1 = 4")).toBe("\\left|x\\right| + 1 = 4");
  });

  it("keeps a bracket that is not the wrapper", () => {
    expect(asciiToLatex("(abs(x) + 1) / 2")).toBe(
      "\\frac{\\left|x\\right| + 1}{2}"
    );
  });

  it("survives a round trip from the LaTeX a student writes", () => {
    expect(asciiToLatex(latexToAscii("|2x - 3| = 7"))).toBe(
      "\\left|2x - 3\\right| = 7"
    );
  });
});
