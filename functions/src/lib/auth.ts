/**
 * Shared auth guard for callable functions.
 */
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

/**
 * Require a signed-in caller and return their uid. Guest sessions in the app
 * are anonymous Firebase Auth users, so they still have a uid — only truly
 * unauthenticated calls are rejected.
 */
export function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in to use this feature."
    );
  }
  return uid;
}
