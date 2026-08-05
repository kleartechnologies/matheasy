/**
 * The three engines the Basic Algebra worksheet forced into existence:
 * change of subject, equations with the unknown under a fraction bar, and
 * factorisation. Each one is only allowed to answer when its answer survives
 * the substitution gate, so these tests check the ANSWER, not just that
 * something came back.
 */
import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solveDeterministic } from "../src/solver/deterministic";
import { factorPolynomial, simplifyAlgebraic } from "../src/solver/polynomial";

/** Solve a problem the way the pipeline does, and require the gate to pass. */
function answer(latex: string): string {
  const cls = classify(latex);
  const candidate = solveDeterministic(cls);
  expect(candidate, `no deterministic candidate for ${latex}`).not.toBeNull();
  expect(candidate!.verify(), `gate rejected the answer to ${latex}`).toBe(true);
  return candidate!.answer.plain;
}

describe("change of subject", () => {
  it("isolates a linear target", () => {
    expect(answer("2x - 5y = 10 \\quad [x]")).toBe("x = (5*y + 10)/2");
    expect(answer("\\text{Make } t \\text{ the subject of } v = u + at")).toBe(
      "t = (-u + v)/a"
    );
  });

  it("isolates a target that appears on both sides", () => {
    expect(answer("xy - 8y = x + 3 \\quad [x]")).toBe("x = (8*y + 3)/(y - 1)");
  });

  it("takes the root when the target is squared", () => {
    expect(answer("V = \\frac{1}{3}\\pi r^2 h \\quad [r]")).toBe("r = sqrt((3*V)/(h*pi))");
  });

  it("clears a radical, and does not fail itself on the domain it creates", () => {
    // Squaring `3y = √(5x) − 9` requires `3y + 9 ≥ 0`; a draw outside that is
    // one the printed formula excludes, and must not count as a refutation.
    expect(answer("3y = \\sqrt{5x} - 9 \\quad [x]")).toBe("x = (9*y^2 + 54*y + 81)/5");
  });

  it("leaves an ordinary one-unknown equation alone", () => {
    // No instruction, one variable — this is a normal solve, not a rearrangement.
    expect(classify("2x - 5 = 11").strategy).not.toBe("subject");
  });
});

describe("equations with the unknown in a denominator", () => {
  it("clears the fraction and keeps both roots", () => {
    expect(answer("x - 1 = \\frac{6-3x}{2x}")).toBe("x = -2 or x = 3/2");
    expect(answer("\\frac{2x+7}{3x-2} = x")).toBe("x = -1 or x = 7/3");
  });

  it("solves when clearing leaves a linear equation", () => {
    expect(answer("3 - \\frac{5}{x+1} = 1")).toBe("x = 3/2");
  });

  it("drops the root the clearing invented", () => {
    // Clearing `x − 3` turns this into `x² = 9`, which offers x = 3 — where the
    // printed equation is undefined on both sides. Only x = −3 may be shipped.
    expect(answer("\\frac{x^2}{x-3} = \\frac{9}{x-3}")).toBe("x = -3");
  });
});

describe("exact answers, not rounded ones", () => {
  it("prints the fraction the worksheet prints", () => {
    expect(answer("4x^2 - 15 = 17x")).toBe("x = -3/4 or x = 5");
    expect(answer("\\frac{2x-3}{4} = \\frac{x+1}{5}")).toBe("x = 19/6");
    expect(answer("2(a - 6) = -a - 13")).toBe("a = -1/3");
  });
});

describe("factorisation", () => {
  it("factors a quadratic trinomial", () => {
    expect(factorPolynomial("p^2 + 6*p - 16")).toBe("(p - 2)*(p + 8)");
    expect(factorPolynomial("2*x^2 + x - 6")).toBe("(x + 2)*(2*x - 3)");
  });

  it("pulls the common factor", () => {
    expect(factorPolynomial("6*x^2 + 9*x")).toBe("3*x*(2*x + 3)");
    expect(factorPolynomial("-10*x^2 + 9*x")).toBe("x*(-10*x + 9)");
  });

  it("recognises a difference of two squares and a perfect square", () => {
    expect(factorPolynomial("4*a^2 - 9*b^2")).toBe("(2*a - 3*b)*(2*a + 3*b)");
    expect(factorPolynomial("a^2 - 2*a*b + b^2")).toBe("(a - b)^2");
  });

  it("groups a four-term expression", () => {
    expect(factorPolynomial("a*x - a*y + 2*x - 2*y")).toBe("(x - y)*(a + 2)");
  });

  it("declines what does not factor", () => {
    expect(factorPolynomial("x^2 + 1")).toBeNull();
    expect(factorPolynomial("3*x + 5")).toBeNull();
    // A single monomial is not a factorisation of itself.
    expect(factorPolynomial("x*y")).toBeNull();
  });

  it("answers with the product when the problem asked to factorise", () => {
    expect(answer("\\text{Factorise } p^2 + 6p - 16")).toBe("(p - 2)*(p + 8)");
    expect(answer("\\text{Factorize } 2x^2(4xy - 5) - 8yx^3 + 9x")).toBe("x*(-10*x + 9)");
  });

  it("answers with the collected sum when it did not, and offers both", () => {
    const cls = classify("2x^2(4xy - 5) - 8yx^3 + 9x");
    const candidate = solveDeterministic(cls)!;
    expect(candidate.answer.plain).toBe("-10*x^2 + 9*x");
    expect(candidate.methods.map((m) => m.id)).toEqual(["simplify", "factorise"]);
  });
});

describe("the polynomial layer declines instead of hanging", () => {
  it("refuses prose read as a twenty-variable product", () => {
    // The ascii pass splits glued letters into implicit products, so a scanned
    // word problem arrives here as a monomial in every letter it contains. The
    // multivariate gcd would recurse per variable; the budget stops it.
    const started = Date.now();
    expect(simplifyAlgebraic("F*i*n*d*t*h*e*a*r*e*a*o*f*a*s*q*u*a*r*e*w*i*t*h*s*i*d*e*7")).toBeNull();
    expect(Date.now() - started).toBeLessThan(5000);
  });
});
