// Linear algebra — DETERMINISTIC via mathjs, each answer proven by a property
// (det: independent cofactor expansion; inverse: A·A⁻¹=I; eigenvalues:
// det(A−λI)=0). Real-valued matrices only; a complex spectrum declines.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("linear algebra is deterministic — the LLM must not be called");
};
const M2 = String.raw`\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}`;

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { op: c.linalgOp, type: c.problemType, verified: p.verified, plain: p.finalAnswer?.plain };
}

describe("classify + solve — linear algebra", () => {
  it("determinant (2×2)", async () => {
    const r = await run(`\\det ${M2}`);
    expect(r.type).toBe("linalg");
    expect(r.op).toBe("determinant");
    expect(r).toMatchObject({ verified: true, plain: "-2" });
  });

  it("determinant (3×3)", async () => {
    const r = await run(String.raw`determinant of \begin{pmatrix} 2 & 0 & 1 \\ 3 & 0 & 0 \\ 5 & 1 & 1 \end{pmatrix}`);
    expect(r).toMatchObject({ op: "determinant", verified: true, plain: "3" });
  });

  it("inverse (verified A·A⁻¹ = I)", async () => {
    const r = await run(String.raw`inverse of \begin{pmatrix} 4 & 7 \\ 2 & 6 \end{pmatrix}`);
    expect(r).toMatchObject({ op: "inverse", verified: true });
    expect(r.plain).toBe("0.6, -0.7; -0.2, 0.4");
  });

  it("eigenvalues (verified det(A−λI)=0)", async () => {
    const r = await run(String.raw`eigenvalues of \begin{pmatrix} 2 & 1 \\ 1 & 2 \end{pmatrix}`);
    expect(r).toMatchObject({ op: "eigenvalues", verified: true, plain: "1, 3" });
  });

  it("declines a singular matrix's inverse (no inverse exists)", async () => {
    const r = await run(String.raw`inverse of \begin{pmatrix} 1 & 2 \\ 2 & 4 \end{pmatrix}`);
    expect(r.verified).toBe(false);
  });

  it("declines a complex spectrum (out of scope)", async () => {
    const r = await run(String.raw`eigenvalues of \begin{pmatrix} 0 & -1 \\ 1 & 0 \end{pmatrix}`);
    expect(r.verified).toBe(false); // ±i are not real
  });
});
