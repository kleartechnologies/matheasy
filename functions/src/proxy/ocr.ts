/**
 * The OCR stage — pass 1 of the two-pass scan pipeline.
 *
 * This pass does ONE job: transcribe what is physically on the page. It is told
 * not to interpret, not to classify, not to fix anything that looks wrong, and
 * above all not to compute. That narrowness is the point — a single pass that
 * simultaneously reads and interprets tends to "helpfully" correct what it reads
 * into whatever problem it expects to see, and a silently normalised `f'(x)` →
 * `f(x)` or `x_1` → `x` is a wrong problem solved perfectly.
 *
 * Pass 2 (`scan.ts`) then does the interpreting, with BOTH images plus this
 * reading in front of it, and is free to overrule any of it. Splitting the two
 * is what makes "OCR correction" a real step with something to correct rather
 * than a description of a single model's inner monologue.
 *
 * The whole stage FAILS SOFT: a null reading means pass 2 runs on the images
 * alone, exactly as the scanner did before this existed.
 */
import OpenAI from "openai";
import { logger } from "firebase-functions/v2";

import { chatVisionJson, VisionImage } from "../lib/openai";

/**
 * Where something sits on the page, in NORMALISED coordinates: `0..1` of the
 * image's width/height, origin top-left.
 *
 * Normalised rather than pixels because the client renders the photo at whatever
 * size the layout gives it, and because the two views handed to the model
 * (original + contrast-enhanced) may not share a pixel size. A fraction of the
 * frame survives both.
 */
export interface AnchorBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** What kind of mark an anchor is. Coarse on purpose — see `anchors.ts`. */
export const ANCHOR_TYPES = [
  "number",
  "variable",
  "operator",
  "angle",
  "length",
  "label",
  "vertex",
  "fraction",
  "root",
  "integral",
  "derivative",
  "matrix",
  "point",
  "axis",
  "equation",
  "figure",
  "other",
] as const;

export type AnchorType = (typeof ANCHOR_TYPES)[number];

/**
 * One readable mark on the page, with WHERE it is.
 *
 * This is what turns "the value 28" into "that angle, up there" — the whole
 * point of the visual-anchor layer. It is still transcription, not
 * interpretation: pass 1 says "the text `28°`, of type angle, in this box". What
 * that angle MEANS (which vertex, whether it is the unknown) is derived
 * deterministically afterwards in `anchors.ts`.
 */
export interface OcrAnchor {
  /** The mark as written, e.g. "28°", "x", "AB", "\\frac{3}{4}". */
  text: string;
  type: AnchorType;
  box: AnchorBox;
  /** 0-1, how sure the reader is of THIS mark (not the page). */
  confidence: number;
}

/** What pass 1 saw. Every field is advisory — pass 2 may overrule all of it. */
export interface OcrReading {
  /** Each printed/written line, transcribed as delimiter-free LaTeX, in order. */
  lines: string[];
  /** The whole problem as one LaTeX transcription, `\\`-separated by line. */
  latex: string;
  /** 0-1, how legible the page was overall. */
  confidence: number;
  /**
   * Marks the reader was genuinely unsure of, in its own words (e.g. "the
   * character after x could be a prime or a speck"). This is the most valuable
   * output of the pass: it tells pass 2 exactly where to look hardest.
   */
  uncertain: string[];
  /**
   * Every mark the reader could place on the page, with its box. Empty when the
   * model returned none — everything downstream degrades to text-only teaching.
   */
  anchors: OcrAnchor[];
}

const SYSTEM_PROMPT = `You are the OCR front-end of a math scanner. Your ONLY job is to TRANSCRIBE what is physically written in the image. Return ONLY a JSON object (no prose, no markdown) with this exact shape:
{
  "lines": string[],      // every line of the problem, in top-to-bottom order, each transcribed as delimiter-free LaTeX
  "latex": string,        // the same content as ONE string, lines joined by " \\\\ "
  "confidence": number,   // 0.0-1.0 — how legibly you could read the page as a whole
  "uncertain": string[],  // short notes naming any mark you were NOT sure about, e.g. "the mark after f could be a prime or a smudge"
  "anchors": [            // WHERE things are on the page — see the anchor rules below
    {"text":"28°","type":"angle","box":{"x":0.42,"y":0.31,"w":0.08,"h":0.05},"confidence":0.93}
  ]
}
ANCHOR RULES — this is how a tutor points at the page instead of reading numbers out loud, so be precise:
- "box" is the mark's bounding box in FRACTIONS of the image: x and y are the top-left corner (0 = left/top edge, 1 = right/bottom edge), w and h are the width and height. All four are between 0 and 1. Never pixels.
- Make the box tight around the mark itself, not the line or region containing it — but never zero-sized.
- "type" is one of: number, variable, operator, angle, length, label, vertex, fraction, root, integral, derivative, matrix, point, axis, equation, figure, other.
  • angle — an angle measure written on a figure ("28°", "x°"); vertex — a single letter naming a corner (A, B, C); length — a side/segment measurement written along a line; label — any other written label on a figure; point — a coordinate pair; axis — an x/y axis label; equation — a whole equation or expression standing on its own line; figure — the overall diagram region (include ONE of these when there is a diagram).
- "confidence" is for THAT mark alone: a smudged digit gets a low number even on an otherwise clean page.
- Anchor everything a teacher might point at: every number, variable, operator that carries meaning, angle, side length, vertex letter, axis, and each standalone equation. Aim for completeness over caution, but never invent a mark you cannot see.
- If the page is plain typed text with no figure, anchoring the standalone equations and their key symbols is enough.
- Return "anchors": [] if you genuinely cannot place anything. An empty list is honest; a made-up box is not.
Rules:
- Transcribe EXACTLY what is on the page. Do NOT solve, simplify, evaluate, correct, complete, or tidy anything.
- If something looks mathematically wrong, transcribe it wrong. You are a camera, not a tutor. Pass 2 decides what it means.
- Capture EVERY line: all givens and conditions, every sub-part label ((i), (ii), (a), (b), 1., 2.), and the actual question(s). Never drop a line.
- Be precise about the small marks that change meaning: primes (f'(x)), subscripts (x_1), minus vs en-dash vs fraction bar, decimal points vs commas, exponents, bars, hats, degree symbols.
- Write words as \\text{...} and math as LaTeX. No delimiters ($, \\[ \\], \\( \\)).
- If the image contains a FIGURE or DIAGRAM, transcribe every number, angle and label printed on it as its own line, prefixed \\text{[figure] }.
- If there is no math in the image at all, return empty "lines", empty "latex", confidence 0.
- "uncertain" is important: be honest. An empty array claims you were sure of every mark.`;

/**
 * Transcribe the page.
 *
 * Returns `null` on any failure — a bad reading must not be able to poison pass
 * 2, and pass 2 is designed to run without one.
 */
export async function readPage(
  client: OpenAI,
  images: VisionImage[]
): Promise<OcrReading | null> {
  try {
    const raw = await chatVisionJson<Partial<OcrReading>>(
      client,
      "ocr",
      SYSTEM_PROMPT,
      images,
      "Transcribe every line of this page exactly as written, place every mark a tutor might point at, and say which marks you were unsure of. Return the JSON described above.",
      // Generous: a dense multi-part page is a lot of LaTeX, the anchor list adds
      // a box per mark on top of it, and a transcription cut off halfway is worse
      // than no transcription at all.
      { maxTokens: 2600 }
    );
    return coerceOcrReading(raw);
  } catch (err) {
    // Logged, not thrown: pass 2 still has the images.
    logger.warn("ocr.readPage failed — pass 2 will run on the images alone", {
      err: String(err),
    });
    return null;
  }
}

/** A short list of strings from untrusted JSON, trimmed and bounded. */
function stringList(value: unknown, max: number): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((v): v is string => typeof v === "string")
    .map((v) => v.trim())
    .filter((v) => v.length > 0)
    .slice(0, max);
}

/**
 * Coerce pass 1's raw JSON into a trusted [OcrReading].
 *
 * `json_object` mode guarantees syntactic JSON, not field types or sane sizes,
 * and this text is about to be embedded in pass 2's prompt — so it is bounded
 * here rather than trusted. Returns null for a reading with no content, so an
 * empty result is indistinguishable from no result at the call site.
 */
export function coerceOcrReading(raw: unknown): OcrReading | null {
  const r = (raw ?? {}) as Partial<OcrReading>;
  const lines = stringList(r.lines, 60);
  const latex = typeof r.latex === "string" ? r.latex.trim() : "";
  if (lines.length === 0 && !latex) return null;

  return {
    lines,
    latex: latex || lines.join(" \\\\ "),
    confidence:
      typeof r.confidence === "number" && Number.isFinite(r.confidence)
        ? Math.min(1, Math.max(0, r.confidence))
        : 0.5,
    uncertain: stringList(r.uncertain, 12),
    anchors: coerceAnchors(r.anchors),
  };
}

/** How many marks to carry. A dense page has plenty; a tutor points at few. */
const MAX_ANCHORS = 48;

/** The smallest box worth drawing an outline around, as a fraction of the frame. */
const MIN_ANCHOR_SIZE = 0.004;

const ANCHOR_TYPE_SET = new Set<string>(ANCHOR_TYPES);

/**
 * Coerce the raw `anchors` array into boxes that are safe to DRAW.
 *
 * Everything here is defensive for one reason: these numbers become rectangles
 * painted over the student's own photo. A box outside the frame, inverted, or
 * NaN would either vanish or smear an outline across an unrelated part of the
 * page and point the student at the wrong thing — which is worse than not
 * pointing at all. So a box must be finite, inside `0..1`, and big enough to
 * see, or the anchor is dropped entirely rather than clamped into something
 * plausible-looking.
 */
export function coerceAnchors(value: unknown): OcrAnchor[] {
  if (!Array.isArray(value)) return [];
  const out: OcrAnchor[] = [];
  for (const item of value) {
    if (!item || typeof item !== "object") continue;
    const raw = item as Partial<OcrAnchor> & { box?: Partial<AnchorBox> };
    const text = typeof raw.text === "string" ? raw.text.trim().slice(0, 60) : "";
    if (!text) continue;
    const box = coerceBox(raw.box);
    if (!box) continue;
    out.push({
      text,
      type:
        typeof raw.type === "string" && ANCHOR_TYPE_SET.has(raw.type)
          ? (raw.type as AnchorType)
          : "other",
      box,
      confidence:
        typeof raw.confidence === "number" && Number.isFinite(raw.confidence)
          ? Math.min(1, Math.max(0, raw.confidence))
          : 0.5,
    });
    if (out.length >= MAX_ANCHORS) break;
  }
  return out;
}

/** A drawable box, or null. See [coerceAnchors] for why null beats clamping. */
export function coerceBox(value: unknown): AnchorBox | null {
  if (!value || typeof value !== "object") return null;
  const raw = value as Partial<AnchorBox>;
  const nums = [raw.x, raw.y, raw.w, raw.h];
  if (!nums.every((n) => typeof n === "number" && Number.isFinite(n))) return null;
  const x = raw.x as number;
  const y = raw.y as number;
  const w = raw.w as number;
  const h = raw.h as number;
  if (w < MIN_ANCHOR_SIZE || h < MIN_ANCHOR_SIZE) return null;
  if (x < 0 || y < 0 || x > 1 || y > 1) return null;
  // A box may legitimately run a little past the edge when a mark is cropped;
  // trim it to the frame rather than dropping a real mark for a rounding error.
  const right = Math.min(1, x + w);
  const bottom = Math.min(1, y + h);
  if (right - x < MIN_ANCHOR_SIZE || bottom - y < MIN_ANCHOR_SIZE) return null;
  return { x, y, w: right - x, h: bottom - y };
}

/**
 * Render a reading as the context block pass 2 receives.
 *
 * Framed explicitly as a draft to be checked rather than as fact. A model handed
 * a confident-sounding transcription tends to ratify it instead of looking at
 * the pixels again, which would defeat the entire point of the second pass — so
 * the wording pushes the other way, and low confidence or an explicit
 * uncertainty list pushes harder.
 */
export function ocrContextBlock(reading: OcrReading | null): string {
  if (!reading) return "";

  const parts = [
    "\n\n--- PASS 1: a DRAFT transcription from the OCR stage ---",
    "This is a first reading by a separate pass. It is NOT authoritative and it may contain misreadings. Check it against the images and CORRECT anything that is wrong — trust the pixels over this text.",
    `Draft LaTeX: ${reading.latex}`,
    `Draft lines:\n${reading.lines.map((l, i) => `  ${i + 1}. ${l}`).join("\n")}`,
    `Reader's own confidence: ${reading.confidence.toFixed(2)}`,
  ];

  if (reading.uncertain.length > 0) {
    parts.push(
      `The reader was UNSURE about the following — look at these especially carefully and decide for yourself:\n${reading.uncertain
        .map((u) => `  • ${u}`)
        .join("\n")}`
    );
  }

  if (reading.confidence < 0.6) {
    parts.push(
      "The reader's confidence is LOW. Treat the draft as a hint only and re-read the page from the images."
    );
  }

  parts.push("--- end of draft ---");
  return parts.join("\n");
}
