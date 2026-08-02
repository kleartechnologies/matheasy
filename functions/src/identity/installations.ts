/**
 * The Installation Manager — layer 1 of the identity stack.
 *
 * An installation is one copy of the app on one device. Firebase Installations
 * gives it an ID; the client sends that ID with every metered request, and this
 * file is where it becomes a durable record of what that copy of the app has
 * spent, independently of who happens to be signed into it right now.
 *
 * WHAT IS AND IS NOT BEING CLAIMED
 *
 * The installation ID is client-supplied and therefore forgeable. A determined
 * user can send a fresh random string and look like a new device. This layer is
 * not trying to stop that person; App Check is the tool for that, and it is a
 * separate, orthogonal deployment. What this layer stops is the far more common
 * and far cheaper attack: sign out, sign in with another Google account, keep
 * scanning. That costs nothing today and costs everything after this file,
 * because the device's counter does not care which account is holding it.
 *
 * PRIVACY
 *
 * The raw installation ID is never stored. The document key is its SHA-256, so
 * the database holds an opaque, non-reversible handle that still resolves from
 * the value the client sends. Nothing here touches IMEI, MAC, serial number,
 * IDFA/AAID, or any other hardware or advertising identifier — all of which are
 * prohibited by the App Store, restricted on Play, and would be personal data
 * under GDPR. The Firebase installation ID is app-scoped, resettable by
 * deleting the app, and deleted on request; that is the whole point of using it.
 */
import { createHash } from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

import { MeteredFeature, UsageLedger, emptyLedger, toLedger } from "../usage/features";
import { DailyWindow, chargeDaily, dayEpoch, toDailyWindow } from "../usage/ledger";
import { RiskAssessment, RiskSignals, assessRisk } from "./risk";
import { db } from "../lib/db";

/** How many uids we keep per installation. A shared classroom device is real. */
export const MAX_TRACKED_UIDS = 50;

// ---------------------------------------------------------------------------
// The ID itself
// ---------------------------------------------------------------------------

/**
 * Accept a client-sent installation ID, or reject it.
 *
 * Firebase installation IDs are 22-character URL-safe base64. The check is
 * deliberately looser than that (any 16-128 char printable token) because the
 * ID also comes from a locally-generated fallback on platforms where the
 * Installations SDK is unavailable — but it is strict enough that an oversized
 * or structured value cannot be used to smuggle anything into a document key.
 */
export function normaliseInstallationId(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (trimmed.length < 16 || trimmed.length > 128) return null;
  if (!/^[A-Za-z0-9_:.-]+$/.test(trimmed)) return null;
  return trimmed;
}

/**
 * The document key for an installation: the SHA-256 of its ID.
 *
 * One-way on purpose. A leaked export of this collection reveals usage patterns
 * against opaque handles, not a list of device identifiers.
 */
export function installationDocId(installationId: string): string {
  return createHash("sha256").update(installationId).digest("hex");
}

// ---------------------------------------------------------------------------
// State — a pure reducer, so the interesting logic is testable
// ---------------------------------------------------------------------------

export interface InstallationState {
  createdAt: number;
  lastSeenAt: number;
  /** The first uid ever seen here. Never overwritten. */
  primaryUid: string | null;
  /** Every uid seen here, newest last, capped at [MAX_TRACKED_UIDS]. */
  uids: string[];
  /** The subset of [uids] that were anonymous when first seen. */
  anonymousUids: string[];
  /** What this DEVICE has spent, whoever was holding it. */
  lifetimeUsage: UsageLedger;
  daily?: DailyWindow;
  signInCount: number;
  /** Requests in the current hour, for the burst signal. */
  requestWindow?: { epoch: number; count: number };
  /** When a different uid last took over this installation. */
  lastSwitchAt?: number;
  /** Account switches inside the current UTC day. */
  switchWindow?: { epoch: number; count: number };
  /** The shortest gap ever seen between two account switches. */
  fastestSwitchMs?: number;
  riskScore: number;
  riskBand: RiskAssessment["band"];
}

export function emptyInstallation(now: number): InstallationState {
  return {
    createdAt: now,
    lastSeenAt: now,
    primaryUid: null,
    uids: [],
    anonymousUids: [],
    lifetimeUsage: emptyLedger(),
    signInCount: 0,
    riskScore: 0,
    riskBand: "normal",
  };
}

/** Read an installation document into state, tolerating anything missing. */
export function toInstallationState(
  raw: Record<string, unknown> | undefined,
  now: number
): InstallationState {
  if (!raw) return emptyInstallation(now);
  const uids = stringArray(raw.uids);
  return {
    createdAt: millis(raw.createdAtMs, now),
    lastSeenAt: millis(raw.lastSeenAtMs, now),
    primaryUid: typeof raw.primaryUid === "string" ? raw.primaryUid : null,
    uids,
    anonymousUids: stringArray(raw.anonymousUids),
    lifetimeUsage: toLedger(raw.lifetimeUsage),
    daily: toDailyWindow(raw.daily),
    signInCount: count(raw.signInCount),
    requestWindow: toRequestWindow(raw.requestWindow),
    switchWindow: toRequestWindow(raw.switchWindow),
    lastSwitchAt: optionalMillis(raw.lastSwitchAtMs),
    fastestSwitchMs: optionalMillis(raw.fastestSwitchMs),
    riskScore: count(raw.riskScore),
    riskBand: (raw.riskBand as RiskAssessment["band"]) ?? "normal",
  };
}

/** Something that happened on an installation. */
export type IdentityEvent =
  | { kind: "seen"; uid: string; anonymous: boolean }
  | { kind: "signIn"; uid: string; anonymous: boolean }
  | { kind: "charge"; uid: string; anonymous: boolean; feature: MeteredFeature };

/**
 * Fold an event into installation state. PURE — no clock, no Firestore.
 *
 * The rules that matter, in one place:
 *  - `primaryUid` is written once and never changed. It is the anchor: the
 *    account this device belonged to first.
 *  - `lifetimeUsage` only ever goes up. There is no branch that lowers it.
 *  - A uid that is already known is not a "switch". Signing back into the
 *    account you were already using is not evasion, and scoring it as one would
 *    punish exactly the students who behave most normally.
 */
export function applyIdentityEvent(
  state: InstallationState,
  event: IdentityEvent,
  now: number
): InstallationState {
  const next: InstallationState = {
    ...state,
    lastSeenAt: now,
    uids: [...state.uids],
    anonymousUids: [...state.anonymousUids],
    lifetimeUsage: { ...state.lifetimeUsage },
  };

  const known = next.uids.includes(event.uid);
  if (!known) {
    // A genuinely new identity on this device. Everything switch-related keys
    // off this branch, so a returning account never looks like a fresh one.
    if (next.uids.length > 0) {
      if (next.lastSwitchAt !== undefined) {
        const gap = now - next.lastSwitchAt;
        next.fastestSwitchMs =
          next.fastestSwitchMs === undefined
            ? gap
            : Math.min(next.fastestSwitchMs, gap);
      }
      next.lastSwitchAt = now;
      next.switchWindow = bumpDay(next.switchWindow, now);
    }
    next.uids = cap([...next.uids, event.uid]);
    if (event.anonymous) next.anonymousUids = cap([...next.anonymousUids, event.uid]);
    next.primaryUid ??= event.uid;
  }

  if (event.kind === "signIn") next.signInCount += 1;

  if (event.kind === "charge") {
    next.lifetimeUsage[event.feature] = (next.lifetimeUsage[event.feature] ?? 0) + 1;
    next.daily = chargeDaily(next.daily, event.feature, now);
    next.requestWindow = bumpHour(next.requestWindow, now);
  }

  return next;
}

/**
 * The risk signals implied by a state — the bridge between the reducer and the
 * scorer, kept separate so the scorer never has to know about Firestore shapes.
 *
 * `accountsLastDay` is switches-today plus one, because N switches means N+1
 * accounts have held the device today. Counting switches instead of stamping
 * every uid keeps this to two integers on a document we are already writing.
 */
export function riskSignalsFor(state: InstallationState, now: number): RiskSignals {
  const switchesToday =
    state.switchWindow?.epoch === dayEpoch(now) ? state.switchWindow.count : 0;
  return {
    accountCount: state.uids.length,
    anonymousAccountCount: state.anonymousUids.length,
    signInCount: state.signInCount,
    accountsLastDay: state.uids.length === 0 ? 0 : switchesToday + 1,
    requestsLastHour:
      state.requestWindow?.epoch === hourEpoch(now) ? state.requestWindow.count : 0,
    fastestSwitchMs: state.fastestSwitchMs,
    ageMs: Math.max(0, now - state.createdAt),
  };
}

/** The Firestore shape for a state. Timestamps are plain millis for portability. */
export function toDocument(state: InstallationState): Record<string, unknown> {
  return {
    createdAtMs: state.createdAt,
    lastSeenAtMs: state.lastSeenAt,
    primaryUid: state.primaryUid,
    uids: state.uids,
    anonymousUids: state.anonymousUids,
    accountCount: state.uids.length,
    lifetimeUsage: state.lifetimeUsage,
    daily: state.daily ?? null,
    signInCount: state.signInCount,
    requestWindow: state.requestWindow ?? null,
    switchWindow: state.switchWindow ?? null,
    lastSwitchAtMs: state.lastSwitchAt ?? null,
    fastestSwitchMs: state.fastestSwitchMs ?? null,
    riskScore: state.riskScore,
    riskBand: state.riskBand,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

// ---------------------------------------------------------------------------
// Firestore
// ---------------------------------------------------------------------------

export function installationRef(installationId: string) {
  return db.collection("installations").doc(installationDocId(installationId));
}

/**
 * Record an event against an installation and return the resulting state.
 *
 * Transactional because two requests from the same device arriving together
 * must not each read a counter of 4 and each write 5. The risk score is
 * recomputed on the way through, so the monitoring number is never stale.
 *
 * Best-effort by contract: if this throws, the caller degrades to account-only
 * enforcement rather than failing the student's request. A device counter is a
 * defence in depth, not a load-bearing wall — losing it costs a few free scans,
 * while failing closed would cost a lesson.
 */
export async function recordInstallationEvent(
  installationId: string,
  event: IdentityEvent,
  options: { scoreRisk?: boolean; now?: number } = {}
): Promise<InstallationState> {
  const now = options.now ?? Date.now();
  const ref = installationRef(installationId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const before = toInstallationState(
      snap.exists ? (snap.data() as Record<string, unknown>) : undefined,
      now
    );
    let after = applyIdentityEvent(before, event, now);

    if (options.scoreRisk !== false) {
      const assessment = assessRisk(riskSignalsFor(after, now));
      after = { ...after, riskScore: assessment.score, riskBand: assessment.band };
      if (assessment.band === "elevated" && before.riskBand !== "elevated") {
        // Worth a human's attention, never an automatic refusal.
        logger.warn("Installation risk elevated", {
          installation: installationDocId(installationId),
          score: assessment.score,
          reasons: assessment.reasons.map((r) => r.code),
        });
      }
    }

    tx.set(ref, toDocument(after), { merge: true });
    return after;
  });
}

/** Read an installation's state without writing. Used by the status callable. */
export async function readInstallation(
  installationId: string,
  now: number = Date.now()
): Promise<InstallationState> {
  const snap = await installationRef(installationId).get();
  return toInstallationState(
    snap.exists ? (snap.data() as Record<string, unknown>) : undefined,
    now
  );
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function cap(list: string[]): string[] {
  return list.length <= MAX_TRACKED_UIDS ? list : list.slice(list.length - MAX_TRACKED_UIDS);
}

function stringArray(raw: unknown): string[] {
  return Array.isArray(raw) ? raw.filter((v): v is string => typeof v === "string") : [];
}

function count(raw: unknown): number {
  const value = Number(raw);
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
}

function millis(raw: unknown, fallback: number): number {
  const value = Number(raw);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function optionalMillis(raw: unknown): number | undefined {
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : undefined;
}

function hourEpoch(now: number): number {
  return Math.floor(now / 3_600_000);
}

function bumpHour(
  window: { epoch: number; count: number } | undefined,
  now: number
): { epoch: number; count: number } {
  return bump(window, hourEpoch(now));
}

function bumpDay(
  window: { epoch: number; count: number } | undefined,
  now: number
): { epoch: number; count: number } {
  return bump(window, dayEpoch(now));
}

/** Count into a fixed window, starting over when its epoch has rolled. */
function bump(
  window: { epoch: number; count: number } | undefined,
  epoch: number
): { epoch: number; count: number } {
  if (!window || window.epoch !== epoch) return { epoch, count: 1 };
  return { epoch, count: window.count + 1 };
}

function toRequestWindow(raw: unknown): { epoch: number; count: number } | undefined {
  const source = raw as { epoch?: unknown; count?: unknown } | undefined;
  const epoch = Number(source?.epoch);
  if (!Number.isFinite(epoch)) return undefined;
  return { epoch, count: count(source?.count) };
}
