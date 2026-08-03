// Sheet 2.8 — "find the times at which the particle is at rest". The answer is a
// PERIODIC FAMILY, `t = 2nπ`, and the stationary-point route could never print it:
// that route proves its list complete from a polynomial's degree, and this set is
// infinite.
//
// Two things had to be true for this to be answerable honestly. Completeness now
// comes from periodicity — the roots inside one proven period, repeated — and the
// root search has to see a TOUCH point, because `v = 1 − cos t` reaches zero
// without ever changing sign, which is exactly where a crossing search finds
// nothing at all.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("at-rest times are deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return {
    type: c.problemType,
    verified: p.verified,
    plain: p.finalAnswer?.plain,
    latex: p.finalAnswer?.latex,
  };
}

describe("a periodic family of rest times", () => {
  it("s = t − sin t is at rest at t = 2nπ — a touch point, not a crossing", async () => {
    const r = await run(
      String.raw`\text{A particle moves so that } s = t - \sin t \text{. Find the times at which it is at rest.}`
    );
    expect(r).toMatchObject({ type: "rest_times", verified: true });
    expect(r.plain).toBe("t = 2nπ for every integer n");
    expect(r.latex).toContain("\\mathbb{Z}");
  });

  it("s = t + cos t offsets the family by π/2, in exact form", async () => {
    const r = await run(
      String.raw`\text{A particle has displacement } s = t + \cos t \text{. Find the times at which the particle is at rest.}`
    );
    expect(r.verified).toBe(true);
    expect(r.plain).toBe("t = π/2 + 2nπ for every integer n");
  });

  it("s = sin t gives BOTH roots of the period, not just the first", async () => {
    const r = await run(
      String.raw`\text{A particle moves with } s = \sin t \text{. Find when the particle is at rest.}`
    );
    expect(r.verified).toBe(true);
    expect(r.plain).toBe("t = π/2 + 2nπ, t = 3π/2 + 2nπ for every integer n");
  });

  it("s = sin 2t has period π, and the answer says so", async () => {
    const r = await run(
      String.raw`\text{Given } s = \sin(2t) \text{, find the times at which the velocity is zero.}`
    );
    expect(r.verified).toBe(true);
    expect(r.plain).toBe("t = π/4 + nπ, t = 3π/4 + nπ for every integer n");
  });
});

describe("the non-periodic case still works the old way", () => {
  it("s = t³ − 3t² is at rest at two times and only two", async () => {
    const r = await run(
      String.raw`\text{Given } s = t^3 - 3t^2 \text{, find the times at which the particle is at rest.}`
    );
    expect(r).toMatchObject({ type: "rest_times", verified: true, plain: "t = 0, t = 2" });
  });
});

describe("what it refuses", () => {
  it("a particle that is never at rest is not given a time", async () => {
    // v = 2 + cos t ≥ 1 — there is no answer, and inventing one would be a lie.
    const r = await run(
      String.raw`\text{Given } s = 2t + \sin t \text{, find the times at which the particle is at rest.}`
    );
    expect(r.verified).not.toBe(true);
  });

  it("constant velocity means never at rest — decline, not t = 0", async () => {
    const r = await run(
      String.raw`\text{Given } s = 5t \text{, find the times at which the particle is at rest.}`
    );
    expect(r.verified).not.toBe(true);
  });

  it("s = e^t is never at rest either", async () => {
    const r = await run(
      String.raw`\text{Given } s = e^t \text{, find the times at which the particle is at rest.}`
    );
    expect(r.verified).not.toBe(true);
  });
});

describe("no regression on the kinematics route", () => {
  it("a STATED time still asks for the velocity there, not for the rest times", async () => {
    const r = await run(String.raw`\text{Given } s = t^2 + 1 \text{, find the velocity at } t = 2`);
    expect(r).toMatchObject({ type: "kinematics", verified: true });
    expect(r.plain).toContain("4");
  });
});
