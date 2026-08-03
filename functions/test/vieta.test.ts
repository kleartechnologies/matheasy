// Symmetric functions of a polynomial's roots — "the cubic 2x³ − 3x² + 4x − 5 = 0
// has roots α, β, γ. Find α + β + γ."
//
// The whole family used to reach the tutor: naming an equation and then asking
// about a quantity built from its roots reads as two asks, and even past that,
// most of these cubics have one real root and an irrational pair, so the
// equation engines had nothing to say either.
//
// The answer comes from the roots (Durand–Kerner, all n at once). The gate never
// finds a root: it multiplies the root set back out and requires it to rebuild
// the printed polynomial coefficient for coefficient, and Newton's identities —
// computed from the coefficients with no root-finding anywhere — confirm every
// power sum a second time. Then the value must survive every relabelling of the
// roots, because otherwise the question has no single answer.
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

const cubic = (poly: string, ask: string) =>
  String.raw`\text{The cubic } ${poly} = 0 \text{ has roots } \alpha, \beta, \gamma \text{. Find } ${ask}`;

describe("the elementary symmetric functions", () => {
  it("Σα of 2x³ − 3x² + 4x − 5", () => {
    const r = run(cubic(String.raw`2x^3 - 3x^2 + 4x - 5`, String.raw`\alpha + \beta + \gamma`));
    expect(r.type).toBe("root_symmetric_function");
    expect(r.answer).toBe("3/2"); // −a₂/a₃
  });

  it("Σαβ", () => {
    const r = run(
      cubic(String.raw`x^3 - 2x^2 + 3x - 4`, String.raw`\alpha\beta + \beta\gamma + \gamma\alpha`)
    );
    expect(r.answer).toBe("3");
  });

  it("αβγ", () => {
    const r = run(cubic(String.raw`x^3 - 2x^2 + 3x - 4`, String.raw`\alpha\beta\gamma`));
    expect(r.answer).toBe("4");
  });
});

describe("power sums, where Newton's identities have to agree", () => {
  it("Σα² of a cubic with only one real root", () => {
    // e₁² − 2e₂ = 4 − 6. Solving the cubic was never on the table: it has one
    // real root and a complex pair.
    const r = run(
      cubic(String.raw`x^3 - 2x^2 + 3x - 4`, String.raw`\alpha^2 + \beta^2 + \gamma^2`)
    );
    expect(r.answer).toBe("-2");
  });

  it("Σα⁴ — past the degree, where the recurrence changes shape", () => {
    const r = run(
      cubic(String.raw`x^3 - 2x^2 + 3x - 4`, String.raw`\alpha^4 + \beta^4 + \gamma^4`)
    );
    expect(r.answer).toBe("18");
  });

  it("α³ + β³ of a QUADRATIC — k > n, the first k where the two forms differ", () => {
    // Roots 1/3 and −2, so 1/27 − 8 = −215/27. Running the ≤n and >n branches of
    // Newton's identities together double-counts the last term, and this is the
    // smallest case that notices.
    const r = run(
      String.raw`\text{The quadratic } 3x^2 + 5x - 2 = 0 \text{ has roots } \alpha \text{ and } \beta \text{. Find } \alpha^3 + \beta^3`
    );
    expect(r.answer).toBe("-215/27");
  });

  it("Σα² of a quartic", () => {
    const r = run(
      String.raw`\text{The quartic } x^4 - x^3 + 2x^2 - x + 1 = 0 \text{ has roots } \alpha, \beta, \gamma, \delta \text{. Find } \alpha^2 + \beta^2 + \gamma^2 + \delta^2`
    );
    expect(r.answer).toBe("-3");
  });
});

describe("the rest of the family", () => {
  it("Σ1/α", () => {
    // x³ − 6x² + 11x − 6 has roots 1, 2, 3 ⇒ 1 + 1/2 + 1/3.
    const r = run(
      cubic(
        String.raw`x^3 - 6x^2 + 11x - 6`,
        String.raw`\frac{1}{\alpha} + \frac{1}{\beta} + \frac{1}{\gamma}`
      )
    );
    expect(r.answer).toBe("11/6");
  });

  it("(α+β)(β+γ)(γ+α)", () => {
    const r = run(
      cubic(
        String.raw`x^3 - 6x^2 + 11x - 6`,
        String.raw`(\alpha + \beta)(\beta + \gamma)(\gamma + \alpha)`
      )
    );
    expect(r.answer).toBe("60");
  });

  it("Σα² of a quadratic", () => {
    const r = run(
      String.raw`\text{The quadratic } x^2 - 5x + 6 = 0 \text{ has roots } \alpha, \beta \text{. Find } \alpha^2 + \beta^2`
    );
    expect(r.answer).toBe("13");
  });
});

describe("what it will not answer", () => {
  it("α + β of a CUBIC is not a number", () => {
    // It depends on which root you called γ. Answering with whichever labelling
    // the root-finder produced would be inventing a result.
    expect(classify(cubic(String.raw`x^3 - 2x^2 + 3x - 4`, String.raw`\alpha + \beta`)).strategy)
      .not.toBe("vieta");
  });

  it("the wrong NUMBER of root names for the degree", () => {
    expect(
      classify(
        String.raw`\text{The cubic } x^3 - 2x^2 + 3x - 4 = 0 \text{ has roots } \alpha, \beta \text{. Find } \alpha + \beta`
      ).strategy
    ).not.toBe("vieta");
  });

  it("a polynomial carrying a free parameter", () => {
    expect(
      classify(cubic(String.raw`x^3 - kx^2 + 3x - 4`, String.raw`\alpha + \beta + \gamma`)).strategy
    ).not.toBe("vieta");
  });

  it("an ask in a symbol that is not one of the roots", () => {
    expect(
      classify(cubic(String.raw`x^3 - 2x^2 + 3x - 4`, String.raw`\alpha + \beta + \gamma + t`))
        .strategy
    ).not.toBe("vieta");
  });
});

describe("no regression — the equations that already solved", () => {
  it("a plain cubic is still solved for x", () => {
    expect(classify(String.raw`\text{Solve } x^3 - 6x^2 + 11x - 6 = 0`).strategy).not.toBe("vieta");
  });

  it("a plain quadratic keeps its roots", () => {
    const r = run(String.raw`\text{Solve } x^2 - 5x + 6 = 0`);
    expect(r.type).toBe("quadratic_equation");
    expect(r.answer).toBe("x = 2 or x = 3");
  });
});
