// The matrix operations a problem sheet actually asks for, beyond the
// det/inverse/eigenvalues the engine already had: an individual element, the
// transpose, the trace, a power, the symmetric + skew-symmetric split, and AB
// alongside BA. Each is gated on a property, never on one library's word.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("matrix operations are deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { type: c.problemType, op: c.linalgOp, verified: p.verified, plain: p.finalAnswer?.plain };
}

const A3 = String.raw`\begin{pmatrix} 1 & 2 & 3 \\ 4 & 5 & 6 \\ 7 & 8 & 10 \end{pmatrix}`;

describe("matrix elements, transpose, trace", () => {
  it("names the element a_{13} — row 1, column 3", async () => {
    const r = await run(String.raw`\text{Write down the element } a_{13} \text{ of } ${A3}`);
    expect(r).toMatchObject({ type: "matrix_element", verified: true, plain: "3" });
  });

  it("a_{31} is the OTHER one — row 3, column 1, not the same entry", async () => {
    const r = await run(String.raw`\text{Write down the element } a_{31} \text{ of } ${A3}`);
    expect(r).toMatchObject({ verified: true, plain: "7" });
  });

  it("declines an element outside the matrix instead of guessing", async () => {
    const r = await run(String.raw`\text{Write down the element } a_{49} \text{ of } ${A3}`);
    expect(r.verified).not.toBe(true);
  });

  it("transpose swaps rows and columns", async () => {
    const r = await run(
      String.raw`\text{Find the transpose of } \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}`
    );
    expect(r).toMatchObject({ type: "matrix_transpose", verified: true, plain: "1, 3; 2, 4" });
  });

  it("transposes a non-square matrix (2×3 → 3×2)", async () => {
    const r = await run(
      String.raw`\text{Find the transpose of } \begin{pmatrix} 1 & 2 & 3 \\ 4 & 5 & 6 \end{pmatrix}`
    );
    expect(r).toMatchObject({ verified: true, plain: "1, 4; 2, 5; 3, 6" });
  });

  it("trace is the sum of the diagonal", async () => {
    const r = await run(String.raw`\text{Find the trace of } ${A3}`);
    expect(r).toMatchObject({ type: "matrix_trace", verified: true, plain: "16" });
  });
});

describe("matrix powers", () => {
  it("A^2 by repeated multiplication", async () => {
    const r = await run(
      String.raw`\text{Find } A^{2} \text{ where } A = \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}`
    );
    expect(r).toMatchObject({ type: "matrix_power", verified: true, plain: "7, 10; 15, 22" });
  });

  it("A^3", async () => {
    const r = await run(
      String.raw`\text{Compute } A^{3} \text{ for } A = \begin{pmatrix} 2 & 0 \\ 0 & 3 \end{pmatrix}`
    );
    expect(r).toMatchObject({ verified: true, plain: "8, 0; 0, 27" });
  });

  it("the exponent hung off the written-out grid, with no matrix named at all", async () => {
    // `\end{pmatrix}^3` — no letter for the power cue to attach to, which is why
    // this form used to fall through to the generic expression route.
    const r = await run(
      String.raw`\text{Find } \begin{pmatrix} 1 & 1 \\ 0 & 1 \end{pmatrix}^{3}`
    );
    expect(r).toMatchObject({ type: "matrix_power", verified: true, plain: "1, 3; 0, 1" });
  });

  it("A^{-1} is still the INVERSE, not a power", async () => {
    const r = await run(
      String.raw`\text{Find } A^{-1} \text{ where } A = \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}`
    );
    expect(r.op).toBe("inverse");
    expect(r.verified).toBe(true);
  });
});

describe("symmetric + skew-symmetric decomposition", () => {
  it("splits A into ½(A+Aᵀ) and ½(A−Aᵀ), which must add back to A", async () => {
    const r = await run(
      String.raw`\text{Express } \begin{pmatrix} 1 & 3 \\ 5 & 7 \end{pmatrix} \text{ as the sum of a symmetric and a skew-symmetric matrix}`
    );
    expect(r).toMatchObject({ type: "matrix_symmetric_split", verified: true });
    // S = [[1,4],[4,7]], K = [[0,-1],[1,0]]
    expect(r.plain).toBe("symmetric: 1, 4; 4, 7; skew-symmetric: 0, -1; 1, 0");
  });

  it("declines a non-square matrix (Aᵀ has the wrong shape to add)", async () => {
    const c = classify(
      String.raw`\text{Express } \begin{pmatrix} 1 & 2 & 3 \\ 4 & 5 & 6 \end{pmatrix} \text{ as the sum of a symmetric and a skew-symmetric matrix}`
    );
    expect(c.linalgOp).toBeUndefined();
  });
});

describe("AB versus BA", () => {
  it("gives BOTH products — the question is that they differ", async () => {
    const r = await run(
      String.raw`\text{Find } AB \text{ and } BA \text{ for } \begin{pmatrix} 1 & 1 \\ 0 & 0 \end{pmatrix} \begin{pmatrix} 0 & 0 \\ 1 & 1 \end{pmatrix}`
    );
    expect(r.verified).toBe(true);
    // AB = [[1,1],[0,0]], BA = [[0,0],[1,1]]
    expect(r.plain).toBe("AB = 1, 1; 0, 0; BA = 0, 0; 1, 1");
  });

  it("a plain product is still just AB", async () => {
    const r = await run(
      String.raw`\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix} \begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}`
    );
    expect(r).toMatchObject({ op: "multiply", verified: true, plain: "1, 2; 3, 4" });
  });
});

// The pre-existing behaviour must not shift.
describe("no regression on the ops that already worked", () => {
  it("determinant", async () => {
    const r = await run(String.raw`\text{Find the determinant of } ${A3}`);
    expect(r).toMatchObject({ op: "determinant", verified: true, plain: "-3" });
  });

  it("rank", async () => {
    const r = await run(String.raw`\text{Find the rank of } ${A3}`);
    expect(r).toMatchObject({ op: "rank", verified: true, plain: "3" });
  });

  it("sum", async () => {
    const r = await run(
      String.raw`\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix} + \begin{pmatrix} 1 & 1 \\ 1 & 1 \end{pmatrix}`
    );
    expect(r).toMatchObject({ op: "add", verified: true, plain: "2, 3; 4, 5" });
  });
});
