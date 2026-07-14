/**
 * `recognizeEquation` — the secure OpenAI Vision OCR proxy.
 *
 * The app sends a base64 photo; this function calls OpenAI Vision (gpt-4o) with
 * the secret API key and returns clean, delimiter-free LaTeX for the primary
 * problem in the image. Mirrors the Flutter `ScannerService` contract
 * (`recognize` → a detected equation), and meters against the free `scans`
 * quota.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { OPENAI_API_KEY, OPENAI_MODEL, REVENUECAT_SECRET_KEY } from "../config";
import { requireUid } from "../lib/auth";
import {
  assertWithinQuota,
  ensureUserDoc,
  incrementUsage,
} from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import { chatVisionJson, createOpenAI, moderateImage } from "../lib/openai";

interface ScanRequest {
  imageBase64?: string;
  mimeType?: string;
  source?: string;
}

/**
 * Upper bound on the base64 image payload (~5MB base64 ≈ 3.7MB decoded). The
 * client compresses to ≤1600px JPEG (well under this); the cap is a tighter,
 * clearer guard than the ~10MB Firebase callable limit and bounds OpenAI cost.
 */
const MAX_IMAGE_BASE64_LEN = 5_000_000;

/** The JSON contract the model must return for a scanned photo. */
interface ScanPayload {
  isMath: boolean;
  problem: string;
  topic: string;
  confidence: number;
}

/** A coerced, trusted recognition result (field types validated). */
export interface ScanResult {
  isMath: boolean;
  problem: string;
  topic: string;
  confidence: number;
}

/**
 * Coerce the model's raw JSON into a trusted [ScanResult]. `json_object` mode
 * guarantees syntactic JSON, not field types, so nothing here is trusted before
 * validation. Crucially it TRIMS but never truncates `problem` — the full
 * multi-line transcription (every line, sub-part and the question, with `\\` row
 * breaks) must survive intact to reach the solver.
 */
export function coerceScanResult(raw: unknown): ScanResult {
  const r = (raw ?? {}) as Partial<ScanPayload>;
  return {
    isMath: r.isMath === true,
    problem: typeof r.problem === "string" ? r.problem.trim() : "",
    topic: typeof r.topic === "string" ? r.topic : "other",
    confidence:
      typeof r.confidence === "number"
        ? Math.min(1, Math.max(0, r.confidence))
        : 0.9,
  };
}

export const SYSTEM_PROMPT = `You are the math OCR engine inside the Matheasy app. You read a photo of a math problem and return ONLY a JSON object (no prose, no markdown) with this exact shape:
{
  "isMath": boolean,      // true if the image contains any real math problem, expression, or question
  "problem": string,      // the COMPLETE problem transcribed as LaTeX (see rules below); "" when isMath is false
  "topic": string,        // one of: arithmetic, fraction, percentage, ratio, linear_equation, quadratic, simultaneous, trigonometry, geometry, calculus, statistics, other
  "confidence": number    // 0.0-1.0, how clearly the WHOLE problem was read
}
Transcription rules — capture the ENTIRE problem, never just one line:
- Transcribe EVERYTHING in the photo that is part of the problem: every line, all given conditions and definitions, EVERY sub-part, and the actual question(s) asked. NEVER drop a line, a "given", or the question — a problem can only be solved with its full context (e.g. a condition like "f'(2) = 10" or "tan θ = 2", and the "find …" question, are essential and MUST be included).
- Preserve the LINE STRUCTURE: put each printed line / statement on its own line, separated by a LaTeX row break " \\\\ ".
- Preserve PART NUMBERING exactly as printed — (i), (ii), (a), (b), 1., 2., etc. — each kept with its own text.
- Preserve every mathematical relationship exactly: equations, primes for derivatives (f'(x)), subscripts, powers, fractions, integrals, d/dx, Greek letters like θ, etc.
- Write words and instructions as \\text{...} and math as LaTeX; keep everything delimiter-free (no $, no \\[ \\], no \\( \\)).
- Do NOT solve, simplify, evaluate, or answer anything — transcribe ONLY what is written.
- Classify the topic using exactly one allowed value (use the topic of the main computation). Set isMath=false (and problem="") only when the image contains no math at all.
- confidence reflects how legibly the WHOLE problem was read.
Example of a well-formed multi-part transcription:
"\\text{It is given that } \\tan\\theta = 2. \\\\ \\text{(i) Find the exact value of } \\tan A \\text{, given that } \\tan(A+\\theta)=4. \\\\ \\text{(ii) Find the exact value of } \\tan B \\text{, given that } \\sin(B+\\theta)=3\\cos(B-\\theta)."`;

export const recognizeEquation = onCall(
  { secrets: [OPENAI_API_KEY, REVENUECAT_SECRET_KEY], memory: "512MiB", timeoutSeconds: 60 },
  async (request) => {
    const uid = requireUid(request);
    const { imageBase64, mimeType = "image/jpeg", source = "camera" } =
      (request.data ?? {}) as ScanRequest;

    if (!imageBase64 || typeof imageBase64 !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "imageBase64 (a base64-encoded image) is required."
      );
    }

    if (imageBase64.length > MAX_IMAGE_BASE64_LEN) {
      throw new HttpsError(
        "invalid-argument",
        "That image is too large. Please try a smaller or more zoomed-in photo."
      );
    }

    const imageDataUri = imageBase64.startsWith("data:")
      ? imageBase64
      : `data:${mimeType};base64,${imageBase64}`;

    await ensureUserDoc(uid);
    // Rate limit BEFORE the quota check and the paid call — the abuse backstop
    // that caps every user (free and Pro), spec §10.
    await assertWithinRateLimit(uid, "recognize");
    await assertWithinQuota(uid, "scans");

    const client = createOpenAI(OPENAI_API_KEY.value());

    // COPPA moderation gate (minors, 8–18): screen the image BEFORE the paid
    // vision call so inappropriate content is never processed. Fails CLOSED on a
    // flag (rejects), and OPEN on a moderation-service error — the isMath output
    // contract below is the backstop, so the model can still only ever return
    // math LaTeX, never arbitrary content.
    const verdict = await moderateImage(client, imageDataUri);
    if (verdict.flagged) {
      logger.warn("recognizeEquation blocked by moderation", {
        uid,
        categories: verdict.categories,
      });
      throw new HttpsError(
        "invalid-argument",
        "That image can’t be scanned. Point the camera at a math problem."
      );
    }

    let result: ScanPayload;
    try {
      result = await chatVisionJson<ScanPayload>(
        client,
        OPENAI_MODEL.value(),
        SYSTEM_PROMPT,
        imageDataUri,
        "Read the ENTIRE math problem in this photo — every line, all given conditions, every sub-part, and the question(s) — and return the JSON described above.",
        // Room for a full multi-part transcription (givens + (i)/(ii)/… + questions).
        { temperature: 0.1, maxTokens: 1200 }
      );
    } catch (err) {
      // A not-found (or any other HttpsError) must not be masked as internal.
      if (err instanceof HttpsError) {
        throw err;
      }
      logger.error("recognizeEquation failed", { uid, err: String(err) });
      throw new HttpsError(
        "internal",
        "Could not recognize the problem. Try a clearer photo."
      );
    }

    // Coerce the model's output (types are not guaranteed by json_object mode).
    // Preserves the full multi-line `problem` intact for the solver.
    const { isMath, problem, topic, confidence } = coerceScanResult(result);

    // Meter the paid Vision call HERE, before the not-found check: the request
    // was billed the moment `chatVisionJson` returned, whether or not math was
    // found. Charging only on a successful read would let a scripted client
    // send endless non-math images and burn unlimited OpenAI cost while the
    // free `scans` quota stays pinned at 0.
    const quota = await incrementUsage(uid, "scans");

    if (!isMath || !problem) {
      throw new HttpsError(
        "not-found",
        "No math was detected in the image. Try again with the problem centered."
      );
    }

    return {
      latex: problem,
      problem,
      topic,
      confidence,
      source,
      usage: quota,
    };
  }
);
