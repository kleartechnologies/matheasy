/**
 * The two-pass scan pipeline: preprocess → OCR → vision.
 *
 * The behaviour worth pinning is the FAIL-SOFT contract. Every stage added here
 * is an accuracy optimisation layered over a path that already worked, so a
 * failure in any of them must degrade to the old single-image behaviour rather
 * than break a scan — that is what makes the rebuild safe to deploy.
 */
import { describe, expect, it } from "vitest";
import sharp from "sharp";

import { parseDataUri, prepareScanImage, visionImages } from "../src/lib/imagePrep";
import { coerceOcrReading, ocrContextBlock, OcrReading } from "../src/proxy/ocr";

/** A real JPEG, so `sharp` is genuinely exercised rather than mocked away. */
async function jpegDataUri(width = 400, height = 300): Promise<string> {
  const buf = await sharp({
    create: {
      width,
      height,
      channels: 3,
      background: { r: 200, g: 200, b: 190 },
    },
  })
    .jpeg()
    .toBuffer();
  return `data:image/jpeg;base64,${buf.toString("base64")}`;
}

describe("parseDataUri", () => {
  it("splits a well-formed data URI", async () => {
    const parsed = parseDataUri(await jpegDataUri());
    expect(parsed?.mime).toBe("image/jpeg");
    expect(parsed!.buffer.length).toBeGreaterThan(0);
  });

  it("returns null for anything that is not a base64 data URI", () => {
    expect(parseDataUri("https://example.com/a.jpg")).toBeNull();
    expect(parseDataUri("")).toBeNull();
    expect(parseDataUri("data:image/jpeg,notbase64")).toBeNull();
  });
});

describe("prepareScanImage", () => {
  it("returns the original untouched alongside the enhanced render", async () => {
    const original = await jpegDataUri();
    const prepared = await prepareScanImage(original);

    // The original must survive byte-for-byte — it is the ground truth the
    // vision stage falls back to when enhancement has eaten a faint stroke.
    expect(prepared.original).toBe(original);
    expect(prepared.enhanced).toMatch(/^data:image\/jpeg;base64,/);
  });

  it("produces a decodable image that is actually grayscale", async () => {
    const prepared = await prepareScanImage(await jpegDataUri());
    const parsed = parseDataUri(prepared.enhanced!)!;
    const meta = await sharp(parsed.buffer).metadata();

    expect(meta.format).toBe("jpeg");
    expect(meta.channels).toBe(1);
  });

  it("does not enlarge an image that is already small", async () => {
    const prepared = await prepareScanImage(await jpegDataUri(400, 300));
    const meta = await sharp(parseDataUri(prepared.enhanced!)!.buffer).metadata();

    expect(meta.width).toBe(400);
    expect(meta.height).toBe(300);
  });

  it("bounds a very large photo to the long-edge cap", async () => {
    const prepared = await prepareScanImage(await jpegDataUri(3000, 2000));
    const meta = await sharp(parseDataUri(prepared.enhanced!)!.buffer).metadata();

    expect(meta.width).toBe(1600);
  });

  it("fails soft to original-only on a non-image payload", async () => {
    const junk = `data:image/jpeg;base64,${Buffer.from("x".repeat(2000)).toString("base64")}`;
    const prepared = await prepareScanImage(junk);

    expect(prepared.original).toBe(junk);
    expect(prepared.enhanced).toBeNull();
  });

  it("fails soft to original-only when the input is not a data URI at all", async () => {
    const prepared = await prepareScanImage("not-an-image");

    expect(prepared.original).toBe("not-an-image");
    expect(prepared.enhanced).toBeNull();
  });
});

describe("visionImages", () => {
  it("sends a single unlabelled image when enhancement was unavailable", () => {
    const images = visionImages("data:image/jpeg;base64,AAA", null);

    expect(images).toHaveLength(1);
    expect(images[0].dataUri).toBe("data:image/jpeg;base64,AAA");
  });

  it("labels both views so they do not read as two separate problems", () => {
    const images = visionImages("data:a", "data:b");

    expect(images).toHaveLength(2);
    expect(images[0].label).toBeTruthy();
    expect(images[1].label).toBeTruthy();
    expect(images[0].dataUri).toBe("data:a");
    expect(images[1].dataUri).toBe("data:b");
  });

  it("names the original as the ground truth", () => {
    // If the model believes the enhanced render over the photo, enhancement
    // artefacts become transcription errors.
    expect(visionImages("data:a", "data:b")[0].label).toMatch(/ground truth/i);
  });
});

describe("coerceOcrReading", () => {
  it("accepts a well-formed reading", () => {
    const r = coerceOcrReading({
      lines: ["2x + 5 = 15", "\\text{Find } x"],
      latex: "2x + 5 = 15 \\\\ \\text{Find } x",
      confidence: 0.87,
      uncertain: ["the 5 could be a 6"],
    });

    expect(r?.lines).toHaveLength(2);
    expect(r?.confidence).toBeCloseTo(0.87);
    expect(r?.uncertain).toEqual(["the 5 could be a 6"]);
  });

  it("returns null for an empty reading, so 'no content' equals 'no result'", () => {
    expect(coerceOcrReading({ lines: [], latex: "", confidence: 0 })).toBeNull();
    expect(coerceOcrReading({})).toBeNull();
    expect(coerceOcrReading(null)).toBeNull();
  });

  it("rebuilds latex from the lines when the model omitted it", () => {
    const r = coerceOcrReading({ lines: ["a = 1", "b = 2"] });
    expect(r?.latex).toBe("a = 1 \\\\ b = 2");
  });

  it("clamps a confidence outside 0-1 and defaults a missing one", () => {
    expect(coerceOcrReading({ lines: ["x"], confidence: 5 })?.confidence).toBe(1);
    expect(coerceOcrReading({ lines: ["x"], confidence: -2 })?.confidence).toBe(0);
    expect(coerceOcrReading({ lines: ["x"] })?.confidence).toBe(0.5);
    expect(coerceOcrReading({ lines: ["x"], confidence: "high" })?.confidence).toBe(0.5);
  });

  it("drops non-string and empty entries rather than trusting the array", () => {
    const r = coerceOcrReading({ lines: ["ok", 42, null, "  ", "  also ok "] });
    expect(r?.lines).toEqual(["ok", "also ok"]);
  });

  it("bounds runaway output — this text goes straight into the next prompt", () => {
    const r = coerceOcrReading({
      lines: Array.from({ length: 500 }, (_, i) => `line ${i}`),
      uncertain: Array.from({ length: 500 }, (_, i) => `note ${i}`),
    });

    expect(r!.lines.length).toBeLessThanOrEqual(60);
    expect(r!.uncertain.length).toBeLessThanOrEqual(12);
  });
});

describe("ocrContextBlock", () => {
  const reading = (over: Partial<OcrReading> = {}): OcrReading => ({
    lines: ["2x + 5 = 15"],
    latex: "2x + 5 = 15",
    confidence: 0.9,
    uncertain: [],
    ...over,
  });

  it("is empty when there is no reading, leaving pass 2's prompt unchanged", () => {
    expect(ocrContextBlock(null)).toBe("");
  });

  it("frames the transcription as a draft to be checked, not as fact", () => {
    // The failure mode this prevents: pass 2 ratifying pass 1 instead of
    // re-reading the pixels, which would make the second pass worthless.
    const block = ocrContextBlock(reading());

    expect(block).toMatch(/draft/i);
    expect(block).toMatch(/not authoritative|may contain misreadings/i);
    expect(block).toMatch(/correct/i);
  });

  it("surfaces the marks pass 1 was unsure about", () => {
    const block = ocrContextBlock(reading({ uncertain: ["prime or smudge after f"] }));
    expect(block).toContain("prime or smudge after f");
  });

  it("pushes harder to re-read when pass 1's confidence was low", () => {
    expect(ocrContextBlock(reading({ confidence: 0.3 }))).toMatch(/LOW/);
    expect(ocrContextBlock(reading({ confidence: 0.95 }))).not.toMatch(/confidence is LOW/);
  });

  it("includes the draft LaTeX pass 2 has to check", () => {
    expect(ocrContextBlock(reading())).toContain("2x + 5 = 15");
  });
});
