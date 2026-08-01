import { describe as describeVitest, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { ODE_POINTEVAL_ENABLED, solve } from "../src/proxy/solve";
import { parseOdePointEval, solveOdePointEval } from "../src/solver/odePointEval";
import { JsonCompleter } from "../src/solver/narrate";

// The ODE point-eval engine is HELD (disabled) pending a scoped redesign — see
// ODE_POINTEVAL_ENABLED in solve.ts. It is a numeric-sampling oracle (two integrators
// that must agree), and an ultra-narrow sub-grid spike in the RHS is stepped over
// identically by both — a golden-rule hole that is irreducible for a fixed grid. While
// it is dormant this whole suite is skipped so the rest of the functions suite stays
// green; the engine and its tests remain committed and revert to a live suite the
// moment the flag flips back to true (its future scoped revival).
const describe = ODE_POINTEVAL_ENABLED ? describeVitest : describeVitest.skip;

// The ODE point-eval engine is DETERMINISTIC: it integrates the IVP with two
// INDEPENDENT integrators (RK4+Richardson and DP5) and returns y(b) only if they
// converge AND agree. The LLM is never called for the math — this completer proves
// it (any call throws). A well-posed IVP that this engine declines falls through to
// the symbolic ODE (llm_candidate) path, where NEVER throws.
const NEVER: JsonCompleter = async () => {
  throw new Error("the ode-point-eval engine must not call the LLM");
};

/** End-to-end classify → solve. Captures the strategy even when a fall-through to
 * the LLM ode path throws (NEVER), so a decline is observable either way. */
async function run(latex: string) {
  const cls = classify(latex);
  try {
    const payload = await solve(cls, NEVER);
    return { strategy: cls.strategy, payload, threw: false as const };
  } catch {
    return { strategy: cls.strategy, payload: null, threw: true as const };
  }
}

describe("parseOdePointEval — determinacy gate", () => {
  it("reads a first-order IVP with a target point", () => {
    const q = parseOdePointEval("y' = y, y(0) = 1, y(1)")!;
    expect(q.order).toBe(1);
    expect(q.at).toBe(0);
    expect(q.y0).toBe(1);
    expect(q.target).toBe(1);
    expect(q.depVar).toBe("y");
  });

  it("reads a second-order IVP with both initial conditions", () => {
    const q = parseOdePointEval("y'' = -y, y(0) = 0, y'(0) = 1, y(1)")!;
    expect(q.order).toBe(2);
    expect(q.y0).toBe(0);
    expect(q.dy0).toBe(1);
    expect(q.target).toBe(1);
  });

  it("declines a numeric-method qualifier (asks for an approximation, not the value)", () => {
    expect(
      parseOdePointEval("Using Euler's method with h = 0.1, y' = y, y(0) = 1, find y(1)")
    ).toBeNull();
    expect(
      parseOdePointEval("Use the Runge-Kutta method: y' = y, y(0) = 1, y(1)")
    ).toBeNull();
  });

  it("declines an underdetermined 2nd-order IVP (only one initial condition)", () => {
    expect(parseOdePointEval("y'' = -y, y(0) = 1, y(1)")).toBeNull();
  });

  it("declines a boundary-value problem (conditions at two different points)", () => {
    expect(parseOdePointEval("y'' = -y, y(0) = 0, y(1) = 1, y(0.5)")).toBeNull();
  });

  it("declines when there is no target point", () => {
    expect(parseOdePointEval("y' = y, y(0) = 1")).toBeNull();
  });
});

describe("solveOdePointEval — cross-checked numeric integration", () => {
  it("integrates y' = y, y(0)=1 to y(1) = e", () => {
    const out = solveOdePointEval(parseOdePointEval("y' = y, y(0) = 1, y(1)")!)!;
    expect(out.answer.plain).toBe("y(1) ≈ 2.71828");
  });

  it("declines an equation implicit in y' ((y')² = y)", () => {
    expect(solveOdePointEval(parseOdePointEval("(y')^2 = y, y(0) = 1, y(1)")!)).toBeNull();
  });

  it("returns the given value when the target IS the initial point", () => {
    const out = solveOdePointEval(parseOdePointEval("y' = y, y(0) = 5, y(0)")!)!;
    expect(out.answer.plain).toBe("y(0) = 5");
  });
});

describe("ode point-eval route — verified values", () => {
  const cases: [string, string][] = [
    ["y' = y, y(0) = 1, y(1)", "y(1) ≈ 2.71828"], // eˣ → e
    ["y' = 2x, y(0) = 0, y(2)", "y(2) ≈ 4"], // x² → 4
    ["y' = -y, y(0) = 1, y(2)", "y(2) ≈ 0.135335"], // e⁻²
    ["y'' = -y, y(0) = 0, y'(0) = 1, y(1)", "y(1) ≈ 0.841471"], // sin 1
    ["y' = y(1-y), y(0) = 0.5, y(1)", "y(1) ≈ 0.731059"], // logistic 1/(1+e⁻ˣ)
  ];
  for (const [latex, expected] of cases) {
    it(`${latex} → ${expected}`, async () => {
      const { strategy, payload } = await run(latex);
      expect(strategy).toBe("ode_point_eval");
      expect(payload?.verified).toBe(true);
      expect(payload?.finalAnswer?.plain).toBe(expected);
    });
  }
});

describe("ode point-eval route — honest declines (never a wrong value)", () => {
  // A decline is safe iff the engine does NOT ship a verified ode_point_eval value —
  // whether it keeps the strategy and returns verified:false, or hands off entirely.
  const declines = [
    "Using Euler's method with h = 0.1, y' = y, y(0) = 1, find y(1)", // method qualifier
    "y'' = -y, y(0) = 1, y(1)", // underdetermined 2nd order
    "y'' = -y, y(0) = 0, y(1) = 1, y(0.5)", // boundary-value problem
    "(y')^2 = y, y(0) = 1, y(1)", // implicit in y'
  ];
  for (const latex of declines) {
    it(`does not ship a verified point-eval value: ${latex}`, async () => {
      const { strategy, payload } = await run(latex);
      const shippedVerifiedPointEval =
        strategy === "ode_point_eval" && payload?.verified === true;
      expect(shippedVerifiedPointEval).toBe(false);
    });
  }
});

describe("ode point-eval route — gate-3 regressions (IC-value / pole / determinacy / nonlinear)", () => {
  // O2 — a fractional / scientific / ×10ᵏ initial value must be read EXACTLY, not
  // truncated to its leading integer. The misread was invisible to the two-integrator
  // gate because both RK4 and DP5 integrated the SAME wrong IVP and agreed.
  it("reads fractional / scientific / ×10ᵏ initial values exactly (not truncated)", () => {
    expect(parseOdePointEval("y' = y, y(0) = 1/2, y(1)")!.y0).toBe(0.5);
    expect(parseOdePointEval("y' = y, y(0) = 3/2, y(1)")!.y0).toBe(1.5);
    expect(parseOdePointEval("y' = y, y(0) = 2.5e2, y(1)")!.y0).toBe(250);
    expect(parseOdePointEval("y' = y, y(0) = 1 \\times 10^{3}, y(1)")!.y0).toBe(1000);
    expect(parseOdePointEval("y' = y, y(0) = \\frac{1}{4}, y(1)")!.y0).toBe(0.25);
  });

  // O3 — a second condition at a DIFFERENT point (over-determined) must not be
  // silently dropped just because its RHS is a \frac; now it registers → the
  // determinacy gate (and the target scan) decline.
  it("declines an over-determined problem whose 2nd condition is a \\frac", () => {
    expect(parseOdePointEval("y' = y, y(0) = 1, y(2) = \\frac{1}{2}")).toBeNull();
  });

  // O1 — a pole STRICTLY between a and b: the grid straddles it (never lands on a
  // node), so both integrators realize the same analytic continuation and agree on
  // a finite value. The peak |y| grows unboundedly under refinement → decline.
  it("declines when a singularity lies between the anchor and the target", () => {
    expect(solveOdePointEval(parseOdePointEval("y' = y/(1-x), y(0) = 1, y(3)")!)).toBeNull();
    expect(solveOdePointEval(parseOdePointEval("y' = y/(1-x), y(0) = 1, y(2)")!)).toBeNull();
  });

  // O4 — nonlinear (multi-valued) in y′: |y'| = y admits both y=eˣ and y=e⁻ˣ, so
  // no single y(b). The linearity probe must sample across 0 to see the kink.
  it("declines an equation with a derivative kink |y'| (multi-valued in y′)", () => {
    expect(solveOdePointEval(parseOdePointEval("|y'| = y, y(0) = 1, y(1)")!)).toBeNull();
  });

  // End-to-end: the corrected fractional/scientific values integrate to the RIGHT
  // number — via the point-eval strategy, verified.
  const correctedValues: [string, string][] = [
    ["y' = y, y(0) = 1/2, y(1)", "y(1) ≈ 1.35914"], // ½·e
    ["y' = y, y(0) = 3/2, y(1)", "y(1) ≈ 4.07742"], // 1.5·e
    ["y' = y, y(0) = 1 \\times 10^{3}, y(1)", "y(1) ≈ 2718.28"], // 1000·e
    ["y' = y, y(0) = 2.5e2, y(1)", "y(1) ≈ 679.57"], // 250·e
  ];
  for (const [latex, expected] of correctedValues) {
    it(`${latex} → ${expected}`, async () => {
      const { strategy, payload } = await run(latex);
      expect(strategy).toBe("ode_point_eval");
      expect(payload?.verified).toBe(true);
      expect(payload?.finalAnswer?.plain).toBe(expected);
    });
  }

  // End-to-end declines: never ship a verified point-eval value for these.
  const declines = [
    "y' = y/(1-x), y(0) = 1, y(3)", // pole in (0, 3)
    "y' = y, y(0) = 1, y(2) = \\frac{1}{2}", // over-determined (inconsistent)
    "|y'| = y, y(0) = 1, y(1)", // nonlinear in y′
  ];
  for (const latex of declines) {
    it(`does not ship a verified point-eval value: ${latex}`, async () => {
      const { strategy, payload } = await run(latex);
      const shipped = strategy === "ode_point_eval" && payload?.verified === true;
      expect(shipped).toBe(false);
    });
  }

  // Guard: legit bounded neighbours the peak-stability gate must NOT over-decline.
  const stillResolve: [string, string][] = [
    ["y' = y, y(0) = 0.5, y(1)", "y(1) ≈ 1.35914"], // decimal control == the 1/2 case
    ["y' = y^2, y(0) = 1, y(0.5)", "y(0.5) ≈ 2"], // finite on [0, 0.5] (the pole is beyond)
    ["y' = y, y(0) = 2, y(3)", "y(3) ≈ 40.1711"], // 2·e³ — bounded and steep
  ];
  for (const [latex, expected] of stillResolve) {
    it(`still resolves (no over-decline): ${latex} → ${expected}`, async () => {
      const { strategy, payload } = await run(latex);
      expect(strategy).toBe("ode_point_eval");
      expect(payload?.verified).toBe(true);
      expect(payload?.finalAnswer?.plain).toBe(expected);
    });
  }
});

describe("ode point-eval route — gate-4 regressions (mixed number / delimiters / nonlinear / uniqueness / resolution)", () => {
  // #1/#2 — a MIXED NUMBER initial value (n\frac{a}{b} = n + a/b, NOT n·a/b) must be
  // read exactly: `2\frac{1}{2}` is 2.5, never 2·½ = 1, nor the bare leading 2. Both
  // integrators inherited the same truncated y₀, so they agreed on a wrong value.
  it("reads a mixed-number initial value as n + a/b (not n·a/b, not the bare integer)", () => {
    expect(parseOdePointEval("y' = y, y(0) = 2\\frac{1}{2}, y(1)")!.y0).toBe(2.5);
    expect(parseOdePointEval("y'' = -y, y(0) = 0, y'(0) = 1\\frac{1}{2}, y(1)")!.dy0).toBe(1.5);
    expect(parseOdePointEval("y' = y, y(0) = -2\\frac{1}{2}, y(1)")!.y0).toBe(-2.5);
  });

  // #3/#4/#6/#7 — a SECOND condition at a different point, written with a decorated
  // equals (`&=` alignment tab, `:=`) or \left\right-wrapped parens, must still
  // register so the determinacy gate declines the over-determined / two-point
  // problem. Otherwise it is invisible to the parser and ships as a well-posed IVP.
  it("declines an over-determined problem whose 2nd condition is decorated (&=, :=, \\left\\right)", () => {
    expect(parseOdePointEval("y' = y, y(0) = 1, y(1) &= 5")).toBeNull();
    expect(parseOdePointEval("y' = y, y(0) = 1, y(2) := 9")).toBeNull();
    expect(parseOdePointEval("y' = y, y(0) = 1, y\\left(2\\right) = 5, y(1)")).toBeNull();
    expect(parseOdePointEval("y' = y, y(0) = 1, y\\left(1\\right) = 5, y(2)")).toBeNull();
  });

  // #5 — nonlinear (and multi-valued) in y′ via a PERIODIC term: y′ + sin(π y′) = x.
  // Integer sampling of the derivative made sin(π·t) look linear (its zeros ARE the
  // integers); the uniform-but-irrational-step linearity probe catches the curvature.
  it("declines a periodic nonlinearity in y′ (sin(π y′))", () => {
    expect(
      solveOdePointEval(parseOdePointEval("y' + \\sin(\\pi y') = x, y(0) = 0, y(1)")!)
    ).toBeNull();
  });

  // #9 — a NON-Lipschitz initial state ⇒ the IVP is NOT unique (Peano gives
  // existence, Picard fails): y′ = 3y^{2/3}, y(0)=0 admits y≡0, y=x³, and delayed
  // cubics. Refuse to ship one arbitrary branch (the trivial y≡0 both realize).
  it("declines a non-Lipschitz / non-unique IVP (y′ = 3y^{2/3}, y(0)=0)", () => {
    expect(solveOdePointEval(parseOdePointEval("y' = 3 y^{2/3}, y(0) = 0, y(2)")!)).toBeNull();
  });

  // #8 — an ultra-thin spike in f (width ≪ step) is stepped over identically by both
  // integrators, which "converge" to a value that misses it. The dense RHS-resolution
  // probe exposes the unsampled spike ⇒ decline (rather than ship ≈0 in place of √π).
  it("declines when the grid steps over an ultra-narrow spike in f", () => {
    expect(
      solveOdePointEval(
        parseOdePointEval("y' = 1000000 e^{-1000000000000 (x - 0.4142136)^2}, y(0) = 0, y(1)")!
      )
    ).toBeNull();
  });

  // The two mixed-number cases integrate to the RIGHT number, verified, point-eval.
  const correctedValues: [string, string][] = [
    ["y' = y, y(0) = 2\\frac{1}{2}, y(1)", "y(1) ≈ 6.7957"], // 2.5·e
    ["y'' = -y, y(0) = 0, y'(0) = 1\\frac{1}{2}, y(1)", "y(1) ≈ 1.26221"], // 1.5·sin 1
  ];
  for (const [latex, expected] of correctedValues) {
    it(`${latex} → ${expected}`, async () => {
      const { strategy, payload } = await run(latex);
      expect(strategy).toBe("ode_point_eval");
      expect(payload?.verified).toBe(true);
      expect(payload?.finalAnswer?.plain).toBe(expected);
    });
  }

  // End-to-end declines: never ship a verified point-eval value for any of these.
  const declines = [
    "y' = y, y(0) = 1, y(1) &= 5", // over-determined via &=
    "y' = y, y(0) = 1, y(2) := 9", // over-determined via :=
    "y' = y, y(0) = 1, y\\left(2\\right) = 5, y(1)", // over-determined via \left\right
    "y' + \\sin(\\pi y') = x, y(0) = 0, y(1)", // periodic nonlinearity in y′
    "y' = 3 y^{2/3}, y(0) = 0, y(2)", // non-Lipschitz / non-unique
    "y' = 1000000 e^{-1000000000000 (x - 0.4142136)^2}, y(0) = 0, y(1)", // grid-missed spike
  ];
  for (const latex of declines) {
    it(`does not ship a verified point-eval value: ${latex}`, async () => {
      const { strategy, payload } = await run(latex);
      const shipped = strategy === "ode_point_eval" && payload?.verified === true;
      expect(shipped).toBe(false);
    });
  }

  // Guard: legit neighbours the new gates must NOT over-decline — a genuinely SHARP
  // but RESOLVABLE Gaussian (the grid refines until it captures the peak, so the
  // dense probe finds nothing the grid missed), √x with the anchor OFF its cusp, and
  // y(0)=0 with a Lipschitz RHS (a unique y≡0, which the Lipschitz gate must allow).
  const stillResolve: [string, string][] = [
    ["y' = 10 e^{-100 (x - 0.5)^2}, y(0) = 0, y(1)", "y(1) ≈ 1.77245"], // ≈√π, resolvable
    ["y' = 100 e^{-10000 (x - 0.5)^2}, y(0) = 0, y(1)", "y(1) ≈ 1.77245"], // sharper, still resolved
    ["y' = \\sqrt{x}, y(1) = 0, y(2)", "y(2) ≈ 1.21895"], // √x, anchor off the cusp
    ["y' = y, y(0) = 0, y(2)", "y(2) ≈ 0"], // Lipschitz at y=0 ⇒ unique y≡0
  ];
  for (const [latex, expected] of stillResolve) {
    it(`still resolves (no over-decline): ${latex} → ${expected}`, async () => {
      const { strategy, payload } = await run(latex);
      expect(strategy).toBe("ode_point_eval");
      expect(payload?.verified).toBe(true);
      expect(payload?.finalAnswer?.plain).toBe(expected);
    });
  }
});

// Adversarial gate (2026-07): four confirmed golden-rule holes where an
// ill-posed / non-integrable problem shipped a confident value. Each hole is a
// PARSE- or SOLVABILITY-layer misread the two-integrator agreement gate is blind
// to (both integrators inherit the same misread), so the fixes force a DECLINE.
describe("ode-point-eval — adversarial gate regressions (2026-07)", () => {
  // #1 / #3 — a SPACING macro between an over-determining condition's `y(b)` and
  // its `=` ( `y(1) \: = 5`, `y(1) \quad = 5` ) hid the `=`, so the extra condition
  // read as a bare TARGET and the ill-posed problem shipped as a well-posed IVP.
  // normalizeOdeLatex now flattens spacing macros → parseInitial sees the 3rd
  // condition → the determinacy gate (initial.length ≠ order) declines.
  it("#1 declines an over-determined IVP whose extra condition hides behind \\:", () => {
    expect(
      parseOdePointEval(String.raw`y'' = -y, y(0) = 0, y'(0) = 1, y(1) \: = 5`)
    ).toBeNull();
  });
  it("#3 declines an over-determined IVP whose extra condition hides behind \\quad", () => {
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, y(1) \quad = 5`)).toBeNull();
    // and the other thin-space macros, for good measure
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, y(1) \; = 5`)).toBeNull();
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, y(1) \, = 5`)).toBeNull();
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, y(1) ~ = 5`)).toBeNull();
  });

  // #4 — a VALUE-FIRST condition ( `5 = y(1)` ) evaded BOTH the forward
  // parseInitial matcher AND findTarget's dep(a) scan, so the over-determining
  // condition vanished and the problem shipped as well-posed. parseInitial now
  // also reads the reversed form → determinacy declines.
  it("#4 declines an over-determined IVP whose extra condition is value-first (5 = y(1))", () => {
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, 5 = y(1)`)).toBeNull();
    expect(
      parseOdePointEval(String.raw`y'' = -y, y(0) = 0, y'(0) = 1, 5 = y(1)`)
    ).toBeNull();
  });

  // #2 — a periodic nonlinearity in y′ TUNED to the single sampling grid
  // ( sin(π√2·y′), whose zeros sit at multiples of 1/√2 ) landed every sample on a
  // zero and read as linear, so an equation this engine cannot integrate shipped a
  // wrong value. A second, incommensurate grid (1/√3) no single frequency can also
  // zero out now exposes the curvature → isExplicitlySolvable declines.
  it("#2 declines a y′-nonlinearity tuned to the old grid ( sin(π√2·y′) )", () => {
    const q = parseOdePointEval(
      String.raw`y' + 0.1\sin(\pi \sqrt{2} y') = y, y(0) = 1, y(1)`
    );
    expect(q).not.toBeNull(); // shape is a well-posed IVP — the decline is at the solvability gate
    expect(solveOdePointEval(q!)).toBeNull();
  });

  // Keep-resolve: the 2nd grid must NOT over-decline a residual that is genuinely
  // linear in y′ (even when nonlinear in y itself) — second differences stay 0 on
  // BOTH grids, so it still integrates.
  it("still resolves a nonlinear-in-y but linear-in-y′ IVP (y′ = sin y)", async () => {
    const { strategy, payload } = await run(String.raw`y' = \sin(y), y(0) = 1, y(1)`);
    expect(strategy).toBe("ode_point_eval");
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain).toBe("y(1) ≈ 1.95629");
  });
});

// Adversarial gate ROUND 2 (2026-07): the fresh re-gate of the fixes above found
// SIX more golden-rule holes — sibling misreads the first round's patches left
// open. Same discipline: each is a parse/solvability misread both integrators
// inherit, so every fix forces a DECLINE (never a confident wrong value).
describe("ode-point-eval — adversarial gate regressions ROUND 2 (2026-07)", () => {
  // #1 / #2 / #6 — a boundary / over-determining condition whose VALUE is symbolic
  // (√5, √7, π) is invisible to the numeric IC matcher, so it dropped silently and
  // the over-determined / inconsistent problem shipped as a well-posed IVP. A
  // clause-count guard (every `dep(number) =` / `= dep(number)`, ANY value) now
  // outnumbers the parsed conditions when one was dropped ⇒ decline.
  it("#1 declines an over-determined BVP with a √ boundary value (y(1)=√5)", () => {
    expect(
      parseOdePointEval(String.raw`y'' + y = 0, y(0) = 0, y'(0) = 1, y(1) = \sqrt{5}, y(2)`)
    ).toBeNull();
  });
  it("#2 declines an over-determined IVP with a √ 2nd condition (y(1)=√7)", () => {
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, y(1) = \sqrt{7}, y(3)`)).toBeNull();
  });
  it("#6 declines an over-determining VALUE-FIRST symbolic condition (π = y(2))", () => {
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, \pi = y(2)`)).toBeNull();
    // e = y(2) too — any symbolic constant on the value side
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, e = y(2)`)).toBeNull();
  });

  // #5 — a NAMED spacing macro (\thinspace and siblings) the round-1 allowlist
  // missed hid an over-determining condition's `=`, so `y(2) \thinspace = 99` read
  // as a bare target. normalizeOdeLatex now flattens the named spacing family.
  it("#5 declines an over-determined IVP whose `=` hides behind \\thinspace", () => {
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, y(2) \thinspace = 99`)).toBeNull();
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, y(2) \medspace = 99`)).toBeNull();
    expect(parseOdePointEval(String.raw`y' = y, y(0) = 1, y(2) \enspace = 99`)).toBeNull();
  });

  // #3 — a residual QUADRATIC in y′ with a huge CONSTANT offset (10y′+(y′)²=10⁹):
  // the old Σ|rs| scale was inflated by the 10⁹ constant so the linearity tolerance
  // swallowed the genuine 2·H² curvature and the equation was linearized to a wrong
  // slope. The tolerance now tracks the residual's SPREAD (max−min), which the
  // constant cancels out of ⇒ the curvature is seen ⇒ decline.
  it("#3 declines a quadratic-in-y′ residual with a huge constant offset", () => {
    expect(
      solveOdePointEval(parseOdePointEval(String.raw`10y' + (y')^2 = 1000000000, y(0)=1, y(1)`)!)
    ).toBeNull();
  });

  // #4 — Peano non-uniqueness living in the DERIVATIVE component: y″ = 3(y′)^{2/3},
  // y′(0)=0 admits multiple solutions, but the Lipschitz gate only perturbed y, not
  // y′, so it declared the singular state Lipschitz and shipped the trivial branch.
  // The gate now perturbs EVERY state component ⇒ the y′ singularity is seen.
  it("#4 declines a 2nd-order IVP non-Lipschitz in y′ (y″ = 3(y′)^{2/3}, y′(0)=0)", () => {
    expect(
      solveOdePointEval(parseOdePointEval(String.raw`y'' = 3(y')^{2/3}, y(0) = 0, y'(0) = 0, y(2)`)!)
    ).toBeNull();
  });

  // End-to-end: none of the six ship a verified point-eval value.
  const declines = [
    String.raw`y'' + y = 0, y(0) = 0, y'(0) = 1, y(1) = \sqrt{5}, y(2)`,
    String.raw`y' = y, y(0) = 1, y(1) = \sqrt{7}, y(3)`,
    String.raw`10y' + (y')^2 = 1000000000, y(0)=1, y(1)`,
    String.raw`y'' = 3(y')^{2/3}, y(0) = 0, y'(0) = 0, y(2)`,
    String.raw`y' = y, y(0) = 1, y(2) \thinspace = 99`,
    String.raw`y' = y, y(0) = 1, \pi = y(2)`,
  ];
  for (const latex of declines) {
    it(`does not ship a verified point-eval value: ${latex}`, async () => {
      const { strategy, payload } = await run(latex);
      const shipped = strategy === "ode_point_eval" && payload?.verified === true;
      expect(shipped).toBe(false);
    });
  }

  // Keep-resolve guards — the six fixes must NOT over-decline these legit neighbours:
  //  • the standard IVP (one numeric condition) still resolves,
  //  • a 2nd-order RHS singular in y′ but at a NON-singular y′(0)=1 still resolves,
  //  • a fractional IC value is not mistaken for a dropped symbolic value.
  const stillResolve: [string, string][] = [
    [String.raw`y' = y, y(0) = 1, y(1)`, "y(1) ≈ 2.71828"],
    [String.raw`y'' = 3(y')^{2/3}, y(0) = 0, y'(0) = 1, y(2)`, "y(2) ≈ 20"],
    [String.raw`y' = y, y(0) = \frac{1}{2}, y(1)`, "y(1) ≈ 1.35914"],
  ];
  for (const [latex, expected] of stillResolve) {
    it(`still resolves (no over-decline): ${latex} → ${expected}`, async () => {
      const { strategy, payload } = await run(latex);
      expect(strategy).toBe("ode_point_eval");
      expect(payload?.verified).toBe(true);
      expect(payload?.finalAnswer?.plain).toBe(expected);
    });
  }
});

// Adversarial gate ROUND 3 (2026-07-27): the fresh re-gate of the ROUND-2 fixes found
// EIGHT more holes in three clusters. Clusters A and B are CLOSED here (a parse /
// linearity misread both integrators inherit → forced DECLINE); Cluster C (an
// ultra-narrow sub-grid spike) proved IRREDUCIBLE for a fixed-grid sampler and is WHY
// the whole engine is now HELD (ODE_POINTEVAL_ENABLED=false) — documented by the
// skipped case below. (These run on the engine's future scoped revival, when the flag
// flips back — see the skip guard at the top of this file.)
describe("ode-point-eval — adversarial gate regressions ROUND 3 (2026-07)", () => {
  // Cluster A — a condition whose POINT is non-numeric (π, 1e0, \frac12, .5) is invisible
  // to parseInitial's `-?\d+(?:\.\d+)?` point matcher, so it dropped silently and an
  // over-determined problem shipped as a well-posed IVP. The clause counter now matches
  // ANY paren-free point (`dep(…) =` / `= dep(…)`), so it outnumbers the parsed
  // conditions when one is dropped ⇒ decline. (The bare target dep(b) carries no `=`.)
  const clusterA: [string, string][] = [
    ["y(π)=5 symbolic point", String.raw`y' = y, y(0)=1, y(\pi)=5, y(3)`],
    ["y(1e0)=5 scientific point", String.raw`y' = y, y(0)=1, y(1e0)=5, y(3)`],
    ["y(\\frac12)=5 fraction point", String.raw`y' = y, y(0)=1, y(\frac{1}{2})=5, y(3)`],
    ["y(.5)=5 leading-dot point", String.raw`y' = y, y(0)=1, y(.5)=5, y(3)`],
    ["2nd-order y(π)=5 over-det", String.raw`y'' = -y, y(0)=0, y'(0)=1, y(\pi)=5, y(1)`],
  ];
  for (const [name, latex] of clusterA) {
    it(`A: declines an over-determined IVP with a non-numeric condition point — ${name}`, () => {
      expect(parseOdePointEval(latex)).toBeNull();
    });
  }

  // Cluster B — a residual NONLINEAR in the top derivative but crafted to read as LINEAR
  // on ANY fixed sampling lattice: sin(π√2 y′)·sin(π√3 y′) vanishes on both incommensurate
  // grids at once, so numeric second-differences can't see it. A SYMBOLIC affine check
  // now differentiates the residual w.r.t. the top-derivative token — ∂F/∂y′ still
  // contains y′ ⇒ nonlinear ⇒ decline. A symbolic derivative cannot be fooled by a lattice.
  const clusterB = [
    String.raw`y' + \sin(\pi\sqrt{2} y')\sin(\pi\sqrt{3} y') = x, y(0)=0, y(1)`,
    String.raw`y' = 2 + \sin(\pi\sqrt{2} y')\sin(\pi\sqrt{3} y'), y(0)=0, y(1)`,
    String.raw`y' = 3 - \sin(\pi\sqrt{2} y')\sin(\pi\sqrt{3} y'), y(0)=0, y(1)`,
  ];
  for (const latex of clusterB) {
    it(`B: declines a product-of-sines residual nonlinear in y′ — ${latex}`, () => {
      const q = parseOdePointEval(latex);
      // It parses as an IVP; the symbolic affine gate inside solve must then refuse it.
      expect(q === null || solveOdePointEval(q) === null).toBe(true);
    });
  }

  // The symbolic affine gate must NOT over-decline a residual nonlinear only in a LOWER
  // derivative: y″ = (y′)² is perfectly integrable (linear in the TOP token y″).
  it("keeps y″ = (y′)² resolvable (nonlinear in y′, AFFINE in the top derivative y″)", () => {
    const q = parseOdePointEval(String.raw`y'' = (y')^2, y(0) = 0, y'(0) = 1, y(0.5)`)!;
    const r = solveOdePointEval(q);
    expect(r).not.toBeNull();
    expect(r!.answer.plain).toBe("y(0.5) ≈ 0.693147"); // −ln(1−x) at x=½
  });

  // Cluster C — an ultra-narrow spike in the RHS (width ~1e−7) placed by a code-reading
  // adversary in a gap of BOTH integrators' grids: both step over it and agree on 0 while
  // the true value is ≈1. No FIXED sampling scheme resolves an arbitrarily narrow feature
  // (spacing must be < width, but the adversary picks any width and can hide it in small
  // literals or products that defeat a magnitude cap) — information-theoretically
  // irreducible. THIS is why the engine is HELD. Un-skip only once a revival verifies the
  // resolvable subclass EXACTLY (interval arithmetic / a closed-form path), not by sampling.
  it.skip("Cluster C (HELD): ultra-narrow spike — irreducible for a fixed-grid sampler", () => {
    const q = parseOdePointEval(
      String.raw`y' = 5640000 e^{-100000000000000 (x - 0.333333969116211)^2}, y(0)=0, y(1)`
    )!;
    const r = solveOdePointEval(q);
    // The behaviour a scoped revival must reach: resolve to ≈1 OR decline — never the
    // current silent 0. (Skipped: today's fixed-grid sampler still ships 0.)
    const shipped = r === null ? null : Number(r.answer.plain.split("≈")[1]);
    expect(r === null || Math.abs((shipped as number) - 0.999664) < 1e-3).toBe(true);
  });

  // Keep-resolve — the ROUND-3 fixes must not over-decline these legit neighbours.
  const stillResolveR3: [string, string][] = [
    [String.raw`y' = y, y(0) = 1, y(1)`, "y(1) ≈ 2.71828"],
    [String.raw`y'' = -y, y(0) = 0, y'(0) = 1, y(1)`, "y(1) ≈ 0.841471"],
    [String.raw`y' = \sin(y), y(0) = 1, y(1)`, "y(1) ≈ 1.95629"],
    [String.raw`y' = y, y(0) = \frac{1}{2}, y(1)`, "y(1) ≈ 1.35914"],
  ];
  for (const [latex, expected] of stillResolveR3) {
    it(`still resolves (no over-decline): ${latex} → ${expected}`, async () => {
      const { strategy, payload } = await run(latex);
      expect(strategy).toBe("ode_point_eval");
      expect(payload?.verified).toBe(true);
      expect(payload?.finalAnswer?.plain).toBe(expected);
    });
  }
});
