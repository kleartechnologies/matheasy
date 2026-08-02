/**
 * Where the limits come from — Firebase Remote Config, read server-side.
 *
 * Nothing in this system hardcodes an allowance. A limit that can only change
 * with a deploy is a limit you will not change: not for a promotion, not for a
 * school pilot, not at 2am when a pricing experiment is losing money. So the
 * numbers live in Remote Config and the server reads them with the Admin SDK —
 * the SERVER template, never the client's, because a value the client can read
 * is a value the client can lie about.
 *
 * Three properties this file exists to guarantee:
 *
 *  - A Remote Config outage must never open the gates. Every read falls back to
 *    the compiled defaults, which are today's shipped numbers.
 *  - A malformed value must never open the gates either. A limit that parses to
 *    NaN, a string, or a negative number is not "unlimited by accident" — it is
 *    the default. Only the explicit sentinel -1 means unlimited, and only for a
 *    daily ceiling.
 *  - It must not add a network round-trip to every scan. The evaluated template
 *    is cached in module scope for [CACHE_TTL_MS]; a warm instance answers from
 *    memory, and a stale-by-a-few-minutes limit is a non-event.
 */
import { getRemoteConfig } from "firebase-admin/remote-config";
import { logger } from "firebase-functions/v2";

import {
  DEFAULT_FREE_DAILY_LIMITS,
  DEFAULT_FREE_LIMITS,
  DEFAULT_PRO_DAILY_LIMITS,
  METERED_FEATURES,
  MeteredFeature,
  UsageLedger,
} from "./features";
import { UsageLimits } from "./ledger";

/** The compiled fallback — what the server enforces if Remote Config says nothing. */
export const DEFAULT_LIMITS: UsageLimits = {
  free: DEFAULT_FREE_LIMITS,
  freeDaily: DEFAULT_FREE_DAILY_LIMITS,
  proDaily: DEFAULT_PRO_DAILY_LIMITS,
};

/**
 * The Remote Config parameter names, spelled out.
 *
 * Flat keys rather than one JSON blob, because a Remote Config CONDITION can
 * target a single parameter — which is what makes "give Malaysian users 8 free
 * scans this month" or a percentage rollout possible without touching code.
 */
export function paramName(
  scope: "free" | "freeDaily" | "proDaily",
  feature: MeteredFeature
): string {
  const suffix =
    scope === "free" ? "free" : scope === "freeDaily" ? "free_daily" : "pro_daily";
  return `limit_${snake(feature)}_${suffix}`;
}

function snake(feature: string): string {
  return feature.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);
}

/** Feature flags the server owns. Same fallback discipline as the limits. */
export interface FeatureFlags {
  /** Whether the anti-abuse gate enforces at all. OFF still meters and logs. */
  usageEnforcementEnabled: boolean;
  /** Whether anonymous (signed-out) installs may spend free usage. */
  anonymousUsageEnabled: boolean;
  /** Whether the risk engine records scores. Never blocks either way. */
  riskScoringEnabled: boolean;
}

export const DEFAULT_FLAGS: FeatureFlags = {
  usageEnforcementEnabled: true,
  anonymousUsageEnabled: true,
  riskScoringEnabled: true,
};

export const FLAG_PARAM = {
  usageEnforcementEnabled: "usage_enforcement_enabled",
  anonymousUsageEnabled: "anonymous_usage_enabled",
  riskScoringEnabled: "risk_scoring_enabled",
} as const;

// ---------------------------------------------------------------------------
// Parsing — pure, and the part that has to be paranoid
// ---------------------------------------------------------------------------

/** A flat `param -> value` view of an evaluated template. */
export type ConfigValues = Record<string, string | number | boolean | undefined>;

/**
 * One limit, read defensively.
 *
 * `-1` is honoured as "no ceiling" because that is the sentinel the rest of the
 * system speaks. Every other non-integer, negative or absent value falls back —
 * a typo in the console must not be able to hand out infinite free scans, and
 * "0" (feature off for this tier) must survive, so absence and zero cannot be
 * conflated.
 */
export function readLimit(
  values: ConfigValues,
  key: string,
  fallback: number
): number {
  const raw = values[key];
  if (raw === undefined || raw === null || raw === "") return fallback;
  const value = typeof raw === "number" ? raw : Number(String(raw).trim());
  if (!Number.isFinite(value)) return fallback;
  const floored = Math.floor(value);
  if (floored === -1) return -1;
  if (floored < 0) return fallback;
  return floored;
}

/** A boolean flag, read defensively. Anything unrecognised is the fallback. */
export function readFlag(
  values: ConfigValues,
  key: string,
  fallback: boolean
): boolean {
  const raw = values[key];
  if (typeof raw === "boolean") return raw;
  if (raw === undefined || raw === null) return fallback;
  const text = String(raw).trim().toLowerCase();
  if (text === "true" || text === "1" || text === "yes") return true;
  if (text === "false" || text === "0" || text === "no") return false;
  return fallback;
}

/** Build the full limit set from an evaluated template. Pure. */
export function parseLimits(values: ConfigValues): UsageLimits {
  const ledger = (scope: "free" | "freeDaily" | "proDaily"): UsageLedger => {
    const out = {} as UsageLedger;
    for (const feature of METERED_FEATURES) {
      out[feature] = readLimit(
        values,
        paramName(scope, feature),
        DEFAULT_LIMITS[scope][feature]
      );
    }
    return out;
  };
  return { free: ledger("free"), freeDaily: ledger("freeDaily"), proDaily: ledger("proDaily") };
}

/** Build the flag set from an evaluated template. Pure. */
export function parseFlags(values: ConfigValues): FeatureFlags {
  return {
    usageEnforcementEnabled: readFlag(
      values,
      FLAG_PARAM.usageEnforcementEnabled,
      DEFAULT_FLAGS.usageEnforcementEnabled
    ),
    anonymousUsageEnabled: readFlag(
      values,
      FLAG_PARAM.anonymousUsageEnabled,
      DEFAULT_FLAGS.anonymousUsageEnabled
    ),
    riskScoringEnabled: readFlag(
      values,
      FLAG_PARAM.riskScoringEnabled,
      DEFAULT_FLAGS.riskScoringEnabled
    ),
  };
}

// ---------------------------------------------------------------------------
// Fetching — the only impure part
// ---------------------------------------------------------------------------

export interface RemoteSettings {
  limits: UsageLimits;
  flags: FeatureFlags;
  /** False when these are the compiled defaults rather than a live read. */
  fromRemoteConfig: boolean;
}

const CACHE_TTL_MS = 5 * 60 * 1000;

let cached: { at: number; settings: RemoteSettings } | null = null;

/** Drop the cache. Tests and the emulator only. */
export function resetSettingsCache(): void {
  cached = null;
}

/**
 * The live limits and flags, cached for five minutes per instance.
 *
 * Failure is not an error here. If Remote Config cannot be reached the compiled
 * defaults are returned and the request proceeds — the alternative, failing a
 * student's scan because a config service blinked, is worse than enforcing
 * yesterday's numbers. The result is marked `fromRemoteConfig: false` so the
 * logs can tell the two apart.
 */
export async function getSettings(now: number = Date.now()): Promise<RemoteSettings> {
  if (cached && now - cached.at < CACHE_TTL_MS) return cached.settings;

  try {
    const template = await getRemoteConfig().getServerTemplate({
      defaultConfig: defaultConfigMap(),
    });
    const config = template.evaluate();
    const values: ConfigValues = {};
    for (const key of Object.keys(defaultConfigMap())) {
      values[key] = config.getValue(key).asString();
    }
    const settings: RemoteSettings = {
      limits: parseLimits(values),
      flags: parseFlags(values),
      fromRemoteConfig: true,
    };
    cached = { at: now, settings };
    return settings;
  } catch (err) {
    // Logged at info, not error: an unconfigured project has no server template
    // and that is a perfectly normal state for a fresh environment.
    logger.info("Remote Config unavailable — using compiled limits", {
      err: String(err),
    });
    const settings: RemoteSettings = {
      limits: DEFAULT_LIMITS,
      flags: DEFAULT_FLAGS,
      fromRemoteConfig: false,
    };
    cached = { at: now, settings };
    return settings;
  }
}

/**
 * The defaults handed to the server template, so `getValue` always resolves
 * even for a parameter nobody has created in the console yet.
 */
export function defaultConfigMap(): Record<string, string> {
  const out: Record<string, string> = {};
  for (const feature of METERED_FEATURES) {
    out[paramName("free", feature)] = String(DEFAULT_LIMITS.free[feature]);
    out[paramName("freeDaily", feature)] = String(DEFAULT_LIMITS.freeDaily[feature]);
    out[paramName("proDaily", feature)] = String(DEFAULT_LIMITS.proDaily[feature]);
  }
  for (const [key, param] of Object.entries(FLAG_PARAM)) {
    out[param] = String(DEFAULT_FLAGS[key as keyof FeatureFlags]);
  }
  return out;
}
