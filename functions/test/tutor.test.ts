import { describe, expect, it } from "vitest";

import {
  optionValue,
  verifyPracticeCard,
  verifyQuizCard,
  verifyTutorCard,
} from "../src/proxy/tutorCard";
import {
  DEFAULT_TUTOR_MODE,
  modeAwaitsStudent,
  modeDirective,
  modeMaySeeAnswer,
  normalizeHelpLevel,
  normalizeMode,
  TUTOR_MODES,
} from "../src/proxy/tutorMode";
import {
  buildMemoryContext,
  buildProblemContext,
  defaultSuggestions,
  openingScanImage,
  parseMeta,
  parseSuggestions,
} from "../src/proxy/tutor";

const QUIZ = {
  kind: "quiz" as const,
  prompt: "Solve for x",
  promptLatex: "2x + 4 = 10",
  options: ["2", "3", "4", "5"],
  correctIndex: 1,
  explanation: "Subtract 4 then divide by 2.",
};

describe("tutor modes", () => {
  it("normalizes an unknown mode to Solve Together, not Show Solution", () => {
    // The default must keep teaching a student who never picked a mode.
    expect(normalizeMode(undefined)).toBe("solveTogether");
    expect(normalizeMode("nonsense")).toBe("solveTogether");
    expect(normalizeMode(42)).toBe("solveTogether");
    expect(DEFAULT_TUTOR_MODE).toBe("solveTogether");
  });

  it("keeps every real mode", () => {
    for (const mode of TUTOR_MODES) expect(normalizeMode(mode)).toBe(mode);
  });

  it("withholds the answer from the modes that must not reveal it", () => {
    expect(modeMaySeeAnswer("hint")).toBe(false);
    expect(modeMaySeeAnswer("quizMe")).toBe(false);
    expect(modeMaySeeAnswer("showSolution")).toBe(true);
    expect(modeMaySeeAnswer("teachMe")).toBe(true);
  });

  it("makes the interactive modes stop and wait for the student", () => {
    expect(modeAwaitsStudent("solveTogether")).toBe(true);
    expect(modeAwaitsStudent("quizMe")).toBe(true);
    expect(modeAwaitsStudent("showSolution")).toBe(false);
  });

  it("clamps helpLevel into the escalation ladder", () => {
    expect(normalizeHelpLevel(-5)).toBe(0);
    expect(normalizeHelpLevel(2)).toBe(2);
    expect(normalizeHelpLevel(99)).toBe(3);
    expect(normalizeHelpLevel("3")).toBe(0);
  });

  it("escalates help without repeating the same explanation", () => {
    expect(modeDirective("solveTogether", 0)).not.toMatch(/ESCALATION/);
    expect(modeDirective("solveTogether", 2)).toMatch(/Do NOT re-explain the same way/i);
    // At the top of the ladder Numi stops asking and just unsticks them.
    expect(modeDirective("teachMe", 3)).toMatch(/Show the next concrete step/i);
  });

  it("forbids the hint mode from revealing the answer even on request", () => {
    const hint = modeDirective("hint", 0);
    expect(hint).toMatch(/must NOT state the final answer/);
    expect(hint).toMatch(/even if the student asks/i);
  });
});

describe("problem context — the answer firewall", () => {
  const problem = {
    questionLatex: "2x + 5 = 13",
    problemType: "Linear Equation",
    finalAnswer: "x = 4",
    verified: true,
    verifyText: "Substituting x = 4 gives 13 = 13.",
    steps: [
      { title: "Subtract 5", resultLatex: "2x = 8", detail: "Undo the + 5." },
      { title: "Divide by 2", resultLatex: "x = 4", rule: "division property" },
    ],
    commonMistakes: ["Forgetting to subtract from BOTH sides"],
  };

  it("gives the verified answer and steps when the mode may see them", () => {
    const ctx = buildProblemContext(problem, true);
    expect(ctx).toMatch(/VERIFIED final answer/);
    expect(ctx).toContain("x = 4");
    expect(ctx).toContain("2x = 8");
    expect(ctx).toMatch(/never contradict it/i);
  });

  it("strips the answer AND every step result in hint/quiz modes", () => {
    const ctx = buildProblemContext(problem, false);
    // Not merely "forbidden" — absent. A prompt injection has nothing to leak.
    expect(ctx).not.toContain("x = 4");
    expect(ctx).not.toContain("2x = 8");
    expect(ctx).not.toContain("13 = 13");
    expect(ctx).toMatch(/deliberately withheld/i);
    // The route itself survives, so hints can still aim at the right move.
    expect(ctx).toContain("Subtract 5");
  });

  it("marks an unverified answer as uncertain rather than authoritative", () => {
    const ctx = buildProblemContext({ ...problem, verified: false }, true);
    expect(ctx).toMatch(/NOT verified/);
    expect(ctx).not.toMatch(/VERIFIED final answer/);
  });

  it("caps runaway step lists", () => {
    const many = Array.from({ length: 40 }, (_, i) => ({
      title: `Step ${i}`,
      resultLatex: `x = ${i}`,
    }));
    const ctx = buildProblemContext({ steps: many }, true);
    expect(ctx).toContain("Step 13");
    expect(ctx).not.toContain("Step 14");
  });

  // ---- V5 practice coaching ----

  it("names the student's own answer for diagnosis, in every mode", () => {
    const withStudent = { ...problem, studentAnswer: "x = 9", attempts: 3 };
    const open = buildProblemContext(withStudent, true);
    expect(open).toMatch(/The student answered: x = 9/);
    expect(open).toMatch(/diagnose the likely mistake/i);
    expect(open).toMatch(/tried this question 3 times/);

    // Their OWN answer is not the withheld answer — the firewall keeps the
    // verified answer out while the diagnosis context stays.
    const withheld = buildProblemContext(withStudent, false);
    expect(withheld).toMatch(/The student answered: x = 9/);
    expect(withheld).not.toContain("x = 4");
  });

  it("tells Numi which hint rung to coach at, without repeating lower ones", () => {
    const ctx = buildProblemContext({ ...problem, hintLevel: 2 }, false);
    expect(ctx).toMatch(/hints up to level 2 of 4/);
    expect(ctx).toMatch(/Coach at the NEXT nudge/i);
  });

  it("ignores malformed practice-coach fields", () => {
    const ctx = buildProblemContext(
      {
        ...problem,
        studentAnswer: "",
        hintLevel: Number.NaN,
        attempts: -2,
      },
      true
    );
    expect(ctx).not.toMatch(/The student answered/);
    expect(ctx).not.toMatch(/hints up to level/);
    expect(ctx).not.toMatch(/tried this question/);
  });
});

describe("student memory", () => {
  it("tells Numi not to re-explain what it already covered", () => {
    const ctx = buildMemoryContext({ conceptsCovered: ["isolating x"] });
    expect(ctx).toMatch(/do NOT re-explain/i);
    expect(ctx).toContain("isolating x");
  });

  it("turns a detected learning style into a concrete instruction", () => {
    expect(buildMemoryContext({ style: "visual" })).toMatch(/picture in words/i);
    expect(buildMemoryContext({ style: "concise" })).toMatch(/Be brief/);
    expect(buildMemoryContext({ style: "bogus" })).toBe("");
  });

  it("is empty for a fresh student", () => {
    expect(buildMemoryContext({})).toBe("");
  });
});

describe("suggestions", () => {
  it("keeps only ids from the allowed vocabulary", () => {
    expect(parseSuggestions(["giveHint", "rm -rf /", "practiceHarder"])).toEqual([
      "giveHint",
      "practiceHarder",
    ]);
  });

  it("dedupes and caps at three chips", () => {
    expect(
      parseSuggestions(["giveHint", "giveHint", "tellMeWhy", "nextStep", "createQuiz"])
    ).toEqual(["giveHint", "tellMeWhy", "nextStep"]);
  });

  it("falls back to mode-appropriate chips", () => {
    // Hint mode must always offer the escape hatch to the full solution.
    expect(defaultSuggestions("hint")).toContain("showSolution");
    expect(defaultSuggestions("solveTogether")).toContain("nextStep");
  });
});

describe("meta", () => {
  it("defaults to a safe reading when the model omits it", () => {
    const meta = parseMeta(undefined);
    expect(meta.understanding).toBe("following");
    expect(meta.checkpoint).toBe(false);
    expect(meta.mistake).toBeNull();
    expect(meta.conceptsCovered).toEqual([]);
  });

  it("passes through the signals the client folds into memory", () => {
    const meta = parseMeta({
      conceptsCovered: ["balance method"],
      mistake: "flipped the sign moving 5 across",
      understanding: "struggling",
      checkpoint: true,
      style: "visual",
    });
    expect(meta).toEqual({
      conceptsCovered: ["balance method"],
      mistake: "flipped the sign moving 5 across",
      understanding: "struggling",
      checkpoint: true,
      style: "visual",
    });
  });

  it("rejects an out-of-vocabulary understanding value", () => {
    expect(parseMeta({ understanding: "vibing" }).understanding).toBe("following");
  });
});

describe("quiz card — the golden-rule gate", () => {
  it("accepts a quiz whose key actually solves the equation", () => {
    const { card } = verifyQuizCard(QUIZ);
    expect(card).toMatchObject({ kind: "quiz", correctIndex: 1 });
  });

  it("DROPS a quiz whose marked answer is wrong", () => {
    // The whole point: a confidently wrong answer key never reaches a student.
    const { card, reason } = verifyQuizCard({ ...QUIZ, correctIndex: 2 });
    expect(card).toBeNull();
    expect(reason).toMatch(/fails substitution/);
  });

  it("DROPS a quiz where a distractor also solves it", () => {
    const { card, reason } = verifyQuizCard({
      ...QUIZ,
      promptLatex: "x^2 = 9",
      options: ["3", "-3", "6", "9"],
      correctIndex: 0,
    });
    expect(card).toBeNull();
    expect(reason).toMatch(/distractor/);
  });

  it("DROPS a quiz it cannot check at all", () => {
    // Symbolic options and word prompts are unverifiable — unverified is a drop,
    // never a guess.
    expect(verifyQuizCard({ ...QUIZ, options: ["2x", "3", "4", "5"] }).card).toBeNull();
    expect(
      verifyQuizCard({ ...QUIZ, promptLatex: "What is a derivative?" }).card
    ).toBeNull();
    expect(
      verifyQuizCard({ ...QUIZ, promptLatex: "2x + 3y = 10" }).card
    ).toBeNull();
  });

  it("rejects malformed option sets", () => {
    expect(verifyQuizCard({ ...QUIZ, options: ["3"] }).card).toBeNull();
    expect(verifyQuizCard({ ...QUIZ, options: ["3", "3", "4", "5"] }).card).toBeNull();
    expect(verifyQuizCard({ ...QUIZ, correctIndex: 9 }).card).toBeNull();
    expect(verifyQuizCard({ ...QUIZ, explanation: "" }).card).toBeNull();
    expect(verifyQuizCard({ ...QUIZ, options: ["2", "", "4", "5"] }).card).toBeNull();
  });

  it("reads the option shapes a tutor actually writes", () => {
    expect(optionValue("x = 3")).toBe(3);
    expect(optionValue("-1/2")).toBeCloseTo(-0.5);
    expect(optionValue("\\frac{1}{2}")).toBeCloseTo(0.5);
    expect(optionValue("2x")).toBeNaN();
    expect(optionValue("")).toBeNaN();
  });

  it("verifies a fractional answer key", () => {
    const { card } = verifyQuizCard({
      ...QUIZ,
      promptLatex: "4x = 2",
      options: ["\\frac{1}{2}", "2", "4", "8"],
      correctIndex: 0,
    });
    expect(card).not.toBeNull();
  });
});

describe("practice card", () => {
  it("accepts a solvable equation and prices it by difficulty", () => {
    const { card } = verifyPracticeCard({
      kind: "practice",
      questionLatex: "3x + 6 = 18",
      difficulty: "easy",
      encouragement: "You've got this.",
    });
    expect(card).toMatchObject({ kind: "practice", difficulty: "easy", xpReward: 15 });
  });

  it("DROPS a question with no real solution", () => {
    const { card, reason } = verifyPracticeCard({
      kind: "practice",
      questionLatex: "x^2 = -4",
      difficulty: "hard",
      encouragement: "Try it.",
    });
    expect(card).toBeNull();
    expect(reason).toMatch(/no real solution/);
  });

  it("DROPS a prompt that isn't a well-formed single-unknown equation", () => {
    expect(
      verifyPracticeCard({
        kind: "practice",
        questionLatex: "Think about fractions",
        encouragement: "Go.",
      }).card
    ).toBeNull();
  });
});

describe("card routing", () => {
  it("ignores absent and unknown cards without throwing", () => {
    expect(verifyTutorCard(null).card).toBeNull();
    expect(verifyTutorCard(undefined).card).toBeNull();
    expect(verifyTutorCard("quiz").card).toBeNull();
    expect(verifyTutorCard({ kind: "diagram" }).card).toBeNull();
  });

  it("routes by kind", () => {
    expect(verifyTutorCard(QUIZ).card).toMatchObject({ kind: "quiz" });
  });
});

describe("problem context — how the page was read", () => {
  const BASE = {
    questionLatex: "2x + 4 = 10",
    finalAnswer: "x = 3",
    verified: true,
  };

  it("tells Numi the transcription and which marks were doubtful", () => {
    const context = buildProblemContext(
      { ...BASE, ocr: { latex: "2x + 4 = 1O", confidence: 0.94, uncertain: ["the 0 in 10"] } },
      true
    );
    expect(context).toContain("2x + 4 = 1O");
    expect(context).toContain("Transcription confidence: 0.94");
    expect(context).toContain("the 0 in 10");
  });

  it("says outright to believe the student when the read was shaky", () => {
    const context = buildProblemContext({ ...BASE, ocr: { confidence: 0.41 } }, true);
    expect(context).toContain("LOW (0.41)");
    expect(context).toMatch(/believe them/i);
  });

  it("keeps the read block in answer-withheld modes — it describes the QUESTION", () => {
    // The firewall hides the answer, not the transcription. A student disputing
    // "that's not my problem" deserves an honest reply in every mode.
    const context = buildProblemContext(
      { ...BASE, ocr: { latex: "2x + 4 = 1O", confidence: 0.41 } },
      false
    );
    expect(context).toContain("2x + 4 = 1O");
    expect(context).toContain("LOW (0.41)");
    expect(context).not.toContain("x = 3");
  });

  it("says nothing at all when the problem was typed, not scanned", () => {
    expect(buildProblemContext(BASE, true)).not.toMatch(/READ from a photo/);
    expect(buildProblemContext({ ...BASE, ocr: {} }, true)).not.toMatch(/READ from a photo/);
  });

  it("points 'give me another one' at practice the app already checked", () => {
    const context = buildProblemContext(
      { ...BASE, practice: ["3x + 1 = 7 (easy)", "5x - 2 = 13 (medium)"] },
      true
    );
    expect(context).toContain("1. 3x + 1 = 7 (easy)");
    expect(context).toContain("2. 5x - 2 = 13 (medium)");
    // Capped, so a long practice set can't crowd out the solve context.
    const many = buildProblemContext(
      { ...BASE, practice: Array.from({ length: 9 }, (_, i) => `q${i}`) },
      true
    );
    expect(many).toContain("5. q4");
    expect(many).not.toContain("6. q5");
  });
});

describe("the scan photo attached to a tutor turn", () => {
  const IMAGE = "AAAAAAAA";

  it("wraps raw base64 with the declared mime", () => {
    expect(openingScanImage({ imageBase64: IMAGE, mimeType: "image/png" }, [])).toBe(
      `data:image/png;base64,${IMAGE}`
    );
  });

  it("falls back to jpeg when the mime is missing or junk", () => {
    expect(openingScanImage({ imageBase64: IMAGE }, [])).toBe(
      `data:image/jpeg;base64,${IMAGE}`
    );
    expect(openingScanImage({ imageBase64: IMAGE, mimeType: "text/html" }, [])).toBe(
      `data:image/jpeg;base64,${IMAGE}`
    );
  });

  it("passes a well-formed data URI through and rejects a malformed one", () => {
    const uri = `data:image/jpeg;base64,${IMAGE}`;
    expect(openingScanImage({ imageBase64: uri }, [])).toBe(uri);
    expect(openingScanImage({ imageBase64: "data:text/html;base64,abc" }, [])).toBeNull();
    expect(openingScanImage({ imageBase64: "data:image/jpeg;base64," }, [])).toBeNull();
  });

  it("still attaches on the student's first message when Numi greeted first", () => {
    // The greeting is already in the transcript — keying off history LENGTH
    // would mean the photo is never sent at all.
    expect(
      openingScanImage({ imageBase64: IMAGE }, [{ role: "assistant", text: "Hi!" }])
    ).toBe(`data:image/jpeg;base64,${IMAGE}`);
  });

  it("drops it once the student has spoken — one upload per conversation", () => {
    expect(
      openingScanImage({ imageBase64: IMAGE }, [
        { role: "assistant", text: "Hi!" },
        { role: "user", text: "why?" },
        { role: "assistant", text: "because…" },
      ])
    ).toBeNull();
  });

  it("drops an absent or oversized image rather than failing the turn", () => {
    expect(openingScanImage({}, [])).toBeNull();
    expect(openingScanImage({ imageBase64: "   " }, [])).toBeNull();
    expect(openingScanImage({ imageBase64: "A".repeat(5_000_001) }, [])).toBeNull();
  });
});
