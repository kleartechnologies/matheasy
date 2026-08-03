// Sheets 8–10, the two vector questions that SOLVE for something rather than
// evaluate it: "find λ so that a + λb is perpendicular to c", and "express d in
// terms of the non-coplanar a, b, c".
//
// Both are proved by putting the answer back into the sentence that defined it —
// the λ must make the dot product actually vanish, and the coefficients must
// actually rebuild d component by component. Neither check re-uses the formula
// that produced the number.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("vector algebra is deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { type: c.problemType, verified: p.verified, plain: p.finalAnswer?.plain };
}

describe("solving for λ in a perpendicularity condition", () => {
  it("(1,2,3) + λ(1,1,0) ⊥ (1,0,1) gives λ = -4", async () => {
    // a·c = 4, b·c = 1, so λ = −4.
    const r = await run(
      String.raw`\text{Find the value of } \lambda \text{ such that } (1, 2, 3) + \lambda (1, 1, 0) \text{ is perpendicular to } (1, 0, 1)`
    );
    expect(r).toMatchObject({
      type: "vector_perpendicular_lambda",
      verified: true,
      plain: "λ = -4",
    });
  });

  it("works in the plane, and 'orthogonal' is the same word", async () => {
    const r = await run(
      String.raw`\text{Find } \lambda \text{ so that } (1, 0) + \lambda (0, 1) \text{ is orthogonal to } (1, 1)`
    );
    expect(r).toMatchObject({ verified: true, plain: "λ = -1" });
  });

  it("a non-integer λ keeps its exact value", async () => {
    // a·c = 5, b·c = 2 → λ = −2.5.
    const r = await run(
      String.raw`\text{Find } \lambda \text{ such that } (1, 2) + \lambda (2, 0) \text{ is perpendicular to } (1, 2)`
    );
    expect(r).toMatchObject({ verified: true, plain: "λ = -2.5" });
  });

  it("when b ⊥ c there is no λ to find — decline, never divide by zero", async () => {
    // b·c = 0 and a·c ≠ 0: the condition is unsatisfiable for every λ.
    const r = await run(
      String.raw`\text{Find } \lambda \text{ such that } (1, 2, 3) + \lambda (1, 1, 1) \text{ is perpendicular to } (1, -1, 0)`
    );
    expect(r.verified).not.toBe(true);
  });

  it("without a scalar between the first two vectors there is nothing to solve for", async () => {
    const r = await run(
      String.raw`\text{Is } (1, 2, 3) + (1, 1, 0) \text{ perpendicular to } (1, 0, 1)?`
    );
    expect(r.type).not.toBe("vector_perpendicular_lambda");
  });
});

describe("expressing a vector in a non-coplanar basis", () => {
  it("the standard basis reads the components straight off", async () => {
    const r = await run(
      String.raw`\text{Express } (5, 6, 7) \text{ in terms of } (1, 0, 0), (0, 1, 0) \text{ and } (0, 0, 1)`
    );
    expect(r).toMatchObject({
      type: "vector_basis_expansion",
      verified: true,
      plain: "v = 5a + 6b + 7c",
    });
  });

  it("a genuinely skew basis — (4,5,6) over (1,1,0), (0,1,1), (1,0,1)", async () => {
    // α + γ = 4, α + β = 5, β + γ = 6 ⇒ α+β+γ = 7.5 ⇒ (1.5, 3.5, 2.5).
    const r = await run(
      String.raw`\text{Express the vector } (4, 5, 6) \text{ in terms of } (1, 1, 0), (0, 1, 1) \text{ and } (1, 0, 1)`
    );
    expect(r).toMatchObject({ verified: true, plain: "v = 1.5a + 3.5b + 2.5c" });
  });

  it("two dimensions work the same way, and a negative coefficient prints as a subtraction", async () => {
    const r = await run(
      String.raw`\text{Express } (7, 8) \text{ in terms of } (1, 1) \text{ and } (1, -1)`
    );
    expect(r).toMatchObject({ verified: true, plain: "v = 7.5a - 0.5b" });
  });

  it("a COPLANAR basis spans nothing — decline rather than pick one of the infinitely many", async () => {
    const r = await run(
      String.raw`\text{Express } (1, 2, 3) \text{ in terms of } (1, 0, 0), (2, 0, 0) \text{ and } (3, 0, 0)`
    );
    expect(r.verified).not.toBe(true);
  });

  it("too few basis vectors is not an expansion — decline", async () => {
    const r = await run(
      String.raw`\text{Express } (1, 2, 3) \text{ in terms of } (1, 0, 0) \text{ and } (0, 1, 0)`
    );
    expect(r.verified).not.toBe(true);
  });
});

describe("no regression on the vector questions that only evaluate", () => {
  it("the angle between two vectors is still the angle", async () => {
    const r = await run(
      String.raw`\text{Find the angle between } (1, 0, 0) \text{ and } (0, 1, 0)`
    );
    expect(r).toMatchObject({ type: "vector_angle", verified: true, plain: "90 degrees" });
  });

  it("a plain dot product is untouched", async () => {
    const r = await run(String.raw`\text{Find the dot product of } (1, 2, 3) \text{ and } (4, 5, 6)`);
    expect(r).toMatchObject({ type: "vector_dot", verified: true, plain: "32" });
  });
});
