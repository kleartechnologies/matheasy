/**
 * `tutorImage` — reading a photo the student sent Numi in chat (spec Parts 2, 12).
 *
 * Two different things arrive through the same button: "here's a question I'm
 * stuck on" and "here's my working, where did I go wrong?". This function's only
 * job is to tell them apart and TRANSCRIBE — it classifies the photo and reads
 * the LaTeX out of it. It never solves, never critiques and never returns
 * tutoring text.
 *
 * That boundary is the golden rule at its source. Whatever comes back here is
 * handed to the app's own deterministic solver, and only then to Numi — so a
 * problem photographed in chat gets exactly the same verified treatment as one
 * scanned from the scanner tab, and a critique of handwriting is judged against
 * verified truth (see `tutorWork.ts`) rather than by the model's own arithmetic.
 *
 * "NEVER SILENTLY FAIL" (spec Part 2): an unreadable or non-math photo is a
 * normal, successful response with `kind: "unreadable" | "notMath"` and a
 * `note` the client turns into an honest, actionable message. Only a genuinely
 * broken request (missing/oversized image, blocked content, backend failure)
 * throws.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { OPENAI_API_KEY, REVENUECAT_SECRET_KEY, scanPipelineEnabled } from "../config";
import { requireUid } from "../lib/auth";
import {
  assertWithinQuota,
  ensureUserDoc,
  incrementUsage,
} from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import { languageDirective } from "../lib/language";
import { chatVisionJson, createOpenAI, moderateImage } from "../lib/openai";
import { prepareScanImage, visionImages } from "../lib/imagePrep";
import { repairJsonEscapedMacros } from "./scan";
import { MAX_WORK_LINES } from "./tutorWork";

interface TutorImageRequest {
  imageBase64?: string;
  mimeType?: string;
  /** What the student typed alongside the photo, if anything. */
  caption?: string;
  /** The learner's language code — `note` is the only prose field it affects. */
  language?: string;
}

/** Mirrors `MAX_IMAGE_BASE64_LEN` in `scan.ts` — ~5MB base64 ≈ 3.7MB decoded. */
const MAX_IMAGE_BASE64_LEN = 5_000_000;

/** What the photo turned out to be. */
export type TutorImageKind = "problem" | "work" | "notMath" | "unreadable";

const KINDS = new Set<string>(["problem", "work", "notMath", "unreadable"]);

/** The raw JSON contract the vision model must return. */
interface TutorImagePayload {
  kind?: unknown;
  problem?: unknown;
  work?: unknown;
  note?: unknown;
  confidence?: unknown;
}

/** A coerced, trusted read of the photo. */
export interface TutorImageRead {
  kind: TutorImageKind;
  /** The ORIGINAL question, transcribed as LaTeX. "" when there isn't one. */
  problem: string;
  /** The student's own working, one transcribed line per step. */
  work: string[];
  /** A short, plain-language note about what was (or wasn't) readable. */
  note: string;
  confidence: number;
}

const MAX_PROBLEM_LEN = 1200;
const MAX_WORK_LINE_LEN = 200;
const MAX_NOTE_LEN = 240;

/** Trim + repair one untrusted LaTeX string from the model. */
function latex(value: unknown, max: number): string {
  return typeof value === "string"
    ? repairJsonEscapedMacros(value).trim().slice(0, max)
    : "";
}

/**
 * Coerce the model's raw JSON into a trusted [TutorImageRead].
 *
 * `json_object` mode guarantees syntactic JSON, not field types or vocabulary,
 * so nothing is trusted before validation. An unrecognised `kind` degrades to
 * `unreadable` — the honest branch — rather than being guessed at.
 */
export function coerceTutorImageRead(raw: unknown): TutorImageRead {
  const r = (raw ?? {}) as TutorImagePayload;
  const problem = latex(r.problem, MAX_PROBLEM_LEN);
  const work: string[] = [];
  if (Array.isArray(r.work)) {
    for (const item of r.work) {
      const l = latex(item, MAX_WORK_LINE_LEN);
      if (l) work.push(l);
      if (work.length >= MAX_WORK_LINES) break;
    }
  }

  let kind: TutorImageKind =
    typeof r.kind === "string" && KINDS.has(r.kind)
      ? (r.kind as TutorImageKind)
      : "unreadable";

  // Reconcile the label with what actually came back. A "problem"/"work" read
  // with nothing transcribed is not a read at all — call it unreadable rather
  // than sending the client off to solve an empty string.
  if ((kind === "problem" || kind === "work") && !problem && work.length === 0) {
    kind = "unreadable";
  }
  // Working with no original question can still be critiqued for method, but
  // there is nothing to verify it against — the caller handles that honestly.
  if (kind === "work" && work.length === 0) kind = "problem";

  return {
    kind,
    problem,
    work,
    note:
      typeof r.note === "string"
        ? r.note.trim().slice(0, MAX_NOTE_LEN)
        : "",
    confidence:
      typeof r.confidence === "number"
        ? Math.min(1, Math.max(0, r.confidence))
        : 0.9,
  };
}

export const SYSTEM_PROMPT = `You are the math transcription engine inside the Matheasy app. A student has sent their tutor a photo. You READ the photo — you never solve it, never check it, and never comment on whether anything in it is correct. Another part of the app does the mathematics.

Return ONLY a JSON object (no prose, no markdown) with this exact shape:
{
  "kind": "problem" | "work" | "notMath" | "unreadable",
  "problem": string,      // the ORIGINAL question, transcribed as LaTeX; "" if there is none
  "work": string[],       // the student's OWN handwritten working, one entry per written line; [] if there is none
  "note": string,         // one short plain sentence about what you could and could not read
  "confidence": number    // 0.0-1.0, how clearly you could read it
}

CHOOSING "kind"
- "problem" — the photo shows a question only: a textbook line, a worksheet item, a screen, a typed exercise. No attempt at solving it is visible.
- "work" — the photo shows the student's OWN attempt: handwritten steps, crossed-out lines, an answer they wrote. Use this whenever there is working, even if the original question is also in the photo.
- "notMath" — the image is real and readable but contains no mathematics at all.
- "unreadable" — there may well be math, but you cannot read it: too blurry, too dark, cut off, at an extreme angle, or handwriting you genuinely cannot make out. Choose this rather than guessing at symbols.

TRANSCRIBING
- Write everything as delimiter-free LaTeX: \\frac{3}{4}, x^{2}, \\sqrt{5}, \\theta. No $ signs, no \\begin{...} environments, no \\[ \\].
- "problem" holds the question exactly as printed, including every given condition and sub-part. Wrap words in \\text{...}.
- "work" holds ONE ENTRY PER LINE the student wrote, in the order they wrote them, top to bottom. Transcribe each line as it stands — including a line you can see is wrong. Do NOT correct it, do NOT tidy it, do NOT skip it, and do NOT add a line they did not write. If they crossed a line out, leave it out.
- If the student wrote their working but the original question is not in the photo, still use "work" and leave "problem" as "".
- Never invent a value you cannot see. If one character is illegible inside an otherwise readable line, transcribe what you can and say which character was unclear in "note".

The "note" is shown to the STUDENT, so keep it short, plain and specific: "The last two lines are cut off at the bottom of the photo." It is the only prose you write — "problem" and "work" are always universal math notation. Return JSON.`;

export const tutorImage = onCall(
  // Preprocessing + a reasoning-model vision pass need more headroom than the
  // single gpt-4o call this was sized for.
  { secrets: [OPENAI_API_KEY, REVENUECAT_SECRET_KEY], memory: "1GiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const { imageBase64, mimeType = "image/jpeg", caption, language } =
      (request.data ?? {}) as TutorImageRequest;

    if (!imageBase64 || typeof imageBase64 !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "imageBase64 (a base64-encoded image) is required."
      );
    }
    if (imageBase64.length > MAX_IMAGE_BASE64_LEN) {
      throw new HttpsError(
        "invalid-argument",
        "That photo is too large. Please try a smaller or more zoomed-in one."
      );
    }

    const imageDataUri = imageBase64.startsWith("data:")
      ? imageBase64
      : `data:${mimeType};base64,${imageBase64}`;

    await ensureUserDoc(uid);
    // Same paid vision call as the scanner, so the same backstops apply: the
    // rate limit caps every user (free and Pro) before the paid call, and the
    // read is metered against `scans` because that is literally what it costs.
    await assertWithinRateLimit(uid, "recognize");
    await assertWithinQuota(uid, "scans");

    const client = createOpenAI(OPENAI_API_KEY.value());

    // COPPA moderation gate (minors, 8-18) — screen BEFORE the paid vision call.
    // Fails CLOSED on a flag; OPEN on a moderation-service error, where the
    // transcription-only output contract is the backstop.
    const verdict = await moderateImage(client, imageDataUri);
    if (verdict.flagged) {
      logger.warn("tutorImage blocked by moderation", {
        uid,
        categories: verdict.categories,
      });
      throw new HttpsError(
        "invalid-argument",
        "That photo can’t be used here. Send a photo of a math problem or your working."
      );
    }

    const hint =
      typeof caption === "string" && caption.trim()
        ? ` The student also wrote: "${caption.trim().slice(0, 200)}". Use it only to decide what the photo is; still transcribe only what you can see.`
        : "";

    // Handwritten pencil working is the hardest thing the app is asked to read —
    // fainter and less regular than print — so it gets the same enhanced second
    // view as a scan. Fails soft to the original alone.
    const prepared = scanPipelineEnabled()
      ? await prepareScanImage(imageDataUri)
      : { original: imageDataUri, enhanced: null };

    let payload: TutorImagePayload;
    try {
      payload = await chatVisionJson<TutorImagePayload>(
        client,
        "handwriting",
        // The directive reaches exactly one field — `note` — because everything
        // else this function returns is math notation, which it leaves alone. A
        // student reading Thai should not be told "the last line is cut off" in
        // English.
        SYSTEM_PROMPT + languageDirective(language),
        visionImages(prepared.original, prepared.enhanced),
        `Read this photo and return the JSON described above. Transcribe only — do not solve it and do not judge whether anything is correct.${hint}`,
        { temperature: 0.1, maxTokens: 1200 }
      );
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error("tutorImage failed", { uid, err: String(err) });
      throw new HttpsError(
        "internal",
        "I couldn’t open that photo. Please try sending it again."
      );
    }

    const read = coerceTutorImageRead(payload);

    // Meter the paid Vision call HERE, whatever the read said. The request was
    // billed the moment `chatVisionJson` returned; charging only on a useful
    // read would let a scripted client burn unlimited OpenAI cost on junk
    // images while the free `scans` quota stayed pinned at 0.
    const quota = await incrementUsage(uid, "scans");

    // Deliberately NOT an error, even for `unreadable`/`notMath` — the student
    // gets a real reply from Numi either way (spec Part 2: never silently fail).
    return {
      kind: read.kind,
      problem: read.problem,
      work: read.work,
      note: read.note,
      confidence: read.confidence,
      usage: quota,
    };
  }
);
