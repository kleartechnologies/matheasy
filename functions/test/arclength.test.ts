// Arc length — "the length of the curve x(t) = t − sin t, y(t) = 1 − cos t for
// 0 ≤ t ≤ 2π". Two definitions and an interval reads as several asks, so the
// whole family went to the tutor; it is one number.
//
// The integrand √(x′² + y′²) is built by symbolic differentiation, so nothing
// about it is guessed. The number is a quadrature, and a quadrature is worth
// only as much as its check: Gauss–Legendre and Romberg have error terms with
// nothing in common, and both must land on the same value before anything is
// returned. A curve with a corner or a pole in range makes them disagree —
// which is exactly when this engine should say nothing.
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

/** For the lengths that are irrational and have no surd form worth printing. */
function num(answer: string | null): number {
  return Number(answer);
}

describe("parametric curves", () => {
  it("the cycloid's arch is exactly 8, not 7.9999999999", () => {
    const r = run(
      String.raw`\text{Find the arc length of } x(t) = t - \sin t, y(t) = 1 - \cos t \text{ for } 0 \le t \le 2\pi`
    );
    expect(r.type).toBe("arc_length");
    expect(r.answer).toBe("8");
  });

  it("half a unit circle is π", () => {
    const r = run(
      String.raw`\text{Find the length of the curve } x(t) = \cos t, y(t) = \sin t \text{ for } 0 \le t \le \pi`
    );
    expect(r.answer).toBe("π");
  });

  it("a straight segment written parametrically — 3-4-5", () => {
    const r = run(
      String.raw`\text{Find the arc length of } x(t) = 3t, y(t) = 4t \text{ for } 0 \le t \le 1`
    );
    expect(r.answer).toBe("5");
  });

  it("the astroid's first quadrant arc is 3/2", () => {
    const r = run(
      String.raw`\text{Find the arc length of } x(t) = \cos(t)^3, y(t) = \sin(t)^3 \text{ from } t = 0 \text{ to } t = \frac{\pi}{2}`
    );
    expect(num(r.answer)).toBeCloseTo(1.5, 5);
  });
});

describe("y = f(x)", () => {
  it("y = x^{3/2} over [0, 4]", () => {
    // (80√10 − 8)/27. No surd form worth printing, so the decimal is the honest
    // answer rather than a dressed-up one.
    const r = run(
      String.raw`\text{Find the arc length of the curve } y = x^{3/2} \text{ for } 0 \le x \le 4`
    );
    expect(r.type).toBe("arc_length");
    expect(num(r.answer)).toBeCloseTo((80 * Math.sqrt(10) - 8) / 27, 5);
  });

  it("the catenary from 0 to 1 is sinh 1", () => {
    const r = run(
      String.raw`\text{Find the arc length of the curve } y = \cosh x \text{ from } x = 0 \text{ to } x = 1`
    );
    expect(num(r.answer)).toBeCloseTo(Math.sinh(1), 5);
  });

  it("the textbook one that integrates exactly: 3/2 + (ln 2)/4", () => {
    const r = run(
      String.raw`\text{Find the arc length of } y = \frac{x^2}{2} - \frac{\ln x}{4} \text{ for } 1 \le x \le 2`
    );
    expect(num(r.answer)).toBeCloseTo(1.5 + Math.log(2) / 4, 5);
  });

  it("a line is its own length — and it comes out as a surd", () => {
    // 3√5, not 6.7082039325. The interval here is written a third way again:
    // "between … and …".
    const r = run(
      String.raw`\text{Find the arc length of the curve } y = 2x + 1 \text{ between } x = 0 \text{ and } x = 3`
    );
    expect(r.answer).toBe("3√5");
  });
});

describe("what it declines rather than guess", () => {
  it("no interval at all", () => {
    const r = run(String.raw`\text{Find the arc length of the curve } y = x^2`);
    expect(r.type).not.toBe("arc_length");
  });

  it("a curve carrying a free parameter is not one curve", () => {
    const r = run(
      String.raw`\text{Find the arc length of the curve } y = a x^2 \text{ for } 0 \le x \le 1`
    );
    expect(r.type).not.toBe("arc_length");
  });

  it("an interval that runs backwards", () => {
    const r = run(
      String.raw`\text{Find the arc length of the curve } y = x^2 \text{ for } 3 \le x \le 1`
    );
    expect(r.type).not.toBe("arc_length");
  });

  it("the two components in different parameters", () => {
    const r = run(
      String.raw`\text{Find the arc length of } x(t) = t^2, y(u) = u^3 \text{ for } 0 \le t \le 1`
    );
    expect(r.type).not.toBe("arc_length");
  });

  it("a pole inside the range — the two rules disagree, so nothing is returned", () => {
    const r = run(
      String.raw`\text{Find the arc length of the curve } y = \frac{1}{x} \text{ for } -1 \le x \le 1`
    );
    expect(r.answer).toBeNull();
  });
});

describe("no regression — the other 'length' questions", () => {
  it("the length of a VECTOR is not an arc", () => {
    const cls = classify(String.raw`\text{Find the magnitude of } (3, 4, 12)`);
    expect(cls.problemType).not.toBe("arc_length");
  });

  it("a plain definite integral keeps its own engine", () => {
    const cls = classify(String.raw`\int_0^1 x^2 \, dx`);
    expect(cls.problemType).not.toBe("arc_length");
  });

  it("differentiating a curve is still differentiation", () => {
    const cls = classify(String.raw`\text{Differentiate } y = \cosh x`);
    expect(cls.problemType).not.toBe("arc_length");
  });
});
