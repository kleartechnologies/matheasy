/**
 * The Firestore handle, and nothing else.
 *
 * Split out of `firestore.ts` so the identity and usage subsystems can reach
 * the database without importing the module that imports THEM. `firestore.ts`
 * re-exports both symbols, so every existing import keeps working and there is
 * still exactly one initialised Admin app.
 */
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

// Initialize the Admin SDK exactly once, even across warm invocations.
if (getApps().length === 0) {
  initializeApp();
}

export const db = getFirestore();

export function userRef(uid: string) {
  return db.collection("users").doc(uid);
}
