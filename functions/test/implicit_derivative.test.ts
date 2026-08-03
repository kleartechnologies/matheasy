// Implicit differentiation — a curve given as a RELATION (`x² + xy + y² = 1`)
// rather than as `y = f(x)`. y is not a function of x there, so the whole family
// used to fall past the single-variable definition parse and route to the tutor.
//
// The answer is symbolic (`−F_x/F_y`), so the gate deliberately never touches
// F_x or F_y: it walks the curve numerically, bisecting `F(x, ·) = 0` for a
// point ON the curve and again at x ± h, and central-differences the branch.
// Only F is ever evaluated, so a mis-differentiation has nowhere to hide.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("implicit differentiation is deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { type: c.problemType, verified: p.verified, plain: p.finalAnswer?.plain };
}

describe("dy/dx from an implicit relation", () => {
  it("x² + xy + y² = 1 — the mixed term is what makes it implicit", async () => {
    const r = await run(
      String.raw`\text{The curve has equation } x^2 + xy + y^2 = 1 \text{. Find } \frac{dy}{dx}`
    );
    expect(r.type).toBe("implicit_derivative");
    expect(r.verified).toBe(true);
    // −(2x + y)/(x + 2y), however mathjs chooses to print it.
    expect(r.plain).toMatch(/2 \* x/);
  });

  it("the circle x² + y² = 25 gives −x/y", async () => {
    const r = await run(String.raw`\text{Find } \frac{dy}{dx} \text{ given } x^2 + y^2 = 25`);
    expect(r).toMatchObject({ type: "implicit_derivative", verified: true });
    expect(r.plain).toBe("dy/dx = -(x / y)");
  });

  it("the folium x³ + y³ = 3xy", async () => {
    const r = await run(
      String.raw`\text{Find } \frac{dy}{dx} \text{ for the curve } x^3 + y^3 = 3xy`
    );
    expect(r).toMatchObject({ type: "implicit_derivative", verified: true });
  });

  it("a transcendental relation — sin y + x² = y, with y on BOTH sides", async () => {
    const r = await run(String.raw`\text{Find } \frac{dy}{dx} \text{ where } \sin y + x^2 = y`);
    expect(r).toMatchObject({ type: "implicit_derivative", verified: true });
  });

  it("e^{xy} = x + y — the glued `xy` mathjs cannot read on its own", async () => {
    const r = await run(String.raw`\text{Find } \frac{dy}{dx} \text{ for } e^{xy} = x + y`);
    expect(r).toMatchObject({ type: "implicit_derivative", verified: true });
  });
});

describe("the gradient AT a stated point", () => {
  it("(3, 4) on x² + y² = 25 gives −3/4", async () => {
    const r = await run(
      String.raw`\text{Find } \frac{dy}{dx} \text{ for } x^2 + y^2 = 25 \text{ at the point } (3, 4)`
    );
    expect(r).toMatchObject({ type: "implicit_derivative", verified: true, plain: "-3/4" });
  });

  it("(3, -4) is the OTHER branch — same x, opposite gradient", async () => {
    const r = await run(
      String.raw`\text{Find } \frac{dy}{dx} \text{ for } x^2 + y^2 = 25 \text{ at the point } (3, -4)`
    );
    expect(r).toMatchObject({ verified: true, plain: "3/4" });
  });

  it("declines a point that is NOT on the curve rather than reporting a gradient", async () => {
    const r = await run(
      String.raw`\text{Find } \frac{dy}{dx} \text{ for } x^2 + y^2 = 25 \text{ at the point } (3, 1)`
    );
    expect(r.verified).not.toBe(true);
  });

  it("declines an x with no y — several branches cross it with different gradients", async () => {
    const r = await run(
      String.raw`\text{Find } \frac{dy}{dx} \text{ for } x^2 + y^2 = 25 \text{ at } x = 3`
    );
    expect(r.type).not.toBe("implicit_derivative");
  });
});

describe("no regression — an explicit definition keeps its own route", () => {
  it("y = ln(1+x²) is still a plain derivative", async () => {
    const r = await run(String.raw`\text{If } y = \ln(1+x^2) \text{, find } \frac{dy}{dx}`);
    expect(r).toMatchObject({ type: "derivative", verified: true });
  });

  it("a separable ODE is still an ODE, not a relation to differentiate", () => {
    const c = classify(String.raw`\text{Find the general solution of } \frac{dy}{dx} = \frac{x^2}{y}`);
    expect(c.problemType).toBe("differential_equation");
  });

  it("an integrating-factor ODE is still an ODE", () => {
    const c = classify(
      String.raw`\text{Solve } \frac{dy}{dx} + xy = x \text{ where } y(0) = 0`
    );
    expect(c.problemType).toBe("differential_equation");
  });
});
