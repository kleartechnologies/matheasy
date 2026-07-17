/**
 * The teaching-layer firewall (spec §4.4). `validateTeaching` is the golden-rule
 * gate for the additive teaching layer: it MUST accept the two golden fixtures
 * and MUST reject every way an LLM could smuggle a number, mislabel the problem,
 * or leak an answer into an honest (unverified) payload.
 */
import { describe, it, expect } from "vitest";

import { validateTeaching, extractNumbers } from "../src/solver/teach";
import { deriveTeachingMeta } from "../src/solver/classify";
import { SolvePayload, TeachingLayer } from "../src/solver/types";

// ---------------------------------------------------------------------------
// Golden fixture 1 — x^2 - 5x + 6 = 0 (spec §4.2)
// ---------------------------------------------------------------------------
function quadraticFixture(): SolvePayload {
  return {
    schemaVersion: 2,
    problemLatex: "x^2 - 5x + 6 = 0",
    problemType: "quadratic_equation",
    verified: true,
    finalAnswer: { latex: "x_1 = 2,\\; x_2 = 3", plain: "x = 2 or x = 3" },
    graph: null,
    methods: [
      {
        id: "factoring",
        name: "Factoring",
        examPick: true,
        steps: [
          {
            expression: "x^2 - 5x + 6 = 0",
            operation: "Start with the equation",
            why: "We begin with the quadratic exactly as given, already set to zero.",
          },
          {
            expression: "(x - 2)(x - 3) = 0",
            operation: "Factor into two brackets",
            operationSymbol: "factor",
            why: "We look for two numbers that multiply to the constant and add to the middle coefficient.",
            rule: "Sum-product factoring",
            explanation:
              "The pair that multiplies to 6 and adds to -5 is -2 and -3, so the quadratic splits into (x-2)(x-3).",
            commonMistake: "Choosing the wrong signs and writing (x+2)(x+3).",
            selfExplainPrompt: "Which pair of numbers multiplies to 6 and adds to -5?",
            pivotal: true,
          },
          {
            expression: "x - 2 = 0 \\;\\text{or}\\; x - 3 = 0",
            operation: "Apply the zero-product rule",
            why: "A product is zero only when one of its factors is zero, so we split into two simple equations.",
            rule: "Zero-product property",
            commonMistake: "Dividing both sides by a bracket, which deletes a solution.",
          },
          {
            expression: "x = 2 \\;\\text{or}\\; x = 3",
            operation: "Solve each factor",
            why: "Undoing the subtraction in each bracket isolates x, giving both roots.",
            commonMistake:
              "Reporting only one root and forgetting a quadratic usually has two.",
          },
        ],
      },
      {
        id: "quadratic_formula",
        name: "Quadratic Formula",
        examPick: false,
        steps: [
          {
            expression: "a=1,\\; b=-5,\\; c=6",
            operation: "Identify a, b, c",
            why: "The formula needs the three coefficients read off the standard form, keeping each sign.",
          },
          {
            expression: "x = \\frac{5 \\pm \\sqrt{25 - 24}}{2}",
            operation: "Apply the quadratic formula",
            why: "Substituting the coefficients into the formula is always valid for a quadratic.",
          },
          {
            expression: "x = \\frac{5 \\pm 1}{2}",
            operation: "Simplify the discriminant",
            why: "A positive discriminant means two real roots.",
          },
          {
            expression: "x = 2 \\;\\text{or}\\; x = 3",
            operation: "Find the roots",
            why: "The two signs give the two solutions.",
          },
        ],
      },
    ],
    teaching: {
      depth: "full",
      header: {
        category: "equations",
        subcategory: "Quadratic equation (factorable, integer roots)",
        difficulty: "secondary",
        learningObjective: "Solve a factorable quadratic using the zero-product rule.",
        methodChosen: "Factoring",
        whyMethodChosen:
          "The constant factors into small whole numbers, so the equation splits by inspection.",
      },
      overview: {
        asked: "Find every value of x that makes the expression equal zero.",
        goal: "Rewrite the quadratic as a product of two factors, then set each to zero.",
        givens: ["x^2 - 5x + 6 = 0", "x is the unknown"],
        predictionPrompt:
          "Before we solve: do you think this equation has one answer, two, or none?",
      },
      concept: {
        body: "A quadratic is an equation where the variable is squared; its graph is a U-shaped parabola. The places the curve crosses the x-axis are the answers, called roots. A parabola can cross twice, touch once, or miss — so a quadratic can have two roots, one, or none.",
        definedTerms: [
          { term: "quadratic", plain: "an equation whose highest power of x is 2" },
          { term: "root", plain: "a value of x that makes the expression zero" },
          { term: "factor", plain: "one of the pieces you multiply together" },
        ],
      },
      methodRationale: {
        alternatives: [
          {
            name: "Quadratic Formula",
            whenBetter:
              "When the quadratic doesn't factor with whole numbers, or you can't spot the factors.",
          },
          {
            name: "Completing the Square",
            whenBetter: "When you also need the vertex, or to derive the formula.",
          },
        ],
      },
      journey: [
        { id: "understand", summary: "Read the equation; the goal is to find x.", stepIndices: [] },
        { id: "chooseMethod", summary: "The constant factors cleanly, so factor.", stepIndices: [] },
        { id: "apply", summary: "Rewrite as (x-2)(x-3)=0.", stepIndices: [1] },
        { id: "simplify", summary: "Use the zero-product rule and solve each factor.", stepIndices: [2, 3] },
        { id: "verify", summary: "Substitute each root back — both give 0.", stepIndices: [] },
        { id: "takeaway", summary: "A factorable quadratic solves in one line.", stepIndices: [] },
      ],
      commonMistakes: [
        {
          mistake: "Getting the signs of the factors wrong.",
          whyTempting: "Both roots are positive, so students expect plus signs inside the brackets.",
          fix: "Expand your brackets back and check the middle term is -5x.",
        },
        {
          mistake: "Reporting only one root.",
          whyTempting: "You stop as soon as you find a value that works.",
          fix: "Two brackets means two equations — set both to zero.",
        },
        {
          mistake: "Dividing both sides by a bracket.",
          whyTempting: "It looks like normal cancelling.",
          fix: "That deletes a root; use the zero-product rule instead.",
        },
      ],
      keyTakeaway: {
        headline: "See a factorable quadratic? Factor, then zero each bracket.",
        detail:
          "When the numbers factor with whole numbers, the roots fall straight out — no formula needed.",
      },
      practiceLadder: {
        easier: { latex: "x^2 - 3x + 2 = 0", rung: "easier", skillHint: "quadratic_factoring" },
        similar: { latex: "x^2 - 7x + 12 = 0", rung: "similar", skillHint: "quadratic_factoring" },
        harder: {
          latex: "2x^2 - 7x + 3 = 0",
          rung: "harder",
          skillHint: "quadratic_factoring_leading_coeff",
        },
      },
    },
  };
}

// ---------------------------------------------------------------------------
// Golden fixture 2 — mean of a data set (spec §4.3)
// ---------------------------------------------------------------------------
function meanFixture(): SolvePayload {
  return {
    schemaVersion: 2,
    problemLatex: "\\text{Find the mean of } 4, 8, 15, 16, 23",
    problemType: "statistics",
    verified: true,
    finalAnswer: { latex: "\\bar{x} = 13.2", plain: "mean = 13.2" },
    graph: null,
    methods: [
      {
        id: "mean_definition",
        name: "Arithmetic Mean",
        examPick: true,
        steps: [
          {
            expression: "\\text{values} = \\{4, 8, 15, 16, 23\\}",
            operation: "List the values",
            why: "Writing out every value makes sure none is missed in the total.",
          },
          {
            expression: "4 + 8 + 15 + 16 + 23 = 66",
            operation: "Add the values",
            operationSymbol: "sum",
            why: "The mean is built from the grand total, so every value is added together.",
            pivotal: true,
            selfExplainPrompt: "Before dividing — what do we need first, the total or the count?",
            commonMistake: "Slipping on one term while adding a long list.",
          },
          {
            expression: "n = 5",
            operation: "Count the values",
            why: "We will divide by how many values there are, so the count must be exact.",
            commonMistake: "Dividing by the largest value instead of the count.",
          },
          {
            expression: "\\bar{x} = \\frac{66}{5} = 13.2",
            operation: "Divide the total by the count",
            why: "Sharing the total equally across all the values is exactly what the mean means.",
            rule: "Mean = sum ÷ count",
            commonMistake: "Rounding the decimal away and writing a whole number.",
          },
        ],
      },
    ],
    teaching: {
      depth: "full",
      header: {
        category: "statistics",
        subcategory: "Measure of centre — arithmetic mean",
        difficulty: "primary",
        learningObjective: "Compute the mean of a small data set and say what it represents.",
        methodChosen: "Arithmetic Mean",
        whyMethodChosen:
          "The question asks for the mean specifically, which is the total shared equally.",
      },
      overview: {
        asked: "Find the average of the five numbers.",
        goal: "Add all the values, then share the total equally across how many there are.",
        givens: ["The data set {4, 8, 15, 16, 23}", "There are 5 values"],
        // Deliberately references 8 (present) and 20 (foreign) — a prediction is a
        // QUESTION and is EXEMPT from the numeric gate on the verified path.
        predictionPrompt: "Quick guess — will the mean be closer to 8 or closer to 20?",
      },
      concept: {
        body: "The mean is the fair-share number: pour all the values together and split them evenly, and each gets the mean. It describes the middle of a set with one number. Because it uses every value, one very large or very small value pulls it up or down.",
        definedTerms: [
          { term: "mean", plain: "the total of the values divided by how many there are" },
          { term: "data set", plain: "the group of numbers you're summarising" },
        ],
      },
      methodRationale: {
        alternatives: [
          { name: "Median", whenBetter: "When extreme outliers would distort the mean." },
          { name: "Mode", whenBetter: "When you care about the most frequent value, like shoe sizes." },
        ],
      },
      journey: [
        { id: "understand", summary: "We need the average of five numbers.", stepIndices: [] },
        { id: "chooseMethod", summary: "'Mean' means sum ÷ count.", stepIndices: [] },
        { id: "apply", summary: "Add the values, then count them.", stepIndices: [1, 2] },
        { id: "simplify", summary: "Divide the total by the count.", stepIndices: [3] },
        { id: "verify", summary: "The result sits between the smallest and largest value.", stepIndices: [] },
        { id: "takeaway", summary: "Mean = total ÷ how many.", stepIndices: [] },
      ],
      commonMistakes: [
        {
          mistake: "Dividing by the wrong number.",
          whyTempting: "The largest value is right there and feels significant.",
          fix: "Divide by the count of values, not by any single value.",
        },
        {
          mistake: "Confusing mean with median.",
          whyTempting: "Both describe 'the middle'.",
          fix: "Mean = sum ÷ count; median = the middle value once sorted.",
        },
        {
          mistake: "Rounding away the decimal.",
          whyTempting: "Whole numbers feel tidier.",
          fix: "A mean often isn't whole — keep the decimal.",
        },
      ],
      keyTakeaway: {
        headline: "To average, total everything then share it out equally.",
        detail: "The mean always lands between the smallest and largest value — a quick sanity check.",
      },
      practiceLadder: {
        easier: { latex: "\\text{mean of } 2, 4, 6", rung: "easier", skillHint: "mean_small_set" },
        similar: { latex: "\\text{mean of } 5, 9, 12, 14, 20", rung: "similar", skillHint: "mean_small_set" },
        harder: { latex: "\\text{mean of } 4, 8, 15, 16, 23, 42", rung: "harder", skillHint: "mean_with_outlier" },
      },
    },
  };
}

// ---------------------------------------------------------------------------
// Honest fixture — a proof routed to the tutor (no answer, no numbers)
// ---------------------------------------------------------------------------
function honestFixture(): SolvePayload {
  return {
    schemaVersion: 2,
    problemLatex: "\\text{Prove that } \\sqrt{2} \\text{ is irrational}",
    problemType: "conceptual",
    verified: false,
    finalAnswer: null,
    graph: null,
    routeToTutor: true,
    methods: [],
    teaching: {
      depth: "concept_only",
      honestReason: "proof",
      header: {
        category: "conceptual",
        subcategory: "Irrationality proof",
        difficulty: "university",
        learningObjective: "Recognise a proof by contradiction.",
        methodChosen: "",
        whyMethodChosen: "",
      },
      overview: {
        asked: "Show that this square root cannot be written as a simple fraction.",
        goal: "Assume it can be written as a fraction, then reach a contradiction.",
        givens: [],
        predictionPrompt: "Do you think this square root can be written as a fraction?",
      },
      concept: {
        body: "An irrational number cannot be written as a simple fraction of whole numbers. A proof by contradiction assumes the opposite and shows that assumption forces an impossibility.",
        definedTerms: [
          { term: "irrational", plain: "a number that cannot be written as a fraction of whole numbers" },
        ],
      },
      methodRationale: { alternatives: [] },
      journey: [
        { id: "understand", summary: "We must show it is not a fraction.", stepIndices: [] },
        { id: "chooseMethod", summary: "Assume the opposite and look for a clash.", stepIndices: [] },
      ],
      commonMistakes: [
        {
          mistake: "Trying to compute a decimal instead of arguing.",
          whyTempting: "A calculator answer feels like proof.",
          fix: "A proof needs a logical contradiction, not a rounded value.",
        },
      ],
      keyTakeaway: { headline: "Assume the opposite, then find a contradiction." },
    },
  };
}

/** Mutate a copy of a fixture's teaching layer. */
function withTeaching(
  base: SolvePayload,
  mutate: (t: TeachingLayer) => void
): SolvePayload {
  const clone = structuredClone(base);
  mutate(clone.teaching as TeachingLayer);
  return clone;
}

describe("deriveTeachingMeta", () => {
  it("maps the golden fixtures' problem types to their header meta", () => {
    expect(deriveTeachingMeta("quadratic_equation")).toEqual({
      category: "equations",
      difficulty: "secondary",
    });
    expect(deriveTeachingMeta("statistics")).toEqual({
      category: "statistics",
      difficulty: "primary",
    });
  });

  it("falls back to [other, secondary] for an unknown type (never throws)", () => {
    expect(deriveTeachingMeta("something_new_v3")).toEqual({
      category: "other",
      difficulty: "secondary",
    });
  });
});

describe("validateTeaching — accepts the golden fixtures", () => {
  it("accepts the quadratic fixture", () => {
    const p = quadraticFixture();
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(true);
  });

  it("accepts the mean fixture (incl. the foreign number in the prediction prompt)", () => {
    const p = meanFixture();
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(true);
  });

  it("accepts the honest (proof) fixture", () => {
    const p = honestFixture();
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(true);
  });
});

describe("validateTeaching — numeric firewall (verified path)", () => {
  it("rejects a step `why` that states a computed result not in the skeleton", () => {
    const p = quadraticFixture();
    p.methods[0].steps[3].why = "Undoing the subtraction gives x = 8.";
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a spelled-out foreign number in a step field", () => {
    const p = quadraticFixture();
    p.methods[0].steps[3].why = "Solving each factor, x becomes eight.";
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a decimal leak in a problem-level field (wrong mean)", () => {
    const p = meanFixture();
    (p.teaching as TeachingLayer).keyTakeaway.detail =
      "The mean of these values works out to 14.7.";
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a fraction leak that a naive =n scrub would miss (concept body)", () => {
    const p = quadraticFixture();
    (p.teaching as TeachingLayer).concept.body =
      "A quadratic like this always has a root at \\frac{7}{2}.";
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("allows a number that IS in this step's own skeleton", () => {
    const p = quadraticFixture();
    // 6 and -5 are in step 1's expression / the problem — legitimate to reference.
    p.methods[0].steps[1].explanation =
      "The pair multiplying to 6 and summing to -5 is what we need.";
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(true);
  });
});

describe("validateTeaching — header anchoring", () => {
  it("rejects a methodChosen that isn't the examPick method's name", () => {
    const p = withTeaching(quadraticFixture(), (t) => {
      t.header.methodChosen = "Completing the Square";
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a category the engine did not derive", () => {
    const p = withTeaching(quadraticFixture(), (t) => {
      t.header.category = "calculus";
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a difficulty the engine did not derive", () => {
    const p = withTeaching(quadraticFixture(), (t) => {
      t.header.difficulty = "university";
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a keyTakeaway that merely paraphrases the learningObjective", () => {
    const p = withTeaching(quadraticFixture(), (t) => {
      t.header.learningObjective = "Solve a factorable quadratic with the zero-product rule.";
      t.keyTakeaway.headline = "Solve a factorable quadratic with the zero-product rule.";
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });
});

describe("validateTeaching — honest mode (unverified)", () => {
  it("rejects a non-concept_only depth on an unverified payload", () => {
    const p = withTeaching(honestFixture(), (t) => {
      t.depth = "lite";
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a practice ladder on an honest payload", () => {
    const p = withTeaching(honestFixture(), (t) => {
      t.practiceLadder = {
        easier: { latex: "x=1", rung: "easier" },
        similar: { latex: "x=2", rung: "similar" },
        harder: { latex: "x=3", rung: "harder" },
      };
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects ANY number in honest-mode prose (empty allow-set)", () => {
    const p = withTeaching(honestFixture(), (t) => {
      t.concept.body = "Assume it equals a fraction with numerator 7 and reach a contradiction.";
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a spelled-out VALUE (>=4) in honest-mode prose", () => {
    const p = withTeaching(honestFixture(), (t) => {
      t.keyTakeaway.headline = "There are seven cases to rule out.";
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("ACCEPTS small structural counting words in honest prose (both/single)", () => {
    const p = withTeaching(honestFixture(), (t) => {
      t.concept.body =
        "Assume both sides are equal and look for the single step that breaks.";
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(true);
  });

  it("rejects a foreign number in honest-mode givens", () => {
    const p = withTeaching(honestFixture(), (t) => {
      t.overview.givens = ["The value is 42"];
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects worked-step narration attached to an honest payload", () => {
    const p = honestFixture();
    p.methods = [
      {
        id: "leak",
        name: "Leak",
        examPick: true,
        steps: [{ expression: "x = 4", operation: "Solve", why: "Isolate x." }],
      },
    ];
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });
});

describe("validateTeaching — depth / ladder consistency", () => {
  it("rejects a practice ladder on a lite (verified) payload", () => {
    const p = withTeaching(quadraticFixture(), (t) => {
      t.depth = "lite";
    });
    // lite still carries the ladder from the full fixture → must be rejected.
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });
});

describe("validateTeaching — firewall bypasses closed by review", () => {
  it("rejects a foreign number in a step operationSymbol chip (#3)", () => {
    const p = quadraticFixture();
    p.methods[0].steps[1].operationSymbol = "= 42"; // answer is x=2/3
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a foreign number in overview.givens (#2)", () => {
    const p = withTeaching(quadraticFixture(), (t) => {
      t.overview.givens = ["x = 999"];
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a problem-only number used in a LATE step (narrow allow-set, #11)", () => {
    const p = quadraticFixture();
    // 6 is the problem's constant but is NOT in the final step's own expressions
    // (answer x=2/3, prior "x-2=0 or x-3=0") → the per-step allow-set must reject it.
    p.methods[0].steps[3].why = "These roots multiply back to the constant 6.";
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a non-ASCII (Arabic-Indic) digit smuggled into prose (#4)", () => {
    const p = withTeaching(meanFixture(), (t) => {
      t.keyTakeaway.detail = "The mean works out to ٥٠."; // Arabic-Indic 50
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });

  it("rejects a thousands-separated foreign number (#6)", () => {
    const p = withTeaching(meanFixture(), (t) => {
      t.concept.body = "A mean can be as large as 9,000 for big data.";
    });
    expect(validateTeaching(p, p.teaching as TeachingLayer)).toBe(false);
  });
});

describe("extractNumbers — normalization + ReDoS safety", () => {
  const has = (arr: number[], v: number) => arr.some((n) => Math.abs(n - v) < 1e-6);

  it("parses a braced mixed number as 10.5 (not 0.5 — the historic regression)", () => {
    expect(has(extractNumbers("10\\frac{1}{2}"), 10.5)).toBe(true);
  });

  it("parses a shorthand mixed number and a bare fraction", () => {
    expect(has(extractNumbers("2\\frac12"), 2.5)).toBe(true);
    expect(has(extractNumbers("\\frac{1}{2}"), 0.5)).toBe(true);
    expect(has(extractNumbers("3/4"), 0.75)).toBe(true);
  });

  it("reads scientific notation and thousands separators as one value", () => {
    expect(has(extractNumbers("about 1e3 things"), 1000)).toBe(true);
    expect(has(extractNumbers("about 9,000 things"), 9000)).toBe(true);
    expect(has(extractNumbers("about 1{,}000 things"), 1000)).toBe(true);
  });

  it("folds fullwidth digits and flags unfoldable Unicode digits", () => {
    expect(has(extractNumbers("value ５０"), 50)).toBe(true); // fullwidth → 50
    expect(extractNumbers("value ٥٠").some((n) => !Number.isFinite(n))).toBe(true); // Arabic-Indic → sentinel
  });

  it("is linear on a pathological \\frac + whitespace input (ReDoS guard)", () => {
    const evil = "\\frac{1" + " ".repeat(50000) + "x";
    const start = Date.now();
    extractNumbers(evil);
    // The old regex was ~O(N^2.8) (tens of seconds at N=6400); linear is <100ms.
    expect(Date.now() - start).toBeLessThan(2000);
  });
});
