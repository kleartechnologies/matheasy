import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { parseCircle, solveCircle } from "../src/solver/circle";
import { JsonCompleter } from "../src/solver/narrate";

// The circle-mensuration engine is DETERMINISTIC: exact π-form answers whose
// rendered coefficient is re-checked against an independent numeric recompute.
// The LLM is never called for the math — this completer proves it (any call
// throws), so an end-to-end route that DECLINES surfaces as a thrown completer.
const NEVER: JsonCompleter = async () => {
  throw new Error("the circle engine must not call the LLM");
};

/** End-to-end: classify → solve. A declined circle problem falls through to the
 * llm_candidate tier, where NEVER throws — caught here as `declined: true`. */
async function run(latex: string) {
  const cls = classify(latex);
  try {
    const payload = await solve(cls, NEVER);
    return { strategy: cls.strategy, payload, declined: false as const };
  } catch {
    return { strategy: cls.strategy, payload: null, declined: true as const };
  }
}

describe("parseCircle — strict parse gate", () => {
  it("reads area from a named radius", () => {
    const s = parseCircle("Find the area of a circle with radius 7 cm")!;
    expect(s.target).toBe("area");
    expect(s.radius).toBe(7);
    expect(s.givenKind).toBe("radius");
    expect(s.unit).toBe("cm");
  });

  it("halves a given diameter into the radius", () => {
    const s = parseCircle("Calculate the area of a circle with diameter 10 cm")!;
    expect(s.target).toBe("area");
    expect(s.radius).toBe(5);
    expect(s.givenKind).toBe("diameter");
    expect(s.givenValue).toBe(10);
  });

  it("reads an arc-length central angle in degrees", () => {
    const s = parseCircle(
      "Find the arc length of a circle of radius 6 with a central angle of 60 degrees"
    )!;
    expect(s.target).toBe("arc_length");
    expect(s.radius).toBe(6);
    expect(s.angleDeg).toBe(60);
  });

  it("finds the diameter as a target from a radius given (not the diameter given)", () => {
    const s = parseCircle("A circle has radius 5. Find its diameter.")!;
    expect(s.target).toBe("diameter");
    expect(s.radius).toBe(5);
    expect(s.givenKind).toBe("radius");
  });

  it("declines a non-circle shape", () => {
    expect(parseCircle("Find the area of a square with side 7")).toBeNull();
  });

  it("declines an inscribed/circumscribed compound figure", () => {
    expect(
      parseCircle("A triangle is inscribed in a circle of radius 7. Find its area.")
    ).toBeNull();
  });

  it("declines when BOTH radius and diameter are separately named", () => {
    expect(
      parseCircle("A circle has radius 7 and diameter 10. Find its area.")
    ).toBeNull();
  });

  it("declines when two distinct targets are asked", () => {
    expect(
      parseCircle("Find the area and circumference of a circle with radius 7")
    ).toBeNull();
  });

  it("declines the inverse problem (find radius from area)", () => {
    expect(parseCircle("The area of a circle is 50. Find its radius.")).toBeNull();
  });

  it("declines arc/sector without an explicit angle", () => {
    expect(
      parseCircle("Find the arc length of a circle of radius 6")
    ).toBeNull();
  });

  it("declines a non-circle prompt entirely", () => {
    expect(parseCircle("Solve 2x + 5 = 15")).toBeNull();
  });
});

describe("solveCircle — exact π-form + internal verify", () => {
  it("area r=7 → 49π", () => {
    const out = solveCircle(parseCircle("area of a circle with radius 7")!)!;
    expect(out.answer.plain.startsWith("49π")).toBe(true);
  });

  it("circumference r=5 → 10π", () => {
    const out = solveCircle(
      parseCircle("circumference of a circle with radius 5")!
    )!;
    expect(out.answer.plain.startsWith("10π")).toBe(true);
  });

  it("sector area r=6, θ=90° → 9π", () => {
    const out = solveCircle(
      parseCircle("sector area of a circle radius 6 with central angle 90 degrees")!
    )!;
    expect(out.answer.plain.startsWith("9π")).toBe(true);
  });

  it("diameter target has no π (d = 2r = 10)", () => {
    const out = solveCircle(
      parseCircle("A circle has radius 5. Find its diameter.")!
    )!;
    expect(out.answer.plain).toBe("10");
  });
});

describe("circle route — verified exact answers", () => {
  it("area r=7 cm → 49π cm² ≈ 153.938 cm²", async () => {
    const { strategy, payload } = await run(
      "Find the area of a circle with radius 7 cm"
    );
    expect(strategy).toBe("circle");
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain).toBe("49π cm² ≈ 153.938 cm²");
  });

  it("circumference r=5 m → 10π m ≈ 31.4159 m", async () => {
    const { payload } = await run(
      "What is the circumference of a circle with radius 5 m?"
    );
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain).toBe("10π m ≈ 31.4159 m");
  });

  it("area from diameter 10 cm → 25π cm² ≈ 78.5398 cm²", async () => {
    const { strategy, payload } = await run(
      "Calculate the area of a circle with diameter 10 cm"
    );
    expect(strategy).toBe("circle");
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain).toBe("25π cm² ≈ 78.5398 cm²");
  });

  it("arc length r=6, θ=60° → 2π ≈ 6.2832", async () => {
    const { payload } = await run(
      "Find the arc length of a circle of radius 6 with a central angle of 60 degrees"
    );
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain).toBe("2π ≈ 6.2832");
  });
});

describe("circle route — honest declines (never a wrong answer)", () => {
  it("a non-circle shape does not take the circle route", async () => {
    const { strategy } = await run("Find the area of a square with side 7");
    expect(strategy).not.toBe("circle");
  });

  it("both radius and diameter given → declines the circle route", async () => {
    const { strategy } = await run(
      "A circle has radius 7 and diameter 10. Find its area."
    );
    expect(strategy).not.toBe("circle");
  });

  it("two targets asked → declines the circle route", async () => {
    const { strategy } = await run(
      "Find the area and circumference of a circle with radius 7"
    );
    expect(strategy).not.toBe("circle");
  });
});

// Regression: the adversarial gate found 25 golden-rule violations, all in the
// PARSER (wrong radius/angle/unit read, or a bare-circle answer for a non-circle
// figure). These lock in the root-cause fixes and guard the legitimate cases that
// must keep resolving.
describe("circle route — gate regressions (fractions / mixed / units)", () => {
  const correct: [string, string][] = [
    ["Find the area of a circle with radius \\frac{1}{2} cm", "1/4 π cm² ≈ 0.7854 cm²"],
    ["Find the area of a circle with radius 3/4 cm", "9/16 π cm² ≈ 1.7671 cm²"],
    ["Find the area of a circle with diameter 9/2 cm", "81/16 π cm² ≈ 15.9043 cm²"],
    ["Find the area of a circle with radius 2\\frac{1}{2} cm", "25/4 π cm² ≈ 19.635 cm²"],
    // Ordinal label "circle 2" must NOT be read as the radius (true r = 5).
    ["The radius of circle 2 is 5 cm. Find its area.", "25π cm² ≈ 78.5398 cm²"],
    // A distractor length ("2 m") must not steal the unit from the real given.
    [
      "A path 2 m wide runs past a circle of radius 14 cm; find the circumference of the circle",
      "28π cm ≈ 87.9646 cm",
    ],
  ];
  for (const [latex, expected] of correct) {
    it(`${latex} → ${expected}`, async () => {
      const { strategy, payload } = await run(latex);
      expect(strategy).toBe("circle");
      expect(payload?.verified).toBe(true);
      expect(payload?.finalAnswer?.plain).toBe(expected);
    });
  }
});

describe("circle route — gate regressions (radian angles decline)", () => {
  const radianDeclines = [
    "Find the arc length of a circle with radius 6 cm and central angle of \\pi/3 radians",
    "Find the sector area of a circle with radius 12 cm and central angle 2\\pi/3 radians",
    "Find the area of a sector of a circle radius 10 with central angle 1 radian",
    "Find the sector area of a circle with radius 6 and central angle π/3 radians",
    "Find the arc length of a circle with radius 9, angle pi/2 radians",
    "Find the arc length of a circle with radius 12 cm and central angle of pi/4 radians",
  ];
  for (const latex of radianDeclines) {
    it(`declines: ${latex}`, async () => {
      const { strategy } = await run(latex);
      expect(strategy).not.toBe("circle");
    });
  }

  // A degree angle beside a "take π = 3.14" clause must still resolve (π-as-value
  // is not a radian angle).
  it("degree angle + 'take π = 3.14' clause still resolves", async () => {
    const { strategy, payload } = await run(
      "Find the sector area of a circle with radius 10, central angle 45 degrees, take pi = 3.14"
    );
    expect(strategy).toBe("circle");
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain?.startsWith("25/2 π")).toBe(true);
  });
});

describe("circle route — gate regressions (partial/compound figures decline)", () => {
  const shapeDeclines = [
    "Find the area of a semi-circle with radius 7 cm",
    "Find the area of a quadrant of a circle with radius 8 cm",
    "Find the area of the shaded region between a circle of radius 7 cm and a circle of radius 3 cm",
    "Find the perimeter of a half circle with radius 7 cm",
    "Find the area of a half circle with radius 6 cm",
    "Find the area of the minor segment of a circle of radius 10 cm with central angle 90 degrees",
    "Find the area between two concentric circles of radius 5 cm and radius 10 cm",
  ];
  for (const latex of shapeDeclines) {
    it(`declines: ${latex}`, async () => {
      const { strategy } = await run(latex);
      expect(strategy).not.toBe("circle");
    });
  }
});

// Regression: the SECOND adversarial gate (post fraction/mixed/unit hardening)
// found 6 more golden-rule violations — a "whole circle" ask absorbing a sector's
// θ/360 factor, a fraction-of-circle ("half OF the circle", "cut in half") slipping
// the partial-figure guard and getting a bare full-circle answer, and a tiny radius
// whose EXACT π-coefficient rounded wrong for display (0.000002π ≠ πr²). Each must
// now DECLINE rather than ship the confidently-wrong number.
describe("circle route — gate-2 regressions (whole-circle / fraction-of-circle / tiny coefficient decline)", () => {
  const declines = [
    // Whole/entire/total-circle ask beside a sector clause is ambiguous → decline
    // (the θ/360 sector factor must NOT be applied to a whole-circle ask).
    "Find the area of the whole circle of radius 10 cm, given a sector with central angle 120 degrees.",
    "Find the area of the entire circle of radius 5 cm, given a sector with central angle 45 degrees",
    "Find the total area of the circle of radius 6 cm with a sector of central angle 60 degrees",
    // Fraction-of-circle with an interposed "of", or a physical cut → semicircle /
    // quadrant, not a whole circle. A bare πr² / 2πr answer would be wrong.
    "Find the area of half of the circle with radius 7 cm",
    "Find the area of half of a circle with radius 7 cm",
    "Find the area of a quarter of the circle with radius 8 cm",
    "Find the area of one quarter of a circle with radius 10 cm",
    "Find the perimeter of half of the circle with radius 7 cm",
    "A circle of radius 7 cm is cut in half. Find the area.",
    "A circle of radius 8 cm is cut into two halves. Find the area.",
    // A sub-1e-6 exact coefficient cannot be displayed faithfully at 6 s.f. and its
    // 4-d.p. decimal collapses to 0 → the rendered-coefficient gate declines.
    "area of a circle radius 0.001234567 cm",
  ];
  for (const latex of declines) {
    it(`declines: ${latex}`, async () => {
      const { strategy, payload } = await run(latex);
      const shippedVerifiedCircle =
        strategy === "circle" && payload?.verified === true;
      expect(shippedVerifiedCircle).toBe(false);
    });
  }

  // The legitimate neighbours must KEEP resolving — the fixes are precise, not a
  // blanket retreat. A plain sector (no "whole/entire"), and a small-but-showable
  // radius, still verify.
  it("a plain sector (no whole-circle qualifier) still resolves", async () => {
    const { strategy, payload } = await run(
      "What is the sector area of a circle radius 10 cm with central angle 120 degrees?"
    );
    expect(strategy).toBe("circle");
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain).toBe("100/3 π cm² ≈ 104.7198 cm²");
  });

  it("a small-but-showable radius (0.5 m) still resolves", async () => {
    const { strategy, payload } = await run("circumference of a circle radius 0.5 m");
    expect(strategy).toBe("circle");
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain).toBe("π m ≈ 3.1416 m");
  });
});

// Regression: the THIRD adversarial gate (on the freshly-wired circle route)
// confirmed 13 more golden-rule violations across four root causes —
//  (C1) a distractor number parked in a comma parenthetical between the keyword
//       and the true value ("radius, on the 2 cm grid, of 8 cm") stolen as the given;
//  (C2) "area OF THE CIRCLE" beside a sector clause silently answered as the
//       sector's θ/360 area, and the annular "area of the PATH" answered as πr²;
//  (C3) a radian angle (2π/3, π/3, ASCII "pi/3") misread as a bare degree count
//       once a "take π = 3.14" / "π = 22/7" clause disabled the radian guard;
//  (C4) the ADJECTIVE partial figures (semi-/quarter-circular) and pluralised
//       fractions (three quarters / two-thirds) leaking a bare full-circle answer.
// Each must now DECLINE (or, where the ask is unambiguous, ship the CORRECT value).
describe("circle route — gate-3 regressions (distractor / target / radian / partial)", () => {
  // C1 — a comma-parenthetical distractor must never be read as the given → decline.
  const distractorDeclines = [
    "A circle has radius, measured on the 2 cm grid, of 8 cm. Find the area.",
    "A circle has diameter, drawn on the 2 cm grid, of 10 cm. Find the area.",
    "Find the area of a circle whose diameter, on a 4 mm grid, is 20 cm.",
  ];
  for (const latex of distractorDeclines) {
    it(`C1 declines distractor-given: ${latex}`, async () => {
      const { strategy, payload } = await run(latex);
      const shipped = strategy === "circle" && payload?.verified === true;
      expect(shipped).toBe(false);
    });
  }

  // C2 — "area of the circle" beside a sector clause is the WHOLE disc, not the
  // sector: the ask is unambiguous, so ship the correct whole-circle value.
  it("C2 'area of the circle' beside a sector clause → whole-circle area", async () => {
    const { strategy, payload } = await run(
      "A circle has radius 10 cm and a sector of angle 90 degrees. Find the area of the circle."
    );
    expect(strategy).toBe("circle");
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain).toBe("100π cm² ≈ 314.1593 cm²");
  });
  it("C2 'area of the circle' after a sector clause (2nd phrasing) → whole circle", async () => {
    const { strategy, payload } = await run(
      "A sector of a circle of radius 7 cm has a central angle of 60 degrees. Find the area of the circle."
    );
    expect(strategy).toBe("circle");
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain).toBe("49π cm² ≈ 153.938 cm²");
  });
  // C2 — the annular region ("area of the path") is a compound figure → decline.
  it("C2 declines the annular 'area of the path'", async () => {
    const { strategy, payload } = await run(
      "A circular pond of radius 7 m is bordered by a path 2 m wide. Find the area of the path."
    );
    const shipped = strategy === "circle" && payload?.verified === true;
    expect(shipped).toBe(false);
  });

  // C3 — a radian angle must DECLINE even with a "π = value" clause or ASCII "pi".
  const radianDeclines = [
    "A sector of a circle has radius 21 cm and subtends an angle of 2π/3 at the centre. Taking π = 22/7, find the arc length.",
    "A circle has radius 6 cm. An arc subtends a central angle of π/3 at the centre. Take π = 3.14 and find the arc length.",
    "Find the sector area of a circle of radius 12 cm, central angle 2π/3, use π = 3.14",
    "Find the sector area of a circle radius 6 cm central angle pi/3",
  ];
  for (const latex of radianDeclines) {
    it(`C3 declines radian-with-π-clause: ${latex}`, async () => {
      const { strategy, payload } = await run(latex);
      const shipped = strategy === "circle" && payload?.verified === true;
      expect(shipped).toBe(false);
    });
  }

  // C4 — adjective partial figures and pluralised fractions must DECLINE.
  const partialDeclines = [
    "Find the area of a semi-circular plate of radius 7 cm",
    "Find the perimeter of a semi-circular plate of radius 7 cm",
    "Find the area of a quarter-circular tile of radius 6 cm",
    "Find the area of three quarters of the circle with radius 4 cm",
    "Find the area of two-thirds of a circle with radius 6 cm",
    "Find the area of seven eighths of a circle with radius 8 cm",
  ];
  for (const latex of partialDeclines) {
    it(`C4 declines partial/plural figure: ${latex}`, async () => {
      const { strategy, payload } = await run(latex);
      const shipped = strategy === "circle" && payload?.verified === true;
      expect(shipped).toBe(false);
    });
  }

  // The legit neighbours must KEEP resolving — the fixes are precise. A degree
  // angle beside a "take π = 22/7" clause, and an adjacent-given radius, still verify.
  it("a degree angle + 'take π = 22/7' clause still resolves", async () => {
    const { strategy, payload } = await run(
      "A sector of a circle has radius 21 cm and central angle 120 degrees. Taking π = 22/7, find the arc length."
    );
    expect(strategy).toBe("circle");
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain?.startsWith("14π")).toBe(true);
  });
  it("an adjacent radius beside an unrelated 'path 2 m wide' still resolves", async () => {
    const { strategy, payload } = await run(
      "A path 2 m wide runs past a circle of radius 14 cm; find the area of the circle"
    );
    expect(strategy).toBe("circle");
    expect(payload?.verified).toBe(true);
    expect(payload?.finalAnswer?.plain).toBe("196π cm² ≈ 615.7522 cm²");
  });
});

// Adversarial gate (2026-07): 16 confirmed golden-rule holes across 5 classes.
// Every one is a PARSE-layer misread the recompute()/verify() gate is BLIND to —
// it re-derives from the SAME misread given — so each fix forces a DECLINE at the
// parse gate. (This engine solves only the FORWARD direction, one whole circle,
// one unambiguous angle.)
describe("parseCircle — adversarial gate regressions (2026-07)", () => {
  // Class A (7) — INVERSE problem: given area/circumference, asked for
  // radius/diameter. givenRe can't invert an area, so it fabricated a linear value
  // from whatever number it saw and answered the FORWARD question (shipping e.g.
  // area 2401π for "area 49π, find the radius", reading 49 as the radius).
  it("A: declines an inverse problem (given area/circumference → find radius/diameter)", () => {
    expect(parseCircle("The area of a circle is 49π cm². Find its radius.")).toBeNull();
    expect(parseCircle("Find the diameter of a circle whose area is 200 cm².")).toBeNull();
    expect(parseCircle("The circumference of a circle is 44 cm. What is the radius?")).toBeNull();
    expect(parseCircle("A circle has area 100 cm². Calculate its diameter.")).toBeNull();
    expect(parseCircle("Given the circumference is 62.8 m, work out the radius.")).toBeNull();
    expect(parseCircle("The area is 314 cm². Determine the radius of the circle.")).toBeNull();
    expect(parseCircle("Obtain the radius of a circle of circumference 20π cm.")).toBeNull();
  });

  // Class B (2) — RELATIONAL given: the linear value is stated as a word-ratio to
  // another quantity ("half the diameter of 16"), and givenRe grabbed the trailing
  // number directly, off by the relational factor.
  it("B: declines a relationally-defined given (half/twice another length)", () => {
    expect(
      parseCircle("The radius is half the diameter of 16 cm. Find the area of the circle.")
    ).toBeNull();
    expect(
      parseCircle("The radius of a circle is twice 7 cm. Find its circumference.")
    ).toBeNull();
  });

  // Class C (3) — AMBIGUOUS / mis-read angle: two degree marks (a bearing beside a
  // central angle), or the loose "angle … N" fallback grabbing a far-off RADIUS as
  // the angle. Nothing re-verifies the angle read.
  it("C: declines when the central angle is ambiguous or absent", () => {
    // two REAL degree marks (neither a compass/thermal distractor) and NO word
    // disambiguating which is the central angle → decline. (A degree mark that IS a
    // "bearing/latitude/temperature" distractor is now excluded, so the SOLE remaining
    // angle wins — see the ROUND-5 "bearing distractor beside an unmarked angle" cases.)
    expect(
      parseCircle("A sector of a circle radius 7 cm is marked 120° and 75°. Find the arc length.")
    ).toBeNull();
    // no angle value — the old fallback read the RADIUS (10) as the angle
    expect(
      parseCircle("A sector of a circle has a central angle. The radius is 10 cm. Find the arc length.")
    ).toBeNull();
    expect(
      parseCircle("Find the area of the sector whose radius is 8 cm and central angle measures.")
    ).toBeNull();
  });

  // Class D (3) — PARTIAL figure: the circle is cut/bisected/split, so a bare πr²
  // would answer for the WHOLE where only a part is meant.
  it("D: declines a partial figure (bisected / split / cut into pieces)", () => {
    expect(parseCircle("A circle of radius 14 cm is bisected. Find the area.")).toBeNull();
    expect(
      parseCircle("A circle of radius 14 cm is split into two equal pieces. Find the area.")
    ).toBeNull();
    expect(
      parseCircle("A circle of radius 10 cm is cut into two pieces. Find the area of one piece.")
    ).toBeNull();
  });

  // Class E (1) — TWO circles by count, phrased so the `circles`/ordinal guards
  // miss it. Two independent linear givens ⇒ a compound figure.
  it("E: declines two circles each with its own linear given", () => {
    expect(
      parseCircle("A circle of radius 5 cm sits beside a circle of radius 8 cm. Find the total area.")
    ).toBeNull();
    expect(
      parseCircle("One circle has diameter 6 cm and another circle has diameter 10 cm. Find the area.")
    ).toBeNull();
  });

  // Keep-resolve: the guards are PRECISE — a plain forward whole-circle problem, a
  // circumference ask (which mentions "circumference" but is NOT a linear ask), and
  // a single unambiguous degree angle all still parse cleanly.
  it("still resolves the FORWARD whole-circle problems the guards must not touch", () => {
    const a = parseCircle("Find the area of a circle with radius 7 cm")!;
    expect(a?.target).toBe("area");
    expect(a?.radius).toBe(7);
    const c = parseCircle("Find the circumference of a circle with radius 7 cm")!;
    expect(c?.target).toBe("circumference");
    expect(c?.radius).toBe(7);
    const s = parseCircle(
      "A sector of a circle has radius 21 cm and central angle 120 degrees. Find the arc length."
    )!;
    expect(s?.target).toBe("arc_length");
    expect(s?.angleDeg).toBe(120);
  });
});

// Adversarial gate ROUND 4 (2026-07): a FRESH complete sweep of the circle engine
// found 10 more golden-rule holes in 4 clusters. Each is a PARSE-layer misread the
// recompute()/verify() gate is blind to; every fix pushes to a DECLINE or a CORRECT
// parse. Value cases assert solveCircle(parseCircle(...)) directly — the exact path
// the gate's probe drove — so the answer string is the shipped one.
describe("parseCircle — adversarial gate regressions ROUND 4 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // Cluster 1 — PARTIAL figure phrased as a fraction/adjective of a "disc"/"circle":
  // "3/4 of a circle", "half a circular disc", "0.5 of a circle". A bare πr² would
  // answer for the WHOLE where only a part is meant → decline.
  it("1: declines a fractional/partial slice of a circle or disc", () => {
    expect(parseCircle("Find the area of 3/4 of a circle with radius 8")).toBeNull();
    expect(parseCircle("Find the area of half a circular disc of radius 7 cm")).toBeNull();
    expect(parseCircle("Find the area of a quarter of a circular disc of radius 8 cm")).toBeNull();
    expect(parseCircle("Find the perimeter of half a circular disc of radius 7 cm")).toBeNull();
    expect(parseCircle("Find the area of 0.5 of a circle with radius 6 cm")).toBeNull();
  });
  it("1: keeps a FULL circular disc (no partial modifier) resolving to πr²", () => {
    expect(ship("Find the area of a circular disc of radius 7 cm")).toBe("49π cm² ≈ 153.938 cm²");
  });

  // Cluster 2 — a LABEL index ("circle number 4", "circle 4") leaked as the given: the
  // "4" was read as the diameter (→ r=2, area 4π). Strip the label; two labelled
  // circles are a compound figure → decline.
  it("2: strips a 'circle number N' label instead of reading N as the given", () => {
    expect(ship("The diameter of circle number 4 is 10 cm. Find the area.")).toBe(
      "25π cm² ≈ 78.5398 cm²"
    );
    expect(ship("The diameter of circle 4 is 10 cm. Find the area.")).toBe("25π cm² ≈ 78.5398 cm²");
  });
  it("2: declines two labelled circles as a compound figure", () => {
    expect(
      parseCircle("Circle number 1 has radius 5 cm and circle number 2 has radius 8 cm. Find the area.")
    ).toBeNull();
  });

  // Cluster 2b — a distractor ° number (bearing/latitude/temperature) beside an
  // explicitly-labelled central angle: the label now OUTRANKS the distractor, and a
  // π-form central angle still declines as radians.
  it("2b: a labelled central angle outranks a bearing/latitude/temperature distractor", () => {
    expect(
      ship(
        "A radar sweeps a sector of radius 8 km through a central angle of 90, starting from a bearing of 45 degrees. Find the sector area."
      )
    ).toBe("16π km² ≈ 50.2655 km²");
    expect(
      ship(
        "A ship sails along a circle of latitude of radius 5000 km through a central angle of 50, starting at latitude 35 degrees north. Find the arc length."
      )
    ).toBe("12500/9 π km ≈ 4363.3231 km");
    expect(
      ship(
        "The central angle of a sector is 120. Find the sector area, radius 15, at a temperature of 300 degrees."
      )
    ).toBe("75π ≈ 235.6194");
  });
  it("2b: a π-form central angle beside a bearing still declines as radians", () => {
    expect(
      parseCircle(
        "A sector of a circle radius 6 cm subtends 2\\pi/3 at the centre, on a bearing of 40 degrees. Find the sector area."
      )
    ).toBeNull();
  });

  // Cluster 3 — POSSESSIVE target "the circle's sector": the ask is the SECTOR area,
  // not the whole circle. The old target detector saw "circle" + "area" → whole disc.
  it("3: 'the circle's sector' asks for the SECTOR area, not the whole circle", () => {
    expect(ship("Find the area of the circle's sector, radius 6 cm, central angle 60°")).toBe(
      "6π cm² ≈ 18.8496 cm²"
    );
  });

  // Cluster 4 — MAJOR / MINOR / REFLEX sector or arc needs the reflex-angle formula
  // and a correct read of which angle is given vs asked → decline rather than guess.
  it("4: declines a major/minor/reflex sector or arc", () => {
    expect(
      parseCircle(
        "A circle has radius 6 cm. The minor sector has central angle 90 degrees. Find the major sector area."
      )
    ).toBeNull();
    expect(
      parseCircle("Find the major arc length of a circle radius 10, central angle 60 degrees.")
    ).toBeNull();
    expect(
      parseCircle("Find the reflex sector area of a circle radius 9 cm, central angle 100 degrees.")
    ).toBeNull();
  });
});

// Adversarial gate ROUND 5 (2026-07): a FRESH complete sweep (22/22 agents, 0 error)
// found 15 more golden-rule holes in 5 clusters — all PARSE-layer misreads the
// recompute()/verify() gate is blind to. Every fix reads the CORRECT value or declines.
describe("parseCircle — adversarial gate regressions ROUND 5 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // Cluster G1 — a DISTRACTOR number ("seating 4 people", "2 cm grid", "room 3", "the
  // 5th circle") sat between the dimension keyword and the real value; the old reader
  // grabbed the FIRST number after the keyword. The value is now read from the
  // "is/=/measures" predication (Tier B), so the distractor is skipped.
  it("G1: reads the PREDICATED value, not an interposed distractor number", () => {
    expect(ship("The diameter of a circular table seating 4 people is 120 cm. Find the area."))
      .toBe("3600π cm² ≈ 11309.7336 cm²");
    expect(ship("The diameter of the circle on the 2 cm grid paper is 8 cm. Find its area."))
      .toBe("16π cm² ≈ 50.2655 cm²");
    expect(ship("The diameter of a circular window in room 3 is 60 cm. Find the area."))
      .toBe("900π cm² ≈ 2827.4334 cm²");
    expect(ship("The radius of the 5th circle is 7 cm. Find the area."))
      .toBe("49π cm² ≈ 153.938 cm²");
  });
  it("G1: a value walled off by a comma-parenthetical stays ambiguous → decline", () => {
    expect(parseCircle("Find the area of a circle whose diameter, on a 4 mm grid, is 20 cm.")).toBeNull();
  });

  // Cluster T — a DESCRIPTIVE "area" ("a large grassy area", "covers an area") set the
  // target to area, so a circumference ask ("distance around", "length of the boundary")
  // shipped πr². "area" now counts only as the ASKED quantity; the boundary phrasings
  // are read as circumference.
  it("T: descriptive 'area' + circumference asked as distance-around / boundary", () => {
    expect(ship("A circular plot has radius 14 m and a large grassy area. Find the distance around the plot."))
      .toBe("28π m ≈ 87.9646 m");
    expect(ship("A circular garden covers an area, radius 5 m. Find the length of the boundary."))
      .toBe("10π m ≈ 31.4159 m");
  });

  // Cluster A — a fraction / mixed-number central angle ("67½°", "45/2°") was truncated
  // to its whole part (67, 45) by the old NUM-only reader. The angle is now parsed
  // through parseValueToken so 67½ → 67.5, 45/2 → 22.5.
  it("A: parses a fraction / mixed-number central angle (no truncation)", () => {
    expect(ship("Find the sector area of a circle radius 8 cm with central angle 67\\frac{1}{2} degrees"))
      .toBe("12π cm² ≈ 37.6991 cm²");
    expect(ship("Find the arc length of a circle radius 12 cm with central angle 7\\frac{1}{2} degrees"))
      .toBe("1/2 π cm ≈ 1.5708 cm");
    expect(ship("Find the sector area of a circle radius 6 cm with central angle \\frac{45}{2} degrees"))
      .toBe("9/4 π cm² ≈ 7.0686 cm²");
  });

  // Cluster N — a NON-circle leaked a bare πr²: a "1/2 circle" (a fraction directly on
  // "circle" with no interposed "of"), and a sphere ("great circle of a spherical ball
  // … surface area"). Both now decline.
  it("N: declines a fraction-on-circle slice and a sphere/great-circle/surface-area", () => {
    expect(parseCircle("Find the area of a 1/2 circle of radius 8 cm")).toBeNull();
    expect(parseCircle("Find the area of a 3/4 circle of radius 8 cm")).toBeNull();
    expect(parseCircle("Find the circumference of a 1/2 circle of radius 8 cm")).toBeNull();
    expect(
      parseCircle("The great circle of a spherical ball has radius 7 cm. Find the surface area of the ball.")
    ).toBeNull();
  });

  // Cluster B2 — a "bearing of N degrees" distractor was grabbed as the central angle
  // whenever the true angle sat UNMARKED ("angle of 90 at the centre", bare "angle 72").
  // The bearing (and latitude/temperature/compass) degree mark is now excluded, so the
  // sole real angle — read by the fallback — wins.
  it("B2: excludes a bearing distractor, reads the unmarked central angle", () => {
    expect(
      ship("A sector of a circle of radius 12 cm has an angle of 90 at the centre. It faces a bearing of 60 degrees. Find the sector area.")
    ).toBe("36π cm² ≈ 113.0973 cm²");
    expect(
      ship("An arc of a circle of radius 10 cm has angle 72, drawn from a bearing of 36 degrees. Find the arc length.")
    ).toBe("4π cm ≈ 12.5664 cm");
  });
  it("B2: two REAL (non-distractor) degree marks stay ambiguous → decline", () => {
    expect(
      parseCircle("A sector of a circle radius 7 cm is marked 120° and 75°. Find the arc length.")
    ).toBeNull();
  });
});

// Adversarial gate ROUND 6 (2026-07): a FRESH complete sweep (20/20 agents, 0 error)
// found 13 more PARSE-layer holes in 4 clusters. Rather than patch each, the NL parsing
// was refactored into a reusable semantic layer (src/solver/nl/): a numeric-literal
// reader with LOCALE-AMBIGUITY detection, and an ANCHOR-based quantity reader (a value
// belongs to a quantity only when anchored to it by adjacency / predication / UNIT).
// These 13 are the permanent regression tests for that layer.
describe("parseCircle — adversarial gate regressions ROUND 6 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // Cluster (a) — a comma glued between digits is LOCALE-AMBIGUOUS (thousands separator
  // in en, the decimal separator across de/fr/es/…). The old VALUE regex truncated at the
  // comma ("1,000" → 1, "12,5" → 12), shipping a wrong verified answer. Now: decline.
  it("(a): a locale-ambiguous comma-in-number declines (never truncates)", () => {
    expect(parseCircle("Find the area of a circle with radius 1,000 cm")).toBeNull();
    expect(parseCircle("Find the area of a circle with diameter 2,000 mm")).toBeNull();
    expect(parseCircle("Find the area of a circle with radius 12,5 cm")).toBeNull();
  });

  // Cluster (b) — "boundary of / length around / distance all the way around" a "circular
  // area" is a CIRCUMFERENCE ask. The descriptive "circular area" fired wantsArea and
  // shipped πr². "area" now counts only as the ASKED OBJECT; the boundary phrasings read
  // as circumference (a LENGTH, correct unit).
  it("(b): boundary / length-around of a 'circular area' → circumference, not area", () => {
    expect(ship("Calculate the boundary of a circular area of radius 7 cm"))
      .toBe("14π cm ≈ 43.9823 cm");
    expect(ship("Find the length around the circular area of radius 7 m"))
      .toBe("14π m ≈ 43.9823 m");
    expect(ship("Find the distance all the way around the circular area of radius 7 cm"))
      .toBe("14π cm ≈ 43.9823 cm");
  });

  // Cluster (c) — a narrative distractor number ("after 2 seconds", "3 o clock position",
  // "1 of the slices", "sector number 2", "slice 3") was grabbed as the central angle
  // instead of the stated "…is N degrees". UNIT-anchoring now wins: whenever any number is
  // degree-marked, the angle MUST be one of them; a bare number anchored to another noun
  // is a distractor.
  it("(c): a degree-marked angle outranks a bare narrative distractor number", () => {
    expect(ship("A wheel of radius 35 cm turns. The central angle after 2 seconds is 120 degrees. Find the arc length."))
      .toBe("70/3 π cm ≈ 73.3038 cm");
    expect(ship("A circle of radius 10 cm. Find the arc length when the central angle at the 3 o clock position is 90 degrees."))
      .toBe("5π cm ≈ 15.708 cm");
    expect(ship("A circle has radius 9 cm. The central angle for 1 of the slices is 40 degrees. Find the sector area."))
      .toBe("9π cm² ≈ 28.2743 cm²");
    expect(ship("The central angle of sector number 2 is 120 degrees. Radius is 6 cm. Find the sector area."))
      .toBe("12π cm² ≈ 37.6991 cm²");
    expect(ship("A pizza has radius 20 cm. The central angle for slice 3 is 40 degrees. Find the sector area."))
      .toBe("400/9 π cm² ≈ 139.6263 cm²");
  });

  // Cluster (d) — a circle PARTITIONED into slices with a per-slice ask, or physically
  // FOLDED, is a partial figure; a bare πr² answers the whole disc (off by the slice count,
  // or by 2 for a fold). These now decline (no explicit angle to size the part).
  it("(d): partitioned (one-of-N slices) or folded figures decline", () => {
    expect(parseCircle("A circular pizza of radius 14 cm is cut into 8 equal slices. Find the area of one slice.")).toBeNull();
    expect(parseCircle("A circular cake of radius 10 cm is cut into 6 slices. Find the area of one slice.")).toBeNull();
    expect(parseCircle("A circle of radius 7 cm is folded in half. Find the area of the resulting shape.")).toBeNull();
  });
});

// Adversarial gate ROUND 7 (2026-07): a FRESH complete sweep (12/12 agents, 0 error)
// AFTER the nl/ refactor found 5 more holes in 3 classes. Each is fixed at the layer
// (not by a special case): the π-radian guard now runs UP FRONT so a decimal π
// coefficient can't be stripped to a bare degree; the quantity reader gained a
// rejectTrailer so a name-anchored angle beats a foreign degree-marked distractor; and
// the figure gate learned two more non-plain-circle categories.
describe("parseCircle — adversarial gate regressions ROUND 7 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (1) A π used as an angle VALUE with a DECIMAL coefficient ("1.5π", "0.5π") is a
  // RADIAN angle. The old ANGVAL alternation only kept integer coefficients, so the
  // reader stripped the π and shipped "1.5°"/"0.5°" (off by a factor of 180). The
  // π-radian guard now runs before any value is read → decline.
  it("(1): a decimal-coefficient π angle (1.5π, 0.5π) declines as radians", () => {
    expect(parseCircle(String.raw`Find the sector area of a circle with radius 6 cm and central angle 1.5\pi`)).toBeNull();
    expect(parseCircle(String.raw`sector area radius 10 cm central angle 0.5\pi`)).toBeNull();
  });

  // (2) Material REMOVED from the disc (a hole cut out) or a CRESCENT/LUNE is not a
  // plain circle: a bare πr² answers the whole disc and ignores the removed / excluded
  // region. The figure gate now declines both.
  it("(2): a disc with a hole cut out, or a crescent/lune, declines", () => {
    expect(parseCircle("A circular metal plate of radius 10 cm has a hole of area 36 pi cut out of it. Find the area of the metal.")).toBeNull();
    expect(parseCircle("The diagram shows a crescent formed by two arcs on a circle of radius 8 cm. Find the area of the crescent.")).toBeNull();
  });

  // (3) A number anchored to the angle's OWN name ("central angle 60") outranks a stray
  // degree-marked number on ANOTHER noun ("the oven is set to 200 degrees"). The old
  // "any degree mark wins" rule grabbed the oven's 200; the reader now binds the
  // name-anchored 60 (and the thermal distractor is excluded from the marked set).
  it("(3): a name-anchored central angle beats a foreign degree-marked distractor", () => {
    expect(ship("A sector of a circle of radius 20 cm has a central angle 60. The oven is set to 200 degrees. Find the sector area."))
      .toBe("200/3 π cm² ≈ 209.4395 cm²");
  });
});

// Adversarial gate ROUND 8 (2026-07): a FRESH complete sweep (16/16 agents, 0 error)
// after the ROUND-7 fixes found 9 deeper holes in 4 classes. Each is fixed at the right
// layer (parse-integrity guard / target reader / angle reader / figure gate), not by a
// one-off, and these are the permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 8 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) An irrational given written with \sqrt cannot survive the macro-strip flatten
  // (cleanLatex deletes "\sqrt", leaving the bare radicand), so "radius √2" would be
  // misread as radius 2 and the verify gate re-derives from the same misread. Decline.
  it("(A): a \\sqrt (irrational) given declines — never misread as its radicand", () => {
    expect(parseCircle(String.raw`Find the area of a circle with radius \sqrt{2} cm`)).toBeNull();
    expect(parseCircle(String.raw`Find the area of a circle with diameter \sqrt{2} cm`)).toBeNull();
  });

  // (B) "distance / length around (or along) the arc" is ARC LENGTH, not the whole
  // circumference — the shared word "around" made it ship 2πr and drop the θ/360 factor.
  it("(B): 'distance around the arc' → arc length (θ/360 kept), not circumference", () => {
    expect(ship("Find the distance around the arc: circle radius 6 cm, central angle 60 degrees"))
      .toBe("2π cm ≈ 6.2832 cm");
    expect(ship("An arc subtends an angle of 90 degrees in a circle of radius 8 cm. Find the distance around the arc."))
      .toBe("4π cm ≈ 12.5664 cm");
  });

  // (C) A RELATIONAL angle ("1/4 of a full turn", "half of 120 degrees") is not a
  // directly-stated measure; the reader grabbed the literal number and shipped a wrong
  // angle. Decline.
  it("(C): a relational / fraction-of-a-turn angle declines", () => {
    expect(parseCircle("Find the arc length of a circle radius 15 with central angle 1/4 of a full turn")).toBeNull();
    expect(parseCircle("Find the sector area of a circle radius 12, central angle is half of 120 degrees")).toBeNull();
  });

  // (D) A disc BISECTED by a diameter — folded along it, divided by it, or a region
  // bounded by a diameter and its arc — is a SEMICIRCLE; a bare πr² ships double the true
  // ½πr². These half-disc figures carry no "semicircle/half" keyword, so decline.
  it("(D): a diameter-bisected half-disc (fold / divide / bounded-by-diameter+arc) declines", () => {
    expect(parseCircle("A circular sheet is folded once along a diameter. Find the area of the resulting shape, radius 8.")).toBeNull();
    expect(parseCircle("A region is bounded by a diameter of a circle and its arc. The radius is 7 cm. Find the area.")).toBeNull();
    expect(parseCircle("A circle of radius 10 cm is divided by a diameter. Find the area of each half.")).toBeNull();
  });
});

// Adversarial gate ROUND 9 (2026-07): a FRESH complete sweep after the ROUND-8 fixes
// found 9 more holes in 3 classes — a chained-arithmetic given misread, a dangling
// central angle on a whole-circle/arc AREA ask, and relational angles the ROUND-8 guard
// missed ("1/3 of 90 degrees", "of a right angle"), plus a fencing/boundary-length ask
// shipping area. Each is fixed at the right layer (parse-integrity guard / target reader
// / angle reader), not a one-off, and these are the permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 9 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) A CHAINED-ARITHMETIC given ("d = 2 × 7 = 14", "radius r = 3 × 4 = 12", "diameter
  // is 4 times 5 = 20") states the value as a mini-calculation. The macro-strip deletes
  // "\times" to a space and the reader grabs the FIRST operand (2/3/4) — a wrong given the
  // verify gate re-derives from. Decline (there is no faithful flattening of the product).
  it("(A): a chained-arithmetic given declines — never grabs the first operand", () => {
    expect(parseCircle(String.raw`A circle has d = 2 \times 7 = 14 cm. Find the area.`)).toBeNull();
    expect(parseCircle(String.raw`A circle has radius r = 3 \times 4 = 12 cm. Find the area.`)).toBeNull();
    expect(parseCircle("A circular pond has diameter 4 times 5 = 20 m. Find the area.")).toBeNull();
  });

  // (B) A dangling central angle on a WHOLE-circle area ask, with no sector/arc noun to
  // host it, is ambiguous (a sector is almost certainly meant); shipping πr² drops the
  // angle. And "area of the arc" is ill-posed (an arc has no area). Both decline. But a
  // whole-circle area ask WITH a separate "sector" noun hosting the angle stays a clean
  // whole-disc ask (see the C2 regressions above) and still ships.
  it("(B): a dangling central angle on a bare-circle / arc AREA ask declines", () => {
    expect(parseCircle("Find the area of a circle radius 6 cm with central angle 60 degrees.")).toBeNull();
    expect(parseCircle("Find the area of the arc of a circle radius 6 cm with central angle 60 degrees.")).toBeNull();
  });

  // (C) Relational angles the ROUND-8 guard missed: a literal fraction "a/b of N degrees"
  // and "of a right angle". The reader grabbed the literal 1/3 (→ 1/3°) or 2/3 (→ 2/3°);
  // computing the relation is a mis-read nothing verifies. Decline.
  it("(C): 'a/b of N degrees' and 'of a right angle' relational angles decline", () => {
    expect(parseCircle("Find the arc length of a circle radius 9 cm, central angle 1/3 of 90 degrees.")).toBeNull();
    expect(parseCircle("Find the arc length of a circle radius 12 cm, central angle 1/3 of a right angle.")).toBeNull();
    expect(parseCircle("Find the sector area of a circle radius 12 cm, central angle 2/3 of a right angle.")).toBeNull();
  });

  // (D) A BOUNDARY-LENGTH ask names the perimeter via the thing laid along it ("length of
  // fencing needed to go around the area of the circle") — the asked quantity is a LENGTH
  // (circumference); the "area" it borders is scenery. It shipped πr²; it must ship 2πr.
  it("(D): a fencing / boundary-length ask → circumference, not the enclosed area", () => {
    expect(ship("A circle has radius 7 m. Find the length of fencing needed to go around the area of the circle."))
      .toBe("14π m ≈ 43.9823 m");
  });
});

// Adversarial gate ROUND 10 (2026-07): a FRESH complete sweep (14/14 agents, 0 error)
// after ROUND-9 found 7 more holes — INCLUDING a regression ROUND-9 itself introduced (a
// boundary cue firing on a SCENERY sentence and suppressing an explicit "Find the area").
// Four classes: scenery-boundary regression, an annular band (path/track with a width), a
// degrees-minutes angle, and "circumference of a sector". Permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 10 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) REGRESSION FIX: a bare "goes/runs around" in a SEPARATE descriptive sentence is
  // scenery, not the ask. ROUND-9's boundary cue matched it and shipped circumference for
  // an explicit "Find the area". The invariant: an AREA ask never ships a length. Cases
  // where the trailing clause carries no circumference noun ship the area outright; one
  // that mentions "the edge" is ambiguous and declines — either way, never a length.
  it("(A): a scenery 'fence/path runs around it' never overrides an explicit area ask", () => {
    expect(ship("Find the area of a circle radius 6 cm. Fencing runs around it.")).toBe("36π cm² ≈ 113.0973 cm²");
    expect(ship("Find the area of a circular field with radius 20 m. A fence runs around it.")).toBe("400π m² ≈ 1256.6371 m²");
    const edge = ship("Find the area of the circle with radius 5 cm. A path goes around the edge.");
    expect(edge === null || edge.includes("²")).toBe(true); // decline or area — never a bare length
  });

  // (B) An ANNULAR BAND — a circular path/track of stated WIDTH — is the region between
  // two radii, not a disc; πr² answers the wrong figure. The ask "area of the CIRCULAR
  // path/track" (an adjective between determiner and region noun) now declines.
  it("(B): 'area of a circular path/track of width w' (an annulus) declines", () => {
    expect(parseCircle("A circular path 2 m wide surrounds a pond of radius 20 m. Find the area of the circular path.")).toBeNull();
    expect(parseCircle("Find the area of a circular track of width 2 m and radius 30 m")).toBeNull();
  });

  // (C) DEGREES-MINUTES angle notation ("30 degrees 45 minutes") — the reader kept only
  // the whole-degree part and dropped the arcminutes (30°45′ → 30°, ~2.5% low). Decline.
  it("(C): a degrees-minutes (DMS) angle declines rather than drop the arcminutes", () => {
    expect(parseCircle("Find the arc length of a circle of radius 12 cm with central angle 30 degrees 45 minutes")).toBeNull();
  });

  // (D) A SECTOR has no "circumference" (its boundary is arc + 2 radii). The literal token
  // was ungated by !mentionsSector and shipped 2πr (the whole circle) for a sector ask.
  it("(D): 'circumference of a sector' declines — a sector has no circumference", () => {
    expect(parseCircle("Find the circumference of a sector with radius 7 cm and angle 90 degrees")).toBeNull();
  });
});

// Adversarial gate ROUND 11 (2026-07): a FRESH complete sweep (18/18 agents, 0 error) after
// ROUND-10 found 11 more holes across five root causes. Every fix hardened the shared parse
// layer rather than adding a special case: the boundary cue is now tied to the ASK verb in
// the same sentence (killing the recurring scenery regression), the DMS reader spans
// connectors, and three new givens (comparison, π-in-a-linear-dimension, removed-material /
// partitioned figures) decline instead of misreading. Permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 11 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) SCENERY-BOUNDARY, again: a "fencing" clause in a SEPARATE sentence is scenery. The
  // boundary cue must fire only when the ASK verb and a boundary noun share one sentence, or
  // it steals an explicit area ask and ships circumference. Invariant: area ask → area.
  it("(A): a separate 'amount of fencing' sentence never overrides an explicit area ask", () => {
    expect(
      ship("Find the area of a circular field of radius 14 cm. Note: the amount of fencing needed to enclose the field was recorded separately.")
    ).toBe("196π cm² ≈ 615.7522 cm²");
    expect(
      ship("A circular lawn has radius 7 m. Find its area. The amount of fencing used is measured.")
    ).toBe("49π m² ≈ 153.938 m²");
    // The genuine boundary ask (verb + boundary noun in one sentence) still ships a length.
    expect(ship("Find the length of fencing needed to go around the area of the circle of radius 7 cm")).toBe("14π cm ≈ 43.9823 cm");
  });

  // (B) A PARTITIONED figure — split "into two portions" / "each portion" / a straight line
  // through the centre — is a partial region, not a disc. πr² answers the whole circle.
  it("(B): a circle split into portions declines rather than ship the whole disc", () => {
    expect(parseCircle("A circular field of radius 6 cm is split down the middle by a fence into two portions. Find the area of one portion.")).toBeNull();
    expect(parseCircle("A circle of radius 10 cm is divided by a straight line through its centre into two portions. Find the area of each portion.")).toBeNull();
  });

  // (C) REMOVED MATERIAL — "a quarter removed" leaves 3/4 of the disc; "area of the disc"
  // over the remaining figure is not πr². Decline rather than ship the full area.
  it("(C): a disc with material removed declines", () => {
    expect(parseCircle("A circular disc of radius 10 cm has a quarter removed. Find the area of the disc.")).toBeNull();
  });

  // (D) DMS with a connector ("30 degrees and 45 minutes", "40 degrees, 30 arcminutes") — the
  // reader must still decline, not keep only the whole-degree part.
  it("(D): a DMS angle joined by 'and'/comma still declines", () => {
    expect(parseCircle("A sector of a circle radius 6 cm has a central angle of 30 degrees and 45 minutes. Find the sector area.")).toBeNull();
    expect(parseCircle("A sector of a circle radius 6 cm has a central angle of 40 degrees, 30 arcminutes. Find the sector area.")).toBeNull();
  });

  // (E) A COMPARISON given — "3 cm less than 15 cm", "4 cm more than 6 cm" — is arithmetic the
  // parser must not collapse to the literal it sits beside (it grabbed 3 / 4). Decline.
  it("(E): a comparison-phrased dimension declines rather than grab the wrong literal", () => {
    expect(parseCircle("The diameter of a circle is 3 cm less than 15 cm. Find the area.")).toBeNull();
    expect(parseCircle("A circle has radius 4 cm more than 6 cm. Find the area.")).toBeNull();
  });

  // (F) A π-IN-A-LINEAR-DIMENSION given — "radius 2π cm" — means r = 2π, so area = 4π³ and
  // circumference = 4π², not the 4π the naive reader ships. Decline the compound literal.
  it("(F): a radius/diameter written with π (r = 2π) declines rather than ship 4π", () => {
    expect(parseCircle(String.raw`A circle has radius 2\pi cm. Find the area.`)).toBeNull();
    expect(parseCircle(String.raw`A circle has radius 2\pi cm. Find the circumference.`)).toBeNull();
  });
});

// Adversarial gate ROUND 12 (2026-07): a FRESH complete sweep (17/17 agents, 0 error) after
// ROUND-11 found 10 more holes across four root causes, all fixed at the parse layer: a
// revolution-unit angle ("1/2 turn", "1/6 revolution", "1/4 rev") mis-split into a bare
// integer degree; a FRACTION of the target ("half the area", "a third of the area of the
// circle") slipping PARTIAL_COMPOUND and shipping the whole πr²; "circumference/perimeter OF
// THE ARC" landing on the bare token and shipping 2πr; and a COMPOUND ask ("the area AND the
// length of fencing") silently shipping only the circumference. Permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 12 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) A REVOLUTION-UNIT angle is measured in full turns (×360°); the fraction reader
  // mis-split "1/2 turn" and grabbed "1" as 1°, shipping an angle off by ×360. Decline —
  // but a NARRATIVE "a wheel turns" (no number on the unit) must still read its real angle.
  it("(A): a turn/revolution/rev angle declines; a narrative 'turns' keeps its stated angle", () => {
    expect(parseCircle("Find the sector area of a circle with radius 6 cm and central angle of 1/2 turn")).toBeNull();
    expect(parseCircle("Find the arc length of a circle radius 12 cm where the central angle is 1/6 revolution")).toBeNull();
    expect(parseCircle("Find the arc length of a circle radius 9 cm, central angle 1/4 rev")).toBeNull();
    expect(parseCircle("The circle has radius 6. Find the sector area where the central angle is 3/4 turn.")).toBeNull();
    // Narrative "turns" (no number welded to it) still reads the explicit 120° angle.
    expect(ship("A wheel of radius 35 cm turns. The central angle after 2 seconds is 120 degrees. Find the arc length.")).toBe("70/3 π cm ≈ 73.3038 cm");
  });

  // (B) A FRACTION of the target ("half the area", "a third of the area of the circle") is a
  // partial quantity; with "the area of" interposed it slips PARTIAL_COMPOUND and the engine
  // ships the FULL πr² (double/triple the true value). Decline.
  it("(B): 'half/a third of the area' declines rather than ship the whole disc", () => {
    expect(parseCircle("Find half the area of the circle of radius 10 cm")).toBeNull();
    expect(parseCircle("Find a third of the area of the circle of radius 6 cm")).toBeNull();
  });

  // (C) "circumference / perimeter OF THE ARC" is ill-posed — an arc has no circumference —
  // and the reader shipped the whole 2πr, dropping the stated angle. Decline. The genuine
  // arc-length ask ("length of the arc") with the same angle still ships correctly.
  it("(C): 'circumference/perimeter of the arc' declines; 'length of the arc' still ships", () => {
    expect(parseCircle("Find the perimeter of the arc of a circle of radius 9 cm with central angle 40 degrees")).toBeNull();
    expect(parseCircle("Find the circumference of the arc of a circle radius 10 cm central angle 90 degrees")).toBeNull();
    expect(ship("Find the length of the arc of a circle radius 10 cm central angle 90 degrees")).toBe("5π cm ≈ 15.708 cm");
  });

  // (D) A COMPOUND ask names two distinct quantities ("the area AND the length of fencing");
  // the boundary cue shipped only the circumference and dropped the explicit area ask. A
  // direct area ask co-occurring with a boundary-length ask declines. The single-quantity
  // "length of fencing to go around the area" (no 'and', area is prepositional) still ships.
  it("(D): 'area AND length of fencing' declines; the single boundary ask still ships", () => {
    expect(parseCircle("Find the area of a circular garden of radius 7 m and the length of fencing needed to enclose it")).toBeNull();
    expect(ship("Find the length of fencing needed to go around the area of the circle of radius 7 cm")).toBe("14π cm ≈ 43.9823 cm");
  });
});

// Adversarial gate ROUND 13 (2026-07): a FRESH complete sweep (19/19 agents, 0 error) after
// ROUND-12 found 12 more holes across five root causes, all fixed at the parse layer: an arc
// named with an angle but a "distance around [it/an arc/its arc]" phrasing shipping the whole
// 2πr; relational/comparison givens with an interposed word ("radius 3 times that of …",
// "2 more centimetres than a 10 cm rod"); a GRADIAN angle unit read as degrees; an inscribed
// angle "at the circumference" read as central; and semicircle synonyms ("half-disc",
// "semi-disc", "enclosed by a diameter and the arc", a sector "enclosed by an arc and two
// radii") shipping the whole disc. Permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 13 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) An arc named WITH an angle, asked as "distance/length around [it | its edge | an arc
  // | its arc]", must not ship the whole 2πr (dropping θ/360). Decline. The genuine
  // arc-length ask ("around THE arc", "length of the arc") still ships the θ-scaled value.
  it("(A): 'distance around [it/an arc/its arc]' with an angle declines; 'around the arc' ships", () => {
    expect(parseCircle("The arc has radius 9 cm and central angle 40 degrees. Find the distance around its edge.")).toBeNull();
    expect(parseCircle("A circular arc of radius 5 cm has a central angle of 120 degrees. Find the distance around it.")).toBeNull();
    expect(parseCircle("A circle of radius 12 cm. Find the distance around an arc for a central angle of 60 degrees.")).toBeNull();
    expect(parseCircle("A circle of radius 8 cm. Find the length around its arc for angle 45 degrees.")).toBeNull();
    expect(ship("A circle of radius 12 cm. Find the distance around the arc for a central angle of 60 degrees.")).toBe("4π cm ≈ 12.5664 cm");
    // An arc mentioned with NO angle is a genuine whole-circle circumference ask → keep.
    expect(ship("A circle of radius 7 cm has an arc drawn on it. Find the circumference.")).toBe("14π cm ≈ 43.9823 cm");
  });

  // (B) A relational/comparison given with an interposed word — "radius 3 times that of a
  // smaller circle", "radius 2 more centimetres than a 10 cm rod" — must not bind the bare
  // multiplier/delta as the radius. Decline.
  it("(B): 'N times that of' and 'N more <unit> than' givens decline", () => {
    expect(parseCircle("A circle has a radius 3 times that of a smaller circle, which is 4 cm. Find the area.")).toBeNull();
    expect(parseCircle("Find the area of a circle with radius 2 more centimetres than a 10 cm rod.")).toBeNull();
  });

  // (C) A GRADIAN (gon) angle is a non-degree unit (100 gon = 90°); "100 gradians" must not
  // be read as 100°. Decline — this engine reads degrees only.
  it("(C): a gradian angle declines rather than read the number as degrees", () => {
    expect(parseCircle("Find the sector area radius 5 cm central angle 100 gradians")).toBeNull();
  });

  // (D) An angle "at the circumference" is INSCRIBED (half the central angle); reading it as
  // central ships half/double the true sector. Decline. The central angle "at the centre"
  // remains the correct, shipped reading.
  it("(D): an inscribed 'at the circumference' angle declines; 'at the centre' still ships", () => {
    expect(parseCircle("A sector of a circle has radius 6 cm. The arc subtends an angle of 40 degrees at the circumference. Find the sector area.")).toBeNull();
    expect(ship("A sector of a circle radius 6 cm has central angle 90 degrees at the centre. Find the sector area.")).toBe("9π cm² ≈ 28.2743 cm²");
  });

  // (E) SEMICIRCLE synonyms — "half-disc"/"semi-disc" (hyphenated), a region "enclosed by a
  // diameter and the arc", or a sector "enclosed by an arc and two radii" — are partial
  // figures, not whole discs; a bare πr² doubles/over-ships. Decline. A FULL "circular disc"
  // (no partial modifier) is still a whole circle and resolves.
  it("(E): half-disc / semi-disc / enclosed-region figures decline; a full disc still ships", () => {
    expect(parseCircle("A half-disc is cut from a circular sheet of radius 6 cm. Find the area of the half-disc.")).toBeNull();
    expect(parseCircle("A semi-disc of a circular plate has radius 6 cm. Find its area.")).toBeNull();
    expect(parseCircle("Find the area enclosed by a diameter of a circle of radius 6 cm and the arc")).toBeNull();
    expect(parseCircle("Find the area enclosed by an arc of a circle of radius 6 cm and the two radii that make a 90 degree angle at the centre")).toBeNull();
    expect(ship("Find the area of a circular disc of radius 7 cm")).toBe("49π cm² ≈ 153.938 cm²");
  });
});

// Adversarial gate ROUND 14 (2026-07): a FRESH complete sweep (14/14 agents, 0 error) after
// ROUND-13 found six more holes in three root-cause classes, fixed at the parse layer:
//  • a dimension word bound to a COUNT ("a diameter of 12 hour markings", "36 spokes") while
//    the true size is a unit-anchored number elsewhere ("30 cm across") → the count was read
//    as the diameter → decline;
//  • a PERCENTAGE of the asked quantity ("50% of the area", "75% of the circumference") →
//    the scale factor was dropped, shipping the full figure → decline (as the fraction guard);
//  • a distractor angle — a degree-MARKED number on a different object ("a nearby ramp rises
//    at 30°", map "declination 15°") beat the definitional central/sector angle ("subtends 60
//    at the centre", "the sector angle is 40") → the anchored angle now wins → ships correct.
// Permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 14 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) A dimension word bound to a part-COUNT, not a length ("diameter of 12 hour markings",
  // "diameter of 36 spokes"), must not be read as the figure's size — the real dimension is
  // the unit-anchored number ("30 cm across", "60 cm across"). Decline. A number glued to a
  // length unit ("a diameter of 10 cm / 12 centimetres") is a genuine dimension and ships.
  it("(A): a dimension bound to a part-count declines; a unit-anchored dimension still ships", () => {
    expect(parseCircle("A circular clock face has a diameter of 12 hour markings and measures 30 cm across. Find its area.")).toBeNull();
    expect(parseCircle("A circular wheel with a diameter of 36 spokes is 60 cm across. Find the area.")).toBeNull();
    expect(ship("Find the area of a circle with a diameter of 10 cm")).toBe("25π cm² ≈ 78.5398 cm²");
    expect(ship("Find the area of a circle with a diameter of 12 centimetres")).toBe("36π cm² ≈ 113.0973 cm²");
  });

  // (B) A PERCENTAGE of the asked quantity is a partial-quantity ask the fraction guard's
  // word/ratio forms miss; shipping the full πr²/2πr drops the scale factor. Decline.
  it("(B): '50% of the area' / '75% of the circumference' decline", () => {
    expect(parseCircle("Find 50% of the area of a circle of radius 7 cm")).toBeNull();
    expect(parseCircle("Find 75% of the circumference of a circle of radius 10 cm")).toBeNull();
  });

  // (C) A degree-MARKED distractor on a different object ("a nearby ramp rises at 30°", map
  // "declination 15°") must not outrank the definitional central/sector angle. The anchored
  // angle wins → the sector ships its correct θ-scaled arc length.
  it("(C): the anchored central/sector angle beats a marked distractor and ships correct", () => {
    expect(ship("A sector of a circle of radius 6 cm subtends an angle of 60 at the centre. A nearby ramp rises at 30°. Find the arc length of the sector.")).toBe("2π cm ≈ 6.2832 cm");
    expect(ship("Find the arc length of a sector of a circle radius 12 cm, the sector angle is 40, shown on a map with declination 15°.")).toBe("8/3 π cm ≈ 8.3776 cm");
  });
});

// Adversarial gate ROUND 15 (2026-07): a FRESH complete sweep (15/15 agents, 0 error) after
// ROUND-14 found eight more holes in four root-cause classes, fixed at the parse layer:
//  • an explicit "find the AREA of …" ask lost to a subordinate boundary clause ("… that
//    needs a length of ribbon around it") and shipped the circumference → area now wins;
//  • an ARCMINUTE / arcsecond angle ("central angle 120 minutes" → read as 12°, dropping the
//    last digit) → decline (a degrees-only engine; the DMS pair is handled separately);
//  • SEMICIRCLE synonyms "half-moon" / "D-shaped", and an ANNULUS "a smaller circle removed"
//    → these non-circle figures shipped a bare πr² (double / over-counted) → decline;
//  • an ORIENTATION distractor ("angle 120. It is inclined at 30°", "the page is tilted 25°")
//    beat the stated sector/arc angle → the tilt distractor now loses → ships correct.
// Permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 15 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) An explicit direct "find the AREA of …" ask must win over a boundary-length phrase
  // buried in a subordinate clause; it must ship the AREA, not the circumference. The
  // genuine boundary ask ("find the length of fencing to go around …") still ships 2πr.
  it("(A): an explicit area ask beats a subordinate boundary clause; the boundary ask still ships circumference", () => {
    expect(ship("Find the area of a circular garden of radius 7 cm that needs a length of ribbon around it")).toBe("49π cm² ≈ 153.938 cm²");
    expect(ship("Find the length of fencing needed to go around the area of the circle of radius 7 cm")).toBe("14π cm ≈ 43.9823 cm");
  });

  // (B) An ARCMINUTE / arcsecond angle ("120 minutes", "36 minutes") is a non-degree unit
  // this engine can't convert (and the reader drops the last digit). Decline. A narrative
  // TIME offset that carries a proper "N degrees" angle is untouched and still ships.
  it("(B): a bare arcminute angle declines; a time-offset with a real degree angle still ships", () => {
    expect(parseCircle("Find the sector area of a circle radius 12 cm, central angle 120 minutes.")).toBeNull();
    expect(parseCircle("Find the sector area of a circle radius 6 cm, central angle 36 minutes.")).toBeNull();
    expect(ship("A wheel of radius 35 cm turns. The central angle after 2 seconds is 120 degrees. Find the arc length.")).toBe("70/3 π cm ≈ 73.3038 cm");
  });

  // (C) Semicircle synonyms ("half-moon", "D-shaped") and an annulus ("a smaller circle
  // removed") are non-circle figures; a bare πr² doubles / over-counts. Decline.
  it("(C): half-moon / D-shaped / circle-removed figures decline", () => {
    expect(parseCircle("A half-moon shaped circular window has radius 5 cm. Find the area.")).toBeNull();
    expect(parseCircle("A D-shaped circular region of radius 8 cm. Find the area.")).toBeNull();
    expect(parseCircle("A circular plate of radius 10 cm has a smaller circle removed. Find the area.")).toBeNull();
  });

  // (D) A degree describing how the whole figure is TILTED / inclined / on a tilted page is
  // an orientation distractor, never the sector's central angle; the stated "angle N" wins.
  it("(D): an orientation-tilt distractor loses to the stated sector/arc angle and ships correct", () => {
    expect(ship("A sector of a circle of radius 10 cm has angle 120. It is inclined at 30 degrees. Find the sector area.")).toBe("100/3 π cm² ≈ 104.7198 cm²");
    expect(ship("An arc of a circle of radius 9 cm has angle 80. The page is tilted 25 degrees. Find the arc length.")).toBe("4π cm ≈ 12.5664 cm");
  });
});

// Adversarial gate ROUND 16 (2026-07): a FRESH complete sweep (13/13 agents, 0 error) after
// ROUND-15 found six more holes in three root-cause classes, fixed at the parse layer:
//  • an arc with a RADIAN (or otherwise unparsed) angle asked as "distance around the edge
//    of the arc" shipped the whole 2πr (dropping rθ) — detectAngleDeg declines radians, so
//    the ROUND-13 arc guard's numeric check was skipped → extend it to any subtends/radian/
//    named-angle clause → decline;
//  • a 3-D SOLID's "curved / lateral surface" or "slant height" ("cylindrical tank … curved
//    surface", "conical cup … slant height") shipped the flat base πr² → decline;
//  • more perception/illumination angle distractors ("angle of elevation is 30°", "viewed at
//    45°", "the sunlight hits at 30°") beat the stated sector/arc angle → distractor now
//    loses → ships correct.
// Permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 16 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) An arc carrying a RADIAN (or named/subtends) angle, asked as "distance around the
  // edge of the arc", is an arc-length ask the degrees-only reader can't scale; shipping the
  // whole 2πr is wrong. Decline. A bare arc with NO angle clause is still a whole-circle ask.
  it("(A): a radian/named-angle arc 'around the edge' declines; a bare arc still ships circumference", () => {
    expect(parseCircle("An arc of a circle of radius 6 cm subtends an angle of pi/3 radians at the centre. Find the distance around the edge of the arc.")).toBeNull();
    expect(ship("A circle of radius 7 cm has an arc drawn on it. Find the circumference.")).toBe("14π cm ≈ 43.9823 cm");
  });

  // (B) A 3-D solid's curved/lateral surface or slant height ("cylindrical tank … curved
  // surface", "conical cup … slant height") is not a plane-circle quantity; the flat base
  // πr² is the wrong figure. Decline.
  it("(B): a cylinder/cone curved-surface or slant-height ask declines", () => {
    expect(parseCircle("A cylindrical tank has a circular base of radius 7 m and height 10 m. Find the area of the curved surface.")).toBeNull();
    expect(parseCircle("A conical cup has a circular top of radius 5 cm and slant height 12 cm. Find the area of the curved surface.")).toBeNull();
  });

  // (C) A perception / illumination degree ("angle of elevation is 30°", "viewed at 45°",
  // "the sunlight hits at 30°") is a distractor, never the sector angle; the stated angle wins.
  it("(C): elevation/viewing/sunlight distractors lose to the stated angle and ship correct", () => {
    expect(ship("Find the arc length of a circle radius 12 with angle 60. The angle of elevation is 30 degrees.")).toBe("4π ≈ 12.5664");
    expect(ship("A sector of a circle has radius 6 cm and angle 60. It is viewed at 45 degrees. Find the sector area.")).toBe("6π cm² ≈ 18.8496 cm²");
    expect(ship("Find the sector area of a circle radius 6 cm. The sector's angle is 90. The sunlight hits at 30 degrees.")).toBe("9π cm² ≈ 28.2743 cm²");
  });
});

// Adversarial gate ROUND 17 (2026-07): a FRESH complete sweep (14/14 agents, 0 error) after
// ROUND-16 found seven more holes in four root-cause classes, fixed at the parse layer:
//  • the "circle sector" SPACED compound ("area of the circle sector") matched the whole-
//    circle pattern and shipped πr² (36π-not-9π) — the sector detector now absorbs an
//    interposed "circle['s] " before "sector", and the whole-circle pattern refuses to fire
//    when a bare/possessive "sector" follows "circle";
//  • a DIGIT-GLUED radian angle "2pi/3" slipped the `\bpi\b` radian guard (no boundary at the
//    "2p" junction) and shipped 1/10 π (angle read as 2°) — the π-token now matches a non-
//    letter-bounded "pi" too → declines as radians;
//  • a disc "cut (straight) ALONG a diameter" is a SEMICIRCLE with no half/semicircle keyword;
//    πr² shipped DOUBLE — HALF_DISC now catches the cut/split-along-a-diameter phrasing;
//  • a subordinate RELATIVE-CLAUSE distractor ("the radius of a circular pond THAT measures 3 m
//    deep IS 10 m") bound the relative-clause number (3) instead of the main-clause value (10)
//    — the shared nl/quantity tier-B reader now skips a "that/which <verb>" predication so the
//    MAIN-clause value binds. Permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 17 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) The "circle sector" spaced compound names the SECTOR — ship the sector area (θ/360),
  // not the whole disc. The possessive "circle's sector" and "sector area" still resolve too.
  it("(A): 'area of the circle sector' ships the sector area, not the whole disc", () => {
    expect(ship("Find the area of the circle sector with radius 6 cm and angle 90 degrees.")).toBe("9π cm² ≈ 28.2743 cm²");
    expect(ship("Find the area of the circle's sector, radius 6 cm, central angle 60 degrees")).toBe("6π cm² ≈ 18.8496 cm²");
    // A plain whole-disc "area of the circle" is unaffected.
    expect(ship("Find the area of the circle with radius 7 cm")).toBe("49π cm² ≈ 153.938 cm²");
  });

  // (B) A digit-glued radian angle "2pi/3" is radians → decline (like the spaced "pi/3 radians").
  it("(B): a digit-glued radian angle '2pi/3' declines", () => {
    expect(parseCircle("Find the arc length of a circle with radius 9 cm and central angle 2pi/3")).toBeNull();
    // The degree equivalent still resolves.
    expect(ship("Find the arc length of a circle with radius 9 cm and central angle 120 degrees")).toBe("6π cm ≈ 18.8496 cm");
  });

  // (C) A disc cut/split ALONG a diameter is a semicircle (half-disc) → decline; πr² would double.
  it("(C): a disc cut along a diameter (semicircle) declines", () => {
    expect(parseCircle("A circular disc of radius 10 cm is cut straight along a diameter. Find the area of the flat-topped shape formed.")).toBeNull();
    expect(parseCircle("A circular disc of radius 8 cm is cut along a diameter. Find the area of the larger part.")).toBeNull();
    // A FULL circular disc (no cut) still resolves.
    expect(ship("Find the area of a circular disc of radius 7 cm")).toBe("49π cm² ≈ 153.938 cm²");
  });

  // (D) A subordinate "that measures N …" relative clause predicates the OTHER noun, not the
  // quantity; the MAIN-clause "is M" value binds. Generalises via the shared nl/quantity reader.
  it("(D): a relative-clause distractor binds the main-clause value, not the subordinate one", () => {
    expect(ship("The radius of a circular pond that measures 3 m deep is 10 m. Find the area.")).toBe("100π m² ≈ 314.1593 m²");
    expect(ship("The diameter of a circular tank that measures 3 m tall is 10 m. Find the area.")).toBe("25π m² ≈ 78.5398 m²");
    expect(ship("The central angle of a sector that measures 30 wide is 90 degrees. The circle has radius 4 cm. Find the sector area.")).toBe("4π cm² ≈ 12.5664 cm²");
  });
});
