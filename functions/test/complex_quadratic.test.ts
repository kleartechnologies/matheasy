// A quadratic whose coefficients are COMPLEX — `z² − (4+i)z + (5+5i) = 0` — and
// its degenerate case `ω² = −5 − 12i`. The first was handed to the real
// quadratic engine, which has no imaginary unit and died with "No term with
// symbol: z"; the second dead-ended at the tutor. A real quadratic with a
// NEGATIVE discriminant is the same gap from the other side: its roots are a
// conjugate pair and the real engine has nothing to say about them.
//
// The gate shares nothing with the answer. The roots come from the quadratic
// formula and a polar square root; each one is then substituted back into the
// original equation and evaluated in the real 2×2 MATRIX representation, where
// there is no complex type and no square root at all. Completeness is proven
// separately — `a(z − r₁)(z − r₂)` has to reproduce the equation everywhere.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("a quadratic over ℂ is deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { type: c.problemType, verified: p.verified, plain: p.finalAnswer?.plain };
}

describe("complex coefficients", () => {
  it("z² − (4+i)z + (5+5i) = 0", async () => {
    const r = await run(String.raw`\text{Solve } z^2 - (4+i)z + (5+5i) = 0`);
    expect(r).toMatchObject({
      type: "complex_quadratic",
      verified: true,
      plain: "z = 3 - i, z = 1 + 2i",
    });
  });

  it("reads the same equation behind a longer directive", async () => {
    const r = await run(String.raw`\text{Solve the equation } z^2 - (4+i)z + (5+5i) = 0`);
    expect(r.plain).toBe("z = 3 - i, z = 1 + 2i");
  });

  it("ω² = −5 − 12i — b = 0, so it reads as taking square roots", async () => {
    const r = await run(String.raw`\text{Solve } \omega^2 = -5-12i`);
    expect(r).toMatchObject({
      type: "complex_quadratic",
      verified: true,
      plain: "omega = 2 - 3i, omega = -2 + 3i",
    });
  });

  it("the same, worded as a condition on ω", async () => {
    const r = await run(String.raw`\text{Find } \omega \text{ such that } \omega^2 = -5 - 12i`);
    expect(r.plain).toBe("omega = 2 - 3i, omega = -2 + 3i");
  });

  it("a leading coefficient that is itself complex", async () => {
    const r = await run(String.raw`\text{Solve } (1+i)z^2 + 2z - (3-i) = 0`);
    expect(r).toMatchObject({ type: "complex_quadratic", verified: true });
  });

  it("`2iz` — the glued run mathjs reads as a variable called `iz`", async () => {
    // Discriminant zero. −b/2a is exact where ±√0 is ~1e-8, which is the
    // difference between printing `i` and printing `0 + 1i`.
    const r = await run(String.raw`\text{Solve } z^2 - 2iz - 1 = 0`);
    expect(r).toMatchObject({ verified: true, plain: "z = i (repeated)" });
  });

  it("z² = i", async () => {
    const r = await run(String.raw`\text{Solve } z^2 = i`);
    expect(r).toMatchObject({ type: "complex_quadratic", verified: true });
  });
});

describe("real coefficients, no real roots", () => {
  it("z² + 2z + 5 = 0 gives the conjugate pair", async () => {
    const r = await run(String.raw`\text{Solve } z^2 + 2z + 5 = 0`);
    expect(r).toMatchObject({
      type: "complex_quadratic",
      verified: true,
      plain: "z = -1 + 2i, z = -1 - 2i",
    });
  });

  it("x² + 4 = 0 only when the question asks for complex roots", async () => {
    const asked = await run(String.raw`\text{Find the complex roots of } x^2 + 4 = 0`);
    expect(asked).toMatchObject({ verified: true, plain: "x = 2i, x = -2i" });
    // Without the word, `x` is a REAL unknown and this stays a real quadratic —
    // answering with an imaginary pair would be answering a different question.
    expect(classify(String.raw`\text{Solve } x^2 + 4 = 0`).problemType).toBe("quadratic_equation");
  });
});

describe("zⁿ = c", () => {
  it("z³ = 8i has three roots, none of them real", async () => {
    const r = await run(String.raw`\text{Solve } z^3 = 8i`);
    expect(r).toMatchObject({ type: "complex_roots", verified: true });
    expect(r.plain).toBe("z0 = √3 + i, z1 = -√3 + i, z2 = -2i");
  });

  it("z⁴ = −16", async () => {
    const r = await run(String.raw`\text{Solve } z^4 = -16`);
    expect(r).toMatchObject({ type: "complex_roots", verified: true });
    expect(r.plain?.split(", ")).toHaveLength(4);
  });

  it("x³ = 8 is a REAL question and keeps its engine", () => {
    expect(classify(String.raw`\text{Solve } x^3 = 8`).problemType).not.toBe("complex_roots");
  });
});

// The coefficients are read off three evaluations and then CHECKED at five more
// points off the real axis. Anything that is not a quadratic disagrees there.
describe("what it refuses", () => {
  const notQuadratic = [
    String.raw`\text{Solve } z^3 + iz = 0`,
    String.raw`\text{Solve } \frac{1}{z} + i = 0`,
    String.raw`\text{Solve } z^2 + \sin(z) + i = 0`,
    String.raw`\text{Solve } iz + 3 = 0`,
    String.raw`\text{Solve } e^{iz} = 2`,
  ];
  for (const q of notQuadratic) {
    it(`declines ${q.slice(14)}`, () => {
      expect(classify(q).problemType).not.toBe("complex_quadratic");
    });
  }
});

describe("no regression — the engines that already worked", () => {
  const kept: [string, string][] = [
    [String.raw`\text{Solve } x^2 - 5x + 6 = 0`, "quadratic_equation"],
    [String.raw`\text{Solve } z^2 - 5z + 6 = 0`, "quadratic_equation"],
    [String.raw`\text{Solve } z^2 - 2z + 1 = 0`, "quadratic_equation"],
    [String.raw`\text{Solve } 2x + 5 = 15`, "linear_equation"],
    [String.raw`\text{Solve } \sin x = 0.5`, "trigonometric_equation"],
    [String.raw`\text{Find the modulus of } 3+4i`, "complex_modulus"],
    [String.raw`\text{Solve } e^z = -1`, "complex_equation"],
    [
      String.raw`\text{Express } \frac{3+4i}{1-2i} \text{ in the form } a+bi`,
      "complex_standard_form",
    ],
    [String.raw`\text{Find the square roots of } -5-12i`, "complex_roots"],
  ];
  for (const [q, type] of kept) {
    it(`${type}: ${q.slice(0, 44)}…`, () => {
      expect(classify(q).problemType).toBe(type);
    });
  }
});
