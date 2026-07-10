/**
 * Matheasy Cloud Functions — entry point.
 *
 * Every exported symbol here becomes a deployed function. Grouped by concern:
 *   • Secure AI proxy   — recognizeEquation, solveEquation, tutorReply,
 *                         generateVisualSolution
 *   • Billing           — revenuecatWebhook
 *   • Data layer        — aggregateProgress
 *
 * `./config` runs setGlobalOptions (region, maxInstances) on import.
 */
import "./config";

// --- Secure AI proxy (Mathpix + OpenAI, keys stay server-side) --------------
export { recognizeEquation } from "./proxy/scan";
export { solveEquation } from "./proxy/solve";
export { tutorReply } from "./proxy/tutor";
export { generateVisualSolution } from "./proxy/visual";

// --- Billing (RevenueCat → Firestore entitlement sync) ----------------------
export { revenuecatWebhook } from "./billing/revenuecatWebhook";

// --- Firestore data layer ---------------------------------------------------
export { aggregateProgress } from "./data/aggregateProgress";
