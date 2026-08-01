import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { parseBoundedTrig, solveBoundedTrig } from "../src/solver/boundedTrig";
import { JsonCompleter } from "../src/solver/narrate";

// The bounded-trig engine is DETERMINISTIC: it enumerates every root in the
// interval and VERIFIES each by substitution into the ORIGINAL equation. The
// LLM is never called — this completer proves it (any call throws).
const NEVER: JsonCompleter = async () => {
  throw new Error("the bounded-trig engine must not call the LLM");
};

/** End-to-end: classify → solve, asserting the deterministic route is taken. */
async function run(latex: string) {
  const cls = classify(latex);
  const payload = await solve(cls, NEVER);
  return { strategy: cls.strategy, payload };
}

describe("parseBoundedTrig — shape gate", () => {
  it("reads `A T(x) + B = C` with a degree interval", () => {
    const s = parseBoundedTrig("\\sin x = \\frac{1}{2} \\text{ for } 0 \\le x \\le 360")!;
    expect(s.fn).toBe("sin");
    expect(s.variable).toBe("x");
    expect(s.c).toBeCloseTo(0.5, 12);
    expect(s.unit).toBe("deg");
    expect(s.loDisplay).toBe(0);
    expect(s.hiDisplay).toBe(360);
    expect(s.loRad).toBeCloseTo(0, 12);
    expect(s.hiRad).toBeCloseTo(2 * Math.PI, 12);
  });

  it("normalizes `2\\sin x - 1 = 0` to `sin x = 1/2`", () => {
    const s = parseBoundedTrig("2\\sin x - 1 = 0 \\text{ for } 0 \\le x \\le 360")!;
    expect(s.fn).toBe("sin");
    expect(s.c).toBeCloseTo(0.5, 12);
  });

  it("reads a radian interval `0 \\le x \\le 2\\pi`", () => {
    const s = parseBoundedTrig("\\sin x = \\frac{1}{2} \\text{ for } 0 \\le x \\le 2\\pi")!;
    expect(s.unit).toBe("rad");
    expect(s.hiRad).toBeCloseTo(2 * Math.PI, 12);
  });

  it("carries the variable name through (θ)", () => {
    const s = parseBoundedTrig("\\cos\\theta = \\frac{1}{2} \\text{ for } 0 \\le \\theta \\le 360")!;
    expect(s.variable).toBe("theta");
    expect(s.fn).toBe("cos");
  });

  it("declines a compound argument `sin(2x)` (arg must be the bare variable)", () => {
    expect(parseBoundedTrig("\\sin(2x) = \\frac{1}{2} \\text{ for } 0 \\le x \\le 360")).toBeNull();
  });

  it("declines a power `sin^2 x` (exactly one trig node, no wrapping)", () => {
    expect(parseBoundedTrig("\\sin^2 x = \\frac{1}{2} \\text{ for } 0 \\le x \\le 360")).toBeNull();
  });

  // Adversarial gate (2026-07): `((tan x − c)^2)^{1/2}` = |tan x − c| parses as NESTED
  // `^` OperatorNodes (no FunctionNode), so wrapsVar never sees it, and the affine
  // sampler is fooled when tan x > c only in a thin sliver near the asymptote that no
  // fixed sample hits — |tan x − c| then looks exactly like c − tan x, and only ONE
  // branch was enumerated (the tan x = c − k roots), the tan x = c + k roots silently
  // dropped, an INCOMPLETE set shipped verified:true. A power whose base encloses the
  // variable is now rejected structurally → decline.
  it("declines a nested-power abs `((tan x − c)^2)^{1/2}` (would drop a branch)", () => {
    expect(parseBoundedTrig("((\\tan x - 3)^2)^{1/2} = 2, 0 \\le x \\le 360")).toBeNull();
    expect(parseBoundedTrig("((\\tan x - 100)^2)^{1/2} = 50, 0 \\le x \\le 180")).toBeNull();
  });

  it("declines when there is no interval to enumerate within", () => {
    expect(parseBoundedTrig("\\sin x = \\frac{1}{2}")).toBeNull();
    expect(parseBoundedTrig("\\tan x = 1")).toBeNull();
  });

  it("declines an ambiguous unit (upper bound > 2π, not a textbook degree, no ° / no π)", () => {
    expect(parseBoundedTrig("\\sin x = 0.5 \\text{ for } 0 \\le x \\le 400")).toBeNull();
  });
});

describe("solveBoundedTrig — enumerate-and-verify", () => {
  it("returns a verified answer listing every root — sin x = 1/2 → 30°, 150°", () => {
    const s = parseBoundedTrig("\\sin x = \\frac{1}{2} \\text{ for } 0 \\le x \\le 360")!;
    const out = solveBoundedTrig(s)!;
    expect(out.answer.plain).toBe("x = 30°, x = 150°");
  });

  it("returns null (declines) when there is no root — sin x = 2", () => {
    const s = parseBoundedTrig("\\sin x = 2 \\text{ for } 0 \\le x \\le 360")!;
    expect(solveBoundedTrig(s)).toBeNull();
  });
});

describe("bounded-trig route — verified degree answers", () => {
  it("sin x = 1/2 → 30°, 150°", async () => {
    const { strategy, payload } = await run("\\sin x = \\frac{1}{2} \\text{ for } 0 \\le x \\le 360");
    expect(strategy).toBe("bounded_trig");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = 30°, x = 150°");
  });

  it("cos x = -√3/2 → 150°, 210°", async () => {
    const { payload } = await run("\\cos x = -\\frac{\\sqrt3}{2}, \\quad 0 \\le x \\le 360");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = 150°, x = 210°");
  });

  it("tan x = 1 → 45°, 225°", async () => {
    const { payload } = await run("\\tan x = 1 \\text{ for } 0 \\le x \\le 360");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = 45°, x = 225°");
  });

  it("2 sin x - 1 = 0 → 30°, 150° (rearranged form)", async () => {
    const { payload } = await run("2\\sin x - 1 = 0 \\text{ for } 0 \\le x \\le 360");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = 30°, x = 150°");
  });

  it("includes the endpoints — cos x = 1 → 0°, 360°", async () => {
    const { payload } = await run("\\cos x = 1 \\text{ for } 0 \\le x \\le 360");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = 0°, x = 360°");
  });

  it("cos x = 0 → 90°, 270°", async () => {
    const { payload } = await run("\\cos x = 0 \\text{ for } 0 \\le x \\le 360");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = 90°, x = 270°");
  });

  it("tan x = 0 keeps all three roots 0°, 180°, 360°", async () => {
    const { payload } = await run("\\tan x = 0 \\text{ for } 0 \\le x \\le 360");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = 0°, x = 180°, x = 360°");
  });

  it("carries the variable name into the answer — cos θ = 1/2", async () => {
    const { payload } = await run("\\cos\\theta = \\frac{1}{2} \\text{ for } 0 \\le \\theta \\le 360");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("theta = 60°, theta = 300°");
  });
});

describe("bounded-trig route — radian answers", () => {
  it("sin x = 1/2 over [0, 2π] → π/6, 5π/6", async () => {
    const { strategy, payload } = await run("\\sin x = \\frac{1}{2} \\text{ for } 0 \\le x \\le 2\\pi");
    expect(strategy).toBe("bounded_trig");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = pi/6, x = 5pi/6");
  });
});

describe("bounded-trig route — honest declines (golden rule)", () => {
  it("declines sin x = 2 (no solution) rather than inventing one", async () => {
    const { strategy, payload } = await run("\\sin x = 2 \\text{ for } 0 \\le x \\le 360");
    expect(strategy).toBe("bounded_trig");
    expect(payload.verified).toBe(false);
    expect(payload.finalAnswer?.plain ?? null).toBeNull();
  });

  it("does NOT claim a bounded-trig answer for sin(2x) (out of shape)", async () => {
    const { strategy } = await run("\\sin(2x) = \\frac{1}{2} \\text{ for } 0 \\le x \\le 360");
    expect(strategy).not.toBe("bounded_trig");
  });

  it("does NOT claim a bounded-trig answer for sin^2 x (out of shape)", async () => {
    const { strategy } = await run("\\sin^2 x = \\frac{1}{2} \\text{ for } 0 \\le x \\le 360");
    expect(strategy).not.toBe("bounded_trig");
  });
});

// Regression: the adversarial gate found 4 golden-rule violations — an OPEN
// interval treated as closed (spurious endpoint roots) and a near-asymptote root
// snapped onto π/2 (where tan is undefined). These lock in the fixes and guard the
// closed-interval + legitimate-π-multiple cases that must keep resolving.
describe("bounded-trig route — gate regressions (open/closed endpoints)", () => {
  it("OPEN 0 < x < 360, cos x = 1 → empty set → decline (not {0°, 360°})", async () => {
    const { strategy, payload } = await run("\\cos x = 1, \\; 0 < x < 360");
    expect(strategy).toBe("bounded_trig");
    expect(payload.verified).toBe(false);
    expect(payload.finalAnswer?.plain ?? null).toBeNull();
  });

  it("HALF-OPEN 0 ≤ x < 360, sin x = 0 → 0°, 180° (drops the 360° copy)", async () => {
    const { payload } = await run("\\sin x = 0, \\; 0 \\le x < 360");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = 0°, x = 180°");
  });

  it("OPEN 0 < x < 360, cos x = 0 keeps the interior roots 90°, 270°", async () => {
    const { payload } = await run("\\cos x = 0, \\; 0 < x < 360");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = 90°, x = 270°");
  });

  it("CLOSED 0 ≤ x ≤ 360 still keeps both endpoints — cos x = 1 → 0°, 360°", async () => {
    const { payload } = await run("\\cos x = 1 \\text{ for } 0 \\le x \\le 360");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = 0°, x = 360°");
  });
});

describe("bounded-trig route — gate regressions (never display an asymptote)", () => {
  it("tan x = 1000000 never renders as π/2 (tan is undefined there)", async () => {
    const { payload } = await run("\\tan x = 1000000 \\text{ for } 0 \\le x \\le 2\\pi");
    // Whether it declines or shows a safe decimal, it must NEVER show the asymptote.
    expect(payload.finalAnswer?.plain ?? "").not.toContain("pi/2");
    expect(payload.finalAnswer?.latex ?? "").not.toContain("\\pi}{2}");
  });

  it("a LEGITIMATE π-multiple radian root still renders — tan x = 1 → π/4, 5π/4", async () => {
    const { payload } = await run("\\tan x = 1 \\text{ for } 0 \\le x \\le 2\\pi");
    expect(payload.verified).toBe(true);
    expect(payload.finalAnswer?.plain).toBe("x = pi/4, x = 5pi/4");
  });
});

// Adversarial gate (2026-07): three confirmed golden-rule holes at the DEDUPE and
// DISPLAY layers — the verify gate passed each individual ROOT, but a downstream
// merge / rounding then presented something that no longer solves the equation.
describe("bounded-trig route — dedupe & display gate regressions (2026-07)", () => {
  const bt = (l: string) => {
    const s = parseBoundedTrig(l);
    if (!s) return null;
    return solveBoundedTrig(s);
  };

  // #1 / #2 — for c just below 1 the TWO distinct near-peak roots sit ~2√(2ε)
  // apart (~9e-7 for ε≈1e-13). The old 1e-6 dedupe MERGED them into one, hiding
  // that both round to the SAME degree string ("90°"). At 1e-9 they stay separate,
  // so the distinctness guard sees the collision and DECLINES rather than show one
  // "90°" that misrepresents a two-root (or effectively no-clean-root) situation.
  it("#1/#2 declines sin x = 0.9999999999999 rather than collapse two roots to one 90°", () => {
    expect(bt(String.raw`\sin x = 0.9999999999999 \text{ for } 0 \le x \le 360`)).toBeNull();
  });

  // #3 — the old 3e-3 display band was WIDER than the substitution error: `tan x =
  // -0.002` shown as "180°, 360°" passed ( tan = 0 there, |0−(−0.002)| = 2e-3 <
  // 3e-3 ) even though 0 ≠ −0.002 under the real gate. displaySafe now uses
  // closeEnough (ABS/REL 1e-4), so those NON-solutions are rejected and the engine
  // ships the TRUE roots (≈179.89°, 359.89°) — never the whole-degree impostors.
  it("#3 never shows the non-solution whole degrees for tan x = -0.002", () => {
    const r = bt(String.raw`\tan x = -0.002 \text{ for } 0 \le x \le 360`);
    expect(r).not.toBeNull(); // the true roots DO exist and verify — it must ship them, not decline
    const plain = r!.answer.plain;
    expect(plain).not.toContain("180°"); // tan 180° = 0 ≠ −0.002
    expect(plain).not.toContain("360°"); // tan 360° = 0 ≠ −0.002
    expect(plain).toContain("179.89°");
    expect(plain).toContain("359.89°");
  });

  // Keep-resolve: neither fix may harm the ordinary cases — a genuine single peak
  // (sin x = 1 → 90°), an ordinary two-root set (sin x = 1/2 → 30°, 150°), and a
  // legit whole-degree root where tan really IS 0 (tan x = 0 → 0°, 180°, 360°).
  it("still resolves the ordinary bounded-trig cases the fixes must not touch", () => {
    expect(bt(String.raw`\sin x = 1 \text{ for } 0 \le x \le 360`)!.answer.plain).toBe("x = 90°");
    expect(bt(String.raw`\sin x = \frac{1}{2} \text{ for } 0 \le x \le 360`)!.answer.plain).toBe(
      "x = 30°, x = 150°"
    );
    expect(bt(String.raw`\tan x = 0 \text{ for } 0 \le x \le 360`)!.answer.plain).toBe(
      "x = 0°, x = 180°, x = 360°"
    );
  });
});
