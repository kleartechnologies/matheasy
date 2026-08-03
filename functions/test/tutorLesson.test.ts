import { describe, expect, it } from "vitest";

import {
  isTrueNumericIdentity,
  lessonDirective,
  lessonShape,
  resolveEquation,
  verifyTutorLesson,
  type LessonContext,
} from "../src/proxy/tutorLesson";
import { TUTOR_MODES } from "../src/proxy/tutorMode";

const PROBLEM = "16x = 9";
const STEP = "x = \\frac{9}{16}";
const ANSWER = "x = \\frac{9}{16}";

/** The context a Show Full Solution turn on a verified problem would build. */
function ctx(over: Partial<LessonContext> = {}): LessonContext {
  return {
    allowed: [PROBLEM, STEP],
    answer: ANSWER,
    shape: lessonShape("showSolution")!,
    ...over,
  };
}

const FULL = {
  goal: "Get x on its own.",
  steps: [
    { title: "Undo the multiplication", explanation: "Divide both sides by 16.", equation: STEP },
  ],
  concept: "Whatever you do to one side you do to the other.",
  commonMistake: "Dividing only the left side.",
  finalAnswer: ANSWER,
};

describe("lessonShape — the mode contract, expressed as cards", () => {
  it("gives every mode a shape or an explicit refusal", () => {
    for (const mode of TUTOR_MODES) {
      expect(() => lessonShape(mode)).not.toThrow();
      expect(lessonDirective(mode)).toBeTruthy();
    }
  });

  // Structure must not smuggle a solution into a mode that promised not to give
  // one. These three are the contract, not styling.
  it("gives a hint no steps and no answer", () => {
    expect(lessonShape("hint")).toEqual({
      maxSteps: 0,
      mayShowAnswer: false,
      allowIdentity: false,
    });
  });

  it("gives Solve Together exactly one step and no answer card", () => {
    const shape = lessonShape("solveTogether")!;
    expect(shape.maxSteps).toBe(1);
    expect(shape.mayShowAnswer).toBe(false);
  });

  it("gives Quiz Me no lesson at all", () => {
    expect(lessonShape("quizMe")).toBeNull();
  });
});

describe("verifyTutorLesson — the shape of a lesson", () => {
  it("accepts a complete, verified lesson unchanged", () => {
    const { lesson, reason } = verifyTutorLesson(FULL, ctx());
    expect(reason).toBe("");
    expect(lesson).toEqual(FULL);
  });

  it("returns null for a turn that sent no lesson", () => {
    expect(verifyTutorLesson(null, ctx()).lesson).toBeNull();
    expect(verifyTutorLesson("teach me", ctx()).lesson).toBeNull();
  });

  it("drops a lesson with no goal — a page of cards needs a heading", () => {
    const { lesson, reason } = verifyTutorLesson({ ...FULL, goal: "  " }, ctx());
    expect(lesson).toBeNull();
    expect(reason).toMatch(/missing goal/);
  });

  // A single card that says less than the sentence above it is worse than no
  // card at all.
  it("drops a lesson that is nothing but a goal", () => {
    const { lesson, reason } = verifyTutorLesson({ goal: "Solve for x." }, ctx());
    expect(lesson).toBeNull();
    expect(reason).toMatch(/nothing to render/);
  });

  it("keeps a framing-only lesson when it carries the idea or the trap", () => {
    const { lesson } = verifyTutorLesson(
      { goal: "Isolate x.", commonMistake: "Forgetting to divide the right side too." },
      ctx({ shape: lessonShape("hint")! })
    );
    expect(lesson?.steps).toEqual([]);
    expect(lesson?.commonMistake).toBe("Forgetting to divide the right side too.");
  });

  it("enforces the mode's step cap", () => {
    const many = {
      ...FULL,
      steps: [
        { title: "One", explanation: "a", equation: PROBLEM },
        { title: "Two", explanation: "b", equation: STEP },
      ],
      finalAnswer: "",
    };
    const { lesson, reason } = verifyTutorLesson(many, ctx({ shape: lessonShape("solveTogether")! }));
    expect(lesson?.steps).toHaveLength(1);
    expect(lesson?.steps[0].title).toBe("One");
    expect(reason).toMatch(/over the mode's cap/);
  });

  it("skips a card with neither a heading nor a sentence", () => {
    const { lesson } = verifyTutorLesson(
      { ...FULL, steps: [{ equation: STEP }, FULL.steps[0]] },
      ctx()
    );
    expect(lesson?.steps).toHaveLength(1);
  });

  it("titles a card from its own sentence when the model gave no heading", () => {
    const { lesson } = verifyTutorLesson(
      { ...FULL, steps: [{ explanation: "Divide both sides by 16." }] },
      ctx()
    );
    expect(lesson?.steps[0].title).toBe("Divide both sides by 16.");
  });

  it("omits empty optional cards rather than rendering blank boxes", () => {
    const { lesson } = verifyTutorLesson(
      { ...FULL, concept: "   ", commonMistake: "" },
      ctx()
    );
    expect(lesson).not.toHaveProperty("concept");
    expect(lesson).not.toHaveProperty("commonMistake");
  });
});

// ---------------------------------------------------------------------------
// The golden rule. A card is read as maths the app CHECKED.
// ---------------------------------------------------------------------------

describe("verifyTutorLesson — the equation on a step card", () => {
  it("renders the app's copy of the equation, not the model's characters", () => {
    const { lesson } = verifyTutorLesson(
      { ...FULL, steps: [{ title: "t", explanation: "e", equation: "x=\\frac{9}{16}" }] },
      ctx()
    );
    expect(lesson?.steps[0].equation).toBe(STEP);
  });

  it("drops an equation the app never verified, and keeps the words", () => {
    const { lesson, reason } = verifyTutorLesson(
      { ...FULL, steps: [{ title: "t", explanation: "e", equation: "x = \\frac{9}{15}" }] },
      ctx()
    );
    expect(lesson?.steps[0]).toEqual({ title: "t", explanation: "e" });
    expect(reason).toMatch(/not verified maths/);
  });

  it("drops a line the model rearranged for itself", () => {
    const { lesson } = verifyTutorLesson(
      { ...FULL, steps: [{ title: "t", explanation: "e", equation: "9 = 16x" }] },
      ctx()
    );
    expect(lesson?.steps[0].equation).toBeUndefined();
  });

  // A lone expression under a step heading reads exactly like an answer.
  it("drops a bare expression that asserts nothing", () => {
    const { lesson } = verifyTutorLesson(
      { ...FULL, steps: [{ title: "t", explanation: "e", equation: "\\frac{9}{16}" }] },
      ctx()
    );
    expect(lesson?.steps[0].equation).toBeUndefined();
  });

  it("accepts a closed arithmetic fact the model wrote itself", () => {
    const { lesson } = verifyTutorLesson(
      { ...FULL, steps: [{ title: "Rewrite 9", explanation: "e", equation: "9 = 3^2" }] },
      ctx()
    );
    expect(lesson?.steps[0].equation).toBe("9 = 3^2");
  });

  it("rejects a closed arithmetic fact that is simply false", () => {
    const { lesson } = verifyTutorLesson(
      { ...FULL, steps: [{ title: "t", explanation: "e", equation: "9 = 3^3" }] },
      ctx()
    );
    expect(lesson?.steps[0].equation).toBeUndefined();
  });

  it("rejects an invented claim about an unknown even when it is true", () => {
    // True of the real solution — and still not something the model may assert,
    // because nothing checked it before it reached the card.
    const { lesson } = verifyTutorLesson(
      { ...FULL, steps: [{ title: "t", explanation: "e", equation: "32x = 18" }] },
      ctx()
    );
    expect(lesson?.steps[0].equation).toBeUndefined();
  });

  it("refuses the model's own arithmetic in a mode not cleared for it", () => {
    const { lesson } = verifyTutorLesson(
      {
        goal: "Notice what is attached to x.",
        steps: [{ title: "t", explanation: "e", equation: "9 = 3^2" }],
        commonMistake: "Adding instead of dividing.",
      },
      ctx({ shape: lessonShape("hint")! })
    );
    expect(lesson?.steps).toEqual([]);
  });
});

describe("isTrueNumericIdentity", () => {
  it.each([
    ["9 = 3^2", true],
    ["\\frac{1}{2} = 0.5", true],
    ["12 \\times 4 = 48", true],
    ["9 = 3^3", false],
    ["2x = 6", false],
    ["x = 3", false],
    ["\\frac{9}{16}", false],
    ["", false],
    ["= = =", false],
  ])("%s → %s", (latex, expected) => {
    expect(isTrueNumericIdentity(latex)).toBe(expected);
  });
});

describe("resolveEquation", () => {
  it("matches the allow-list whitespace-insensitively", () => {
    expect(resolveEquation("16x=9", [PROBLEM], false)).toBe(PROBLEM);
  });

  it("returns null for an empty claim", () => {
    expect(resolveEquation("", [PROBLEM], true)).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// The answer firewall, extended to the answer CARD.
// ---------------------------------------------------------------------------

describe("verifyTutorLesson — the final-answer card", () => {
  it("renders the app's verified answer, never the model's", () => {
    const { lesson, reason } = verifyTutorLesson(
      { ...FULL, finalAnswer: "x = 0.5" },
      ctx()
    );
    expect(lesson?.finalAnswer).toBe(ANSWER);
    expect(reason).toMatch(/differed from the verified one/);
  });

  it("withholds the card entirely in a mode that may not reveal the answer", () => {
    const { lesson, reason } = verifyTutorLesson(
      FULL,
      ctx({ shape: lessonShape("solveTogether")!, allowed: [PROBLEM] })
    );
    expect(lesson?.finalAnswer).toBeUndefined();
    expect(reason).toMatch(/withheld in this mode/);
  });

  it("withholds the card when the app has no verified answer to substitute", () => {
    const { lesson } = verifyTutorLesson(FULL, ctx({ answer: "" }));
    expect(lesson?.finalAnswer).toBeUndefined();
  });

  it("shows no answer card when the lesson did not ask for one", () => {
    const { lesson, reason } = verifyTutorLesson({ ...FULL, finalAnswer: "" }, ctx());
    expect(lesson?.finalAnswer).toBeUndefined();
    expect(reason).toBe("");
  });
});
