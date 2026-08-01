import { describe, it, expect } from "vitest";

import {
  hasLocaleAmbiguousNumber,
  parseNumericToken,
} from "../src/solver/nl/numeric";
import { readBoundValue, readUnitAnchoredValues } from "../src/solver/nl/quantity";

// The nl/ layer is the shared, domain-agnostic natural-language parsing used by the
// deterministic engines. These tests document its reusable contract directly (circle's
// suites exercise it in context; these pin the primitives themselves).

describe("nl/numeric — literal reading", () => {
  it("parses integers, decimals, fractions, and mixed numbers", () => {
    expect(parseNumericToken("7")).toBe(7);
    expect(parseNumericToken("3.5")).toBe(3.5);
    expect(parseNumericToken("3/4")).toBe(0.75);
    expect(parseNumericToken("2 1/2")).toBe(2.5);
    expect(parseNumericToken("45/2")).toBe(22.5);
  });
  it("returns null on a zero denominator or garbage", () => {
    expect(parseNumericToken("1/0")).toBeNull();
    expect(parseNumericToken("abc")).toBeNull();
  });
});

describe("nl/numeric — locale-ambiguous comma", () => {
  it("flags a comma glued between digits (thousands vs decimal)", () => {
    expect(hasLocaleAmbiguousNumber("radius 1,000 cm")).toBe(true);
    expect(hasLocaleAmbiguousNumber("radius 12,5 cm")).toBe(true);
  });
  it("does NOT flag a clause comma or a spaced list", () => {
    expect(hasLocaleAmbiguousNumber("a circle, radius 7 cm")).toBe(false);
    expect(hasLocaleAmbiguousNumber("radii 3, 4, or 5")).toBe(false);
  });
});

describe("nl/quantity — anchor-based value binding", () => {
  it("adjacency: reads the value sitting on the name through connectors", () => {
    expect(readBoundValue("radius 7 cm", "radius")?.value).toBe(7);
    expect(readBoundValue("radius of 7", "radius")?.value).toBe(7);
    expect(readBoundValue("radius = 7 cm", "radius")?.value).toBe(7);
  });
  it("predication: skips an interposed distractor number, takes the asserted value", () => {
    // "seating 4 people is 120" → 120, never the distractor 4.
    expect(
      readBoundValue("diameter of a table seating 4 people is 120 cm", "diameter")?.value
    ).toBe(120);
  });
  it("a value walled off by a comma-parenthetical stays unbound (→ null)", () => {
    expect(readBoundValue("diameter, on a 4 mm grid, is 20 cm", "diameter")).toBeNull();
  });
  it("captures a trailing unit when unitSrc is given", () => {
    const r = readBoundValue("radius 7 cm", "radius", { unitSrc: "cm|mm|m" });
    expect(r?.value).toBe(7);
    expect(r?.unitRaw).toBe("cm");
  });
});

describe("nl/quantity — unit-anchored collection", () => {
  const degOpts = {
    unitSrc: String.raw`°|degrees?|deg\b`,
    disqualifyTrailer: String.raw`\s*(?:north|south|east|west|[nsew]\b|celsius|centigrade|fahrenheit|[cf]\b)`,
    distractorCtx: /\b(?:bearing|latitude|temperature)\b/i,
  };
  it("collects every degree-marked number", () => {
    expect(readUnitAnchoredValues("marked 120° and 75 degrees", degOpts)).toEqual([120, 75]);
  });
  it("excludes bearing/temperature contexts and compass/thermal trailers", () => {
    expect(readUnitAnchoredValues("angle 90 at the centre, bearing of 60 degrees", degOpts)).toEqual([]);
    expect(readUnitAnchoredValues("heading 35 degrees north", degOpts)).toEqual([]);
    expect(readUnitAnchoredValues("300 degrees celsius", degOpts)).toEqual([]);
  });
});
