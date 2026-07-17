// Simultaneous LINEAR + QUADRATIC systems (2 variables) — the deterministic
// substitution path, plus the chained-equality split that feeds it (the exam
// form "2(x−y) = x+y−1 = 2x²−11y²" arrives as ONE statement with two '=').
//
// Golden rule: the composed polynomial's degree ≤ 2 is PROVEN by the sampling
// fit, every (x, y) pair is substitution-verified against BOTH original
// equations, and anything else (no real intersection, cubic composition, two
// quadratics) declines honestly.
import { describe, expect, it } from "vitest";

import { classify, equationParts } from "../src/solver/classify";
import { parseSimultaneous } from "../src/solver/simultaneous";
import { solve } from "../src/proxy/solve";
import { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("a simultaneous system is deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return {
    strategy: c.strategy,
    problemType: p.problemType,
    verified: p.verified,
    plain: p.finalAnswer?.plain,
    routeToTutor: p.routeToTutor === true,
  };
}

describe("equationParts — chained equality split", () => {
  it("splits A = B = C into {A = B, B = C}", () => {
    expect(equationParts("2x + 1 = x + 4 = 7")).toEqual([
      { lhs: "2x + 1", rhs: "x + 4" },
      { lhs: "x + 4", rhs: "7" },
    ]);
  });

  it("leaves a single equation untouched", () => {
    expect(equationParts("2x + 1 = 7")).toEqual([{ lhs: "2x + 1", rhs: "7" }]);
  });

  it("still splits a comma-separated system", () => {
    expect(equationParts("2x + 3y = 6, x - y = 3")).toEqual([
      { lhs: "2x + 3y", rhs: "6" },
      { lhs: "x - y", rhs: "3" },
    ]);
  });

  it("a degenerate empty segment falls back to the first-'=' behavior", () => {
    expect(equationParts("x = = 5")).toEqual([{ lhs: "x", rhs: "= 5" }]);
  });
});

describe("parseSimultaneous — detection", () => {
  it("accepts one linear + one quadratic member", () => {
    const sys = parseSimultaneous(
      [
        { lhs: "x^2 + y", rhs: "5" },
        { lhs: "x - y", rhs: "1" },
      ],
      ["x", "y"]
    );
    expect(sys).not.toBeNull();
    expect(sys!.vars).toEqual(["x", "y"]);
    // The linear member is x − y − 1 = 0 → cu = 1, cv = −1, k = −1.
    expect(sys!.cu).toBeCloseTo(1, 9);
    expect(sys!.cv).toBeCloseTo(-1, 9);
    expect(sys!.k).toBeCloseTo(-1, 9);
  });

  it("declines two quadratics (no linear member to substitute)", () => {
    expect(
      parseSimultaneous(
        [
          { lhs: "x^2 + y", rhs: "5" },
          { lhs: "y^2 + x", rhs: "5" },
        ],
        ["x", "y"]
      )
    ).toBeNull();
  });

  it("declines when both members are linear (linsystem owns that)", () => {
    expect(
      parseSimultaneous(
        [
          { lhs: "x + y", rhs: "5" },
          { lhs: "x - y", rhs: "1" },
        ],
        ["x", "y"]
      )
    ).toBeNull();
  });
});

describe("solve — linear+quadratic systems, deterministic + complete", () => {
  it("the scanned chained exam form: 2(x−y) = x+y−1 = 2x²−11y²", async () => {
    const r = await run(
      String.raw`\text{Solve the simultaneous equations: } 2(x-y) = x+y-1 = 2x^2-11y^2`
    );
    expect(r).toMatchObject({
      strategy: "simultaneous",
      problemType: "simultaneous_equations",
      verified: true,
      plain: "x = -1/7, y = 2/7 or x = 5, y = 2",
      routeToTutor: false,
    });
  });

  it("y = x² and y = x + 2 → BOTH intersection points, verified", async () => {
    const r = await run("\\begin{cases} y = x^2 \\\\ y = x + 2 \\end{cases}");
    expect(r.verified).toBe(true);
    expect(r.plain).toBe("x = -1, y = 1 or x = 2, y = 4");
  });

  it("a tangent line (repeated root) returns the single pair", async () => {
    // y = x² and y = 2x − 1 touch only at (1, 1).
    const r = await run("y = x^2 \\\\ y = 2x - 1");
    expect(r.verified).toBe(true);
    expect(r.plain).toBe("x = 1, y = 1");
  });

  it("irrational intersections keep the exact form", async () => {
    // x = y and x² + y² = 4 → x = y = ±√2.
    const r = await run("x = y \\\\ x^2 + y^2 = 4");
    expect(r.verified).toBe(true);
    expect(r.plain).toContain("√2");
  });

  it("no real intersection → the tutor invite, never a fake answer", async () => {
    // y = x² + 10 never meets y = x. "No solutions" can't be substitution-
    // verified, and a system the engine can't finish is still a SYSTEM —
    // exactly what the tutor route existed for before this strategy landed.
    const r = await run("y = x^2 + 10 \\\\ y = x");
    expect(r.verified).toBe(false);
    expect(r.plain).toBeUndefined();
    expect(r.routeToTutor).toBe(true);
    expect(r.problemType).toBe("system_of_equations");
  });

  it("a TINY cubic term (1e-7) cannot fake a complete quadratic answer", async () => {
    // The 5-point sampling fit alone accepts this and would ship 2 of the 3
    // real solutions as "the" verified answer; the symbolic third-derivative
    // proof rejects it exactly.
    const r = await run("y = x^2 + 0.0000001x^3 \\\\ x + y = 3");
    expect(r.strategy).toBe("simultaneous");
    expect(r.verified).toBe(false);
    expect(r.routeToTutor).toBe(true);
  });

  it("a reciprocal (pole at a probe) → tutor, not a bare couldn't-verify", async () => {
    // y = 12/x meets x + y = 8 at (2,6)/(6,2), but the composition has a pole
    // at the t=0 probe so the engine declines — the honest hand-off is the tutor.
    const r = await run("y = \\frac{12}{x} \\\\ x + y = 8");
    expect(r.verified).toBe(false);
    expect(r.routeToTutor).toBe(true);
  });

  it("huge coefficients cannot scale away a solution pair (completeness)", async () => {
    // Eliminating the 10⁶-coefficient variable shrinks the composed
    // quadratic's leading term to ~10⁻¹²; a naive |a| < ε "it's linear" call
    // would return ONE pair and silently drop the second real intersection.
    const r = await run("1000000x + y = 2000000 \\\\ y = x^2");
    expect(r.verified).toBe(true);
    expect(r.plain).toContain(" or "); // BOTH pairs, never a silent truncation
    expect(r.plain).toContain("x = -1000001.99"); // the true second root
  });

  it("a genuinely linear composition still yields its single pair", async () => {
    // x = 2 into x·y = 6 composes to a LINEAR 2y − 6 → exactly one pair.
    const r = await run("x = 2 \\\\ x y = 6");
    expect(r.verified).toBe(true);
    expect(r.plain).toBe("x = 2, y = 3");
  });

  it("a CUBIC composition fails the degree proof → tutor invite", async () => {
    const r = await run("y = x^3 \\\\ y = x + 1");
    expect(r.strategy).toBe("simultaneous");
    expect(r.verified).toBe(false);
    expect(r.routeToTutor).toBe(true);
  });

  it("two quadratics still route to the tutor with an honest problemType", async () => {
    const r = await run("x^2 + y = 5 \\\\ y^2 + x = 5");
    expect(r.verified).toBe(false);
    expect(r.routeToTutor).toBe(true);
    expect(r.problemType).toBe("system_of_equations");
  });
});
