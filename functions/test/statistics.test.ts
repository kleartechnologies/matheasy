// Descriptive statistics — a DETERMINISTIC, cross-checked solve path. Every
// answer is computed by mathjs AND an independent recompute that must agree,
// so the golden rule holds without an equation to substitute into.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { parseStatistics } from "../src/solver/statistics";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("statistics is deterministic — the LLM must not be called");
};

async function answer(input: string): Promise<{ verified: boolean; plain?: string }> {
  const p = await solve(classify(input), NEVER);
  return { verified: p.verified, plain: p.finalAnswer?.plain };
}

describe("parseStatistics", () => {
  it("extracts the statistic + comma-separated data set", () => {
    expect(parseStatistics("mean of 2, 4, 6, 8")).toEqual({ stat: "mean", data: [2, 4, 6, 8] });
    expect(parseStatistics("median(3, 1, 4, 1, 5)")).toEqual({ stat: "median", data: [3, 1, 4, 1, 5] });
    expect(parseStatistics("standard deviation of 2, 4, 4")).toEqual({ stat: "std", data: [2, 4, 4] });
  });
  it("returns null without a keyword or without a ≥2-number list", () => {
    expect(parseStatistics("2, 4, 6, 8")).toBeNull(); // no keyword
    expect(parseStatistics("mean of 5")).toBeNull(); // single value, not a set
    expect(parseStatistics("2x + 3 = 15")).toBeNull(); // an ordinary equation
  });
});

describe("solve — descriptive statistics (deterministic + verified)", () => {
  it("mean", async () => expect(await answer("mean of 2, 4, 6, 8")).toEqual({ verified: true, plain: "5" }));
  it("median (odd n)", async () => expect(await answer("median of 3, 1, 4, 1, 5, 9, 2")).toEqual({ verified: true, plain: "3" }));
  it("median (even n → average of the two middles)", async () =>
    expect(await answer("median of 1, 2, 3, 4")).toEqual({ verified: true, plain: "2.5" }));
  it("population standard deviation", async () =>
    expect(await answer("standard deviation of 2, 4, 4, 4, 5, 5, 7, 9")).toEqual({ verified: true, plain: "2" }));
  it("population variance", async () =>
    expect(await answer("variance of 1, 2, 3, 4, 5")).toEqual({ verified: true, plain: "2" }));
  it("mode", async () => expect(await answer("mode of 1, 2, 2, 3, 3, 3, 4")).toEqual({ verified: true, plain: "3" }));
  it("range", async () => expect(await answer("range of 10, 3, 7, 1")).toEqual({ verified: true, plain: "9" }));
  it("sum", async () => expect(await answer("sum of 2, 4, 6, 8")).toEqual({ verified: true, plain: "20" }));

  it("declines an all-distinct 'mode' honestly (no clear mode → couldn't-verify)", async () => {
    // deterministic path returns null; verifyMode 'none' → no LLM, honest refusal.
    expect((await answer("mode of 1, 2, 3, 4")).verified).toBe(false);
  });
});
