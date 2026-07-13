// Taylor / Maclaurin series — DETERMINISTIC (mathjs repeated differentiation),
// proven by an INDEPENDENT contact-order test: the scaled residual |f−T|/δⁿ must
// decay like a correct order-n series, so a wrong coefficient can never pass.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { verifyTaylor } from "../src/solver/taylor";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("Taylor series is deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return {
    type: c.problemType,
    strategy: c.strategy,
    fn: c.taylorFn,
    center: c.taylorCenter,
    order: c.taylorOrder,
    verified: p.verified,
    plain: p.finalAnswer?.plain,
  };
}

describe("classify + solve — Taylor / Maclaurin series", () => {
  it("Maclaurin of eˣ (order 4)", async () => {
    const r = await run(String.raw`Maclaurin series of e^x to order 4`);
    expect(r).toMatchObject({
      type: "maclaurin_series",
      verified: true,
      plain: "1 + x + (1/2)x^2 + (1/6)x^3 + (1/24)x^4",
    });
  });

  it("Maclaurin of sin x (order 5) — only odd terms", async () => {
    const r = await run(String.raw`Maclaurin series of \sin(x) up to order 5`);
    expect(r).toMatchObject({ verified: true, plain: "x - (1/6)x^3 + (1/120)x^5" });
  });

  it("Maclaurin of cos x (order 4) — only even terms (no false reject)", async () => {
    const r = await run(String.raw`Maclaurin series of \cos(x) to order 4`);
    expect(r).toMatchObject({ verified: true, plain: "1 - (1/2)x^2 + (1/24)x^4" });
  });

  it("Taylor of ln x about x=1 (order 3)", async () => {
    const r = await run(String.raw`Taylor series of \ln(x) around x = 1 to order 3`);
    expect(r).toMatchObject({
      type: "taylor_series",
      center: 1,
      verified: true,
      plain: "(x - 1) - (1/2)(x - 1)^2 + (1/3)(x - 1)^3",
    });
  });

  it("Maclaurin of 1/(1−x) (geometric, order 3)", async () => {
    const r = await run(String.raw`Maclaurin series of \frac{1}{1-x} to order 3`);
    expect(r).toMatchObject({ verified: true, plain: "1 + x + x^2 + x^3" });
  });

  it("Taylor of √x about x=4 (order 2)", async () => {
    const r = await run(String.raw`Taylor polynomial of degree 2 for \sqrt{x} at x = 4`);
    expect(r).toMatchObject({
      center: 4,
      verified: true,
      plain: "2 + (1/4)(x - 4) - (1/64)(x - 4)^2",
    });
  });

  it("Taylor of cos x about x=π (order 2)", async () => {
    const r = await run(String.raw`Taylor series of \cos(x) about x = \pi to order 2`);
    expect(r.verified).toBe(true);
    expect(r.plain).toBe("-1 + (1/2)(x - \\pi)^2");
  });

  it("a polynomial equals its own Maclaurin series (exact residual = 0)", async () => {
    const r = await run(String.raw`Maclaurin series of x^3 + 2x to order 4`);
    expect(r).toMatchObject({ verified: true, plain: "2x + x^3" });
  });

  it("'5 terms' means degree 4", async () => {
    const r = await run(String.raw`Maclaurin series of e^x, first 5 terms`);
    expect(r).toMatchObject({ order: 4, verified: true });
  });

  it("declines a multivariable function (single-variable only)", () => {
    const c = classify(String.raw`Maclaurin series of x y to order 2`);
    expect(c.strategy).not.toBe("taylor");
  });

  it("declines an order beyond the supported range", () => {
    const c = classify(String.raw`Maclaurin series of e^x to order 8`);
    expect(c.strategy).not.toBe("taylor");
  });
});

describe("Taylor gate — the contact-order test rejects wrong coefficients", () => {
  // sin x at 0: c = [0, 1, 0, -1/6, 0, 1/120]
  it("accepts the correct coefficients", () => {
    expect(verifyTaylor("sin(x)", "x", 0, 5, [0, 1, 0, -1 / 6, 0, 1 / 120])).toBe(true);
  });

  it("rejects a wrong highest coefficient (residual stops decaying)", () => {
    // c₃ wrong (−1/5 instead of −1/6)
    expect(verifyTaylor("sin(x)", "x", 0, 3, [0, 1, 0, -1 / 5])).toBe(false);
  });

  it("rejects a wrong low coefficient (residual grows as δ→0)", () => {
    // c₁ wrong (2 instead of 1)
    expect(verifyTaylor("sin(x)", "x", 0, 5, [0, 2, 0, -1 / 6, 0, 1 / 120])).toBe(false);
  });

  it("rejects a wrong constant term", () => {
    expect(verifyTaylor("cos(x)", "x", 0, 4, [2, 0, -1 / 2, 0, 1 / 24])).toBe(false);
  });
});
