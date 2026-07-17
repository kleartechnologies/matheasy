// The "Find X" hole (real-device scan, 2026-07-17): a scanned geometry figure
// whose transcription carries NO computable math ("Find X", "Calculate the
// area of the triangle.") used to reach the simplify path as a bare variable,
// echo itself, and pass verifyEquality's identity short-circuit — a VERIFIED
// non-answer. The golden rule forbids exactly that: nothing-to-compute must
// decline honestly (couldn't-verify), without ever calling the LLM.
import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("a no-op input must decline without any LLM call");
};

async function run(latex: string) {
  const c = classify(latex);
  const p = await solve(c, NEVER);
  return {
    strategy: c.strategy,
    verifyMode: c.verifyMode,
    verified: p.verified,
    finalAnswer: p.finalAnswer,
    routeToTutor: p.routeToTutor === true,
  };
}

describe("no-op expressions decline instead of verifying an echo", () => {
  const noops: [string, string][] = [
    ["the scanned 'Find X'", String.raw`\text{Find } X`],
    ["a bare typed variable", "x"],
    ["a SUBSCRIPTED bare variable (the digit must not fool the guard)", String.raw`\text{Find } x_1`],
    ["a SIGNED bare variable (the sign must not fool the guard)", String.raw`\text{Find } -x`],
    ["prose remnant with a variable", String.raw`\text{In the triangle, angle } y \text{ is obtuse. Work out the size of angle } y.`],
    ["prose with no math at all", String.raw`\text{Calculate the area of the triangle.}`],
  ];
  for (const [name, latex] of noops) {
    it(`${name} → couldn't-verify, no LLM, no confident echo`, async () => {
      const r = await run(latex);
      expect(r.verified).toBe(false);
      expect(r.finalAnswer).toBeNull();
      expect(r.routeToTutor).toBe(false);
      expect(r.verifyMode).toBe("none"); // decline is final — no LLM tier
    });
  }
});

describe("real expressions and constants still solve", () => {
  it("2x + 3x still simplifies (operator present)", async () => {
    const r = await run("2x + 3x");
    expect(r.verified).toBe(true);
  });

  it("a bare number still evaluates", async () => {
    const r = await run("42 + 0");
    expect(r.verified).toBe(true);
  });

  it("pi alone still evaluates (a real constant, not prose)", async () => {
    const r = await run(String.raw`\pi`);
    expect(r.strategy).toBe("arithmetic");
    expect(r.verified).toBe(true);
  });

  it("sqrt(16) still evaluates", async () => {
    const r = await run(String.raw`\sqrt{16}`);
    expect(r.verified).toBe(true);
    expect(r.finalAnswer?.plain).toBe("4");
  });

  it("a factorial is real math content, not a no-op", async () => {
    const r = await run("x!");
    expect(r.strategy).toBe("simplify");
  });

  it("a varless identity chain declines without claiming a 'system'", async () => {
    const r = await run("2 + 3 = 5 = 5");
    expect(r.verified).toBe(false);
    expect(r.routeToTutor).toBe(false);
  });
});
