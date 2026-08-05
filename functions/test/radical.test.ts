import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solveDeterministic } from "../src/solver/deterministic";
import type { RawMethod } from "../src/solver/types";

function solve(latex: string) {
  const c = solveDeterministic(classify(latex));
  expect(c, `no candidate for ${latex}`).not.toBeNull();
  expect(c!.verify(), `verify failed for ${latex}`).toBe(true);
  const m = c!.methods.find((x) => x.examPick) ?? c!.methods[0];
  return { method: m, candidate: c! };
}

const codes = (m: RawMethod) => m.steps.map((s) => s.operationCode);
const asciis = (m: RawMethod) => m.steps.map((s) => s.ascii);

describe("radical equations — squaring invents roots, so every root is checked", () => {
  it("walks the whole method for the equation that had no engine at all", () => {
    // The problem from the competitor comparison. Before this engine existed it
    // returned no deterministic candidate.
    const { method, candidate } = solve("x - 1 = \\sqrt{x+1}");
    expect(candidate.answer.plain).toBe("x = 3");
    expect(codes(method)).toEqual([
      "GIVEN",
      "ISOLATE_RADICAL",
      "SQUARE_BOTH_SIDES",
      "RADICAL_CANCELS",
      "EXPAND_SQUARE",
      "COLLECT_TERMS",
      // The atomic step engine refines this method's FACTORISE like any other:
      // the quadratic reaches it through the candidate, so the sum-product
      // reasoning appears here too.
      "FIND_FACTOR_PAIR",
      "WRITE_FACTORS",
      "ZERO_PRODUCT",
      "CANDIDATE_ROOTS",
      "CHECK_REJECTS_ROOT",
      "CHECK_KEEPS_ROOT",
      "FIND_ROOTS",
    ]);
    expect(asciis(method)).toEqual([
      "x - 1 = sqrt(x+1)",
      "sqrt(x + 1) = x - 1",
      "(sqrt(x + 1))^2 = (x - 1)^2",
      "x + 1 = (x - 1)^2",
      "x + 1 = x^2 - 2*x + 1",
      "x^2 - 3*x = 0",
      "0 * (-3) = 0, 0 + (-3) = -3",
      "x*(x - 3) = 0",
      "x = 0 or x - 3 = 0",
      "x = [0, 3]",
      "0 - 1 = sqrt(0 + 1)",
      "3 - 1 = sqrt(3 + 1)",
      "x = [3]",
    ]);
  });

  it("names the rejected root as extraneous, in the step itself", () => {
    const { method } = solve("x - 1 = \\sqrt{x+1}");
    const rejected = method.steps.find(
      (s) => s.operationCode === "CHECK_REJECTS_ROOT"
    );
    expect(rejected!.latex).toContain("extraneous");
    expect(rejected!.latex).toContain("\\ne");
  });

  it("expanding and collecting stay two separate changes", () => {
    // The brief is explicit: a student shown only `x^2 - 3x = 0` has to expand
    // the bracket in their head.
    const { method } = solve("\\sqrt{3x - 2} = x - 2");
    const i = codes(method).indexOf("EXPAND_SQUARE");
    expect(i).toBeGreaterThan(0);
    expect(method.steps[i].ascii).toBe("3 x - 2 = x^2 - 4*x + 4");
    expect(method.steps[i + 1].ascii).toBe("x^2 - 7*x + 6 = 0");
  });

  it("collects with a positive leading coefficient", () => {
    // `x + 1 = (x-1)^2` collects naturally to `-x^2 + 3x = 0`, which no
    // worksheet writes.
    for (const p of ["x - 1 = \\sqrt{x+1}", "\\sqrt{x+4} + 2 = x"]) {
      const { method } = solve(p);
      const collected = method.steps.find(
        (s) => s.operationCode === "COLLECT_TERMS"
      );
      expect(collected!.ascii.startsWith("-"), p).toBe(false);
    }
  });

  it("isolates the radical before squaring, including a coefficient", () => {
    expect(solve("2\\sqrt{x} = 6").method.steps[1].ascii).toBe("sqrt(x) = 3");
    expect(solve("\\sqrt{x+4} + 2 = x").method.steps[1].ascii).toBe(
      "sqrt(x + 4) = x - 2"
    );
  });

  it("solves the plain shapes with no root to reject", () => {
    expect(solve("\\sqrt{2x+3} = 5").candidate.answer.plain).toBe("x = 11");
    expect(solve("\\sqrt{x} = 4").candidate.answer.plain).toBe("x = 16");
    for (const p of ["\\sqrt{2x+3} = 5", "\\sqrt{x} = 4"]) {
      expect(codes(solve(p).method)).toContain("CHECK_KEEPS_ROOT");
      expect(codes(solve(p).method)).not.toContain("CHECK_REJECTS_ROOT");
    }
  });

  it("declines when nothing survives the check", () => {
    // A square root is never negative, so `sqrt(x) = -2` has no solution — and
    // "no solution" has no shipped answer shape. Declining reaches the honest
    // couldn't-verify state instead of inventing x = 4.
    expect(solveDeterministic(classify("\\sqrt{x} = -2"))).toBeNull();
  });

  it("declines two radicals rather than square once and be wrong", () => {
    expect(
      solveDeterministic(classify("\\sqrt{x} + \\sqrt{x+1} = 5"))
    ).toBeNull();
  });

  it("declines when the radical's coefficient holds the unknown", () => {
    // `x·sqrt(x) = 8` is linear in the radical, but its coefficient is not
    // constant, so `sqrt(x) = 8/x` is not an isolation a student should be shown.
    const c = solveDeterministic(classify("x\\sqrt{x} = 8"));
    if (c) expect(codes(c.methods[0])).not.toContain("ISOLATE_RADICAL");
  });
});

describe("absolute-value equations — two cases, then the same check", () => {
  it("splits into cases and keeps both roots", () => {
    const { method, candidate } = solve("|2x - 3| = 7");
    expect(candidate.answer.plain).toBe("x = -2 or x = 5");
    expect(codes(method)).toEqual([
      "GIVEN",
      "ISOLATE_ABSOLUTE",
      "ABSOLUTE_CASES",
      "CASE_POSITIVE",
      "CASE_NEGATIVE",
      "CANDIDATE_ROOTS",
      "CHECK_KEEPS_ROOT",
      "CHECK_KEEPS_ROOT",
      "FIND_ROOTS",
    ]);
    expect(method.steps[2].ascii).toBe("2 x - 3 = 7 or 2 x - 3 = -(7)");
  });

  it("isolates the modulus first", () => {
    const { method, candidate } = solve("|x| + 1 = 4");
    expect(method.steps[1].ascii).toBe("abs(x) = 3");
    expect(candidate.answer.plain).toBe("x = -3 or x = 3");
  });

  it("handles a right side that holds the unknown", () => {
    // This is why the check is not optional for moduli either: a case can
    // produce a root the modulus never had.
    expect(solve("|2x - 3| = x").candidate.answer.plain).toBe(
      "x = 1 or x = 3"
    );
  });

  it("does not invent a second case when the modulus is zero", () => {
    const { method, candidate } = solve("|x - 4| = 0");
    expect(candidate.answer.plain).toBe("x = 4");
    expect(codes(method)).toEqual([
      "GIVEN",
      "ISOLATE_ABSOLUTE",
      "ZERO_MODULUS",
      "CANDIDATE_ROOTS",
      "CHECK_KEEPS_ROOT",
      "FIND_ROOTS",
    ]);
  });
});

describe("radical + modulus methods never leak source syntax", () => {
  it("prints bars and roots, not function names or arrays", () => {
    for (const p of [
      "x - 1 = \\sqrt{x+1}",
      "\\sqrt{x+4} + 2 = x",
      "|2x - 3| = 7",
      "|x| + 1 = 4",
      "|x - 4| = 0",
    ]) {
      for (const s of solve(p).method.steps) {
        const shown = s.latex ?? "";
        expect(shown, `${p} / ${s.operationCode}`).not.toContain("abs(");
        expect(shown, `${p} / ${s.operationCode}`).not.toContain("[");
        // `\text{or}` is prose and typesets correctly; a bare `or` in math mode
        // renders as three italic variables.
        const maths = shown.replace(/\\text\{[^{}]*\}/g, "");
        expect(maths, `${p} / ${s.operationCode}`).not.toMatch(/\bor\b/);
      }
    }
  });
});

describe("the new tiers do not disturb the equations that already worked", () => {
  it("leaves mathsteps and the factoring engine alone", () => {
    expect(solve("2x + 5 = 15").candidate.answer.plain).toBe("x = 5");
    expect(codes(solve("2x + 5 = 15").method)).not.toContain("GIVEN");
    expect(solve("x^2 - 5x + 6 = 0").candidate.answer.plain).toBe(
      "x = 2 or x = 3"
    );
    expect(codes(solve("x^2 - 5x + 6 = 0").method)[0]).toBe("START");
  });
});
