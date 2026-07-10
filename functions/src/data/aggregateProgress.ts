/**
 * `aggregateProgress` — the Firestore data-layer trigger.
 *
 * The app appends immutable events to `users/{uid}/progressEvents/{eventId}`
 * (e.g. { type: "solved", xp: 20 }). This trigger rolls each new event up into
 * the aggregate `stats` on the parent user doc, so the home/profile screens can
 * read one document instead of scanning the whole history.
 *
 * Expected event shape (adjust freely to match your data-layer stage):
 *   { type: "scan" | "practice" | "tutor" | "solved", xp?: number, createdAt }
 *
 * `stats` is server-managed (see firestore.rules) so the client can never
 * inflate its own XP.
 */
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

import { userRef } from "../lib/firestore";

interface ProgressEvent {
  type?: string;
  xp?: number;
}

export const aggregateProgress = onDocumentCreated(
  "users/{uid}/progressEvents/{eventId}",
  async (event) => {
    const uid = event.params.uid;
    const data = (event.data?.data() ?? {}) as ProgressEvent;

    const xp = typeof data.xp === "number" ? data.xp : 0;
    const solved = data.type === "solved" ? 1 : 0;

    await userRef(uid).set(
      {
        stats: {
          xp: FieldValue.increment(xp),
          problemsSolved: FieldValue.increment(solved),
          lastActivityAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );

    logger.info("Aggregated progress event", { uid, type: data.type, xp });
  }
);
