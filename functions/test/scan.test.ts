import { describe, expect, it } from "vitest";

import { coerceScanResult, SYSTEM_PROMPT } from "../src/proxy/scan";

/**
 * Regression for the "OCR loses context on multi-line problems" bug: the vision
 * prompt used to extract "the single primary problem", so a multi-line question
 * (a given + sub-parts + the actual question) came back as ONE line and the rest
 * was silently dropped. The prompt must now transcribe the WHOLE problem, and
 * our coercion must pass that full transcription through untouched.
 */

// The transcription the (fixed) OCR is expected to return for the reported
// uploaded image — a differentiable-f(x) calculus problem across four lines.
const UPLOADED_IMAGE_TRANSCRIPTION =
  "\\text{f(x) is differentiable} \\\\ " +
  "x \\cdot f'(x) + f(x) = \\frac{d}{dx}(x^4 - x) \\\\ " +
  "f'(2) = 10 \\\\ " +
  "\\text{what is } f(-1)?";

// A multi-part trig question (the user's worked example) — given + (i) + (ii).
const TRIG_MULTIPART =
  "\\text{It is given that } \\tan\\theta = 2. \\\\ " +
  "\\text{(i) Find the exact value of } \\tan A \\text{, given that } \\tan(A+\\theta)=4. \\\\ " +
  "\\text{(ii) Find the exact value of } \\tan B \\text{, given that } \\sin(B+\\theta)=3\\cos(B-\\theta).";

describe("recognizeEquation SYSTEM_PROMPT — full multi-line capture", () => {
  it("no longer asks for a single problem, and requires the whole problem", () => {
    // The exact wording that caused the bug must be gone.
    expect(SYSTEM_PROMPT).not.toMatch(/single primary problem/i);
    expect(SYSTEM_PROMPT).not.toMatch(/choose the single clearest/i);
    // …and it must now demand a complete transcription.
    expect(SYSTEM_PROMPT).toMatch(/ENTIRE problem|COMPLETE problem/);
    expect(SYSTEM_PROMPT).toMatch(/every line/i);
    expect(SYSTEM_PROMPT).toMatch(/NEVER drop/i);
  });

  it("requires preserving line structure, numbering, and the question", () => {
    expect(SYSTEM_PROMPT).toMatch(/row break|line structure/i);
    expect(SYSTEM_PROMPT).toMatch(/\(i\), \(ii\)/); // part numbering
    expect(SYSTEM_PROMPT).toMatch(/question/i);
    expect(SYSTEM_PROMPT).toMatch(/sub-part/i);
    // It must NOT solve — only transcribe.
    expect(SYSTEM_PROMPT).toMatch(/do NOT solve/i);
    // json_object mode requires the literal word JSON in the prompt.
    expect(SYSTEM_PROMPT).toMatch(/JSON/);
  });
});

describe("coerceScanResult — preserves the full multi-line transcription", () => {
  it("passes the uploaded image's four-line problem through intact", () => {
    const out = coerceScanResult({
      isMath: true,
      problem: UPLOADED_IMAGE_TRANSCRIPTION,
      topic: "calculus",
      confidence: 0.9,
    });
    expect(out.isMath).toBe(true);
    // Every line survives — the given AND the question, not just the equation.
    expect(out.problem).toBe(UPLOADED_IMAGE_TRANSCRIPTION);
    expect(out.problem).toContain("f'(2) = 10"); // the given condition
    expect(out.problem).toContain("f(-1)"); // the actual question
    expect((out.problem.match(/\\\\/g) ?? []).length).toBe(3); // 4 lines → 3 breaks
  });

  it("preserves a multi-part trig question's (i)/(ii) numbering", () => {
    const out = coerceScanResult({
      isMath: true,
      problem: TRIG_MULTIPART,
      topic: "trigonometry",
      confidence: 0.85,
    });
    expect(out.problem).toBe(TRIG_MULTIPART);
    expect(out.problem).toContain("(i) Find");
    expect(out.problem).toContain("(ii) Find");
    expect(out.problem).toContain("\\tan\\theta = 2"); // the shared given
  });

  it("trims surrounding whitespace but keeps interior line breaks", () => {
    const out = coerceScanResult({
      isMath: true,
      problem: `  ${UPLOADED_IMAGE_TRANSCRIPTION}  `,
      topic: "calculus",
      confidence: 0.9,
    });
    expect(out.problem).toBe(UPLOADED_IMAGE_TRANSCRIPTION);
  });

  it("coerces bad field types safely (json_object guarantees syntax, not types)", () => {
    expect(coerceScanResult({}).problem).toBe("");
    expect(coerceScanResult({ isMath: true, problem: 42 }).problem).toBe("");
    expect(coerceScanResult({ confidence: 5 }).confidence).toBe(1); // clamped
    expect(coerceScanResult({ topic: null }).topic).toBe("other");
    expect(coerceScanResult(null).isMath).toBe(false);
  });
});
