/**
 * Regression tests for the 9 defects the adversarial review confirmed.
 * Each asserts the FIXED behavior; a regression would flip these red.
 */
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { JsonCompleter } from "../src/solver/narrate";
import { verifyDerivative } from "../src/solver/verify";

const narrationOnly: JsonCompleter = async () => ({});
function candidate(obj: Record<string, unknown>): JsonCompleter {
  return async (system: string) => (system.includes("ALREADY-SOLVED") ? {} : obj);
}
const run = (latex: string, c: JsonCompleter = narrationOnly) =>
  solve(classify(latex), c);

describe("#1 \\log is base-10", () => {
  it("log(100) = 2, verified", async () => {
    const p = await run("\\log(100)");
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("2");
  });
  it("log(1000) = 3", async () => {
    expect((await run("\\log(1000)")).finalAnswer?.plain).toBe("3");
  });
});

describe("#2 \\ln maps to mathjs natural log", () => {
  it("d/dx ln(x) = 1/x, verified", async () => {
    const p = await run("\\frac{d}{dx}\\ln(x)");
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain.replace(/\s/g, "")).toBe("1/x");
  });
  it("ln(e) = 1, verified", async () => {
    const p = await run("\\ln(e)");
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("1");
  });
});

describe("#3 substitution-mode shows the VERIFIED answer, not the model's text", () => {
  it("a lying answerLatex is discarded for the verified roots", async () => {
    const p = await run(
      "x^3 - x = 0",
      candidate({
        answerLatex: "x = 42",
        answerPlain: "x = 42",
        solutions: [
          { variable: "x", value: 0 },
          { variable: "x", value: 1 },
          { variable: "x", value: -1 },
        ],
        methods: [],
      })
    );
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = -1 or x = 0 or x = 1"); // NOT "x = 42"
    expect(p.finalAnswer?.plain).not.toContain("42");
  });
});

describe("#5 incomplete polynomial roots are rejected", () => {
  it("cubic with only one of three roots → couldn't verify", async () => {
    const p = await run(
      "x^3 - 6x^2 + 11x - 6 = 0",
      candidate({
        answerLatex: "x = 1",
        answerPlain: "x = 1",
        solutions: [{ variable: "x", value: 1 }],
        methods: [],
      })
    );
    expect(p.verified).toBe(false);
    expect(p.finalAnswer).toBeNull();
  });
  it("cubic with all three roots → verified", async () => {
    const p = await run(
      "x^3 - 6x^2 + 11x - 6 = 0",
      candidate({
        answerLatex: "roots",
        answerPlain: "roots",
        solutions: [
          { variable: "x", value: 1 },
          { variable: "x", value: 2 },
          { variable: "x", value: 3 },
        ],
        methods: [],
      })
    );
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = 1 or x = 2 or x = 3");
  });
  it("a double root (one distinct value) is NOT over-rejected", async () => {
    const p = await run(
      "x^2 - 2x + 1 = 0",
      candidate({
        answerLatex: "x = 1",
        answerPlain: "x = 1",
        solutions: [{ variable: "x", value: 1 }],
        methods: [],
      })
    );
    expect(p.verified).toBe(true);
  });
});

describe("#4 verifyDerivative tolerates free parameters (no crash)", () => {
  it("d/dx(a x^2) verifies to 2ax instead of throwing", async () => {
    const p = await run("d/dx(a x^2)");
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain.replace(/\s/g, "")).toBe("2*a*x".replace(/\s/g, ""));
  });
  it("verifyDerivative returns false (not throw) on an unrelated symbol mismatch", () => {
    expect(verifyDerivative("a*x^2", "3*a*x", "x")).toBe(false);
    expect(verifyDerivative("a*x^2", "2*a*x", "x")).toBe(true);
  });
});

describe("#6 verifyEquality handles restricted domains", () => {
  it("sqrt(x-4) verifies (only defined for x>4)", async () => {
    const p = await run("\\sqrt{x-4}");
    expect(p.verified).toBe(true);
  });
  it("sqrt(x-4)+sqrt(x-4) simplifies and verifies", async () => {
    const p = await run("\\sqrt{x-4}+\\sqrt{x-4}");
    expect(p.verified).toBe(true);
  });
});

describe("#7 derivative with a leading coefficient is not silently halved", () => {
  it("2 d/dx(x^2) does not return a confident 2x", async () => {
    const p = await run("2\\frac{d}{dx}(x^2)");
    expect(p.verified).toBe(false);
    expect(p.finalAnswer).toBeNull();
  });
});

describe("#8 mixed numbers", () => {
  it("2 1/2 + 1 = 7/2 (3.5), not 2", async () => {
    const p = await run("2\\frac{1}{2} + 1");
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("7/2");
  });
  it("a coefficient times a variable fraction stays implicit multiply", async () => {
    // 2·(x/3) — must NOT become the mixed number 2 + x/3
    const p = await run("2\\frac{x}{3}");
    expect(p.verified).toBe(true); // 2x/3 ≡ 2·x/3
  });
});

describe("#8b mixed number keeps precedence in context (round-2 fix)", () => {
  it("2½x = 5 solves to x = 2, not x = 6", async () => {
    const p = await run("2\\frac{1}{2}x = 5");
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = 2");
  });
  it("2½ · 4 = 10", async () => {
    expect((await run("2\\frac{1}{2} \\cdot 4")).finalAnswer?.plain).toBe("10");
  });
  it("5 − 2½ = 5/2", async () => {
    expect((await run("5 - 2\\frac{1}{2}")).finalAnswer?.plain).toBe("5/2");
  });
});

describe("Keyboard §6 — nested structures round-trip to solve()", () => {
  it("a fraction with an exponent inside now verifies (was mangled)", async () => {
    const p = await run(String.raw`\frac{x^{2}}{3}`);
    expect(p.verified).toBe(true);
  });
  it("a fraction inside an exponent verifies", async () => {
    const p = await run(String.raw`x^{\frac{2}{3}}`);
    expect(p.verified).toBe(true);
  });
  it("derivative of a structured operand verifies to 2x", async () => {
    const p = await run(String.raw`\frac{d}{dx}(x^{2})`);
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain.replace(/\s/g, "")).toBe("2*x");
  });
});

describe("Gap A — definite integrals verify by numeric integration", () => {
  it("∫₀² x² dx accepts the correct value 8/3 (numeric integration agrees)", async () => {
    const p = await run(
      "\\int_{0}^{2} x^2 \\, dx",
      candidate({
        answerLatex: "\\frac{8}{3}",
        answerPlain: "8/3",
        solutions: [],
        methods: [{ id: "power_rule", name: "Power rule", examPick: true, steps: [{ expression: "\\frac{8}{3}", operation: "Integrate", why: "..." }] }],
      })
    );
    expect(p.problemType).toBe("definite_integral");
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("8/3");
  });
  it("rejects a wrong definite-integral value", async () => {
    const p = await run(
      "\\int_{0}^{2} x^2 \\, dx",
      candidate({ answerLatex: "3", answerPlain: "3", solutions: [], methods: [] })
    );
    expect(p.verified).toBe(false);
  });
});

describe("Gap B — trig equations verify principal solutions + periodicity", () => {
  it("sin(x)=1/2 accepts principal radians and shows a general form", async () => {
    const p = await run(
      "\\sin(x) = \\frac{1}{2}",
      candidate({
        answerLatex: "x = \\frac{\\pi}{6} + 2k\\pi",
        answerPlain: "general",
        solutions: [
          { variable: "x", value: Math.PI / 6 },
          { variable: "x", value: (5 * Math.PI) / 6 },
        ],
        methods: [{ id: "unit_circle", name: "Unit circle", examPick: true, steps: [{ expression: "x = \\frac{\\pi}{6}", operation: "Solve", why: "..." }] }],
      })
    );
    expect(p.verified).toBe(true);
    // Built from OUR verified values, prettified to exact radians + 2πn.
    expect(p.finalAnswer?.latex).toContain("\\frac{\\pi}{6}");
    expect(p.finalAnswer?.latex).toContain("\\frac{5\\pi}{6}");
    expect(p.finalAnswer?.latex).toContain("2\\pi n");
  });
  it("rejects a principal value that doesn't actually satisfy the equation", async () => {
    const p = await run(
      "\\sin(x) = \\frac{1}{2}",
      candidate({
        answerLatex: "x = 1",
        answerPlain: "x = 1",
        solutions: [{ variable: "x", value: 1 }], // sin(1) ≠ 0.5
        methods: [],
      })
    );
    expect(p.verified).toBe(false);
  });
});

describe("#A completeness gate skips rational equations (round-2 fix)", () => {
  it("(x^3-x)/(x-5)=0 accepts the correct 3 roots (asymptote is not a root)", async () => {
    const p = await run(
      "\\frac{x^3-x}{x-5}=0",
      candidate({
        answerLatex: "roots",
        answerPlain: "roots",
        solutions: [
          { variable: "x", value: -1 },
          { variable: "x", value: 0 },
          { variable: "x", value: 1 },
        ],
        methods: [],
      })
    );
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = -1 or x = 0 or x = 1");
  });
});
