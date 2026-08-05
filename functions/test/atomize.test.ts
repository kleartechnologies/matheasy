import { describe, expect, it } from "vitest";
import { evaluate } from "mathjs";
import { classify } from "../src/solver/classify";
import { solveDeterministic } from "../src/solver/deterministic";
import { atomizeMethod, type AtomizeContext } from "../src/solver/atomize";
import type { RawMethod } from "../src/solver/types";

/** The exam-pick method for a problem, as it ships. */
function pick(latex: string) {
  const cls = classify(latex);
  const c = solveDeterministic(cls);
  expect(c, `no candidate for ${latex}`).not.toBeNull();
  expect(c!.verify(), `verify failed for ${latex}`).toBe(true);
  const m = c!.methods.find((x) => x.examPick) ?? c!.methods[0];
  return { method: m, candidate: c! };
}

const codes = (m: RawMethod) => m.steps.map((s) => s.operationCode);

describe("atomize — factorable quadratics gain the skipped reasoning", () => {
  it("monic: shows the sum-product pair, the factors, and the two cases", () => {
    const { method } = pick("x^2 - 5x + 6 = 0");
    expect(codes(method)).toEqual([
      "START",
      "FIND_FACTOR_PAIR",
      "WRITE_FACTORS",
      "ZERO_PRODUCT",
      "FIND_ROOTS",
    ]);
    // The pair step must state the two facts that justify the choice.
    expect(method.steps[1].latex).toContain("= 6");
    expect(method.steps[1].latex).toContain("= -5");
    // The factored form is the ENGINE's, carried through byte-identical.
    expect(method.steps[2].ascii).toBe("(x - 2) * (x - 3) = 0");
  });

  it("non-monic: the trick moves to a*c and the middle term splits", () => {
    const { method } = pick("2x^2 - 7x + 3 = 0");
    expect(codes(method)).toEqual([
      "START",
      "SPLIT_MIDDLE_TERM",
      "WRITE_FACTORS",
      "ZERO_PRODUCT",
      "FIND_ROOTS",
    ]);
    // a*c = 2*3 = 6, and the pair must still add to b = -7.
    expect(method.steps[1].latex).toContain("= 6");
    expect(method.steps[1].latex).toContain("= -7");
  });

  it("difference of squares expands too", () => {
    const { method } = pick("x^2 - 4 = 0");
    expect(codes(method)).toContain("ZERO_PRODUCT");
    expect(method.steps[0].operationCode).toBe("START");
  });

  it("a repeated factor shows ONE case, not the same case twice", () => {
    const { method } = pick("x^2 - 2x + 1 = 0");
    const zp = method.steps.find((s) => s.operationCode === "ZERO_PRODUCT");
    expect(zp).toBeDefined();
    expect(zp!.ascii).toBe("x - 1 = 0");
  });
});

describe("atomize — display repair on the payoff step", () => {
  it("renders roots as an 'or', never mathsteps' array syntax", () => {
    for (const p of ["x^2 - 5x + 6 = 0", "x^2 - 4 = 0", "2x^2 - 7x + 3 = 0"]) {
      const { method } = pick(p);
      const last = method.steps[method.steps.length - 1];
      expect(last.operationCode).toBe("FIND_ROOTS");
      expect(last.latex, `${p} leaked array syntax`).not.toMatch(/[[\]]/);
      expect(last.latex).toContain("\\text{or}");
    }
  });

  it("keeps a root's exact form rather than a decimal", () => {
    const { method } = pick("2x^2 - 7x + 3 = 0");
    const last = method.steps[method.steps.length - 1];
    expect(last.latex).toContain("\\frac{1}{2}");
    expect(last.latex).not.toContain("0.5");
  });
});

describe("atomize — the chain gate rejects unsound expansions", () => {
  const ctx: AtomizeContext = {
    unknown: "x",
    originalAscii: "x^2 - 5x + 6 = 0",
    roots: [2, 3],
    quadratic: { a: 1, b: -5, c: 6 },
  };

  /** A method whose factored form is WRONG — the gate must refuse to refine it. */
  it("drops an expansion whose factors do not reproduce the problem", () => {
    const bad: RawMethod = {
      id: "factoring",
      name: "Factoring",
      examPick: true,
      steps: [
        // (x-1)(x-6) = x^2-7x+6 — agrees at NEITHER verified root.
        { ascii: "(x - 1) * (x - 6) = 0", operationCode: "FACTOR_SUM_PRODUCT_RULE" },
      ],
    };
    expect(atomizeMethod(bad, ctx).steps).toEqual(bad.steps);
  });

  it("drops an expansion whose factors vanish at the roots but change the equation", () => {
    // (x-2)(x-3)(x-9) shares both verified roots but is a DIFFERENT equation.
    // Root-only checking would accept this; proportional residuals reject it.
    const sneaky: RawMethod = {
      id: "factoring",
      name: "Factoring",
      examPick: true,
      steps: [
        {
          ascii: "(x - 2) * (x - 3) * (x - 9) = 0",
          operationCode: "FACTOR_SUM_PRODUCT_RULE",
        },
      ],
    };
    const out = atomizeMethod(sneaky, ctx);
    // It may not claim these are the factors of the ORIGINAL quadratic.
    expect(out.steps).toEqual(sneaky.steps);
  });

  it("checks a mid-method factorisation against the step it replaced, not itself", () => {
    // No START step here (a step precedes it), so the factored form's ONLY
    // equation check is against `prev`. A claim compared to itself would prove
    // nothing and let this bogus factorisation ship as taught reasoning.
    const m: RawMethod = {
      id: "factoring",
      name: "Factoring",
      examPick: true,
      steps: [
        { ascii: "x^2 - 5x + 6 = 0", operationCode: "SIMPLIFY_LEFT_SIDE" },
        // Shares both verified roots, but is NOT the same equation.
        {
          ascii: "(x - 2) * (x - 3) * (x - 9) = 0",
          operationCode: "FACTOR_SUM_PRODUCT_RULE",
        },
      ],
    };
    expect(codes(atomizeMethod(m, ctx))).toEqual([
      "SIMPLIFY_LEFT_SIDE",
      "FACTOR_SUM_PRODUCT_RULE",
    ]);
  });

  it("accepts a mid-method factorisation that IS equivalent to its predecessor", () => {
    const m: RawMethod = {
      id: "factoring",
      name: "Factoring",
      examPick: true,
      steps: [
        { ascii: "x^2 - 5x + 6 = 0", operationCode: "SIMPLIFY_LEFT_SIDE" },
        { ascii: "(x - 2) * (x - 3) = 0", operationCode: "FACTOR_SUM_PRODUCT_RULE" },
      ],
    };
    expect(codes(atomizeMethod(m, ctx))).toEqual([
      "SIMPLIFY_LEFT_SIDE",
      "FIND_FACTOR_PAIR",
      "WRITE_FACTORS",
    ]);
  });

  it("leaves a step alone when it has no expander", () => {
    const m: RawMethod = {
      id: "isolation",
      name: "Isolate",
      examPick: true,
      steps: [
        { ascii: "2x = 10", operationCode: "SIMPLIFY_ARITHMETIC" },
        { ascii: "x = 5", operationCode: "SIMPLIFY_FRACTION" },
      ],
    };
    expect(atomizeMethod(m, { ...ctx, roots: [5] })).toEqual(m);
  });

  it("never drops or invents a root in the zero-product split", () => {
    const m: RawMethod = {
      id: "factoring",
      name: "Factoring",
      examPick: true,
      steps: [
        { ascii: "(x - 2) * (x - 3) = 0", operationCode: "WRITE_FACTORS" },
        { ascii: "x = [2, 3]", operationCode: "FIND_ROOTS" },
      ],
    };
    // Verified roots that disagree with the factors ⇒ the split must not ship.
    const wrong = atomizeMethod(m, { ...ctx, roots: [2] });
    expect(codes(wrong)).toEqual(["WRITE_FACTORS", "FIND_ROOTS"]);
    // Agreeing roots ⇒ the split ships.
    expect(codes(atomizeMethod(m, ctx))).toEqual([
      "WRITE_FACTORS",
      "ZERO_PRODUCT",
      "FIND_ROOTS",
    ]);
  });
});

describe("atomize — calculus stops leaping over the rule", () => {
  it("names the product rule, differentiates each piece, then assembles", () => {
    const { method } = pick("\\frac{d}{dx}(x^3 \\sin(x))");
    expect(codes(method)).toEqual([
      "DIFFERENTIATE",
      "RULE_PRODUCT",
      "DIFFERENTIATE_PARTS",
      "APPLY_RULE",
      "RESULT",
    ]);
    // The rule itself is stated, not just applied silently.
    expect(method.steps[1].latex).toContain("(uv)' = u'v + uv'");
    expect(method.steps[1].ascii).toBe("u = x ^ 3, v = sin(x)");
    expect(method.steps[2].ascii).toBe("u' = 3 * x ^ 2, v' = cos(x)");
  });

  it("picks the quotient rule for a fraction and the chain rule for a composite", () => {
    const q = pick("\\frac{d}{dx}\\left(\\frac{x^2+1}{x-3}\\right)").method;
    expect(codes(q)).toContain("RULE_QUOTIENT");

    for (const p of [
      "\\frac{d}{dx}(\\sin(3x+1))",
      "\\frac{d}{dx}(\\sqrt{x^2+1})",
      "\\frac{d}{dx}(e^{2x})",
    ]) {
      expect(codes(pick(p).method), p).toContain("RULE_CHAIN");
    }
  });

  it("leaves a standard derivative alone — one honest step needs no splitting", () => {
    for (const p of ["\\frac{d}{dx}(x^3)", "\\frac{d}{dx}(\\sin(x))"]) {
      expect(codes(pick(p).method), p).toEqual(["DIFFERENTIATE", "RESULT"]);
    }
  });

  it("leaves a higher-order derivative alone — one rule can't land on it", () => {
    const { method } = pick("\\frac{d^2}{dx^2}(x^3 \\sin(x))");
    expect(codes(method)).toEqual(["DIFFERENTIATE", "RESULT"]);
  });

  it("reaches the calculus engines' own `dy/dx = …` step shape too", () => {
    const { method } = pick("Find the equation of the tangent to y = x^2 \\sin(x) at x = 1");
    expect(codes(method).slice(0, 5)).toEqual([
      "IDENTIFY_FUNCTION",
      "RULE_PRODUCT",
      "DIFFERENTIATE_PARTS",
      "APPLY_RULE",
      "DIFFERENTIATE",
    ]);
    // The assembled step keeps the label the engine gave it.
    expect(method.steps[3].ascii.startsWith("\\frac{dy}{dx} = ")).toBe(true);
    // …and the engine's own derivative is still what the rest of the method uses.
    expect(method.steps[4].ascii).toBe("\\frac{dy}{dx} = 2 * x * sin(x) + x ^ 2 * cos(x)");
  });

  it("drops the expansion when the parts are not really the function's pieces", () => {
    const ctx: AtomizeContext = { unknown: "x", originalAscii: "", roots: [] };
    const m: RawMethod = {
      id: "differentiate",
      name: "Differentiate",
      examPick: true,
      steps: [
        { ascii: "d/dx(x^2 sin(x))", operationCode: "DIFFERENTIATE" },
        // Not the derivative of the target — the product rule assembled from
        // x^2 and sin(x) can never land here.
        { ascii: "2 * x * cos(x)", operationCode: "RESULT" },
      ],
    };
    expect(codes(atomizeMethod(m, ctx))).toEqual(["DIFFERENTIATE", "RESULT"]);
  });
});

describe("atomize — arithmetic gets the lesson, not just the answer", () => {
  it("adding fractions goes through the common denominator", () => {
    const { method } = pick("\\frac{1}{2} + \\frac{1}{3}");
    expect(codes(method)).toEqual([
      "START",
      "COMMON_DENOMINATOR",
      "REWRITE_EQUIVALENT",
      "COMBINE_NUMERATORS",
      "COMPUTE",
    ]);
    expect(method.steps[1].latex).toContain("\\text{LCM}(2, 3) = 6");
    expect(method.steps[2].ascii).toBe("3/6 + 2/6");
  });

  it("skips the LCM step when the denominators already match, and simplifies at the end", () => {
    const { method } = pick("\\frac{2}{6} + \\frac{1}{6}");
    expect(codes(method)).toEqual([
      "START",
      "COMBINE_NUMERATORS",
      "ADD_NUMERATORS",
      "SIMPLIFY_FRACTION",
    ]);
    expect(method.steps[2].ascii).toBe("3/6");
  });

  it("dividing by a fraction shows the flip — the step students actually miss", () => {
    const { method } = pick("\\frac{2}{3} \\div \\frac{4}{9}");
    expect(codes(method)).toEqual([
      "START",
      "MULTIPLY_BY_RECIPROCAL",
      "MULTIPLY_FRACTIONS",
      "MULTIPLY_OUT",
      "SIMPLIFY_FRACTION",
    ]);
    expect(method.steps[1].ascii).toBe("2/3 * 9/4");
  });

  it("does one operation per step, in BIDMAS order", () => {
    const { method } = pick("2^3 + 4 \\times (7 - 5)");
    expect(codes(method)).toEqual([
      "START",
      "BRACKETS_FIRST",
      "INDICES",
      "MULTIPLY_DIVIDE",
      "COMPUTE",
    ]);
    expect(method.steps.map((s) => s.ascii)).toEqual([
      "2^3 + 4 * (7 - 5)",
      "2 ^ 3 + 4 * 2",
      "8 + 4 * 2",
      "8 + 8",
      "16",
    ]);
  });

  it("works left to right between operations of equal rank", () => {
    const { method } = pick("18 \\div 3 + 2 \\times 5");
    expect(method.steps.map((s) => s.ascii)).toEqual([
      "18 / 3 + 2 * 5",
      "6 + 2 * 5",
      "6 + 10",
      "16",
    ]);
  });

  it("leaves a single operation alone — there is no order to teach", () => {
    expect(codes(pick("3 + 4").method)).toEqual(["START", "COMPUTE"]);
  });

  it("hands decimals to their own lesson instead of the BIDMAS reducer", () => {
    // 0.25 + 0.5 is not an order-of-operations problem; the split below owns it.
    expect(codes(pick("0.25 + 0.5").method)).not.toContain("MULTIPLY_DIVIDE");
  });
});

describe("atomize — decimals become whole numbers you can actually add", () => {
  it("unequal places are lined up before anything is scaled", () => {
    const { method } = pick("0.25 + 0.5");
    expect(codes(method)).toEqual([
      "START",
      "ALIGN_DECIMALS",
      "SCALE_TO_WHOLE",
      "COMPUTE_WHOLE",
      "COMPUTE",
    ]);
    expect(method.steps[1].ascii).toBe("0.25 + 0.50");
    expect(method.steps[2].ascii).toBe("(25 + 50) / 100");
    expect(method.steps[3].ascii).toBe("75 / 100");
  });

  it("equal places skip the alignment — there is nothing to line up", () => {
    const { method } = pick("2.5 + 1.5");
    expect(codes(method)).toEqual([
      "START",
      "SCALE_TO_WHOLE",
      "COMPUTE_WHOLE",
      "COMPUTE",
    ]);
    expect(method.steps[1].ascii).toBe("(25 + 15) / 10");
  });

  it("subtraction pads the shorter side and keeps the sign", () => {
    const { method } = pick("1.2 - 0.75");
    expect(method.steps.map((s) => s.ascii)).toEqual([
      "1.2 - 0.75",
      "1.20 - 0.75",
      "(120 - 75) / 100",
      "45 / 100",
      "0.45",
    ]);
  });

  it("a whole number is padded like any other operand", () => {
    const { method } = pick("3 + 0.5");
    expect(method.steps[1].ascii).toBe("3.0 + 0.5");
  });

  it("multiplication scales by the TOTAL number of places, not the larger", () => {
    const { method } = pick("0.3 \\times 0.4");
    expect(codes(method)).toEqual([
      "START",
      "SCALE_TO_WHOLE",
      "COMPUTE_WHOLE",
      "COMPUTE",
    ]);
    // One place each → divide by 100, not by 10. Getting this wrong is the
    // classic decimal-multiplication mistake, so the step has to show it.
    expect(method.steps[1].ascii).toBe("(3 * 4) / 100");
  });

  it("division scales BOTH sides, so the quotient is untouched", () => {
    const { method } = pick("4.8 \\div 0.6");
    expect(codes(method)).toEqual(["START", "SCALE_TO_WHOLE", "COMPUTE"]);
    expect(method.steps[1].ascii).toBe("48 / 6");
  });

  it("never restates the answer it has already reached", () => {
    // 0.1 / 0.3 recurs, so the answer stays the fraction 1/3 — and scaling both
    // sides reaches exactly `1 / 3`. Printing both would show the student a step
    // where nothing changed, so the whole expansion is dropped instead.
    const { method } = pick("0.1 \\div 0.3");
    expect(method.steps.map((s) => s.ascii)).toEqual(["0.1 / 0.3", "1/3"]);
  });

  it("every printed line still equals the problem it came from", () => {
    const { method } = pick("1.2 - 0.75");
    const target = evaluate("1.2 - 0.75");
    for (const step of method.steps) {
      expect(evaluate(step.ascii), step.ascii).toBeCloseTo(target, 10);
    }
  });

  it("declines whole numbers — that is the order-of-operations lesson", () => {
    expect(codes(pick("18 / 3 + 2 \\times 5").method)).toContain(
      "MULTIPLY_DIVIDE",
    );
  });
});

describe("atomize — statistics shows the calculation, not just the statistic", () => {
  it("mean: adds up, then divides by the count", () => {
    const { method } = pick("Find the mean of 4, 8, 15, 16, 23, 42");
    expect(codes(method)).toEqual([
      "START",
      "COMPUTE",
      "ADD_VALUES",
      "DIVIDE_BY_COUNT",
      "RESULT",
    ]);
    expect(method.steps[2].ascii).toBe("4 + 8 + 15 + 16 + 23 + 42 = 108");
    expect(method.steps[3].ascii).toBe("108 / 6 = 18");
  });

  it("standard deviation: the whole textbook route, one stage per step", () => {
    const { method } = pick("Find the standard deviation of 2, 4, 4, 4, 5, 5, 7, 9");
    expect(codes(method)).toEqual([
      "START",
      "COMPUTE",
      "ADD_VALUES",
      "DIVIDE_BY_COUNT",
      "DEVIATIONS",
      "SQUARE_DEVIATIONS",
      "SUM_SQUARES",
      "DIVIDE_BY_COUNT",
      "SQUARE_ROOT",
      "RESULT",
    ]);
    expect(method.steps[4].ascii).toBe("-3, -1, -1, -1, 0, 0, 2, 4");
    expect(method.steps[5].ascii).toBe("9, 1, 1, 1, 0, 0, 4, 16");
    expect(method.steps[8].ascii).toBe("sqrt(4) = 2");
  });

  it("variance stops one step earlier — no square root to take", () => {
    const { method } = pick("Find the variance of 2, 4, 4, 4, 5, 5, 7, 9");
    expect(codes(method)).not.toContain("SQUARE_ROOT");
    expect(codes(method).slice(-2)).toEqual(["DIVIDE_BY_COUNT", "RESULT"]);
  });

  it("median: sorts first, then averages the middle pair when n is even", () => {
    const { method } = pick("Find the median of 2, 4, 4, 4, 5, 5, 7, 9");
    expect(codes(method)).toEqual(["START", "COMPUTE", "SORT_DATA", "PICK_MIDDLE", "RESULT"]);
    expect(method.steps[2].ascii).toBe("2, 4, 4, 4, 5, 5, 7, 9");
    expect(method.steps[3].ascii).toBe("(4 + 5) / 2 = 4.5");
  });

  it("median: odd n locates the middle position rather than averaging", () => {
    const { method } = pick("Find the median of 3, 9, 1, 7, 5");
    expect(codes(method)).toEqual(["START", "COMPUTE", "SORT_DATA", "PICK_MIDDLE", "RESULT"]);
    // Sorting is the point of the lesson — the unsorted data must not survive it.
    expect(method.steps[2].ascii).toBe("1, 3, 5, 7, 9");
    expect(method.steps[3].ascii).toBe("(5 + 1) / 2 = 3");
  });

  it("range: names the two extremes before subtracting them", () => {
    const { method } = pick("Find the range of 12, 5, 19, 3");
    expect(codes(method)).toEqual([
      "START",
      "COMPUTE",
      "FIND_EXTREMES",
      "SUBTRACT_EXTREMES",
      "RESULT",
    ]);
    expect(method.steps[3].ascii).toBe("19 - 3 = 16");
  });

  it("mode has no arithmetic to show, so it ships as it arrived", () => {
    // The answer is a set, not a value; the identity machinery has nothing to
    // prove and must decline rather than invent a plausible-looking split.
    expect(codes(pick("Find the mode of 2, 3, 3, 5").method)).toEqual([
      "START",
      "COMPUTE",
      "RESULT",
    ]);
  });

  it("every printed arithmetic line is true as printed", () => {
    for (const p of [
      "Find the mean of 1, 2, 4",
      "Find the standard deviation of 10, 12, 23, 23, 16, 23, 21, 16",
      "Find the sum of 3, 7, 11",
    ]) {
      for (const s of pick(p).method.steps) {
        const i = s.ascii.indexOf("=");
        // Only the computed lines carry an `=`; labels and lists are exempt.
        if (i === -1 || !/^[-\d\s+*/().sqrt]+$/.test(s.ascii)) continue;
        expect(evaluate(s.ascii.slice(0, i)), `${p} :: ${s.ascii}`).toBeCloseTo(
          evaluate(s.ascii.slice(i + 1)),
          9,
        );
      }
    }
  });
});

describe("atomize — matrices show the row-by-column work", () => {
  it("product: one step per entry, and the second matrix finally appears", () => {
    const { method } = pick(
      "\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix} \\begin{pmatrix}5&6\\\\7&8\\end{pmatrix}",
    );
    expect(codes(method)).toEqual([
      "START",
      "SECOND_MATRIX",
      "ENTRY_ROW_BY_COLUMN",
      "ENTRY_ROW_BY_COLUMN",
      "ENTRY_ROW_BY_COLUMN",
      "ENTRY_ROW_BY_COLUMN",
      "RESULT",
    ]);
    // B is an operand the coarse steps never showed at all.
    expect(method.steps[1].latex).toContain("B = ");
    expect(method.steps[2].ascii).toBe("1 * 5 + 2 * 7 = 19");
    expect(method.steps[5].ascii).toBe("3 * 6 + 4 * 8 = 50");
  });

  it("2x2 determinant: the cross-multiplication is written out", () => {
    const { method } = pick("Find the determinant of \\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}");
    expect(codes(method)).toEqual(["START", "CROSS_MULTIPLY", "RESULT"]);
    expect(method.steps[1].ascii).toBe("1 * 4 - 2 * 3 = -2");
  });

  it("3x3 determinant: each minor is its own step before the expansion", () => {
    const { method } = pick(
      "Find the determinant of \\begin{pmatrix}1&2&3\\\\4&5&6\\\\7&8&10\\end{pmatrix}",
    );
    expect(codes(method)).toEqual([
      "START",
      "MINOR",
      "MINOR",
      "MINOR",
      "COFACTOR_EXPANSION",
      "RESULT",
    ]);
    expect(method.steps[1].ascii).toBe("5 * 10 - 6 * 8 = 2");
    // The alternating signs are visible, not folded into the arithmetic.
    expect(method.steps[4].ascii).toBe("1 * 2 - 2 * (-2) + 3 * (-3) = -3");
  });

  it("2x2 inverse: determinant, adjugate, then divide entry by entry", () => {
    const { method } = pick("Find the inverse of \\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}");
    expect(codes(method)).toEqual([
      "START",
      "CROSS_MULTIPLY",
      "ADJUGATE",
      "DIVIDE_BY_DET",
      "DIVIDE_BY_DET",
      "DIVIDE_BY_DET",
      "DIVIDE_BY_DET",
      "RESULT",
    ]);
    expect(method.steps[2].ascii).toBe("4, -2; -3, 1");
    expect(method.steps[3].ascii).toBe("4 / (-2) = -2");
  });

  it("sum: negatives are bracketed so the line still reads as arithmetic", () => {
    const { method } = pick(
      "\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix} + \\begin{pmatrix}5&-6\\\\7&8\\end{pmatrix}",
    );
    expect(codes(method).filter((c) => c === "COMBINE_ENTRY")).toHaveLength(4);
    expect(method.steps[3].ascii).toBe("2 + (-6) = -4");
  });

  it("trace adds the diagonal; transpose has no arithmetic and ships as it was", () => {
    expect(codes(pick("Find the trace of \\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}").method)).toEqual([
      "START",
      "SUM_DIAGONAL",
      "RESULT",
    ]);
    expect(
      codes(pick("Find the transpose of \\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}").method),
    ).toEqual(["START", "RESULT"]);
  });

  it("every entry line is true as printed, and lands on the shipped answer", () => {
    for (const p of [
      "\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix} \\begin{pmatrix}5&6\\\\7&8\\end{pmatrix}",
      "Find the determinant of \\begin{pmatrix}2&-1&0\\\\3&5&4\\\\-2&1&7\\end{pmatrix}",
      "Find the inverse of \\begin{pmatrix}4&7\\\\2&6\\end{pmatrix}",
    ]) {
      const { method, candidate } = pick(p);
      for (const s of method.steps) {
        const i = s.ascii.indexOf("=");
        if (i === -1 || !/^[-\d\s+*/().]+$/.test(s.ascii)) continue;
        expect(evaluate(s.ascii.slice(0, i)), `${p} :: ${s.ascii}`).toBeCloseTo(
          evaluate(s.ascii.slice(i + 1)),
          9,
        );
      }
      // The refined walkthrough still ends exactly where the engine put it.
      const last = method.steps[method.steps.length - 1];
      expect(last.operationCode).toBe("RESULT");
      expect(last.ascii).toContain(candidate.answer.latex);
    }
  });
});

describe("atomize — refinement never costs correctness", () => {
  it("leaves the verified answer and the engine's own expressions untouched", () => {
    for (const p of ["x^2 - 5x + 6 = 0", "2x^2 - 7x + 3 = 0", "2x + 5 = 15"]) {
      const { method, candidate } = pick(p);
      expect(candidate.verify()).toBe(true);
      // The final step still lands where the engine put it.
      const last = method.steps[method.steps.length - 1];
      expect(last.ascii).toMatch(/^x =/);
    }
  });

  it("linear isolation is already atomic and is not touched", () => {
    const { method } = pick("3(x+2) - 4 = 2(x-1) + 9");
    expect(method.steps).toHaveLength(8);
    expect(codes(method)).not.toContain("START");
  });
});
