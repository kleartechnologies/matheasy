/**
 * Teaching actions — Numi pointing at the student's page.
 *
 * A reply may carry a short list of actions ("highlight `angle_B`", "pulse the
 * equation"), which the client paints as an overlay on the original photo. This
 * module is the gate between what the model asked for and what is allowed to be
 * drawn.
 *
 * The rule is the same one that governs cards and focus equations, applied to
 * geometry-on-a-photo: **the model may only point at things the app already
 * located itself.** A target must be the id of a semantic anchor derived
 * deterministically from the scan (`anchors.ts`); anything else is dropped, not
 * repaired. That single check is what makes an overlay trustworthy — an outline
 * drawn at model-invented coordinates would point confidently at the wrong part
 * of the student's own homework, which is worse than never pointing at all.
 *
 * Actions carry no arithmetic and no answer, so they are permitted in every
 * teaching mode, including the ones the verified answer is withheld from: "look
 * at this angle" is a direction of attention, not a result.
 */
import { ANCHOR_ROLES, type AnchorRole, type SemanticAnchor } from "./anchors";

/** Every gesture the renderer knows how to draw. */
export const ACTION_TYPES = [
  "highlight",
  "circle",
  "underline",
  "glow",
  "pulse",
  "zoom",
  "fade",
  "drawArrow",
  "drawBracket",
  "flash",
  "focusRegion",
] as const;

export type ActionType = (typeof ACTION_TYPES)[number];

/** A verified action, safe to draw. */
export interface TutorActionOut {
  type: ActionType;
  /** The id of a semantic anchor on this page. */
  target: string;
  /** The teaching colour, defaulted from the anchor's own semantic role. */
  role: AnchorRole;
}

export interface TutorActionsVerdict {
  actions: TutorActionOut[];
  /** Why anything was dropped — logged, never shown to the student. */
  reason: string | null;
}

const ACTION_TYPE_SET = new Set<string>(ACTION_TYPES);
const ROLE_SET = new Set<string>(ANCHOR_ROLES);

/**
 * How many gestures one turn may carry.
 *
 * Small on purpose. A tutor's hand points at one thing, occasionally two; an
 * overlay that lights up six regions at once is a Christmas tree, and the
 * student learns nothing about where to look. The cap is a teaching decision as
 * much as a performance one.
 */
const MAX_ACTIONS = 3;

/**
 * Keep only the actions that point at something real.
 *
 * @param raw the model's `actions` field, untrusted
 * @param anchors the semantic anchors for the page on screen
 */
export function verifyTutorActions(
  raw: unknown,
  anchors: SemanticAnchor[]
): TutorActionsVerdict {
  if (raw === undefined || raw === null) return { actions: [], reason: null };
  if (!Array.isArray(raw)) return { actions: [], reason: "actions was not a list" };
  if (anchors.length === 0) {
    return { actions: [], reason: "no anchors on this page to point at" };
  }

  const byId = new Map(anchors.map((a) => [a.id, a]));
  const out: TutorActionOut[] = [];
  const seen = new Set<string>();
  const dropped: string[] = [];

  for (const item of raw) {
    if (out.length >= MAX_ACTIONS) break;
    if (!item || typeof item !== "object") {
      dropped.push("non-object");
      continue;
    }
    const action = item as { type?: unknown; target?: unknown; role?: unknown };
    const type = typeof action.type === "string" ? action.type.trim() : "";
    const target = typeof action.target === "string" ? action.target.trim() : "";

    if (!ACTION_TYPE_SET.has(type)) {
      dropped.push(`unknown type "${type}"`);
      continue;
    }
    const anchor = byId.get(target);
    if (!anchor) {
      // The most important rejection in this file: an id nobody located.
      dropped.push(`unknown target "${target}"`);
      continue;
    }
    const key = `${type}:${target}`;
    if (seen.has(key)) continue;
    seen.add(key);

    const role = typeof action.role === "string" ? action.role.trim() : "";
    out.push({
      type: type as ActionType,
      target,
      // The anchor's own role is the default, so the page overlay and the
      // equation highlighting agree on what colour a "known value" is without
      // the model having to remember the vocabulary.
      role: ROLE_SET.has(role) ? (role as AnchorRole) : anchor.role,
    });
  }

  return {
    actions: out,
    reason: dropped.length > 0 ? `dropped ${dropped.length}: ${dropped.join(", ")}` : null,
  };
}
