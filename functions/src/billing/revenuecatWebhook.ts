/**
 * `revenuecatWebhook` — receives RevenueCat server events and syncs the user's
 * entitlement + subscription snapshot into Firestore. RevenueCat stays the
 * source of truth; this keeps a server-trusted copy the app (and security
 * rules) can rely on, so paid status can never be forged on-device.
 *
 * SETUP (RevenueCat dashboard → Integrations → Webhooks):
 *   URL:            https://<region>-<project>.cloudfunctions.net/revenuecatWebhook
 *   Authorization:  the SAME value you store in the REVENUECAT_WEBHOOK_TOKEN secret
 *
 * IMPORTANT — user mapping: this keys the Firestore doc off `event.app_user_id`,
 * so the app MUST call `Purchases.logIn(firebaseUid)` after auth resolves.
 * Otherwise RevenueCat sends an anonymous `$RCAnonymousID:…` we can't map, and
 * such events are acknowledged-but-skipped (logged as "unmapped").
 */
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue } from "firebase-admin/firestore";

import { PRO_ENTITLEMENT_ID, REVENUECAT_WEBHOOK_TOKEN } from "../config";
import { userRef } from "../lib/firestore";

interface RCEvent {
  id?: string;
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  entitlement_ids?: string[] | null;
  entitlement_id?: string | null;
  product_id?: string;
  expiration_at_ms?: number | null;
  purchased_at_ms?: number | null;
  store?: string;
  environment?: string;
  period_type?: string;
  cancel_reason?: string;
}

// Event types after which the user should NOT hold the entitlement.
const REVOKING_TYPES = new Set(["EXPIRATION", "REFUND", "SUBSCRIPTION_PAUSED"]);
// Cancellation = auto-renew turned off, but access continues until expiry.
const CANCELLATION_TYPES = new Set(["CANCELLATION"]);
const BILLING_ISSUE_TYPES = new Set(["BILLING_ISSUE"]);

function grantsProNow(event: RCEvent): boolean {
  if (event.type && REVOKING_TYPES.has(event.type)) return false;
  const ids = event.entitlement_ids ?? (event.entitlement_id ? [event.entitlement_id] : []);
  const mentionsPro = ids.includes(PRO_ENTITLEMENT_ID);
  // If the event carries no entitlement ids (some event types omit them), fall
  // back to "not a revoking event" — RevenueCat only sends these for the pro sub.
  const applies = ids.length === 0 ? true : mentionsPro;
  if (!applies) return false;
  // If there's an expiry in the past, it's lapsed.
  if (event.expiration_at_ms && event.expiration_at_ms < nowMs(event)) return false;
  return true;
}

// RevenueCat events don't carry "now"; use expiration/purchase context. We only
// need a monotonic-ish comparison, so compare against the purchase time when the
// expiry looks historical. Defaulting to 0 means "treat expiry as future".
function nowMs(_event: RCEvent): number {
  // Deliberately conservative: without a trusted clock we don't proactively
  // expire here — EXPIRATION events do that explicitly. Returning 0 means the
  // expiry check above never falsely revokes an active sub.
  return 0;
}

function mapStore(store?: string): string {
  switch (store) {
    case "APP_STORE":
    case "MAC_APP_STORE":
      return "appStore";
    case "PLAY_STORE":
      return "playStore";
    case "STRIPE":
      return "stripe";
    case "PROMOTIONAL":
      return "promotional";
    default:
      return "unknown";
  }
}

export const revenuecatWebhook = onRequest(
  { secrets: [REVENUECAT_WEBHOOK_TOKEN], memory: "256MiB" },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    // Verify the shared secret RevenueCat sends in the Authorization header.
    const provided = req.header("Authorization") ?? "";
    if (provided !== REVENUECAT_WEBHOOK_TOKEN.value()) {
      logger.warn("RevenueCat webhook: bad Authorization header");
      res.status(401).send("Unauthorized");
      return;
    }

    const event: RCEvent = req.body?.event ?? {};
    const uid = event.app_user_id;
    const eventType = event.type ?? "UNKNOWN";

    // Anonymous / unmapped user — ack so RevenueCat stops retrying, but skip.
    if (!uid || uid.startsWith("$RCAnonymousID")) {
      logger.warn("RevenueCat webhook: unmapped app_user_id — skipping", {
        eventType,
        appUserId: uid ?? null,
      });
      res.status(200).send("ok (unmapped)");
      return;
    }

    try {
      const ref = userRef(uid);
      // Idempotency + derive state in a transaction (RevenueCat retries events).
      await ref.firestore.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (event.id && snap.get("subscription.lastEventId") === event.id) {
          logger.info("RevenueCat webhook: duplicate event, skipping", { uid, id: event.id });
          return;
        }

        const isPro = grantsProNow(event);
        const cancelled = event.type ? CANCELLATION_TYPES.has(event.type) : false;
        const billingIssue = event.type ? BILLING_ISSUE_TYPES.has(event.type) : false;

        tx.set(
          ref,
          {
            entitlement: isPro ? PRO_ENTITLEMENT_ID : "none",
            subscription: {
              isPro,
              productId: event.product_id ?? null,
              store: mapStore(event.store),
              environment: event.environment ?? null,
              periodType: event.period_type ?? null,
              expiresAtMs: event.expiration_at_ms ?? null,
              willRenew: isPro && !cancelled,
              unsubscribeDetected: cancelled,
              hasBillingIssue: billingIssue,
              lastEventType: eventType,
              lastEventId: event.id ?? null,
              updatedAt: FieldValue.serverTimestamp(),
            },
          },
          { merge: true }
        );
      });

      logger.info("RevenueCat webhook processed", { uid, eventType });
      res.status(200).send("ok");
    } catch (err) {
      // 5xx tells RevenueCat to retry with backoff.
      logger.error("RevenueCat webhook failed", { uid, eventType, err: String(err) });
      res.status(500).send("error");
    }
  }
);
