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

const SYSTEM_PROMPT = `You are the math OCR engine inside the Matheasy app. You read a photo and return ONLY a JSON object (no prose, no markdown) with this exact shape:
{
  "isMath": boolean,      // true only if the image contains a real math problem or expression
  "problem": string,      // the single primary problem as clean LaTeX, e.g. "2x + 5 = 15" or "\\frac{3}{4} + \\frac{1}{2}"; "" when isMath is false
  "topic": string,        // one of: arithmetic, fraction, percentage, ratio, linear_equation, quadratic, simultaneous, trigonometry, geometry, calculus, statistics, other
  "confidence": number    // 0.0-1.0, how clearly the problem was read
}
Rules:
- Identify the main math problem in the photo. If several are present, choose the single clearest, most complete problem.
- Extract it as valid LaTeX with NO surrounding math delimiters (no $, no \\[ \\], no \\( \\)).
- Classify the topic using exactly one of the allowed values above.
- Set isMath=false (and problem="") for photos that contain no math.
- confidence must reflect legibility: high when the problem is crisp and centered, lower when blurry or partially cropped.`;

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
        "Read the math problem in this photo and return the JSON described above.",
        { temperature: 0.1, maxTokens: 700 }
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

    // Coerce the model's output — `json_object` guarantees syntactic JSON, not
    // field types, so never trust `result.problem` to be a string.
    const isMath = result.isMath === true;
    const problem =
      typeof result.problem === "string" ? result.problem.trim() : "";
    const topic = typeof result.topic === "string" ? result.topic : "other";
    const confidence =
      typeof result.confidence === "number"
        ? Math.min(1, Math.max(0, result.confidence))
        : 0.9;

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
