// Word problems — the LLM EXTRACTS an equation and solves it; the gate confirms
// the answer satisfies that extracted equation (arithmetic verified). The
// reading itself can't be verified, so the interpretation is shown to the user.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const comp = (c: Record<string, unknown>): JsonCompleter => async (s) =>
  s.includes("ALREADY-SOLVED") ? {} : c;

describe("classify — word problems (conservative prose detection)", () => {
  it("detects a narrative with numbers", () => {
    expect(classify("John has 3 apples and buys 5 more, how many total?").problemType).toBe("word_problem");
    expect(classify("A train travels 60 km in 2 hours, what is its speed?").problemType).toBe("word_problem");
  });
  it("does NOT misfire on a bare directive or structured math", () => {
    expect(classify("solve for the value of x").problemType).not.toBe("word_problem");
    expect(classify("2x + 3 = 15").problemType).toBe("linear_equation");
    expect(classify("mean of 2, 4, 6").problemType).toBe("statistics");
    expect(classify("find x").problemType).not.toBe("word_problem"); // no digit, too few words
  });
});

describe("solve — word problems", () => {
  it("verifies the answer against the model's extracted equation", async () => {
    const p = await solve(classify("John has 3 apples and buys 5 more, how many total?"),
      comp({ setupLatex: "x = 3 + 5", answerLatex: "8 \\text{ apples}", answerPlain: "8 apples",
        solutions: [{ variable: "x", value: 8 }], methods: [] }));
    expect(p.problemType).toBe("word_problem");
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("8 apples");
  });

  it("REJECTS an arithmetic slip (setup x=3+5 but answer 7)", async () => {
    const p = await solve(classify("John has 3 apples and buys 5 more, how many total?"),
      comp({ setupLatex: "x = 3 + 5", answerLatex: "7", answerPlain: "7",
        solutions: [{ variable: "x", value: 7 }], methods: [] }));
    expect(p.verified).toBe(false);
  });

  it("verifies a two-step setup (2x+5=17 → x=6)", async () => {
    const p = await solve(classify("A number doubled plus 5 equals 17. Find the number."),
      comp({ setupLatex: "2x + 5 = 17", answerLatex: "x = 6", answerPlain: "6",
        solutions: [{ variable: "x", value: 6 }], methods: [] }));
    expect(p.verified).toBe(true);
  });
});
