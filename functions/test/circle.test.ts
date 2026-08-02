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

// Adversarial gate ROUND 18 (2026-07): a FRESH complete sweep (35/35 agents, 0 error — a much
// deeper finder pool than prior rounds) found 28 holes in eight root-cause classes, all fixed
// at the parse layer. Permanent regression tests.
describe("parseCircle — adversarial gate regressions ROUND 18 (2026-07)", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) A PART of the disc named by a non-"sector" noun (wedge / pie slice / one quarter /
  // each friend's share / "covered by the sector") must not receive the WHOLE-disc πr².
  // Gated on the resolved TARGET: with a sector target the same nouns are legitimate scenery.
  it("(A): a part-of-disc ask with a whole-figure target declines; a sector target still ships", () => {
    expect(parseCircle("A circle has radius 6 cm. Find the area of the wedge cut by an arc of 90 degrees.")).toBeNull();
    expect(parseCircle("A circular pizza of radius 12 cm has an arc of 60 degrees marked. Find the area of the pie slice.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 6 cm has central angle 90 degrees. Find the area of the circle covered by the sector.")).toBeNull();
    expect(parseCircle("A circular cake of radius 10 cm is cut into quarters. Find the area of one quarter.")).toBeNull();
    expect(parseCircle("A circular pizza of radius 14 cm is shared equally among 4 friends. Find the area each friend receives.")).toBeNull();
    // A genuine sector ask that merely mentions slices still resolves.
    expect(ship("A circle has radius 9 cm. The central angle for 1 of the slices is 40 degrees. Find the sector area.")).toBe("9π cm² ≈ 28.2743 cm²");
  });

  // (B) POSTPOSITIVE given ("7 cm in radius") must win over a later distractor length; the
  // possessive relative clause ("whose crust is 2 cm wide is 15 cm") binds the main clause.
  it("(B): a postpositive given beats a trailing distractor length", () => {
    expect(ship("A circular disc is 7 cm in radius and the table it rests on is 100 cm wide. Find the area of the disc.")).toBe("49π cm² ≈ 153.938 cm²");
    expect(ship("A circular tabletop is 120 cm in diameter and its leg is 75 cm long. Find the area of the tabletop.")).toBe("3600π cm² ≈ 11309.7336 cm²");
    expect(ship("A circular running wheel is 70 cm in diameter and the axle is 4 cm thick. Find the distance around the wheel.")).toBe("70π cm ≈ 219.9115 cm");
    expect(ship("The radius of a circular pizza whose crust is 2 cm wide is 15 cm. Find the area of the pizza.")).toBe("225π cm² ≈ 706.8583 cm²");
  });

  // (C) An explicit AREA ask survives a subordinate boundary-length clause, including the
  // adjectival "the TOTAL area" and the participial "the area COVERED BY" / "it occupies".
  // A scenery area plus a "how long is the wire" ask is a two-target ambiguity → decline.
  it("(C): area-vs-boundary — explicit area asks ship area; scenery-area + length ask declines", () => {
    expect(ship("Calculate the total area of a circular pond of radius 3 m that is surrounded by a length of edging.")).toBe("9π m² ≈ 28.2743 m²");
    expect(ship("A circular garden has a radius of 7 m. Calculate the area covered by grass inside the length of fencing that runs around it.")).toBe("49π m² ≈ 153.938 m²");
    expect(ship("A circular lawn has radius 9 m. Calculate the area it occupies, not counting the length of edging placed on it.")).toBe("81π m² ≈ 254.469 m²");
    // SUPERSEDED BY ROUND 20. This used to decline as a two-target ambiguity. The ROUND-20
    // gate then flagged the identical shape ("The AREA of the circle … is given in the table.
    // How LONG is the elastic that stretches once round it?") as a VIOLATION for shipping the
    // area — the ask clause names the length and the area is scenery. Reading the target from
    // the ask clause resolves both; here it ships the correct 2πr, which the stated 154 sq cm
    // agrees with. A correct answer beats an honest decline.
    expect(ship("A wire is bent to fit exactly along the edge of a circle of radius 7 cm. How long must the wire be? The area of the circle is 154 sq cm.")).toBe("14π cm ≈ 43.9823 cm");
    // A genuine boundary-length ask (no area object) still ships the circumference.
    expect(ship("A circular plot has radius 7 m. Find the length of fencing needed to go around it.")).toBe("14π m ≈ 43.9823 m");
  });

  // (D) A DERIVED angle — radians by their textbook name ("in circular measure"), a percentage
  // of another angle, a multiplier, or a supplement — is not the stated number. Decline.
  it("(D): derived/non-degree central angles decline", () => {
    expect(parseCircle("An arc of a circle of radius 10 cm subtends an angle of 1.2 in circular measure at the centre. Find the arc length.")).toBeNull();
    expect(parseCircle("A sector of a circle with radius 14 cm has a central angle that is 30% of 360 degrees. Find the area of the sector.")).toBeNull();
    expect(parseCircle("The central angle of a sector of a circle of radius 12 cm is double 45 degrees. Find the area of the sector.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 12 cm has a central angle supplementary to 120 degrees. Find the area of the sector.")).toBeNull();
  });

  // (E) A UNICODE VULGAR FRACTION is a real value, not a truncation: "7½" is 7.5, not 7.
  it("(E): vulgar fractions read at their true value", () => {
    expect(ship("The radius of a circle is 7½ cm. Find its area.")).toBe("225/4 π cm² ≈ 176.7146 cm²");
    expect(ship("A sector of a circle of radius 12 cm has a central angle of 22½ degrees. Find the sector area.")).toBe("9π cm² ≈ 28.2743 cm²");
  });

  // (F) The OTHER figure's area (an annular paving/surround, a rectangular card, a hexagonal
  // tile), a pronominal fraction ("half of it"), and a compound multi-unit length all decline.
  it("(F): surrounds, adjectival other-shapes, pronominal fractions and compound units decline", () => {
    expect(parseCircle("A circular pond of radius 7 m is surrounded by a paved surround 2 m wide. Find the area of the paving.")).toBeNull();
    expect(parseCircle("A rectangular sheet of card measures 30 cm by 20 cm. A circle of radius 5 cm is cut from it. Find the area of the card outside the circle.")).toBeNull();
    expect(parseCircle("A hexagonal tile has a circle of radius 4 cm stamped on it. Find the area of the tile.")).toBeNull();
    expect(parseCircle("A circular field has a radius of 14 m. Half of it is planted with grass. Find the area of the grass.")).toBeNull();
    expect(parseCircle("The radius of a circle is 1 m 20 cm. Find its area.")).toBeNull();
  });
});

// ── ROUND-19 (adversarial gate wf_024a8e15-c02; 41 agents, 34 confirmed) ──────────
// The deepest sweep so far. Ten root causes, all in the PARSE layer:
//  • a SWEPT angle whose host noun is narrative ("rotates through an ARC of 45°") switched
//    off the dangling-angle guard, shipping the whole disc for a sector (8× too large);
//  • an area/boundary ask decided by which clause is SCENERY, not by which words appear;
//  • the "N cm ACROSS" diameter idiom, unread, so a SECOND circle's given was bound;
//  • alternative angular units ("rads", "grades", "0.5 of a revolution") read as degrees;
//  • non-circle composite regions ("the area of the tile NOT COVERED by the circle");
//  • a qualified half ("the NORTHERN half"), an annular band stated as a width;
//  • Unicode fraction glyphs beyond the hand-picked set (⅑, ⅐) and the U+2044 slash;
//  • a SUBORDINATE clause ("the radius … WHEN the water level is 2 m deep is 14 m") whose
//    predication was bound instead of the main clause's.
// Permanent regression tests.
describe("circle — ROUND-19 gate regressions", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) A SWEPT angle: the "arc"/"sector" noun is narrative, the ask names no whole figure,
  // so πr² / 2πr would silently discard the stated angle. Decline. An ask that DOES name the
  // whole circle ("the area of the circle") keeps shipping — see the C2 regressions above.
  it("(A): a swept angle on a descriptive area/boundary ask declines", () => {
    expect(parseCircle("A searchlight with a beam of radius 20 m rotates through an arc of 45 degrees. Find the area lit.")).toBeNull();
    expect(parseCircle("A circular lawn sprinkler of radius 8 m turns through an arc of 120 degrees. Find the area watered.")).toBeNull();
    expect(parseCircle("A windscreen wiper of radius 12 cm sweeps through an arc of 60 degrees. Find the area it cleans.")).toBeNull();
    expect(parseCircle("A point on a circular disc of radius 20 cm moves through a central angle of 90 degrees. Find the distance it travels around the circle.")).toBeNull();
    expect(parseCircle("A circular gear of radius 10 cm rotates through a central angle of 120 degrees. Find the distance around the edge travelled by a tooth.")).toBeNull();
    expect(ship("A circle has radius 10 cm and a sector of angle 90 degrees. Find the area of the circle.")).toBe("100π cm² ≈ 314.1593 cm²");
  });

  // (B) The ASK CLAUSE decides the target: an "area of a circular garden" that is merely
  // scenery must not beat an explicit "find the length of the fence". The boundary object may
  // carry a determiner and adjectives ("the length of THE METAL STRIP").
  it("(B): a boundary ask beats a scenery area clause", () => {
    expect(ship("The area of a circular garden of radius 7 m is planted with grass. Find the length of the fence needed to go round it.")).toBe("14π m ≈ 43.9823 m");
    expect(ship("The area of a circular sign of radius 9 cm is painted. Work out the length of the metal strip fitted to its edge.")).toBe("18π cm ≈ 56.5487 cm");
    // Both a sector-area and a circle-area phrase present ⇒ which is the ask is unreadable.
    expect(parseCircle("The sector area is shown in the diagram and the central angle is 90 degrees. What is the area of the circle of radius 8 cm?")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 6 cm has a central angle of 90 degrees. Find the area of the circle taken up by the sector.")).toBeNull();
    // A plain sector ask that merely names its circle is NOT ambiguous and still ships.
    expect(ship("Find the sector area of a circle, radius 6 cm, central angle 60°")).toBe("6π cm² ≈ 18.8496 cm²");
  });

  // (C) "N cm ACROSS" is a diameter, read explicitly. ANY disagreeing reading elsewhere —
  // named or symbolic — is a possible second circle and declines. The symbol tier used to LOSE
  // to the idiom (on the theory that "d" was a foreign quantity, "its thickness is d = 2 mm"),
  // but ROUND 20 showed the same shape is more often the asked circle's OWN diameter ("a
  // tabletop with D = 120 CM has a coaster 10 CM ACROSS" shipped 25π for a true 3600π). A weak
  // anchor cannot tell those apart, so disagreement now declines in both directions.
  // ROUND 23 SUPERSEDES the "decline in both directions" rule: a span is now read WITH the
  // noun it is predicated of, so a dimension stated in a clause that never mentions the asked
  // figure ("It stands on a circular BASE of diameter 40 cm") is another object's, not a
  // competing reading of this one. It disagrees only when it might be the SAME figure's.
  it("(C): the 'across' idiom beats a dimension stated of a DIFFERENT object", () => {
    expect(ship("A circular tabletop is 90 cm across. It stands on a circular base of diameter 40 cm. Find the area of the tabletop.")).toBe("2025π cm² ≈ 6361.7251 cm²");
    expect(ship("A circular pond is 20 m across. The path beside it has diameter 26 m. Find the circumference of the pond.")).toBe("20π m ≈ 62.8319 m");
    expect(ship("A circular lid is 6 cm across. Its thickness is d = 2 mm. Find the area of the lid.")).toBe("9π cm² ≈ 28.2743 cm²");
    // …and symmetrically, a span stated of ANOTHER object no longer vetoes the asked figure's
    // own stated dimension — it is a distractor, which is what a word problem always meant it
    // to be.
    expect(ship("A circular tabletop with d = 120 cm has a coaster 10 cm across resting on it. Find the area of the tabletop.")).toBe("3600π cm² ≈ 11309.7336 cm²");
    expect(ship("A circular clock face with d = 24 cm has a sticker 6 cm across on it. Find the circumference of the clock face.")).toBe("24π cm ≈ 75.3982 cm");
    // A span is fatal only when it is the ONLY size in the text and belongs to other scenery.
    expect(parseCircle("A circular fountain sits in a courtyard 40 m across. Find the area of the fountain.")).toBeNull();
  });

  // (D) Alternative ANGULAR UNITS and derived angles — clipped plurals ("rads", "grades"),
  // a revolution without the "full/complete" modifier, a spelled-out ordinal fraction, and an
  // angle given as a DIFFERENCE of two protractor positions. All read as degrees before.
  it("(D): alternative angular units and derived angles decline", () => {
    expect(parseCircle("An arc of a circle of radius 10 cm subtends a central angle of 1.5 rads. Find the arc length.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 10 cm has a central angle of 100 grades. Find the sector area.")).toBeNull();
    expect(parseCircle("Find the arc length of a circle of radius 8 cm with a central angle of 0.5 of a revolution.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 12 cm has a central angle of one fourth of 360 degrees. Find the sector area.")).toBeNull();
    expect(parseCircle("An arc of a circle of radius 12 cm runs from the 90 degree position to the 150 degree position on a protractor. Find the length around the edge of the arc.")).toBeNull();
    expect(parseCircle("Find the area of 60 percent of a circular field of radius 20 m")).toBeNull();
  });

  // (E) NON-CIRCLE composite regions, qualified halves, annular bands stated as a width, and
  // the curved SIDE of a solid — each would have shipped the circle's own πr².
  it("(E): composite regions, qualified halves, annular bands and solid faces decline", () => {
    expect(parseCircle("A circle of radius 4 cm touches all four sides of a tile of side 8 cm. Find the area of the tile not covered by the circle.")).toBeNull();
    expect(parseCircle("A circle of radius 5 cm is cut from a card measuring 12 cm by 12 cm. Find the area of the card that remains.")).toBeNull();
    expect(parseCircle("A circular field has radius 7 m. A goat can reach only the northern half. Find the area the goat can graze.")).toBeNull();
    expect(parseCircle("A circular badge of radius 6 cm has its lower half painted red. Find the area painted red.")).toBeNull();
    expect(parseCircle("A circular window has radius 60 cm. Find the area of the upper half.")).toBeNull();
    expect(parseCircle("A circular pond of radius 7 m is surrounded by grass out to a fence 3 m away. Find the area of the grass.")).toBeNull();
    expect(parseCircle("Find the area of the curved side of a circular tin of radius 5 cm and height 10 cm")).toBeNull();
  });

  // (F) The shared GLYPH normaliser: the whole Unicode fraction block plus the typographic
  // U+2044 fraction slash, which a `\d+/\d+` token never matched ("3⁄4" read as a bare 3).
  it("(F): the full vulgar-fraction block and the U+2044 slash read exactly", () => {
    expect(ship("Find the area of a circle with radius 3⁄4 m")).toBe("9/16 π m² ≈ 1.7671 m²");
    expect(ship("Find the circumference of a circle with radius 3⁄4 m")).toBe("3/2 π m ≈ 4.7124 m");
    expect(ship("Find the area of a circle with radius 7⅑ cm")).toBe("4096/81 π cm² ≈ 158.8637 cm²");
    expect(ship("Find the area of a circle with radius 3⅐ cm")).toBe("484/49 π cm² ≈ 31.0312 cm²");
  });

  // (G) The shared SUBORDINATE-CLAUSE firewall: a when/while/where clause predicates its own
  // subject, so the MAIN clause's value is the quantity's. Previously the distractor won.
  it("(G): a subordinate clause no longer steals the predication", () => {
    expect(ship("The radius of a circular pond when the water level is 2 m deep is 14 m. Find the area.")).toBe("196π m² ≈ 615.7522 m²");
    expect(ship("The radius of a circle drawn while the pen width is 1 mm is 6 cm. Find the circumference.")).toBe("12π cm ≈ 37.6991 cm");
    expect(ship("The diameter of a circular table where each place setting is 40 cm wide is 180 cm. Find the circumference.")).toBe("180π cm ≈ 565.4867 cm");
    expect(ship("The central angle of a sector of a circle of radius 6 cm where the scale is 3 to 1 is 60 degrees. Find the arc length.")).toBe("2π cm ≈ 6.2832 cm");
  });
});

// ---------------------------------------------------------------------------
// ROUND-20 adversarial gate (28 confirmed violations, complete 35-agent sweep).
// The headline defect was ARCHITECTURAL: the angle reader had only two states, "a
// degree value" and `undefined`, and the dangling-angle guard tested `!== undefined`.
// So an angle the reader could NOT read (π/2, radians, a sweep "from 30° to 120°",
// "2^{c}") switched the safety OFF and shipped the whole disc — while the SAME problem
// written "90 degrees" declined correctly. The reader now returns a THIRD state,
// "unreadable", and the guard fails CLOSED on it.
// The other classes were fixed in the SHARED nl/ layer where they generalise: every
// reading of a named quantity (nl/quantity readBoundValues) so two objects can be told
// from one, and ask-clause extraction (nl/ask) so scenery cannot hijack the target.
// ---------------------------------------------------------------------------
describe("circle — ROUND-20 gate regressions", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) THE FAIL-OPEN ANGLE GUARD. An unreadable angle is the strongest reason to
  // decline, not a reason to proceed. Each of these shipped the WHOLE circle.
  it("(A): an angle that cannot be read declines instead of switching the guard off", () => {
    expect(parseCircle("A sprinkler at the centre of a circular lawn of radius 10 m turns through an angle of π/2. Find the area watered.")).toBeNull();
    expect(parseCircle("A searchlight at the centre of a circular field of radius 20 m sweeps from 30 degrees to 120 degrees. Find the area lit.")).toBeNull();
    expect(parseCircle("A circular protractor of radius 6 cm. Find the length around the circle from the 20 degree mark to the 80 degree mark.")).toBeNull();
    expect(parseCircle("A point on the rim of a circular disc of radius 10 cm moves as the disc turns through 1.5 radians. Find the distance it travels around the circle.")).toBeNull();
    expect(parseCircle("Find the area of the sector of a circle of radius 12 cm with a central angle of 30 + 45 degrees.")).toBeNull();
    expect(parseCircle("Find the arc length of a circle of radius 9 cm whose central angle is 2^{c}.")).toBeNull();
    // …and an angle-free problem must still read as "no angle" and ship normally, so the
    // fail-closed rule cannot be satisfied by declining everything.
    expect(ship("Find the area of a circle with radius 7 cm")).toBe("49π cm² ≈ 153.938 cm²");
    expect(ship("Find the area of the circle with radius 7 cm. Give your answer in terms of π.")).toBe("49π cm² ≈ 153.938 cm²");
  });

  // (B) NAMED ANGLE UNITS are exact multiples of 90°/180° — read them, do not take the
  // COUNT as the angle. "Subtends 2 right angles" had been shipping 2°.
  it("(B): 'N right angles' / 'N straight angles' read as exact degrees", () => {
    expect(ship("An arc of a circle of radius 6 cm subtends 2 right angles at the centre. Find the length of the arc.")).toBe("6π cm ≈ 18.8496 cm");
    expect(ship("The central angle of a sector of a circle of radius 14 cm is 2 right angles. Find the area of the sector.")).toBe("98π cm² ≈ 307.8761 cm²");
    expect(ship("An arc of a circle of radius 6 cm subtends 2 straight angles at the centre. Find the length of the arc.")).toBe("12π cm ≈ 37.6991 cm");
    expect(ship("An arc subtends 2 right angles at the centre of a circle of radius 14 cm. Find the arc length.")).toBe("14π cm ≈ 43.9823 cm");
    // A RELATIONAL fraction of one is still not a stated measure → decline.
    expect(parseCircle("A sector of a circle of radius 12 cm has a central angle of two thirds of a right angle. Find the sector area.")).toBeNull();
  });

  // (C) TWO OBJECTS, one ask. The same dimension named twice with different values is two
  // circles; the best-anchored reading is then the wrong one's. (nl/quantity readBoundValues)
  it("(C): a dimension named for two different objects declines", () => {
    expect(parseCircle("A circular pond of diameter 12 m has a fountain 60 cm in diameter at its centre. Find the area of the pond.")).toBeNull();
    expect(parseCircle("A coin 2 cm in diameter lies on a circular plate whose diameter is 30 cm. Find the area of the plate.")).toBeNull();
    expect(parseCircle("A coin 1 cm in radius lies on a circular table whose radius is 50 cm. Find the area of the table.")).toBeNull();
    // (The "d = 120 … coaster 10 cm across" pair moved to the ROUND-23 block: a span stated of
    // a DIFFERENT object is a distractor, not a competing reading — it now ships 3600π.)
    // ONE mention read at two tiers is the same object seen twice, and must still ship.
    expect(ship("A circular disc is 7 cm in radius and the table it rests on is 100 cm wide. Find the area of the disc.")).toBe("49π cm² ≈ 153.938 cm²");
    expect(ship("The radius of a circular pizza whose crust is 2 cm wide is 15 cm. Find the area of the pizza.")).toBe("225π cm² ≈ 706.8583 cm²");
  });

  // (D) THE ASK CLAUSE governs the target; a target noun in the scenery does not. (nl/ask)
  it("(D): target is read from the ask clause, not from scenery", () => {
    expect(ship("A circular garden has a radius of 7 m. A fence runs along its perimeter. How much area does the garden cover?")).toBe("49π m² ≈ 153.938 m²");
    expect(ship("A circular pizza of radius 10 inches has crust all round its circumference. What area of pizza is there?")).toBe("100π in² ≈ 314.1593 in²");
    expect(ship("A circular lawn of radius 7 m lies inside the boundary of the park. How much area of turf is needed?")).toBe("49π m² ≈ 153.938 m²");
    expect(ship("The area of the circle of radius 7 cm is given in the table. How long is the elastic that stretches exactly once round it?")).toBe("14π cm ≈ 43.9823 cm");
    // The DUAL-AREA ambiguity is a whole-text property and must survive the scoping.
    expect(parseCircle("The sector area is shown in the diagram and the central angle is 90 degrees. What is the area of the circle of radius 8 cm?")).toBeNull();
  });

  // (E) NON-CIRCLE figures the engine must not answer with πr²: a solid's side surface
  // named without the words "curved surface", concentric circles (an annulus), any half,
  // a shared-out portion, a SCALED dimension, and a polygon stated by its diagonals.
  it("(E): non-circle and part-circle regions decline", () => {
    expect(parseCircle("A circular flowerbed of radius 3 m sits at the centre of a circular lawn whose edge is 7 m from that centre. Find the area of the grass.")).toBeNull();
    expect(parseCircle("A circular tin of radius 7 cm and height 10 cm is wrapped in a paper label that covers its side exactly. Find the area of the label.")).toBeNull();
    expect(parseCircle("A party hat is made from card. Its circular base has radius 5 cm and its sloping side is 12 cm long. Find the area of the card used to make the curved part of the hat.")).toBeNull();
    expect(parseCircle("A circular sheet of paper of radius 6 cm is cut straight through the middle. Find the area of the resulting half.")).toBeNull();
    expect(parseCircle("A circular cake of radius 8 cm is shared by two friends equally. Find the area each gets.")).toBeNull();
    expect(parseCircle("The radius of a circle is 5 cm. Find the area of the circle when the radius is tripled.")).toBeNull();
    expect(parseCircle("A circle has radius 7 cm. Find the area of a circle with twice the radius.")).toBeNull();
    expect(parseCircle("A kite has diagonals 10 cm and 8 cm and contains a circle of radius 2 cm. Find the area of the kite.")).toBeNull();
    expect(parseCircle("A sector with a central angle of 90 degrees is drawn in a circle of radius 8 cm. What is the area of the circle within the sector?")).toBeNull();
  });
});

/**
 * ROUND-21 adversarial gate regressions.
 *
 * Every case below shipped a CONFIRMED WRONG value before these fixes. Two of them (the
 * "Note: … is not what is being asked" family and the "Fig. 3" split) were regressions
 * introduced by ROUND 20's own ask-clause scoping — the mechanism that stopped scenery
 * from hijacking the target let a DISCLAIMER and a figure reference do exactly that.
 */
describe("circle — ROUND-21 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) A DISCLAIMER names the wrong quantity precisely in order to exclude it; a META
  // sentence ("Note: …") comments rather than asks; an ABBREVIATION's full stop does not
  // end a sentence; a trailing ", which …" describes the figure. All four made the WRONG
  // noun the apparent ask, so the engine shipped the exact quantity the text ruled out.
  it("(A): disclaimers, notes, abbreviations and descriptions never become the ask", () => {
    expect(ship("Find the area of a circle of radius 7 cm. Note: the perimeter is not what is being asked.")).toBe("49π cm² ≈ 153.938 cm²");
    expect(ship("Find the circumference of a circle of radius 7 cm. Note which formula gives the area of the circle.")).toBe("14π cm ≈ 43.9823 cm");
    expect(ship("Find the arc length of a sector of radius 6 cm with a central angle of 60 degrees. Note: the sector area is not what is being asked.")).toBe("2π cm ≈ 6.2832 cm");
    expect(ship("Find the area of the sector of a circle of radius 6 cm with a central angle of 60 degrees. Which arc length is longer is not asked.")).toBe("6π cm² ≈ 18.8496 cm²");
    expect(ship("Calculate the area of the circle of radius 7 cm shown in Fig. 3, which has its perimeter drawn in red.")).toBe("49π cm² ≈ 153.938 cm²");
  });

  // (B) TWO OBJECTS stated with the SAME "N across" idiom. The idiom was read with a
  // non-global exec, so the FIRST match won regardless of which circle was asked about —
  // and the two-object firewall could not see it, because it keys on the literal nouns
  // "radius"/"diameter" and this idiom names neither.
  // ROUND 23: two spans are no longer ambiguous BY COUNT — they are ambiguous only when the
  // engine cannot tell which figure each belongs to. "A circular fountain stands in a PLAZA
  // 30 m across. The FOUNTAIN is 6 m across" states both spans with their subjects, and the
  // ask names the fountain, so it is determinate. A span whose subject cannot be recovered
  // ("a circular table in IT is 90 cm across") still leaves the asked figure unmeasured.
  it("(B): competing 'N across' readings resolve by SUBJECT, else decline", () => {
    expect(ship("A circular fountain stands in a plaza 30 m across. The fountain is 6 m across. Find the area of the fountain.")).toBe("9π m² ≈ 28.2743 m²");
    expect(ship("A river is 50 m across. A circular raft is 4 m across. Find the circumference of the raft.")).toBe("4π m ≈ 12.5664 m");
    // ROUND 27: this one is no longer a decline either. "A circular table IN IT is 90 cm
    // across" states the table's span perfectly clearly — the subject was unrecoverable only
    // because the reader captured the word immediately before the copula, which a locative
    // phrase displaces. Resolving the NP head recovers "table", the ask names the table, and
    // the problem is determinate.
    expect(ship("A hall is 4 m across. A circular table in it is 90 cm across. Find the area of the table.")).toBe(
      "2025π cm² ≈ 6361.7251 cm²"
    );
  });

  // (C) MANY FIGURES, or BOTH FACES of one: a total over N objects is not one circle's area.
  it("(C): multiple figures and two-sided totals decline", () => {
    expect(parseCircle("There are 5 circular tiles each of radius 3 cm. Find the total area of the tiles.")).toBeNull();
    expect(parseCircle("Four identical circular badges each have a diameter of 6 cm. Find the total area of the four badges.")).toBeNull();
    expect(parseCircle("Find the total area of both faces of a circular coin of radius 2 cm.")).toBeNull();
  });

  // (D) A FOLDED / CUT figure is a fraction of the disc, and a rug touching all four walls
  // is a statement about the SQUARE room, not about the rug.
  it("(D): partitioned figures and enclosing polygons decline", () => {
    expect(parseCircle("A circular sheet of radius 6 cm is folded in four. Find the area of the shape obtained.")).toBeNull();
    expect(parseCircle("A circular napkin of radius 8 cm is folded in three. Find the area of the resulting figure.")).toBeNull();
    expect(parseCircle("A circular cake of radius 8 cm is cut into four. Find the area of the smallest resulting figure.")).toBeNull();
    expect(parseCircle("A circular rug of radius 5 m exactly touches all four walls of a room. Find the area of the floor.")).toBeNull();
  });

  // (E) ANGLE notations the reader cannot fully consume. The Unicode superscript unit
  // carries no caret, so "2ᶜ" (2 radians) was read as 2 DEGREES — a 28.6× error; and a
  // COMPOUND angle's named part was read while its "+ 30 degrees" was silently dropped.
  it("(E): unicode superscript units and compound angles decline", () => {
    expect(parseCircle("The central angle of a sector of a circle of radius 14 cm is 2ᶜ. Find the arc length.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 10 cm has a central angle of 100ᵍ. Find the sector area.")).toBeNull();
    expect(parseCircle("Find the sector area of a circle of radius 6 cm whose central angle is one right angle plus 30 degrees.")).toBeNull();
    // A SIMPLE named angle is still read exactly — the guard must not swallow it.
    expect(ship("An arc of a circle of radius 12 cm subtends 2 right angles. Find the arc length.")).toBe("12π cm ≈ 37.6991 cm");
  });

  // (F) REPRESENTABILITY. A double cannot carry every integer past 2^53, and the display
  // underflows below 1e-12 — so the engine asserted a coefficient wrong in its last three
  // digits, and asserted that a strictly positive area was ZERO. Both are confident wrong
  // answers that the verify gate cannot catch, because it recomputes in the same doubles.
  it("(F): values the display cannot represent decline", () => {
    expect(ship("Find the area of a circle with radius 1234567891 cm")).toBeNull();
    expect(ship("A circular bacterial colony has a radius of 0.0000006 m. Find its area.")).toBeNull();
    // Ordinary magnitudes at both ends are unaffected.
    expect(ship("Find the area of a circle of radius 0.5 m")).toBe("1/4 π m² ≈ 0.7854 m²");
    expect(ship("Find the area of a circle of radius 1000 cm")).toBe("1000000π cm² ≈ 3141592.6536 cm²");
  });
});

/**
 * ROUND-22 adversarial gate regressions (first COMPLETE sweep: 39/39 agents, 0 errors).
 *
 * Eleven root causes. The two most instructive are at the ends of the pipeline: an angle
 * modifier the reader silently dropped rather than declined, and a FRACTION RENDERER that
 * printed a continued-fraction convergent as though it were the exact answer.
 */
describe("circle — ROUND-22 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) MULTIPLICATIVE and COMPARATIVE angle modifiers. "twice a right angle" fell past the
  // multiplier guard (which demanded a digit) into the named-angle reader, which bound the
  // DETERMINER "a" as its count — so it shipped 90° for a true 180°, exactly half, while the
  // very same engine read "two right angles" and "180 degrees" correctly. It disagreed with
  // itself, which is the signature of a dropped token rather than a convention dispute.
  it("(A): multiplicative and comparative angle modifiers decline", () => {
    expect(parseCircle("A sector of a circle of radius 8 cm subtends twice a right angle at the centre. Find the arc length.")).toBeNull();
    expect(parseCircle("In a circle of radius 12 cm an arc subtends three times a right angle at the centre. Find the arc length.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 9 cm has a central angle three times 25 degrees. Find the sector area.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 10 cm has a central angle twice as large as 40 degrees. Find the sector area.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 12 cm has a central angle twice as big as 30°. Find the area of the sector.")).toBeNull();
    expect(parseCircle("Find the arc length of a circle of radius 12 cm where the arc subtends an angle 30 degrees more than a right angle at the centre.")).toBeNull();
    expect(parseCircle("Find the area of the sector of a circle of radius 10 cm whose central angle is 15 degrees less than a straight angle.")).toBeNull();
    // The UNMODIFIED named angle must still be read exactly — the guard must not swallow it.
    expect(ship("An arc of a circle of radius 8 cm subtends two right angles at the centre. Find the arc length.")).toBe("8π cm ≈ 25.1327 cm");
  });

  // (B) Angle SUB-UNITS (DMS) and non-standard units (artillery mils, whose definition is
  // itself convention-dependent: 1/6400 vs 1/6000 turn). Only the leading number was consumed.
  it("(B): DMS and mils decline", () => {
    expect(parseCircle("Find the sector area of a circle of radius 6 cm with a central angle of 30 degrees 45 min.")).toBeNull();
    expect(parseCircle("Find the sector area of a circle of radius 4 cm with a central angle of 200 mils.")).toBeNull();
  });

  // (C) SEMI-DIAMETER is the classical name for the RADIUS and embeds the token "diameter",
  // so the value was halved. Normalised lexically before any dimension is read.
  it("(C): semi-diameter reads as the radius", () => {
    expect(ship("A circle has a semi-diameter of 5 cm. Find the area of the circle.")).toBe("25π cm² ≈ 78.5398 cm²");
    expect(ship("Find the circumference of a circle whose semidiameter is 6 cm.")).toBe("12π cm ≈ 37.6991 cm");
  });

  // (D) The ATTRIBUTIVE anchor — "a 14 CM DIAMETER circle" — was the one premodifier form
  // with no tier, so a later "whose diameter IS 90 cm" predicated the TABLE's size onto the
  // circle. With the tier in place both readings surface and the two-object firewall fires.
  it("(D): preposed dimension attributives are read, and conflicts decline", () => {
    expect(parseCircle("A 14 cm diameter circle sits on a round table whose diameter is 90 cm. Find the area of the circle.")).toBeNull();
    expect(parseCircle("A 5 cm radius circle is painted on a round tray whose diameter is 60 cm. Find the area of the circle.")).toBeNull();
    // With no competing object the attributive is simply the given.
    expect(ship("A 14 cm diameter circle is drawn. Find its area.")).toBe("49π cm² ≈ 153.938 cm²");
  });

  // (E) The dimension stated INDIRECTLY — as a fraction of itself, or as an unevaluated sum.
  it("(E): indirect dimension givens decline", () => {
    expect(parseCircle("A quarter of the diameter of a circle is 2 cm. Find the area.")).toBeNull();
    expect(parseCircle("A quarter of the radius of a circle is 2 cm. Find the area.")).toBeNull();
    expect(parseCircle("The diameter of the circle is 3 cm plus 5 cm. Find the area of the circle.")).toBeNull();
  });

  // (F) COVERING asks name a MATERIAL, not the word "area" — so the ask clause carried no
  // area cue at all and a scenery boundary ("a cornice runs along the boundary", "a fence
  // around the circle") won the target and shipped a LENGTH for an AREA question.
  it("(F): covering asks are area asks", () => {
    expect(ship("A circular ceiling has a radius of 3 m. A cornice runs along the boundary of the ceiling. How much paint is needed to cover the whole ceiling?")).toBe("9π m² ≈ 28.2743 m²");
    expect(ship("A circular lawn has a radius of 7 m. The boundary of the lawn is painted white. How much turf is needed to cover the lawn?")).toBe("49π m² ≈ 153.938 m²");
    expect(ship("A circular lawn of radius 8 m has a fence around the circle. How much turf is needed to cover the lawn?")).toBe("64π m² ≈ 201.0619 m²");
    // …and the mirror image: a boundary ask whose scenery mentions the area.
    expect(ship("A circular tray has a radius of 7 cm. The area of the circle is printed underneath. Find the length of the gold hoop fitted to its edge.")).toBe("14π cm ≈ 43.9823 cm");
    expect(ship("A circular plate has a diameter of 20 cm. The area of the circle is stamped on the back. Find the length of the silver hoop soldered to it.")).toBe("20π cm ≈ 62.8319 cm");
    // An INTERROGATIVE outranks a later instruction about a formula.
    expect(ship("What is the circumference of a circle of radius 7 cm? State the area formula.")).toBe("14π cm ≈ 43.9823 cm");
  });

  // (G) Regions that are not the disc: a solid painted all over, an annular mown strip named
  // by its width alone, and a rectangle whose length and width are both given.
  it("(G): non-circle regions decline", () => {
    expect(parseCircle("A circular drum of radius 3 m and height 2 m is to be painted all over. Find the area to be painted.")).toBeNull();
    expect(parseCircle("A circular field has radius 20 m. A tractor mows a strip 3 m wide around the edge. Find the area mown.")).toBeNull();
    expect(parseCircle("A circular pond of radius 7 m sits in a garden of length 20 m and width 15 m. Find the area of the garden.")).toBeNull();
  });

  // (H) A FRACTION of the figure named with an everyday noun, and N circuits of the boundary.
  it("(H): fractions of the figure and multiple circuits decline", () => {
    expect(parseCircle("A circular pizza has a radius of 12 cm. Ravi eats a third of the pizza. Find the area he eats.")).toBeNull();
    expect(parseCircle("A circular window of radius 50 cm is a quarter covered by frost. Find the area covered by frost.")).toBeNull();
    expect(parseCircle("Find the area of both faces of a circular coin of radius 2 cm.")).toBeNull();
    expect(parseCircle("A circular running track has a radius of 40 m. Find the distance around it for 2 laps.")).toBeNull();
  });

  // (I) THE EXACT-RATIONAL RENDERER. mathjs `fraction()` returns the best continued-fraction
  // CONVERGENT — an approximation. It was trusted, so r = 1000.2 printed 10003000000/9999 for
  // a true 25010001/25: a WRONG EXACT RATIONAL that the substitution gate cannot catch,
  // because the decimal it verifies against does agree. Terminating values now convert
  // exactly from their own decimal expansion; a convergent is accepted only if it reproduces
  // the value to full double precision, which is what keeps the genuine 100/3 working.
  it("(I): rendered fractions are exact, not convergents", () => {
    expect(ship("Find the area of a circle with radius 1000.2 cm")).toBe("25010001/25 π cm² ≈ 3142849.4163 cm²");
    expect(ship("Find the sector area of a circle with radius 480.6 cm and a central angle of 179 degrees")).toBe("114846579/1000 π cm² ≈ 360801.1689 cm²");
    // Too fine to reduce inside the fraction bound → an EXACT terminating decimal instead.
    expect(ship("Find the sector area of a circle with radius 30.9 cm and a central angle of 111.4 degrees")).toBe("295.46065π cm² ≈ 928.217 cm²");
    // Genuinely REPEATING rationals must still render as fractions.
    expect(ship("A sector of a circle of radius 10 cm has angle 120. Find the sector area.")).toBe("100/3 π cm² ≈ 104.7198 cm²");
    expect(ship("Find the area of a circle with radius 7⅑ cm")).toBe("4096/81 π cm² ≈ 158.8637 cm²");
  });
});

describe("circle — ROUND-23 gate regressions", () => {
  const ship = (latex: string) => {
    const spec = parseCircle(latex);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  // (A) SUBJECT-BOUND SPANS. "N units wide/across/long" states a diameter, but the decisive
  // question was never "what spans are stated?" — it is "does this span belong to the figure
  // being ASKED about?". Count-based arbitration was simultaneously too weak (one span, on
  // scenery, sized the wrong figure) and too strong (two spans, one plainly the asked figure,
  // declined a determinate problem). nl/quantity now reads every span WITH its subject noun and
  // nl/ask returns the asked figure's HEAD noun, so the two are directly comparable.
  it("(A): a span sizes the figure it is predicated OF", () => {
    expect(ship("A circular tabletop is 90 cm wide. A coaster on it has radius 5 cm. Find the area of the tabletop.")).toBe("2025π cm² ≈ 6361.7251 cm²");
    expect(ship("A circular pond is 12 m wide. A stone of radius 3 m lies beside it. Find the area of the pond.")).toBe("36π m² ≈ 113.0973 m²");
    expect(ship("A circular clock face is 24 cm wide. Its hour hand has radius 9 cm. Find the circumference of the clock face.")).toBe("24π cm ≈ 75.3982 cm");
    expect(ship("A circular table is 120 cm wide. A plate on it is 24 cm across. Find the area of the table.")).toBe("3600π cm² ≈ 11309.7336 cm²");
    // "LONG" is NOT a span (see nl/quantity SPAN_IDIOM): the same words read as a radial arm,
    // a boundary, or a disc, so the lawn is unmeasured — and the POT's diameter, stated in a
    // clause that introduces a competing circular figure, must not size it either.
    expect(
      parseCircle(
        "A circular lawn is 30 m long. A circular pot of diameter 40 cm stands on it. Find the circumference of the lawn."
      )
    ).toBeNull();
    // …and a span that belongs to scenery leaves the asked figure unmeasured.
    expect(parseCircle("A circular fountain sits in a courtyard 40 m across. Find the area of the fountain.")).toBeNull();
  });

  // (B) COVERING asks. Making "cover" an AREA cue in ROUND 22 hijacked BOUNDARY asks: "how much
  // fencing is needed to COVER THE BOUNDARY" shipped 25π m² for a true 10π m. What is covered
  // decides the target, not the verb.
  it("(B): 'cover the boundary/edge/outline' is a circumference ask", () => {
    expect(ship("A circular pond has a radius of 5 m. How much fencing is needed to cover the boundary?")).toBe("10π m ≈ 31.4159 m");
    expect(ship("A circular badge has a radius of 3 cm. How much gold wire is needed to cover its outline?")).toBe("6π cm ≈ 18.8496 cm");
    expect(ship("A circular clock face has a diameter of 20 cm. How much tape is needed to cover its edge?")).toBe("20π cm ≈ 62.8319 cm");
    expect(ship("What length of ribbon will cover the edge of a circular badge of radius 3 cm?")).toBe("6π cm ≈ 18.8496 cm");
  });

  // (C) PIE-CHART DISTRACTORS. The "angle at the centre" phrase reader stops at the first digit,
  // so a count naming a DIFFERENT noun was captured as the angle: "the angle at the centre of the
  // sector FOR 30 STUDENTS is 120 degrees" bound 30 (27/4 π for a true 27π). The stated angle is
  // the one carrying the degree unit.
  it("(C): a count label never outranks the degree-marked angle", () => {
    expect(ship("A circle has radius 9 cm. The angle at the centre of the sector for 30 students is 120 degrees. Find the sector area.")).toBe("27π cm² ≈ 84.823 cm²");
    expect(ship("A circle has radius 9 cm. The angle at the centre of the sector for 30 students is 120 degrees. Find the arc length.")).toBe("6π cm ≈ 18.8496 cm");
    expect(ship("In a circle of radius 10 cm, the angle at the centre of sector 2 is 60 degrees. Find the sector area.")).toBe("50/3 π cm² ≈ 52.3599 cm²");
    expect(ship("The angle at the center of the sector showing 20 cars is 90 degrees. The circle has radius 8 cm. Find the sector area.")).toBe("16π cm² ≈ 50.2655 cm²");
  });

  // (D) REGIONS THAT ARE NOT THE WHOLE FIGURE, restated in prose the earlier guards missed.
  it("(D): partial regions and non-circle solids decline", () => {
    expect(parseCircle("A sector of a circle of radius 12 cm has a central angle of 30 degrees. How much of the circle's area does the sector cover?")).toBeNull();
    expect(parseCircle("A sector AOB of a circle of radius 10 cm has a central angle of 36 degrees. Find the area of the circle enclosed by OA, the arc AB and OB.")).toBeNull();
    expect(parseCircle("A circle of radius 14 m has a sector of central angle 90 degrees. Calculate the area of the circle enclosed by the sector.")).toBeNull();
    expect(parseCircle("The arc AB makes a right angle at the centre of a circle of radius 6 cm. Find the length of circumference cut off by the arc AB.")).toBeNull();
    expect(parseCircle("Find the area of an octant of a circle of radius 8 cm")).toBeNull();
    expect(parseCircle("A circular garden of radius 8 m is crossed by a hedge that goes right through the middle from edge to edge. Find the area of the garden on one side of the hedge.")).toBeNull();
    expect(parseCircle("A circular tank of radius 3 m and height 5 m is made of metal. Find the area of the metal sheet needed to make its side.")).toBeNull();
    expect(parseCircle("A circular flowerbed of radius 4 m sits inside a circular lawn whose edge is 9 m from the same point. Find the area of the lawn around the flowerbed.")).toBeNull();
    expect(parseCircle("A circular ball of radius 7 cm is to be covered in leather. Find the area of leather needed.")).toBeNull();
    expect(parseCircle("A circular pizza has a radius of 12 cm. Ravi eats a sixth. Find the area Ravi eats.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 6 cm has a central angle twice the angle of 30 degrees. Find the sector area.")).toBeNull();
  });

  // (E) EXACT ARITHMETIC. A double coefficient holds ~15 significant digits, so r = 111111.1111
  // squared to 12345679009.876543 and the renderer published 24691358019753/2000 — a confident
  // WRONG exact rational (true: 1234567900987654321/100000000). The substitution gate cannot see
  // it: it re-squares the same double and agrees with itself. The coefficient is now computed in
  // exact integer arithmetic from the givens, and declines when the true value needs more digits
  // than the display contract can carry.
  it("(E): a coefficient that exceeds exact representation declines", () => {
    expect(parseCircle("Find the area of a circle with radius 111111.1111 cm")).toBeTruthy();
    expect(solveCircle(parseCircle("Find the area of a circle with radius 111111.1111 cm")!)).toBeNull();
    expect(solveCircle(parseCircle("Find the area of a circle with radius 12345678.9 cm")!)).toBeNull();
    // ROUND 27: scientific notation is no longer a decline. It used to be one because the
    // reader took the MANTISSA and dropped the exponent, which is a misread, not a limitation —
    // resolving "1.5 x 10^2" to 150 is an exact decimal-point shift with no second reading, so
    // the given is now read faithfully and the answer ships.
    expect(ship("Find the area of a circle of radius 1.5 x 10^2 cm")).toBe(
      "22500π cm² ≈ 70685.8347 cm²"
    );
    // …while every exactly-representable rational still ships exactly.
    expect(ship("Find the area of a circle with radius 7⅑ cm")).toBe("4096/81 π cm² ≈ 158.8637 cm²");
    expect(ship("Find the area of a circle with radius 3⁄4 m")).toBe("9/16 π m² ≈ 1.7671 m²");
    expect(ship("Find the area of a circle with radius 1000.2 cm")).toBe("25010001/25 π cm² ≈ 3142849.4163 cm²");
  });
});

/**
 * ROUND-24 adversarial gate (wf_9843c9e8-3d8, 30/30 agents, 22 confirmed violations).
 *
 * Two thirds of this round were MY OWN ROUND-23 regressions, and both have the same shape: a
 * cue that looks decisive locally but carries several incompatible readings.
 *   • "N units LONG" was admitted as a span. It is three different quantities — a RADIAL ARM
 *     ("the minute hand is 14 cm long" → the radius), a BOUNDARY ("a circular path is 44 m
 *     long" → the circumference, an inverse problem this engine declines), and a DISC ("a
 *     circular lawn is 30 m long" → the diameter) — so reading it as one shipped
 *     exactly-half and π-times-too-big answers as verified:true. It is now unread.
 *   • A covering ask was targeted by the noun of the thing COVERED ("cover it up to the
 *     EDGE" → circumference). The MATERIAL fixes the dimension far more reliably: fencing,
 *     ribbon and wire are LENGTHS; turf, paint and carpet are AREAS.
 */
describe("circle — ROUND-24 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  it("(A): 'N units long' is not a span — a radial arm is not a diameter", () => {
    expect(
      parseCircle(
        "The minute hand of a clock is 14 cm long. Find the length of the arc it traces when it turns through 90 degrees."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A pendulum is 20 cm long. Find the length of the arc through which the bob swings for a central angle of 30 degrees."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A goat is tied to a post by a rope 7 m long and grazes a circular patch of grass. How much area can the goat graze?"
      )
    ).toBeNull();
  });

  it("(B): a stated BOUNDARY length is the inverse problem, never a diameter", () => {
    expect(
      parseCircle("A circular path around a pond is 44 m long. What is the circumference of the pond?")
    ).toBeNull();
    expect(parseCircle("A circular racetrack is 400 m long. Find the area it encloses.")).toBeNull();
    expect(
      parseCircle("A circular path around a lake is 88 m long. Find the area of the lake.")
    ).toBeNull();
    expect(
      parseCircle("A circular moat is 50 m long around the castle. Find the area inside.")
    ).toBeNull();
    expect(
      parseCircle("A wire is 88 cm long. It is bent into a circle. How much area does the circle enclose?")
    ).toBeNull();
  });

  it("(C): a covering ask takes its dimension from the MATERIAL, not the covered noun", () => {
    expect(ship("A circular lawn has a radius of 7 m. How much turf is needed to cover it right up to the edge?")).toBe(
      "49π m² ≈ 153.938 m²"
    );
    expect(ship("How much paint is needed to cover a circular lid of diameter 12 cm right to its rim?")).toBe(
      "36π cm² ≈ 113.0973 cm²"
    );
    expect(ship("How much fencing is needed to cover the outside of a circular pen of radius 5 m?")).toBe(
      "10π m ≈ 31.4159 m"
    );
    expect(ship("How much ribbon is needed to cover the hem of a circular tablecloth of radius 7 cm?")).toBe(
      "14π cm ≈ 43.9823 cm"
    );
  });

  it("(D): angle units this engine does not convert, and angles that are RATES", () => {
    expect(
      parseCircle(
        "A sector of a circle of radius 12 km has a central angle of 30 arc minutes. Find the length of the arc."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "Find the length of the arc of a circle of radius 9 cm with a central angle of 100 centesimal degrees."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A radar antenna at the centre of a circle of radius 10 km rotates through 15 degrees every second. Find the area of the sector it sweeps in 4 seconds."
      )
    ).toBeNull();
  });

  it("(E): partial regions, partitions, compound boundaries and solids", () => {
    expect(
      parseCircle(
        "A sector of radius 6 cm has a central angle of 90 degrees. Find the total length of the arc and the two radii bounding it."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circular flowerbed of radius 3 m sits in the middle of a circular lawn that is 20 m across. Find the area of the grass."
      )
    ).toBeNull();
    expect(
      parseCircle("A circular field of radius 8 m is fenced into four equal plots. Find the area of one plot.")
    ).toBeNull();
    expect(
      parseCircle(
        "A circular cake of radius 10 cm is sliced right down the middle. Find the area of the top of one of the two resulting parts."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circular pipe has radius 3 cm and length 100 cm. Find the area of paint needed to coat the outside of the pipe."
      )
    ).toBeNull();
    expect(
      parseCircle("A circle of radius 6 cm is drawn on a quadrilateral of area 200 cm2. Find the area of the quadrilateral.")
    ).toBeNull();
  });

  it("(F): a cylinder's height must be asserted in the MAIN clause to disqualify the circle", () => {
    // The height sits in a relative clause DESCRIBING the tank; the ask is still a plain circle.
    expect(ship("The diameter of a circular tank that measures 3 m tall is 10 m. Find the area.")).toBe(
      "25π m² ≈ 78.5398 m²"
    );
  });

  it("(G): the exact coefficient is shown only when the decimal cannot say it", () => {
    // [ROUND 28] 841/800000 IS 0.00105125 exactly — it only looked inexpressible because the
    // old printer used toFixed(6), which truncates every significant digit below 1e-6. The
    // printer now measures SIGNIFICANT digits (toPrecision(15) + a length test), so a
    // terminating value prints in full whatever its magnitude, and the readable form wins.
    expect(ship("Find the sector area of a circle with radius 0.87 cm and central angle 0.5 degrees")).toBe(
      "0.00105125π cm² ≈ 0.0033 cm²"
    );
    // 5909213/20000 IS its decimal exactly → show the readable form.
    expect(ship("Find the sector area of a circle of radius 30.9 cm with a central angle of 111.4 degrees")).toBe(
      "295.46065π cm² ≈ 928.217 cm²"
    );
  });
});

/**
 * ROUND-25 adversarial gate (wf_29900e01-a34 — an INCOMPLETE sweep: 10/18 agents finished,
 * 8 died on a session limit, so 7 confirmed is a floor, not a measurement). Two root causes.
 *
 *   • A ROTATION IS A SWEEP. The orientation-distractor list carried `rotat\w*(?!\s+through)`
 *     to catch "the page is rotated 25°", and it discarded the real swept angle of every
 *     problem phrased without the preposition — leaving the problem's ACTUAL distractor as the
 *     only surviving candidate. What marks an orientation is the static mounting predicate
 *     ("set at", "braced at"), not the verb.
 *   • NON-DISC REGIONS. An annulus stated as a wall thickness or an offset from the edge, a
 *     fold worded without "into two", and a half-disc under a flat floor level with the centre all
 *     reached a bare πr².
 */
describe("circle — ROUND-25 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  it("(A): a swept angle beats a mounting angle, preposition or no preposition", () => {
    expect(
      ship(
        "A sprinkler rotates 120 degrees to water a sector of a circle of radius 9 m. The feed pipe is set at 40 degrees to the ground. Find the area of the sector watered."
      )
    ).toBe("27π m² ≈ 84.823 m²");
    expect(
      ship(
        "A radar antenna rotates 80 degrees, scanning a sector of a circle of radius 15 km. The mast is braced at 25 degrees. Find the area of the sector scanned."
      )
    ).toBe("50π km² ≈ 157.0796 km²");
    expect(
      ship(
        "A wheel of radius 18 cm rotates 60 degrees. The axle is set at 20 degrees. Find the arc length of the sector turned through."
      )
    ).toBe("6π cm ≈ 18.8496 cm");
    // …and the orientation distractor still loses to a stated angle, as it always did.
    expect(
      ship("A sector of a circle of radius 10 cm has angle 120. It is inclined at 30 degrees. Find the sector area.")
    ).toBe("100/3 π cm² ≈ 104.7198 cm²");
  });

  it("(B): an annulus stated as a thickness or an edge offset is not a disc", () => {
    expect(
      parseCircle(
        "A circular pipe has an internal radius of 4 cm and its metal wall is 1 cm thick. Find the area of the cross-section of the metal."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circular pond of radius 5 m has a circular fence built 2 m out from its edge. Find the area enclosed by the fence."
      )
    ).toBeNull();
  });

  it("(C): a fold and a flat floor level with the centre both halve the disc", () => {
    expect(
      parseCircle(
        "A circular pizza is folded once so the edges meet exactly. The radius is 12 cm. Find the area of the folded shape."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circular tunnel entrance has a flat floor at the level of its centre. The circular arch above has radius 4 m. Find the area of the entrance."
      )
    ).toBeNull();
  });
});

/**
 * ROUND-26 adversarial gate (wf_ff93b9d8-6b8 — a COMPLETE sweep: 33/33 agents, 0 errors,
 * 25 confirmed). Six root causes, four of them in the shared nl/ layer:
 *
 *   • THE TARGET BELONGS TO THE ASK. Every target cue scanned the whole problem, so a
 *     quantity named in the SCENERY captured it — the exact failure nl/ask.ts was written
 *     for, applied to the givens but never to the target.
 *   • A relative clause was treated as governing the rest of its sentence, so a dimension
 *     stated of one figure was disowned from the figure that followed it.
 *   • "Fig. 2" — an abbreviating full stop the label-stripper could not cross, so the FIGURE
 *     NUMBER became the radius; and "radius OA = 7 cm" had no reader at all.
 *   • A fraction is an EXACTNESS CLAIM. The fallback printed a continued-fraction convergent.
 */
describe("circle — ROUND-26 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  it("(A): a mixed-number span keeps its whole part", () => {
    expect(ship("A circular badge, 2½ cm across, is pinned on a shirt. Find the area.")).toBe(
      "25/16 π cm² ≈ 4.9087 cm²"
    );
    expect(ship("A circular pond, 3 1/2 m across, lies in the park. Find the circumference.")).toBe(
      "7/2 π m ≈ 10.9956 m"
    );
  });

  it("(B): a relative clause governs its own clause, not the rest of the sentence", () => {
    expect(
      ship("A circular tray whose diameter is 20 cm holds a circular plate 6 cm across. Find the area of the plate.")
    ).toBe("9π cm² ≈ 28.2743 cm²");
    expect(
      ship(
        "A circular tray whose diameter is 20 cm holds a circular plate 6 cm across. Find the circumference of the plate."
      )
    ).toBe("6π cm ≈ 18.8496 cm");
  });

  it("(C): the target is read from the ASK, the givens from the whole text", () => {
    expect(
      ship("The area of a circular garden of radius 6 m is shown on the plan. Find the length of the hedge that surrounds it.")
    ).toBe("12π m ≈ 37.6991 m");
    expect(
      ship(
        "A plan shows the area of the circular lawn of radius 10 m. Find the length of the garland that will be laid along the edge."
      )
    ).toBe("20π m ≈ 62.8319 m");
    expect(
      ship("A ribbon runs around the edge of a circular rug of radius 3 m. How much space does the rug take up on the floor?")
    ).toBe("9π m² ≈ 28.2743 m²");
    expect(
      ship("A rubber seal runs around the rim of a circular window of radius 5 m. How much glass is needed for the window?")
    ).toBe("25π m² ≈ 78.5398 m²");
    // …and an ANSWER-FORMAT sentence is not the ask, however many ask cues it carries.
    expect(ship("Find the area of the circle with radius 7 cm. Give your answer in terms of π")).toBe(
      "49π cm² ≈ 153.938 cm²"
    );
  });

  it("(D): a figure caption's number is not a dimension; a point label does not hide one", () => {
    expect(ship("In Fig. 2 radius OA = 7 cm. Find the area of the circle.")).toBe("49π cm² ≈ 153.938 cm²");
    expect(ship("In Fig. 3 diameter AB = 20 cm. Find the circumference of the circle.")).toBe("20π cm ≈ 62.8319 cm");
    expect(ship("In Fig. 7 central angle POQ measures 90 degrees and the radius is 8 cm. Find the sector area.")).toBe(
      "16π cm² ≈ 50.2655 cm²"
    );
    expect(
      ship("In Fig. 2 central angle AOB measures 60 degrees. The radius of the circle is 10 cm. Find the length of the arc.")
    ).toBe("10/3 π cm ≈ 10.472 cm");
  });

  it("(E): every spelling of π, and angle units glued to their digits", () => {
    // U+1D70B MATHEMATICAL ITALIC SMALL PI — a radian angle no π-guard could see.
    expect(parseCircle("A sector of a circle of radius 6 cm has a central angle of 2𝜋/3. Find the sector area.")).toBeNull();
    expect(parseCircle("Find the arc length of a circle of radius 9 cm whose central angle is 2𝜋/3.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 6 cm has a central angle of 2rad. Find the sector area.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 9 cm has a central angle of 1.5rad. Find the arc length.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 6 cm has a central angle of 100gon. Find the sector area.")).toBeNull();
  });

  it("(F): solids, encircling bands, and figures counted more than once", () => {
    expect(
      parseCircle(
        "A circular pond has a radius of 5 m. A path 1 m in width runs around it. Find the total area of the pond and the path."
      )
    ).toBeNull();
    expect(
      parseCircle("A circular candle has a radius of 3 cm and is 12 cm tall. Find the area of the wax on the side of the candle.")
    ).toBeNull();
    expect(parseCircle("Find the total area of the two faces of a circular coin of radius 1 cm.")).toBeNull();
    expect(
      parseCircle("How much fabric is needed to cover the top and the bottom of a circular cushion of radius 20 cm?")
    ).toBeNull();
    expect(parseCircle("A pair of circular badges each of radius 3 cm. Find the total area.")).toBeNull();
    expect(parseCircle("A rope goes twice around a circular post of radius 3 cm. What length of rope is needed?")).toBeNull();
    // …and a path that merely runs PAST the circle is still scenery, not a band around it.
    expect(ship("A path 2 m wide runs past a circle of radius 14 cm; find the circumference of the circle")).toBe(
      "28π cm ≈ 87.9646 cm"
    );
  });

  it("(G): a printed fraction is an exactness claim — never a convergent", () => {
    // The exact coefficient needs a 3.6-million denominator; the old fallback printed
    // 960120/121 π, which is not the number.
    // [ROUND-31] …and neither was the decimal this test used to expect. 28565553719/3600000
    // REPEATS (the 9 in 3600000), so "7934.876033π" is a rounding wearing an exactness claim —
    // the same defect as the convergent, just quieter. An ugly exact fraction is the only
    // honest form for a repeating coefficient; terminating ones still print as decimals.
    expect(ship("Find the sector area of a circle with radius 109.1 cm and central angle 239.99 degrees")).toBe(
      "28565553719/3600000 π cm² ≈ 24928.1483 cm²"
    );
    expect(ship("Find the sector area of a circle with diameter 100.6580 cm and central angle 239.97 degrees")).toBe(
      "20261532919759/12000000000 π cm² ≈ 5304.4569 cm²"
    );
  });
});

/**
 * ROUND-27 adversarial gate (wf_c76d0b0e-23e — a COMPLETE sweep: 29/29 agents, 0 errors,
 * 22 confirmed). Six root causes, four of them in the shared nl/ layer again:
 *
 *   • A LOCATIVE PHRASE DISPLACES THE SUBJECT. "A circular tin ON IT is 20 cm across"
 *     captured "it", the reading was dropped, and a SHELF's width was left as the only span
 *     in the text — so the shelf sized the tin. Dropping a reading is not the safe direction
 *     when a competing one survives; resolve the NP head instead.
 *   • THE ASK CAN NAME ITS OBJECT IN THE SUBJECT SLOT — "how much area DOES THE TIN COVER?"
 *     is the same question as "the area OF THE TIN", and only one of them had a reader.
 *   • AN EXPONENT IS PART OF THE NUMBER. "10²", "10^2", "1.5e2", "2^3", "1.5\times10^{2}" all
 *     read as their MANTISSA — and the trailing unit, sitting behind the exponent, was lost
 *     with it. Resolving is exact (decimal-point shifts, BigInt powers): no second reading.
 *   • `\b` IS THE WRONG BOUNDARY FOR A TeX MACRO. A control word ends at the first NON-letter,
 *     so `\sqrt2` and `\times20` slipped both parse-integrity guards written to stop them.
 */
describe("circle — ROUND-27 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  it("(A): a locative phrase does not steal the span's subject", () => {
    expect(ship("A shelf is 60 cm wide. A circular tin on it is 20 cm across. How much area does the tin cover?")).toBe(
      "100π cm² ≈ 314.1593 cm²"
    );
    expect(
      ship("A bench is 150 cm wide. A circular plate on it is 24 cm across. How much area does the plate cover?")
    ).toBe("144π cm² ≈ 452.3893 cm²");
    // …and with the ask made by a PRONOUN, the head is unrecoverable — but only one of the two
    // nouns is ever called circular, and a corridor's width is not a circle's diameter.
    expect(ship("A corridor is 3 m wide. A circular rug in it is 120 cm across. Find its circumference.")).toBe(
      "120π cm ≈ 376.9911 cm"
    );
    // The head noun is the NP's, never the locative phrase's object: the plate, not the table.
    expect(ship("A circular plate on the table is 24 cm across. Find the area of the plate.")).toBe(
      "144π cm² ≈ 452.3893 cm²"
    );
  });

  it("(B): the SUPPLIED material fixes the dimension; a named unit outranks it", () => {
    // "hedge" is a linear material — but it is what the turf is laid UP TO, not what is asked for.
    expect(ship("A circular lawn has a radius of 5 m. How much turf is needed to cover the lawn up to the hedge?")).toBe(
      "25π m² ≈ 78.5398 m²"
    );
    // …and mesh is sold by area, yet "HOW MANY METRES OF" states the answer's dimension outright.
    expect(ship("How many metres of mesh are needed to go right round a circular pen of radius 4 m?")).toBe(
      "8π m ≈ 25.1327 m"
    );
  });

  it("(C): an angle written as a calculation, or stated 'at the centre' in radians", () => {
    expect(parseCircle("A sector of a circle of radius 6 cm has central angle 2 x 30 degrees. Find the area of the sector.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 6 cm has a central angle of 3\\times20 degrees. Find the sector area.")).toBeNull();
    // No angle word anywhere in this one — "at the centre" is what makes π/2 a central angle.
    expect(parseCircle("A circular fan of radius 20 cm opens π/2 at the centre. Find the area it covers.")).toBeNull();
  });

  it("(D): the exponent is part of the number — and so is the unit behind it", () => {
    expect(ship("Find the area of a circle with radius 10² cm")).toBe("10000π cm² ≈ 31415.9265 cm²");
    expect(ship("Find the sector area of a circle with radius 10^2 cm and central angle 90 degrees")).toBe(
      "2500π cm² ≈ 7853.9816 cm²"
    );
    expect(ship("Find the area of a circle with radius 1.5e2 cm")).toBe("22500π cm² ≈ 70685.8347 cm²");
    expect(ship("Find the area of a circle with radius 2^3 cm")).toBe("64π cm² ≈ 201.0619 cm²");
    expect(ship("A circle has a radius of 1.5\\times10^{2} cm. Find the area of the circle.")).toBe(
      "22500π cm² ≈ 70685.8347 cm²"
    );
    // A SQUARED UNIT is not a power of a number, and the radian/gradian superscripts are not
    // exponents either — none of them may be resolved away.
    expect(ship("A circle has an area of 36 cm^2. Find the circumference.")).toBeNull();
    expect(parseCircle("A sector of a circle of radius 9 cm has a central angle of 2^{c}. Find the arc length.")).toBeNull();
  });

  it("(E): an unbraced TeX macro is still that macro", () => {
    expect(ship("A circle has a radius of \\frac12 cm. Find the area of the circle.")).toBe(
      "1/4 π cm² ≈ 0.7854 cm²"
    );
    // …and an irrational given cannot survive the flatten, braces or no braces → decline.
    expect(parseCircle("A circle has a radius of \\sqrt2 cm. Find the area of the circle.")).toBeNull();
  });

  it("(F): bands, overhangs, bisecting chords and counted multiplicities", () => {
    expect(
      parseCircle("A circular pond of radius 3 m is surrounded by a grass border of width 2 m. Find the area of the grass.")
    ).toBeNull();
    expect(
      parseCircle(
        "A circular fountain of radius 4 m is ringed by flagstones of width 1 m. Find the area covered by the flagstones."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circular table of radius 40 cm is covered by a cloth which overhangs the edge by 10 cm. Find the area of the cloth."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circular plate of radius 9 cm sits on a mat that extends 3 cm beyond it all the way round. Find the area of the mat."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circular field of radius 30 m is separated by a straight fence running from one point on the rim to the point directly opposite. Sheep graze only the part of the field north of the fence. Find the area the sheep graze."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circular flower bed has a radius of 7 m. Three strands of rope are to be run around it. Find the total length of rope needed."
      )
    ).toBeNull();
    expect(parseCircle("The circular lid of a tin has a radius of 5 cm. Find the total area of the lid and the base.")).toBeNull();
  });
});

/**
 * ROUND-28 adversarial gate (wf_4efcf98e-625 — a COMPLETE sweep: 0 errors, 22 confirmed).
 * Nine root causes, five of them in the shared nl/ layer:
 *
 *   • AN NP HEAD IS FINAL; A MODIFIER PP IS STRIPPED FROM THE RIGHT. Cutting the noun phrase
 *     at the FIRST preposition scanning left-to-right kept "a circle is drawn" and returned
 *     the PARTICIPLE "drawn" as a span's subject — which then passed the circular-subject
 *     test by matching "circle is drawn". Strip a TRAILING PP instead, and only for the
 *     COPULAR frame ("a circular table IN IT is 90 cm across"); the ATTRIBUTIVE frame
 *     ("a card 40 cm wide") heads on the noun immediately before the span, not after it.
 *   • A SPAN ON A SUBJECT THE TEXT NEVER MARKS CIRCULAR IS INADMISSIBLE, not merely lower
 *     priority — unless that subject IS the ask object. A card's width is not a candidate
 *     diameter for the circle drawn on it, however few other readings survive.
 *   • AN INSTRUCTION *ABOUT* THE ANSWER IS NOT THE ASK — already true of "give your answer in
 *     terms of π", and equally true of "What is the FORMULA for the circumference?": it names
 *     a quantity in the abstract, with no figure and no givens, and hijacked the target from
 *     the numeric question that had both. (nl/ask FORMULA_SENTENCE.)
 *   • SPACE IS A THOUSANDS SEPARATOR TOO. "1 000 cm" is 1000 cm under SI and "1" followed by
 *     a stray "000" otherwise — the same two-reading ambiguity the comma already declined.
 *     (nl/numeric SPACE_GROUPED_NUMBER.)
 *   • AN ATTRIBUTIVE GIVEN MUST NOT YIELD TO A BARE COPULA. The tier-A lookahead rejected
 *     "a 6 cm radius IS DRAWN" and threw away the problem's only real given.
 *   • AN EXPLICIT RELATION OUTRANKS THE MATERIAL. Tape is linear and felt is areal, but that
 *     is a proxy; "go once ROUND the rim" and "cover the whole TOP" are facts about the
 *     problem, and the proxy must lose to them.
 *   • ARCMINUTES AND ARCSECONDS AT A DISTANCE FROM THE ANGLE NOUN. "an arc subtends 120' AT
 *     THE CENTRE" was read as 120 DEGREES — a 20× error — because the guard only looked
 *     directly adjacent to the unit.
 *   • A TERMINATING DECIMAL BELOW 1 IS STILL EXACT. toFixed(6) truncates significant digits
 *     by MAGNITUDE; toPrecision(15) measures them by SIGNIFICANCE.
 *   • MORE SHAPE / VESSEL / BAND / CIRCUIT VOCABULARY: n-gon and dodecagon inscriptions, a
 *     WELL's curved wall, a walk lying "just outside" a garden, wire "used to fence" a plot.
 */
describe("circle — ROUND-28 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  it("(A): a subregion phrased as the WHOLE circle's area is still a subregion", () => {
    // "the area OF THE CIRCLE that the sector takes up" names the circle but asks for a part
    // of it; each shipped the FULL disc. Both voices, active and passive.
    expect(
      parseCircle(
        "A circle of radius 6 cm has a sector of central angle 60 degrees. Find the area of the circle that the sector takes up."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circle of radius 10 m has a sector of central angle 72 degrees. Find the area of the circle spanned by the sector."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circle of radius 6 cm has a sector of central angle 60 degrees. Find the area of the circle contained in that sector."
      )
    ).toBeNull();
  });

  it("(B): a span on non-circular scenery can never size the circle", () => {
    // The card's width is not a candidate diameter — the circle's own radius is given.
    expect(ship("A circle with a 6 cm radius is drawn on a card 40 cm wide. Find its area.")).toBe(
      "36π cm² ≈ 113.0973 cm²"
    );
    expect(ship("A circle with a 10 cm diameter is drawn on a card 30 cm wide. Find its area.")).toBe(
      "25π cm² ≈ 78.5398 cm²"
    );
    // …and with NO given for the circle at all, the shelf's width must not stand in for one.
    expect(parseCircle("A circle is drawn on a shelf 60 cm wide. Find its area.")).toBeNull();
    // The subject the span IS stated of still resolves — the head is the noun, not a
    // participle picked up by truncating the phrase from the left.
    expect(ship("A shelf is 60 cm wide. A circular tin on it is 20 cm across. How much area does the tin cover?")).toBe(
      "100π cm² ≈ 314.1593 cm²"
    );
  });

  it("(C): an explicit relation outranks the material's linear/areal proxy", () => {
    expect(ship("How much tape is needed to cover the whole top of a circular lid of radius 10 cm?")).toBe(
      "100π cm² ≈ 314.1593 cm²"
    );
    expect(ship("How much felt is needed to go once round the rim of a circular drum of radius 15 cm?")).toBe(
      "30π cm ≈ 94.2478 cm"
    );
    expect(ship("How much netting is needed to go once round the rim of a circular pen of radius 5 m?")).toBe(
      "10π m ≈ 31.4159 m"
    );
    // The proxy still governs when no relation contradicts it.
    expect(ship("A circular lawn has a radius of 5 m. How much turf is needed to cover it right up to the edge?")).toBe(
      "25π m² ≈ 78.5398 m²"
    );
    expect(ship("A circular pen has a radius of 5 m. How much fencing is needed to cover the outside?")).toBe(
      "10π m ≈ 31.4159 m"
    );
  });

  it("(D): arcminutes and arcseconds are never degrees, however far from the angle noun", () => {
    expect(
      parseCircle("In a circle of radius 6 cm, an arc subtends 120' at the centre. Find the length of the arc.")
    ).toBeNull();
    expect(parseCircle("In a circle of radius 6 cm the angle at the centre is 120'. Find the arc length.")).toBeNull();
    expect(
      parseCircle("In a circle of radius 6 cm, an arc subtends 30 minutes at the centre. Find the length of the arc.")
    ).toBeNull();
    expect(
      parseCircle("In a circle of radius 9 cm, an arc subtends 45 seconds at the centre. Find the arc length.")
    ).toBeNull();
    // A DEGREE angle in the same frame is untouched.
    expect(ship("An arc of a circle of radius 6 cm subtends 60 degrees at the centre. Find the length of the arc.")).toBe(
      "2π cm ≈ 6.2832 cm"
    );
  });

  it("(E): a formula question is an instruction about the answer, not the ask", () => {
    expect(ship("Find the area of a circle with radius 10 cm. What is the formula for the circumference of a circle?")).toBe(
      "100π cm² ≈ 314.1593 cm²"
    );
    expect(ship("What is the circumference of a circle of radius 7 cm? State the area formula.")).toBe(
      "14π cm ≈ 43.9823 cm"
    );
  });

  it("(F): space-grouped digits are as ambiguous as comma-grouped ones", () => {
    expect(parseCircle("The radius of a circle is 1 000 cm. Find the area.")).toBeNull();
    // Ungrouped, the same magnitude is unambiguous.
    expect(ship("The radius of a circle is 1000 cm. Find the area.")).toBe("1000000π cm² ≈ 3141592.6536 cm²");
  });

  it("(G): more shape, vessel, band and circuit vocabulary", () => {
    // A dodecagon circumscribing the circle is not the circle.
    expect(
      parseCircle(
        "A circle of radius 7 cm is drawn inside a regular dodecagon so that it touches every side. Find the area of the dodecagon."
      )
    ).toBeNull();
    // A WELL's wall is a cylinder's curved surface, not a disc.
    expect(parseCircle("A circular well has a radius of 3 m and is 10 m deep. Find the area of its wall.")).toBeNull();
    // Half a disc cut by a diameter, and the band lying JUST OUTSIDE the garden.
    expect(
      parseCircle(
        "A circular field has a radius of 20 m. A fence runs along a diameter. Find the area of the ground on the east side."
      )
    ).toBeNull();
    expect(
      parseCircle(
        "A circular garden has a radius of 10 m. A gravel walk 2 m broad runs just outside it. Find the area of the gravel walk."
      )
    ).toBeNull();
    // Wire "USED TO FENCE" a plot is n circuits of it, not one.
    expect(
      parseCircle(
        "Three strands of wire are used to fence a circular plot of radius 10 m. Find the total length of wire needed."
      )
    ).toBeNull();
    // A path that merely RUNS PAST a circle is scenery, and must not decline it.
    expect(ship("A path 2 m wide runs past a circle of radius 14 cm. Find the circumference of the circle.")).toBe(
      "28π cm ≈ 87.9646 cm"
    );
  });

  it("(H): a terminating coefficient prints in full at any magnitude", () => {
    expect(ship("Find the area of a circle with radius 0.0323 cm")).toBe("0.00104329π cm² ≈ 0.0033 cm²");
    expect(ship("Find the area of a circle with radius 2.5 cm")).toBe("25/4 π cm² ≈ 19.635 cm²");
  });

  it("(I): a band that is PART of the figure does not resize it", () => {
    // The pizza's radius already includes its crust — asking for the PIZZA is unambiguous…
    expect(ship("A circular pizza has a radius of 15 cm. The crust is 2 cm wide. Find the area of the pizza.")).toBe(
      "225π cm² ≈ 706.8583 cm²"
    );
    // …and asking for the CRUST is the annulus this engine does not solve.
    expect(
      parseCircle("A circular pizza has a radius of 15 cm. The crust is 2 cm wide. Find the area of the crust.")
    ).toBeNull();
  });
});

/**
 * ROUND-29 adversarial gate (wf_83660856-3dc — 26/33 agents; 7 died on a session limit, so the
 * sweep is INCOMPLETE and cannot be a clean gate whatever it returned. 19 confirmed).
 * Six root causes, three in the shared nl/ layer:
 *
 *   • THE COUNTED NOUN IS THE PHRASE HEAD, not the word after "circular". "two circular FLOWER
 *     BEDS" and "two circular TABLE TOPS" both escaped the multiplicity guard because one
 *     modifier sat between "circular" and the plural — and the engine sized ONE bed and shipped
 *     it as the total. "each" and "total" also routinely sit in different SENTENCES.
 *   • AN INTERROGATIVE IS NOT THE ASK BY KIND — POSITION DECIDES. Sweeping for "?" before
 *     sweeping for cues inverted every lesson-style problem, because the teaching patter is a
 *     question and the real ask is an imperative: "Which is bigger, the area or the
 *     circumference? … Find the AREA." shipped a circumference. And patter that discusses the
 *     mathematics rather than posing it ("What does the word circumference mean?", "Can you see
 *     the diameter?") can never be the ask at all. (nl/ask RHETORICAL_SENTENCE.)
 *   • A REFERENCE LABEL IS NOT A GIVEN. "In EXAMPLE 5 diameter AB = 14 cm" bound the 5.
 *     (nl/numeric maskReferenceLabels — a label number is never an input, in any domain.)
 *   • OWNERSHIP IS A PROPERTY OF THE NOUN, NOT THE CLAUSE. "A circular BADGE is pinned to a
 *     BOARD whose diameter is 30 cm" states whose dimension it is, but the clause veto saw the
 *     ask object in the same clause and let the board's 30 cm size the badge. (nl/quantity
 *     dimensionOwner.) The same "of" ambiguity bites the ask-object reader: "of the circle"
 *     names an object, "of radius 7 cm" names a value.
 *   • A FUNCTION WORD ENDS A NOUN PHRASE. "a CIRCLE on a CARD 40 cm wide" made the CARD count as
 *     circular, because the premodifier gap admitted "on a".
 *   • THE VERTEX IS WHAT MAKES AN ANGLE CENTRAL. "at the circumference" is one phrasing of that
 *     fact; "where C lies on the circumference", "at a point R on the circumference" and the
 *     three-letter name "angle OAB" (vertex A, not the centre O) are others, and all three
 *     shipped an inscribed angle as a central one.
 *   • AN OUTWARD OFFSET NEEDS NO PARTICULAR VERB: "put up 3 m OUTSIDE IT", "hangs 20 cm OVER THE
 *     EDGE", "pegged 1 m OUTSIDE THE EDGE" all name a second, larger circle.
 */
describe("circle — ROUND-29 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  it("(A): a counted plural is a multi-figure total however many modifiers it carries", () => {
    expect(
      parseCircle("Two circular flower beds each of radius 3 m are to be edged. Find the total length of edging.")
    ).toBeNull();
    expect(
      parseCircle("Two circular table tops each of radius 4 m are to be polished. Find the total area to be polished.")
    ).toBeNull();
    expect(
      parseCircle("Five circular flower beds each of radius 1.5 m are to be edged. Find the total length of edging.")
    ).toBeNull();
    expect(
      parseCircle("Two circular garden beds each of diameter 10 m are to be fenced. Find the total length of fencing.")
    ).toBeNull();
    // ONE figure still ships.
    expect(ship("A circular flower bed of radius 3 m is to be edged. Find the length of edging.")).toBe(
      "6π m ≈ 18.8496 m"
    );
  });

  it("(B): the ask is the LAST sentence that poses work, question mark or not", () => {
    expect(
      ship("Which is bigger, the area or the circumference? A circle has a radius of 9 m. Find the area of the circle.")
    ).toBe("81π m² ≈ 254.469 m²");
    expect(
      ship(
        "What is the area of a circle? A circular hoop has a radius of 7 cm. Find the length of the wire that goes around the hoop."
      )
    ).toBe("14π cm ≈ 43.9823 cm");
    expect(
      ship("Look at the diagram. Can you see the diameter? Now calculate the area of the circle, which has a radius of 7 cm.")
    ).toBe("49π cm² ≈ 153.938 cm²");
    expect(
      ship("What does the word circumference mean? A circular tabletop has a diameter of 12 cm. Find the area of the tabletop.")
    ).toBe("36π cm² ≈ 113.0973 cm²");
    // …and the ROUND-22 case the "?"-first sweep was added for still resolves, because the
    // formula instruction is skipped outright rather than out-ranked.
    expect(ship("What is the circumference of a circle of radius 7 cm? State the area formula.")).toBe(
      "14π cm ≈ 43.9823 cm"
    );
    expect(ship("Find the area of a circle with radius 7 cm. Give your answer in terms of π.")).toBe(
      "49π cm² ≈ 153.938 cm²"
    );
  });

  it("(C): a reference-label number is not a given", () => {
    expect(ship("In Example 5 diameter AB = 14 cm. Find the area of the circle.")).toBe("49π cm² ≈ 153.938 cm²");
    expect(ship("In Fig. 3 the radius of a circle is 7 cm. Find the area.")).toBe("49π cm² ≈ 153.938 cm²");
    expect(ship("Question 12: the diameter of a circle is 20 cm. Find the area.")).toBe("100π cm² ≈ 314.1593 cm²");
  });

  it("(D): a dimension belongs to the noun the text says it belongs to", () => {
    expect(
      parseCircle("A circular badge is pinned to a board whose diameter is 30 cm. Find the area of the badge.")
    ).toBeNull();
    expect(
      parseCircle("A button sits on a circular plate with a diameter of 30 cm. Find the area of the button.")
    ).toBeNull();
    expect(parseCircle("A circle on a card 40 cm wide. Find its area.")).toBeNull();
    // A PART inherits its whole's radius — the owner veto must not touch it.
    expect(ship("A sector of a circle of radius 6 cm has a central angle of 60 degrees. Find the area of the sector.")).toBe(
      "6π cm² ≈ 18.8496 cm²"
    );
    // …and an ask object that is not a figure the text names ("how much area of TURF") vetoes
    // nothing: the lawn's own radius is still the given.
    expect(
      ship("A circular lawn of radius 7 m lies inside the boundary of the park. How much area of turf is needed?")
    ).toBe("49π m² ≈ 153.938 m²");
  });

  it("(E): an angle is central only when its vertex is the centre", () => {
    expect(
      parseCircle("A circle has radius 9 cm. Angle ACB is 40 degrees where C lies on the circumference. Find the length of arc AB.")
    ).toBeNull();
    expect(
      parseCircle(
        "An arc PQ of a circle of radius 18 cm subtends an angle of 30 degrees at a point R on the circumference. Find the area of the sector OPQ."
      )
    ).toBeNull();
    expect(
      parseCircle("OA and OB are radii of a circle of radius 10 cm and angle OAB is 50 degrees. Find the length of arc AB.")
    ).toBeNull();
    // A genuinely CENTRAL named angle still ships.
    expect(ship("In a circle of radius 6 cm, angle AOB is 60 degrees where O is the centre. Find the length of arc AB.")).toBe(
      "2π cm ≈ 6.2832 cm"
    );
  });

  it("(F): an outward offset names a second, larger circle whatever verb carries it", () => {
    expect(
      parseCircle("A circular flower bed of radius 7 m has a fence put up 3 m outside it. Find the area enclosed by the fence.")
    ).toBeNull();
    expect(
      parseCircle("A circular table of radius 70 cm is covered by a cloth that hangs 20 cm over the edge. Find the area of the cloth.")
    ).toBeNull();
    expect(
      parseCircle("A circular pond of radius 7 m is covered by a net that hangs 2 m past the edge. Find the circumference of the net.")
    ).toBeNull();
    expect(
      parseCircle("A circular pond of radius 6 m. A rope is pegged 1 m outside the edge all the way round. Find the length of the rope.")
    ).toBeNull();
    // A path that merely RUNS PAST the circle is not an offset.
    expect(ship("A path 2 m wide runs past a circle of radius 14 cm. Find the circumference of the circle.")).toBe(
      "28π cm ≈ 87.9646 cm"
    );
  });
});

/**
 * ROUND-30 gate regressions — the 19 violations a COMPLETE 28-agent adversarial sweep
 * confirmed against the ROUND-29 build. Nine root causes, six of them in the shared NL
 * layer rather than in this engine:
 *
 *   (A) A MEASURED number is never a reference LABEL. "table", "step", "part" and "page"
 *       are ordinary nouns as well as label words, so masking them deleted a real given
 *       ("a circular TABLE 40 CM across"). The unit is the discriminator — and the digits
 *       must be pinned WHOLE, or they backtrack until the unit guard is looking at a digit.
 *   (B) The same backtrack, older: "A circle 12.5 cm in diameter" strip-matched the label
 *       "circle 12" and left ".5".
 *   (C) A SWEPT angle IS the central angle. The distractor list is written in NOUNS, and a
 *       searchlight problem says "beam" in the sentence that states the sweep — so both
 *       angles were disqualified and the bare "angle of N" fallback shipped the TOWER's tilt.
 *   (D) DEEP is TALL. A main-clause depth beside a radius means a solid (2πrh), and both the
 *       adjective and the noun form were missing from the general height guard.
 *   (E) Every named ball is a ball: `\bball\b` does not match "football".
 *   (F) A terminating decimal must print in FULL — a 12-significant-digit cap turned the
 *       exact coefficient 3.99999960000001 into "4", a wrong exact value.
 *   (G) A quantity welded to a FOREIGN unit is a foreign quantity ("resistance R = 4 ohms").
 *   (H) Possession is stated by the VERB as often as by the preposition ("the box HAS a
 *       diameter of 40 cm"), and "from one rim to the opposite rim" is a diameter said long.
 *   (I) A guard must test the ASK, not the text. "The perimeter is fenced." — one bystander
 *       sentence — switched off the dangling-angle guard and shipped a whole circumference
 *       for an arc ask.
 */
describe("circle — ROUND-30 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  it("(A): a number carrying a UNIT is a dimension, not a reference label", () => {
    expect(ship("A circular table 40 cm across stands on a circular mat. The mat's radius is 50 cm. Find the area of the table.")).toBe(
      "400π cm² ≈ 1256.6371 cm²"
    );
    expect(ship("A circular table 40 cm across stands in a circular hall. The hall's radius is 9 m. Find the area of the table.")).toBe(
      "400π cm² ≈ 1256.6371 cm²"
    );
    expect(ship("A circular table 40 cm across stands on a circular mat. The mat's radius is 50 cm. Find the circumference of the table.")).toBe(
      "40π cm ≈ 125.6637 cm"
    );
    expect(ship("A circular step 30 cm across sits on a circular base. The base's radius is 50 cm. Find the area of the step.")).toBe(
      "225π cm² ≈ 706.8583 cm²"
    );
    // A genuine label — no unit — is still masked.
    expect(ship("In Example 5 diameter AB = 14 cm. Find the area of the circle.")).toBe("49π cm² ≈ 153.938 cm²");
    expect(ship("Question 12: the diameter of a circle is 20 cm. Find the area.")).toBe("100π cm² ≈ 314.1593 cm²");
  });

  it("(B): the label stripper reads the number whole, so a decimal given survives", () => {
    expect(ship("A circle 12.5 cm in diameter is drawn. Find its area.")).toBe("625/16 π cm² ≈ 122.7185 cm²");
    expect(ship("A circle 20.4 cm in diameter. Find its circumference.")).toBe("102/5 π cm ≈ 64.0885 cm");
    // …and a real ordinal label is still stripped.
    expect(ship("In Fig. 3 the radius of a circle is 7 cm. Find the area.")).toBe("49π cm² ≈ 153.938 cm²");
  });

  it("(C): a swept angle beats a mounting angle, whatever nouns surround it", () => {
    expect(ship("A searchlight has a beam that sweeps 150 degrees. Its beam has a radius of 30 m. The tower is inclined at an angle of 5 degrees. Find the area of the sector swept by the beam.")).toBe(
      "375π m² ≈ 1178.0972 m²"
    );
    expect(ship("A lighthouse light sweeps through 90 degrees. Its beam has a radius of 12 m. The lamp is mounted 40 degrees above the horizontal. Find the length of the arc swept by the tip of the beam.")).toBe(
      "6π m ≈ 18.8496 m"
    );
    expect(ship("A lighthouse light sweeps through 90 degrees. Its beam has a radius of 20 m. The lamp is mounted 30 degrees above the horizontal. Find the area of the sector swept.")).toBe(
      "100π m² ≈ 314.1593 m²"
    );
    // A mounting angle with no sweep to fall back on fails CLOSED.
    expect(
      parseCircle("A circular sign of radius 6 m is inclined at an angle of 30 degrees. Find the area of the sector.")
    ).toBeNull();
  });

  it("(D)+(E): a depth makes a solid; every named ball is a sphere", () => {
    expect(
      parseCircle("A circular swimming pool has a radius of 5 m and is 2 m deep. How much paint is needed to cover the wall around the inside of the pool?")
    ).toBeNull();
    expect(
      parseCircle("A circular jar of radius 3 cm and depth 10 cm. Find the area of paper needed to go round the jar.")
    ).toBeNull();
    expect(
      parseCircle("How much leather is needed to cover a circular football of radius 11 cm?")
    ).toBeNull();
  });

  it("(F): a terminating coefficient prints every digit it carries", () => {
    expect(ship("Find the area of a circle with radius 1.9999999 cm")).toBe(
      "3.99999960000001π cm² ≈ 12.5664 cm²"
    );
    // A repeating expansion still rounds.
    expect(ship("Find the sector area of a circle with radius 10 cm and central angle 120 degrees")).toBe(
      "100/3 π cm² ≈ 104.7198 cm²"
    );
  });

  it("(G): a value glued to a non-length unit is not a length", () => {
    expect(
      parseCircle("A circular loop of wire has resistance R = 4 ohms. Find the area of the loop.")
    ).toBeNull();
    // The symbol tier still reads a real radius.
    expect(ship("A circle has r = 4 cm. Find the area.")).toBe("16π cm² ≈ 50.2655 cm²");
  });

  it("(H): 'X has a diameter of V' names X as the owner; rim-to-rim is a diameter", () => {
    // The BOX's diameter must not become the TRAY's; the tray's own rim-to-rim span is read.
    expect(ship("A circular tray measures 30 cm from one rim to the opposite rim. The box holding it has a diameter of 40 cm. Find the area of the tray.")).toBe(
      "225π cm² ≈ 706.8583 cm²"
    );
  });

  it("(I): a bystander sentence cannot switch off the dangling-angle guard", () => {
    expect(
      parseCircle("A circular field with centre O has radius 30 m. The perimeter is fenced. A cow walks along the arc from A to B, where angle AOB is 120. What distance does the cow walk around the edge?")
    ).toBeNull();
    expect(
      parseCircle("The circumference of a circular pond with centre O is marked on the plan. Its radius is 8 m. A duck swims along the arc AB, where angle AOB is 45. How far does it swim around the edge?")
    ).toBeNull();
    // An ask that really does name the whole figure still ships.
    expect(ship("Find the circumference of a circle of radius 7 cm")).toBe("14π cm ≈ 43.9823 cm");
  });

  it("(J): a surface relation outranks the unit the material is sold in", () => {
    expect(ship("How many metres of carpet are needed to cover the whole floor of a circular room of radius 3 m?")).toBe(
      "9π m² ≈ 28.2743 m²"
    );
    // …and an encircling relation still wins for an area material.
    expect(ship("How much felt is needed to be sewn around the hem of a circular mat of radius 3 m?")).toBe(
      "6π m ≈ 18.8496 m"
    );
  });
});

/**
 * ROUND-31 gate regressions — the adversarial sweep after the ROUND-30 fixes. Root causes:
 *
 *   (A) A COVERAGE CLAUSE outranks the head noun it hangs on. "Find the area of the circle
 *       IT WETS" (sprinkler sweeping 60°) matched "area of the circle" and shipped the whole
 *       disc, 36π for a true 6π. The clause is restrictive: it names the ground the agent
 *       reaches, so the ask is a sub-region even though the noun says "circle".
 *   (B) A VULGAR or MIXED number is a given like any other — "a circle 3½ cm in radius",
 *       "3 1/2 cm across", "1/2 cm in radius". The reference-label mask ate the digits before
 *       any of them could be read (the label regex backtracked the number apart), so a
 *       perfectly ordinary problem parsed as having no radius at all.
 *   (C) COVERING a face is an AREA ask however the material is measured — "the AMOUNT OF TAPE
 *       needed to cover the whole top", "how much tape to cover the lid COMPLETELY", "how many
 *       METRES of carpet to cover a circular floor". A linear material name is not a linear ask.
 *   (D) A figure that is ROTATED is re-oriented, not swept. The ROUND-30 sweep tier read
 *       "the circle is then rotated through 120 degrees" as the central angle and beat the
 *       real 40° subtended arc. A sweep needs a swept SUBJECT, not merely a turning verb.
 *   (E) A NAMED FRACTION of a circle ("its north-eastern quarter", "one-quarter of the field
 *       is planted", "a sixteenth") is a sub-region, not the disc — decline rather than ship
 *       πr² for a quarter.
 *   (F) The DISPLAYED coefficient must be derived from the EXACT rational, never read off the
 *       double. 730303/720000000 π printed as "0.001014π" and 15999992000001/16000000000000 π
 *       collapsed to "1π" — both confident wrong exact values. A terminating coefficient has
 *       an exact finite decimal (compute it in BigInt); a repeating one has none, so the
 *       fraction — however ugly — is the only honest form.
 *   (G) A REACH stated inside the figure ("a sprinkler at the centre THROWS WATER 4 m" on a
 *       12 m lawn), a SECOND comparative figure ("drawn inside a LARGER circle"), a rope wound
 *       TWICE, and a COMPOUND mixed-unit given ("3 cm 5 mm") each mean the number in hand is
 *       not the radius of the figure asked about. Decline.
 */
describe("circle — ROUND-31 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  it("(A): a coverage clause narrows the referent — the head noun does not decide", () => {
    // Sub-region ask: the whole-disc 36π would be a confident wrong answer.
    expect(ship("A lawn sprinkler at the centre of a circle of radius 6 m sweeps an arc of 60 degrees. Find the area of the circle it wets.")).toBeNull();
    expect(ship("A sector of 60 degrees is marked on a circle of radius 12 cm. What area of the circle is taken by the sector?")).toBeNull();
    // …but the clause must sit ON the noun. A plain whole-circle ask still ships.
    expect(ship("Find the area of the circle of radius 7 cm")).toBe("49π cm² ≈ 153.938 cm²");
    expect(ship("A sprinkler waters a lawn. Find the area of the circle of radius 7 cm.")).toBe(
      "49π cm² ≈ 153.938 cm²"
    );
  });

  it("(B): vulgar and mixed numbers are givens, not labels", () => {
    expect(ship("Find the area of a circle 3½ cm in radius.")).toBe("49/4 π cm² ≈ 38.4845 cm²");
    expect(ship("A circle 3 1/2 cm across. Find its area.")).toBe("49/16 π cm² ≈ 9.6211 cm²");
    expect(ship("Find the arc length of a circle 2 1/2 cm in diameter with a central angle of 60 degrees.")).toBe(
      "5/12 π cm ≈ 1.309 cm"
    );
    expect(ship("Draw a circle 1/2 cm in radius. Find its area.")).toBe("1/4 π cm² ≈ 0.7854 cm²");
    expect(ship("A circle 10 1/2 cm in radius. Find the circumference.")).toBe("21π cm ≈ 65.9734 cm");
    // The mask still has to work: a real reference label is stripped, digits and all.
    expect(ship("In Example 5 diameter AB = 14 cm. Find the area of the circle.")).toBe(
      "49π cm² ≈ 153.938 cm²"
    );
  });

  it("(C): covering a face is an area ask whatever the material is measured in", () => {
    expect(ship("A circular lid has a radius of 5 cm. Find the amount of tape needed to cover the whole top of the lid.")).toBe(
      "25π cm² ≈ 78.5398 cm²"
    );
    expect(ship("A circular lid has a radius of 5 cm. How much tape is needed to cover the lid completely?")).toBe(
      "25π cm² ≈ 78.5398 cm²"
    );
    expect(ship("How many metres of carpet are needed to cover a circular floor of radius 5 m?")).toBe(
      "25π m² ≈ 78.5398 m²"
    );
    // The mirror still holds: material run ROUND a boundary stays a length ask.
    expect(ship("How much felt is needed to go once round the rim of a circular drum of radius 15 cm?")).toBe(
      "30π cm ≈ 94.2478 cm"
    );
  });

  it("(D): a rotated figure is re-oriented, not swept", () => {
    // Two candidate angles and no way to tell which governs → decline, never guess.
    expect(ship("An arc AB of a circle of radius 9 cm subtends an angle of 40 degrees at the centre O. The circle is then rotated through 120 degrees about O. Find the length of arc AB.")).toBeNull();
    expect(ship("A sector of a circle of radius 12 cm has an angle of 120 degrees at the centre. The disc is then turned through 40 degrees before the reading is taken. Find the area of the sector.")).toBeNull();
    // A genuinely SWEPT beam still reads as the central angle (ROUND-30 (E) must survive).
    expect(ship("A searchlight has a beam that sweeps 150 degrees. Its beam has a radius of 30 m. The tower is inclined at an angle of 5 degrees. Find the area of the sector swept by the beam.")).toBe(
      "375π m² ≈ 1178.0972 m²"
    );
  });

  it("(E): a named fraction of the circle is a sub-region", () => {
    expect(ship("A circular garden has a radius of 14 m. Find the area of its north-eastern quarter.")).toBeNull();
    expect(ship("A circular field has a radius of 12 m. One-quarter of the field is planted. Find the area planted.")).toBeNull();
    expect(ship("A circular pond has a diameter of 20 m. Find the area of its southern quarter.")).toBeNull();
    expect(ship("A circular field has a radius of 12 m. A sixteenth of the field is planted. Find the area planted.")).toBeNull();
    expect(ship("A circular garden has a radius of 14 m. Find the perimeter of its north-eastern quarter.")).toBeNull();
  });

  it("(F): the exact coefficient decides the display — never the double", () => {
    // Repeating expansion → the fraction is the only exact form (was "0.001014π" / "0.001π").
    expect(ship("Find the area of the sector of a circle with radius 0.0323 cm and central angle 350 degrees")).toBe(
      "730303/720000000 π cm² ≈ 0.0032 cm²"
    );
    expect(ship("Find the arc length of a circle with radius 0.6001 cm and central angle 0.3 degrees")).toBe(
      "6001/6000000 π cm ≈ 0.0031 cm"
    );
    // Terminating expansion → the exact decimal, all 16 digits of it (was a flat "1π").
    expect(ship("A circle has a diameter of 1.9999995 cm. Find its area.")).toBe(
      "0.9999995000000625π cm² ≈ 3.1416 cm²"
    );
    // …and the readable cases are unmoved: small denominators stay fractions.
    expect(ship("Find the area of a circle with radius 2.5 cm")).toBe("25/4 π cm² ≈ 19.635 cm²");
    expect(ship("Find the sector area of a circle with radius 10 cm and central angle 120 degrees")).toBe(
      "100/3 π cm² ≈ 104.7198 cm²"
    );
    expect(ship("Find the sector area of a circle with radius 0.87 cm and central angle 0.5 degrees")).toBe(
      "0.00105125π cm² ≈ 0.0033 cm²"
    );
    expect(ship("Find the area of a circle with radius 1.9999999 cm")).toBe(
      "3.99999960000001π cm² ≈ 12.5664 cm²"
    );
  });

  it("(G): a reach, a second figure, a double wrap, and a compound given are all declines", () => {
    expect(ship("A circular lawn has a radius of 12 m. A sprinkler at the centre throws water 4 m. Find the area the sprinkler waters.")).toBeNull();
    expect(ship("A circle of radius 4 cm is drawn inside a larger circle. Find the area of the larger circle.")).toBeNull();
    expect(ship("A circular mat has a radius of 4 m. A rope is wound around it twice. Find the total length of rope needed.")).toBeNull();
    expect(ship("A circle has a radius of 3 cm 5 mm. Find its area.")).toBeNull();
  });
});

/**
 * ROUND-32 GATE REGRESSIONS.
 *
 * The thirty-first adversarial sweep of the circle engine. Every case below shipped a
 * CONFIDENT WRONG value before the fix, and each names a place where a CLOSED VOCABULARY sat
 * in a position that decides correctness — the recurring shape of this whole audit:
 *
 *   • A LIST OF FIGURE NOUNS decided whether a rotation was a sweep, and did not know "dish".
 *   • A LIST OF THROWING VERBS decided whether a second radius had been stated, and did not
 *     know that a TETHER states one with a noun.
 *   • A LIST OF SPHERE NOUNS decided whether the ask was 3-D, and did not know "watermelon".
 *   • A LIST OF COVERING VERBS decided whether an ask was a surface, and did not know "for".
 *
 * Each fix replaces the list with the FACT it was approximating: a turn is a sweep only when a
 * SWEEPER turns; a skin/peel ask is a 3-D surface whatever the fruit; a three-letter angle name
 * states its own vertex; a dimension attributively welded to a bystander noun belongs to that
 * noun. Over-declining is honest; a confident wrong value is not.
 */
describe("circle — ROUND-32 gate regressions", () => {
  const ship = (t: string): string | null => {
    const spec = parseCircle(t);
    if (!spec) return null;
    return solveCircle(spec)?.answer.plain ?? null;
  };

  it("(A): a three-letter angle name states its own vertex", () => {
    // "Angle AOB" is central when O is the centre; "angle OAB" is a base angle. The degree MARK
    // sat on the DISTRACTOR, so the marked tier shipped the base angle as the central one.
    expect(ship("O is the centre of a circle of radius 12 cm. Angle AOB is 40. Angle OAB is 70 degrees. Find the length of arc AB.")).toBe(
      "8/3 π cm ≈ 8.3776 cm"
    );
    expect(ship("O is the centre of a circle of radius 10 cm. Angle AOB is 36. Angle OAB is 72 degrees. Find the area of the sector.")).toBe(
      "10π cm² ≈ 31.4159 cm²"
    );
    expect(ship("O is the centre of a circle of radius 9 cm. Angle AOB is 120. Angle OAB is 30 degrees. Find the area of the sector.")).toBe(
      "27π cm² ≈ 84.823 cm²"
    );
    // The single-name reading is unmoved.
    expect(ship("In a circle of radius 6 cm, angle AOB is 60 degrees where O is the centre. Find the length of arc AB.")).toBe(
      "2π cm ≈ 6.2832 cm"
    );
  });

  it("(B): a turn is a sweep only when a sweeper turns", () => {
    // The figure-noun list did not contain "dish", so a rigid re-orientation was read as the
    // central angle (28π cm for a true 7π). Two competing angles → decline.
    expect(ship("An arc of a circle of radius 21 cm subtends 60 degrees at the centre O. The dish is then turned through 240 degrees about O. Find the length of the arc.")).toBeNull();
    // A real sweeper still states the swept angle, whatever scenery surrounds it.
    expect(ship("A sprinkler rotates 120 degrees to water a sector of a circle of radius 9 m. The feed pipe is set at 40 degrees to the ground. Find the area of the sector watered.")).toBe(
      "27π m² ≈ 84.823 m²"
    );
    expect(ship("A lighthouse light sweeps through 90 degrees. Its beam has a radius of 12 m. The lamp is mounted 40 degrees above the horizontal. Find the length of the arc swept by the tip of the beam.")).toBe(
      "6π m ≈ 18.8496 m"
    );
  });

  it("(C): a count riding the number is a label, not the central angle", () => {
    // The phrase reader's gap stopped at the first digit, so the pie-chart tally ("for 8
    // PUPILS") was bound and the bare stated angle ("is 90") lost — 4/5 π for a true 9π.
    expect(ship("A sector of a circle of radius 6 cm: the angle at the centre of the sector for 8 pupils is 90. Find the area of the sector.")).toBe(
      "9π cm² ≈ 28.2743 cm²"
    );
    // The degree-marked forms this reader already handled are unmoved.
    expect(ship("An arc of a circle of radius 6 cm subtends 60 degrees at the centre. Find the length of the arc.")).toBe(
      "2π cm ≈ 6.2832 cm"
    );
  });

  it("(D): a skin, a peel and a part-of ask are not the disc", () => {
    // SPHERE_FIGURE is a noun list; "watermelon" and "orange" were not in it. Match the ASK —
    // a skin/peel wraps a SOLID, so its area is a 3-D surface whatever the figure is called.
    expect(ship("A circular watermelon has a radius of 12 cm. Find the area of its skin.")).toBeNull();
    expect(ship("A circular orange has a radius of 4 cm. Find the area of its peel.")).toBeNull();
    // "the area of THE PART OF the face that …" carves a sub-region out of the whole figure.
    expect(ship("A circular clock face has a radius of 10 cm. Find the area of the part of the face that the minute hand passes over in 15 minutes.")).toBeNull();
    // A LATERAL surface asked with a verb of enclosing is the same 2πrh decline.
    expect(ship("A circular tin of radius 5 cm is 12 cm thick. Find the area of the paper that wraps its side.")).toBeNull();
  });

  it("(E): a tether states a second radius, exactly as a throw does", () => {
    expect(ship("A circular field has a radius of 20 m. A goat is tethered at its centre with a 5 m rope. Find the area the goat can graze.")).toBeNull();
    // The throwing-verb form (ROUND-31 (G)) must survive.
    expect(ship("A circular lawn has a radius of 12 m. A sprinkler at the centre throws water 4 m. Find the area the sprinkler waters.")).toBeNull();
  });

  it("(F): a dimension welded to a bystander noun never sizes the asked figure", () => {
    // "A COIN 2 CM IN DIAMETER" and "A 2 CM DIAMETER COIN" both name their owner; neither frame
    // existed, so an ownerless 2 cm sized the TABLE and the PLATE.
    expect(ship("A coin 2 cm in diameter lies on a circular table of circumference 60 cm. Find the area of the table.")).toBeNull();
    expect(ship("A 2 cm diameter coin lies on a circular plate. Find the area of the plate.")).toBeNull();
    expect(ship("A tin lid 8 cm in diameter is placed on a circular table. Find the circumference of the table.")).toBeNull();
    // The asked figure's OWN dimension, stated the same way, still reads.
    expect(ship("A circular table 40 cm across stands on a circular mat. The mat's radius is 50 cm. Find the area of the table.")).toBe(
      "400π cm² ≈ 1256.6371 cm²"
    );
  });

  it("(G): a material supplied FOR a face is a surface relation", () => {
    // No covering verb at all — the stated unit ("metres") set a length target for a plainly
    // two-dimensional ask (6π m for a true 9π m²).
    expect(ship("How many metres of carpet are needed for the floor of a circular room of radius 3 m?")).toBe(
      "9π m² ≈ 28.2743 m²"
    );
    // …and a LINEAR material supplied for a boundary is untouched by the new arm.
    expect(ship("How many metres of mesh are needed to go right round a circular pen of radius 4 m?")).toBe(
      "8π m ≈ 25.1327 m"
    );
  });

  // (H) THE HEAD-DIFFERENTIAL findings. Every probe set only guards cases a previous round
  // already found, so broadening a reader can re-open a trap that used to fail CLOSED while
  // the whole suite stays green. Running the corpus against PRODUCTION as the baseline is what
  // surfaced these two: both were introduced by this round's own fixes.
  it("(H): a sweeper standing at the centre introduces no second figure", () => {
    // A subject-free "at the centre of a circular X" guard — meant for a figure INSIDE a figure
    // — declined every genuine sweep in the corpus (40 of them), including the canonical one.
    expect(
      ship("A sprinkler at the centre of a circular field sweeps through 120 degrees. The field has a radius of 9 m. Find the area of the sector swept.")
    ).toBe("27π m² ≈ 84.823 m²");
    expect(
      ship("A radar at the centre of a circular field rotates through 120 degrees. The field has a radius of 9 m. Find the area of the sector swept.")
    ).toBe("27π m² ≈ 84.823 m²");
    // …and the figure-inside-a-figure the guard was FOR still declines, on both locative nouns.
    expect(
      ship("A circular flowerbed of radius 3 m sits in the middle of a circular lawn that is 20 m across. Find the area of the grass.")
    ).toBeNull();
    expect(
      ship("A circular flowerbed of radius 3 m sits at the centre of a circular lawn whose edge is 7 m from that centre. Find the area of the grass.")
    ).toBeNull();
  });

  it("(H): a length unit and a length-only material outrank a surface relation", () => {
    // A SURFACE relation beats the material, and beats a stated length unit, because area
    // materials are sold by the metre. Both overrides at once is a contradiction — the ask
    // demands metres and the relation demands an area — so decline instead of picking a side.
    expect(ship("How many metres of fencing are needed to cover the floor of a circular room of radius 3 m?")).toBeNull();
    expect(ship("How many metres of ribbon are needed to cover the top of a circular room of radius 3 m?")).toBeNull();
    // Neither override alone is affected: no length unit → the relation still wins…
    expect(ship("How much tape is needed to cover the whole top of a circular lid of radius 10 cm?")).toBe(
      "100π cm² ≈ 314.1593 cm²"
    );
    // …and an AREA material with a length unit still reads as the face.
    expect(ship("How many metres of carpet are needed to cover the floor of a circular room of radius 3 m?")).toBe(
      "9π m² ≈ 28.2743 m²"
    );
  });
});
