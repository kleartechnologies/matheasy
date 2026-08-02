/**
 * Image preprocessing — the first stage of the scan pipeline.
 *
 * A phone photo of a maths problem is rarely a clean scan: it is shot at an
 * angle under room light, so the page carries a brightness gradient, the pencil
 * is low-contrast grey on off-white, and JPEG artefacts blur the thin strokes
 * that carry the actual meaning — a minus sign, a prime on `f'(x)`, a subscript,
 * a decimal point. Those are exactly the marks whose misreading turns a solvable
 * problem into a wrong one.
 *
 * So before the model sees anything, the photo is rendered a SECOND time with
 * the page flattened and the strokes pushed apart from the paper. Both versions
 * are then sent: the enhanced render is easier to read, but enhancement can
 * destroy information too (a faint construction line normalised away, a shaded
 * region crushed to flat black), so the original stays in the request as the
 * ground truth the model can always fall back to.
 *
 * This runs SERVER-SIDE on purpose: the enhancement can be re-tuned and
 * redeployed without shipping a client release, and the phone still uploads only
 * one image.
 */
import { logger } from "firebase-functions/v2";
import sharp from "sharp";

import { VisionImage } from "./openai";

/**
 * The longest edge of the enhanced render, in pixels.
 *
 * Vision models tile an image and bill per tile, so bigger is not free — but
 * maths notation is detail-critical and the client already caps its upload at
 * ~1600px. Matching that keeps every stroke the client bothered to send.
 */
const MAX_EDGE = 1600;

/** JPEG quality for the enhanced render — high, because artefacts are the enemy. */
const JPEG_QUALITY = 92;

/** Enhancement is a best-effort optimisation; it must never delay a scan for long. */
const TIMEOUT_MS = 8_000;

export interface PreparedImage {
  /** The photo exactly as the client sent it, as a data URI. */
  original: string;
  /**
   * The contrast-enhanced render, as a data URI — or `null` when enhancement
   * was not possible. A null here is NOT an error: the pipeline simply proceeds
   * with the original alone, exactly as it did before this stage existed.
   */
  enhanced: string | null;
}

/** Split a `data:<mime>;base64,<payload>` URI. Returns null if it isn't one. */
export function parseDataUri(uri: string): { mime: string; buffer: Buffer } | null {
  const match = /^data:([^;,]+);base64,(.*)$/s.exec(uri);
  if (!match) return null;
  try {
    return { mime: match[1], buffer: Buffer.from(match[2], "base64") };
  } catch {
    return null;
  }
}

/** Reject a value that would make `sharp` do unbounded work or fail oddly. */
function isUsableImage(buffer: Buffer): boolean {
  // A few hundred bytes cannot be a photo of a page; anything smaller is a
  // corrupt upload and enhancing it just burns CPU to produce noise.
  return buffer.length > 512;
}

/**
 * Build the enhanced render of [buffer].
 *
 * The steps, and why each one is here:
 *
 *   • `rotate()` — apply the EXIF orientation. Phones store a sideways photo
 *     with an orientation flag rather than rotated pixels; strip the metadata
 *     without applying it and the model is handed a 90°-rotated page.
 *   • `grayscale()` — colour carries no information in pencil-on-paper maths,
 *     and dropping it stops a coloured page tint from skewing the normalisation.
 *   • `normalise()` — stretch the tonal range so the darkest ink goes to black
 *     and the paper goes to white. This is what rescues an under-exposed photo.
 *   • `linear()` — a mild extra contrast push around the midpoint, which is
 *     where faint pencil sits after normalisation.
 *   • `sharpen()` — recover the thin-stroke definition that resizing and JPEG
 *     compression soften. This is the step that matters most for primes,
 *     minus signs and decimal points.
 *
 * Deliberately NOT done: binarisation (a hard black/white threshold). It looks
 * dramatic and reads well on clean print, but on a shaded diagram or a
 * gradient-lit page it erases whole regions — and an erased construction line is
 * a silently wrong problem rather than an obviously unreadable one.
 */
async function enhance(buffer: Buffer): Promise<Buffer> {
  return sharp(buffer, { failOn: "none" })
    .rotate()
    .resize({
      width: MAX_EDGE,
      height: MAX_EDGE,
      fit: "inside",
      withoutEnlargement: true,
    })
    .grayscale()
    .normalise()
    .linear(1.15, -12)
    .sharpen({ sigma: 1.1 })
    // `grayscale()` alone makes the PIXELS grey but still writes three identical
    // channels; forcing the colourspace emits a genuine single-channel JPEG,
    // which is a third of the bytes for identical information — and the upload
    // to the vision model is billed by size.
    .toColourspace("b-w")
    .jpeg({ quality: JPEG_QUALITY })
    .toBuffer();
}

/** Run [work], resolving to null if it takes longer than [ms]. */
async function withTimeout<T>(work: Promise<T>, ms: number): Promise<T | null> {
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      work,
      new Promise<null>((resolve) => {
        timer = setTimeout(() => resolve(null), ms);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

/**
 * Preprocess a scanned photo into the pair of views the vision stage reads.
 *
 * FAILS SOFT by design. Enhancement is an accuracy optimisation layered on top
 * of a path that already worked; a `sharp` failure, an unsupported format, a
 * corrupt upload or a slow render must degrade to "original only" rather than
 * break the scan. Every such case is logged so a systematic failure is visible
 * instead of silently costing accuracy on every scan.
 */
export async function prepareScanImage(imageDataUri: string): Promise<PreparedImage> {
  const parsed = parseDataUri(imageDataUri);
  if (!parsed || !isUsableImage(parsed.buffer)) {
    logger.warn("imagePrep.skipped — not a usable data URI");
    return { original: imageDataUri, enhanced: null };
  }

  try {
    const rendered = await withTimeout(enhance(parsed.buffer), TIMEOUT_MS);
    if (!rendered) {
      logger.warn("imagePrep.timedOut — proceeding with the original only", {
        bytes: parsed.buffer.length,
      });
      return { original: imageDataUri, enhanced: null };
    }
    return {
      original: imageDataUri,
      enhanced: `data:image/jpeg;base64,${rendered.toString("base64")}`,
    };
  } catch (err) {
    logger.warn("imagePrep.failed — proceeding with the original only", {
      err: String(err),
    });
    return { original: imageDataUri, enhanced: null };
  }
}
/**
 * Build the labelled image list pass 2 reads.
 *
 * The labels are load-bearing. Two unlabelled images in one turn read as two
 * separate problems; labelled, they read as two views of one page, and the model
 * is told which is the untouched ground truth — so when enhancement has eaten a
 * faint construction line, it has somewhere to look.
 */
export function visionImages(
  original: string,
  enhanced: string | null
): VisionImage[] {
  if (!enhanced) return [{ dataUri: original }];
  return [
    {
      label:
        "IMAGE 1 — ORIGINAL PHOTO, exactly as taken. This is the ground truth: where the two images disagree, believe this one.",
      dataUri: original,
    },
    {
      label:
        "IMAGE 2 — the SAME page, contrast-enhanced and sharpened to make faint strokes legible. Use it to resolve marks that are unclear in image 1. Enhancement can erase very faint detail, so never conclude something is absent from this image alone.",
      dataUri: enhanced,
    },
  ];
}
