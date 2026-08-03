// The engine that verifies a definite integral. Nothing here decides an answer
// — it decides whether the answer a student is shown can be trusted — so being
// wrong and being silent are very different failures, and only one of them is
// acceptable.
//
// Simpson's rule was the whole engine, and it evaluates at both endpoints. That
// made two ordinary families unanswerable: an integral to infinity (the bound
// isn't a number, so everything downstream was NaN) and an integrand that blows
// up at an endpoint while still having a perfectly finite area. Tanh–sinh never
// samples an endpoint, which is exactly the shape both of those need, and an
// infinite bound is substituted onto a finite one before any rule runs.
//
// Gauss–Legendre stays as an independent check — but only where it is a fair
// one. Against an endpoint singularity GL is simply the wrong tool, and its
// disagreement there would be evidence about GL rather than about the integral.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { numericIntegrate } from "../src/solver/verify";

const near = (got: number, want: number) =>
  expect(Math.abs(got - want)).toBeLessThan(1e-6 * Math.max(1, Math.abs(want)));

describe("integrals to infinity", () => {
  it("∫₃^∞ dx/((x−1)(x−2)) = ln 2", () => {
    near(numericIntegrate("1/((x-1)*(x-2))", "x", "3", "\\infty"), Math.log(2));
  });

  it("the ∞ character, not just the macro", () => {
    near(numericIntegrate("e^(-x)", "x", "0", "∞"), 1);
  });

  it("a lower bound of −∞", () => {
    near(numericIntegrate("e^(x)", "x", "-\\infty", "0"), 1);
  });

  it("both ends infinite — the Gaussian", () => {
    near(numericIntegrate("e^(-x^2)", "x", "-\\infty", "\\infty"), Math.sqrt(Math.PI));
  });

  it("a tail that does not converge is not given a value", () => {
    // ∫₁^∞ dx/x diverges. A number here would be a fabricated one.
    expect(numericIntegrate("1/x", "x", "1", "\\infty")).toBeNaN();
  });
});

describe("an integrand that blows up at an endpoint", () => {
  it("∫₁² dx/√(x²−1) = ln(2+√3)", () => {
    near(numericIntegrate("1/sqrt(x^2-1)", "x", "1", "2"), Math.log(2 + Math.sqrt(3)));
  });

  it("∫₀¹ dx/√x = 2", () => {
    near(numericIntegrate("1/sqrt(x)", "x", "0", "1"), 2);
  });

  it("∫₀¹ ln x dx = −1", () => {
    near(numericIntegrate("log(x)", "x", "0", "1"), -1);
  });

  it("a pole INSIDE the range still has no value", () => {
    // ∫₀² dx/(x−1) does not converge. The endpoints are both fine, which is
    // exactly why "finite at the endpoints" was never the right test.
    expect(numericIntegrate("1/(x-1)", "x", "0", "2")).toBeNaN();
  });
});

describe("no regression — the ordinary integrals Simpson already got right", () => {
  it("∫₀^{π/2} x sin x dx = 1", () => {
    near(numericIntegrate("x*sin(x)", "x", "0", "pi/2"), 1);
  });

  it("∫₀¹ x² dx = 1/3", () => {
    near(numericIntegrate("x^2", "x", "0", "1"), 1 / 3);
  });

  it("a reversed interval keeps its sign", () => {
    near(numericIntegrate("x^2", "x", "1", "0"), -1 / 3);
  });

  it("an empty interval is zero", () => {
    expect(numericIntegrate("x^2", "x", "1", "1")).toBe(0);
  });

  it("an integrand that doesn't parse gets no number", () => {
    expect(numericIntegrate("x^^2", "x", "0", "1")).toBeNaN();
  });
});

describe("the variable of integration is whatever the question calls it", () => {
  it("dθ, written as a macro", () => {
    // `latexToAscii` turns `dθ` into `d theta`, which no single-letter pattern
    // can see — so the unknown silently defaulted to `x` and the engine sampled
    // a variable the integrand did not contain.
    const cls = classify(String.raw`\int_0^{\pi/2} \cos^5\theta \, d\theta`);
    expect(cls.problemType).toBe("definite_integral");
    expect(cls.unknown).toBe("theta");
    near(
      numericIntegrate(cls.integrand!, cls.unknown, cls.lowerBound!, cls.upperBound!),
      8 / 15
    );
  });

  it("dθ inside a fraction", () => {
    const cls = classify(String.raw`\int_0^{\pi/2} \frac{d\theta}{(1+\sin\theta)^2}`);
    expect(cls.unknown).toBe("theta");
    near(
      numericIntegrate(cls.integrand!, cls.unknown, cls.lowerBound!, cls.upperBound!),
      2 / 3
    );
  });

  it("a Greek macro latexToAscii does not itself know", () => {
    const cls = classify(String.raw`\int_0^{1} \phi^2 \, d\phi`);
    expect(cls.unknown).toBe("phi");
    near(
      numericIntegrate(cls.integrand!, cls.unknown, cls.lowerBound!, cls.upperBound!),
      1 / 3
    );
  });

  it("no differential at all — one variable is not an ambiguity", () => {
    const cls = classify(String.raw`\int_0^{2} t^2`);
    expect(cls.unknown).toBe("t");
  });

  it("dt, dx, du are all still read the ordinary way", () => {
    expect(classify(String.raw`\int_0^1 t^2 \, dt`).unknown).toBe("t");
    expect(classify(String.raw`\int_0^1 u^2 \, du`).unknown).toBe("u");
    expect(classify(String.raw`\int_0^1 x^2 \, dx`).unknown).toBe("x");
  });

  it("a `= ?` trailer after the dx does not hide it", () => {
    const cls = classify(String.raw`\int \sin x \cdot \cos x \, dx = ?`);
    expect(cls.unknown).toBe("x");
    expect(cls.integrand).toBe("sin(x) * cos(x)");
  });
});
