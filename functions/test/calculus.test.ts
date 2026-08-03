/**
 * The applied-differentiation engine — the shape a real problem sheet uses:
 * DEFINE a function, then ask about its derivative in Leibniz notation.
 *
 * Two things are under test and they matter equally:
 *  1. the answers are right, and
 *  2. the engine DECLINES whenever it cannot prove them — a wrong printed
 *     claim, a point the curve does not pass through, a stationary set whose
 *     completeness is unprovable. A decline falls through to the tutor route,
 *     which is exactly where these problems went before this engine existed.
 */
import { describe, expect, it } from "vitest";

import { parseCalculus, solveCalculus } from "../src/solver/calculus";
import { classify } from "../src/solver/classify";
import { solveDeterministic } from "../src/solver/deterministic";

/** Classify + solve + verify, returning the plain answer or null on decline. */
function solve(latex: string): string | null {
  const cls = classify(latex);
  if (cls.strategy !== "calculus") return null;
  const cand = solveDeterministic(cls);
  if (!cand || !cand.verify()) return null;
  return cand.answer.plain;
}

function typeOf(latex: string): string {
  return classify(latex).problemType;
}

describe("calculus — routing", () => {
  it("routes a Leibniz derivative over a defined function", () => {
    const cls = classify(String.raw`\text{If } y = \ln(1 + x^2) \text{, find } \frac{dy}{dx}`);
    expect(cls.strategy).toBe("calculus");
    expect(cls.problemType).toBe("derivative");
    expect(cls.unknown).toBe("x");
  });

  it("names each task honestly", () => {
    expect(
      typeOf(String.raw`\text{Find the slope of the curve } y = 4x + e^x \text{ at } (0, 1)`)
    ).toBe("curve_gradient");
    expect(
      typeOf(
        String.raw`\text{Find the equation of the tangent to } y = x^3 - 2x + 1 \text{ at } (1, 0)`
      )
    ).toBe("tangent_line");
    expect(
      typeOf(String.raw`\text{Find the equation of the normal to } y = x^2 \text{ at } (2, 4)`)
    ).toBe("normal_line");
    expect(
      typeOf(
        String.raw`\text{Find the angle of inclination of the tangent to } y = x^2 \text{ at } (1, 1)`
      )
    ).toBe("angle_of_inclination");
    expect(
      typeOf(String.raw`\text{If } s = 3t^3 + 4t + 1 \text{, find the acceleration at } t = 4`)
    ).toBe("kinematics");
    expect(typeOf(String.raw`\text{Classify the stationary points of } y = x^3 - 3x`)).toBe(
      "stationary_points"
    );
    expect(
      typeOf(
        String.raw`\text{If } y = \ln[x + \sqrt{1 + x^2}] \text{, show that } \frac{dy}{dx} = \frac{1}{\sqrt{1+x^2}}`
      )
    ).toBe("derivative_identity");
  });

  it("leaves the OPERATOR form on the existing derivative engine", () => {
    const cls = classify(String.raw`\frac{d}{dx}(x^2 + 3x)`);
    expect(cls.strategy).toBe("derivative");
  });

  it("never swallows a differential equation", () => {
    // `dy/dx = 2y` has the same Leibniz operator, but its right-hand side is in
    // the DEPENDENT variable — that is an ODE, and misreading it as "y is
    // defined to be 2y" would be a silent wrong answer.
    for (const ode of [
      String.raw`\frac{dy}{dx} = 2y`,
      String.raw`\text{Solve } \frac{dy}{dx} + 2y = 0`,
      String.raw`\frac{dy}{dx} = x y`,
    ]) {
      expect(classify(ode).strategy).not.toBe("calculus");
    }
  });

  it("declines integrals, limits and matrices outright", () => {
    expect(parseCalculus(String.raw`\int y = x^2 \, dx`)).toBeNull();
    expect(parseCalculus(String.raw`\lim_{x \to 0} y = \frac{\sin x}{x}`)).toBeNull();
  });
});

describe("calculus — derivatives", () => {
  const cases: [string, string][] = [
    [String.raw`\text{If } y = \ln(1 + x^2) \text{, find } \frac{dy}{dx}`, "2 * x / (x ^ 2 + 1)"],
    [String.raw`\text{If } y = \cosh(x^4) \text{, find } \frac{dy}{dx}`, "4 * x ^ 3 * sinh(x ^ 4)"],
  ];

  it.each(cases)("%s", (latex, expected) => {
    expect(solve(latex)).toBe(`dy/dx = ${expected}`);
  });

  it("labels a SECOND derivative as one", () => {
    // Announcing d²y/dx² as "dy/dx" would be a false statement about the answer.
    const answer = solve(String.raw`\text{If } y = \ln x \text{, find } \frac{d^2y}{dx^2}`);
    expect(answer).toMatch(/^d\^2y\/dx\^2 = /);
  });

  it("differentiates a quotient correctly", () => {
    const cls = classify(String.raw`\text{If } y = \frac{x^3}{2x-1} \text{, find } \frac{dy}{dx}`);
    const cand = solveDeterministic(cls);
    expect(cand).not.toBeNull();
    expect(cand!.verify()).toBe(true);
  });
});

describe("calculus — show that dy/dx = …", () => {
  it("proves a correct identity", () => {
    const answer = solve(
      String.raw`\text{If } y = \ln[x + \sqrt{1 + x^2}] \text{, show that } \frac{dy}{dx} = \frac{1}{\sqrt{1+x^2}}`
    );
    expect(answer).not.toBeNull();
  });

  it("proves sinh⁻¹ x", () => {
    expect(
      solve(
        String.raw`\text{If } y = \sinh^{-1} x \text{, show that } \frac{dy}{dx} = \frac{1}{\sqrt{1+x^2}}`
      )
    ).not.toBeNull();
  });

  it("REFUSES a claim it cannot reproduce", () => {
    // A single misread digit — 1+x³ where the sheet printed 1+x². The engine
    // must not "show" something it did not derive.
    expect(
      solve(
        String.raw`\text{If } y = \ln(1+x^2) \text{, show that } \frac{dy}{dx} = \frac{2x}{1+x^3}`
      )
    ).toBeNull();
  });
});

describe("calculus — evaluated at a point", () => {
  it("finds a slope", () => {
    // y = 4x + e^x at (0,1): y' = 4 + e^x = 5.
    expect(solve(String.raw`\text{Find the slope of } y = 4x + e^x \text{ at } (0, 1)`)).toBe(
      "slope = 5"
    );
  });

  it("finds an acceleration from a displacement law", () => {
    // s = 3t³ + 4t + 1 → a = 18t → 72 at t = 4.
    expect(
      solve(String.raw`\text{A body moves so that } s = 3t^3 + 4t + 1 \text{. Find the acceleration at } t = 4`)
    ).toBe("acceleration = 72");
  });

  it("finds a velocity", () => {
    // s = t − sin t → v = 1 − cos t → 1 − cos 2 ≈ 1.416147.
    expect(solve(String.raw`\text{If } s = t - \sin t \text{, find the velocity at } t = 2`)).toBe(
      "velocity = 1.416147"
    );
  });

  it("REFUSES when the stated point is not on the curve", () => {
    // (0, 7) is not on y = 4x + e^x. Either the curve or the point was misread;
    // answering anyway would be answering a different question.
    expect(solve(String.raw`\text{Find the slope of } y = 4x + e^x \text{ at } (0, 7)`)).toBeNull();
  });
});

describe("calculus — tangent and normal lines", () => {
  it("builds a tangent line", () => {
    // y = x³ − 2x + 1 at (1, 0): y' = 3x² − 2 = 1 → y = x − 1.
    expect(
      solve(
        String.raw`\text{Find the equation of the tangent to the curve } y = x^3 - 2x + 1 \text{ at } (1, 0)`
      )
    ).toBe("y = x - 1");
  });

  it("builds a normal line, in exact fractions", () => {
    // y = x² at (2, 4): tangent slope 4, normal slope −1/4 → y = −x/4 + 9/2.
    // A normal printed as "-0.25x + 4.5" would lose the exact form the golden
    // rule requires.
    const answer = solve(
      String.raw`\text{Find the equation of the normal to the curve } y = x^2 \text{ at } (2, 4)`
    );
    expect(answer).toBe("y = -1/4x + 9/2");
  });

  it("REFUSES a normal where the tangent is horizontal", () => {
    // The normal at the vertex of y = x² is the vertical line x = 0, which has
    // no y = mx + c form. Declining beats printing an infinite gradient.
    expect(
      solve(String.raw`\text{Find the equation of the normal to } y = x^2 \text{ at } (0, 0)`)
    ).toBeNull();
  });
});

describe("calculus — angle of inclination", () => {
  it("reports the angle of the tangent", () => {
    // y = x² at (1,1): m = 2 → θ = arctan 2 = 63.4349°.
    const answer = solve(
      String.raw`\text{Find the angle of inclination of the tangent to } y = x^2 \text{ at } (1, 1)`
    );
    expect(answer).toBe("theta = 63.4349 degrees");
  });
});

describe("calculus — stationary points", () => {
  it("finds and classifies both turning points of a cubic", () => {
    expect(solve(String.raw`\text{Classify the stationary points of } y = x^3 - 3x`)).toBe(
      "(-1, 2) is a maximum; (1, -2) is a minimum"
    );
  });

  it("finds all three of a quartic", () => {
    expect(
      solve(String.raw`\text{Find and classify the stationary points of } y = x^4 - 2x^2`)
    ).toBe("(-1, -1) is a minimum; (0, 0) is a maximum; (1, -1) is a minimum");
  });

  it("REFUSES when completeness cannot be proven", () => {
    // sin x has infinitely many stationary points. A list of the ones inside the
    // scan window would read as "these are the stationary points" — false.
    expect(solve(String.raw`\text{Classify the stationary points of } y = \sin x`)).toBeNull();
  });

  // A RATIONAL curve's derivative is a fraction, so the polynomial-degree bound
  // can't read it and the whole family used to decline. `f = p/q` ⇒ the turning
  // points are the roots of `p′q − pq′`, and Durand–Kerner returns all of them.
  it("finds the turning points of a rational curve", () => {
    expect(solve(String.raw`\text{Find the turning points of } y = x + \frac{1}{x}`)).toBe(
      "(-1, -2) is a maximum; (1, 2) is a minimum"
    );
  });

  it("handles a turning point BETWEEN two poles", () => {
    const r = solve(
      String.raw`\text{Find the turning points of } y = \frac{x^2+1}{(x-1)(x-2)}`
    );
    // x = (1 ± √10)/3. The branch between the poles falls to −∞ at both ends,
    // so its turning point is a MAXIMUM at a NEGATIVE y — the sign the scan
    // route would have had no way to reach.
    expect(r).toBe(
      "(-0.720759, 0.324555) is a minimum; (1.387426, -12.324555) is a maximum"
    );
  });

  it("a pole is NOT a turning point", () => {
    // 1/x has none at all; listing x = 0 would be a plain error.
    expect(solve(String.raw`\text{Find the turning points of } y = \frac{1}{x}`)).toBeNull();
  });

  it("a removable factor is not one either", () => {
    // (x²−1)/(x−1) is the line y = x+1 with a hole — nothing is stationary.
    expect(
      solve(String.raw`\text{Find the turning points of } y = \frac{x^2-1}{x-1}`)
    ).toBeNull();
  });
});

describe("calculus — the parse stays narrow", () => {
  it("needs a function definition", () => {
    expect(parseCalculus(String.raw`\text{Find } \frac{dy}{dx}`)).toBeNull();
  });

  it("needs a recognised ask", () => {
    expect(parseCalculus(String.raw`y = x^2 + 1`)).toBeNull();
  });

  it("refuses a body carrying a free parameter", () => {
    // "y = ax²" has no single tangent, slope, or stationary point.
    expect(
      parseCalculus(String.raw`\text{If } y = a x^2 \text{, find } \frac{dy}{dx}`)
    ).toBeNull();
  });

  it("solveCalculus is a no-op without a spec", () => {
    expect(solveCalculus({})).toBeNull();
  });
});
