import { describe as describeVitest, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { LIMIT_ENGINE_ENABLED, solve } from "../src/proxy/solve";
import { parseLimit } from "../src/solver/limit";
import { JsonCompleter } from "../src/solver/narrate";

// The limit engine is HELD (disabled) pending a scoped redesign — see
// LIMIT_ENGINE_ENABLED in solve.ts. A numeric oracle can't be proven
// golden-rule-clean, so it is not in the safe-deploy batch. While it is dormant
// this whole suite is skipped so the rest of the functions suite stays green; the
// engine and its tests remain committed and this reverts to a live suite the
// moment the flag flips back to true.
const describe = LIMIT_ENGINE_ENABLED ? describeVitest : describeVitest.skip;

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
  it("folds a leading sign / numeric coefficient into `factor` (never dropped)", () => {
    expect(parseLimit("\\lim_{x \\to 1} x")!.factor).toBe(1); // no prefix
    expect(parseLimit("-\\lim_{x \\to 3} x^2")!.factor).toBe(-1);
    expect(parseLimit("2\\lim_{x \\to 0} \\frac{\\sin x}{x}")!.factor).toBe(2);
    expect(parseLimit("\\frac{1}{2}\\lim_{x \\to 0} x")!.factor).toBeCloseTo(0.5, 12);
  });
  it("flags an un-foldable prefix (additive / symbolic) with a NON-FINITE factor", () => {
    // The classifier still routes these to the deterministic limit engine, which
    // declines on the bad factor — it never drops the prefix or hits the LLM.
    expect(Number.isFinite(parseLimit("10-\\lim_{x \\to 3} x^2")!.factor)).toBe(false);
    expect(Number.isFinite(parseLimit("a\\lim_{x \\to 3} x^2")!.factor)).toBe(false);
  });
});

describe("limit engine — R3: a LaTeX prefix is folded, never dropped", () => {
  // The old parser sliced only the text AFTER `\lim_{…}`, silently dropping any
  // leading coefficient/sign: `-\lim_{x→3}x²` shipped +9 (SIGN FLIP), `2\lim…`
  // shipped 1. The prefix is now folded onto the verified inner value.
  const solves: [string, string, string][] = [
    ["-\\lim x² @3 → −9 (sign folded)", "-\\lim_{x \\to 3} x^2", "-9"],
    ["2\\lim sinx/x → 2", "2\\lim_{x \\to 0} \\frac{\\sin x}{x}", "2"],
    ["4\\lim (x²−4)/(x−2) @2 → 16", "4\\lim_{x \\to 2} \\frac{x^2-4}{x-2}", "16"],
    ["½\\lim sinx/x → 1/2", "\\frac{1}{2}\\lim_{x \\to 0} \\frac{\\sin x}{x}", "1/2"],
  ];
  for (const [name, latex, expected] of solves) {
    it(name, async () => {
      const cls = classify(latex);
      expect(cls.problemType).toBe("limit");
      const p = await solve(cls, NEVER);
      expect(p.verified).toBe(true);
      expect(p.finalAnswer?.plain).toBe(expected);
    });
  }

  it("π\\lim sinx/x → π (exact irrational preserved)", async () => {
    const p = await solve(classify("\\pi\\lim_{x \\to 0} \\frac{\\sin x}{x}"), NEVER);
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("π");
  });

  // An additive (`10-\lim`) or symbolic (`a\lim`) prefix can't be folded to a
  // constant, so the engine DECLINES deterministically (no LLM) — it must never
  // answer the bare sub-expression and drop the prefix.
  const declines: [string, string][] = [
    ["additive prefix 10−\\lim x² @3", "10-\\lim_{x \\to 3} x^2"],
    ["symbolic prefix a\\lim x² @3", "a\\lim_{x \\to 3} x^2"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify (deterministic, no LLM)`, async () => {
      const cls = classify(latex);
      expect(cls.problemType).toBe("limit");
      const p = await solve(cls, NEVER); // NEVER proves the LLM isn't touched
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }
});

describe("limit engine — R3: non-linear-phase oscillation aliasing DECLINES", () => {
  // The single 1/√2 companion ladder was defeated by QUADRATIC / LOGARITHMIC
  // phase — (1/√2)²=½ is rational, so cos(2πx²) re-aligns on the shifted ladder
  // too and both looked constant. The dense off-lattice irrational audit samples
  // every phase and forces the honest decline for these non-existent limits.
  const declines: [string, string][] = [
    ["cos(2πx²) @∞ (quadratic phase)", "\\lim_{x \\to \\infty} \\cos(2\\pi x^2)"],
    ["2+cos(2πx²) @∞", "\\lim_{x \\to \\infty} 2 + \\cos(2\\pi x^2)"],
    ["cos(πx²) @∞", "\\lim_{x \\to \\infty} \\cos(\\pi x^2)"],
    ["cos(2π/x²) @0 (quadratic phase both sides)", "\\lim_{x \\to 0} \\cos\\left(\\frac{2\\pi}{x^2}\\right)"],
    ["cos(2π·93·log₁₀x) @∞ (log phase)", "\\lim_{x \\to \\infty} \\cos(2\\pi \\cdot 93 \\cdot \\log_{10} x)"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }

  it("a DECAYING oscillation sin(x)/x → 0 @∞ still SOLVES (not over-declined)", async () => {
    // The audit is smarter than a blunt "unbounded trig argument → decline"
    // guard: sin(x)/x has an unbounded argument but a real limit (squeeze), and
    // every off-lattice audit point is ≈0, so it is verified 0, not declined.
    const p = await solve(classify("\\lim_{x \\to \\infty} \\frac{\\sin x}{x}"), NEVER);
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("0");
  });
});

describe("limit engine — R3: saturation below the step floor DECLINES", () => {
  it("tanh(10⁶·x) @0⁺ declines (true 0; the coarse plateau is a lie)", async () => {
    // Samples sit on the saturated plateau (…,1,1,0.76) while the true limit 0 is
    // reached only below the 1e-6 step floor. The old converge fell back to the
    // coarse plateau and shipped 1; the fine-anchored one sees the large-span
    // departure at the tail and declines.
    const p = await solve(classify("\\lim_{x \\to 0^+} \\tanh(1000000 x)"), NEVER);
    expect(p.verified).toBe(false);
    expect(p.finalAnswer).toBeNull();
  });
});

describe("limit engine — R3: a small jump on a LARGE baseline DECLINES", () => {
  it("1000 + 0.04·x/√(x²) @0 declines (jump 0.08 ≪ old relative tol)", async () => {
    // The two sides are exact flat constants 1000.04 vs 999.96; the spread-aware
    // two-sided tolerance (derived from their ~0 convergence noise) catches the
    // 0.08 jump the old relative 1e-4·(1+|v|)=0.1 tolerance waved through.
    const p = await solve(
      classify("\\lim_{x \\to 0} 1000 + \\frac{0.04 x}{\\sqrt{x^2}}"),
      NEVER
    );
    expect(p.verified).toBe(false);
    expect(p.finalAnswer).toBeNull();
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

  it("a LARGE-valued jump (999.5 vs 1000.5) declines (tight two-sided tol)", async () => {
    const p = await solve(
      classify("\\lim_{x \\to 0} 1000 + \\frac{0.5 x}{\\sqrt{x^2}}"),
      NEVER
    );
    expect(p.verified).toBe(false);
  });
});

describe("limit engine — adversarial-review hardening: log / harmonic tails DECLINE", () => {
  // Geometric sampling turns logarithmic GROWTH into an arithmetic (constant-
  // difference) sequence and 1/log into a harmonic tail — both fooled the old
  // "differences shrink" gate into a confident WRONG finite value. The geometric-
  // decay gate must now DECLINE all of these (they diverge, or Aitken can't
  // extrapolate them) rather than ship a number.
  const declines: [string, string][] = [
    ["ln x at ∞ (→ +∞, constant diffs)", "\\lim_{x \\to \\infty} \\ln x"],
    ["log₁₀ x at ∞ (→ +∞, snapped to 6 before)", "\\lim_{x \\to \\infty} \\log_{10} x"],
    ["ln(x²) at ∞ (→ +∞)", "\\lim_{x \\to \\infty} \\ln(x^2)"],
    ["ln(ln x) at ∞ (→ +∞, slow log-of-log)", "\\lim_{x \\to \\infty} \\ln(\\ln x)"],
    ["1/ln x at 0⁺ (→ 0, harmonic — was −0.043)", "\\lim_{x \\to 0^+} \\frac{1}{\\ln x}"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify (never a wrong value)`, async () => {
      const cls = classify(latex);
      expect(cls.problemType).toBe("limit");
      const p = await solve(cls, NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }

  it("a cancellation limit (1−cos x)/x² → 1/2 still SOLVES (flat tail at h≥1e-6)", async () => {
    const p = await solve(
      classify("\\lim_{x \\to 0} \\frac{1 - \\cos x}{x^2}"),
      NEVER
    );
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("1/2");
  });
});

describe("limit engine — anti-aliasing: grid-resonant periodic limits DECLINE", () => {
  // A periodic function sampled only on the power-of-10 lattice hits the SAME
  // phase every step and looks constant (cos(2π·integer)=1), so the oracle would
  // ship a confident value for a limit that does NOT exist. The off-phase
  // companion ladder must break this and force an honest decline.
  const declines: [string, string][] = [
    ["cos(2πx) at ∞ (aliases to 1)", "\\lim_{x \\to \\infty} \\cos(2\\pi x)"],
    ["cos(πx) at ∞ (aliases to 1)", "\\lim_{x \\to \\infty} \\cos(\\pi x)"],
    ["2+cos(2πx) at ∞ (aliases to 3)", "\\lim_{x \\to \\infty} 2 + \\cos(2\\pi x)"],
    ["sin(2πx) at ∞ (noise snapped to 0)", "\\lim_{x \\to \\infty} \\sin(2\\pi x)"],
    ["cos(2π/x) at 0 (aliases to 1 both sides)", "\\lim_{x \\to 0} \\cos\\left(\\frac{2\\pi}{x}\\right)"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }
});

describe("limit engine — R4 family A: a COMPLETE additive prefix DECLINES", () => {
  // R3 only rejected a DANGLING operator prefix (`10-\lim`). A *complete*
  // additive prefix — `10 - 3\lim`, `1 + ½\lim`, `2 - 1\lim` — parsed to a finite
  // leading term and was silently folded as if it were a multiplier, shipping the
  // sub-expression scaled by the wrong number. A top-level binary +/− in the
  // prefix now forces a NON-FINITE factor, so the engine declines deterministically.
  const declines: [string, string][] = [
    ["10 − 3\\lim x @2", "10 - 3\\lim_{x\\to 2} x"],
    ["3 − ½\\lim x @2", "3 - \\frac{1}{2}\\lim_{x\\to 2} x"],
    ["1 + ½\\lim x @2", "1 + \\frac{1}{2}\\lim_{x\\to 2} x"],
    ["5 − 2½\\lim x @2", "5 - 2\\frac{1}{2}\\lim_{x\\to 2} x"],
    ["2 − 1\\lim x @2", "2 - 1\\lim_{x\\to 2} x"],
    ["10 + 3\\lim x @2", "10 + 3\\lim_{x\\to 2} x"],
    ["3 + 2\\lim x @4", "3 + 2\\lim_{x\\to 4} x"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify (deterministic, no LLM)`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }

  // The fix must NOT over-decline a genuine PURE multiplicative coefficient — a
  // leading sign, integer, fraction, π, or mixed number is still folded and solved.
  const solves: [string, string, string][] = [
    ["−\\lim x² @3 → −9", "-\\lim_{x\\to 3} x^2", "-9"],
    ["2\\lim x @3 → 6", "2\\lim_{x\\to 3} x", "6"],
    ["½\\lim x @2 → 1", "\\frac{1}{2}\\lim_{x\\to 2} x", "1"],
    ["2½\\lim x @2 → 5 (mixed number, still pure)", "2\\frac{1}{2}\\lim_{x\\to 2} x", "5"],
  ];
  for (const [name, latex, expected] of solves) {
    it(`${name} still SOLVES (coefficient folded, not dropped)`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(true);
      expect(p.finalAnswer?.plain).toBe(expected);
    });
  }
});

describe("limit engine — R4 family B: a feature outside the sampling window DECLINES", () => {
  // The ladder samples |x| ∈ [1e-6, 1e6]. A transition/feature governed by a
  // constant LARGER than that window (a tanh/sigmoid step at 1e8, a period of
  // 1e12) sits entirely outside every sample, so the whole ladder looks flat and
  // the oracle would ship a confident value for the wrong plateau. Any sub-term
  // that is constant in x with magnitude > 1e6 now forces an honest decline.
  const declines: [string, string][] = [
    ["cos(x/1e12) @∞ (period ≫ window)", "\\lim_{x \\to \\infty} \\cos\\left(\\frac{x}{10^{12}}\\right)"],
    ["2 + cos(x/1e12) @∞", "\\lim_{x \\to \\infty} \\left(2 + \\cos\\frac{x}{10^{12}}\\right)"],
    ["sign via √ shifted by 1e8 @∞", "\\lim_{x \\to \\infty} \\frac{x - 10^{8}}{\\sqrt{(x - 10^{8})^2}}"],
    ["tanh(x − 1e8) @∞ (step past window)", "\\lim_{x \\to \\infty} \\tanh(x - 10^{8})"],
    ["sigmoid shifted 1e8 @∞", "\\lim_{x \\to \\infty} \\frac{1}{1 + e^{-(x - 10^{8})}}"],
    ["tanh(1/x − 5e6) @0⁺", "\\lim_{x \\to 0^+} \\tanh\\left(\\frac{1}{x} - 5\\cdot 10^6\\right)"],
    ["tanh(5e6 − x) @∞", "\\lim_{x \\to \\infty} \\tanh(5\\cdot 10^6 - x)"],
    ["tanh(x + 5e6) @−∞", "\\lim_{x \\to -\\infty} \\tanh(x + 5\\cdot 10^6)"],
    ["tanh(1e9·x − 100) @0⁺", "\\lim_{x \\to 0^+} \\tanh(10^9 x - 100)"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }
});

describe("limit engine — R4 family C: oscillation on a LARGE baseline DECLINES", () => {
  // A big additive baseline (100 + cos(2πx)) inflated the audit's relative
  // tolerance 2e-2·(1+|value|) to ≈2, wide enough to swallow the ±1 oscillation
  // so the aliased ladder looked constant at ~100/101. Jittering the ladder off
  // the integer lattice at the source samples every phase, so the oscillation is
  // seen and the non-existent limit is declined regardless of baseline size.
  const declines: [string, string][] = [
    ["100 + cos(2πx) @∞", "\\lim_{x \\to \\infty} 100 + \\cos(2\\pi x)"],
    ["100 + cos(2π/x) @0", "\\lim_{x \\to 0} 100 + \\cos(2\\pi/x)"],
    ["1000 + cos(2πx²) @∞ (quadratic phase)", "\\lim_{x \\to \\infty} 1000 + \\cos(2\\pi x^2)"],
    ["100 + 0.5cos(2πx) @∞ (small ripple, big base)", "\\lim_{x \\to \\infty} 100 + 0.5\\cos(2\\pi x)"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }

  // The jitter must NOT over-decline a genuine large-VALUED convergent limit —
  // the value being large is fine; only an unseen oscillation should decline.
  const solves: [string, string, string][] = [
    ["(x + 1000)/x @∞ → 1 (large const, converges)", "\\lim_{x \\to \\infty} \\frac{x + 1000}{x}", "1"],
    ["(1e6·x)/(x+1) @∞ → 1000000 (large value)", "\\lim_{x \\to \\infty} \\frac{1000000 x}{x + 1}", "1000000"],
  ];
  for (const [name, latex, expected] of solves) {
    it(`${name} still SOLVES (large value ≠ decline)`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(true);
      expect(p.finalAnswer?.plain).toBe(expected);
    });
  }
});

describe("limit engine — R5 family D: a SPLIT-constant saturation beyond the window DECLINES", () => {
  // maxConstMagnitude reads INDIVIDUAL constant literals, so an additive chain
  // `x - 5e5 - 5e5 - 5e5 - 5e5` (= x - 2e6) kept every literal under the 1e6 guard
  // yet placed the tanh/sigmoid/sign transition at 2e6, beyond the ladder's ~1.6e6
  // edge — so every in-window sample sat on the WRONG plateau and shipped it (−1
  // for a limit that is +1). The ∞ audit now reaches out to 1e12, sees the far
  // plateau flip, and declines. (The transition, not the value, is unreachable.)
  const declines: [string, string][] = [
    ["tanh(x − 4×5e5) @∞ (true +1)", "\\lim_{x \\to \\infty} \\tanh(x - 500000 - 500000 - 500000 - 500000)"],
    ["tanh(x − 2×9e5) @∞ (true +1)", "\\lim_{x \\to \\infty} \\tanh(x - 900000 - 900000)"],
    ["sigmoid centered 2e6 @∞ (true 1)", "\\lim_{x \\to \\infty} \\frac{1}{1+e^{-(x - 500000 - 500000 - 500000 - 500000)}}"],
    ["sign(x − 2e6) @∞ (true +1)", "\\lim_{x \\to \\infty} \\frac{x - 500000 - 500000 - 500000 - 500000}{\\sqrt{(x - 500000 - 500000 - 500000 - 500000)^2}}"],
    ["tanh(x + 2e6) @−∞ (true −1)", "\\lim_{x \\to -\\infty} \\tanh(x + 500000 + 500000 + 500000 + 500000)"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify (never the wrong plateau)`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }

  // The far-out audit (now reaching 1e12) must NOT over-decline a genuine
  // equal-degree rational whose limit is a real ratio — it is flat all the way
  // out, so every extended audit point agrees and it still SOLVES.
  it("(3x + 5)/(x + 2) @∞ → 3 still SOLVES (flat to 1e12)", async () => {
    const p = await solve(
      classify("\\lim_{x \\to \\infty} \\frac{3x + 5}{x + 2}"),
      NEVER
    );
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("3");
  });
});

describe("limit engine — R5 family E: a very-low-FREQUENCY oscillation DECLINES", () => {
  // A TINY coefficient (1e-13) makes an oscillation whose period is astronomically
  // long (~6e13), so its phase barely moves across the whole sampling window and
  // every sample sits on ONE crest — the engine read cos≈1 and shipped 1 for a
  // limit that does NOT exist. The tiny-constant guard (reject nonzero |c| < 1e-9)
  // declines these; the constant is too small to resolve, not too large.
  const declines: [string, string][] = [
    ["cos(1e-13/x) @0", "\\lim_{x \\to 0} \\cos\\left(\\frac{10^{-13}}{x}\\right)"],
    ["cos(1e-13/x) @0 (decimal spelling)", "\\lim_{x \\to 0} \\cos\\left(\\frac{0.0000000000001}{x}\\right)"],
    ["cos(1e-20/x) @0 (flatter crest)", "\\lim_{x \\to 0} \\cos\\left(\\frac{10^{-20}}{x}\\right)"],
    ["cos(1e-13·x) @∞", "\\lim_{x \\to \\infty} \\cos\\left(10^{-13} x\\right)"],
    ["cos(1e-13·x) @∞ (decimal)", "\\lim_{x \\to \\infty} \\cos\\left(0.0000000000001 x\\right)"],
    ["cos(2π·1e-13·x) @∞", "\\lim_{x \\to \\infty} \\cos\\left(2\\pi \\cdot 10^{-13} x\\right)"],
    ["cos(1e-11·x) @∞ (boundary of the band)", "\\lim_{x \\to \\infty} \\cos\\left(10^{-11} x\\right)"],
    ["cos(1e-12·x) @∞", "\\lim_{x \\to \\infty} \\cos\\left(10^{-12} x\\right)"],
    ["cos(1e-15/x²) @0⁺ (inverse-square phase)", "\\lim_{x \\to 0^+} \\cos\\left(\\frac{10^{-15}}{x^2}\\right)"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }
});

describe("limit engine — R5 family F: a genuine NEAR-integer limit ships the true value", () => {
  // cleanValue snapped anything within a fixed 1e-4 of an integer, so
  // `lim sin(1.00005x)/x = 1.00005` shipped the WRONG integer 1. The snap window
  // is now tied to the run's convergence noise (spread), which is ~0 for these —
  // a genuine 5e-5 offset is 10⁴× the noise, so the true value is preserved.
  const solves: [string, string, string][] = [
    ["sin(1.00005x)/x → 1.00005", "\\lim_{x \\to 0} \\frac{\\sin(1.00005 x)}{x}", "1.00005"],
    ["sin(0.99997x)/x → 0.99997", "\\lim_{x \\to 0} \\frac{\\sin(0.99997 x)}{x}", "0.99997"],
    ["tan(0.99996x)/x → 0.99996", "\\lim_{x \\to 0} \\frac{\\tan(0.99996 x)}{x}", "0.99996"],
    ["sin(2.00007x)/x → 2.00007", "\\lim_{x \\to 0} \\frac{\\sin(2.00007 x)}{x}", "2.00007"],
  ];
  for (const [name, latex, expected] of solves) {
    it(`${name} (not snapped to the wrong integer)`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(true);
      expect(p.finalAnswer?.plain).toBe(expected);
    });
  }

  // …but genuine float NOISE around an integer is still cleaned to the integer.
  it("sin(x)/x → 1 stays the clean integer 1 (noise snapped)", async () => {
    const p = await solve(classify("\\lim_{x \\to 0} \\frac{\\sin x}{x}"), NEVER);
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("1");
  });
});

describe("limit engine — R6 family G: a bounded saturation whose crossover hides past the ladder", () => {
  // tanh/atan/erf saturate to a constant. When the transition sits BEYOND the
  // ladder's reach, every rung reads a DEAD-FLAT plateau — the OLD engine shipped
  // that plateau as the limit with the WRONG sign:
  //   tanh(ln x − 30): crossover at x=e³⁰≈1.1e13, reads −1 in-window, true +1.
  // The audit pushes a BOUNDED transcendental's reach to 1e250 (it never loses
  // precision to cancellation) and judges the far tail with an ABSOLUTE 1e-3 floor,
  // so a beyond-ladder crossover is DECLINED rather than shipped wrong.
  const declines: [string, string][] = [
    ["tanh(ln x − 30) @∞ (crossover ~1e13)", "\\lim_{x \\to \\infty} \\tanh(\\ln(x) - 30)"],
    ["tanh(ln x − 40) @∞ (crossover ~1e17)", "\\lim_{x \\to \\infty} \\tanh(\\ln(x) - 40)"],
    ["−tanh(ln x − 40) @∞ (flipped sign)", "\\lim_{x \\to \\infty} -\\tanh(\\ln(x) - 40)"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }

  // A WITHIN-ladder crossover is now RESOLVED, not declined. With the ∞ ladder
  // reaching 1e10 ([1e2,1e3,1e4,1e6,1e8,1e10]), a transition below ~1e6 sits
  // entirely below the fine extrapolation triple (1e6,1e8,1e10), which then locks
  // onto the TRUE post-transition plateau. Verified correct-or-decline across the
  // whole family: crossover ≤1e6 → the exact plateau; a crossover that STRADDLES
  // the fine triple (1e6…1e10) → the estimates disagree → DECLINE; beyond 1e10 →
  // the audit far-check → DECLINE. No crossover ever ships a WRONG plateau.
  const resolves: [string, string, string][] = [
    ["999999 + tanh(x − 3e5) @∞", "\\lim_{x \\to \\infty} (999999 + \\tanh(x - 300000))", "1000000"],
    ["5000 + tanh(x − 3e5) @∞", "\\lim_{x \\to \\infty} (5000 + \\tanh(x - 300000))", "5001"],
    ["900000 − tanh(x − 3e5) @∞", "\\lim_{x \\to \\infty} (900000 - \\tanh(x - 300000))", "899999"],
  ];
  for (const [name, latex, expected] of resolves) {
    it(`${name} → ${expected} (within-ladder crossover now resolved)`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(true);
      expect(p.finalAnswer?.plain).toBe(expected);
    });
  }

  // A GENUINE saturating limit is dead flat at the far tail and still SOLVES.
  const solves: [string, string, string][] = [
    ["tanh(x) → 1", "\\lim_{x \\to \\infty} \\tanh(x)", "1"],
    ["tanh(2x) → 1", "\\lim_{x \\to \\infty} \\tanh(2x)", "1"],
    ["arctan(x) → π/2", "\\lim_{x \\to \\infty} \\arctan(x)", "π/2"],
    ["arctan(x²) → π/2", "\\lim_{x \\to \\infty} \\arctan(x^2)", "π/2"],
    ["erf(x) → 1", "\\lim_{x \\to \\infty} \\operatorname{erf}(x)", "1"],
  ];
  for (const [name, latex, expected] of solves) {
    it(`${name} still solves`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(true);
      expect(p.finalAnswer?.plain).toBe(expected);
    });
  }
});

describe("limit engine — R6 family H: a log-periodic oscillation aliases the geometric ladder flat", () => {
  // cos(2π·log₁₀ x) has period exactly ONE DECADE, so on the φ·10^k ladder every
  // rung lands on the SAME crest — log₁₀(φ·10^k) = log₁₀φ + k → cos is constant.
  // The φ multiplicative jitter (which beats a LINEAR phase) can't beat a phase
  // that is linear in log x. The ladder read a flat 0.001274 and shipped it, but
  // the limit does NOT exist (oscillates in [−0.005, 0.005] forever). The far-tail
  // audit at DENSE incommensurate phases now sees the full swing at every
  // magnitude (a non-decaying far deviation) and DECLINES.
  const declines: [string, string][] = [
    ["0.005·cos(2π ln x/ln 10) @∞", "\\lim_{x \\to \\infty} 0.005\\cos\\left(\\frac{2\\pi\\ln(x)}{\\ln(10)}\\right)"],
    ["0.005·cos(2π ln x/ln 10) @0⁺", "\\lim_{x \\to 0^+} 0.005\\cos\\left(\\frac{2\\pi\\ln(x)}{\\ln(10)}\\right)"],
    ["2 + 0.005·cos(2π ln x/ln 10) @∞", "\\lim_{x \\to \\infty} \\left(2 + 0.005\\cos\\left(\\frac{2\\pi\\ln(x)}{\\ln(10)}\\right)\\right)"],
  ];
  for (const [name, latex] of declines) {
    it(`${name} → couldn't-verify (DNE)`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(false);
      expect(p.finalAnswer).toBeNull();
    });
  }
});

describe("limit engine — R6 family I: a clean limit just short of its value snaps correctly", () => {
  // A cancellation-prone Taylor limit converges in SHAPE but lands a true few·1e-6
  // short of the exact value ((eˣ−1−x)/x² → 0.499993, off 7e-6 from ½); a squeeze
  // limit lands at the noise floor (x·sin(1/x) → ~3e-6, true 0). Both read as wrong
  // answers. cleanValue now snaps to the nearest simple rational within the run's
  // convergence noise, and a FINITE point carries a ~1e-5 resolution floor (the
  // finest probe is h≈1.6e-6), so these land on the exact value.
  const solves: [string, string, string][] = [
    ["(eˣ−1−x)/x² → 1/2", "\\lim_{x \\to 0} \\frac{e^x-1-x}{x^2}", "1/2"],
    ["(e⁵ˣ−1−5x)/x² → 25/2", "\\lim_{x \\to 0} \\frac{e^{5x}-1-5x}{x^2}", "25/2"],
    ["x·sin(1/x) → 0", "\\lim_{x \\to 0} x \\sin(1/x)", "0"],
    ["2 + x·sin(1/x) → 2", "\\lim_{x \\to 0} (2 + x \\sin(1/x))", "2"],
  ];
  for (const [name, latex, expected] of solves) {
    it(`${name} (snapped to the exact value)`, async () => {
      const p = await solve(classify(latex), NEVER);
      expect(p.verified).toBe(true);
      expect(p.finalAnswer?.plain).toBe(expected);
    });
  }
});
