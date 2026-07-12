import { describe, expect, it } from "vitest";
import { evaluateRateLimit } from "../src/lib/rateLimit";
import { solveCacheKey } from "../src/lib/solveCache";
import { moderateImage } from "../src/lib/openai";

// Step 9 (§10) cost/safety hardening: the pure rate-limit decision, the
// collision-safe solve-cache key, and the image-moderation verdict mapping.

const T0 = 1_700_000_000_000; // a fixed "now" (ms); real Date.now() is avoided.

describe("rate limiter — fixed-window decision", () => {
  const limits = { perMinute: 3, perDay: 5 };

  it("allows calls under the per-minute ceiling and counts them", () => {
    let state = {};
    const d1 = evaluateRateLimit(state, limits, T0);
    expect(d1.allow).toBe(true);
    expect(d1.next.minCount).toBe(1);
    state = d1.next;
    const d2 = evaluateRateLimit(state, limits, T0 + 1000);
    expect(d2.allow).toBe(true);
    expect(d2.next.minCount).toBe(2);
  });

  it("rejects the call that would exceed the per-minute ceiling", () => {
    // Third call fills the window (count 3 == limit, still allowed); fourth trips.
    let state = {};
    for (let i = 0; i < 3; i++) {
      const d = evaluateRateLimit(state, limits, T0 + i * 1000);
      expect(d.allow).toBe(true);
      state = d.next;
    }
    const over = evaluateRateLimit(state, limits, T0 + 3000);
    expect(over.allow).toBe(false);
    expect(over.window).toBe("minute");
    expect(over.retryAfterSeconds).toBeGreaterThan(0);
  });

  it("resets the minute window when the minute rolls over", () => {
    const filled = { minEpoch: Math.floor(T0 / 60_000), minCount: 3, dayEpoch: Math.floor(T0 / 86_400_000), dayCount: 3 };
    const nextMinute = evaluateRateLimit(filled, limits, T0 + 61_000);
    expect(nextMinute.allow).toBe(true);
    expect(nextMinute.next.minCount).toBe(1); // fresh minute
    expect(nextMinute.next.dayCount).toBe(4); // same day keeps counting
  });

  it("rejects on the per-day ceiling even across minutes", () => {
    // Day count already at the limit; a new minute still trips the day cap.
    const day = Math.floor(T0 / 86_400_000);
    const state = { minEpoch: 0, minCount: 0, dayEpoch: day, dayCount: 5 };
    const over = evaluateRateLimit(state, limits, T0 + 120_000);
    expect(over.allow).toBe(false);
    expect(over.window).toBe("day");
  });
});

describe("solveCacheKey — collision-safe both ways", () => {
  it("maps different renderings of the same problem to one key", () => {
    expect(solveCacheKey("5x^2")).toBe(solveCacheKey("5x^{2}"));
    expect(solveCacheKey("\\left(x+1\\right)^2")).toBe(solveCacheKey("(x+1)^2"));
    expect(solveCacheKey("2\\cdot3")).toBe(solveCacheKey("2\\times3"));
    expect(solveCacheKey("2x + 5 = 13")).toBe(solveCacheKey("2x+5=13"));
  });

  it("never merges genuinely different problems", () => {
    expect(solveCacheKey("x^2 + 1 = 0")).not.toBe(solveCacheKey("x^2 - 1 = 0"));
    expect(solveCacheKey("5x^2")).not.toBe(solveCacheKey("5x^3"));
    // multi-char exponent is NOT unwrapped: x^{10} (10th power) ≠ x^10 (x^1·0)
    expect(solveCacheKey("x^{10}")).not.toBe(solveCacheKey("x^10"));
  });
});

describe("moderateImage — COPPA verdict mapping", () => {
  function fakeClient(impl: () => Promise<unknown>): any {
    return { moderations: { create: impl } };
  }

  it("reports a positive flag with its categories", async () => {
    const client = fakeClient(async () => ({
      results: [{ flagged: true, categories: { violence: true, sexual: false } }],
    }));
    const v = await moderateImage(client, "data:image/jpeg;base64,AAAA");
    expect(v.flagged).toBe(true);
    expect(v.categories).toContain("violence");
    expect(v.categories).not.toContain("sexual");
  });

  it("passes a clean image", async () => {
    const client = fakeClient(async () => ({ results: [{ flagged: false, categories: {} }] }));
    const v = await moderateImage(client, "data:image/jpeg;base64,AAAA");
    expect(v.flagged).toBe(false);
  });

  it("fails OPEN (not flagged) when the moderation service errors", async () => {
    const client = fakeClient(async () => {
      throw new Error("moderation down");
    });
    const v = await moderateImage(client, "data:image/jpeg;base64,AAAA");
    expect(v.flagged).toBe(false); // an outage must not block the scanner
  });
});
