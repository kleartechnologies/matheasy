// The RevenueCat REST fallback's pure core: is the `pro` entitlement active in a
// /subscribers payload? (Used by assertWithinQuota to heal a lagged/missed
// webhook without ever trusting a client claim.)
import { describe, expect, it } from "vitest";
import { proEntitlementActive } from "../src/lib/firestore";

const NOW = 1_700_000_000_000; // fixed "now" for deterministic expiry checks
const sub = (pro: { expires_date?: string | null } | undefined) => ({
  subscriber: { entitlements: pro ? { pro } : {} },
});

describe("proEntitlementActive", () => {
  it("active when expires_date is in the future", () => {
    expect(
      proEntitlementActive(sub({ expires_date: "2100-01-01T00:00:00Z" }), NOW)
    ).toBe(true);
  });

  it("active when expires_date is null (lifetime / non-expiring)", () => {
    expect(proEntitlementActive(sub({ expires_date: null }), NOW)).toBe(true);
    expect(proEntitlementActive(sub({}), NOW)).toBe(true);
  });

  it("inactive when expires_date is in the past (e.g. an expired sandbox sub)", () => {
    expect(
      proEntitlementActive(sub({ expires_date: "2000-01-01T00:00:00Z" }), NOW)
    ).toBe(false);
  });

  it("inactive when there is no pro entitlement", () => {
    expect(proEntitlementActive(sub(undefined), NOW)).toBe(false);
  });

  it("inactive (fails closed) on a malformed / empty payload", () => {
    expect(proEntitlementActive(null, NOW)).toBe(false);
    expect(proEntitlementActive({}, NOW)).toBe(false);
    expect(proEntitlementActive({ subscriber: {} }, NOW)).toBe(false);
    expect(
      proEntitlementActive(sub({ expires_date: "not-a-date" }), NOW)
    ).toBe(false);
  });
});
