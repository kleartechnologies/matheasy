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

describe("solveDeterministic — trig evaluation uses the unit the student meant", () => {
  it("answers a bare degree-valued trig expression in degrees", () => {
    // Previously `-1.940445`, marked verified: the substitution gate re-evaluates
    // under the same convention it was given, so it cannot catch a unit error.
    for (const [problem, answer] of [
      ["\\sin(30) + \\cos(60)", "1"],
      ["\\tan(45)", "1"],
      ["\\sin(90)", "1"],
    ] as const) {
      const { candidate } = det(problem);
      expect(candidate, problem).not.toBeNull();
      expect(candidate!.verify(), problem).toBe(true);
      expect(candidate!.answer.plain, problem).toBe(answer);
    }
  });

  it("solves the explicitly-marked degree form, which used to decline outright", () => {
    const { candidate } = det("\\sin 30^\\circ + \\cos 60^\\circ");
    expect(candidate).not.toBeNull();
    expect(candidate!.verify()).toBe(true);
    expect(candidate!.answer.plain).toBe("1");
  });

  it("keeps radians for arguments that are plainly radians", () => {
    expect(det("\\sin(\\pi/6)").candidate!.answer.plain).toBe("1/2");
    expect(det("\\cos(0)").candidate!.answer.plain).toBe("1");
    expect(det("\\sin(1)").candidate!.answer.plain).toBe("0.841471");
    expect(det("\\sin(0.5)").candidate!.answer.plain).toBe("0.479426");
  });
});

describe("solveDeterministic — decimals are answered in decimals", () => {
  it("answers in the notation the student wrote", () => {
    for (const [problem, answer] of [
      ["0.25 + 0.5", "0.75"], // was 3/4
      ["0.3 \\times 0.4", "0.12"], // was 3/25
      ["1.2 - 0.75", "0.45"], // was 9/20
      ["-1.2 + 0.5", "-0.7"],
      ["0.5 \\times 0.5 \\times 0.5", "0.125"],
    ] as const) {
      const { candidate } = det(problem);
      expect(candidate, problem).not.toBeNull();
      expect(candidate!.verify(), problem).toBe(true);
      expect(candidate!.answer.plain, problem).toBe(answer);
    }
  });

  it("built from the exact fraction, not from the float", () => {
    // 0.1 + 0.2 is 0.30000000000000004 in binary; reading `toString()` would
    // print all of it.
    expect(det("0.1 + 0.2").candidate!.answer.plain).toBe("0.3");
  });

  it("keeps the fraction when the decimal would recur", () => {
    // 0.333… has no exact decimal form, and an exact answer outranks matching
    // the student's notation.
    expect(det("0.1 \\div 0.3").candidate!.answer.plain).toBe("1/3");
    expect(det("1 \\div 0.6").candidate!.answer.plain).toBe("5/3");
  });

  it("leaves problems written as fractions alone", () => {
    expect(det("1/2 + 1/3").candidate!.answer.plain).toBe("5/6");
    expect(det("3/4").candidate!.answer.plain).toBe("3/4");
  });

  it("still prints whole results as whole numbers", () => {
    expect(det("4.8 \\div 0.6").candidate!.answer.plain).toBe("8");
    expect(det("2.5 + 1.5").candidate!.answer.plain).toBe("4");
  });
});

describe("solveDeterministic — irrational roots ship in exact surd form", () => {
  it("answers the flagged violations exactly", () => {
    // These used to print the float: -3.732051, 0.618034.
    expect(det("x^2 + 4x + 1 = 0").candidate!.answer.plain).toBe(
      "x = -2 - √3 or x = -2 + √3"
    );
    expect(det("x^2 + x - 1 = 0").candidate!.answer.plain).toBe(
      "x = (-1 - √5)/2 or x = (-1 + √5)/2"
    );
    expect(det("x^2 - 6x + 7 = 0").candidate!.answer.plain).toBe(
      "x = 3 - √2 or x = 3 + √2"
    );
    expect(det("2x^2 + 4x - 1 = 0").candidate!.answer.plain).toBe(
      "x = (-2 - √6)/2 or x = (-2 + √6)/2"
    );
  });

  it("shows the simplify-and-cancel work as separate steps", () => {
    // `(−4 ± √12)/2 → −2 ± √3` hides two moves; each now has its own line.
    const { candidate } = det("x^2 + 4x + 1 = 0");
    const m = candidate!.methods.find((x) => x.examPick) ?? candidate!.methods[0];
    const codes = m.steps.map((s) => s.operationCode);
    const i = codes.indexOf("SIMPLIFY_RADICAL");
    expect(i).toBeGreaterThan(0);
    expect(codes[i + 1]).toBe("CANCEL_COMMON_FACTOR");
    expect(m.steps[i].latex).toContain("2\\sqrt{3}");
    expect(m.steps[i + 1].latex).toContain("-2 \\pm \\sqrt{3}");
    // The payoff step agrees with the answer instead of rounding it away.
    expect(m.steps[codes.indexOf("FIND_ROOTS")].latex).toContain("\\sqrt{3}");
  });

  it("emits neither step when the discriminant is already square-free", () => {
    const { candidate } = det("x^2 + x - 1 = 0");
    const m = candidate!.methods.find((x) => x.examPick) ?? candidate!.methods[0];
    const codes = m.steps.map((s) => s.operationCode);
    expect(codes).not.toContain("SIMPLIFY_RADICAL");
    expect(codes).not.toContain("CANCEL_COMMON_FACTOR");
  });

  it("a radical equation that keeps ONE root of the pair still prints the surd", () => {
    // Sifting drops (1−√5)/2; the survivor must not fall back to 1.618034.
    const { candidate } = det("\\sqrt{x+1} = x");
    expect(candidate!.answer.plain).toBe("x = (1 + √5)/2");
    expect(candidate!.verify()).toBe(true);
  });

  it("an absolute value that splits into two quadratics gets surds from both", () => {
    const { candidate } = det("|x^2 - 2| = 1");
    expect(candidate!.answer.plain).toBe(
      "x = -√3 or x = -1 or x = 1 or x = √3"
    );
    expect(candidate!.verify()).toBe(true);
  });

  it("rational roots are untouched by the surd path", () => {
    expect(det("x^2 - 5x + 6 = 0").candidate!.answer.plain).toBe(
      "x = 2 or x = 3"
    );
    expect(det("(x+1)^2 = 4(x+4)").candidate!.answer.plain).toBe(
      "x = -3 or x = 5"
    );
  });
});
