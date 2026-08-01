import { describe, expect, it } from "vitest";

import { deriveTutorSketch } from "../src/proxy/tutorSketch";
import { verifyTutorFocus } from "../src/proxy/tutorFocus";

const at = (latex: string, kind: string) => deriveTutorSketch(latex, kind);

describe("deriveTutorSketch — fractions", () => {
  it("draws a fraction of whole numbers as parts of a bar", () => {
    expect(at("\\frac{3}{4}", "fraction")).toEqual({
      kind: "fraction",
      params: { numerator: 3, denominator: 4 },
    });
  });

  it("reads the display forms the same way", () => {
    expect(at("x = \\dfrac{2}{5}", "fraction")?.params).toEqual({
      numerator: 2,
      denominator: 5,
    });
  });

  it("declines what a bar cannot honestly show", () => {
    expect(at("\\frac{1}{1}", "fraction")).toBeNull(); // one whole cell
    expect(at("\\frac{5}{4}", "fraction")).toBeNull(); // more than the bar holds
    expect(at("\\frac{-1}{4}", "fraction")).toBeNull(); // no shading means -1
    expect(at("\\frac{3}{200}", "fraction")).toBeNull(); // a grey smear
    expect(at("\\frac{x}{4}", "fraction")).toBeNull(); // not a number yet
  });
});

describe("deriveTutorSketch — number line", () => {
  it("marks the value an equation gives", () => {
    expect(at("x = 4", "numberLine")?.params.value).toBe(4);
  });

  it("keeps zero in frame, so the value has something to be relative to", () => {
    const positive = at("x = 4", "numberLine")!.params;
    expect(positive.min).toBeLessThanOrEqual(0);
    expect(positive.max).toBeGreaterThan(4);

    const negative = at("x = -3", "numberLine")!.params;
    expect(negative.min).toBeLessThan(-3);
    expect(negative.max).toBeGreaterThanOrEqual(0);
  });

  it("reads an exact value exactly", () => {
    expect(at("x = \\frac{3}{2}", "numberLine")?.params.value).toBe(1.5);
  });

  it("declines when there is no single value to mark", () => {
    expect(at("x = 2y", "numberLine")).toBeNull();
    // The zero here is the right-hand side of an equation, not an answer:
    // marking it would point the student at the wrong number.
    expect(at("x^2 + 8x + 4 = 0", "numberLine")).toBeNull();
  });
});

describe("deriveTutorSketch — graphs", () => {
  it("recovers a line's slope and intercept", () => {
    expect(at("y = 2x + 3", "line")?.params).toMatchObject({
      slope: 2,
      intercept: 3,
    });
  });

  it("recovers a quadratic's coefficients from the equation as written", () => {
    expect(at("x^2 + 8x + 4 = 0", "parabola")?.params).toEqual({
      a: 1,
      b: 8,
      c: 4,
    });
  });

  it("frames the line so both the intercept and the root are visible", () => {
    const params = at("y = 2x + 3", "line")!.params;
    expect(params.xMin).toBeLessThan(-1.5); // the root
    expect(params.xMax).toBeGreaterThan(0); // the intercept
  });

  // The whole point of deriving rather than trusting: an expression that isn't
  // the shape the model claimed gets no drawing at all.
  it("refuses to draw a shape the maths is not", () => {
    expect(at("y = 2x + 3", "parabola")).toBeNull(); // no curvature
    expect(at("x^2 + 8x + 4 = 0", "line")).toBeNull(); // not straight
    expect(at("y = \\sin(x)", "parabola")).toBeNull(); // curved, but not a parabola
    expect(at("y = \\frac{1}{x}", "parabola")).toBeNull();
    expect(at("y = 2^x", "line")).toBeNull();
    expect(at("x + y + z = 1", "line")).toBeNull(); // more unknowns than a plot
  });
});

describe("deriveTutorSketch — area under a curve", () => {
  it("shades exactly the interval the integral names", () => {
    expect(at("\\int_{0}^{2} x^2 dx", "area")?.params).toMatchObject({
      a: 1,
      b: 0,
      c: 0,
      from: 0,
      to: 2,
    });
  });

  it("reads bounds without braces, and a spaced differential", () => {
    expect(at("\\int_1^3 2x \\, dx", "area")?.params).toMatchObject({
      b: 2,
      from: 1,
      to: 3,
    });
  });

  it("evaluates a symbolic bound rather than dropping it", () => {
    expect(at("\\int_{0}^{\\pi} x dx", "area")?.params.to).toBeCloseTo(Math.PI, 6);
  });

  // The client sweeps the shading from `from` to `to`; a window derived from
  // the bounds would rescale mid-animation.
  it("pins the window so the region fills a fixed frame", () => {
    const params = at("\\int_{0}^{2} x^2 dx", "area")!.params;
    expect(params.xMin).toBeLessThan(0);
    expect(params.xMax).toBeGreaterThan(2);
  });

  it("declines an integral it cannot draw", () => {
    expect(at("\\int_{3}^{1} x dx", "area")).toBeNull(); // backwards
    expect(at("\\int_{0}^{2} \\sin(x) dx", "area")).toBeNull(); // not polynomial
    expect(at("\\int x^2 dx", "area")).toBeNull(); // no bounds at all
  });
});

describe("deriveTutorSketch — the unit circle", () => {
  it("marks a degree angle", () => {
    expect(at("\\sin(30^\\circ)", "unitCircle")?.params.angleDegrees).toBe(30);
    expect(at("\\cos 45", "unitCircle")?.params.angleDegrees).toBe(45);
  });

  it("converts radians, which π is the only honest signal of", () => {
    expect(at("\\cos(\\frac{\\pi}{3})", "unitCircle")?.params.angleDegrees).toBe(60);
  });

  it("wraps into one turn, so the drawn arc is the angle shown", () => {
    expect(at("\\tan(400)", "unitCircle")?.params.angleDegrees).toBe(40);
    expect(at("\\sin(-90)", "unitCircle")?.params.angleDegrees).toBe(270);
  });

  it("is not fooled by an inverse function", () => {
    expect(at("\\arcsin(0.5)", "unitCircle")).toBeNull();
  });

  it("declines an angle it cannot pin down", () => {
    expect(at("\\sin(x)", "unitCircle")).toBeNull();
    expect(at("x + 1 = 2", "unitCircle")).toBeNull();
  });
});

describe("deriveTutorSketch — what the model may contribute", () => {
  it("takes the kind and nothing else", () => {
    // Numbers sent alongside the name are ignored: the drawing is derived.
    const sketch = deriveTutorSketch("\\frac{3}{4}", {
      kind: "fraction",
      params: { numerator: 99, denominator: 100 },
    });
    expect(sketch?.params).toEqual({ numerator: 3, denominator: 4 });
  });

  it("draws nothing for a kind it does not know", () => {
    expect(at("\\frac{3}{4}", "pieChart")).toBeNull();
    expect(at("\\frac{3}{4}", "")).toBeNull();
    expect(deriveTutorSketch("\\frac{3}{4}", null)).toBeNull();
    expect(deriveTutorSketch("\\frac{3}{4}", 7)).toBeNull();
  });

  it("draws nothing without maths to draw from", () => {
    expect(at("", "fraction")).toBeNull();
    expect(at("x".repeat(400), "line")).toBeNull();
  });
});

// The sketch rides on the focus, so it inherits the focus's gate: it is derived
// from the app's VERIFIED copy of the equation, never from what the model sent.
describe("the sketch inherits the focus firewall", () => {
  it("draws from the verified equation", () => {
    const { focus } = verifyTutorFocus(
      {
        latex: "x^2 + 8x + 4 = 0",
        caption: "the curve this equation draws",
        spans: [{ text: "x^2", role: "unknown" }],
        sketch: "parabola",
      },
      ["x^2 + 8x + 4 = 0"]
    );
    expect(focus?.sketch).toEqual({ kind: "parabola", params: { a: 1, b: 8, c: 4 } });
  });

  it("draws nothing when the equation itself was rejected", () => {
    const { focus } = verifyTutorFocus(
      {
        latex: "x^2 + 8x + 5 = 0",
        caption: "made up",
        spans: [{ text: "5", role: "known" }],
        sketch: "parabola",
      },
      ["x^2 + 8x + 4 = 0"]
    );
    expect(focus).toBeNull();
  });

  // A focus is still worth showing when only the picture fails.
  it("keeps the highlighted equation when the drawing does not fit", () => {
    const { focus } = verifyTutorFocus(
      {
        latex: "x^2 + 8x + 4 = 0",
        caption: "the coefficient",
        spans: [{ text: "8x", role: "operation" }],
        sketch: "fraction",
      },
      ["x^2 + 8x + 4 = 0"]
    );
    expect(focus?.latex).toBe("x^2 + 8x + 4 = 0");
    expect(focus?.sketch).toBeUndefined();
  });
});
