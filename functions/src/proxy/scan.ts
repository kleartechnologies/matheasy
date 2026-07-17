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
  /** Optional structured facts for a solvable single-unknown geometry problem. */
  geometry?: unknown;
}

/** A coerced, trusted recognition result (field types validated). */
export interface ScanResult {
  isMath: boolean;
  problem: string;
  topic: string;
  confidence: number;
  /**
   * The raw `geometry` object, passed through untouched — the CLIENT
   * (`GeometryPayloadMapper`) validates every field and computes the answer
   * itself, so nothing here is trusted. `null` when absent/not an object.
   */
  geometry: unknown | null;
}

/**
 * Coerce the model's raw JSON into a trusted [ScanResult]. `json_object` mode
 * guarantees syntactic JSON, not field types, so nothing here is trusted before
 * validation. Crucially it TRIMS but never truncates `problem` — the full
 * multi-line transcription (every line, sub-part and the question, with `\\` row
 * breaks) must survive intact to reach the solver.
 */
/**
 * Repair LaTeX backslashes the model under-escaped in its JSON. A macro must be
 * written `\\text` inside a JSON string; when the model writes `\text`, JSON.parse
 * consumes `\t` as a TAB and the macro arrives as TAB+"ext{…}" — which then reads
 * as prose/variables instead of a command. The same trap hits `\f`rac, `\b`egin.
 * Only TAB/FORM-FEED/BACKSPACE are repaired: they are never legitimate in math
 * LaTeX, whereas a real newline IS a legitimate line separator, so it is left be.
 */
function repairJsonEscapedMacros(s: string): string {
  return s
    .replace(/\t(?=[a-zA-Z])/g, "\\t") // \text, \times, \tan, \theta, \tfrac
    .replace(/\f(?=[a-zA-Z])/g, "\\f") // \frac
    .replace(/[\b](?=[a-zA-Z])/g, "\\b"); // \begin, \binom
}

export function coerceScanResult(raw: unknown): ScanResult {
  const r = (raw ?? {}) as Partial<ScanPayload>;
  return {
    isMath: r.isMath === true,
    problem:
      typeof r.problem === "string" ? repairJsonEscapedMacros(r.problem).trim() : "",
    topic: typeof r.topic === "string" ? r.topic : "other",
    confidence:
      typeof r.confidence === "number"
        ? Math.min(1, Math.max(0, r.confidence))
        : 0.9,
    // Pass the geometry object through only when it's a non-array object; the
    // client validates it. Anything else becomes null.
    geometry:
      typeof r.geometry === "object" &&
      r.geometry !== null &&
      !Array.isArray(r.geometry)
        ? r.geometry
        : null,
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
GEOMETRY (optional) — if, AND ONLY IF, the image is a solvable problem matching exactly ONE of the shapes below, ALSO include a top-level "geometry" object so the app can draw and animate it. Pick one "kind" and use ONLY its fields:
1. One missing ANGLE by an angle rule:
{"kind":"triangleAngles|isoscelesTriangle|quadrilateralAngles|polygonAngles|straightLineAngles|anglesAroundPoint|parallelLines|circleAngle", "unknown":"x", "knownAngles":[{"label":"A","value":60}], "polygonSides":5, "relation":"equal|supplementary|doubleOf|halfOf", "relationReference":"a", "ruleName":"Angles in a triangle sum to 180°"}
   (knownAngles values in degrees, numbers only; "polygonSides" only for polygonAngles; "relation"/"relationReference" only for parallelLines/circleAngle.)
2. Right triangle, TWO sides given, third side unknown (Pythagoras):
{"kind":"rightTrianglePythagoras", "unknown":"x", "sides":[{"label":"a","role":"leg","value":6},{"label":"c","role":"hypotenuse","value":10},{"label":"x","role":"leg"}]}
   (exactly 3 sides; OMIT "value" on the unknown; "role" is "leg" or "hypotenuse" — you MUST mark which side is the hypotenuse, opposite the right angle.)
3. Right triangle, ONE side + ONE acute angle given, another side unknown (trig ratio):
{"kind":"rightTriangleTrig", "unknown":"x", "knownAngle":{"label":"θ","value":35}, "sides":[{"label":"a","role":"adjacent","value":40},{"label":"x","role":"hypotenuse"}]}
   (EXACTLY 2 sides — the known one and the unknown one; OMIT "value" on the unknown. "role" is opposite|adjacent|hypotenuse RELATIVE TO the known angle: opposite = the side across from that angle, adjacent = the LEG touching it (never the hypotenuse), hypotenuse = the side across from the right angle.)
4. Any triangle, TWO sides + one NON-included angle given, a missing ANGLE asked (sine rule):
{"kind":"sineRuleAngle", "unknown":"y", "knownAngle":{"label":"C","value":34}, "sideOppositeKnown":{"label":"c","value":10}, "sideOppositeUnknown":{"label":"b","value":16}}
   ("sideOppositeKnown" = the side directly ACROSS FROM the known angle; "sideOppositeUnknown" = the side across from the asked angle. ADD "angleBranch":"acute" or "angleBranch":"obtuse" ONLY when the problem itself states it (e.g. "angle y is obtuse" → "angleBranch":"obtuse"); NEVER include the key otherwise — the example above omits it on purpose.)
5. Triangle AREA from two sides + the INCLUDED angle between them:
{"kind":"sasArea", "unknown":"Area", "sides":[{"label":"a","value":11},{"label":"b","value":13}], "includedAngle":{"label":"C","value":39}}
   (the angle must sit BETWEEN the two given sides, and "unknown" MUST be the literal string "Area" — if the problem asks for a SIDE of that triangle instead, that is the cosine rule: OMIT geometry.)
CRITICAL for geometry: every "value" is a plain NUMBER — angle values in degrees WITHOUT the ° symbol, lengths without units. Read the GIVEN numbers off the figure/text and name the single unknown — DO NOT compute or include the unknown's value; the app computes it deterministically and discards your geometry object if the numbers are inconsistent. OMIT "geometry" entirely for anything else (proofs, perimeter, a missing SIDE of a non-right triangle (cosine rule), other area shapes, coordinate geometry, or any problem you're unsure about) — a wrong geometry object is worse than none. "problem" must ALWAYS still contain the full transcription regardless (including the figure's given numbers when the text alone doesn't carry them).
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
    const { isMath, problem, topic, confidence, geometry } =
      coerceScanResult(result);

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
      // Untrusted structured facts for the diagram-first geometry player; the
      // client validates + computes. Present only for solvable angle/right-
      // triangle problems, else null.
      geometry,
      usage: quota,
    };
  }
);
