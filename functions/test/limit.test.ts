import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { parseLimit } from "../src/solver/limit";
import { JsonCompleter } from "../src/solver/narrate";

// The limit engine is DETERMINISTIC (a numeric convergence oracle) — the LLM is
// never called. This completer proves it: any call throws.
const NEVER: JsonCompleter = async () => {
  throw new Error("the limit engine must not call the LLM");
};

describe("parseLimit", () => {
  it("reads x, the point, direction, and the function", () => {
    const p = parseLimit("\\lim_{x \\to 1} \\frac{x^2-1}{x-1}")!;
    expect(p.variable).toBe("x");
    expect(p.point).toBe(1);
    expect(p.dir).toBe("both");
  });
  it("reads a one-sided limit (a^+ → right)", () => {
    expect(parseLimit("\\lim_{x \\to 0^+} \\frac{1}{x}")!.dir).toBe("right");
    expect(parseLimit("\\lim_{x \\to 0^-} \\frac{1}{x}")!.dir).toBe("left");
  });
  it("reads a limit at infinity", () => {
    expect(parseLimit("\\lim_{x \\to \\infty} \\frac{1}{x}")!.point).toBe(Infinity);
    expect(parseLimit("\\lim_{x \\to -\\infty} \\frac{1}{x}")!.point).toBe(-Infinity);
  });
  it("returns null when there is no \\lim or the subscript is malformed", () => {
    expect(parseLimit("\\frac{x^2-1}{x-1}")).toBeNull();
    expect(parseLimit("\\lim_{x} f(x)")).toBeNull();
  });
});

describe("limit engine — convergent limits verify (no LLM)", () => {
  const cases: [string, string, string][] = [
    ["removable 0/0 → 2", "\\lim_{x \\to 1} \\frac{x^2-1}{x-1}", "2"],
    ["removable 0/0 → 4", "\\lim_{x \\to 2} \\frac{x^2-4}{x-2}", "4"],
    ["sin x / x → 1", "\\lim_{x \\to 0} \\frac{\\sin x}{x}", "1"],
    ["a continuous value → 7", "\\lim_{x \\to 2} 3x + 1", "7"],
    ["1/x at infinity → 0", "\\lim_{x \\to \\infty} \\frac{1}{x}", "0"],
  ];
  for (const [name, latex, expected] of cases) {
    it(name, async () => {
      const cls = classify(latex);
      expect(cls.problemType).toBe("limit");
      const p = await solve(cls, NEVER);
      expect(p.verified).toBe(true);
      expect(p.finalAnswer?.plain).toBe(expected);
      expect(p.routeToTutor).toBeUndefined();
    });
  }

  it("a one-sided limit converges from the stated side", async () => {
    // 1/x → +∞ from the right (diverges → decline), but sqrt(x) → 0 from 0⁺.
    const p = await solve(classify("\\lim_{x \\to 0^+} \\sqrt{x}"), NEVER);
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("0");
  });
});

describe("limit engine — golden rule: divergent / DNE limits DECLINE", () => {
  // These must NOT ship a confident value; an honest couldn't-verify instead.
  const declines: [string, string][] = [
    ["1/x two-sided at 0 (both sides diverge)", "\\lim_{x \\to 0} \\frac{1}{x}"],
    ["1/x² at 0 (diverges to +∞)", "\\lim_{x \\to 0} \\frac{1}{x^2}"],
    ["a polynomial at infinity (diverges)", "\\lim_{x \\to \\infty} x^2 + 1"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify`, async () => {
      const cls = classify(latex);
      expect(cls.problemType).toBe("limit");
      const p = await solve(cls, NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
      // A divergent limit is honestly declined — NOT a fake answer, NOT tutor.
      expect(p.routeToTutor).toBeUndefined();
    });
  }

  it("a jump discontinuity (two sides disagree) declines", async () => {
    // (x)/|x| jumps from −1 to +1 at 0; if abs parses, the two sides disagree.
    const p = await solve(classify("\\lim_{x \\to 0} \\frac{x}{\\sqrt{x^2}}"), NEVER);
    expect(p.verified).toBe(false);
  });
});
