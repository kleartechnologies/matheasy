// Failure-analytics pure helpers: rolling classify types up to a domain, and
// sorting the aggregate counters for the "most common unsolved types" report.
import { describe, expect, it } from "vitest";
import { topicForProblemType } from "../src/lib/firestore";
import { sortedCounts } from "../src/analytics/solveFailureReport";

describe("topicForProblemType", () => {
  it("rolls classify's problemTypes up to a math domain", () => {
    expect(topicForProblemType("linear_equation")).toBe("algebra");
    expect(topicForProblemType("quadratic_equation")).toBe("algebra");
    expect(topicForProblemType("exponential_equation")).toBe("algebra");
    expect(topicForProblemType("system_of_equations")).toBe("algebra");
    expect(topicForProblemType("trigonometric_equation")).toBe("trigonometry");
    expect(topicForProblemType("integral")).toBe("calculus");
    expect(topicForProblemType("definite_integral")).toBe("calculus");
    expect(topicForProblemType("derivative")).toBe("calculus");
    expect(topicForProblemType("something_new")).toBe("other");
  });
});

describe("sortedCounts", () => {
  it("returns {key,count} descending, dropping zero/negative and junk", () => {
    expect(sortedCounts({ algebra: 3, calculus: 10, trigonometry: 0 })).toEqual([
      { key: "calculus", count: 10 },
      { key: "algebra", count: 3 },
    ]);
  });

  it("tolerates a missing / malformed aggregate field", () => {
    expect(sortedCounts(undefined)).toEqual([]);
    expect(sortedCounts(null)).toEqual([]);
    expect(sortedCounts("nope")).toEqual([]);
    expect(sortedCounts({})).toEqual([]);
  });
});
