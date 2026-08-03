// "Sketch the curve, stating its asymptotes" — the Sheet-4 staple, which used to
// dead-end at `beyond_solver`.
//
// The engine only accepts a RATIONAL function (mathjs `rationalize` throws on
// anything else, which is the parse gate), finds ALL the denominator's roots by
// Durand–Kerner rather than by a scan that could step over one, and then proves
// the answer against the function itself: each pole must blow up, no unlisted
// blow-up may exist in the window, and the end-behaviour residual must DECAY.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("asymptotes are deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { type: c.problemType, verified: p.verified, plain: p.finalAnswer?.plain };
}

describe("vertical + horizontal asymptotes", () => {
  it("y = (x+1)/(x-2) — a pole at 2 and the line y = 1", async () => {
    const r = await run(
      String.raw`\text{Sketch the curve } y = \frac{x+1}{x-2} \text{, stating its asymptotes}`
    );
    expect(r).toMatchObject({ type: "curve_asymptotes", verified: true, plain: "x = 2, y = 1" });
  });

  it("y = (2x+3)/(x-1) — the horizontal asymptote is the ratio of the leading terms", async () => {
    const r = await run(
      String.raw`\text{Find the asymptotes of } y = \frac{2x+3}{x-1}`
    );
    expect(r).toMatchObject({ verified: true, plain: "x = 1, y = 2" });
  });

  it("y = 1/(x²-4) — TWO poles, and both are found", async () => {
    const r = await run(String.raw`\text{Find the asymptotes of } y = \frac{1}{x^2-4}`);
    expect(r).toMatchObject({ verified: true, plain: "x = -2, x = 2, y = 0" });
  });

  it("a denominator with no real root has no vertical asymptote", async () => {
    const r = await run(String.raw`\text{Find the asymptotes of } y = \frac{1}{x^2+1}`);
    expect(r).toMatchObject({ verified: true, plain: "y = 0" });
  });
});

describe("oblique asymptotes", () => {
  it("y = (x²+x+1)/(x+1) — the quotient of the long division is y = x", async () => {
    const r = await run(
      String.raw`\text{Sketch the curve } y = \frac{x^2+x+1}{x+1} \text{, stating its asymptotes}`
    );
    expect(r).toMatchObject({ verified: true, plain: "x = -1, y = x" });
  });

  it("y = (x²+1)/x — asymptote y = x through a pole at the origin", async () => {
    const r = await run(String.raw`\text{Find the asymptotes of } y = \frac{x^2+1}{x}`);
    expect(r).toMatchObject({ verified: true, plain: "x = 0, y = x" });
  });

  it("y = (x²-3x+2)/(x-3) gives a shifted oblique asymptote", async () => {
    // x² − 3x + 2 = (x − 3)x + 2, so y = x is the asymptote and x = 3 the pole.
    const r = await run(String.raw`\text{Find the asymptotes of } y = \frac{x^2-3x+2}{x-3}`);
    expect(r).toMatchObject({ verified: true, plain: "x = 3, y = x" });
  });

  it("a cubic over a linear runs away faster than any line — only the pole is stated", async () => {
    const r = await run(String.raw`\text{Find the asymptotes of } y = \frac{x^3}{x-1}`);
    expect(r).toMatchObject({ verified: true, plain: "x = 1" });
  });
});

describe("what it refuses to call an asymptote", () => {
  it("a shared factor is a HOLE, not an asymptote — decline", async () => {
    // (x²−1)/(x−1) is the straight line y = x + 1 with a gap at x = 1. Calling
    // x = 1 an asymptote would be plainly false.
    const r = await run(String.raw`\text{Find the asymptotes of } y = \frac{x^2-1}{x-1}`);
    expect(r.verified).not.toBe(true);
  });

  it("a non-rational function is not this engine's problem", async () => {
    const r = await run(String.raw`\text{Find the asymptotes of } y = \frac{\sin x}{x}`);
    expect(r.verified).not.toBe(true);
  });

  it("e^x / (x-1) declines rather than guessing at the exponential's behaviour", async () => {
    const r = await run(String.raw`\text{Find the asymptotes of } y = \frac{e^x}{x-1}`);
    expect(r.verified).not.toBe(true);
  });

  it("a polynomial has no asymptotes and is not answered as though it did", async () => {
    const r = await run(String.raw`\text{Find the asymptotes of } y = x^2 + 1`);
    expect(r.verified).not.toBe(true);
  });
});

describe("no regression on the other sketching asks", () => {
  it("'find the stationary points' still wins over the sketch cue", async () => {
    const r = await run(
      String.raw`\text{Sketch the curve } y = x^3 - 3x \text{, finding its stationary points}`
    );
    expect(r).toMatchObject({ type: "stationary_points", verified: true });
  });
});
