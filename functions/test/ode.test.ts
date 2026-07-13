// ODEs — the LLM proposes a solution y(x); we PROVE it by substitution
// (differentiate the candidate, check the residual ≈ 0 across samples + constant
// values + any initial conditions). A non-solution leaves a residual and is
// rejected → honest couldn't-verify. The LLM never invents the math.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { parseOde, verifyOde } from "../src/solver/ode";
import type { JsonCompleter } from "../src/solver/narrate";

/** A completer returning `{}` for narration and a canned ODE candidate otherwise. */
function candidate(answerLatex: string, solutionExpr: string): JsonCompleter {
  return async (system: string) => {
    if (system.includes("ALREADY-SOLVED")) return {};
    return { answerLatex, answerPlain: answerLatex, solutionExpr, solutions: [] };
  };
}

async function run(ode: string, answerLatex: string, solutionExpr: string) {
  const c = classify(ode);
  const p = await solve(c, candidate(answerLatex, solutionExpr));
  return { cls: c, verified: p.verified, answer: p.finalAnswer?.plain };
}

describe("classify — ODE detection", () => {
  it("routes y' = 2y to the ODE gate", () => {
    const c = classify(String.raw`y' = 2y`);
    expect(c).toMatchObject({
      strategy: "llm_candidate",
      verifyMode: "ode",
      odeDepVar: "y",
      odeIndepVar: "x",
      odeOrder: 1,
    });
    expect(c.odeResidual).toBe("(dy) - (2y)");
  });

  it("reads dy/dt (a non-x independent variable)", () => {
    const c = classify(String.raw`\frac{dy}{dt} = -0.5 y`);
    expect(c).toMatchObject({ verifyMode: "ode", odeIndepVar: "t", odeDepVar: "y" });
  });

  it("captures numeric initial conditions", () => {
    const c = classify(String.raw`y'' - 3y' + 2y = 0, y(0)=2, y'(0)=3`);
    expect(c.odeOrder).toBe(2);
    expect(c.odeInitial).toEqual([
      { order: 0, at: 0, value: 2 },
      { order: 1, at: 0, value: 3 },
    ]);
  });

  it("does NOT treat a plain equation or a d/dx request as an ODE", () => {
    expect(classify(String.raw`2x + 3 = 7`).verifyMode).not.toBe("ode");
    expect(classify(String.raw`x^2 - 5x + 6 = 0`).verifyMode).not.toBe("ode");
    expect(classify(String.raw`\frac{d}{dx}(x^2)`).verifyMode).not.toBe("ode");
  });

  it("an apostrophe in prose is NOT a derivative (no word-problem hijack)", () => {
    // "it's"/"Tom's" — the ' is followed by a letter, so it's not a prime.
    expect(parseOde("it's x = 2")).toBeNull();
    expect(parseOde("Tom's age is x, and his father = 2x")).toBeNull();
    expect(classify("it's x = 2").verifyMode).not.toBe("ode");
  });

  it("declines a 3rd-order ODE (out of scope, never mis-verified as order 2)", () => {
    expect(parseOde(String.raw`y''' + y = 0`)).toBeNull();
    expect(classify(String.raw`y''' + y = 0`).verifyMode).not.toBe("ode");
  });
});

describe("solve — ODE substitution gate accepts real solutions", () => {
  it("first-order linear: y' = 2y → C₁e^{2x}", async () => {
    const r = await run(String.raw`y' = 2y`, "y = C_1 e^{2x}", "C1*e^(2*x)");
    expect(r.verified).toBe(true);
    // The displayed answer is rendered from the VERIFIED solutionExpr.
    expect(r.answer).toBe("y = C1*e^(2*x)");
  });

  it("second-order: y'' + y = 0 → C₁cos x + C₂sin x", async () => {
    const r = await run(String.raw`y'' + y = 0`, "y = C_1\\cos x + C_2\\sin x", "C1*cos(x) + C2*sin(x)");
    expect(r.verified).toBe(true);
  });

  it("constant-coefficient: y'' − 5y' + 6y = 0 → C₁e^{2x} + C₂e^{3x}", async () => {
    const r = await run(String.raw`y'' - 5y' + 6y = 0`, "y = C_1 e^{2x} + C_2 e^{3x}", "C1*e^(2*x) + C2*e^(3*x)");
    expect(r.verified).toBe(true);
  });

  it("separable: dy/dx = xy → C·e^{x²/2}", async () => {
    const r = await run(String.raw`\frac{dy}{dx} = x y`, "y = C e^{x^2/2}", "C1*e^(x^2/2)");
    expect(r.verified).toBe(true);
  });

  it("direct antiderivative: dy/dx = x → x²/2 + C", async () => {
    const r = await run(String.raw`\frac{dy}{dx} = x`, "y = \\frac{x^2}{2} + C", "x^2/2 + C1");
    expect(r.verified).toBe(true);
  });

  it("IVP: y' = 2y, y(0) = 3 → 3e^{2x}", async () => {
    const r = await run(String.raw`y' = 2y, y(0) = 3`, "y = 3 e^{2x}", "3*e^(2*x)");
    expect(r.verified).toBe(true);
  });

  it("second-order IVP: checks y(0) AND y'(0)", async () => {
    const r = await run(
      String.raw`y'' - 3y' + 2y = 0, y(0)=2, y'(0)=3`,
      "y = e^x + e^{2x}",
      "e^(x) + e^(2*x)"
    );
    expect(r.verified).toBe(true);
  });
});

describe("solve — ODE gate REJECTS non-solutions (golden rule)", () => {
  it("rejects a wrong exponent (y' = 2y with e^{3x})", async () => {
    const r = await run(String.raw`y' = 2y`, "y = C_1 e^{3x}", "C1*e^(3*x)");
    expect(r.verified).toBe(false);
  });

  it("rejects a wrong form (y'' + y = 0 with e^x)", async () => {
    const r = await run(String.raw`y'' + y = 0`, "y = C_1 e^{x}", "C1*e^(x)");
    expect(r.verified).toBe(false);
  });

  it("rejects a solution that violates the initial condition", async () => {
    const r = await run(String.raw`y' = 2y, y(0) = 3`, "y = 5 e^{2x}", "5*e^(2*x)");
    expect(r.verified).toBe(false);
  });

  it("rejects a general solution when an IVP demanded a particular one", async () => {
    // constants left unresolved despite y(0)=3 → not pinned down → decline
    const r = await run(String.raw`y' = 2y, y(0) = 3`, "y = C_1 e^{2x}", "C1*e^(2*x)");
    expect(r.verified).toBe(false);
  });

  it("rejects an empty candidate", async () => {
    const r = await run(String.raw`y' = 2y`, "", "");
    expect(r.verified).toBe(false);
  });
});

describe("verifyOde — unit", () => {
  it("accepts a correct solution, rejects a perturbed one", () => {
    expect(verifyOde("(dy) - (2y)", "y", "x", 1, "C1*e^(2*x)", [])).toBe(true);
    expect(verifyOde("(dy) - (2y)", "y", "x", 1, "C1*e^(2.01*x)", [])).toBe(false);
  });

  it("enforces initial conditions", () => {
    expect(verifyOde("(dy) - (2y)", "y", "x", 1, "3*e^(2*x)", [{ order: 0, at: 0, value: 3 }])).toBe(true);
    expect(verifyOde("(dy) - (2y)", "y", "x", 1, "3*e^(2*x)", [{ order: 0, at: 0, value: 4 }])).toBe(false);
  });
});

// Every finding from the adversarial review of the ODE solver: each shipped a
// WRONG answer as verified:true (a golden-rule hole). These lock the fixes.
describe("regression — ODE review findings", () => {
  const cand = (solutionExpr: string): JsonCompleter => async (system: string) =>
    system.includes("ALREADY-SOLVED")
      ? {}
      : { answerLatex: "y = ?", answerPlain: "y = ?", solutionExpr, solutions: [] };
  const solveWith = async (ode: string, sol: string) =>
    (await solve(classify(ode), cand(sol))).verified;

  it("#1 CRITICAL: a collapsed residual (dy/dx = dx/dy) no longer accepts anything", async () => {
    // buildResidual must NOT map \frac{dx}{dy} to the same dy token → residual is
    // not identically zero → a garbage candidate is rejected.
    expect(await solveWith(String.raw`\frac{dy}{dx} = \frac{dx}{dy}`, "x^3 + 7")).toBe(false);
    expect(await solveWith(String.raw`\frac{dy}{dx} = \frac{dz}{dx}`, "sin(5*x)")).toBe(false);
    // The degeneracy guard also rejects a tautology (same derivative both sides).
    expect(verifyOde("(dy) - (dy)", "y", "x", 1, "x^3 + 7", [])).toBe(false);
  });

  it("#2 HIGH: an incomplete general solution is rejected (constants ≠ order)", async () => {
    // y'' - 4y = 0 needs TWO independent constants; one branch is not enough.
    expect(await solveWith(String.raw`y'' - 4y = 0`, "C1*e^(2*x)")).toBe(false);
    // A dropped constant (particular passed off as general) is rejected.
    expect(await solveWith(String.raw`y' = 2y`, "e^(2*x)")).toBe(false);
    // Repeated root written as C1 e^x + C2 e^x — two symbols, one DOF (rank 1).
    expect(await solveWith(String.raw`y'' - 2y' + y = 0`, "C1*e^(x) + C2*e^(x)")).toBe(false);
    // The genuine general solutions still verify.
    expect(await solveWith(String.raw`y'' - 4y = 0`, "C1*e^(2*x) + C2*e^(-2*x)")).toBe(true);
    expect(await solveWith(String.raw`y' = 2y`, "C1*e^(2*x)")).toBe(true);
  });

  it("#3 MEDIUM: the DISPLAYED answer is the verified expression, not free text", async () => {
    // solutionExpr is correct but answerLatex diverges → we ship the verified one.
    const c = classify(String.raw`y' = 2y`);
    const p = await solve(
      c,
      async (system: string) =>
        system.includes("ALREADY-SOLVED")
          ? {}
          : {
              answerLatex: "y = 5 e^{2x} + 7x", // WRONG, never checked
              answerPlain: "y = 5 e^{2x} + 7x",
              solutionExpr: "C1*e^(2*x)", // correct
              solutions: [],
            }
    );
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("y = C1*e^(2*x)"); // the verified expression
    expect(p.finalAnswer?.plain).not.toContain("7x"); // never the divergent free text
  });

  it("declines an absurdly long input (no pathological backtracking)", () => {
    expect(parseOde("y' = " + " ".repeat(5000) + "2y")).toBeNull();
  });
});
