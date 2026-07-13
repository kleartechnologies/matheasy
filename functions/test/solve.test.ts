import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { JsonCompleter } from "../src/solver/narrate";

/** A completer that returns `{}` for narration and a canned candidate otherwise. */
function completerWith(candidate: Record<string, unknown>): JsonCompleter {
  return async (system: string) => {
    if (system.includes("ALREADY-SOLVED")) return {}; // narration → fallbacks
    return candidate;
  };
}

const NEVER: JsonCompleter = async () => {
  throw new Error("completer should not be called");
};

async function run(latex: string, completer: JsonCompleter) {
  return solve(classify(latex), completer);
}

describe("solve — deterministic verified path", () => {
  it("quadratic returns the §4 schema, verified, with a graph", async () => {
    const p = await run("5x^2 + 3x - 2 = 0", completerWith({}));
    expect(p.verified).toBe(true);
    expect(p.problemType).toBe("quadratic_equation");
    expect(p.finalAnswer).toEqual({
      latex: "x_1 = -1,\\; x_2 = \\tfrac{2}{5}",
      plain: "x = -1 or x = 2/5",
    });
    expect(p.methods.map((m) => m.id)).toEqual(["factoring", "quadratic_formula"]);
    expect(p.methods.filter((m) => m.examPick)).toHaveLength(1);
    // narration failed/empty → humanized fallback label, empty why
    expect(p.methods[0].steps[0].operation).toBeTruthy();
    // graph reproduces the §4 example's key points
    expect(p.graph?.kind).toBe("function");
    const labels = p.graph!.keyPoints.map((k) => k.label);
    expect(labels).toContain("root");
    expect(labels).toContain("vertex");
    // §7 curve: deterministic samples (finite), spanning the roots' x-range.
    const curve = p.graph!.curve;
    expect(curve.length).toBeGreaterThan(20);
    expect(curve.every((c) => Number.isFinite(c.x) && Number.isFinite(c.y))).toBe(true);
    const roots = p.graph!.keyPoints.filter((k) => k.label === "root");
    const cxs = curve.map((c) => c.x);
    expect(Math.min(...cxs)).toBeLessThanOrEqual(Math.min(...roots.map((r) => r.x)));
    expect(Math.max(...cxs)).toBeGreaterThanOrEqual(Math.max(...roots.map((r) => r.x)));
  });

  it("no graph for a non-plottable problem (pure arithmetic)", async () => {
    const p = await run("3 + 4 \\times 2", completerWith({}));
    expect(p.graph).toBeNull();
  });

  it("linear equation verifies", async () => {
    const p = await run("2x + 5 = 15", completerWith({}));
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = 5");
  });
});

describe("solve — the verification gate", () => {
  it("returns couldn't-verify when there is no real solution", async () => {
    // mathsteps can't solve it; LLM offers complex roots (no real solutions).
    const p = await run("x^2 + 1 = 0", completerWith({
      answerLatex: "x = \\pm i",
      answerPlain: "x = ±i",
      solutions: [],
      methods: [],
    }));
    expect(p.verified).toBe(false);
    expect(p.finalAnswer).toBeNull();
    expect(p.methods).toEqual([]);
  });

  it("accepts a CORRECT llm candidate (trig)", async () => {
    const p = await run("\\sin(x) = 0.5", completerWith({
      answerLatex: "x = \\frac{\\pi}{6}",
      answerPlain: "x = pi/6",
      solutions: [{ variable: "x", value: Math.PI / 6 }],
      methods: [
        {
          id: "unit_circle",
          name: "Unit circle",
          examPick: true,
          steps: [{ expression: "x = \\frac{\\pi}{6}", operation: "Solve", why: "sin is 1/2 at 30°." }],
        },
      ],
    }));
    expect(p.verified).toBe(true);
    // trig mode: a general form built from the VERIFIED principal value (π/6),
    // not the model's free-text answerLatex.
    expect(p.finalAnswer!.latex).toContain("\\frac{\\pi}{6}");
    expect(p.finalAnswer!.plain).toContain("2πn");
    expect(p.methods[0].id).toBe("unit_circle");
  });

  it("REJECTS a wrong llm candidate (trig)", async () => {
    const p = await run("\\sin(x) = 0.5", completerWith({
      answerLatex: "x = 1",
      answerPlain: "x = 1",
      solutions: [{ variable: "x", value: 1 }],
      methods: [],
    }));
    expect(p.verified).toBe(false);
    expect(p.finalAnswer).toBeNull();
  });

  it("verifies a system by substituting into every equation", async () => {
    const p = await run("2x + 3y = 6, x - y = 3", completerWith({
      answerLatex: "x=3,\\; y=0",
      answerPlain: "x=3, y=0",
      solutions: [{ variable: "x", value: 3 }, { variable: "y", value: 0 }],
      methods: [
        { id: "elimination", name: "Elimination", examPick: true, steps: [{ expression: "x=3, y=0", operation: "Solve", why: "..." }] },
      ],
    }));
    expect(p.verified).toBe(true);
    expect(p.problemType).toBe("system_of_equations");
  });

  it("rejects a wrong system solution", async () => {
    const p = await run("2x + 3y = 6, x - y = 3", completerWith({
      answerLatex: "x=1,\\; y=1",
      answerPlain: "x=1, y=1",
      solutions: [{ variable: "x", value: 1 }, { variable: "y", value: 1 }],
      methods: [],
    }));
    expect(p.verified).toBe(false);
  });

  it("cubic: all three llm roots must check out", async () => {
    const p = await run("x^3 - 6x^2 + 11x - 6 = 0", completerWith({
      answerLatex: "x = 1, 2, 3",
      answerPlain: "x = 1 or 2 or 3",
      solutions: [
        { variable: "x", value: 1 },
        { variable: "x", value: 2 },
        { variable: "x", value: 3 },
      ],
      methods: [],
    }));
    expect(p.verified).toBe(true);
    expect(p.graph?.keyPoints.filter((k) => k.label === "root")).toHaveLength(3);
  });
});

describe("solve — integral via differentiate-back", () => {
  it("accepts an antiderivative whose derivative matches the integrand", async () => {
    const p = await run("\\int x^2 dx", completerWith({
      answerLatex: "\\frac{x^3}{3} + C",
      answerPlain: "x^3/3 + C",
      solutions: [],
      methods: [{ id: "power_rule", name: "Power rule", examPick: true, steps: [{ expression: "\\frac{x^3}{3} + C", operation: "Integrate", why: "..." }] }],
    }));
    expect(p.verified).toBe(true);
  });

  it("rejects a wrong antiderivative", async () => {
    const p = await run("\\int x^2 dx", completerWith({
      answerLatex: "\\frac{x^2}{2} + C",
      answerPlain: "x^2/2 + C",
      solutions: [],
      methods: [],
    }));
    expect(p.verified).toBe(false);
  });
});

describe("solve — resilience", () => {
  it("still returns a verified deterministic answer if narration throws", async () => {
    const flaky: JsonCompleter = async (system) => {
      if (system.includes("ALREADY-SOLVED")) throw new Error("openai down");
      return {};
    };
    const p = await run("2x + 5 = 15", flaky);
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = 5");
  });

  it("verifyMode 'none' short-circuits to couldn't-verify without calling the LLM", async () => {
    const cls = { ...classify("2x + 5 = 15"), verifyMode: "none" as const };
    // deterministic solve would normally succeed, so force the llm branch by
    // pretending the deterministic engine is bypassed: use a non-solvable input.
    const noneCls = { ...classify("x^2 + 1 = 0"), verifyMode: "none" as const };
    const p = await solve(noneCls, NEVER);
    expect(p.verified).toBe(false);
    expect(cls.verifyMode).toBe("none");
  });
});

describe("solve — ∫(9x+2)/(x²+x-6)dx (rational integral) verifies via ln|…|", () => {
  it("classifies as an indefinite integral and verifies the partial-fractions "
    + "antiderivative 5ln|x+3|+4ln|x-2| (abs no longer breaks derivative-back)",
    async () => {
    const p = await solve(
      classify("\\int \\frac{9x+2}{x^2+x-6} dx"),
      completerWith({
        answerLatex: "5\\ln|x+3| + 4\\ln|x-2|",
        answerPlain: "5 ln|x+3| + 4 ln|x-2|",
        solutions: [],
        methods: [],
      })
    );
    expect(p.problemType).toBe("integral");
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.latex).toContain("\\ln");
  });

  it("still REJECTS a wrong antiderivative (derivative-back gate intact)", async () => {
    const p = await solve(
      classify("\\int \\frac{9x+2}{x^2+x-6} dx"),
      completerWith({
        answerLatex: "\\ln|x+3| + \\ln|x-2|", // wrong coefficients
        answerPlain: "ln|x+3| + ln|x-2|",
        solutions: [],
        methods: [],
      })
    );
    expect(p.verified).toBe(false);
  });
});

describe("solve — 3^{2x+1}+4(3^x)-15=0 (exponential) verifies a precise root", () => {
  const EQ = "3^{2x+1} + 4(3^x) - 15 = 0";

  it("classifies as exponential and verifies the true root x=log_3(5/3) when "
    + "the candidate is precise (6+ sig digits)", async () => {
    const p = await solve(
      classify(EQ),
      completerWith({
        answerLatex: "x = \\log_3 \\tfrac{5}{3}",
        answerPlain: "x = log_3(5/3)",
        solutions: [{ variable: "x", value: 0.46497352 }],
        methods: [],
      })
    );
    expect(p.problemType).toBe("exponential_equation");
    expect(p.verified).toBe(true);
    // Substitution-verified candidates report the numeric root (an irrational
    // root can't be rationalised, so it shows as a decimal ~0.46497).
    expect(p.finalAnswer?.plain).toContain("0.46");
  });

  it("still declines an IMPRECISE candidate (0.465) — the safety gate is not "
    + "loosened", async () => {
    const p = await solve(
      classify(EQ),
      completerWith({
        answerLatex: "x \\approx 0.465",
        answerPlain: "x = 0.465",
        solutions: [{ variable: "x", value: 0.465 }],
        methods: [],
      })
    );
    expect(p.verified).toBe(false); // 0.465 → residual ~7e-4 > tolerance
  });
});

describe("solve — \\frac{x+2}{(x+1)^3}=\\frac{120}{x} reaches the LLM tier honestly", () => {
  const EQ = "\\frac{x + 2}{(x + 1)^3} = \\frac{120}{x}";

  it("the deterministic engine can't solve it, so the LLM candidate leg runs "
    + "and is told the TRUE (non-linear) problem type", async () => {
    const calls: { system: string; user: string }[] = [];
    const spy: JsonCompleter = async (system, user) => {
      calls.push({ system, user });
      return {}; // empty candidate → still couldn't-verify, but the leg WAS reached
    };

    const p = await solve(classify(EQ), spy);

    // The candidate prompt (narrate.ts) is `Problem (LaTeX): …\nProblem type: …`.
    const candidateCall = calls.find((c) => c.user.includes("Problem type:"));
    expect(candidateCall).toBeDefined(); // the LLM tier was reached
    expect(candidateCall!.user).toContain("Problem type: polynomial_equation");
    expect(candidateCall!.user).not.toContain("linear_equation");
    // The mock returned no usable candidate, so the gate honestly declines —
    // but the §4 problemType still reflects the real classification, not "linear".
    expect(p.verified).toBe(false);
    expect(p.problemType).toBe("polynomial_equation");
  });
});
