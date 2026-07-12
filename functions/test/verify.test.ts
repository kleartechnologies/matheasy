import { describe, expect, it } from "vitest";
import {
  evalReal,
  stripIntegrationConstant,
  verifyDerivative,
  verifyEquality,
  verifyRoots,
  verifySolution,
} from "../src/solver/verify";

describe("evalReal", () => {
  it("evaluates arithmetic and substitutes variables", () => {
    expect(evalReal("3/4 + 1/2")).toBeCloseTo(1.25, 9);
    expect(evalReal("5x^2 + 3x - 2", { x: -1 })).toBeCloseTo(0, 9);
  });
  it("returns NaN for undefined symbols or garbage", () => {
    expect(Number.isNaN(evalReal("x + 1"))).toBe(true);
    expect(Number.isNaN(evalReal(")(("))).toBe(true);
  });
});

describe("verifyRoots — the gate", () => {
  const q = [{ lhs: "5x^2 + 3x - 2", rhs: "0" }];
  it("accepts correct roots", () => {
    expect(verifyRoots(q, "x", [-1, 0.4])).toBe(true);
  });
  it("REJECTS a wrong root", () => {
    expect(verifyRoots(q, "x", [-1, 0.5])).toBe(false);
  });
  it("rejects an empty root set", () => {
    expect(verifyRoots(q, "x", [])).toBe(false);
  });
  it("rejects a wrong linear answer", () => {
    expect(verifyRoots([{ lhs: "2x + 5", rhs: "15" }], "x", [4])).toBe(false);
    expect(verifyRoots([{ lhs: "2x + 5", rhs: "15" }], "x", [5])).toBe(true);
  });
});

describe("verifySolution — systems", () => {
  const system = [
    { lhs: "2x + 3y", rhs: "6" },
    { lhs: "x - y", rhs: "3" },
  ];
  it("accepts a solution satisfying every equation", () => {
    expect(verifySolution(system, { x: 3, y: 0 })).toBe(true);
  });
  it("rejects a solution that fails one equation", () => {
    expect(verifySolution(system, { x: 0, y: 2 })).toBe(false);
  });
  it("rejects when a variable is missing", () => {
    expect(verifySolution(system, { x: 3 })).toBe(false);
  });
});

describe("verifyEquality — simplify", () => {
  it("accepts an equivalent simplification", () => {
    expect(verifyEquality("2x + 3x + 5", "5*(x + 1)", ["x"])).toBe(true);
    expect(verifyEquality("2x + 3x + 5", "5x + 5", ["x"])).toBe(true);
  });
  it("rejects a non-equivalent expression", () => {
    expect(verifyEquality("2x + 3x + 5", "5x + 6", ["x"])).toBe(false);
  });
});

describe("verifyDerivative", () => {
  it("accepts the correct derivative", () => {
    expect(verifyDerivative("sqrt(2)*x + sin(3*x)", "3*cos(3*x) + sqrt(2)", "x")).toBe(
      true
    );
  });
  it("rejects a wrong derivative", () => {
    expect(verifyDerivative("x^3 + 2x", "3*x^2 + 3", "x")).toBe(false);
    expect(verifyDerivative("x^3 + 2x", "3*x^2 + 2", "x")).toBe(true);
  });
});

describe("stripIntegrationConstant", () => {
  it("drops a trailing + C", () => {
    expect(stripIntegrationConstant("x^2/2 + C")).toBe("x^2/2");
    expect(stripIntegrationConstant("sin(x) - C")).toBe("sin(x)");
    expect(stripIntegrationConstant("x^2/2")).toBe("x^2/2");
  });
});
