import { describe, expect, it } from "vitest";
import * as mathsteps from "mathsteps";

import {
  AnimationInstruction,
  TEMPLATE_BY_CHANGE_TYPE,
  assertNoInventedTokens,
  buildAnimationSchema,
  collectChangeGroups,
} from "../src/solver/animationSchema";

/** Real mathsteps step objects — NOT hand-mocked, so the tests exercise the true
 * runtime node/changeGroup shape the resolvers depend on. */
function steps(equation: string): mathsteps.MsStep[] {
  return mathsteps.solveEquation(equation);
}

/** First instruction whose changeType matches (schema is one-per-step). */
function byType(
  schema: AnimationInstruction[],
  changeType: string
): AnimationInstruction | undefined {
  return schema.find((i) => i.changeType === changeType);
}

describe("buildAnimationSchema — linear equation (2x + 3 = 7)", () => {
  const schema = buildAnimationSchema(steps("2x + 3 = 7"));

  it("emits one instruction per equation step, indices aligned", () => {
    expect(schema.length).toBeGreaterThan(0);
    schema.forEach((inst, i) => expect(inst.stepIndex).toBe(i));
  });

  it("SUBTRACT step uses move_across_equals and moves +3 across the equals", () => {
    const sub = byType(schema, "SUBTRACT_FROM_BOTH_SIDES");
    expect(sub).toBeDefined();
    expect(sub!.animationTemplate).toBe("move_across_equals");

    // The constant 3 that was on the LEFT is paired to its destination on the RIGHT.
    const three = sub!.tokens.find((t) => t.value === "3");
    expect(three).toBeDefined();
    expect(three!.fromPath).toBe("L/1"); // +3 was the 2nd top-level term on the left
    expect(three!.toPath).toBeTruthy();
    expect(three!.toPath!.startsWith("R")).toBe(true); // moved to the right side
  });

  it("before/after LaTeX come straight from the verified equations", () => {
    const sub = byType(schema, "SUBTRACT_FROM_BOTH_SIDES");
    expect(sub!.beforeLatex).toBe("2x + 3 = 7"); // == the original problem
    expect(sub!.afterLatex).toContain("-"); // the subtraction now shows
  });

  it("DIVIDE step pairs the coefficient to the divisor on both sides", () => {
    const div = byType(schema, "DIVIDE_FROM_BOTH_SIDES");
    expect(div).toBeDefined();
    expect(div!.animationTemplate).toBe("divide_both_sides");

    // Coefficient 2 (from 2x on the left) → the /2 divisor on the left.
    const primary = div!.tokens.find(
      (t) => t.value === "2" && t.toPath !== null && t.toPath.startsWith("L")
    );
    expect(primary).toBeDefined();
    expect(primary!.fromPath).toBe("L/0"); // the coefficient inside 2*x
    expect(primary!.toPath).toBe("L/1"); // the divisor of (2x)/2

    // The same divisor also appears on the right side.
    expect(
      div!.tokens.some((t) => t.value === "2" && t.toPath?.startsWith("R"))
    ).toBe(true);
  });

  it("every referenced token traces back to the verified expression (firewall held)", () => {
    // buildAnimationSchema throws on a fabricated token; reaching here means every
    // token value is a substring of some verified before/after equation.
    for (const inst of schema) {
      const hay = (inst.beforeLatex + inst.afterLatex).replace(/\s|\*/g, "");
      for (const t of inst.tokens) {
        if (t.value.length === 0) continue;
        expect(hay.includes(t.value.replace(/\s|\*/g, ""))).toBe(true);
      }
    }
  });
});

describe("buildAnimationSchema — pure divide (6x = 18)", () => {
  const schema = buildAnimationSchema(steps("6x = 18"));

  it("first step divides both sides, pairing coefficient 6 → divisor 6", () => {
    const div = byType(schema, "DIVIDE_FROM_BOTH_SIDES");
    expect(div).toBeDefined();
    expect(div!.animationTemplate).toBe("divide_both_sides");

    const primary = div!.tokens.find(
      (t) => t.value === "6" && t.toPath?.startsWith("L")
    );
    expect(primary).toBeDefined();
    expect(primary!.fromPath).toBe("L/0"); // coefficient of 6x
    expect(primary!.toPath).toBe("L/1"); // divisor of (6x)/6
  });
});

describe("buildAnimationSchema — multiply to clear a denominator (x/3 = 4)", () => {
  const schema = buildAnimationSchema(steps("x/3 = 4"));

  it("maps MULTIPLY_TO_BOTH_SIDES to divide_both_sides (the multiplicative family)", () => {
    const mul = byType(schema, "MULTIPLY_TO_BOTH_SIDES");
    expect(mul).toBeDefined();
    expect(mul!.animationTemplate).toBe("divide_both_sides");

    // The denominator 3 (of x/3) pairs to the ×3 applied on the left.
    const primary = mul!.tokens.find(
      (t) => t.value === "3" && t.toPath?.startsWith("L")
    );
    expect(primary).toBeDefined();
    expect(primary!.fromPath).toBe("L/1"); // the denominator in x/3
    // ...and the same multiplier lands on the right side too.
    expect(mul!.tokens.some((t) => t.value === "3" && t.toPath?.startsWith("R"))).toBe(true);
  });
});

describe("buildAnimationSchema — combine like terms (2x + 3x + 1 = 11)", () => {
  const schema = buildAnimationSchema(steps("2x + 3x + 1 = 11"));

  it("maps the two like terms onto the single combined term", () => {
    const combine = byType(schema, "COLLECT_AND_COMBINE_LIKE_TERMS");
    expect(combine).toBeDefined();
    expect(combine!.animationTemplate).toBe("combine_terms");

    const twoX = combine!.tokens.find((t) => t.value === "2x");
    const threeX = combine!.tokens.find((t) => t.value === "3x");
    expect(twoX).toBeDefined();
    expect(threeX).toBeDefined();

    // Both collapse into the SAME combined slot (the 5x term)...
    expect(twoX!.toPath).toBe(threeX!.toPath);
    expect(twoX!.toPath).toBeTruthy();
    // ...and originate from DISTINCT source terms on the left.
    expect(twoX!.fromPath).not.toBe(threeX!.fromPath);
    expect(twoX!.fromPath).toBeTruthy();
    expect(threeX!.fromPath).toBeTruthy();
  });
});

describe("buildAnimationSchema — ADD_POLYNOMIAL_TERMS (2x + 3x = 10)", () => {
  const schema = buildAnimationSchema(steps("2x + 3x = 10"));

  it("animates the simplest like-terms merge as combine_terms (not a fade)", () => {
    const combine = byType(schema, "ADD_POLYNOMIAL_TERMS");
    expect(combine).toBeDefined();
    expect(combine!.animationTemplate).toBe("combine_terms");

    const twoX = combine!.tokens.find((t) => t.value === "2x");
    const threeX = combine!.tokens.find((t) => t.value === "3x");
    expect(twoX).toBeDefined();
    expect(threeX).toBeDefined();
    // Both collapse into the single combined slot on the left.
    expect(twoX!.toPath).toBe(threeX!.toPath);
    expect(twoX!.fromPath).not.toBe(threeX!.fromPath);
  });
});

describe("template table + changeGroup helper", () => {
  it("maps every documented changeType and leaves unknowns to the default", () => {
    expect(TEMPLATE_BY_CHANGE_TYPE.SUBTRACT_FROM_BOTH_SIDES).toBe("move_across_equals");
    expect(TEMPLATE_BY_CHANGE_TYPE.ADD_TO_BOTH_SIDES).toBe("move_across_equals");
    expect(TEMPLATE_BY_CHANGE_TYPE.DIVIDE_FROM_BOTH_SIDES).toBe("divide_both_sides");
    expect(TEMPLATE_BY_CHANGE_TYPE.SIMPLIFY_ARITHMETIC).toBe("simplify_in_place");
    expect(TEMPLATE_BY_CHANGE_TYPE.SIMPLIFY_FRACTION).toBe("simplify_in_place");
    expect(TEMPLATE_BY_CHANGE_TYPE.COLLECT_AND_COMBINE_LIKE_TERMS).toBe("combine_terms");
    expect(TEMPLATE_BY_CHANGE_TYPE.SOME_UNKNOWN_TYPE).toBeUndefined();
  });

  it("collectChangeGroups yields side-prefixed paths for tagged nodes", () => {
    // The SUBTRACT step tags the introduced constant on the new equation's sides.
    const sub = steps("2x + 3 = 7").find(
      (s) => s.changeType === "SUBTRACT_FROM_BOTH_SIDES"
    );
    expect(sub).toBeDefined();
    const newEq = sub!.newEquation as unknown as {
      leftNode: Parameters<typeof collectChangeGroups>[0];
    };
    const hits = collectChangeGroups(newEq.leftNode, "L");
    expect(hits.length).toBeGreaterThan(0);
    for (const h of hits) {
      expect(h.path.startsWith("L")).toBe(true);
      expect(typeof h.changeGroup).toBe("number");
    }
  });
});

describe("firewall — no false positives on faithful values", () => {
  // Regression: a whole-side/simplify value copied via node.toString() renders an
  // internal negative as "x + -1", while the firewall haystack uses ascii's
  // "x - 1". Before canonicalization these disagreed and the firewall threw on a
  // faithful value, aborting the whole schema. It must not throw now.
  it.each([
    "3x - 1 = 2x + 5",
    "x - 5 = 2x - 8",
    "2x - 7 = 5 - x",
    "-2x + 3 = -x - 4",
  ])("builds %s without a false firewall throw", (eq) => {
    const schema = buildAnimationSchema(steps(eq));
    expect(schema.length).toBeGreaterThan(0);
  });
});

describe("firewall — assertNoInventedTokens actually throws", () => {
  // Build a real instruction from a real step, then POISON one token with a value
  // absent from the verified before/after — the exact golden-rule violation the
  // firewall exists to catch. This pins the throw branch so the guard can't be
  // silently weakened to a no-op without a test failing.
  const step = steps("2x + 3 = 7")[0];
  const base: AnimationInstruction = {
    stepIndex: 0,
    changeType: step.changeType,
    beforeLatex: step.oldEquation!.ascii(),
    afterLatex: step.newEquation!.ascii(),
    animationTemplate: "move_across_equals",
    tokens: [],
    explanationKey: "anim.step.test",
  };

  it("throws on a token value absent from the verified expressions", () => {
    const poisoned: AnimationInstruction = {
      ...base,
      tokens: [{ value: "999", fromPath: "L/0", toPath: "R/0", color: "pink", highlight: "circle" }],
    };
    expect(() =>
      assertNoInventedTokens(poisoned, step.oldEquation!, step.newEquation!)
    ).toThrow(/firewall/);
  });

  it("does NOT throw on a token value the solver really produced", () => {
    const faithful: AnimationInstruction = {
      ...base,
      tokens: [{ value: "3", fromPath: "L/1", toPath: "R/1", color: "pink", highlight: "circle" }],
    };
    expect(() =>
      assertNoInventedTokens(faithful, step.oldEquation!, step.newEquation!)
    ).not.toThrow();
  });
});
