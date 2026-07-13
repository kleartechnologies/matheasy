// Linear systems Ax = b — DETERMINISTIC via mathjs, proven by substitution
// (A·x = b, recomputed independently). Non-linear / non-square / singular systems
// decline honestly rather than reach the LLM tier with a guess.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { parseLinearSystem } from "../src/solver/linsystem";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("a linear system is deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { strategy: c.strategy, verified: p.verified, plain: p.finalAnswer?.plain };
}

describe("classify + solve — linear systems", () => {
  it("2×2 comma-separated", async () => {
    const r = await run(String.raw`2x + y = 5, x - y = 1`);
    expect(r).toMatchObject({ strategy: "linsystem", verified: true, plain: "x = 2, y = 1" });
  });

  it("2×2 in a cases environment", async () => {
    const r = await run(String.raw`\begin{cases} 2x + y = 5 \\ x - y = 1 \end{cases}`);
    expect(r).toMatchObject({ strategy: "linsystem", verified: true, plain: "x = 2, y = 1" });
  });

  it("2×2 in an aligned environment (& tabs)", async () => {
    const r = await run(String.raw`\begin{aligned} x + y &= 10 \\ x - y &= 2 \end{aligned}`);
    expect(r).toMatchObject({ verified: true, plain: "x = 6, y = 4" });
  });

  it("3×3 with a fractional solution", async () => {
    const r = await run(String.raw`x + y + z = 6, 2x - y + z = 3, x + 2y - z = 3`);
    expect(r).toMatchObject({ strategy: "linsystem", verified: true, plain: "x = 9/7, y = 15/7, z = 18/7" });
  });

  it("declines a singular system (no unique solution)", async () => {
    // x + y = 3 and 2x + 2y = 6 are dependent → det = 0.
    const r = await run(String.raw`x + y = 3, 2x + 2y = 6`);
    expect(r.verified).toBe(false);
  });

  it("a non-linear system is not routed to the deterministic path", () => {
    expect(classify(String.raw`x^2 + y = 5, x - y = 1`).strategy).not.toBe("linsystem");
  });

  it("a single equation is not a system", () => {
    expect(classify(String.raw`2x + 5 = 15`).strategy).not.toBe("linsystem");
  });
});

describe("parseLinearSystem — unit", () => {
  it("reads coefficients + RHS without string parsing", () => {
    const sys = parseLinearSystem(
      [
        { lhs: "2x + y", rhs: "5" },
        { lhs: "x - y", rhs: "1" },
      ],
      ["x", "y"]
    );
    expect(sys).toEqual({ a: [[2, 1], [1, -1]], b: [5, 1], vars: ["x", "y"] });
  });

  it("declines a non-square system", () => {
    expect(
      parseLinearSystem([{ lhs: "x + y", rhs: "1" }], ["x", "y"])
    ).toBeNull();
  });

  it("declines a non-linear equation", () => {
    expect(
      parseLinearSystem(
        [
          { lhs: "x^2 + y", rhs: "5" },
          { lhs: "x - y", rhs: "1" },
        ],
        ["x", "y"]
      )
    ).toBeNull();
  });
});
