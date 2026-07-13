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

describe("classify + solve — matrix product", () => {
  it("multiplies two conformable matrices (recompute-verified)", async () => {
    const B = String.raw`\begin{pmatrix} 5 & 6 \\ 7 & 8 \end{pmatrix}`;
    const r = await run(`${M2} ${B}`);
    expect(r.type).toBe("matrix_product");
    expect(r.op).toBe("multiply");
    expect(r).toMatchObject({ verified: true, plain: "19, 22; 43, 50" });
  });

  it("declines a non-conformable product (shapes don't line up)", async () => {
    // 2×2 times 3×2 — inner dimensions 2 ≠ 3.
    const A = String.raw`\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}`;
    const B = String.raw`\begin{pmatrix} 1 & 2 \\ 3 & 4 \\ 5 & 6 \end{pmatrix}`;
    const r = await run(`${A} ${B}`);
    expect(r.verified).toBe(false);
  });
});

async function runVec(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { op: c.vectorOp, type: c.problemType, verified: p.verified, plain: p.finalAnswer?.plain };
}

describe("classify + solve — vectors", () => {
  it("dot product (independent recompute)", async () => {
    const r = await runVec(String.raw`(1,2,3) \cdot (4,5,6)`);
    expect(r).toMatchObject({ op: "dot", type: "vector_dot", verified: true, plain: "32" });
  });

  it("cross product (recompute + ⊥ to both operands)", async () => {
    const r = await runVec(String.raw`(1,0,0) \times (0,1,0)`);
    expect(r).toMatchObject({ op: "cross", verified: true, plain: "(0, 0, 1)" });
  });

  it("magnitude of a vector", async () => {
    const r = await runVec(String.raw`magnitude of (3,4)`);
    expect(r).toMatchObject({ op: "magnitude", verified: true, plain: "5" });
  });

  it("cross product of parallel vectors is the zero vector", async () => {
    const r = await runVec(String.raw`(1,2,3) \times (2,4,6)`);
    expect(r).toMatchObject({ op: "cross", verified: true, plain: "(0, 0, 0)" });
  });
});

describe("classify + solve — matrix sum / difference", () => {
  const B = String.raw`\begin{pmatrix} 5 & 6 \\ 7 & 8 \end{pmatrix}`;

  it("adds two same-shape matrices (element-wise recompute)", async () => {
    const r = await run(`${M2} + ${B}`);
    expect(r).toMatchObject({ op: "add", type: "matrix_sum", verified: true, plain: "6, 8; 10, 12" });
  });

  it("subtracts two same-shape matrices", async () => {
    const r = await run(`${M2} - ${B}`);
    expect(r).toMatchObject({ op: "subtract", type: "matrix_difference", verified: true, plain: "-4, -4; -4, -4" });
  });

  it("declines a sum of mismatched shapes", () => {
    const B3 = String.raw`\begin{pmatrix} 1 & 2 & 3 \\ 4 & 5 & 6 \end{pmatrix}`;
    expect(classify(`${M2} + ${B3}`).linalgOp).toBeUndefined();
  });
});

// Every finding from the adversarial review of the Phase B tail: each was a
// routing false-positive that shipped a confident WRONG answer as verified:true.
// The fix is to DECLINE when the operation is ambiguous. These lock that in.
describe("regression — review findings must not ship a confident wrong answer", () => {
  const A = String.raw`\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}`;
  const B = String.raw`\begin{pmatrix} 5 & 6 \\ 7 & 8 \end{pmatrix}`;

  it("#1 A + B returns the SUM, never the product", async () => {
    const r = await run(`${A} + ${B}`);
    expect(r.plain).not.toBe("19, 22; 43, 50"); // the product would be the wrong answer
    expect(r).toMatchObject({ verified: true, plain: "6, 8; 10, 12" });
  });

  it("#1 det of a product declines, never returns the raw product", () => {
    const c = classify(String.raw`\det ${A} ${B}`);
    expect(c.linalgOp).toBeUndefined();
    expect(c.problemType).not.toBe("matrix_product");
  });

  it("#2 'length of the interval (2,5)' is not hijacked into a magnitude", () => {
    const c = classify(String.raw`length of the interval (2, 5)`);
    expect(c.vectorOp).toBeUndefined();
    expect(c.strategy).not.toBe("linalg");
  });

  it("#3 'sum of vectors …' is not misread as a statistic or a vector op", () => {
    const c = classify(String.raw`sum of vectors (1, 2, 3) and (4, 5, 6)`);
    expect(c.strategy).not.toBe("statistics");
    expect(c.statKind).toBeUndefined();
    expect(c.vectorOp).toBeUndefined();
  });

  it("#4 thousands separators are not read as a dot product", () => {
    const c = classify(String.raw`(1,000) \cdot (2,000)`);
    expect(c.vectorOp).toBeUndefined();
  });

  it("#5 a chained 3-matrix product declines", () => {
    const C = String.raw`\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}`;
    expect(classify(`${A} ${B} ${C}`).linalgOp).toBeUndefined();
  });

  it("#6 a matrix with a blank cell declines instead of coercing it to 0", () => {
    const c = classify(String.raw`\begin{vmatrix} 1 & 2 \\ 3 & \end{vmatrix}`);
    expect(c.linalgOp).toBeUndefined();
  });

  it("#7 a malformed vector with a trailing comma declines", () => {
    const c = classify(String.raw`(1, 2,) \times (4, 5, 6)`);
    expect(c.vectorOp).toBeUndefined();
  });

  it("a genuine magnitude/dot/cross still works (guards aren't over-broad)", async () => {
    const dot = await runVec(String.raw`(1,2,3) \cdot (4,5,6)`);
    expect(dot).toMatchObject({ op: "dot", verified: true, plain: "32" });
    const mag = await runVec(String.raw`magnitude of (3,4)`);
    expect(mag).toMatchObject({ op: "magnitude", verified: true, plain: "5" });
  });
});
