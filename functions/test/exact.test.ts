import { describe, expect, it } from "vitest";
import { exactForm, resymbolize } from "../src/solver/exact";
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
