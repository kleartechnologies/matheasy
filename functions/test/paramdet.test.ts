// A matrix with a parameter in it — "for what values of a does this have
// determinant zero?", and the whole singular / non-invertible / no-inverse
// family, and the characteristic equation det(A − λI) = 0 with it.
//
// The existing matrix reader takes numeric cells only, so a grid containing an
// a² was not a matrix at all: the question fell through and was read as an
// expression.
//
// The determinant is a polynomial in the parameter, so it is read off by
// evaluating the determinant at sample points and interpolating — no symbolic
// cofactor algebra anywhere. The gate is the golden rule stated literally: each
// value goes back into the ORIGINAL cells and the determinant is recomputed
// there from the numbers. And because the polynomial's degree is known, a scan
// over Cauchy's bound can promise it found every real value — which is what
// makes "no real values" a result rather than a failure.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solveDeterministic } from "../src/solver/deterministic";

function run(latex: string): { type: string; answer: string | null } {
  const cls = classify(latex);
  const cand = solveDeterministic(cls);
  return {
    type: cls.problemType,
    answer: cand && cand.verify() ? (cand.answer.plain ?? null) : null,
  };
}

describe("the sheet question and its family", () => {
  it("a 3×3 with a² in two cells", () => {
    // det = a³ − 2a² − a + 2 = (a−1)(a+1)(a−2).
    const r = run(
      String.raw`\text{For what values of } a \text{ does } \begin{pmatrix} 1 & 2 & a^2 \\ 1 & a & 1 \\ 1 & a & a^2 \end{pmatrix} \text{ have determinant zero?}`
    );
    expect(r.type).toBe("parametric_determinant");
    expect(r.answer).toBe("a = -1 or a = 1 or a = 2");
  });

  it("'is singular' asks the same thing", () => {
    // k² − 6 = 0. √6, not 2.449489743.
    const r = run(
      String.raw`\text{Find the values of } k \text{ for which } \begin{pmatrix} k & 2 \\ 3 & k \end{pmatrix} \text{ is singular}`
    );
    expect(r.answer).toBe("k = -√6 or k = √6");
  });

  it("'has no inverse' too", () => {
    // 1 − 2t² = 0.
    const r = run(
      String.raw`\text{Find all values of } t \text{ for which } \begin{pmatrix} 1 & t & 0 \\ t & 1 & t \\ 0 & t & 1 \end{pmatrix} \text{ has no inverse}`
    );
    expect(r.answer).toBe("t = -√2/2 or t = √2/2");
  });

  it("a fractional value", () => {
    const r = run(
      String.raw`\text{For what values of } a \text{ is } \begin{pmatrix} 2a & 1 \\ 4 & 3 \end{pmatrix} \text{ singular?}`
    );
    expect(r.answer).toBe("a = 2/3");
  });
});

describe("the characteristic equation, which is the same question in λ", () => {
  it("λ written as a LaTeX macro is a parameter, not a parse failure", () => {
    // mathjs cannot read a backslash, so `2 − λ` down the diagonal used to make
    // the whole grid non-numeric and the question declined.
    const r = run(
      String.raw`\text{For what values of } \lambda \text{ is } \begin{pmatrix} 2-\lambda & 1 \\ 1 & 2-\lambda \end{pmatrix} \text{ singular?}`
    );
    expect(r.type).toBe("parametric_determinant");
    expect(r.answer).toBe("λ = 1 or λ = 3");
  });

  it("eigenvalues that are 1 ± √2, not −0.414214 and 2.414214", () => {
    const r = run(
      String.raw`\text{For what values of } \lambda \text{ is } \begin{pmatrix} 1-\lambda & 1 & 0 \\ 1 & 1-\lambda & 1 \\ 0 & 1 & 1-\lambda \end{pmatrix} \text{ singular?}`
    );
    expect(r.answer).toBe("λ = 1 - √2 or λ = 1 or λ = 1 + √2");
  });
});

describe("the cases a sign scan alone would get wrong", () => {
  it("a repeated root touches the axis without crossing it", () => {
    // det = (a−1)². There is no sign change anywhere, so the root is found from
    // the stationary points instead.
    const r = run(
      String.raw`\text{For what values of } a \text{ does } \begin{pmatrix} a-1 & 0 \\ 0 & a-1 \end{pmatrix} \text{ have determinant zero?}`
    );
    expect(r.answer).toBe("a = 1");
  });

  it("no real value makes it singular — and saying so is the answer", () => {
    // det = k² + 1. Every real root lies inside Cauchy's bound and there is
    // none there, so this is a result rather than a failure to find one.
    const r = run(
      String.raw`\text{Find the values of } k \text{ for which } \begin{pmatrix} k & -1 \\ 1 & k \end{pmatrix} \text{ is singular}`
    );
    expect(r.answer).toBe("no real values of k");
  });
});

describe("what it declines", () => {
  it("two parameters is not one polynomial", () => {
    const r = run(
      String.raw`\text{Find the values of } a \text{ for which } \begin{pmatrix} a & b \\ 1 & a \end{pmatrix} \text{ is singular}`
    );
    expect(r.type).not.toBe("parametric_determinant");
  });

  it("a non-square grid has no determinant", () => {
    const r = run(
      String.raw`\text{For what values of } a \text{ is } \begin{pmatrix} 1 & 2 & a \\ 3 & 4 & 1 \end{pmatrix} \text{ singular?}`
    );
    expect(r.type).not.toBe("parametric_determinant");
  });

  it("the parameter the question names must be the one in the grid", () => {
    const r = run(
      String.raw`\text{For what values of } b \text{ is } \begin{pmatrix} a & 1 \\ 1 & a \end{pmatrix} \text{ singular?}`
    );
    expect(r.type).not.toBe("parametric_determinant");
  });

  it("no 'values' question at all — just a claim to show", () => {
    const r = run(
      String.raw`\text{Show that } \begin{pmatrix} 1 & 2 \\ 2 & 4 \end{pmatrix} \text{ is singular}`
    );
    expect(r.type).not.toBe("parametric_determinant");
  });
});

describe("no regression — the matrix questions that already worked", () => {
  it("a plain determinant is still a plain determinant", () => {
    const r = run(String.raw`\text{Find the determinant of } \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}`);
    expect(r.type).toBe("linalg");
    expect(r.answer).toBe("-2");
  });

  it("eigenvalues of a numeric matrix keep their own engine", () => {
    const cls = classify(
      String.raw`\text{Find the eigenvalues of } \begin{pmatrix} 2 & 1 \\ 1 & 2 \end{pmatrix}`
    );
    expect(cls.problemType).not.toBe("parametric_determinant");
  });

  it("the inverse of a numeric matrix is untouched", () => {
    const cls = classify(
      String.raw`\text{Find the inverse of } \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}`
    );
    expect(cls.problemType).not.toBe("parametric_determinant");
  });
});
