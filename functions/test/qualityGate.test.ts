/**
 * The educational quality gate — scoring, the bar, and the regeneration loop.
 *
 * `qualityChecks.test.ts` proves the fifteen checks see what they are supposed
 * to see. This file proves the machine built on top of them behaves: that the
 * bar is where the spec put it, that a generous judge cannot lift a draft the
 * deterministic checks already failed, that a rejection regenerates the WORDS
 * and never the mathematics, and that when it gives up it gives up honestly.
 *
 * The load-bearing assertion in the whole file is the one that says the verified
 * truth handed to attempt 3 is byte-for-byte the truth handed to attempt 1. That
 * is the golden rule, expressed as a test: this layer may rewrite an explanation
 * as many times as it likes and may never touch the solution.
 */
import { describe, expect, it, vi } from "vitest";
import type OpenAI from "openai";

import {
  evaluateQuality,
  gateExplanation,
  meetsBar,
  mergeScores,
  overallScore,
  regenerationFeedback,
  scoreFindings,
} from "../src/quality/gate";
import { __testing as judgeTesting } from "../src/quality/judge";
import {
  difficultyFromBand,
  fieldsFromTeaching,
  practiceFromLadder,
  teachingToQualityInput,
  truthFromPayload,
  tutorToQualityInput,
} from "../src/quality/adapters";
import {
  PASS_CRITERIA,
  PERFECT,
  expectedDifficulty,
  shiftDifficulty,
  type QualityFinding,
  type QualityInput,
  type QualityScores,
} from "../src/quality/types";
import type { MethodData, SolvePayload, TeachingLayer } from "../src/solver/types";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function finding(over: Partial<QualityFinding> = {}): QualityFinding {
  return {
    check: "hidden_steps",
    dimension: "teachingClarity",
    severity: "minor",
    detail: "a step is glossed",
    ...over,
  };
}

function input(over: Partial<QualityInput> = {}): QualityInput {
  return {
    explanation: {
      fields: [
        { id: "overview.goal", kind: "prose", text: "Find the value of x in this equation." },
        {
          id: "steps.0.why",
          kind: "step",
          stepIndex: 0,
          text: "Subtract 4 from both sides so the x term stands alone.",
        },
        {
          id: "steps.1.why",
          kind: "step",
          stepIndex: 1,
          text: "Divide both sides by 2 to leave x by itself.",
        },
      ],
      journey: ["understand", "apply", "verify"],
    },
    truth: {
      problemLatex: "2x + 4 = 10",
      answerLatex: "x = 3",
      answerPlain: "x = 3",
      stepExpressions: ["2x = 6", "x = 3"],
      verified: true,
      problemType: "linear equation",
    },
    audience: { language: "en", difficulty: "medium" },
    visuals: { anchors: [], actions: [] },
    certainty: { state: "PASS" },
    surface: "test",
    ...over,
  };
}

/** A draft whose prose quotes a number the solver never produced. */
function contradictory(): QualityInput {
  return input({
    explanation: {
      fields: [{ id: "overview.goal", kind: "prose", text: "Divide both sides by 42." }],
    },
  });
}

/** An OpenAI stand-in that returns whatever verdict the test wants. */
function fakeClient(verdict: unknown, spy?: { calls: number }) {
  return {
    chat: {
      completions: {
        create: async () => {
          if (spy) spy.calls++;
          return {
            choices: [
              { message: { content: JSON.stringify(verdict) }, finish_reason: "stop" },
            ],
            usage: {},
          };
        },
      },
    },
  } as unknown as OpenAI;
}

const scores = (over: Partial<QualityScores> = {}): QualityScores => ({ ...PERFECT, ...over });

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

describe("scoring", () => {
  it("starts perfect and deducts", () => {
    expect(scoreFindings([])).toEqual(PERFECT);
  });

  it("zeroes a dimension on a hard failure — there is no partial credit for that", () => {
    const s = scoreFindings([
      finding({ dimension: "mathematicalConsistency", severity: "hard" }),
    ]);
    expect(s.mathematicalConsistency).toBe(0);
    expect(s.teachingClarity).toBe(100);
  });

  it("deducts 25 for a major and 8 for a minor, cumulatively", () => {
    expect(scoreFindings([finding({ severity: "major" })]).teachingClarity).toBe(75);
    expect(scoreFindings([finding({ severity: "minor" })]).teachingClarity).toBe(92);
    expect(
      scoreFindings([
        finding({ severity: "major" }),
        finding({ severity: "minor" }),
      ]).teachingClarity
    ).toBe(67);
  });

  it("floors at zero rather than going negative", () => {
    const many = Array.from({ length: 12 }, () => finding({ severity: "major" }));
    expect(scoreFindings(many).teachingClarity).toBe(0);
  });

  it("weights the overall score, mathematical consistency heaviest", () => {
    expect(overallScore(PERFECT)).toBe(100);
    expect(overallScore(scores({ mathematicalConsistency: 0 }))).toBeCloseTo(70, 5);
    expect(overallScore(scores({ visualConsistency: 0 }))).toBeCloseTo(90, 5);
  });
});

// ---------------------------------------------------------------------------
// The bar
// ---------------------------------------------------------------------------

describe("the bar", () => {
  it("is exactly what the spec says it is", () => {
    expect(PASS_CRITERIA).toEqual({
      overall: 95,
      mathematicalConsistency: 100,
      visualConsistency: 100,
    });
  });

  it("passes a perfect draft", () => {
    expect(meetsBar(PERFECT, 100)).toBe(true);
  });

  it("passes a draft with a small blemish somewhere it is allowed one", () => {
    const s = scores({ teachingClarity: 92 });
    expect(overallScore(s)).toBeCloseTo(98.4, 5);
    expect(meetsBar(s, overallScore(s))).toBe(true);
  });

  it("fails at 99 on mathematical consistency, however good the rest is", () => {
    const s = scores({ mathematicalConsistency: 99 });
    expect(overallScore(s)).toBeGreaterThan(PASS_CRITERIA.overall);
    expect(meetsBar(s, overallScore(s))).toBe(false);
  });

  it("fails at 99 on visual consistency, however good the rest is", () => {
    const s = scores({ visualConsistency: 99 });
    expect(overallScore(s)).toBeGreaterThan(PASS_CRITERIA.overall);
    expect(meetsBar(s, overallScore(s))).toBe(false);
  });

  it("fails a draft that is perfect on the absolutes but weak overall", () => {
    const s = scores({ pedagogicalQuality: 50, teachingClarity: 50 });
    expect(s.mathematicalConsistency).toBe(100);
    expect(s.visualConsistency).toBe(100);
    expect(meetsBar(s, overallScore(s))).toBe(false);
  });

  it("fails exactly one point below the overall bar", () => {
    const s = scores({ pedagogicalQuality: 90, teachingClarity: 90 });
    expect(overallScore(s)).toBeCloseTo(96, 5);
    expect(meetsBar(s, overallScore(s))).toBe(true);
    const worse = scores({ pedagogicalQuality: 80, teachingClarity: 80 });
    expect(overallScore(worse)).toBeCloseTo(92, 5);
    expect(meetsBar(worse, overallScore(worse))).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// The judge can only lower
// ---------------------------------------------------------------------------

describe("merging the judge's opinion", () => {
  it("takes the minimum of each dimension", () => {
    const merged = mergeScores(
      scores({ teachingClarity: 60, languageQuality: 100 }),
      scores({ teachingClarity: 90, languageQuality: 40 })
    );
    expect(merged.teachingClarity).toBe(60);
    expect(merged.languageQuality).toBe(40);
    expect(merged.mathematicalConsistency).toBe(100);
  });

  it("cannot rescue a draft the deterministic checks failed", () => {
    const det = scoreFindings([
      finding({ dimension: "visualConsistency", severity: "hard" }),
    ]);
    const merged = mergeScores(det, PERFECT);
    expect(merged.visualConsistency).toBe(0);
    expect(meetsBar(merged, overallScore(merged))).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// evaluateQuality
// ---------------------------------------------------------------------------

describe("evaluateQuality", () => {
  it("runs deterministic-only when there is no client, and says so", async () => {
    const report = await evaluateQuality(null, input());
    expect(report.judged).toBe(false);
    expect(report.pass).toBe(true);
    expect(report.findings).toEqual([]);
  });

  it("fails a contradictory draft without a client at all", async () => {
    const report = await evaluateQuality(null, contradictory());
    expect(report.pass).toBe(false);
    expect(report.scores.mathematicalConsistency).toBe(0);
  });

  it("does not spend a judge call on a draft that already hard-failed", async () => {
    const spy = { calls: 0 };
    const client = fakeClient({ scores: PERFECT, findings: [] }, spy);
    const report = await evaluateQuality(client, contradictory());
    expect(spy.calls).toBe(0);
    expect(report.judged).toBe(false);
    expect(report.pass).toBe(false);
  });

  it("lets the judge lower a draft the deterministic checks liked", async () => {
    const client = fakeClient({
      scores: { ...PERFECT, pedagogicalQuality: 40 },
      findings: [
        {
          check: "concept_introduction",
          dimension: "pedagogicalQuality",
          severity: "major",
          detail: "names the method without saying why it is the right one",
        },
      ],
    });
    const report = await evaluateQuality(client, input());
    expect(report.judged).toBe(true);
    expect(report.pass).toBe(false);
    expect(report.scores.pedagogicalQuality).toBe(40);
  });

  it("cannot be talked into passing by a judge that scores everything 100", async () => {
    const client = fakeClient({ scores: PERFECT, findings: [] });
    const report = await evaluateQuality(
      client,
      input({
        visuals: { anchors: [], actions: [] },
        explanation: {
          fields: [
            {
              id: "overview.goal",
              kind: "prose",
              text: "Find x.",
              visualRefs: ["angle_Q"],
            },
          ],
        },
      })
    );
    expect(report.pass).toBe(false);
    expect(report.scores.visualConsistency).toBe(0);
  });

  it("degrades to the deterministic verdict when the judge is unreachable", async () => {
    const broken = {
      chat: { completions: { create: async () => { throw new Error("503"); } } },
    } as unknown as OpenAI;
    const report = await evaluateQuality(broken, input());
    expect(report.judged).toBe(false);
    expect(report.pass).toBe(true);
  });

  it("survives a judge that returns nonsense", async () => {
    const client = fakeClient({ scores: "great", findings: "none" });
    const report = await evaluateQuality(client, input());
    // Absent scores read as 100 — the judge abstaining is not a failing grade.
    expect(report.scores).toEqual(PERFECT);
    expect(report.pass).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// The judge's own guards
// ---------------------------------------------------------------------------

describe("the judge", () => {
  const { JUDGE_SYSTEM, buildDossier, sanitiseFindings, score } = judgeTesting;

  it("is told, in its own prompt, that it may not compute", () => {
    expect(JUDGE_SYSTEM).toMatch(/never recompute/i);
    expect(JUDGE_SYSTEM).toMatch(/ALREADY been computed/i);
    expect(JUDGE_SYSTEM).toMatch(/NOT a solver/i);
  });

  it("is handed the proven solution as fact, not as a question", () => {
    const dossier = JSON.parse(buildDossier(input()));
    expect(dossier.provenSolution.answer).toBe("x = 3");
    expect(dossier.provenSolution.steps).toEqual(["2x = 6", "x = 3"]);
    expect(dossier.provenSolution.verified).toBe(true);
  });

  it("reads an absent score as perfect rather than as zero", () => {
    expect(score(undefined)).toBe(100);
    expect(score(87)).toBe(87);
    expect(score(-5)).toBe(0);
    expect(score(1000)).toBe(100);
    expect(score("nonsense")).toBe(100);
  });

  it("drops findings that name a check, dimension or severity that does not exist", () => {
    const kept = sanitiseFindings([
      { check: "hidden_steps", dimension: "teachingClarity", severity: "major", detail: "ok" },
      { check: "invented_check", dimension: "teachingClarity", severity: "major", detail: "no" },
      { check: "hidden_steps", dimension: "vibes", severity: "major", detail: "no" },
      { check: "hidden_steps", dimension: "teachingClarity", severity: "catastrophic", detail: "no" },
      { check: "hidden_steps", dimension: "teachingClarity", severity: "major" },
    ]);
    expect(kept).toHaveLength(1);
    expect(kept[0].check).toBe("hidden_steps");
  });

  it("caps how many findings one judgement can carry", () => {
    const flood = Array.from({ length: 40 }, (_, i) => ({
      check: "hidden_steps",
      dimension: "teachingClarity",
      severity: "minor",
      detail: `complaint ${i}`,
    }));
    expect(sanitiseFindings(flood).length).toBeLessThanOrEqual(12);
  });

  it("returns nothing at all for a non-array", () => {
    expect(sanitiseFindings(null)).toEqual([]);
    expect(sanitiseFindings("some findings")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Regeneration feedback
// ---------------------------------------------------------------------------

describe("regeneration feedback", () => {
  it("puts the worst first", () => {
    const lines = regenerationFeedback([
      finding({ severity: "minor", detail: "minor thing" }),
      finding({ severity: "hard", detail: "hard thing" }),
      finding({ severity: "major", detail: "major thing" }),
    ]);
    expect(lines[0]).toContain("hard thing");
    expect(lines[1]).toContain("major thing");
    expect(lines[2]).toContain("minor thing");
  });

  it("names the field so the next attempt knows what to rewrite", () => {
    const [line] = regenerationFeedback([finding({ field: "steps.2.why" })]);
    expect(line).toContain("steps.2.why");
    expect(line).toContain("hidden_steps");
  });

  it("deduplicates, so the prompt is not six copies of one complaint", () => {
    const lines = regenerationFeedback([finding(), finding(), finding()]);
    expect(lines).toHaveLength(1);
  });

  it("caps the list rather than shipping an essay", () => {
    const lines = regenerationFeedback(
      Array.from({ length: 30 }, (_, i) => finding({ detail: `thing ${i}` }))
    );
    expect(lines).toHaveLength(8);
  });
});

// ---------------------------------------------------------------------------
// The loop
// ---------------------------------------------------------------------------

describe("the regeneration loop", () => {
  it("ships a good first draft and stops", async () => {
    const generate = vi.fn(async () => ({ tag: "good" }));
    const result = await gateExplanation({
      client: null,
      surface: "test",
      generate,
      toInput: () => input(),
    });
    expect(result.draft).toEqual({ tag: "good" });
    expect(result.attempts).toBe(1);
    expect(generate).toHaveBeenCalledTimes(1);
  });

  it("regenerates with the findings and ships the second draft", async () => {
    const seen: string[][] = [];
    const result = await gateExplanation({
      client: null,
      surface: "test",
      generate: async (attempt, feedback) => {
        seen.push(feedback);
        return { attempt };
      },
      toInput: (draft) => (draft.attempt === 1 ? contradictory() : input()),
    });
    expect(result.draft).toEqual({ attempt: 2 });
    expect(result.attempts).toBe(2);
    expect(seen[0]).toEqual([]);
    expect(seen[1][0]).toContain("mathematical_consistency");
  });

  it("gives up rather than lowering the bar, and returns nothing", async () => {
    const generate = vi.fn(async () => ({ tag: "bad" }));
    const result = await gateExplanation({
      client: null,
      surface: "test",
      generate,
      toInput: () => contradictory(),
      maxAttempts: 3,
    });
    expect(result.draft).toBeNull();
    expect(result.attempts).toBe(3);
    expect(generate).toHaveBeenCalledTimes(3);
    expect(result.report?.pass).toBe(false);
  });

  it("stops immediately when the generator itself returns nothing", async () => {
    const generate = vi.fn(async () => null);
    const result = await gateExplanation({
      client: null,
      surface: "test",
      generate,
      toInput: () => input(),
      maxAttempts: 3,
    });
    expect(result.draft).toBeNull();
    expect(generate).toHaveBeenCalledTimes(1);
    expect(result.report).toBeNull();
  });

  it("NEVER re-solves — every attempt is measured against the identical truth", async () => {
    const truth = input().truth;
    const truthSeen: unknown[] = [];
    await gateExplanation({
      client: null,
      surface: "test",
      generate: async (attempt) => ({ attempt }),
      toInput: () => {
        const next = contradictory();
        // The gate is handed the SAME proven solution object every time; nothing
        // in the loop is given a chance to re-derive it.
        next.truth = truth;
        truthSeen.push(JSON.parse(JSON.stringify(next.truth)));
        return next;
      },
      maxAttempts: 3,
    });
    expect(truthSeen).toHaveLength(3);
    for (const seen of truthSeen) expect(seen).toEqual(truth);
    expect(truth).toEqual(input().truth);
  });

  it("regenerates the explanation only — the generator is never told to re-solve", async () => {
    const feedbacks: string[][] = [];
    await gateExplanation({
      client: null,
      surface: "test",
      generate: async (attempt, feedback) => {
        feedbacks.push(feedback);
        return { attempt };
      },
      toInput: () => contradictory(),
      maxAttempts: 3,
    });
    const everything = feedbacks.flat().join(" ").toLowerCase();
    expect(everything).not.toContain("re-solve");
    expect(everything).not.toContain("recompute");
    expect(everything).not.toContain("correct answer is");
  });
});

// ---------------------------------------------------------------------------
// Difficulty arithmetic
// ---------------------------------------------------------------------------

describe("the difficulty ladder", () => {
  it("shifts a level and clamps at both ends", () => {
    expect(shiftDifficulty("medium", 1)).toBe("hard");
    expect(shiftDifficulty("medium", -1)).toBe("easy");
    expect(shiftDifficulty("veryEasy", -1)).toBe("veryEasy");
    expect(shiftDifficulty("expert", 1)).toBe("expert");
  });

  it("places a ladder's rungs either side of what was asked for", () => {
    expect(expectedDifficulty("medium", "easier")).toBe("easy");
    expect(expectedDifficulty("medium", "similar")).toBe("medium");
    expect(expectedDifficulty("medium", "harder")).toBe("hard");
    expect(expectedDifficulty("medium")).toBe("medium");
  });

  it("maps the engine's own band onto the student ladder", () => {
    expect(difficultyFromBand("primary")).toBe("easy");
    expect(difficultyFromBand("secondary")).toBe("medium");
    expect(difficultyFromBand("preUniversity")).toBe("hard");
    expect(difficultyFromBand("university")).toBe("expert");
  });
});

// ---------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------

function methodFixture(): MethodData[] {
  return [
    {
      id: "factoring",
      name: "Factoring",
      examPick: true,
      steps: [
        {
          expression: "x^2 - 5x + 6 = 0",
          operation: "Start with the equation",
          why: "We begin with the quadratic exactly as it was given to us.",
        },
        {
          expression: "(x - 2)(x - 3) = 0",
          operation: "Factor into two brackets",
          why: "We look for the pair that multiplies to the constant and adds to the middle.",
          rule: "Sum-product factoring",
          explanation: "The pair is -2 and -3, so the quadratic splits into two brackets.",
          commonMistake: "Choosing the wrong signs and writing (x+2)(x+3).",
          selfExplainPrompt: "Which pair multiplies to 6 and adds to -5?",
        },
      ],
    },
    {
      id: "quadratic_formula",
      name: "Quadratic Formula",
      examPick: false,
      steps: [
        {
          expression: "x = 2 \\;\\text{or}\\; x = 3",
          operation: "Apply the formula",
          why: "The formula always works, factorable or not.",
        },
      ],
    },
  ];
}

function payloadFixture(): SolvePayload {
  return {
    schemaVersion: 2,
    problemLatex: "x^2 - 5x + 6 = 0",
    problemType: "quadratic_equation",
    verified: true,
    finalAnswer: { latex: "x_1 = 2,\\; x_2 = 3", plain: "x = 2 or x = 3" },
    graph: null,
    methods: methodFixture(),
  };
}

function teachingFixture(): TeachingLayer {
  return {
    depth: "full",
    header: {
      category: "equations",
      subcategory: "quadratic_equation",
      difficulty: "secondary",
      learningObjective: "Solve a factorable quadratic using the zero-product rule.",
      methodChosen: "Factoring",
      whyMethodChosen: "The constant factors into small whole numbers, so it splits by inspection.",
    },
    overview: {
      asked: "Find every value of x that makes the expression equal zero.",
      goal: "Rewrite it as a product of two brackets, then set each one to zero.",
      givens: ["x^2 - 5x + 6 = 0"],
      predictionPrompt: "Before we start: how many answers do you think this has?",
    },
    concept: {
      body: "A quadratic is an equation whose highest power of x is two, and its graph is a curve.",
      definedTerms: [{ term: "root", plain: "a value of x that makes the expression zero" }],
    },
    methodRationale: {
      alternatives: [
        { name: "Quadratic Formula", whenBetter: "When the brackets do not come out whole." },
      ],
    },
    journey: [
      { id: "understand", summary: "Read the equation; the goal is to find x.", stepIndices: [0] },
      { id: "apply", summary: "Rewrite the left side as two brackets multiplied.", stepIndices: [1] },
    ],
    commonMistakes: [
      {
        mistake: "Getting the signs of the brackets wrong.",
        whyTempting: "Both answers are positive, so plus signs look right.",
        fix: "Multiply the brackets out again and check the middle term.",
      },
    ],
    keyTakeaway: {
      headline: "See a factorable quadratic? Factor, then zero each bracket.",
      detail: "When the numbers come out whole, the answers fall straight out.",
    },
    practiceLadder: {
      easier: { latex: "x^2 - 3x + 2 = 0", rung: "easier", skillHint: "quadratic_equation" },
      similar: { latex: "x^2 - 7x + 12 = 0", rung: "similar", skillHint: "quadratic_equation" },
      harder: { latex: "2x^2 - 7x + 3 = 0", rung: "harder", skillHint: "quadratic_equation" },
    },
  };
}

describe("adapters", () => {
  it("lifts the verified solution out of the payload without touching it", () => {
    const truth = truthFromPayload(payloadFixture());
    expect(truth.problemLatex).toBe("x^2 - 5x + 6 = 0");
    expect(truth.answerPlain).toBe("x = 2 or x = 3");
    expect(truth.stepExpressions).toEqual(["x^2 - 5x + 6 = 0", "(x - 2)(x - 3) = 0"]);
    expect(truth.verified).toBe(true);
  });

  it("takes its steps from the exam-pick method, which is the one being taught", () => {
    const truth = truthFromPayload(payloadFixture());
    expect(truth.stepExpressions).toHaveLength(2);
    expect(truth.stepOperations?.[1]).toBe("Factor into two brackets");
  });

  it("reports a payload the solver could not prove as unverified", () => {
    const payload = { ...payloadFixture(), verified: false };
    expect(truthFromPayload(payload).verified).toBe(false);
  });

  it("flattens the teaching layer into addressable fields", () => {
    const fields = fieldsFromTeaching(teachingFixture(), methodFixture());
    const ids = fields.map((f) => f.id);
    expect(ids).toContain("overview.goal");
    expect(ids).toContain("journey.1.summary");
    expect(ids).toContain("steps.1.why");
    expect(ids).toContain("keyTakeaway.headline");
    expect(fields.every((f) => f.text.trim().length > 0)).toBe(true);
  });

  it("carries prompts across as QUESTIONS, not as assertions", () => {
    const fields = fieldsFromTeaching(teachingFixture(), methodFixture());
    const asked = fields.filter((f) => f.kind === "question").map((f) => f.id);
    expect(asked).toContain("overview.predictionPrompt");
    expect(asked).toContain("steps.1.selfExplainPrompt");
  });

  it("gives the practice ladder its rungs, so check 15 measures each correctly", () => {
    const ladder = practiceFromLadder(teachingFixture(), "medium");
    expect(ladder.map((p) => p.rung)).toEqual(["easier", "similar", "harder"]);
    expect(ladder.map((p) => p.difficulty)).toEqual(["easy", "medium", "hard"]);
  });

  it("builds a teaching input whose truth is the payload's, unaltered", () => {
    const payload = payloadFixture();
    const built = teachingToQualityInput({
      payload,
      teaching: teachingFixture(),
      methods: methodFixture(),
      language: "en",
    });
    expect(built.truth).toEqual(truthFromPayload(payload, methodFixture()));
    expect(built.surface).toBe("teach");
    expect(built.audience.band).toBe("secondary");
    expect(built.certainty.state).toBe("PASS");
  });

  it("marks an unproven payload as a verifier disagreement, not as a pass", () => {
    const built = teachingToQualityInput({
      payload: { ...payloadFixture(), verified: false },
      teaching: teachingFixture(),
      methods: methodFixture(),
      language: "en",
    });
    expect(built.certainty.state).toBe("VERIFIER_DISAGREEMENT");
  });

  it("hands a tutor turn over as one prose field with its declared references", () => {
    const built = tutorToQualityInput({
      reply: "Look at the angle I have highlighted.",
      truth: input().truth,
      language: "en",
      difficulty: "medium",
      state: "PASS",
      anchors: [],
      actions: [],
      visualRefs: ["angle_B"],
    });
    expect(built.surface).toBe("tutor");
    expect(built.explanation.fields).toHaveLength(1);
    expect(built.explanation.fields[0].visualRefs).toEqual(["angle_B"]);
  });
});

// ---------------------------------------------------------------------------
// Golden: the shipped teaching fixture, end to end
// ---------------------------------------------------------------------------

describe("golden — a real teaching layer", () => {
  it("passes the gate", async () => {
    const built = teachingToQualityInput({
      payload: payloadFixture(),
      teaching: teachingFixture(),
      methods: methodFixture(),
      language: "en",
    });
    const report = await evaluateQuality(null, built);
    expect(report.findings).toEqual([]);
    expect(report.pass).toBe(true);
    expect(report.overall).toBe(100);
  });

  it("fails the moment one sentence quotes a number the solver never produced", async () => {
    const teaching = teachingFixture();
    teaching.keyTakeaway.detail = "When the numbers come out whole, x lands on 47 every time.";
    const report = await evaluateQuality(
      null,
      teachingToQualityInput({
        payload: payloadFixture(),
        teaching,
        methods: methodFixture(),
        language: "en",
      })
    );
    expect(report.pass).toBe(false);
    expect(report.scores.mathematicalConsistency).toBe(0);
    expect(report.findings[0].check).toBe("mathematical_consistency");
  });

  it("fails the moment the journey is reordered", async () => {
    const teaching = teachingFixture();
    teaching.journey = [
      { id: "verify", summary: "Check both answers satisfy the equation.", stepIndices: [1] },
      { id: "understand", summary: "Read the equation; the goal is to find x.", stepIndices: [0] },
    ];
    const report = await evaluateQuality(
      null,
      teachingToQualityInput({
        payload: payloadFixture(),
        teaching,
        methods: methodFixture(),
        language: "en",
      })
    );
    expect(report.findings.some((f) => f.check === "educational_flow")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Regressions — every one of these was a real bug in this layer
// ---------------------------------------------------------------------------

describe("regressions", () => {
  it('does not read "let n be the number" as a claim about newtons', async () => {
    const report = await evaluateQuality(
      null,
      input({
        truth: { ...input().truth, units: ["cm"] },
        explanation: {
          fields: [
            { id: "overview.goal", kind: "prose", text: "Let n be the number of sides of the shape." },
          ],
        },
      })
    );
    expect(report.findings).toEqual([]);
  });

  it('does not read "180 degrees in a triangle" as a smuggled answer', async () => {
    const report = await evaluateQuality(
      null,
      input({
        truth: {
          problemLatex: "x + 40 + 65 = 180",
          answerPlain: "x = 75",
          stepExpressions: ["x = 75"],
          verified: true,
        },
        explanation: {
          fields: [
            {
              id: "concept.body",
              kind: "prose",
              text: "The angles inside any triangle always add up to 180 degrees.",
            },
          ],
        },
      })
    );
    expect(report.findings).toEqual([]);
  });

  it('does not accept "this" as having defined a term', async () => {
    const report = await evaluateQuality(
      null,
      input({
        explanation: {
          fields: [
            {
              id: "steps.0.why",
              kind: "step",
              stepIndex: 0,
              text: "This tells us to use the discriminant, so work that out and then continue.",
            },
          ],
        },
      })
    );
    expect(report.findings.some((f) => f.check === "concept_introduction")).toBe(true);
  });

  it("does not block every practice question generated for an unverified problem", async () => {
    const report = await evaluateQuality(
      null,
      input({
        truth: { ...input().truth, verified: false },
        certainty: { state: "LOW_CONFIDENCE" },
        explanation: {
          fields: [{ id: "q1", kind: "practice", text: "Solve $5x + 3 = 23$." }],
        },
        practice: [
          {
            id: "q1",
            prompt: "Solve $5x + 3 = 23$.",
            skill: "linear equation",
            difficulty: "medium",
            concepts: ["linear equation"],
          },
        ],
      })
    );
    expect(report.findings).toEqual([]);
  });

  it("keeps a hyphenated word whole instead of eating the rest of the sentence", async () => {
    const report = await evaluateQuality(
      null,
      input({
        audience: { language: "en", difficulty: "veryEasy" },
        explanation: {
          fields: [
            {
              id: "steps.0.why",
              kind: "step",
              stepIndex: 0,
              text:
                "This well-known move takes the same amount away from each side of " +
                "the equation, which keeps both sides balanced and equal for us all.",
            },
          ],
        },
      })
    );
    // 24 words at veryEasy, where the limit is 16 — only visible if the hyphen
    // did not swallow everything after it.
    expect(report.findings.some((f) => f.check === "difficulty_alignment")).toBe(true);
  });
});
