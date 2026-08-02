/**
 * The visual-teaching layer: anchors → actions → what Numi is allowed to point at.
 *
 * These tests all defend one property, from four angles: **the overlay may only
 * ever be drawn over places the APP located itself.** An outline painted at
 * model-invented coordinates would circle the wrong part of a student's own
 * homework with total confidence — the visual equivalent of a hallucinated
 * answer, and exactly what the golden rule exists to prevent. So every stage
 * here DROPS what it cannot justify rather than repairing it into something
 * plausible-looking.
 */
import { describe, expect, it } from "vitest";

import { coerceAnchors, coerceBox, type OcrAnchor } from "../src/proxy/ocr";
import {
  anchorContextBlock,
  coerceSemanticAnchors,
  deriveSemanticAnchors,
  nearestVertex,
  type SemanticAnchor,
} from "../src/proxy/anchors";
import { verifyTutorActions } from "../src/proxy/tutorActions";
import {
  normalizeVerificationState,
  verificationDirective,
  verificationState,
} from "../src/proxy/tutorVerification";

const BOX = { x: 0.1, y: 0.1, w: 0.1, h: 0.05 };

function ocrAnchor(over: Partial<OcrAnchor> = {}): OcrAnchor {
  return { text: "28", type: "number", box: BOX, confidence: 0.9, ...over };
}

function semantic(over: Partial<SemanticAnchor> = {}): SemanticAnchor {
  return {
    id: "angle_B",
    type: "angle",
    label: "28°",
    role: "known",
    box: BOX,
    confidence: 0.9,
    ...over,
  };
}

describe("coerceBox — a rectangle is only kept if it can be drawn honestly", () => {
  it("keeps a well-formed normalized box", () => {
    // `closeTo` throughout: the width is recomputed as `min(1, x + w) - x`, so
    // it comes back a float ULP away from what went in. That is fine for a
    // rectangle measured in fractions of a photo.
    expect(coerceBox({ x: 0.2, y: 0.3, w: 0.1, h: 0.08 })).toEqual({
      x: 0.2,
      y: 0.3,
      w: expect.closeTo(0.1, 10),
      h: expect.closeTo(0.08, 10),
    });
  });

  it("drops boxes given in PIXELS rather than fractions of the frame", () => {
    // The single most likely model mistake, and the most dangerous: 412 would
    // land the outline nowhere at all.
    expect(coerceBox({ x: 412, y: 233, w: 60, h: 24 })).toBeNull();
  });

  it("drops NaN, infinite and missing coordinates", () => {
    expect(coerceBox({ x: Number.NaN, y: 0.1, w: 0.1, h: 0.1 })).toBeNull();
    expect(coerceBox({ x: 0.1, y: 0.1, w: Number.POSITIVE_INFINITY, h: 0.1 })).toBeNull();
    expect(coerceBox({ x: 0.1, y: 0.1, w: 0.1 })).toBeNull();
    expect(coerceBox(null)).toBeNull();
    expect(coerceBox("0.1,0.1,0.2,0.2")).toBeNull();
  });

  it("drops boxes too small to see, and negative origins", () => {
    expect(coerceBox({ x: 0.5, y: 0.5, w: 0.001, h: 0.2 })).toBeNull();
    expect(coerceBox({ x: -0.05, y: 0.5, w: 0.2, h: 0.2 })).toBeNull();
  });

  it("trims a box that overhangs the edge instead of dropping a real mark", () => {
    // A cropped symbol at the margin is a genuine reading; a rounding error at
    // the frame edge should cost precision, never the anchor.
    expect(coerceBox({ x: 0.9, y: 0.9, w: 0.5, h: 0.5 })).toEqual({
      x: 0.9,
      y: 0.9,
      w: expect.closeTo(0.1, 10),
      h: expect.closeTo(0.1, 10),
    });
  });
});

describe("coerceAnchors", () => {
  it("keeps readable marks and normalizes their type and confidence", () => {
    const out = coerceAnchors([
      { text: " x ", type: "variable", box: BOX, confidence: 4 },
      { text: "5", type: "nonsense-type", box: BOX },
    ]);
    expect(out).toHaveLength(2);
    expect(out[0]).toMatchObject({ text: "x", type: "variable", confidence: 1 });
    // An unknown type degrades to "other" (which the semantic layer then drops)
    // rather than being taken at face value.
    expect(out[1]).toMatchObject({ text: "5", type: "other", confidence: 0.5 });
  });

  it("drops a mark with no text and a mark with no drawable box", () => {
    expect(
      coerceAnchors([
        { text: "  ", type: "number", box: BOX },
        { text: "7", type: "number", box: { x: 2, y: 2, w: 0.1, h: 0.1 } },
        "not an object",
      ])
    ).toEqual([]);
  });

  it("returns an empty list for a missing or non-array field", () => {
    expect(coerceAnchors(undefined)).toEqual([]);
    expect(coerceAnchors({ text: "x" })).toEqual([]);
  });
});

describe("deriveSemanticAnchors — marks become concepts, deterministically", () => {
  it("names the asked-for unknown from the geometry facts, above all else", () => {
    const out = deriveSemanticAnchors(
      [ocrAnchor({ text: "x", type: "variable" })],
      { kind: "triangleAngles", unknown: "x" }
    );
    expect(out).toHaveLength(1);
    // Not "variable_x": the target of the problem is the one relationship a
    // tutor must never lose.
    expect(out[0]).toMatchObject({ id: "unknown_x", type: "unknown", role: "unknown" });
  });

  it("attaches an angle to the vertex letter printed beside it", () => {
    const out = deriveSemanticAnchors(
      [
        ocrAnchor({ text: "28°", type: "angle", box: { x: 0.3, y: 0.3, w: 0.06, h: 0.04 } }),
        ocrAnchor({ text: "B", type: "vertex", box: { x: 0.34, y: 0.33, w: 0.03, h: 0.03 } }),
      ],
      { knownAngles: [{ value: 28 }] }
    );
    expect(out[0]).toMatchObject({ id: "angle_B", type: "angle", vertex: "B" });
    // The value was GIVEN, so it wears the "known" colour, not a concept colour.
    expect(out[0].role).toBe("known");
  });

  it("leaves an angle unnamed rather than attributing it to a distant vertex", () => {
    const out = deriveSemanticAnchors(
      [
        ocrAnchor({ text: "28°", type: "angle", box: { x: 0.05, y: 0.05, w: 0.06, h: 0.04 } }),
        ocrAnchor({ text: "B", type: "vertex", box: { x: 0.9, y: 0.9, w: 0.03, h: 0.03 } }),
      ],
      null
    );
    // "this angle" is honest; "the angle at B" pointing at the wrong corner is not.
    expect(out[0].vertex).toBeUndefined();
    expect(out[0].id).toBe("angle_28");
  });

  it("marks the hypotenuse as such when the geometry facts say so", () => {
    const out = deriveSemanticAnchors(
      [ocrAnchor({ text: "13", type: "length" })],
      { kind: "rightTriangleAngle", sides: [{ label: "c", value: 13, role: "hypotenuse" }] }
    );
    expect(out[0]).toMatchObject({ id: "hypotenuse_13", type: "hypotenuse", role: "known" });
  });

  it("drops bare operators — a tutor points at what they join", () => {
    expect(
      deriveSemanticAnchors(
        [ocrAnchor({ text: "+", type: "operator" }), ocrAnchor({ text: "~", type: "other" })],
        null
      )
    ).toEqual([]);
  });

  it("keeps ids unique when two marks read the same", () => {
    const out = deriveSemanticAnchors(
      [
        ocrAnchor({ text: "5", type: "number", box: { x: 0.1, y: 0.1, w: 0.05, h: 0.05 } }),
        ocrAnchor({ text: "5", type: "number", box: { x: 0.6, y: 0.6, w: 0.05, h: 0.05 } }),
      ],
      null
    );
    expect(out.map((a) => a.id)).toEqual(["known_5", "known_5_2"]);
  });

  it("returns nothing when the reader placed nothing", () => {
    expect(deriveSemanticAnchors([], { unknown: "x" })).toEqual([]);
    expect(deriveSemanticAnchors([ocrAnchor()], "not-an-object" as unknown)).toHaveLength(1);
  });
});

describe("nearestVertex", () => {
  it("picks the closest plausible vertex letter", () => {
    const angle = ocrAnchor({ type: "angle", box: { x: 0.5, y: 0.5, w: 0.04, h: 0.04 } });
    const near = ocrAnchor({ text: "C", type: "vertex", box: { x: 0.54, y: 0.52, w: 0.03, h: 0.03 } });
    const far = ocrAnchor({ text: "A", type: "vertex", box: { x: 0.62, y: 0.62, w: 0.03, h: 0.03 } });
    expect(nearestVertex(angle, [far, near])).toBe("C");
  });

  it("ignores things that are not vertex letters", () => {
    const angle = ocrAnchor({ type: "angle", box: { x: 0.5, y: 0.5, w: 0.04, h: 0.04 } });
    const label = ocrAnchor({ text: "cm", box: { x: 0.51, y: 0.51, w: 0.03, h: 0.03 } });
    expect(nearestVertex(angle, [label])).toBeNull();
  });
});

describe("coerceSemanticAnchors — the round trip back from a device", () => {
  it("keeps a well-formed anchor", () => {
    const out = coerceSemanticAnchors([semantic({ vertex: "B" })]);
    expect(out[0]).toMatchObject({ id: "angle_B", type: "angle", vertex: "B", role: "known" });
  });

  it("drops an anchor with no id or no drawable box", () => {
    expect(
      coerceSemanticAnchors([
        semantic({ id: "" }),
        { ...semantic(), box: { x: 5, y: 5, w: 1, h: 1 } },
      ])
    ).toEqual([]);
  });

  it("drops duplicate ids — a target must resolve to exactly one place", () => {
    const out = coerceSemanticAnchors([semantic(), semantic({ label: "31°" })]);
    expect(out).toHaveLength(1);
    expect(out[0].label).toBe("28°");
  });

  it("falls back to safe meaning rather than trusting an unknown type or role", () => {
    const out = coerceSemanticAnchors([
      { ...semantic(), type: "supernova", role: "rainbow" },
    ]);
    expect(out[0]).toMatchObject({ type: "label", role: "aside" });
  });
});

describe("anchorContextBlock", () => {
  it("is empty when there is nothing on the page to point at", () => {
    expect(anchorContextBlock([])).toBe("");
  });

  it("lists ids and instructs Numi to point rather than recite", () => {
    const block = anchorContextBlock([semantic({ vertex: "B" })]);
    expect(block).toContain("angle_B | angle at vertex B | \"28°\"");
    expect(block).toMatch(/rather than reading its value out loud/i);
  });
});

describe("verifyTutorActions — the gate on what may be drawn", () => {
  const anchors = [semantic(), semantic({ id: "unknown_x", type: "unknown", role: "unknown" })];

  it("keeps an action that points at a real anchor", () => {
    const verdict = verifyTutorActions([{ type: "circle", target: "angle_B" }], anchors);
    expect(verdict.actions).toEqual([{ type: "circle", target: "angle_B", role: "known" }]);
    expect(verdict.reason).toBeNull();
  });

  it("DROPS a target nobody located — the rejection this file exists for", () => {
    const verdict = verifyTutorActions(
      [{ type: "circle", target: "angle_Z" }, { type: "glow", target: "the top right" }],
      anchors
    );
    expect(verdict.actions).toEqual([]);
    expect(verdict.reason).toContain("unknown target");
  });

  it("drops an action type the renderer cannot draw", () => {
    const verdict = verifyTutorActions([{ type: "explode", target: "angle_B" }], anchors);
    expect(verdict.actions).toEqual([]);
    expect(verdict.reason).toContain("unknown type");
  });

  it("defaults the colour to the anchor's own role, and honours an explicit one", () => {
    const [a, b] = verifyTutorActions(
      [
        { type: "pulse", target: "unknown_x" },
        { type: "highlight", target: "angle_B", role: "hint" },
      ],
      anchors
    ).actions;
    expect(a.role).toBe("unknown");
    expect(b.role).toBe("hint");
  });

  it("ignores a bogus role rather than passing an unpaintable colour on", () => {
    const [action] = verifyTutorActions(
      [{ type: "flash", target: "angle_B", role: "chartreuse" }],
      anchors
    ).actions;
    expect(action.role).toBe("known");
  });

  it("dedupes and caps at three — an overlay lighting up six regions teaches nothing", () => {
    const verdict = verifyTutorActions(
      [
        { type: "circle", target: "angle_B" },
        { type: "circle", target: "angle_B" },
        { type: "glow", target: "angle_B" },
        { type: "pulse", target: "unknown_x" },
        { type: "flash", target: "angle_B" },
        { type: "zoom", target: "unknown_x" },
      ],
      anchors
    );
    expect(verdict.actions).toHaveLength(3);
    expect(verdict.actions.map((a) => `${a.type}:${a.target}`)).toEqual([
      "circle:angle_B",
      "glow:angle_B",
      "pulse:unknown_x",
    ]);
  });

  it("draws nothing at all when the page has no anchors", () => {
    const verdict = verifyTutorActions([{ type: "circle", target: "angle_B" }], []);
    expect(verdict.actions).toEqual([]);
    expect(verdict.reason).toContain("no anchors");
  });

  it("treats a missing actions field as simply nothing to point at", () => {
    expect(verifyTutorActions(undefined, anchors)).toEqual({ actions: [], reason: null });
    expect(verifyTutorActions(null, anchors).actions).toEqual([]);
    expect(verifyTutorActions("circle angle_B", anchors).reason).toContain("not a list");
  });
});

describe("verificationState — order is the design", () => {
  it("is PASS only for a verified answer read off a clean page", () => {
    expect(
      verificationState({ verified: true, hasAnswer: true, ocrConfidence: 0.95, uncertain: [] })
    ).toBe("PASS");
  });

  it("reports HIGH_CONFIDENCE when the read was good but not pristine", () => {
    expect(
      verificationState({ verified: true, hasAnswer: true, ocrConfidence: 0.8, uncertain: [] })
    ).toBe("HIGH_CONFIDENCE");
  });

  it("puts a failed verification above everything else", () => {
    // Perfect handwriting does not make an unverified answer safe to teach.
    expect(
      verificationState({ verified: false, hasAnswer: true, ocrConfidence: 1, uncertain: [] })
    ).toBe("VERIFIER_DISAGREEMENT");
    expect(verificationState({ verified: true, hasAnswer: false })).toBe(
      "VERIFIER_DISAGREEMENT"
    );
  });

  it("puts a doubtful READ above a clean solve", () => {
    // A perfect answer to the wrong question is the failure students actually
    // hit — and the only one they can fix themselves.
    expect(
      verificationState({ verified: true, hasAnswer: true, ocrConfidence: 0.5 })
    ).toBe("OCR_LOW_CONFIDENCE");
    expect(
      verificationState({
        verified: true,
        hasAnswer: true,
        ocrConfidence: 0.99,
        uncertain: ["the 3 in the denominator may be an 8"],
      })
    ).toBe("OCR_LOW_CONFIDENCE");
  });

  it("hedges a shaky solve that still read cleanly", () => {
    expect(
      verificationState({
        verified: true,
        hasAnswer: true,
        ocrConfidence: 0.95,
        scanConfidence: 0.4,
      })
    ).toBe("LOW_CONFIDENCE");
  });
});

describe("normalizeVerificationState", () => {
  it("accepts a known state in any casing", () => {
    expect(normalizeVerificationState("pass")).toBe("PASS");
    expect(normalizeVerificationState(" OCR_LOW_CONFIDENCE ")).toBe("OCR_LOW_CONFIDENCE");
  });

  it("rejects anything else, so the server recomputes instead", () => {
    expect(normalizeVerificationState("PROBABLY_FINE")).toBeNull();
    expect(normalizeVerificationState(7)).toBeNull();
    expect(normalizeVerificationState(undefined)).toBeNull();
  });
});

describe("verificationDirective — doubt is an instruction, not a mood", () => {
  it("tells Numi NOT to hedge when the app is certain", () => {
    const directive = verificationDirective("PASS");
    expect(directive).toMatch(/do not hedge/i);
  });

  it("names the specific mark to ask about when the read is doubtful", () => {
    const directive = verificationDirective("OCR_LOW_CONFIDENCE", [
      "the 3 in the denominator may be an 8",
    ]);
    expect(directive).toContain("the 3 in the denominator may be an 8");
    // Concrete question > generic hedging prose.
    expect(directive).toMatch(/is that a 3 or an 8/i);
  });

  it("forbids solving or guessing when verification failed", () => {
    const directive = verificationDirective("VERIFIER_DISAGREEMENT");
    expect(directive).toMatch(/found an inconsistency/i);
    expect(directive).toMatch(/must NOT solve it yourself/i);
    expect(directive).toMatch(/must NOT guess/i);
  });
});
