// A differential equation written the way a problem sheet writes it — "Find the
// general solution of …" in front of the maths. Two separate bugs sent these
// away from the ODE gate, and one of them shipped a WRONG ANSWER:
//
//   1. `\frac{d^2y}{dx^2} + 3\frac{dy}{dx} + 2y = x` — the `2y =` inside the
//      equation reads exactly like a function definition, so the calculus parser
//      claimed it and answered "d^2y/dx^2 = 0" to a question nobody asked.
//   2. "the general solution of <\frac …>" looked like a DERIVED-quantity ask
//      (its own Leibniz `\frac` was the giveaway), so the tutor route took it.
//
// Both must land on the ODE gate, where the LLM's candidate is proven by
// substituting it back into the equation.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

/** A completer returning `{}` for narration and a canned ODE candidate otherwise. */
function candidate(answerLatex: string, solutionExpr: string): JsonCompleter {
  return async (system: string) => {
    if (system.includes("ALREADY-SOLVED")) return {};
    return { answerLatex, answerPlain: answerLatex, solutionExpr, solutions: [] };
  };
}

const NEVER: JsonCompleter = async () => {
  throw new Error("the LLM must not be called");
};

describe("classify — an ODE behind a prose directive", () => {
  it("reads an INHOMOGENEOUS second-order ODE as an ODE, not as `y = x`", () => {
    const c = classify(
      String.raw`\text{Find the general solution of } \frac{d^2y}{dx^2} + 3\frac{dy}{dx} + 2y = x`
    );
    expect(c).toMatchObject({
      problemType: "differential_equation",
      strategy: "llm_candidate",
      verifyMode: "ode",
      odeDepVar: "y",
      odeIndepVar: "x",
      odeOrder: 2,
    });
  });

  it("the same equation with a trig and an exponential right-hand side", () => {
    for (const rhs of [String.raw`\sin x`, "e^{x}"]) {
      const c = classify(
        String.raw`\text{Find the general solution of } \frac{d^2y}{dx^2} + 3\frac{dy}{dx} + 2y = ${rhs}`
      );
      expect(c.problemType).toBe("differential_equation");
      expect(c.odeOrder).toBe(2);
    }
  });

  it("homogeneous and separable forms behind the same directive", () => {
    for (const eq of [
      String.raw`\frac{d^2y}{dx^2} - y = 0`,
      String.raw`\frac{d^2y}{dx^2} + 3\frac{dy}{dx} + 2y = 0`,
      String.raw`\frac{dy}{dx} = \frac{x^2}{y}`,
      String.raw`\frac{dy}{dx} = e^{x+2y}`,
    ]) {
      const c = classify(String.raw`\text{Find the general solution of } ${eq}`);
      expect(c.problemType).toBe("differential_equation");
      expect(c.verifyMode).toBe("ode");
    }
  });
});

// The guard that fixed bug 1 says a `y =` sitting in the same EXPRESSION as a
// derivative is a term, not a definition. A derivative separated from the
// definition by words is a different sentence, and those must still parse.
describe("no regression — a derivative question is still a derivative question", () => {
  const cases: [string, string][] = [
    [String.raw`\text{If } y = \ln(1+x^2) \text{, find } \frac{dy}{dx}`, "derivative"],
    [String.raw`\text{Find } \frac{dy}{dx} \text{ where } y = x^2`, "derivative"],
    [String.raw`\text{Find } \frac{dy}{dx} \text{ for } y = \sin x`, "derivative"],
    [String.raw`\text{If } y = e^{2x} \text{, find } \frac{d^2y}{dx^2}`, "derivative"],
    [String.raw`\text{Find the equation of the tangent to } y = x^2 \text{ at } x = 3`, "tangent_line"],
    [String.raw`\text{Given } s = t^3 - 2t \text{, find the velocity at } t = 2`, "kinematics"],
    [
      String.raw`\text{A particle moves so that } s = t - \sin t \text{. Find the times at which it is at rest.}`,
      "rest_times",
    ],
    [
      String.raw`\text{Given } r = 1 + \sin^2\theta \text{, find } \frac{dy}{dx} \text{ at } \theta = \frac{\pi}{4}`,
      "polar_gradient",
    ],
    [
      String.raw`\text{Show that if } y = x\sin x \text{ then } \frac{dy}{dx} = \sin x + x\cos x`,
      "derivative_identity",
    ],
  ];
  for (const [input, type] of cases) {
    it(`${type}: ${input.slice(0, 48)}…`, async () => {
      const c = classify(input);
      expect(c.problemType).toBe(type);
      expect(c.strategy).toBe("calculus");
      // Deterministic all the way through — no LLM anywhere in these.
      const p = await solve(c, NEVER);
      expect(p.verified).toBe(true);
    });
  }

  it("`\\text{Find the general solution of …}` does not swallow a plain solve", () => {
    // "the solution" of an ordinary equation is still that equation's root.
    const c = classify(String.raw`\text{Find the solution of } 2x + 5 = 15`);
    expect(c.problemType).not.toBe("beyond_solver");
  });
});

// End to end: the gate is what makes the answer trustworthy, not the directive.
describe("the substitution gate still decides", () => {
  const Q = String.raw`\text{Find the general solution of } \frac{d^2y}{dx^2} + 3\frac{dy}{dx} + 2y = x`;

  it("accepts the complementary function PLUS the correct particular integral", async () => {
    const c = classify(Q);
    const p = await solve(
      c,
      candidate(
        "y = C_1 e^{-x} + C_2 e^{-2x} + x/2 - 3/4",
        "C1*exp(-x) + C2*exp(-2*x) + x/2 - 3/4"
      )
    );
    expect(p.verified).toBe(true);
  });

  it("rejects the same answer with the particular integral wrong", async () => {
    const c = classify(Q);
    const p = await solve(
      c,
      candidate("y = C_1 e^{-x} + C_2 e^{-2x} + x/2", "C1*exp(-x) + C2*exp(-2*x) + x/2")
    );
    expect(p.verified).not.toBe(true);
  });
});
