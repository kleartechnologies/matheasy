import { describe, expect, it } from "vitest";

import {
  buildWorkContext,
  checkStudentWork,
  normalizeWorkLines,
  parseAssignments,
  MAX_WORK_LINES,
} from "../src/proxy/tutorWork";
import { coerceTutorImageRead } from "../src/proxy/tutorImage";

describe("parseAssignments", () => {
  it("reads a single root", () => {
    expect(parseAssignments("x = 4")).toEqual([{ x: 4 }]);
  });

  it("reads several roots of one unknown as alternatives", () => {
    expect(parseAssignments("x = 2, x = -3")).toEqual([{ x: 2 }, { x: -3 }]);
    expect(parseAssignments("x = 2 \\text{ or } x = -3")).toEqual([
      { x: 2 },
      { x: -3 },
    ]);
  });

  it("reads a system as ONE assignment naming every unknown", () => {
    expect(parseAssignments("x = -1, y = 3")).toEqual([{ x: -1, y: 3 }]);
  });

  it("evaluates exact fractional and radical answers", () => {
    expect(parseAssignments("x = \\frac{1}{2}")).toEqual([{ x: 0.5 }]);
    const [root] = parseAssignments("x = \\sqrt{2}");
    expect(root.x).toBeCloseTo(Math.SQRT2, 10);
  });

  it("declines anything it cannot read as an assignment", () => {
    // A bare value, an inequality, a set, prose — better no check than a guess.
    expect(parseAssignments("4")).toEqual([]);
    expect(parseAssignments("")).toEqual([]);
    expect(parseAssignments("x > 3")).toEqual([]);
    expect(parseAssignments("\\{1, 2, 3\\}")).toEqual([]);
    expect(parseAssignments("2x = 8")).toEqual([]);
    // Mixed repeated AND distinct names is ambiguous — decline, don't guess.
    expect(parseAssignments("x = 1, x = 2, y = 3")).toEqual([]);
  });
});

describe("checkStudentWork — equation problems", () => {
  it("passes working that stays equivalent to the original", () => {
    const check = checkStudentWork("2x + 5 = 13", "x = 4", [
      "2x + 5 = 13",
      "2x = 8",
      "x = 4",
    ]);
    expect(check.status).toBe("ok");
    expect(check.firstErrorLine).toBeNull();
    expect(check.checkedCount).toBe(3);
  });

  it("finds the FIRST line that stopped being equivalent", () => {
    // The classic slip: 13 - 5 written as 9.
    const check = checkStudentWork("2x + 5 = 13", "x = 4", [
      "2x + 5 = 13",
      "2x = 9",
      "x = 4.5",
    ]);
    expect(check.status).toBe("error");
    expect(check.firstErrorLine).toBe(2);
    expect(check.firstErrorLatex).toBe("2x = 9");
  });

  it("accepts a student working one case of a multi-root problem", () => {
    // x = 2 is a legitimate line even though x = -3 does not satisfy it.
    const check = checkStudentWork(
      "x^2 + x - 6 = 0",
      "x = 2, x = -3",
      ["(x - 2)(x + 3) = 0", "x = 2"]
    );
    expect(check.status).toBe("ok");
  });

  it("catches a wrong factorisation of a quadratic", () => {
    const check = checkStudentWork(
      "x^2 + x - 6 = 0",
      "x = 2, x = -3",
      ["(x - 2)(x - 3) = 0"]
    );
    expect(check.status).toBe("error");
    expect(check.firstErrorLine).toBe(1);
  });

  it("accepts a legal case split out of a factorisation", () => {
    // "(x - 2) = 0, so x = 2" drops the other root — legal, not an error.
    const check = checkStudentWork("x^2 + x - 6 = 0", "x = 2, x = -3", [
      "(x - 2)(x + 3) = 0",
      "x - 2 = 0",
      "x = 2",
    ]);
    expect(check.status).toBe("ok");
  });

  it("stands down when squaring both sides may LEGALLY add a root", () => {
    // sqrt(x + 3) = x + 1 has the single root x = 1; squaring is a legal move
    // that introduces the extraneous x = -2. Flagging that would be a false
    // accusation, so the spurious-root test must not run on radicals at all.
    const check = checkStudentWork("\\sqrt{x + 3} = x + 1", "x = 1", [
      "x + 3 = (x + 1)^2",
      "x^2 + x - 2 = 0",
      "x = 1",
    ]);
    expect(check.status).not.toBe("error");
  });

  it("stands down when the verified answer is only a principal solution", () => {
    // sin(x) = 0.5 has infinitely many roots; the app reports one. The original's
    // own roots then can't match the verified set, so the test steps aside and
    // a legal rearrangement is never called an error.
    const check = checkStudentWork("\\sin(x) = 0.5", "x = 0.5236", [
      "\\sin(x) - 0.5 = 0",
    ]);
    expect(check.status).not.toBe("error");
  });

  it("stands down on an equation with the unknown in a denominator", () => {
    // Clearing the denominator is standard practice and legitimately changes the
    // root set (x = 0 appears), so this must not be reported as a mistake.
    const check = checkStudentWork("\\frac{6}{x} = 3", "x = 2", ["6 = 3x"]);
    expect(check.status).not.toBe("error");
  });

  it("checks a simultaneous system against the whole assignment", () => {
    const ok = checkStudentWork("x + y = 5", "x = 2, y = 3", ["y = 5 - x"]);
    expect(ok.status).toBe("ok");
    const bad = checkStudentWork("x + y = 5", "x = 2, y = 3", ["y = 5 + x"]);
    expect(bad.status).toBe("error");
  });

  it("skips lines it cannot decide instead of calling them wrong", () => {
    const check = checkStudentWork("2x + 5 = 13", "x = 4", [
      "\\text{subtract 5 from both sides}", // prose
      "2x", // a fragment, not an equation
      "2t = 8", // a free unknown the answer says nothing about
      "x = 4",
    ]);
    expect(check.status).toBe("ok");
    expect(check.checkedCount).toBe(1);
    expect(check.totalLines).toBe(4);
  });

  it("is honest when there is no verified answer to check against", () => {
    const check = checkStudentWork("2x + 5 = 13", "", ["2x = 8"]);
    expect(check.status).toBe("unknown");
    expect(check.reason).toContain("verified answer");
    expect(check.firstErrorLine).toBeNull();
  });

  it("is honest when nothing could be evaluated", () => {
    const check = checkStudentWork("2x + 5 = 13", "x = 4", [
      "\\text{I moved the 5 over}",
    ]);
    expect(check.status).toBe("unknown");
    expect(check.checkedCount).toBe(0);
  });

  it("is honest with no working at all", () => {
    expect(checkStudentWork("2x + 5 = 13", "x = 4", []).status).toBe("unknown");
  });
});

describe("checkStudentWork — expression problems", () => {
  it("passes a simplification that stays equal to the original", () => {
    const check = checkStudentWork("2(x + 3)", "2x + 6", [
      "2(x + 3)",
      "2x + 6",
    ]);
    expect(check.status).toBe("ok");
  });

  it("catches a distribution slip", () => {
    // The classic: multiplying only the first term.
    const check = checkStudentWork("2(x + 3)", "2x + 6", ["2x + 3"]);
    expect(check.status).toBe("error");
    expect(check.firstErrorLine).toBe(1);
  });

  it("checks BOTH sides of a chained arithmetic line", () => {
    const ok = checkStudentWork("\\frac{1}{2} + \\frac{1}{4}", "\\frac{3}{4}", [
      "\\frac{2}{4} + \\frac{1}{4} = \\frac{3}{4}",
    ]);
    expect(ok.status).toBe("ok");
    const bad = checkStudentWork("\\frac{1}{2} + \\frac{1}{4}", "\\frac{3}{4}", [
      "\\frac{1}{2} + \\frac{1}{4} = \\frac{2}{6}",
    ]);
    expect(bad.status).toBe("error");
  });

  it("does not need a verified answer for an expression", () => {
    // Equality to the original is the whole test — the answer is not consulted.
    expect(checkStudentWork("2(x + 3)", "", ["2x + 6"]).status).toBe("ok");
  });
});

describe("normalizeWorkLines", () => {
  it("trims, drops blanks and caps the line count", () => {
    expect(normalizeWorkLines(["  2x = 8 ", "", "   ", "x = 4"])).toEqual([
      "2x = 8",
      "x = 4",
    ]);
    const many = Array.from({ length: 40 }, (_, i) => `x = ${i}`);
    expect(normalizeWorkLines(many)).toHaveLength(MAX_WORK_LINES);
  });

  it("ignores non-arrays and non-strings", () => {
    expect(normalizeWorkLines(undefined)).toEqual([]);
    expect(normalizeWorkLines("2x = 8")).toEqual([]);
    expect(normalizeWorkLines([1, null, { a: 1 }])).toEqual([]);
  });
});

describe("buildWorkContext", () => {
  const lines = ["2x + 5 = 13", "2x = 9", "x = 4.5"];

  it("hands the model a verdict it may narrate but not overrule", () => {
    const check = checkStudentWork("2x + 5 = 13", "x = 4", lines);
    const context = buildWorkContext(lines, check);
    expect(context).toContain("Line 2: 2x = 9");
    expect(context).toContain("line 2 is the FIRST line");
    expect(context).toMatch(/NOT by you/);
    expect(context).toMatch(/do not re-derive/i);
  });

  it("forbids asserting right-or-wrong when the check could not run", () => {
    const check = checkStudentWork("2x + 5 = 13", "", lines);
    const context = buildWorkContext(lines, check);
    expect(context).toContain("could NOT check");
    expect(context).toMatch(/must NOT say any line is right or wrong/);
    expect(context).not.toContain("FIRST line");
  });

  it("reports what was checked rather than blanket approval", () => {
    const ok = checkStudentWork("2x + 5 = 13", "x = 4", ["2x = 8", "x = 4"]);
    const context = buildWorkContext(["2x = 8", "x = 4"], ok);
    expect(context).toContain("2 of 2");
    expect(context).toMatch(/do not claim the whole thing is right/i);
  });

  it("warns that the transcription itself may be wrong", () => {
    const check = checkStudentWork("2x + 5 = 13", "x = 4", lines);
    expect(buildWorkContext(lines, check)).toMatch(/OCR slips/);
  });

  it("is empty with no working", () => {
    expect(buildWorkContext([], checkStudentWork("x = 1", "x = 1", []))).toBe("");
  });
});

describe("coerceTutorImageRead", () => {
  it("keeps a well-formed problem read", () => {
    expect(
      coerceTutorImageRead({
        kind: "problem",
        problem: "2x + 5 = 13",
        work: [],
        note: "Clear photo.",
        confidence: 0.95,
      })
    ).toEqual({
      kind: "problem",
      problem: "2x + 5 = 13",
      work: [],
      note: "Clear photo.",
      confidence: 0.95,
    });
  });

  it("keeps handwritten working in the order it was written", () => {
    const read = coerceTutorImageRead({
      kind: "work",
      problem: "2x + 5 = 13",
      work: ["2x + 5 = 13", "2x = 9", "x = 4.5"],
    });
    expect(read.kind).toBe("work");
    expect(read.work).toEqual(["2x + 5 = 13", "2x = 9", "x = 4.5"]);
  });

  it("degrades an unknown kind to the honest branch", () => {
    expect(coerceTutorImageRead({ kind: "solved" }).kind).toBe("unreadable");
    expect(coerceTutorImageRead({}).kind).toBe("unreadable");
    expect(coerceTutorImageRead(null).kind).toBe("unreadable");
  });

  it("does not send an empty transcription off to be solved", () => {
    expect(
      coerceTutorImageRead({ kind: "problem", problem: "   ", work: [] }).kind
    ).toBe("unreadable");
  });

  it("treats 'work' with no working as a plain problem", () => {
    const read = coerceTutorImageRead({
      kind: "work",
      problem: "2x + 5 = 13",
      work: [],
    });
    expect(read.kind).toBe("problem");
  });

  it("repairs macros the model under-escaped, and caps the line count", () => {
    // JSON.parse turns a lone `\t` into a TAB before we ever see it.
    const read = coerceTutorImageRead({
      kind: "work",
      problem: "\text{Solve } 2x = 8",
      work: Array.from({ length: 30 }, (_, i) => `x = ${i}`),
    });
    expect(read.problem).toContain("\\text{Solve }");
    expect(read.work).toHaveLength(MAX_WORK_LINES);
  });

  it("clamps a nonsense confidence", () => {
    expect(coerceTutorImageRead({ kind: "notMath", confidence: 7 }).confidence).toBe(1);
    expect(coerceTutorImageRead({ kind: "notMath", confidence: -2 }).confidence).toBe(0);
    expect(coerceTutorImageRead({ kind: "notMath" }).confidence).toBe(0.9);
  });
});
