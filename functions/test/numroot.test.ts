// A root asked for as a NUMBER — "find the positive root of sin x = ½x to 6
// decimal places".
//
// The family was split between two wrong answers. The transcendental ones went
// to the tutor. The polynomial ones went to the exact-equation route, which
// returns a closed form when the question asked for six digits — right number,
// wrong answer.
//
// The answer here comes from bisection, which uses nothing but the sign of f.
// The gate re-finds the same root with Newton–Raphson from the far end of the
// bracket, driven by the symbolic derivative: a tangent line and a sign test
// share no machinery, so agreement is evidence rather than the same arithmetic
// run twice. And the rounding is part of the answer — a root sitting on the
// rounding boundary of the requested digit is declined, not rounded and
// asserted.
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

describe("transcendental roots, which no exact engine could reach", () => {
  it("the sheet question: the positive root of sin x = x/2", () => {
    // x = 0 is a root too, which is why "positive" is doing real work here.
    const r = run(
      String.raw`\text{Find the positive root of } \sin x = \frac{1}{2}x \text{ to 6 decimal places}`
    );
    expect(r.type).toBe("numeric_root");
    expect(r.answer).toBe("x = 1.895494");
  });

  it("the Dottie number, cos x = x", () => {
    const r = run(
      String.raw`\text{Find the smallest positive root of } \cos x = x \text{ correct to 5 decimal places}`
    );
    expect(r.answer).toBe("x = 0.73909");
  });

  it("an interval pins down which root of e^x = 3x is wanted", () => {
    // The other one is near 1.512; the bracket is the whole question.
    const r = run(
      String.raw`\text{Find the root of } e^x = 3x \text{ in the interval } [0, 1] \text{ to 4 decimal places}`
    );
    expect(r.answer).toBe("x = 0.6191");
  });

  it("'the root' singular is answered when the search finds exactly one", () => {
    const r = run(String.raw`\text{Find the root of } \ln x = 1 \text{ to 5 decimal places}`);
    expect(r.answer).toBe("x = 2.71828");
  });
});

describe("polynomials, where the exact route answered a different question", () => {
  it("Newton–Raphson named explicitly", () => {
    const r = run(
      String.raw`\text{Use the Newton-Raphson method to find the root of } x^3 - x - 1 = 0 \text{ to 5 decimal places}`
    );
    expect(r.type).toBe("numeric_root");
    expect(r.answer).toBe("x = 1.32472");
  });

  it("no method named — the precision alone is the ask", () => {
    const r = run(String.raw`\text{Solve } x^3 - x - 1 = 0 \text{ to 4 decimal places}`);
    expect(r.answer).toBe("x = 1.3247");
  });

  it("all the real roots, because Cauchy's bound makes the window exhaustive", () => {
    const r = run(String.raw`\text{Solve } x^2 - 2 = 0 \text{ to 4 decimal places}`);
    expect(r.answer).toBe("x = -1.4142 or x = 1.4142");
  });

  it("three roots stay three roots", () => {
    const r = run(
      String.raw`\text{Solve } x^3 - 6x^2 + 11x - 6 = 0 \text{ to 3 decimal places}`
    );
    expect(r.answer).toBe("x = 1.000 or x = 2.000 or x = 3.000");
  });

  it("the NEGATIVE root of a cubic with three of them", () => {
    const r = run(
      String.raw`\text{Find the negative root of } x^3 - 3x + 1 = 0 \text{ to 4 decimal places}`
    );
    expect(r.answer).toBe("x = -1.8794");
  });

  it("significant figures, not decimal places", () => {
    const r = run(
      String.raw`\text{Find the root of } x^3 + x - 3 = 0 \text{ to 3 significant figures}`
    );
    expect(r.answer).toBe("x = 1.21");
  });
});

describe("what it declines rather than guess", () => {
  it("'the positive root' when there are two of them", () => {
    // x = 1 and x = 2 are both positive. Answering with either is answering a
    // question that was not asked.
    const r = run(
      String.raw`\text{Find the positive root of } x^2 - 3x + 2 = 0 \text{ to 4 decimal places}`
    );
    expect(r.answer).toBeNull();
  });

  it("every root of a transcendental equation is not a finite list", () => {
    // sin x = 0 has infinitely many. No window can promise to hold them all.
    const r = run(String.raw`\text{Solve } \sin x = 0 \text{ to 4 decimal places}`);
    expect(r.answer).toBeNull();
  });

  it("an equation with no real root at all", () => {
    const r = run(String.raw`\text{Solve } x^2 + 1 = 0 \text{ to 4 decimal places}`);
    expect(r.answer).toBeNull();
  });

  it("a free parameter means there is no one number", () => {
    const r = run(
      String.raw`\text{Find the root of } x^2 - k = 0 \text{ to 4 decimal places}`
    );
    expect(r.type).not.toBe("numeric_root");
  });
});

describe("the gate is not the answer path", () => {
  it("a root on the rounding boundary has no correct N-place spelling", () => {
    // The root of 4x − 5 = 0 is exactly 1.25, and to 1 d.p. that is 1.2 or 1.3
    // depending on a rounding convention rather than on the mathematics.
    const cls = classify(String.raw`\text{Solve } 4x - 5 = 0 \text{ to 1 decimal place}`);
    const cand = solveDeterministic(cls);
    expect(cand?.answer.plain ?? null).toBeNull();
  });

  it("but a root that is merely short is spelled out in full", () => {
    const r = run(String.raw`\text{Solve } 4x - 5 = 0 \text{ to 3 decimal places}`);
    expect(r.answer).toBe("x = 1.250");
  });
});

describe("no regression — the equations that already had exact answers", () => {
  it("a plain quadratic keeps its exact roots", () => {
    const r = run(String.raw`\text{Solve } x^2 - 5x + 6 = 0`);
    expect(r.type).toBe("quadratic_equation");
    expect(r.answer).toBe("x = 2 or x = 3");
  });

  it("a trig equation with no precision directive is untouched", () => {
    expect(classify(String.raw`\text{Solve } \cos x = x`).problemType).not.toBe("numeric_root");
  });

  it("a bounded-range trig equation keeps its own enumerator", () => {
    const cls = classify(
      String.raw`\text{Solve } \sin x = 0.5 \text{ for } 0 \le x \le 360`
    );
    expect(cls.problemType).not.toBe("numeric_root");
  });

  it("rounding a plain number is not a root question", () => {
    expect(
      classify(String.raw`\text{Write } 3.14159 \text{ to 3 decimal places}`).problemType
    ).not.toBe("numeric_root");
  });
});
