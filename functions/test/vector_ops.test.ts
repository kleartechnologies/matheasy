// The vector geometry the problem sheets actually ask for, beyond the
// dot/cross/magnitude the engine already had: sums, unit vectors, angles,
// projections, the scalar triple product, coplanarity, midpoints, section
// points, the distance from the origin to a line, and resolving a magnitude +
// direction into components.
//
// Every one is gated on a PROPERTY rather than on one library's word: the
// remainder of a projection is proven perpendicular, the section point is proven
// both collinear and in the stated ratio, the triple product is computed three
// independent ways, and the foot of a perpendicular is proven perpendicular.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("vector operations are deterministic — the LLM must not be called");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { op: c.vectorOp, type: c.problemType, verified: p.verified, plain: p.finalAnswer?.plain };
}

/** The numbers inside a `(a, b, c)` answer, so a test asserts the VECTOR rather
 * than the last digit of a decimal expansion. */
function comps(plain: string | undefined): number[] {
  return (plain ?? "").replace(/[()]/g, "").split(",").map((s) => Number(s.trim()));
}

describe("sums, differences, unit vectors", () => {
  it("adds two vectors", async () => {
    const r = await run(String.raw`\text{Find } (1, 2, 3) + (4, 5, 6)`);
    expect(r).toMatchObject({ op: "add", verified: true, plain: "(5, 7, 9)" });
  });

  it("subtracts two vectors", async () => {
    const r = await run(String.raw`\text{Find } (5, 7, 9) - (1, 2, 3)`);
    expect(r).toMatchObject({ op: "subtract", verified: true, plain: "(4, 5, 6)" });
  });

  it("the unit vector in the direction of (3,4)", async () => {
    const r = await run(String.raw`\text{Find the unit vector in the direction of } (3, 4)`);
    expect(r).toMatchObject({ op: "unit", verified: true, plain: "(0.6, 0.8)" });
  });

  it("the zero vector has no direction — decline, never (NaN, NaN)", async () => {
    const r = await run(String.raw`\text{Find the unit vector in the direction of } (0, 0)`);
    expect(r.verified).not.toBe(true);
  });
});

describe("angles and projections", () => {
  it("perpendicular axes meet at 90°", async () => {
    const r = await run(String.raw`\text{Find the angle between } (1, 0, 0) \text{ and } (0, 1, 0)`);
    expect(r).toMatchObject({ op: "angle", verified: true, plain: "90 degrees" });
  });

  it("(1,0) and (1,1) meet at 45°", async () => {
    const r = await run(String.raw`\text{Find the angle between } (1, 0) \text{ and } (1, 1)`);
    expect(r.verified).toBe(true);
    expect(Number((r.plain ?? "").split(" ")[0])).toBeCloseTo(45, 8);
  });

  it("opposite vectors meet at 180°, not -180°", async () => {
    const r = await run(String.raw`\text{Find the angle between } (1, 0) \text{ and } (-1, 0)`);
    expect(r).toMatchObject({ verified: true, plain: "180 degrees" });
  });

  it("projects a onto b", async () => {
    const r = await run(String.raw`\text{Find the projection of } (3, 4) \text{ onto } (1, 0)`);
    expect(r).toMatchObject({ op: "projection", verified: true, plain: "(3, 0)" });
  });

  it("the projection onto a non-axis direction", async () => {
    // proj_b a = (a·b / b·b) b = (3/2)(1,1) = (1.5, 1.5)
    const r = await run(String.raw`\text{Find the component of } (2, 1) \text{ along } (1, 1)`);
    expect(r).toMatchObject({ op: "projection", verified: true, plain: "(1.5, 1.5)" });
  });
});

describe("scalar triple product and coplanarity", () => {
  it("the triple product of the standard basis is 1", async () => {
    const r = await run(
      String.raw`\text{Find the scalar triple product of } (1, 0, 0), (0, 1, 0) \text{ and } (0, 0, 1)`
    );
    expect(r).toMatchObject({ op: "triple", verified: true, plain: "1" });
  });

  it("the volume of the parallelepiped", async () => {
    const r = await run(
      String.raw`\text{Find the volume of the parallelepiped with edges } (2, 0, 0), (0, 3, 0) \text{ and } (0, 0, 4)`
    );
    expect(r).toMatchObject({ verified: true, plain: "24" });
  });

  it("two parallel vectors force coplanarity", async () => {
    const r = await run(
      String.raw`\text{Are } (1, 2, 3), (2, 4, 6) \text{ and } (1, 1, 1) \text{ coplanar?}`
    );
    expect(r).toMatchObject({
      op: "coplanar",
      verified: true,
      plain: "Yes — they are coplanar",
    });
  });

  it("says NO when they are not coplanar, rather than hedging", async () => {
    const r = await run(
      String.raw`\text{Are } (1, 0, 0), (0, 1, 0) \text{ and } (0, 0, 1) \text{ coplanar?}`
    );
    expect(r).toMatchObject({ verified: true, plain: "No — they are not coplanar" });
  });
});

describe("points on a line: midpoint, section, distance from the origin", () => {
  it("the midpoint of AB", async () => {
    const r = await run(String.raw`\text{Find the midpoint of } (1, 2, 3) \text{ and } (5, 6, 7)`);
    expect(r).toMatchObject({ op: "midpoint", verified: true, plain: "(3, 4, 5)" });
  });

  it("the point dividing AB in the ratio 2 : 3", async () => {
    const r = await run(
      String.raw`\text{Find the point dividing } (0, 0, 0) \text{ and } (5, 10, 15) \text{ in the ratio } 2 : 3`
    );
    expect(r).toMatchObject({ op: "section", verified: true, plain: "(2, 4, 6)" });
  });

  it("the ratio matters — 3 : 2 is the OTHER point", async () => {
    const r = await run(
      String.raw`\text{Find the point dividing } (0, 0, 0) \text{ and } (5, 10, 15) \text{ in the ratio } 3 : 2`
    );
    expect(r).toMatchObject({ verified: true, plain: "(3, 6, 9)" });
  });

  it("a section question with no ratio stated declines", () => {
    const c = classify(
      String.raw`\text{Find the point dividing } (0, 0, 0) \text{ and } (5, 10, 15) \text{ in a given ratio}`
    );
    expect(c.vectorOp).toBeUndefined();
  });

  it("the shortest distance from the origin to the line AB", async () => {
    const r = await run(
      String.raw`\text{Find the shortest distance from the origin to the line through } (1, 0, 0) \text{ and } (1, 1, 0)`
    );
    expect(r).toMatchObject({ op: "distance_origin_line", verified: true, plain: "1" });
  });

  it("the perpendicular distance when the foot is not an endpoint", async () => {
    // Line through (1,0) and (0,1): x + y = 1, distance from O is 1/√2.
    const r = await run(
      String.raw`\text{Find the perpendicular distance from the origin to the line through } (1, 0) \text{ and } (0, 1)`
    );
    expect(r.verified).toBe(true);
    expect(Number(r.plain)).toBeCloseTo(Math.SQRT1_2, 8);
  });
});

describe("resolving a magnitude and a direction into components", () => {
  it("a force of magnitude 10 at 30° to the x-axis", async () => {
    const r = await run(
      String.raw`\text{A force of magnitude 10 acts at } 30^\circ \text{ to the x-axis. Find its components.}`
    );
    expect(r).toMatchObject({ op: "resolve", verified: true });
    const [x, y] = comps(r.plain);
    expect(x).toBeCloseTo(10 * Math.cos(Math.PI / 6), 8);
    expect(y).toBeCloseTo(5, 8);
  });

  it("an angle given as π/3 rather than in degrees", async () => {
    const r = await run(
      String.raw`\text{Resolve a velocity of magnitude 4 at an angle } \pi/3 \text{ into components}`
    );
    expect(r.verified).toBe(true);
    const [x, y] = comps(r.plain);
    expect(x).toBeCloseTo(2, 8);
    expect(y).toBeCloseTo(4 * Math.sin(Math.PI / 3), 8);
  });

  it("no angle stated — decline rather than assume the x-axis", () => {
    const c = classify(String.raw`\text{Find the components of a force of magnitude 10}`);
    expect(c.vectorOp).toBeUndefined();
  });
});

describe("vectors written in the ijk basis", () => {
  it("reads 3i + 4j, which the bracket parser cannot see at all", async () => {
    const r = await run(String.raw`\text{Find the magnitude of } 3\mathbf{i} + 4\mathbf{j}`);
    expect(r).toMatchObject({ op: "magnitude", verified: true, plain: "5" });
  });

  it("a bare k means 1k, and a bare -k means -1k", async () => {
    const r = await run(
      String.raw`\text{Find } \mathbf{a} \cdot \mathbf{b} \text{ where } \mathbf{a} = 2\mathbf{i} + 3\mathbf{j} - \mathbf{k} \text{ and } \mathbf{b} = \mathbf{i} - \mathbf{j} + 4\mathbf{k}`
    );
    expect(r).toMatchObject({ op: "dot", verified: true, plain: "-5" });
  });

  it("an UNDECORATED i is refused — in this app it is the imaginary unit", () => {
    const c = classify(String.raw`\text{Find the magnitude of } 3i + 4j`);
    expect(c.vectorOp).toBeUndefined();
  });
});

// The pre-existing vector behaviour must not shift now that the block runs
// earlier in classify().
describe("no regression on the ops that already worked", () => {
  it("dot product", async () => {
    const r = await run(String.raw`(1,2,3) \cdot (4,5,6)`);
    expect(r).toMatchObject({ op: "dot", verified: true, plain: "32" });
  });

  it("cross product", async () => {
    const r = await run(String.raw`(1,0,0) \times (0,1,0)`);
    expect(r).toMatchObject({ op: "cross", verified: true, plain: "(0, 0, 1)" });
  });

  it("magnitude", async () => {
    const r = await run(String.raw`magnitude of (3,4)`);
    expect(r).toMatchObject({ op: "magnitude", verified: true, plain: "5" });
  });

  it("'length of the interval (2, 5)' is still not a magnitude", () => {
    const c = classify(String.raw`length of the interval (2, 5)`);
    expect(c.vectorOp).toBeUndefined();
  });

  it("'sum of vectors … and …' still declines — no explicit connective", () => {
    const c = classify(String.raw`sum of vectors (1, 2, 3) and (4, 5, 6)`);
    expect(c.vectorOp).toBeUndefined();
  });
});
