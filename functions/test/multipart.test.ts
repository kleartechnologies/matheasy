import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { parseStatistics } from "../src/solver/statistics";
import { JsonCompleter } from "../src/solver/narrate";

/**
 * Golden-rule hardening for the full-text OCR change. Capturing the WHOLE
 * multi-line problem feeds prose + multi-part questions to the solver; an
 * adversarial sweep found 24 confident-WRONG answers (a statistics keyword
 * hijacking a calculus problem; the single-answer engines returning an
 * equation's ROOT for a question that asks a DERIVED quantity). These lock the
 * fix: such problems route to the tutor (or decline) — never a wrong answer —
 * while genuine single problems still solve.
 */

// A completer that must NOT be reached (routeToTutor short-circuits before any
// LLM call) — and a canned-candidate completer for the genuine-solve cases.
const NEVER: JsonCompleter = async () => {
  throw new Error("completer should not be called for a tutor-routed problem");
};
function completerWith(cand: Record<string, unknown>): JsonCompleter {
  return async (system: string) => (system.includes("ALREADY-SOLVED") ? {} : cand);
}

describe("statistics parser is strict — no calculus/word-problem hijack", () => {
  it("declines a calculus 'average/min/max/range value of f(x) on [a,b]'", () => {
    expect(parseStatistics("Find the average value of f(x) = x^2 on the interval [0, 6]")).toBeNull();
    expect(parseStatistics("Find the minimum value of f(x) = x^2 - 6x + 5 on [0, 5]")).toBeNull();
    expect(parseStatistics("Find the range of the function f(x) = x^2 on [-2, 3]")).toBeNull();
    expect(parseStatistics("Find the average rate of change of f(x) = x^3 on [1, 4]")).toBeNull();
  });
  it("declines a word problem that GIVES an average and asks something else", () => {
    expect(
      parseStatistics("The average of three numbers is 20. Two of them are 12, 15. Find the third number.")
    ).toBeNull();
  });
  it("still reads a genuine data-set query", () => {
    expect(parseStatistics("mean of 2, 4, 6, 8")).toEqual({ stat: "mean", data: [2, 4, 6, 8] });
    expect(parseStatistics("range of 10, 3, 7, 1")).toEqual({ stat: "range", data: [10, 3, 7, 1] });
    expect(parseStatistics("median(3, 1, 4, 1, 5)")).toEqual({ stat: "median", data: [3, 1, 4, 1, 5] });
  });
});

describe("solve — the calculus 'average value' no longer ships mean=3", () => {
  it("routes to the tutor instead of a confident wrong statistic", async () => {
    const p = await solve(
      classify("Find the average value of f(x) = x^2 on the interval [0, 6]"),
      completerWith({ answerLatex: "3", answerPlain: "3", solutions: [{ variable: "x", value: 3 }] })
    );
    expect(p.verified).toBe(false);
    expect(p.routeToTutor).toBe(true);
  });
});

describe("solve — multi-part / derived-question → tutor (not a wrong root)", () => {
  const tutorCases: [string, string][] = [
    ["given eqn, find x²", "\\begin{aligned} 2x + 5 = 15 \\\\ \\text{find } x^2 \\end{aligned}"],
    ["system, find xy", "\\begin{aligned} x + y = 10 \\\\ x - y = 4 \\\\ \\text{find } xy \\end{aligned}"],
    ["given, find 1/x", "\\text{Given } \\frac{1}{2}x + 3 = 8 \\\\ \\text{find } \\frac{1}{x}"],
    ["trig, find sin 2x", "\\begin{aligned} \\cos x = \\frac{3}{5} \\\\ \\text{find } \\sin 2x \\end{aligned}"],
    ["derived via '= ?'", "\\cos x = \\frac{3}{5} \\\\ \\sin 2x = ?"],
    ["sub-parts (i)(ii)", "\\text{Given } \\tan\\theta = 2 \\\\ \\text{(i) find } \\tan A \\\\ \\text{(ii) find } \\cos\\theta"],
    ["hence find the roots", "\\text{Consider } y=x^2-7x+12. \\\\ \\text{(i) Factorise.} \\\\ \\text{(ii) Hence find the roots.}"],
    ["reported f(x) problem", "\\text{f(x) is differentiable} \\\\ x f'(x) + f(x) = \\frac{d}{dx}(x^4 - x) \\\\ f'(2) = 10 \\\\ \\text{what is } f(-1)?"],
  ];
  for (const [name, latex] of tutorCases) {
    it(`${name} → routeToTutor`, async () => {
      // A WRONG candidate is offered; the tutor route must fire BEFORE any solve
      // so it can never be accepted.
      const p = await solve(
        classify(latex),
        completerWith({ answerLatex: "x = 5", answerPlain: "x = 5", solutions: [{ variable: "x", value: 5 }] })
      );
      expect(p.verified).toBe(false);
      expect(p.routeToTutor).toBe(true);
    });
  }
});

describe("integral with a leading coefficient/sign is not dropped", () => {
  it("-∫₀¹ x² dx verifies -1/3 and REJECTS +1/3", async () => {
    const neg = classify("-\\int_0^1 x^2 \\, dx");
    const good = await solve(neg, completerWith({ answerLatex: "-\\frac{1}{3}", answerPlain: "-0.3333333333" }));
    expect(good.verified).toBe(true);
    const bad = await solve(neg, completerWith({ answerLatex: "\\frac{1}{3}", answerPlain: "0.3333333333" }));
    expect(bad.verified).toBe(false); // the sign-wrong value must NOT verify
  });
  it("½∫₀² x² dx verifies 4/3, not the bare 8/3", async () => {
    const cls = classify("\\frac{1}{2}\\int_0^2 x^2 \\, dx");
    const good = await solve(cls, completerWith({ answerLatex: "\\frac{4}{3}", answerPlain: "1.3333333333" }));
    expect(good.verified).toBe(true);
    const bad = await solve(cls, completerWith({ answerLatex: "\\frac{8}{3}", answerPlain: "2.6666666667" }));
    expect(bad.verified).toBe(false);
  });
});

describe("solve — non-unique systems + merged/multi-question → tutor", () => {
  const cases: [string, string][] = [
    ["nonlinear system (2 solutions)", "\\begin{cases} y = x^2 \\\\ y = x + 2 \\end{cases}"],
    ["underdetermined system (3 unknowns, 2 eqns)", "\\begin{cases} x + y + z = 6 \\\\ x - y = 0 \\end{cases}"],
    ["merged trig 'given sin x=0.5, find cos x'", "\\sin x = 0.5 \\\\ \\cos x"],
    ["merged trig with newline", "\\sin x = 0.5\n\\cos x"],
    ["find 2x (derived coefficient·var)", "\\begin{aligned} 2x + 5 = 15 \\\\ \\text{find } 2x \\end{aligned}"],
    ["two-question word problem", "A rectangle is 8 cm by 5 cm. What is its area? What is its perimeter?"],
    ["find X and the Y", "A car goes 60 km/h for 2 h then 80 km/h for 3 h. Find the total distance and the average speed."],
    ["'as well as' connector", "A worker earns RM15 per hour and works 40 hours a week. Calculate her weekly wage as well as her yearly income over 52 weeks."],
    ["multi-step sequence", "\\text{Start with 5.} \\\\ \\text{Multiply by 3.} \\\\ \\text{Add 4.} \\\\ \\text{What is the result?}"],
    ["'then' sequencer", "\\text{Ravi has 20 marbles and gives 8 away.} \\\\ \\text{Find how many remain. Then double that count.}"],
    ["past-participle 2nd ask", "A projectile is launched at 20 m/s. Find the maximum height. Its total flight time should also be computed."],
    ["obtuse-angle constraint", "The obtuse angle x makes \\cos x = -\\frac{1}{2} true. Determine x."],
    ["acute-angle constraint", "The acute angle x satisfies 2\\sin x = 1. Determine x."],
    ["reflex-angle in words", "A rotating arm turns through a reflex angle x between \\pi and 2\\pi radians, where its tangent equals one. Find the angle x."],
    ["system + trailing x·y =", "\\begin{cases} 3x + 2y = 12 \\\\ x - y = 1 \\end{cases} \\\\ x \\cdot y ="],
    ["system + trailing x + y", "\\begin{cases} 5x - 2y = 16 \\\\ 3x + 2y = 16 \\end{cases} \\\\ x + y"],
  ];
  for (const [name, latex] of cases) {
    it(`${name} → routeToTutor`, async () => {
      const p = await solve(
        classify(latex),
        completerWith({ answerLatex: "x=2, y=4", answerPlain: "x=2, y=4", solutions: [{ variable: "x", value: 2 }, { variable: "y", value: 4 }] })
      );
      expect(p.verified).toBe(false);
      expect(p.routeToTutor).toBe(true);
    });
  }
});

describe("solve — reported scans: prose-labelled problems still solve", () => {
  // Regression: the OCR marks instructions with \text{…}. Unwrapping that into
  // the math made every prose letter a "variable" (S,o,l,v,e…), so a one-line
  // equation misread as a multi-variable system and routed to the tutor. The
  // prose must be DROPPED on the solving path (display keeps it).
  it("'Solve the algebraic equation. 3 − x − 2x² = 0' → the quadratic solves", async () => {
    const cls = classify("\\text{Solve the algebraic equation.} 3 - x - 2x^2 = 0");
    expect(cls.problemType).toBe("quadratic_equation");
    const p = await solve(cls, completerWith({}));
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = -3/2 or x = 1");
  });
  it("'iii. Simplify … (4x²+3/2y²)²' is directive+math, not a word problem", async () => {
    const cls = classify(
      "\\text{iii. Simplify the algebraic expression below} (4x^2 + \\frac{3}{2}y^2)^2"
    );
    expect(cls.problemType).toBe("expression");
    const p = await solve(cls, completerWith({}));
    expect(p.verified).toBe(true);
  });
  it("3x(x-1)/2 = x+6 — a variable before '(' is a product, not a function call", async () => {
    // mathjs read `x(x-1)` as calling a function x, so the correct roots were
    // rejected; latexToAscii now inserts the implicit '*'.
    const p = await solve(
      classify("\\frac{3x(x-1)}{2} = x + 6"),
      completerWith({
        answerLatex: "x=3",
        answerPlain: "x=3",
        solutions: [{ variable: "x", value: 3 }, { variable: "x", value: -1.3333333 }],
      })
    );
    expect(p.verified).toBe(true);
  });
  it("f(x) is still a function application, not f×(x)", () => {
    expect(classify("\\frac{d}{dx}(x^2)").problemType).toBe("derivative");
  });
  it("a bare '\\\\' row-break splits a two-line simultaneous system", async () => {
    // The OCR puts each line on its own row; the system used to run together
    // ("5x-2y=17 \\ 6x+2y=16") and fall through to the tutor.
    const cls = classify("5x - 2y = 17 \\\\ 6x + 2y = 16");
    expect(cls.problemType).toBe("linear_system");
    const p = await solve(cls, completerWith({}));
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = 3, y = -1");
  });
  it("simultaneous eqns with a prose directive + numbering still solve", async () => {
    const cls = classify(
      "\\text{Solve the following simultaneous equations.} \\\\ \\text{1.} 5x + 2y = 17 \\\\ 4x + y = 10"
    );
    expect(cls.problemType).toBe("linear_system");
    expect((await solve(cls, completerWith({}))).finalAnswer?.plain).toBe("x = 1, y = 6");
  });
  it("(x+1)² = 4(x+4) solves deterministically when mathsteps declines", async () => {
    // Falls back to the quadratic formula over sampled coefficients.
    const cls = classify("(x+1)^2 = 4(x+4)");
    expect(cls.problemType).toBe("quadratic_equation");
    const p = await solve(cls, NEVER);
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = -3 or x = 5");
  });
  it("the quadratic fallback keeps EXACT irrational roots (x²−2=0 → ±√2)", async () => {
    const p = await solve(classify("x^2 - 2 = 0"), NEVER);
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.latex).toContain("\\sqrt{2}");
    expect(p.finalAnswer?.latex).not.toMatch(/1\.414/);
  });
});

describe("solve — genuine single problems still solve (no over-routing)", () => {
  it("'Solve 2x+5=15' (leading directive stripped) → x=5", async () => {
    const p = await solve(classify("\\text{Solve } 2x + 5 = 15"), completerWith({}));
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = 5");
  });
  it("'find the roots of x²-5x+6=0' → the quadratic solves", async () => {
    const p = await solve(classify("\\text{find the roots of } x^2 - 5x + 6 = 0"), completerWith({}));
    expect(p.verified).toBe(true);
  });
  it("'find x: 2x+5=15' is a plain solve, not multi-part", async () => {
    const cls = classify("\\text{find } x: 2x + 5 = 15");
    expect(cls.problemType).not.toBe("multi_part");
    const p = await solve(cls, completerWith({}));
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = 5");
  });
  it("a Taylor SERIES request is not mistaken for a derived quantity", () => {
    expect(classify("Find the Taylor series of e^x about the point x=2 to order 3").problemType)
      .toBe("taylor_series");
  });
  it("a genuine data-set statistic still verifies", async () => {
    const p = await solve(classify("mean of 2, 4, 6, 8"), completerWith({}));
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("5");
  });
  it("a single equation with a trailing 'x =' answer blank still solves", async () => {
    // '5x = 20 \n x =' — the blank must not merge into the equation.
    const p = await solve(classify("5x = 20\nx ="), completerWith({}));
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = 4");
  });
  it("does not call the LLM for a tutor-routed problem", async () => {
    const p = await solve(classify("\\begin{aligned} 2x+5=15 \\\\ \\text{find } x^2 \\end{aligned}"), NEVER);
    expect(p.routeToTutor).toBe(true);
  });
});
