// Complex numbers — DETERMINISTIC. Every arithmetic answer is re-computed in
// the real 2×2 matrix representation of ℂ (a+bi ≅ aI+bJ), which shares no code
// path with mathjs's complex type; the other tasks are gated on their defining
// property (r² = a²+b², z·z̄ = |z|², wⁿ = z, substitution for the root families).
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("complex numbers are deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return {
    type: c.problemType,
    strategy: c.strategy,
    verified: p.verified,
    plain: p.finalAnswer?.plain,
    latex: p.finalAnswer?.latex,
  };
}

describe("classify + solve — complex arithmetic (a + bi)", () => {
  it("Oxford 6.1(a) — a product", async () => {
    const r = await run(String.raw`(3+4i)(2-i)`);
    expect(r).toMatchObject({
      type: "complex_standard_form",
      strategy: "complex",
      verified: true,
      plain: "10 + 5i",
    });
  });

  it("Oxford 6.1(b) — a quotient rationalises", async () => {
    const r = await run(String.raw`\text{Express in the form } a+bi: \frac{3+4i}{1-2i}`);
    // (3+4i)(1+2i)/5 = (−5+10i)/5 = −1 + 2i
    expect(r).toMatchObject({ verified: true, plain: "-1 + 2i" });
  });

  it("a reciprocal keeps EXACT fractions, never decimals", async () => {
    const r = await run(String.raw`\text{Reduce } \frac{1}{2+3i} \text{ to the form } a+bi`);
    expect(r.verified).toBe(true);
    expect(r.plain).toBe("2/13 - 3/13i");
  });

  it("a high power by De Moivre — (1+i)^8 = 16", async () => {
    const r = await run(String.raw`\text{Evaluate } (1+i)^8`);
    expect(r).toMatchObject({ verified: true, plain: "16" });
  });

  it("i^2 = -1 (the whole point)", async () => {
    const r = await run(String.raw`\text{Simplify } (2+3i)(2-3i)`);
    expect(r).toMatchObject({ verified: true, plain: "13" });
  });

  it("a purely imaginary result prints as 'i', not '1i'", async () => {
    const r = await run(String.raw`\text{Express } (1+i)^2 \text{ in the form } a+bi`);
    expect(r).toMatchObject({ verified: true, plain: "2i" });
  });
});

describe("classify + solve — modulus, argument, conjugate, polar", () => {
  it("modulus of 3+4i is exactly 5", async () => {
    const r = await run(String.raw`\text{Find the modulus of } 3+4i`);
    expect(r).toMatchObject({ type: "complex_modulus", verified: true, plain: "|z| = 5" });
  });

  it("modulus of 1+i is √2 — exact, not 1.414", async () => {
    const r = await run(String.raw`\text{Find the modulus of } 1+i`);
    expect(r.verified).toBe(true);
    expect(r.latex).toBe("|z| = \\sqrt{2}");
  });

  it("argument of 1+i is π/4 (exact multiple of π)", async () => {
    const r = await run(String.raw`\text{Find the argument of } 1+i`);
    expect(r).toMatchObject({ type: "complex_argument", verified: true });
    expect(r.latex).toBe("\\arg z = \\tfrac{\\pi}{4}");
  });

  it("the argument is the PRINCIPAL value — arg(-1) is π, not 3π or -π", async () => {
    const r = await run(String.raw`\text{Find the argument of } -1 + 0i`);
    expect(r.verified).toBe(true);
    expect(r.latex).toBe("\\arg z = \\pi");
  });

  it("a third-quadrant argument is negative (principal branch)", async () => {
    const r = await run(String.raw`\text{Find the argument of } -1-i`);
    expect(r.verified).toBe(true);
    expect(r.latex).toBe("\\arg z = -\\tfrac{3\\pi}{4}");
  });

  it("conjugate flips the imaginary sign", async () => {
    const r = await run(String.raw`\text{Find the conjugate of } 3-5i`);
    expect(r).toMatchObject({ type: "complex_conjugate", verified: true });
    expect(r.latex).toBe("\\bar{z} = 3 + 5i");
  });

  it("reads \\bar{z} notation, which had no ascii spelling at all", async () => {
    const r = await run(String.raw`\text{Simplify } \bar{z} \text{ where } z = 2+3i`);
    // Before conjugates were rewritten, `\bar{z}` became the variables b,a,r,z.
    expect(r.strategy).toBe("complex");
  });

  it("modulus AND argument together give the polar form", async () => {
    const r = await run(String.raw`\text{Find the modulus and argument of } 1 + i\sqrt{3}`);
    expect(r).toMatchObject({ type: "complex_polar_form", verified: true });
    expect(r.latex).toBe("2\\left(\\cos \\tfrac{\\pi}{3} + i\\sin \\tfrac{\\pi}{3}\\right)");
  });

  it("'polar form' is enough on its own", async () => {
    const r = await run(String.raw`\text{Express } -2i \text{ in polar form}`);
    expect(r).toMatchObject({ type: "complex_polar_form", verified: true });
    expect(r.latex).toContain("-\\tfrac{\\pi}{2}");
  });

  it("real and imaginary parts", async () => {
    const a = await run(String.raw`\text{Find the real part of } \frac{1}{1+i}`);
    const b = await run(String.raw`\text{Find the imaginary part of } \frac{1}{1+i}`);
    expect(a).toMatchObject({ verified: true, plain: "real part = 1/2" });
    expect(b).toMatchObject({ verified: true, plain: "imaginary part = -1/2" });
  });
});

describe("classify + solve — nth roots (De Moivre)", () => {
  it("the three cube roots of 1 are distinct and each cubes back to 1", async () => {
    const r = await run(String.raw`\text{Find the cube roots of } 1 + 0i`);
    expect(r).toMatchObject({ type: "complex_roots", verified: true });
    expect(r.plain).toContain("z0 = 1");
    expect(r.plain).toContain("z1 = -1/2 + ");
    expect(r.plain).toContain("z2 = -1/2 - ");
  });

  it("the two square roots of i", async () => {
    const r = await run(String.raw`\text{Find the square roots of } 0 + i`);
    expect(r.verified).toBe(true);
    // e^{iπ/4} and its negative
    expect(r.plain).toContain("z0 = ");
    expect(r.plain?.split(",").length).toBe(2);
  });

  it("the four fourth roots of -4", async () => {
    const r = await run(String.raw`\text{Find the fourth roots of } -4 + 0i`);
    expect(r).toMatchObject({ verified: true });
    // ±1±i
    expect(r.plain).toBe("z0 = 1 + i, z1 = -1 + i, z2 = -1 - i, z3 = 1 - i");
  });
});

describe("classify + solve — equations over ℂ", () => {
  it("e^z = -1 has no real solution; over ℂ it is the family (2n+1)πi", async () => {
    const r = await run(String.raw`\text{Solve } e^{z} = -1`);
    expect(r).toMatchObject({ type: "complex_equation", verified: true });
    expect(r.latex).toContain("2n\\pi i");
    expect(r.latex).toContain("\\mathbb{Z}");
  });

  it("cosh z = 0 — roots only off the real axis", async () => {
    const r = await run(String.raw`\text{Find the complex roots of } \cosh z = 0`);
    expect(r).toMatchObject({ verified: true });
    expect(r.latex).toContain("2n\\pi i");
  });

  it("cos z = 2 is unsolvable over ℝ but solvable over ℂ", async () => {
    const r = await run(String.raw`\text{Solve } \cos z = 2`);
    expect(r).toMatchObject({ type: "complex_equation", verified: true });
    // ±i·arccosh(2) + 2nπ — the answer is a family, and every member was
    // substituted back into cos z = 2 before it was allowed out.
    expect(r.latex).toContain("2n\\pi");
  });

  it("sin z = 3 likewise", async () => {
    const r = await run(String.raw`\text{Solve } \sin z = 3 \text{ over the complex numbers}`);
    expect(r.verified).toBe(true);
  });
});

// The engine must not annex problems that belong elsewhere, and must not answer
// what it cannot prove. Each of these is a DECLINE, not a wrong answer.
describe("complex engine — declines", () => {
  it("leaves ordinary real arithmetic alone", () => {
    const c = classify(String.raw`(3+4)(2-1)`);
    expect(c.strategy).not.toBe("complex");
  });

  it("leaves a real trig equation on the trig engines", () => {
    // cos x = 1/2 has real solutions — nothing complex about it.
    const c = classify(String.raw`\text{Solve } \cos x = \frac{1}{2}`);
    expect(c.strategy).not.toBe("complex");
  });

  it("leaves e^x = 5 on the real engines", () => {
    const c = classify(String.raw`\text{Solve } e^{x} = 5`);
    expect(c.strategy).not.toBe("complex");
  });

  it("does not annex an integral that happens to contain i", () => {
    const c = classify(String.raw`\int (1+i) \, dx`);
    expect(c.strategy).not.toBe("complex");
  });

  it("does not annex a matrix", () => {
    const c = classify(String.raw`\begin{pmatrix} 1 & i \\ 0 & 1 \end{pmatrix}`);
    expect(c.strategy).not.toBe("complex");
  });

  it("an expression with a FREE variable is not a number the oracle can check", () => {
    // `z + i` has no value; the matrix oracle throws on the free symbol and the
    // engine declines rather than inventing one.
    const c = classify(String.raw`\text{Express } z + i \text{ in the form } a+bi`);
    expect(c.strategy).not.toBe("complex");
  });

  it("the argument of 0 is undefined — decline, never 0", async () => {
    const r = await run(String.raw`\text{Find the argument of } 0 + 0i`);
    expect(r.verified).not.toBe(true);
  });
});
