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
    latex: p.finalAnswer?.latex,
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
    // The PLAIN answer is read as text, so the centre is spelled, not marked up:
    // `\pi` belongs in the LaTeX, which is asserted separately below.
    expect(r.plain).toBe("-1 + (1/2)(x - π)^2");
    expect(r.latex).toContain("\\pi");
  });

  it("a polynomial equals its own Maclaurin series (exact residual = 0)", async () => {
    const r = await run(String.raw`Maclaurin series of x^3 + 2x to order 4`);
    expect(r).toMatchObject({ verified: true, plain: "2x + x^3" });
  });

  it("'5 terms' means degree 4", async () => {
    const r = await run(String.raw`Maclaurin series of e^x, first 5 terms`);
    expect(r).toMatchObject({ order: 4, verified: true });
  });

  // How a real problem sheet actually words it — a spelled-out term count, the
  // centre given as "near x = a", the function introduced by "for", and the
  // whole sentence wrapped in `\text{}` by the OCR. Every one of these three
  // was previously misrouted: 5.2(a) classified as a LINEAR EQUATION and
  // answered "x = 0" (it read "near x = 0" as the equation to solve).
  it("Oxford 5.2(a) — four-term polynomial near x = 0 for √(1+x)", async () => {
    const r = await run(
      String.raw`\text{Obtain the four-term Taylor polynomial near } x = 0 \text{ for } (1+x)^{1/2}`
    );
    expect(r).toMatchObject({
      type: "maclaurin_series",
      order: 3,
      verified: true,
      plain: "1 + (1/2)x - (1/8)x^2 + (1/16)x^3",
    });
  });

  it("Oxford 5.2(b) — sin 2x", async () => {
    const r = await run(
      String.raw`\text{Obtain the four-term Taylor polynomial near } x = 0 \text{ for } \sin 2x`
    );
    expect(r).toMatchObject({ verified: true, plain: "2x - (4/3)x^3" });
  });

  it("Oxford 5.2(c) — ln(1+3x)", async () => {
    const r = await run(
      String.raw`\text{Obtain the four-term Taylor polynomial near } x = 0 \text{ for } \ln(1+3x)`
    );
    expect(r).toMatchObject({ verified: true, plain: "3x - (9/2)x^2 + 9x^3" });
  });

  it("'near x = a' is a CENTRE, not a default to 0", async () => {
    // The dangerous case: before "near" was a centre cue this expanded about 0
    // and returned a confident series for the wrong point.
    const r = await run(
      String.raw`\text{Find the three-term Taylor polynomial near } x = 1 \text{ for } \ln x`
    );
    expect(r).toMatchObject({
      type: "taylor_series",
      center: 1,
      verified: true,
      plain: "(x - 1) - (1/2)(x - 1)^2",
    });
  });

  it("reads the term count when the order phrase comes FIRST", async () => {
    const r = await run(String.raw`Find the first 4 terms of the Maclaurin series for e^x`);
    expect(r).toMatchObject({ order: 3, verified: true });
  });

  it("does not mistake leftover English for the function", () => {
    // mathjs parses "the Maclaurin series for e^x" as implicit multiplication
    // rather than throwing, so the phrase once survived as the "function".
    const c = classify(String.raw`Maclaurin polynomial for e^x with 4 terms`);
    expect(c.taylorFn).toBe("e^x");
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

// The adversarial review found 5 golden-rule violations, ALL center-parse
// fidelity: a correct series about the WRONG center (the gate can't catch that,
// since the series IS valid about whatever center it was handed). These lock the
// fixes: the right center is parsed, or the request DECLINES.
describe("regression — review findings (center fidelity)", () => {
  it("#1 a π/6 center is parsed as π/6, not π", async () => {
    const r = await run(String.raw`Taylor series of \sin(x) around x = \pi/6 to order 3`);
    expect(r.center).toBeCloseTo(Math.PI / 6, 6);
    expect(r.verified).toBe(true);
    expect(r.plain?.startsWith("1/2")).toBe(true); // sin(π/6)=1/2
    expect(r.plain).toContain("π/6");
    expect(r.latex).toContain("\\frac{\\pi}{6}");
    expect(r.plain).not.toContain("(x - π)"); // the old wrong-center output
  });

  it("#1 a 1/2 center is parsed as 0.5, not 1", async () => {
    const r = await run(String.raw`Taylor series of e^x around x = 1/2 to order 3`);
    expect(r.center).toBeCloseTo(0.5, 9);
    expect(r.verified).toBe(true);
    expect(r.plain?.startsWith("1.648721")).toBe(true); // √e, not e
  });

  it("#2 'at 3rd order' is the ORDER, not a center of 3", async () => {
    const r = await run(String.raw`Taylor series of \sin(x) at 3rd order`);
    expect(r).toMatchObject({ center: 0, verified: true, plain: "x - (1/6)x^3" });
  });

  it("#2 'at 4 terms' is the term COUNT, not a center of 4", async () => {
    const r = await run(String.raw`Taylor series of \cos(x) at 4 terms`);
    expect(r).toMatchObject({ center: 0, verified: true });
  });

  it("#3 a pole at the (correctly-parsed) center declines honestly", async () => {
    const r = await run(String.raw`Taylor series of \tan(x) around \pi/2 order 4`);
    expect(r.strategy).toBe("taylor");
    expect(r.center).toBeCloseTo(Math.PI / 2, 6);
    expect(r.verified).toBe(false); // tan has a pole at π/2 — no series
  });

  it("#3 a symbolic center declines (never silently defaults to 0)", () => {
    const c = classify(String.raw`Taylor series of e^x centered at a to order 3`);
    expect(c.strategy).not.toBe("taylor");
  });

  it("#4 'about the point x=2' is parsed as center 2, not Maclaurin", async () => {
    const r = await run(String.raw`Find the Taylor series of e^x about the point x=2 to order 3`);
    expect(r).toMatchObject({ center: 2, verified: true });
    expect(r.plain).toContain("(x - 2)");
  });

  it("#5 the surname 'Taylor' in prose is NOT a series request", () => {
    const c = classify(String.raw`Taylor drew a 5 degree angle, then a line. Find the value of x.`);
    expect(c.strategy).not.toBe("taylor");
  });
});

// How a problem sheet actually states the order: "up to x⁴", "as far as the term
// in x⁴", "including the x³ term". None of these named a NUMBER the order
// patterns could see, so the whole family declined and fell through to be read
// as a POLYNOMIAL EQUATION — an answer to a question nobody asked.
describe("the order as a problem sheet writes it", () => {
  const sheet: [string, string, string][] = [
    [
      String.raw`\text{Find the Maclaurin series of } \sec x \text{ up to } x^4`,
      "maclaurin_series",
      "1 + (1/2)x^2 + (5/24)x^4",
    ],
    [
      String.raw`\text{Find the Maclaurin series of } \tan x \text{ up to } x^5`,
      "maclaurin_series",
      "x + (1/3)x^3 + (2/15)x^5",
    ],
    [
      String.raw`\text{Find the Maclaurin series of } \ln(1+x) \text{ as far as the term in } x^3`,
      "maclaurin_series",
      "x - (1/2)x^2 + (1/3)x^3",
    ],
    [
      String.raw`\text{Expand } \sqrt{1+x} \text{ as a Maclaurin series including the } x^2 \text{ term}`,
      "maclaurin_series",
      "1 + (1/2)x - (1/8)x^2",
    ],
  ];

  it.each(sheet)("%s", async (latex, type, plain) => {
    const r = await run(latex);
    expect(r).toMatchObject({ type, verified: true, plain });
  });

  it("a centre written as a LaTeX fraction is a centre, not a decline", async () => {
    // `\frac{\pi}{3}` survived none of the backslash-stripping the old parse did,
    // so `about x = \frac{\pi}{3}` read as no centre at all.
    const r = await run(
      String.raw`\text{Find the Taylor series of } \cos x \text{ about } x = \frac{\pi}{3} \text{ up to } x^2`
    );
    expect(r.type).toBe("taylor_series");
    expect(r.center).toBeCloseTo(Math.PI / 3, 9);
    expect(r.verified).toBe(true);
    // Plain is read as text; the markup belongs in the LaTeX beside it.
    expect(r.plain).toContain("π/3");
    expect(r.plain).not.toContain("frac");
    expect(r.latex).toContain("\\frac{\\pi}{3}");
  });
});
