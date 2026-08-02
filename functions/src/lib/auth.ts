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

/**
 * The identity signals every metered endpoint passes to the usage guard.
 *
 * `isAnonymous` is read from the VERIFIED ID token, not from the request body —
 * the client cannot claim to be signed in when it is not. `installationId` is
 * the one client-supplied value, and it is a lookup key rather than a claim:
 * a forged one fails to find the device's ledger and leaves the account's,
 * which the client cannot touch, doing the enforcing.
 */
export function callerIdentity(request: CallableRequest): {
  installationId: unknown;
  isAnonymous: boolean;
} {
  const token = request.auth?.token as
    | { firebase?: { sign_in_provider?: string } }
    | undefined;
  return {
    installationId: (request.data as { installationId?: unknown } | undefined)
      ?.installationId,
    isAnonymous: token?.firebase?.sign_in_provider === "anonymous",
  };
}
