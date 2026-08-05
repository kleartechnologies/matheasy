/**
 * The canonical-polynomial layer. mathjs expands but never re-orders a
 * commutative product, so `8x^3y` and `8yx^3` are the same monomial written two
 * ways and never met — these lock in that they now collect, exactly.
 */
import { describe, expect, it } from "vitest";
import { canonicalPolynomial, toPoly, reduceFraction, polyToAscii } from "../src/solver/polynomial";

const canon = (s: string) => canonicalPolynomial(s);

describe("canonicalPolynomial — like terms collect regardless of order", () => {
  it("the worksheet case: 2x^2(4xy-5) - 8yx^3 + 9x", () => {
    expect(canon("2*x^2*(4*x*y-5) - 8*y*x^3 + 9*x")).toBe("-10*x^2 + 9*x");
  });
  it("xy + 3yx - 4y^2x", () => {
    expect(canon("x*y + 3*y*x - 4*y^2*x")).toBe("-4*x*y^2 + 4*x*y");
  });
  it("3a + 4ba - 2a^2 + 4a^2 + 6a", () => {
    expect(canon("3*a + 4*b*a - 2*a^2 + 4*a^2 + 6*a")).toBe("2*a^2 + 4*a*b + 9*a");
  });
  it("expands a product of binomials", () => {
    expect(canon("(2*x+y)*(x-2*y)")).toBe("2*x^2 - 3*x*y - 2*y^2");
  });
  it("expands a square", () => {
    expect(canon("(x-2*y)^2")).toBe("x^2 - 4*x*y + 4*y^2");
  });
  it("a double negative adds", () => {
    expect(canon("-2*a^2*b*c^2 - (-6*a^2*b*c^2)")).toBe("4*a^2*b*c^2");
  });
  it("3a(2b-3c+4d) - (6ab - 2ac + 12ad) = -7ac", () => {
    expect(canon("3*a*(2*b-3*c+4*d) - (6*a*b - 2*a*c + 12*a*d)")).toBe("-7*a*c");
  });
});

describe("exact rational coefficients", () => {
  it("keeps thirds as thirds, never 0.333", () => {
    expect(canon("x/3 + x/6")).toBe("x/2");
    expect(canon("0.25*x")).toBe("x/4");
  });
});

describe("atoms — a non-polynomial subtree still collects", () => {
  it("3sqrt(x) - sqrt(x) = 2sqrt(x)", () => {
    expect(canon("3*sqrt(x) - sqrt(x)")).toBe("2*sqrt(x)");
  });
  it("declines nothing: a symbolic exponent becomes an atom, not a failure", () => {
    expect(canon("2*x^n + 3*x^n")).toBe("5*(x ^ n)");
  });
});

describe("reduceFraction", () => {
  const frac = (n: string, d: string) => {
    const pn = toPoly(n);
    const pd = toPoly(d);
    if (!pn || !pd) throw new Error("parse");
    const r = reduceFraction(pn.poly, pd.poly);
    return `${polyToAscii(r.num, pn.atoms.source)} / ${polyToAscii(r.den, pd.atoms.source)}`;
  };
  it("cancels a common monomial", () => {
    expect(frac("42*a*b^2*d*c^2", "35*a^3*b^3")).toBe("6*c^2*d / 5*a^2*b");
  });
  it("cancels a repeated linear factor (univariate gcd)", () => {
    expect(frac("6*x^2 + 24*x + 24", "9*x^3 + 36*x^2 + 36*x")).toBe("2 / 3*x");
  });
  it("divides out exactly when the denominator is a factor", () => {
    expect(frac("x^2 - 1", "x - 1")).toBe("x + 1 / 1");
  });
});
