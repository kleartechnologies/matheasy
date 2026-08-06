/**
 * `sanitizeHints` — the answer-leak screen on AI-generated practice hints.
 *
 * Pure function, no I/O, no mocks (house rule). A hint that survives must be
 * safe to show BEFORE the student answers: well-formed, capped at 2, and never
 * containing the question's correct answer in the normalized form the client's
 * answer matcher uses.
 */
import { describe, expect, it } from "vitest";

import { sanitizeHints } from "../src/proxy/practice";

type Question = Parameters<typeof sanitizeHints>[0];

function typed(overrides: Partial<Question> = {}): Question {
  return {
    prompt: "Solve for x",
    promptLatex: "2x + 5 = 13",
    type: "equation",
    acceptedAnswers: ["4", "x=4"],
    explanation: "Subtract 5, divide by 2.",
    ...overrides,
  };
}

describe("sanitizeHints", () => {
  it("keeps well-formed, non-leaking hints", () => {
    const q = typed({
      hints: ["Look at what happens to x.", "Undo the +5 first, then the ×2."],
    });
    expect(sanitizeHints(q)).toEqual([
      "Look at what happens to x.",
      "Undo the +5 first, then the ×2.",
    ]);
  });

  it("drops a hint containing the typed answer", () => {
    const q = typed({
      hints: ["Look at what happens to x.", "The value you need is 4."],
    });
    expect(sanitizeHints(q)).toEqual(["Look at what happens to x."]);
  });

  it("normalizes 'x=4' answers the way the client matcher does", () => {
    const q = typed({
      acceptedAnswers: ["x = 4"],
      hints: ["You should get x = 4 here."],
    });
    expect(sanitizeHints(q)).toEqual([]);
  });

  it("matches numeric answers on digit boundaries only", () => {
    // Answer "3" must not falsely flag a hint quoting the GIVEN "13".
    const q = typed({
      acceptedAnswers: ["3"],
      hints: ["Subtract the 13 on the right first.", "Then you get 3."],
    });
    expect(sanitizeHints(q)).toEqual(["Subtract the 13 on the right first."]);
  });

  it("screens against the correct multiple-choice option", () => {
    const q = typed({
      type: "multipleChoice",
      acceptedAnswers: undefined,
      options: [
        { text: "2x", isCorrect: true },
        { text: "x", isCorrect: false },
        { text: "x^2", isCorrect: false },
        { text: "2", isCorrect: false },
      ],
      hints: ["Use the power rule.", "Bring the power down: you get 2x."],
    });
    expect(sanitizeHints(q)).toEqual(["Use the power rule."]);
  });

  it("drops non-strings and blanks, then caps at two usable hints", () => {
    const q = typed({
      hints: [
        "  ",
        "First real hint.",
        "Second real hint.",
        "Third hint never ships.",
      ],
    });
    expect(sanitizeHints(q)).toEqual([
      "First real hint.",
      "Second real hint.",
    ]);
  });

  it("returns empty when hints are missing or malformed", () => {
    expect(sanitizeHints(typed({ hints: undefined }))).toEqual([]);
    expect(
      sanitizeHints(typed({ hints: 42 as unknown as string[] }))
    ).toEqual([]);
  });
});
