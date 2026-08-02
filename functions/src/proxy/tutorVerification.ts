/**
 * How sure the app is — and what Numi is required to say about it.
 *
 * The app already knows more about its own certainty than it has ever told the
 * student. It knows whether the answer survived substitution, how legible the
 * page was, and whether the reader flagged marks it couldn't resolve. Collapsing
 * all of that into a silent binary ("here's your answer") is how a tutor loses
 * trust the first time it is confidently wrong about a 5 it read as a 6.
 *
 * So the state is computed deterministically here, from facts the app owns, and
 * pushed into Numi's context as a BEHAVIOURAL contract rather than a hint. The
 * two doubtful states are not apologies — they are instructions to stop and
 * check the question with the student before teaching an answer to a problem
 * they may never have written.
 */

/** The five states, from most to least certain. */
export const VERIFICATION_STATES = [
  /** Substituted back into the original problem and it held. */
  "PASS",
  /** Verified, and the page was read cleanly. */
  "HIGH_CONFIDENCE",
  /** Verified, but something about the solve was shaky. */
  "LOW_CONFIDENCE",
  /** The maths checks out; the READ of the page does not. */
  "OCR_LOW_CONFIDENCE",
  /** The answer did not survive verification. */
  "VERIFIER_DISAGREEMENT",
] as const;

export type VerificationState = (typeof VERIFICATION_STATES)[number];

const STATE_SET = new Set<string>(VERIFICATION_STATES);

/** Below this, a transcription is not trustworthy enough to teach from silently. */
export const OCR_DOUBT_THRESHOLD = 0.7;

/** Below this, even a verified solve is worth hedging. */
const SOLVE_DOUBT_THRESHOLD = 0.6;

export interface VerificationInput {
  /** Did the answer survive substitution back into the problem? */
  verified?: boolean;
  /** Is there an answer at all? */
  hasAnswer?: boolean;
  /** The OCR pass's confidence in its own read, 0-1. */
  ocrConfidence?: number;
  /** Marks the reader flagged as doubtful. */
  uncertain?: string[];
  /** The scanner's confidence in the final transcription, 0-1. */
  scanConfidence?: number;
}

/**
 * Compute the state.
 *
 * ORDER IS THE DESIGN. A failed verification outranks everything: no amount of
 * legible handwriting makes an unverified answer safe. A doubtful READ outranks
 * a clean solve, because a perfect answer to the wrong question is the failure
 * mode students actually hit — and the only one they can fix themselves, by
 * looking at their own page.
 */
export function verificationState(input: VerificationInput): VerificationState {
  const { verified, hasAnswer, ocrConfidence, uncertain, scanConfidence } = input;

  if (verified === false || hasAnswer === false) return "VERIFIER_DISAGREEMENT";

  const ocrDoubt =
    (typeof ocrConfidence === "number" &&
      Number.isFinite(ocrConfidence) &&
      ocrConfidence < OCR_DOUBT_THRESHOLD) ||
    (Array.isArray(uncertain) && uncertain.length > 0);
  if (ocrDoubt) return "OCR_LOW_CONFIDENCE";

  if (
    typeof scanConfidence === "number" &&
    Number.isFinite(scanConfidence) &&
    scanConfidence < SOLVE_DOUBT_THRESHOLD
  ) {
    return "LOW_CONFIDENCE";
  }

  // A clean read AND a passed substitution is the only way to reach the top.
  const clean =
    typeof ocrConfidence !== "number" || ocrConfidence >= 0.9;
  return clean ? "PASS" : "HIGH_CONFIDENCE";
}

/** Accept a state the client computed, else null. */
export function normalizeVerificationState(value: unknown): VerificationState | null {
  if (typeof value !== "string") return null;
  const key = value.trim().toUpperCase();
  return STATE_SET.has(key) ? (key as VerificationState) : null;
}

/**
 * The directive for a state — what Numi must DO, not merely know.
 *
 * The doubtful states name the concrete question to ask, because "express
 * uncertainty" produces hedging prose ("I might be wrong, but…") that helps
 * nobody, whereas "ask them to check whether that mark is a 3 or an 8" produces
 * the one sentence that actually resolves it.
 */
export function verificationDirective(
  state: VerificationState,
  uncertain: string[] = []
): string {
  const marks =
    uncertain.length > 0
      ? ` The reader specifically flagged: ${uncertain.slice(0, 4).join("; ")}.`
      : "";

  switch (state) {
    case "PASS":
    case "HIGH_CONFIDENCE":
      return (
        "CERTAINTY: the answer was checked by substituting it back into the problem and it held, and the page was read cleanly. " +
        "Teach with confidence. Do not hedge, do not apologise, and do not invite doubt the app does not have."
      );
    case "LOW_CONFIDENCE":
      return (
        "CERTAINTY: the answer verified, but parts of this problem were awkward to read. " +
        "Teach normally, and if the student pushes back on a detail, take them seriously and re-check the question with them rather than restating the answer."
      );
    case "OCR_LOW_CONFIDENCE":
      return (
        "CERTAINTY: the MATHS is verified, but the READ of the page is doubtful — this problem may not be quite what the student wrote." +
        marks +
        " Before teaching the answer, name the specific mark you are unsure of and ask them to confirm it, e.g. \"I may have read this wrong — is that a 3 or an 8?\". " +
        "Point at the mark on their page if you can. Do not present the answer as settled until they confirm the question."
      );
    case "VERIFIER_DISAGREEMENT":
      return (
        "CERTAINTY: verification FAILED — the app could not confirm an answer for this problem, so there is no verified answer for you to teach. " +
        "Say so plainly and immediately: \"I found an inconsistency — let's look at the question before we go further.\" " +
        "Then help them check the problem itself (a misread character, a missing condition, a sub-part). " +
        "You must NOT solve it yourself, and you must NOT guess an answer to fill the gap — an honest 'let's check this together' is the correct answer here."
      );
  }
}
