import { describe, expect, it } from "vitest";
import {
  exactForm,
  quadraticSurdRoots,
  resymbolize,
  squareFreeSplit,
} from "../src/solver/exact";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { JsonCompleter } from "../src/solver/narrate";

// Regression: derivatives and irrational roots must DISPLAY exact symbolic form
// (√2, π, fractions), not decimals — the exact form is the correct SPM/IGCSE
// answer. The verify gate keeps substituting numerically (see solve.test.ts).

/** Narration → {} (fallback labels); never used for the actual math here. */
const narrateOnly: JsonCompleter = async (system) =>
  system.includes("ALREADY-SOLVED") ? {} : {};

describe("exactForm — value → exact symbolic display", () => {
  it("recognizes rational multiples of square roots", () => {
    expect(exactForm(Math.SQRT2)).toMatchObject({ latex: "\\sqrt{2}", plain: "√2" });
    expect(exactForm(-Math.SQRT2)).toMatchObject({ latex: "-\\sqrt{2}" });
    expect(exactForm(Math.sqrt(3))).toMatchObject({ latex: "\\sqrt{3}" });
    expect(exactForm(2 * Math.SQRT2)).toMatchObject({ latex: "2\\sqrt{2}" });
    expect(exactForm(Math.SQRT2 / 2)).toMatchObject({ latex: "\\tfrac{\\sqrt{2}}{2}" });
    // a 6-sig-fig rounded value (what the model returns) still resolves
    expect(exactForm(1.414214)).toMatchObject({ latex: "\\sqrt{2}" });
  });

  it("recognizes rational multiples of π", () => {
    expect(exactForm(Math.PI)).toMatchObject({ latex: "\\pi" });
    expect(exactForm(Math.PI / 6)).toMatchObject({ latex: "\\tfrac{\\pi}{6}" });
  });

  it("returns null for integers, simple fractions and plain decimals", () => {
    expect(exactForm(5)).toBeNull();
    expect(exactForm(0.5)).toBeNull(); // caller renders 1/2
    expect(exactForm(2.5)).toBeNull();
    expect(exactForm(0.4)).toBeNull();
  });
});

describe("resymbolize — de-decimalize a mathjs expression for display", () => {
  it("restores irrational constants but leaves intended decimals", () => {
    expect(resymbolize("3 * cos(3 x) + 1.4142135623730951")).toBe(
      "3 * cos(3 x) + sqrt(2)"
    );
    expect(resymbolize("1.7320508075688772")).toBe("sqrt(3)");
    expect(resymbolize("0.5 + 3.2 * x")).toBe("0.5 + 3.2 * x"); // untouched
  });
});

describe("solve() display — exact form end to end (verify gate unchanged)", () => {
  it("d/dx(√2·x + sin(3x)) shows √2, not 1.414…", async () => {
    const p = await solve(
      classify("\\frac{d}{dx}(\\sqrt{2}\\cdot x + \\sin(3x))"),
      narrateOnly
    );
    expect(p.verified).toBe(true);
    expect(p.methods[0].steps.at(-1)?.expression).toContain("\\sqrt{2}");
    expect(p.methods[0].steps.at(-1)?.expression).not.toMatch(/1\.4142/);
  });

  it("x²−2=0 → x = ±√2, verified, never ±1.414", async () => {
    // Deterministic can't factor it → LLM candidate, which must still pass the
    // numeric substitution gate; the DISPLAY is built as exact √2.
    const p = await solve(classify("x^2 - 2 = 0"), async (system) =>
      system.includes("ALREADY-SOLVED")
        ? {}
        : {
            answerLatex: "x = \\pm\\sqrt{2}",
            answerPlain: "x = ±√2",
            solutions: [
              { variable: "x", value: 1.4142135 },
              { variable: "x", value: -1.4142135 },
            ],
            methods: [],
          }
    );
    expect(p.verified).toBe(true); // the gate still accepts it numerically
    expect(p.finalAnswer?.latex).toContain("\\sqrt{2}");
    expect(p.finalAnswer?.latex).not.toMatch(/1\.414/);
    expect(p.finalAnswer?.plain).toContain("√2");
  });
});

describe("squareFreeSplit", () => {
  it("pulls the largest square factor out", () => {
    expect(squareFreeSplit(12)).toEqual({ k: 2, m: 3 });
    expect(squareFreeSplit(48)).toEqual({ k: 4, m: 3 });
    expect(squareFreeSplit(8)).toEqual({ k: 2, m: 2 });
    expect(squareFreeSplit(5)).toEqual({ k: 1, m: 5 });
    expect(squareFreeSplit(36)).toEqual({ k: 6, m: 1 });
  });

  it("declines what is not a positive integer", () => {
    expect(squareFreeSplit(0)).toBeNull();
    expect(squareFreeSplit(-4)).toBeNull();
    expect(squareFreeSplit(2.5)).toBeNull();
  });
});

describe("quadraticSurdRoots — the surd is built from the algebra, never the float", () => {
  it("x² + 4x + 1: the classic −2 ± √3", () => {
    const roots = quadraticSurdRoots(1, 4, 1)!;
    expect(roots.map((r) => r.plain)).toEqual(["-2 - √3", "-2 + √3"]);
    expect(roots.map((r) => r.latex)).toEqual([
      "-2 - \\sqrt{3}",
      "-2 + \\sqrt{3}",
    ]);
    // The values must be the actual roots — the answer path matches on them.
    expect(roots[0].value).toBeCloseTo(-2 - Math.sqrt(3), 12);
    expect(roots[1].value).toBeCloseTo(-2 + Math.sqrt(3), 12);
  });

  it("keeps the fraction when nothing cancels", () => {
    const roots = quadraticSurdRoots(1, 1, -1)!;
    expect(roots.map((r) => r.plain)).toEqual(["(-1 - √5)/2", "(-1 + √5)/2"]);
  });

  it("cancels the common factor across the whole fraction", () => {
    // (−4 ± 2√6)/4 → (−2 ± √6)/2, not left half-reduced.
    const roots = quadraticSurdRoots(2, 4, -1)!;
    expect(roots.map((r) => r.plain)).toEqual(["(-2 - √6)/2", "(-2 + √6)/2"]);
  });

  it("b = 0 gives a bare surd with no stray zero", () => {
    const roots = quadraticSurdRoots(1, 0, -2)!;
    expect(roots.map((r) => r.plain)).toEqual(["-√2", "√2"]);
  });

  it("a negative leading coefficient still lists roots in value order", () => {
    const roots = quadraticSurdRoots(-1, 0, 2)!;
    expect(roots[0].value).toBeLessThan(roots[1].value);
    for (const r of roots) {
      expect(Math.abs(r.value * r.value - 2)).toBeLessThan(1e-9);
    }
  });

  it("declines when a surd adds nothing", () => {
    expect(quadraticSurdRoots(1, -5, 6)).toBeNull(); // perfect square disc — rational
    expect(quadraticSurdRoots(1, 2, 5)).toBeNull(); // negative disc — no real roots
    expect(quadraticSurdRoots(1, 4, 4)).toBeNull(); // repeated rational root
    expect(quadraticSurdRoots(0, 2, 1)).toBeNull(); // not a quadratic
    expect(quadraticSurdRoots(1, 0.5, -1)).toBeNull(); // non-integer coefficients
  });
});
