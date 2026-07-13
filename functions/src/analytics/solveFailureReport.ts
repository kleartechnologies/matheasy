/**
 * `solveFailureReport` — the dashboard behind "prioritize real solver gaps
 * instead of guessing". Returns the most common UNSOLVED question types from
 * the single aggregate doc `analytics/solveFailures` (O(1) read; the raw
 * `solve_failures` collection holds the per-failure drill-down).
 *
 * Admin-only: the caller's uid must equal the ADMIN_UID param (unset → denied),
 * because the aggregate is an internal engineering tool.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";

import { ADMIN_UID } from "../config";
import { requireUid } from "../lib/auth";

/** `{ algebra: 12, calculus: 5 }` → `[{key:'algebra',count:12}, …]`, desc. */
export function sortedCounts(m: unknown): { key: string; count: number }[] {
  if (!m || typeof m !== "object") return [];
  return Object.entries(m as Record<string, unknown>)
    .map(([key, v]) => ({ key, count: Number(v) || 0 }))
    .filter((e) => e.count > 0)
    .sort((a, b) => b.count - a.count);
}

export const solveFailureReport = onCall(async (request) => {
  const uid = requireUid(request);
  const admin = ADMIN_UID.value();
  if (!admin || uid !== admin) {
    throw new HttpsError("permission-denied", "Admins only.");
  }

  const snap = await getFirestore().doc("analytics/solveFailures").get();
  const data = snap.data() ?? {};
  return {
    total: Number(data.total ?? 0),
    byTopic: sortedCounts(data.byTopic), // math domains, most-failing first
    byProblemType: sortedCounts(data.byProblemType), // classify's types
    byReason: sortedCounts(data.byReason), // no_verify_mode / llm_no_candidate / verify_gate_failed
    updatedAt: data.updatedAt ?? null,
  };
});
