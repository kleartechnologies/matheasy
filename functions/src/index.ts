/**
 * Matheasy Cloud Functions — entry point.
 *
 * Every exported symbol here becomes a deployed function. Grouped by concern:
 *   • Secure AI proxy   — recognizeEquation, solveEquation, tutorReply,
 *                         tutorImage, generateVisualSolution,
 *                         generatePracticeQuestion
 *   • Billing           — revenuecatWebhook
 *   • Data layer        — aggregateProgress
 *
 * `./config` runs setGlobalOptions (region, maxInstances) on import.
 */
import "./config";

// --- Secure AI proxy (OpenAI, keys stay server-side) ------------------------
export { recognizeEquation } from "./proxy/scan";
export { solveEquation } from "./proxy/solve";
export { enrichTeaching } from "./proxy/teach";
export { tutorReply } from "./proxy/tutor";
export { tutorImage } from "./proxy/tutorImage";
export { generateVisualSolution } from "./proxy/visual";
export { generatePracticeQuestion } from "./proxy/practice";

// --- Identity + usage (server-authoritative free-tier enforcement) ----------
export { registerInstallation, linkIdentity, usageStatus } from "./proxy/usage";

// --- Billing (RevenueCat → Firestore entitlement sync) ----------------------
export { revenuecatWebhook } from "./billing/revenuecatWebhook";

// --- Firestore data layer ---------------------------------------------------
export { aggregateProgress } from "./data/aggregateProgress";

// --- Analytics (admin-only solve-failure dashboard) -------------------------
export { solveFailureReport } from "./analytics/solveFailureReport";
