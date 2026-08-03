// The shortest distance between two lines in space. Four vectors and two lines,
// so no existing vector op could reach it — the sheet question fell through to
// the tutor as "multi_part", which is not an answer.
//
// Which of the four vectors is a POINT and which is a DIRECTION is the entire
// question: read them backwards and the answer is a different number that looks
// exactly as plausible. So the role comes from the words in front of each
// vector, and a line that names neither is declined.
//
// The gate shares no step with the answer. The closed form uses a cross product;
// the proof MINIMISES the gap between the two lines numerically over both
// parameters, touching no cross product at all, and then checks that the
// joining segment at that minimum really is perpendicular to both lines.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solveDeterministic } from "../src/solver/deterministic";

function run(latex: string): { type: string; answer: string | null } {
  const cls = classify(latex);
  const cand = solveDeterministic(cls);
  return {
    type: cls.problemType,
    answer: cand && cand.verify() ? (cand.answer.plain ?? null) : null,
  };
}

describe("skew lines", () => {
  it("the sheet question, as a point and a direction each", () => {
    // d₁ × d₂ = (−1, −2, 4); (P₂ − P₁)·n = 3; |n| = √21 ⇒ 3/√21 = √21/7.
    const r = run(
      String.raw`\text{Find the shortest distance between the line through } (1, 3, 0) \text{ with direction } (2, 3, 2) \text{ and the line through } (2, 1, 0) \text{ with direction } (0, 2, 1)`
    );
    expect(r.type).toBe("vector_line_distance");
    expect(r.answer).toBe("√21/7");
  });

  it("the same lines written parametrically", () => {
    // `+ s(` names a direction as plainly as the word does — and then the other
    // vector of that line must be the point.
    const r = run(
      String.raw`\text{Find the shortest distance between the lines } r = (1,3,0) + s(2,3,2) \text{ and } r = (2,1,0) + t(0,2,1)`
    );
    expect(r.answer).toBe("√21/7");
  });

  it("a textbook pair with a large answer", () => {
    const r = run(
      String.raw`\text{Find the shortest distance between the line through } (3,8,3) \text{ with direction } (3,-1,1) \text{ and the line through } (-3,-7,6) \text{ with direction } (-3,2,4)`
    );
    expect(r.answer).toBe("3√30");
  });

  it("intersecting lines are zero apart, not 'no answer'", () => {
    const r = run(
      String.raw`\text{Find the shortest distance between the line through } (0,0,0) \text{ with direction } (1,0,0) \text{ and the line through } (0,0,0) \text{ with direction } (0,1,0)`
    );
    expect(r.answer).toBe("0");
  });
});

describe("parallel lines — a different formula, and it matters", () => {
  it("d₁ × d₂ vanishes, so the perpendicular formula would divide by nothing", () => {
    // The x-axis and the line x ↦ (2x, 3, 4): 3-4-5, so the gap is 5.
    const r = run(
      String.raw`\text{Find the distance between the parallel lines through } (0,0,0) \text{ with direction } (1,0,0) \text{ and through } (0,3,4) \text{ with direction } (2,0,0)`
    );
    expect(r.type).toBe("vector_line_distance");
    expect(r.answer).toBe("5");
  });

  it("two names for the same line are zero apart", () => {
    const r = run(
      String.raw`\text{Find the distance between the line through } (1,1,1) \text{ with direction } (1,2,3) \text{ and the line through } (2,3,4) \text{ with direction } (2,4,6)`
    );
    expect(r.answer).toBe("0");
  });
});

describe("what it declines", () => {
  it("a 'line' with no direction at all", () => {
    const r = run(
      String.raw`\text{Find the shortest distance between the line through } (1,2,3) \text{ with direction } (0,0,0) \text{ and the line through } (4,5,6) \text{ with direction } (1,1,1)`
    );
    expect(r.answer).toBeNull();
  });

  it("four vectors with no role named anywhere", () => {
    // Nothing says which is a point and which is a direction. Picking an order
    // and answering would be answering a question that was never asked.
    const r = run(
      String.raw`\text{Find the shortest distance between the lines } (1,3,0), (2,3,2) \text{ and } (2,1,0), (0,2,1)`
    );
    expect(r.answer).toBeNull();
  });

  it("only three vectors — one of the lines is incomplete", () => {
    const r = run(
      String.raw`\text{Find the shortest distance between the line through } (1,3,0) \text{ with direction } (2,3,2) \text{ and the line through } (2,1,0)`
    );
    expect(r.answer).toBeNull();
  });
});

describe("no regression — the distance questions that already worked", () => {
  it("distance from the ORIGIN to a line keeps its own engine", () => {
    const cls = classify(
      String.raw`\text{Find the shortest distance from the origin to the line through } (1,2,3) \text{ and } (4,5,6)`
    );
    expect(cls.problemType).toBe("vector_distance_origin_line");
  });

  it("the midpoint of two points is not a line question", () => {
    const cls = classify(String.raw`\text{Find the midpoint of } (1,2,3) \text{ and } (4,5,6)`);
    expect(cls.problemType).toBe("vector_midpoint");
  });

  it("the angle between two vectors is untouched", () => {
    const cls = classify(
      String.raw`\text{Find the angle between } (1,0,0) \text{ and } (0,1,0)`
    );
    expect(cls.problemType).toBe("vector_angle");
  });
});
