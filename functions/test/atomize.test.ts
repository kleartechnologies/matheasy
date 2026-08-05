import { describe, expect, it } from "vitest";
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
