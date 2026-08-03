// Sheet 3.9 — the gradient of a POLAR curve. `r = f(θ)` is defined in one pair
// of coordinates and asked about in another, so it could never satisfy the
// single-variable definition parse the rest of the calculus engine uses.
//
// The gate is a finite difference of x(θ) = r cos θ and y(θ) = r sin θ taken
// directly, then divided — it never touches the chain-rule formula the answer
// comes from, so a slipped sign has nowhere to hide.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("the polar gradient is deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { type: c.problemType, verified: p.verified, plain: p.finalAnswer?.plain };
}

describe("dy/dx along a polar curve", () => {
  it("Oxford 3.9 — r = 1 + sin²θ at θ = π/4 gives exactly -5", async () => {
    // r = 3/2, r′ = sin 2θ = 1 there, so
    // dy/dx = (1·sin45 + 1.5·cos45)/(1·cos45 − 1.5·sin45) = 2.5/(−0.5) = −5.
    const r = await run(
      String.raw`\text{Given } r = 1 + \sin^2\theta \text{, find } \frac{dy}{dx} \text{ at } \theta = \frac{\pi}{4}`
    );
    expect(r).toMatchObject({ type: "polar_gradient", verified: true });
    expect(r.plain).toContain("dy/dx = -5");
  });

  it("the circle r = 2 cos θ has a horizontal tangent at θ = π/4", async () => {
    // r = 2cosθ is the circle (x−1)² + y² = 1; at θ = π/4 the point is (1,1),
    // the top of the circle, so the tangent is horizontal.
    const r = await run(
      String.raw`\text{For the polar curve } r = 2\cos\theta \text{, find the gradient } \frac{dy}{dx} \text{ at } \theta = \frac{\pi}{4}`
    );
    expect(r.verified).toBe(true);
    expect(r.plain).toContain("dy/dx = 0");
  });

  it("the cardioid r = 1 + cos θ at θ = π/2", async () => {
    // r = 1, r′ = −1: dy/dx = (−1·1 + 1·0)/(−1·0 − 1·1) = 1.
    const r = await run(
      String.raw`\text{Find } \frac{dy}{dx} \text{ for } r = 1 + \cos\theta \text{ at } \theta = \frac{\pi}{2}`
    );
    expect(r.verified).toBe(true);
    expect(r.plain).toContain("dy/dx = 1");
  });

  it("with no angle given, the answer is the expression in θ", async () => {
    const r = await run(
      String.raw`\text{Find the gradient } \frac{dy}{dx} \text{ of the polar curve } r = 1 + \cos\theta`
    );
    expect(r).toMatchObject({ type: "polar_gradient", verified: true });
    expect(r.plain).toContain("dy/dx =");
  });
});

describe("what the polar branch refuses", () => {
  it("a VERTICAL tangent has no gradient — decline, never ∞", async () => {
    // r = 1 + cos θ at θ = 0 is the cusp-facing point where dx/dθ = 0.
    const r = await run(
      String.raw`\text{Find } \frac{dy}{dx} \text{ for } r = 1 + \cos\theta \text{ at } \theta = 0`
    );
    expect(r.verified).not.toBe(true);
  });

  it("dr/dθ is an ORDINARY derivative and is not annexed", () => {
    const c = classify(
      String.raw`\text{Given } r = 1 + \sin^2\theta \text{, find } \frac{dr}{d\theta}`
    );
    expect(c.problemType).not.toBe("polar_gradient");
  });

  it("an r that does not depend on θ is a circle, not a polar gradient", () => {
    const c = classify(String.raw`\text{Given } r = 3 \text{, find } \frac{dy}{dx} \text{ at } \theta = 1`);
    expect(c.problemType).not.toBe("polar_gradient");
  });

  it("a free parameter makes it a family, not an answer", () => {
    const c = classify(
      String.raw`\text{Given } r = a(1 + \cos\theta) \text{, find } \frac{dy}{dx} \text{ at } \theta = \frac{\pi}{2}`
    );
    expect(c.problemType).not.toBe("polar_gradient");
  });

  it("an ordinary cartesian dy/dx is untouched", async () => {
    const r = await run(String.raw`\text{If } y = x^3 \text{, find } \frac{dy}{dx}`);
    expect(r).toMatchObject({ type: "derivative", verified: true });
  });
});
