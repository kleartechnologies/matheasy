// The server-side anti-abuse system: free usage that survives signing out,
// switching Google accounts, reinstalling the app, and every combination of
// those. Everything exercised here is a pure function by design — the decision
// logic was deliberately kept out of the Firestore shells so that the code
// deciding whether a student may scan their homework can be run a thousand
// times in a unit test rather than observed through an emulator.
import { describe, expect, it } from "vitest";

import {
  DEFAULT_FREE_DAILY_LIMITS,
  DEFAULT_FREE_LIMITS,
  DEFAULT_PRO_DAILY_LIMITS,
  METERED_FEATURES,
  UNLIMITED,
  emptyLedger,
  isMeteredFeature,
  toLedger,
} from "../src/usage/features";
import {
  UsageLimits,
  chargeDaily,
  dailyUsed,
  dayEpoch,
  decideUsage,
  effectiveLedger,
  effectiveUsage,
  mergeLedgers,
  secondsUntilNextDay,
  toDailyWindow,
} from "../src/usage/ledger";
import {
  DEFAULT_FLAGS,
  DEFAULT_LIMITS,
  FLAG_PARAM,
  defaultConfigMap,
  paramName,
  parseFlags,
  parseLimits,
  readFlag,
  readLimit,
} from "../src/usage/limits";
import { assessRisk } from "../src/identity/risk";
import {
  MAX_TRACKED_UIDS,
  applyIdentityEvent,
  emptyInstallation,
  installationDocId,
  normaliseInstallationId,
  riskSignalsFor,
  toInstallationState,
  toDocument,
} from "../src/identity/installations";
import { planMerge } from "../src/identity/merge";
import {
  GRACE_WINDOW_MS,
  proActiveInSubscriber,
  resolveEntitlement,
} from "../src/billing/entitlement";
import { dayKey, eventDocument, rollupDocId, rollupIncrements } from "../src/usage/events";

const T0 = 1_700_000_000_000; // a fixed "now"; real Date.now() is avoided.
const DAY = 86_400_000;

const LIMITS: UsageLimits = {
  free: { ...emptyLedger(), scans: 5, tutorMessages: 20 },
  freeDaily: { ...emptyLedger(), scans: 20, tutorMessages: 60 },
  proDaily: { ...emptyLedger(), scans: 400, tutorMessages: 600 },
};

function ledger(overrides: Partial<Record<string, number>> = {}) {
  return { ...emptyLedger(), ...overrides } as ReturnType<typeof emptyLedger>;
}

// ---------------------------------------------------------------------------
// The ledger
// ---------------------------------------------------------------------------

describe("usage ledger — reading across identities", () => {
  it("counts the MAXIMUM of the account and the device, never the sum", () => {
    // The same scan lands on both counters. Summing would charge a loyal
    // single-device student twice for every scan they ever made.
    const account = ledger({ scans: 3 });
    const device = ledger({ scans: 3 });
    expect(effectiveUsage("scans", account, device)).toBe(3);
  });

  it("takes the higher counter when they disagree", () => {
    // Signed out and kept scanning: the device knows, the fresh account does not.
    expect(effectiveUsage("scans", ledger({ scans: 0 }), ledger({ scans: 5 }))).toBe(5);
    // Reinstalled: the device forgot, the account remembers.
    expect(effectiveUsage("scans", ledger({ scans: 5 }), ledger({ scans: 0 }))).toBe(5);
  });

  it("reports every feature at once for the status callable", () => {
    const all = effectiveLedger(ledger({ scans: 4 }), ledger({ tutorMessages: 9 }));
    expect(all.scans).toBe(4);
    expect(all.tutorMessages).toBe(9);
    expect(all.practiceQuestions).toBe(0);
  });
});

describe("usage ledger — merging", () => {
  it("takes the maximum, so signing in never costs and never refunds", () => {
    const merged = mergeLedgers(ledger({ scans: 3, tutorMessages: 1 }), ledger({ scans: 1 }));
    expect(merged.scans).toBe(3);
    expect(merged.tutorMessages).toBe(1);
  });

  it("is IDEMPOTENT — replaying a merge cannot double-charge", () => {
    // Clients retry and networks drop responses; the same anonymous uid will
    // arrive at the same account more than once. Summing would quietly double
    // a student's spent allowance every time that happened.
    const anon = ledger({ scans: 3 });
    const once = mergeLedgers(anon, ledger());
    const twice = mergeLedgers(anon, once);
    const thrice = mergeLedgers(anon, twice);
    expect(twice).toEqual(once);
    expect(thrice).toEqual(once);
  });

  it("never lowers a counter", () => {
    for (const feature of METERED_FEATURES) {
      const merged = mergeLedgers(ledger({ [feature]: 2 }), ledger({ [feature]: 7 }));
      expect(merged[feature]).toBe(7);
    }
  });
});

describe("toLedger — untrusted input", () => {
  it("reads missing, negative and nonsense counters as ZERO, never as credit", () => {
    // A negative counter would read as a NEGATIVE balance, i.e. unlimited free
    // usage. Every degenerate value must fail towards zero.
    expect(toLedger(undefined)).toEqual(emptyLedger());
    expect(toLedger(null)).toEqual(emptyLedger());
    expect(toLedger({ scans: -50 }).scans).toBe(0);
    expect(toLedger({ scans: "many" }).scans).toBe(0);
    expect(toLedger({ scans: NaN }).scans).toBe(0);
    expect(toLedger({ scans: Infinity }).scans).toBe(0);
  });

  it("floors fractions and keeps real counts", () => {
    expect(toLedger({ scans: 3.9 }).scans).toBe(3);
    expect(toLedger({ scans: 4 }).scans).toBe(4);
  });

  it("ignores keys that are not metered features", () => {
    const read = toLedger({ scans: 2, freeStuff: 999 });
    expect(read.scans).toBe(2);
    expect(Object.keys(read).sort()).toEqual([...METERED_FEATURES].sort());
  });

  it("recognises exactly the catalogue", () => {
    expect(isMeteredFeature("scans")).toBe(true);
    expect(isMeteredFeature("SCANS")).toBe(false);
    expect(isMeteredFeature("toString")).toBe(false);
    expect(isMeteredFeature(undefined)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// The decision
// ---------------------------------------------------------------------------

function decide(over: Partial<Parameters<typeof decideUsage>[0]> = {}) {
  return decideUsage({
    feature: "scans",
    isPro: false,
    lifetimeUsed: 0,
    dailyUsed: 0,
    limits: LIMITS,
    now: T0,
    ...over,
  });
}

describe("decideUsage", () => {
  it("allows a free user inside their lifetime allowance", () => {
    const d = decide({ lifetimeUsed: 2 });
    expect(d.allowed).toBe(true);
    expect(d.verdict).toBe("ok");
    expect(d.remaining).toBe(2); // 5 - 2 - this one
  });

  it("refuses the request AT the ceiling, not one past it", () => {
    const at = decide({ lifetimeUsed: 5 });
    expect(at.allowed).toBe(false);
    expect(at.verdict).toBe("upgrade_required");
    expect(at.remaining).toBe(0);
    expect(decide({ lifetimeUsed: 4 }).allowed).toBe(true);
  });

  it("gives Pro users no lifetime ceiling", () => {
    const d = decide({ isPro: true, lifetimeUsed: 10_000 });
    expect(d.allowed).toBe(true);
    expect(d.limit).toBe(UNLIMITED);
    expect(d.remaining).toBe(UNLIMITED);
  });

  it("still caps Pro users daily — the cost backstop, not a product limit", () => {
    const d = decide({ isPro: true, lifetimeUsed: 10_000, dailyUsed: 400 });
    expect(d.allowed).toBe(false);
    expect(d.verdict).toBe("daily_limit");
    expect(d.retryAfterSeconds).toBeGreaterThan(0);
  });

  it("checks the LIFETIME ceiling before the daily one", () => {
    // Both are blown. The student must be told the thing paying would fix —
    // showing the paywall for a condition money cannot lift is the wrong moment.
    const d = decide({ lifetimeUsed: 5, dailyUsed: 20 });
    expect(d.verdict).toBe("upgrade_required");
  });

  it("reads a ceiling of ZERO as upgrade-required, never as allow", () => {
    // 0 is how "Pro-exclusive" is spelled — a legitimate Remote Config state.
    const d = decide({ feature: "visualExplanations" });
    expect(d.limit).toBe(0);
    expect(d.allowed).toBe(false);
    expect(d.verdict).toBe("upgrade_required");
  });

  it("treats -1 and other negatives as no ceiling", () => {
    const uncapped: UsageLimits = {
      ...LIMITS,
      free: { ...LIMITS.free, scans: UNLIMITED },
    };
    const d = decide({ limits: uncapped, lifetimeUsed: 9_999 });
    expect(d.allowed).toBe(true);
    expect(d.remaining).toBe(UNLIMITED);
  });

  it("walls off signed-out usage only when the flag says so", () => {
    expect(decide({ anonymous: true }).allowed).toBe(true);
    expect(decide({ anonymous: true, anonymousAllowed: true }).allowed).toBe(true);
    const walled = decide({ anonymous: true, anonymousAllowed: false });
    expect(walled.allowed).toBe(false);
    expect(walled.verdict).toBe("sign_in_required");
  });

  it("never walls off a PAYING anonymous user — they bought it", () => {
    const d = decide({ isPro: true, anonymous: true, anonymousAllowed: false });
    expect(d.allowed).toBe(true);
  });

  it("never returns a negative remaining", () => {
    // A corrupt counter above the ceiling must read as 0 left, not as credit.
    expect(decide({ lifetimeUsed: 99 }).remaining).toBe(0);
  });
});

describe("daily windows", () => {
  it("counts within a day and resets across the boundary", () => {
    let window = chargeDaily(undefined, "scans", T0);
    expect(dailyUsed(window, "scans", T0)).toBe(1);
    window = chargeDaily(window, "scans", T0 + 60_000);
    expect(dailyUsed(window, "scans", T0)).toBe(2);
    // Tomorrow: yesterday's count can neither block today nor be replayed.
    expect(dailyUsed(window, "scans", T0 + DAY)).toBe(0);
    const fresh = chargeDaily(window, "scans", T0 + DAY);
    expect(fresh.epoch).toBe(dayEpoch(T0 + DAY));
    expect(dailyUsed(fresh, "scans", T0 + DAY)).toBe(1);
  });

  it("keeps features independent", () => {
    const window = chargeDaily(chargeDaily(undefined, "scans", T0), "tutorMessages", T0);
    expect(dailyUsed(window, "scans", T0)).toBe(1);
    expect(dailyUsed(window, "tutorMessages", T0)).toBe(1);
    expect(dailyUsed(window, "animations", T0)).toBe(0);
  });

  it("drops a malformed stored window rather than trusting it", () => {
    expect(toDailyWindow(undefined)).toBeUndefined();
    expect(toDailyWindow({ counts: { scans: 3 } })).toBeUndefined(); // no epoch
    const read = toDailyWindow({ epoch: dayEpoch(T0), counts: { scans: -4, tutorMessages: 2 } });
    expect(read?.counts.scans).toBeUndefined();
    expect(read?.counts.tutorMessages).toBe(2);
  });

  it("never says 'retry now'", () => {
    expect(secondsUntilNextDay(T0)).toBeGreaterThan(0);
    // One millisecond before midnight UTC still rounds up to a second.
    expect(secondsUntilNextDay(dayEpoch(T0) * DAY + DAY - 1)).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Remote Config
// ---------------------------------------------------------------------------

describe("limits from Remote Config", () => {
  it("names parameters in snake_case per scope", () => {
    expect(paramName("free", "scans")).toBe("limit_scans_free");
    expect(paramName("freeDaily", "tutorMessages")).toBe("limit_tutor_messages_free_daily");
    expect(paramName("proDaily", "visualExplanations")).toBe(
      "limit_visual_explanations_pro_daily"
    );
  });

  it("falls back to the compiled default for anything malformed", () => {
    // A typo in the console must not be able to hand out infinite free scans.
    expect(readLimit({}, "k", 5)).toBe(5);
    expect(readLimit({ k: "" }, "k", 5)).toBe(5);
    expect(readLimit({ k: "lots" }, "k", 5)).toBe(5);
    expect(readLimit({ k: "-7" }, "k", 5)).toBe(5);
    expect(readLimit({ k: undefined }, "k", 5)).toBe(5);
  });

  it("honours -1 as unlimited and 0 as off", () => {
    expect(readLimit({ k: "-1" }, "k", 5)).toBe(-1);
    expect(readLimit({ k: -1 }, "k", 5)).toBe(-1);
    // 0 must survive: absence and "this tier is off" are different states.
    expect(readLimit({ k: "0" }, "k", 5)).toBe(0);
    expect(readLimit({ k: 0 }, "k", 5)).toBe(0);
  });

  it("reads live values and leaves the rest at their defaults", () => {
    const parsed = parseLimits({ [paramName("free", "scans")]: "8" });
    expect(parsed.free.scans).toBe(8);
    expect(parsed.free.tutorMessages).toBe(DEFAULT_FREE_LIMITS.tutorMessages);
    expect(parsed.freeDaily).toEqual(DEFAULT_FREE_DAILY_LIMITS);
    expect(parsed.proDaily).toEqual(DEFAULT_PRO_DAILY_LIMITS);
  });

  it("parses flags from every spelling a console produces", () => {
    expect(readFlag({ k: "true" }, "k", false)).toBe(true);
    expect(readFlag({ k: "TRUE" }, "k", false)).toBe(true);
    expect(readFlag({ k: "1" }, "k", false)).toBe(true);
    expect(readFlag({ k: false }, "k", true)).toBe(false);
    expect(readFlag({ k: "no" }, "k", true)).toBe(false);
    expect(readFlag({ k: "maybe" }, "k", true)).toBe(true); // unrecognised → fallback
    expect(parseFlags({})).toEqual(DEFAULT_FLAGS);
    expect(parseFlags({ [FLAG_PARAM.usageEnforcementEnabled]: "false" })
      .usageEnforcementEnabled).toBe(false);
  });

  it("ships a default for every parameter it will ever read", () => {
    const defaults = defaultConfigMap();
    for (const feature of METERED_FEATURES) {
      for (const scope of ["free", "freeDaily", "proDaily"] as const) {
        expect(defaults[paramName(scope, feature)]).toBe(
          String(DEFAULT_LIMITS[scope][feature])
        );
      }
    }
    for (const param of Object.values(FLAG_PARAM)) {
      expect(defaults[param]).toBeDefined();
    }
  });

  it("defaults the Pro-exclusive features to a free ceiling of ZERO", () => {
    // Today's shipped behaviour, expressed as a number so a promotion is a
    // console edit rather than a deploy.
    expect(DEFAULT_FREE_LIMITS.practiceQuestions).toBe(0);
    expect(DEFAULT_FREE_LIMITS.visualExplanations).toBe(0);
    expect(DEFAULT_FREE_LIMITS.animations).toBe(0);
    expect(DEFAULT_FREE_LIMITS.scans).toBe(5);
  });
});

// ---------------------------------------------------------------------------
// Installations
// ---------------------------------------------------------------------------

describe("installation ids", () => {
  it("accepts a Firebase installation id and rejects junk", () => {
    expect(normaliseInstallationId("cX1kY2Zq7T-abc_9:xy.z")).toBe("cX1kY2Zq7T-abc_9:xy.z");
    expect(normaliseInstallationId("  cX1kY2Zq7Tabc9xyz  ")).toBe("cX1kY2Zq7Tabc9xyz");
    expect(normaliseInstallationId("short")).toBeNull();
    expect(normaliseInstallationId("x".repeat(129))).toBeNull();
    expect(normaliseInstallationId("has spaces in it here")).toBeNull();
    expect(normaliseInstallationId("../../etc/passwd/aaaaaaaa")).toBeNull();
    expect(normaliseInstallationId(12345678901234567890)).toBeNull();
    expect(normaliseInstallationId(null)).toBeNull();
  });

  it("keys documents by a stable one-way hash, never the raw id", () => {
    const raw = "cX1kY2Zq7Tabc9xyz";
    const key = installationDocId(raw);
    expect(key).toHaveLength(64);
    expect(key).toMatch(/^[0-9a-f]+$/);
    expect(installationDocId(raw)).toBe(key); // stable
    expect(key).not.toContain(raw); // and not reversible by inspection
    expect(installationDocId(raw + "1")).not.toBe(key);
  });
});

describe("installation reducer", () => {
  const A = "uid-anon-1";
  const B = "uid-google-1";

  it("anchors the first uid and never overwrites it", () => {
    let state = emptyInstallation(T0);
    state = applyIdentityEvent(state, { kind: "seen", uid: A, anonymous: true }, T0);
    state = applyIdentityEvent(state, { kind: "seen", uid: B, anonymous: false }, T0 + 1000);
    expect(state.primaryUid).toBe(A);
    expect(state.uids).toEqual([A, B]);
    expect(state.anonymousUids).toEqual([A]);
  });

  it("counts a NEW uid as a switch and a returning one as nothing", () => {
    let state = emptyInstallation(T0);
    state = applyIdentityEvent(state, { kind: "seen", uid: A, anonymous: true }, T0);
    expect(state.lastSwitchAt).toBeUndefined(); // the first account is not a switch
    state = applyIdentityEvent(state, { kind: "seen", uid: B, anonymous: false }, T0 + 5_000);
    expect(state.lastSwitchAt).toBe(T0 + 5_000);
    const switchesAfterTwo = state.switchWindow?.count;

    // Signing back into an account you already used is not evasion.
    state = applyIdentityEvent(state, { kind: "seen", uid: A, anonymous: true }, T0 + 9_000);
    expect(state.switchWindow?.count).toBe(switchesAfterTwo);
    expect(state.uids).toEqual([A, B]);
  });

  it("remembers the fastest gap between two account switches", () => {
    let state = emptyInstallation(T0);
    state = applyIdentityEvent(state, { kind: "seen", uid: "u1", anonymous: true }, T0);
    state = applyIdentityEvent(state, { kind: "seen", uid: "u2", anonymous: true }, T0 + 60_000);
    expect(state.fastestSwitchMs).toBeUndefined(); // only one switch so far
    state = applyIdentityEvent(state, { kind: "seen", uid: "u3", anonymous: true }, T0 + 70_000);
    expect(state.fastestSwitchMs).toBe(10_000);
    state = applyIdentityEvent(state, { kind: "seen", uid: "u4", anonymous: true }, T0 + 400_000);
    expect(state.fastestSwitchMs).toBe(10_000); // keeps the MINIMUM
  });

  it("only ever raises the device's lifetime usage", () => {
    let state = emptyInstallation(T0);
    for (let i = 0; i < 7; i++) {
      state = applyIdentityEvent(
        state,
        { kind: "charge", uid: A, anonymous: true, feature: "scans" },
        T0 + i
      );
    }
    expect(state.lifetimeUsage.scans).toBe(7);

    // A different account on the same device keeps counting from 7, not 0.
    state = applyIdentityEvent(
      state,
      { kind: "charge", uid: B, anonymous: false, feature: "scans" },
      T0 + 100
    );
    expect(state.lifetimeUsage.scans).toBe(8);
  });

  it("counts sign-ins separately from sightings", () => {
    let state = emptyInstallation(T0);
    state = applyIdentityEvent(state, { kind: "seen", uid: A, anonymous: true }, T0);
    expect(state.signInCount).toBe(0);
    state = applyIdentityEvent(state, { kind: "signIn", uid: B, anonymous: false }, T0 + 1);
    expect(state.signInCount).toBe(1);
  });

  it("caps the tracked uid list so a shared device cannot grow unbounded", () => {
    let state = emptyInstallation(T0);
    for (let i = 0; i < MAX_TRACKED_UIDS + 10; i++) {
      state = applyIdentityEvent(state, { kind: "seen", uid: `u${i}`, anonymous: true }, T0 + i);
    }
    expect(state.uids).toHaveLength(MAX_TRACKED_UIDS);
    expect(state.uids[state.uids.length - 1]).toBe(`u${MAX_TRACKED_UIDS + 9}`); // newest kept
    expect(state.primaryUid).toBe("u0"); // the anchor survives the cap
  });

  it("is pure — the input state is never mutated", () => {
    const before = emptyInstallation(T0);
    const snapshot = JSON.parse(JSON.stringify(before));
    applyIdentityEvent(before, { kind: "charge", uid: A, anonymous: true, feature: "scans" }, T0);
    expect(JSON.parse(JSON.stringify(before))).toEqual(snapshot);
  });
});

describe("installation state from Firestore", () => {
  it("survives a missing or half-written document", () => {
    expect(toInstallationState(undefined, T0)).toEqual(emptyInstallation(T0));
    const partial = toInstallationState({ uids: ["a", 7, null], riskScore: -3 }, T0);
    expect(partial.uids).toEqual(["a"]);
    expect(partial.riskScore).toBe(0);
    expect(partial.lifetimeUsage).toEqual(emptyLedger());
    expect(partial.riskBand).toBe("normal");
  });

  it("round-trips through the document shape", () => {
    let state = emptyInstallation(T0);
    state = applyIdentityEvent(state, { kind: "signIn", uid: "u1", anonymous: false }, T0);
    state = applyIdentityEvent(
      state,
      { kind: "charge", uid: "u1", anonymous: false, feature: "scans" },
      T0
    );
    const doc = toDocument(state);
    const back = toInstallationState(doc as Record<string, unknown>, T0);
    expect(back.uids).toEqual(state.uids);
    expect(back.lifetimeUsage).toEqual(state.lifetimeUsage);
    expect(back.signInCount).toBe(state.signInCount);
    expect(back.primaryUid).toBe(state.primaryUid);
  });
});

// ---------------------------------------------------------------------------
// Risk — advisory only
// ---------------------------------------------------------------------------

describe("risk scoring", () => {
  const quiet = {
    accountCount: 1,
    anonymousAccountCount: 1,
    signInCount: 1,
    accountsLastDay: 1,
    requestsLastHour: 3,
    ageMs: DAY,
  };

  it("scores an ordinary student at zero", () => {
    const r = assessRisk(quiet);
    expect(r.score).toBe(0);
    expect(r.band).toBe("normal");
    expect(r.reasons).toEqual([]);
  });

  it("leaves a family device — three accounts, a few sign-ins — well below alarm", () => {
    const r = assessRisk({ ...quiet, accountCount: 3, anonymousAccountCount: 2, signInCount: 8 });
    expect(r.band).toBe("normal");
  });

  it("does not let a single shared classroom device max the score", () => {
    // Twenty accounts on one iPad is a real school, not a farm. One signal,
    // however extreme, must stay capped.
    const r = assessRisk({ ...quiet, accountCount: 20 });
    expect(r.score).toBeLessThan(60);
    expect(r.reasons.map((x) => x.code)).toEqual(["many_accounts"]);
  });

  it("raises the band when several signals trip together", () => {
    const r = assessRisk({
      accountCount: 14,
      anonymousAccountCount: 12,
      signInCount: 70,
      accountsLastDay: 9,
      requestsLastHour: 160,
      fastestSwitchMs: 4_000,
      ageMs: 3 * 3_600_000,
    });
    expect(r.band).toBe("elevated");
    expect(r.reasons.length).toBeGreaterThanOrEqual(4);
  });

  it("never exceeds 100 and never goes negative", () => {
    const worst = assessRisk({
      accountCount: 9_999,
      anonymousAccountCount: 9_999,
      signInCount: 9_999,
      accountsLastDay: 9_999,
      requestsLastHour: 9_999,
      fastestSwitchMs: 0,
      ageMs: 0,
    });
    expect(worst.score).toBeLessThanOrEqual(100);
    expect(assessRisk(quiet).score).toBeGreaterThanOrEqual(0);
  });

  it("returns a reason a human can read for everything it counts", () => {
    const r = assessRisk({ ...quiet, accountCount: 20 });
    for (const reason of r.reasons) {
      expect(reason.detail.length).toBeGreaterThan(10);
      expect(reason.points).toBeGreaterThan(0);
    }
  });

  it("produces advice, never a refusal — the assessment carries no verdict", () => {
    // Load-bearing. `deviceRiskScore` exists for a dashboard and a human in the
    // loop. If anybody ever adds an `allowed`/`block` field here, this fails and
    // they have to justify it in review — which is exactly the point.
    const r = assessRisk({ ...quiet, accountCount: 50, requestsLastHour: 900 });
    expect(Object.keys(r).sort()).toEqual(["band", "reasons", "score"]);
  });

  it("scores the signals a real installation produces", () => {
    let state = emptyInstallation(T0);
    for (let i = 0; i < 6; i++) {
      state = applyIdentityEvent(state, { kind: "signIn", uid: `u${i}`, anonymous: true }, T0 + i * 1000);
    }
    const signals = riskSignalsFor(state, T0 + 6000);
    expect(signals.accountCount).toBe(6);
    expect(signals.anonymousAccountCount).toBe(6);
    expect(signals.signInCount).toBe(6);
    expect(signals.accountsLastDay).toBe(6); // 5 switches + the first account
    expect(assessRisk(signals).score).toBeGreaterThan(0);
  });
});

// ---------------------------------------------------------------------------
// Merging
// ---------------------------------------------------------------------------

describe("account merge", () => {
  const anon = {
    uid: "anon-1",
    usage: ledger({ scans: 3 }),
    installationIds: ["dev-a"],
  };

  it("carries the anonymous session's usage into the account", () => {
    const result = planMerge({
      source: anon,
      target: { uid: "google-1", usage: ledger(), installationIds: [] },
    });
    expect(result.changed).toBe(true);
    expect(result.reason).toBe("merged");
    expect(result.usage.scans).toBe(3);
    expect(result.installationIds).toEqual(["dev-a"]);
  });

  it("keeps the account's own history when it is larger", () => {
    const result = planMerge({
      source: anon,
      target: { uid: "google-1", usage: ledger({ scans: 5 }), installationIds: ["dev-b"] },
    });
    expect(result.usage.scans).toBe(5);
    expect(result.installationIds.sort()).toEqual(["dev-a", "dev-b"]);
  });

  it("refuses to merge an account into itself", () => {
    const result = planMerge({
      source: { ...anon, uid: "same" },
      target: { uid: "same", usage: ledger({ scans: 1 }), installationIds: [] },
    });
    expect(result.changed).toBe(false);
    expect(result.reason).toBe("same_account");
    expect(result.usage.scans).toBe(1);
  });

  it("refuses to launder one anonymous session through a SECOND account", () => {
    // Sign in as A, merge, sign out, sign in as B, replay the merge. Allowing it
    // would smear one device's trail across accounts that never touched it.
    const result = planMerge({
      source: { ...anon, mergedInto: "google-1" },
      target: { uid: "google-2", usage: ledger(), installationIds: [] },
    });
    expect(result.changed).toBe(false);
    expect(result.reason).toBe("already_merged");
    expect(result.usage.scans).toBe(0);
  });

  it("is a no-op when replayed into the SAME target", () => {
    const first = planMerge({
      source: anon,
      target: { uid: "google-1", usage: ledger(), installationIds: [] },
    });
    const replay = planMerge({
      source: { ...anon, mergedInto: "google-1" },
      target: {
        uid: "google-1",
        usage: first.usage,
        installationIds: first.installationIds,
      },
    });
    expect(replay.changed).toBe(false);
    expect(replay.reason).toBe("nothing_to_merge");
    expect(replay.usage).toEqual(first.usage);
  });
});

// ---------------------------------------------------------------------------
// Entitlement
// ---------------------------------------------------------------------------

describe("entitlement resolution", () => {
  it("grants Pro inside a renewing subscription", () => {
    const view = resolveEntitlement(
      { isPro: true, expiresAtMs: T0 + DAY, willRenew: true },
      "pro",
      T0
    );
    expect(view.state).toBe("active");
    expect(view.isPro).toBe(true);
  });

  it("KEEPS Pro after cancellation until the paid period ends", () => {
    // Auto-renew off is not revocation. Treating cancel as revoke is the classic
    // way to take away access somebody has already paid for.
    const view = resolveEntitlement(
      { isPro: true, expiresAtMs: T0 + 10 * DAY, willRenew: false },
      "pro",
      T0
    );
    expect(view.state).toBe("cancelled");
    expect(view.isPro).toBe(true);
  });

  it("KEEPS Pro through a billing retry past the expiry date", () => {
    const view = resolveEntitlement(
      { isPro: true, expiresAtMs: T0 - DAY, hasBillingIssue: true },
      "pro",
      T0
    );
    expect(view.state).toBe("grace");
    expect(view.isPro).toBe(true);
  });

  it("stops granting once the store's grace window is exhausted", () => {
    const view = resolveEntitlement(
      { isPro: true, expiresAtMs: T0 - GRACE_WINDOW_MS - DAY, hasBillingIssue: true },
      "pro",
      T0
    );
    expect(view.state).toBe("expired");
    expect(view.isPro).toBe(false);
  });

  it("lets a real expiry date beat a stale isPro flag", () => {
    const view = resolveEntitlement({ isPro: true, expiresAtMs: T0 - DAY }, "pro", T0);
    expect(view.state).toBe("expired");
    expect(view.isPro).toBe(false);
  });

  it("honours a lifetime grant with no expiry", () => {
    const view = resolveEntitlement({ isPro: true, willRenew: true }, "pro", T0);
    expect(view.isPro).toBe(true);
  });

  it("reads a student who never paid as none, not expired", () => {
    const view = resolveEntitlement(undefined, "none", T0);
    expect(view.state).toBe("none");
    expect(view.isPro).toBe(false);
  });

  it("reads RevenueCat's own grace field", () => {
    const body = (ent: Record<string, unknown>) => ({ subscriber: { entitlements: { pro: ent } } });
    expect(
      proActiveInSubscriber(
        body({
          expires_date: new Date(T0 - DAY).toISOString(),
          grace_period_expires_date: new Date(T0 + DAY).toISOString(),
        }),
        T0
      )
    ).toBe(true);
    expect(
      proActiveInSubscriber(body({ expires_date: new Date(T0 - DAY).toISOString() }), T0)
    ).toBe(false);
    expect(proActiveInSubscriber(body({ expires_date: null }), T0)).toBe(true);
    expect(proActiveInSubscriber({ subscriber: { entitlements: {} } }, T0)).toBe(false);
    expect(proActiveInSubscriber(null, T0)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Analytics
// ---------------------------------------------------------------------------

describe("usage events", () => {
  it("buckets by UTC day", () => {
    expect(dayKey(T0)).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(rollupDocId(T0)).toBe(`daily_${dayKey(T0)}`);
    expect(dayKey(T0)).not.toBe(dayKey(T0 + DAY));
  });

  it("drops undefined fields — Firestore rejects them", () => {
    const doc = eventDocument({ action: "install", uid: "u1", installation: null }, T0);
    expect(doc).not.toHaveProperty("feature");
    expect(doc).not.toHaveProperty("verdict");
    expect(doc.uid).toBe("u1");
    expect(doc.installation).toBeNull();
    expect(doc.day).toBe(dayKey(T0));
  });

  it("carries no problem text, image or answer — it is a meter reading", () => {
    const doc = eventDocument(
      { action: "charge", uid: "u1", installation: "hash", feature: "scans", isPro: false },
      T0
    );
    const keys = Object.keys(doc);
    for (const forbidden of ["latex", "problem", "image", "answer", "prompt"]) {
      expect(keys).not.toContain(forbidden);
    }
  });

  it("counts the funnel questions the product actually asks", () => {
    const free = rollupIncrements({
      action: "charge",
      uid: "u",
      installation: null,
      feature: "scans",
      isPro: false,
    });
    expect(free).toMatchObject({ events: 1, charges: 1, freeCharges: 1 });
    expect(free["feature.scans.charges"]).toBe(1);
    expect(free.proCharges).toBeUndefined();

    const paid = rollupIncrements({
      action: "charge",
      uid: "u",
      installation: null,
      feature: "scans",
      isPro: true,
    });
    expect(paid.proCharges).toBe(1);
    expect(paid.freeCharges).toBeUndefined();

    const wall = rollupIncrements({
      action: "refused",
      uid: "u",
      installation: null,
      feature: "scans",
      verdict: "upgrade_required",
    });
    expect(wall).toMatchObject({ refusals: 1, upgradeRequired: 1 });

    expect(rollupIncrements({ action: "merge", uid: "u", installation: null }).merges).toBe(1);
    expect(rollupIncrements({ action: "link", uid: "u", installation: null }).signIns).toBe(1);
    expect(rollupIncrements({ action: "install", uid: "u", installation: null }).installs).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// The scenarios the whole system exists for
// ---------------------------------------------------------------------------

describe("evasion scenarios", () => {
  // A small in-memory model of the two ledgers the guard consults, so a whole
  // user journey can be played out against the real decision functions.
  function world() {
    const accounts = new Map<string, ReturnType<typeof emptyLedger>>();
    let device = emptyInstallation(T0);
    let clock = T0;

    return {
      get deviceUsage() {
        return device.lifetimeUsage;
      },
      newDevice() {
        device = emptyInstallation(clock);
      },
      /** Try to scan as [uid]; charges both ledgers when allowed. */
      scan(uid: string, opts: { isPro?: boolean } = {}) {
        clock += 60_000;
        const account = accounts.get(uid) ?? emptyLedger();
        const decision = decideUsage({
          feature: "scans",
          isPro: opts.isPro ?? false,
          lifetimeUsed: effectiveUsage("scans", account, device.lifetimeUsage),
          dailyUsed: 0,
          limits: LIMITS,
          now: clock,
        });
        if (decision.allowed) {
          accounts.set(uid, { ...account, scans: account.scans + 1 });
          device = applyIdentityEvent(
            device,
            { kind: "charge", uid, anonymous: false, feature: "scans" },
            clock
          );
        } else {
          device = applyIdentityEvent(device, { kind: "seen", uid, anonymous: false }, clock);
        }
        return decision;
      },
      signIn(from: string, to: string) {
        clock += 1000;
        const plan = planMerge({
          source: { uid: from, usage: accounts.get(from) ?? emptyLedger(), installationIds: [] },
          target: { uid: to, usage: accounts.get(to) ?? emptyLedger(), installationIds: [] },
        });
        accounts.set(to, plan.usage);
        device = applyIdentityEvent(device, { kind: "signIn", uid: to, anonymous: false }, clock);
        return plan;
      },
      usage(uid: string) {
        return effectiveUsage("scans", accounts.get(uid) ?? emptyLedger(), device.lifetimeUsage);
      },
    };
  }

  it("spends the free allowance and then stops", () => {
    const w = world();
    for (let i = 0; i < 5; i++) expect(w.scan("anon-1").allowed).toBe(true);
    expect(w.scan("anon-1").verdict).toBe("upgrade_required");
  });

  it("SIGNING OUT AND INTO A NEW GOOGLE ACCOUNT does not restore free usage", () => {
    // The cheapest and by far the most common attack. The new account's own
    // counter is 0, but the DEVICE has spent five and does not care who is
    // holding it.
    const w = world();
    for (let i = 0; i < 5; i++) w.scan("anon-1");
    const fresh = w.scan("google-brand-new");
    expect(fresh.allowed).toBe(false);
    expect(fresh.verdict).toBe("upgrade_required");
  });

  it("SWITCHING BETWEEN SEVERAL ACCOUNTS gets no further than one", () => {
    const w = world();
    for (let i = 0; i < 5; i++) w.scan("anon-1");
    for (const uid of ["google-a", "apple-b", "email-c", "anon-2"]) {
      expect(w.scan(uid).allowed).toBe(false);
    }
    expect(w.deviceUsage.scans).toBe(5); // refusals cost nothing, so nothing inflates
  });

  it("LOGGING OUT does not restore free usage", () => {
    // No merge happens on sign-OUT — there is nothing to merge into. The device
    // ledger alone is what carries the three spent scans into the guest session.
    const w = world();
    for (let i = 0; i < 3; i++) w.scan("google-1");
    expect(w.scan("anon-2").allowed).toBe(true); // 4th
    expect(w.scan("anon-2").allowed).toBe(true); // 5th
    expect(w.scan("anon-2").allowed).toBe(false); // and no further
  });

  it("REINSTALLING does not restore free usage for the same account", () => {
    // The device counter is gone. The account's is not, and it is consulted on
    // every request.
    const w = world();
    for (let i = 0; i < 5; i++) w.scan("google-1");
    w.newDevice();
    expect(w.deviceUsage.scans).toBe(0);
    expect(w.scan("google-1").allowed).toBe(false);
  });

  it("only a NEW DEVICE AND a NEW ACCOUNT gets back to zero — the accepted bar", () => {
    // Stated plainly because it is a product decision, not a gap: abuse is not
    // impossible, only more expensive than it is worth.
    const w = world();
    for (let i = 0; i < 5; i++) w.scan("google-1");
    w.newDevice();
    expect(w.scan("google-2").allowed).toBe(true);
  });

  it("ANONYMOUS → GOOGLE carries the spent usage across, and only once", () => {
    const w = world();
    for (let i = 0; i < 3; i++) w.scan("anon-1");
    const merged = w.signIn("anon-1", "google-1");
    expect(merged.usage.scans).toBe(3);
    expect(w.usage("google-1")).toBe(3);

    // Two scans left, not five.
    expect(w.scan("google-1").allowed).toBe(true);
    expect(w.scan("google-1").allowed).toBe(true);
    expect(w.scan("google-1").allowed).toBe(false);
  });

  it("ANONYMOUS → APPLE behaves identically — the provider is not part of the rule", () => {
    const w = world();
    for (let i = 0; i < 4; i++) w.scan("anon-1");
    w.signIn("anon-1", "apple-1");
    expect(w.usage("apple-1")).toBe(4);
    expect(w.scan("apple-1").allowed).toBe(true);
    expect(w.scan("apple-1").allowed).toBe(false);
  });

  it("a REPLAYED merge cannot inflate what a student has spent", () => {
    const w = world();
    for (let i = 0; i < 2; i++) w.scan("anon-1");
    w.signIn("anon-1", "google-1");
    w.signIn("anon-1", "google-1");
    w.signIn("anon-1", "google-1");
    expect(w.usage("google-1")).toBe(2); // not 6
  });

  it("SUBSCRIBING lifts the wall immediately, and expiry puts it back", () => {
    const w = world();
    for (let i = 0; i < 5; i++) w.scan("google-1");
    expect(w.scan("google-1").allowed).toBe(false);

    // RevenueCat says active — the same spent counters, a different ceiling.
    expect(w.scan("google-1", { isPro: true }).allowed).toBe(true);

    // And when it lapses, the free ceiling applies again to usage that was
    // never reset. Nobody gets a fresh five for having once paid.
    expect(w.scan("google-1").allowed).toBe(false);
  });
});
