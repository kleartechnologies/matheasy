// The ODE gate, and two ways it was rejecting correct answers.
//
// `y' + xy = x` is the shape of every integrating-factor question there is. Its
// residual was built as `(dy + xy) - (x)`, and to mathjs `xy` is not a product —
// it is one symbol, which nothing binds, so every sample evaluated to NaN and
// was skipped. A correct answer then failed for want of evidence, and the
// student was told it couldn't be verified.
//
// And a general solution is not obliged to be defined everywhere.
// `y = -½ln(C − 2eˣ)` is the general solution of `y' = e^{x+2y}` and it exists
// only where the logarithm's argument is positive. The independence check
// demanded a value at five fixed points and threw the whole candidate away when
// one of them lay outside the domain.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { verifyOde } from "../src/solver/ode";

function ode(latex: string) {
  const cls = classify(latex);
  return {
    type: cls.problemType,
    residual: cls.odeResidual ?? "",
    check: (solution: string) =>
      verifyOde(
        cls.odeResidual ?? "",
        cls.odeDepVar ?? "y",
        cls.odeIndepVar ?? "x",
        cls.odeOrder ?? 1,
        solution,
        cls.odeInitial ?? []
      ),
  };
}

describe("juxtaposition is multiplication, not a variable name", () => {
  it("y' + xy = x accepts its own solution", () => {
    const q = ode(String.raw`\text{Solve } \frac{dy}{dx} + xy = x \text{ where } y(0) = 0`);
    expect(q.type).toBe("differential_equation");
    expect(q.check("1 - e^(-x^2/2)")).toBe(true);
  });

  it("the residual holds a product where the question wrote one", () => {
    const q = ode(String.raw`\text{Solve } \frac{dy}{dx} + xy = x \text{ where } y(0) = 0`);
    expect(q.residual).toContain("x*y");
  });

  it("written the other way round, yx", () => {
    const q = ode(String.raw`\text{Solve } \frac{dy}{dx} + yx = x \text{ where } y(0) = 0`);
    expect(q.check("1 - e^(-x^2/2)")).toBe(true);
  });

  it("a wrong answer is still wrong", () => {
    const q = ode(String.raw`\text{Solve } \frac{dy}{dx} + xy = x \text{ where } y(0) = 0`);
    expect(q.check("1 - e^(-x^2)")).toBe(false);
  });
});

describe("a general solution with a restricted domain", () => {
  it("y' = e^{x+2y} accepts y = -½ln(C − 2eˣ)", () => {
    const q = ode(String.raw`\text{Find the general solution of } \frac{dy}{dx} = e^{x+2y}`);
    expect(q.check("-log(C1 - 2*e^x)/2")).toBe(true);
  });

  it("but a PARTICULAR member is still not the general solution", () => {
    // No initial condition was given, so a specific constant does not answer the
    // question that was asked.
    const q = ode(String.raw`\text{Find the general solution of } \frac{dy}{dx} = e^{x+2y}`);
    expect(q.check("-log(5 - 2*e^x)/2")).toBe(false);
  });

  it("a separable one whose solution is a square root", () => {
    const q = ode(String.raw`\text{Find the general solution of } \frac{dy}{dx} = \frac{x^2}{y}`);
    expect(q.check("sqrt(2*x^3/3 + C1)")).toBe(true);
    expect(q.check("sqrt(2*x^3/3 + 1)")).toBe(false);
  });
});

describe("no regression — what the gate already refused", () => {
  it("a second-order equation still needs TWO independent constants", () => {
    const q = ode(
      String.raw`\text{Find the general solution of } \frac{d^2y}{dx^2} + 3\frac{dy}{dx} + 2y = 0`
    );
    expect(q.check("C1*e^(-x) + C2*e^(-2*x)")).toBe(true);
    expect(q.check("C1*e^(-x)")).toBe(false);
  });

  it("two constants that are not independent do not count as two", () => {
    const q = ode(String.raw`\text{Find the general solution of } \frac{d^2y}{dx^2} - y = 0`);
    expect(q.check("C1*e^x + C2*e^x")).toBe(false);
  });

  it("an IVP wants the particular solution, with nothing left free", () => {
    const q = ode(
      String.raw`\text{Solve } \frac{d^2y}{dx^2} + 4y = 0 \text{ where } y(0) = 1 \text{ and } y'(0) = 1`
    );
    expect(q.check("cos(2*x) + sin(2*x)/2")).toBe(true);
    expect(q.check("C1*cos(2*x) + C2*sin(2*x)")).toBe(false);
    expect(q.check("cos(2*x) + sin(2*x)")).toBe(false);
  });

  it("nothing at all is not a solution", () => {
    const q = ode(String.raw`\text{Find the general solution of } \frac{d^2y}{dx^2} - y = 0`);
    expect(q.check("")).toBe(false);
  });
});
