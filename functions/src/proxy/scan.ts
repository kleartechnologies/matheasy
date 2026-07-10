/**
 * `recognizeEquation` — the secure Mathpix OCR proxy.
 *
 * The app sends a base64 photo; this function calls Mathpix with the secret
 * credentials and returns clean LaTeX. Mirrors the Flutter `ScannerService`
 * contract (`recognize` → a detected equation), and meters against the free
 * `scans` quota.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { MATHPIX_APP_ID, MATHPIX_APP_KEY } from "../config";
import { requireUid } from "../lib/auth";
import {
  assertWithinQuota,
  ensureUserDoc,
  incrementUsage,
} from "../lib/firestore";
import { recognizeWithMathpix } from "../lib/mathpix";

interface ScanRequest {
  imageBase64?: string;
  mimeType?: string;
  source?: string;
}

export const recognizeEquation = onCall(
  { secrets: [MATHPIX_APP_ID, MATHPIX_APP_KEY], memory: "512MiB", timeoutSeconds: 60 },
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

    await ensureUserDoc(uid);
    await assertWithinQuota(uid, "scans");

    let result;
    try {
      result = await recognizeWithMathpix(
        imageBase64,
        mimeType,
        MATHPIX_APP_ID.value(),
        MATHPIX_APP_KEY.value()
      );
    } catch (err) {
      logger.error("recognizeEquation failed", { uid, err: String(err) });
      throw new HttpsError("internal", "Could not recognize the problem. Try a clearer photo.");
    }

    if (!result.latex) {
      throw new HttpsError(
        "not-found",
        "No math was detected in the image. Try again with the problem centered."
      );
    }

    const quota = await incrementUsage(uid, "scans");

    return {
      latex: result.latex,
      confidence: result.confidence,
      source,
      usage: quota,
    };
  }
);
