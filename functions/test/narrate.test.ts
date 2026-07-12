import { describe, expect, it } from "vitest";
import {
  assembleMethods,
  generateLlmCandidate,
  humanizeOperation,
} from "../src/solver/narrate";
import { classify } from "../src/solver/classify";
import { RawMethod } from "../src/solver/types";

describe("humanizeOperation", () => {
  it("maps known mathsteps codes to friendly labels", () => {
    expect(humanizeOperation("SUBTRACT_FROM_BOTH_SIDES")).toBe(
      "Subtract from both sides"
    );
    expect(humanizeOperation("FIND_ROOTS")).toBe("Find the roots");
  });
  it("falls back to a title-cased code", () => {
    expect(humanizeOperation("SOME_UNKNOWN_CODE")).toBe("Some unknown code");
  });
});

describe("assembleMethods", () => {
  const raw: RawMethod[] = [
    {
      id: "isolation",
      name: "Isolate",
      examPick: true,
      steps: [
        { ascii: "2x = 10", operationCode: "SUBTRACT_FROM_BOTH_SIDES" },
        { ascii: "x = 5", operationCode: "SIMPLIFY_FRACTION", latex: "x = 5" },
      ],
    },
  ];

  it("uses narration when present, keyed by method id + step index", () => {
    const methods = assembleMethods(raw, {
      isolation: {
        id: "isolation",
        steps: [
          { operation: "Move the 5", why: "Subtract 5 from both sides." },
          { operation: "Divide by 2", why: "Isolate x." },
        ],
      },
    });
    expect(methods[0].steps[0].operation).toBe("Move the 5");
    expect(methods[0].steps[0].why).toBe("Subtract 5 from both sides.");
    // step with a `latex` override is used verbatim
    expect(methods[0].steps[1].expression).toBe("x = 5");
  });

  it("falls back to humanized labels + empty why when narration is null", () => {
    const methods = assembleMethods(raw, null);
    expect(methods[0].steps[0].operation).toBe("Subtract from both sides");
    expect(methods[0].steps[0].why).toBe("");
  });
});

describe("generateLlmCandidate", () => {
  it("coerces a well-formed candidate and forces exactly one exam pick", async () => {
    const cls = classify("\\sin(x) = 0.5");
    const candidate = await generateLlmCandidate(
      async () => ({
        answerLatex: "x = \\frac{\\pi}{6}",
        answerPlain: "x = pi/6",
        solutions: [{ variable: "x", value: 0.5236 }],
        methods: [
          { id: "a", name: "A", steps: [{ expression: "x=1", operation: "o", why: "w" }] },
          { id: "b", name: "B", steps: [{ expression: "x=2", operation: "o", why: "w" }] },
        ],
      }),
      cls
    );
    expect(candidate).not.toBeNull();
    expect(candidate!.assignments).toEqual([{ variable: "x", value: 0.5236 }]);
    expect(candidate!.methods.filter((m) => m.examPick)).toHaveLength(1);
  });

  it("drops non-numeric solution values and empty steps", async () => {
    const cls = classify("\\sin(x) = 0.5");
    const candidate = await generateLlmCandidate(
      async () => ({
        answerLatex: "x = 1",
        solutions: [{ variable: "x", value: "not a number" }],
        methods: [{ id: "a", name: "A", steps: [] }],
      }),
      cls
    );
    expect(candidate!.assignments).toEqual([]);
    expect(candidate!.methods).toEqual([]);
  });

  it("returns null when the model omits an answer", async () => {
    const cls = classify("\\sin(x) = 0.5");
    expect(await generateLlmCandidate(async () => ({}), cls)).toBeNull();
  });
});
