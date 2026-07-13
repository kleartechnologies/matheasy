// Partial derivatives — reuse the DETERMINISTIC derivative path: mathjs
// `derivative(f, v)` differentiates w.r.t. v holding every other symbol constant
// (that IS the partial), and verifyDerivative samples all free variables, so a
// partial verifies exactly like a single-variable derivative. Only classify's
// operator recognition (∂/∂x, \partial, ∂_x) is new.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("a bare partial derivative is deterministic — no LLM");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return {
    type: c.problemType,
    strategy: c.strategy,
    unknown: c.unknown,
    verified: p.verified,
    plain: p.finalAnswer?.plain,
  };
}

describe("classify + solve — partial derivatives", () => {
  it("∂/∂x (x² y + y³) = 2xy", async () => {
    const r = await run(String.raw`\frac{\partial}{\partial x}(x^2 y + y^3)`);
    expect(r).toMatchObject({
      type: "partial_derivative",
      strategy: "derivative",
      unknown: "x",
      verified: true,
    });
    expect(r.plain?.replace(/\s/g, "")).toBe("2*y*x".replace(/\s/g, ""));
  });

  it("∂/∂y (x² y + y³) = x² + 3y²", async () => {
    const r = await run(String.raw`\frac{\partial}{\partial y}(x^2 y + y^3)`);
    expect(r).toMatchObject({ unknown: "y", verified: true });
    expect(r.plain?.replace(/\s/g, "")).toBe("x^2+3*y^2".replace(/\s/g, ""));
  });

  it("∂_x notation (x² + 3xy) = 2x + 3y", async () => {
    const r = await run(String.raw`\partial_x (x^2 + 3 x y)`);
    expect(r).toMatchObject({ type: "partial_derivative", unknown: "x", verified: true });
  });

  it("∂/∂x sin(xy) = y·cos(xy)", async () => {
    const r = await run(String.raw`\frac{\partial}{\partial x}(\sin(x y))`);
    expect(r.verified).toBe(true);
    expect(r.plain?.replace(/\s/g, "")).toContain("cos");
  });

  it("an ordinary d/dx is still a plain derivative (not partial)", async () => {
    const r = await run(String.raw`\frac{d}{dx}(x^2)`);
    expect(r).toMatchObject({ type: "derivative", verified: true });
  });
});
