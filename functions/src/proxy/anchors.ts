/**
 * Semantic anchors — the layer that lets Numi say "this angle" instead of "28".
 *
 * Pass 1 (`ocr.ts`) reports WHAT is written and WHERE. That is not yet enough to
 * teach with: "28°" in a box is a reading, whereas "the angle at vertex B, which
 * is one of the two you were given" is a thing a tutor can point at. This module
 * closes that gap.
 *
 * It is deliberately DETERMINISTIC and model-free. Every semantic claim made
 * here is derived from two things the app already trusts — the OCR anchors and
 * the structured `geometry` facts the scanner extracted — by plain rules that
 * can be unit-tested. Nothing is asked of a model, so nothing here can invent a
 * relationship that isn't on the page, and the golden rule is untouched: an
 * anchor says where a mark is and what role it plays, never what it evaluates
 * to.
 *
 * The output is a stable, referenceable id per concept (`angle_B`, `side_c`,
 * `unknown_x`). Numi's teaching actions target those ids and are rejected if
 * they name anything else — see `tutorActions.ts`.
 */
import { coerceBox, type AnchorBox, type OcrAnchor } from "./ocr";

/** What a mark MEANS, once the raw read has been cross-checked against context. */
export const SEMANTIC_TYPES = [
  "angle",
  "side",
  "hypotenuse",
  "radius",
  "diameter",
  "vertex",
  "unknown",
  "known",
  "equation",
  "expression",
  "fraction",
  "root",
  "integral",
  "derivative",
  "limit",
  "matrix",
  "point",
  "axis",
  "intercept",
  "figure",
  "label",
] as const;

export type SemanticType = (typeof SEMANTIC_TYPES)[number];

/**
 * The teaching colour a concept wears. Mirrors the client's `MathRole`
 * vocabulary exactly — the same meaning has to wear the same colour on the page
 * overlay as it does inside an equation, or the student has to learn it twice.
 */
export const ANCHOR_ROLES = [
  "answer",
  "known",
  "operation",
  "unknown",
  "mistake",
  "hint",
  "concept",
  "memory",
  "aside",
] as const;

export type AnchorRole = (typeof ANCHOR_ROLES)[number];

/** A concept on the page, addressable by id. */
export interface SemanticAnchor {
  /** Stable and human-readable, e.g. `angle_B`. Unique within one scan. */
  id: string;
  type: SemanticType;
  /** The mark as written — "28°", "x", "AB". */
  label: string;
  /** The vertex an angle sits at, when one could be determined. */
  vertex?: string;
  role: AnchorRole;
  box: AnchorBox;
  confidence: number;
}

/**
 * The structured geometry facts, as the scanner returned them. Untyped on the
 * wire (the client validates and computes); read here only to NAME things.
 */
interface GeometryFacts {
  kind?: unknown;
  unknown?: unknown;
  knownAngles?: unknown;
  sides?: unknown;
  knownAngle?: unknown;
  includedAngle?: unknown;
}

/** How many concepts to carry. A tutor points at a handful, never at forty. */
const MAX_SEMANTIC_ANCHORS = 24;

/** Matches an angle measure: `28`, `28°`, `28.5^\circ`, `x°`. */
const ANGLE_TEXT = /^([a-z]|\d+(?:\.\d+)?)\s*(?:°|\^?\\?circ|deg)?$/i;

/** A vertex letter: a single capital, optionally primed. */
const VERTEX_TEXT = /^[A-Z]'?$/;

/**
 * Derive the semantic anchors for a scanned page.
 *
 * @param anchors the raw marks from pass 1
 * @param geometry the scanner's structured facts, or null
 */
export function deriveSemanticAnchors(
  anchors: OcrAnchor[],
  geometry: unknown | null
): SemanticAnchor[] {
  if (!Array.isArray(anchors) || anchors.length === 0) return [];

  const facts = (geometry && typeof geometry === "object" ? geometry : {}) as GeometryFacts;
  const unknownName = typeof facts.unknown === "string" ? facts.unknown.trim() : "";
  const sideRoles = sideRoleMap(facts.sides);
  const knownValues = knownAngleValues(facts);
  const vertices = anchors.filter((a) => a.type === "vertex" || VERTEX_TEXT.test(a.text));

  const used = new Set<string>();
  const out: SemanticAnchor[] = [];

  for (const anchor of anchors) {
    const semantic = classify(anchor, {
      unknownName,
      sideRoles,
      knownValues,
      vertices,
    });
    if (!semantic) continue;
    semantic.id = uniqueId(semantic.id, used);
    out.push(semantic);
    if (out.length >= MAX_SEMANTIC_ANCHORS) break;
  }
  return out;
}

interface ClassifyContext {
  unknownName: string;
  sideRoles: Map<string, string>;
  knownValues: Set<string>;
  vertices: OcrAnchor[];
}

/**
 * One mark → one concept, or null when the mark carries nothing a tutor would
 * point at (a stray operator, an unreadable smudge).
 */
function classify(anchor: OcrAnchor, ctx: ClassifyContext): SemanticAnchor | null {
  const label = anchor.text;
  const bare = stripDegrees(label);
  const base = { label, box: anchor.box, confidence: anchor.confidence };

  // The single unknown the problem asks for, named by the geometry facts. This
  // is checked FIRST: "x" is the target of the whole problem, and calling it a
  // plain variable would lose the one relationship that matters most.
  if (ctx.unknownName && bare === ctx.unknownName) {
    return {
      ...base,
      id: `unknown_${slug(bare)}`,
      type: "unknown",
      role: "unknown",
      ...(isAngleish(anchor) ? { vertex: bare } : {}),
    };
  }

  switch (anchor.type) {
    case "angle": {
      const vertex = nearestVertex(anchor, ctx.vertices);
      return {
        ...base,
        id: `angle_${slug(vertex ?? bare)}`,
        type: "angle",
        role: ctx.knownValues.has(bare) ? "known" : "concept",
        ...(vertex ? { vertex } : {}),
      };
    }
    case "vertex":
      return { ...base, id: `vertex_${slug(bare)}`, type: "vertex", role: "aside" };
    case "length": {
      const role = ctx.sideRoles.get(bare);
      const type: SemanticType =
        role === "hypotenuse" ? "hypotenuse" : role ? "side" : "side";
      return {
        ...base,
        id: `${type === "hypotenuse" ? "hypotenuse" : "side"}_${slug(bare)}`,
        type,
        role: "known",
      };
    }
    case "equation":
      return { ...base, id: "equation", type: "equation", role: "operation" };
    case "fraction":
      return { ...base, id: `fraction_${slug(bare)}`, type: "fraction", role: "concept" };
    case "root":
      return { ...base, id: `root_${slug(bare)}`, type: "root", role: "concept" };
    case "integral":
      return { ...base, id: "integral", type: "integral", role: "operation" };
    case "derivative":
      return { ...base, id: "derivative", type: "derivative", role: "operation" };
    case "matrix":
      return { ...base, id: `matrix_${slug(bare)}`, type: "matrix", role: "concept" };
    case "point":
      return { ...base, id: `point_${slug(bare)}`, type: "point", role: "known" };
    case "axis":
      return { ...base, id: `axis_${slug(bare)}`, type: "axis", role: "aside" };
    case "figure":
      return { ...base, id: "figure", type: "figure", role: "concept" };
    case "number":
      return {
        ...base,
        id: `known_${slug(bare)}`,
        type: "known",
        role: "known",
      };
    case "variable":
      return {
        ...base,
        id: `variable_${slug(bare)}`,
        // A lone variable that ISN'T the asked-for unknown is still a symbol the
        // student has to track — but it is not the target, so it must not wear
        // the target's colour.
        type: "expression",
        role: "concept",
      };
    case "label":
      return { ...base, id: `label_${slug(bare)}`, type: "label", role: "aside" };
    // An operator on its own ("+", "=") is not a concept; a tutor points at the
    // things it joins. Dropped rather than anchored.
    case "operator":
    case "other":
      return null;
  }
}

/** `28°` → `28`, `x°` → `x`. Degrees are notation, not identity. */
function stripDegrees(text: string): string {
  const match = ANGLE_TEXT.exec(text.trim());
  return match ? match[1] : text.trim();
}

function isAngleish(anchor: OcrAnchor): boolean {
  return anchor.type === "angle";
}

/**
 * The vertex letter an angle belongs to: the nearest vertex anchor by centre
 * distance, if one is close enough to plausibly be labelling it.
 *
 * "Close enough" is a fraction of the frame rather than a pixel count, and
 * deliberately tight: an angle mis-attributed to a far-away letter would have
 * Numi point at the wrong corner with total confidence. Better to leave the
 * angle unnamed and let her say "this angle" than to name it wrong.
 */
export function nearestVertex(angle: OcrAnchor, vertices: OcrAnchor[]): string | null {
  const NEAR = 0.22;
  let best: { letter: string; distance: number } | null = null;
  for (const v of vertices) {
    const letter = v.text.trim();
    if (!VERTEX_TEXT.test(letter)) continue;
    const distance = centreDistance(angle.box, v.box);
    if (distance > NEAR) continue;
    if (!best || distance < best.distance) best = { letter, distance };
  }
  return best?.letter ?? null;
}

function centreDistance(a: AnchorBox, b: AnchorBox): number {
  const dx = a.x + a.w / 2 - (b.x + b.w / 2);
  const dy = a.y + a.h / 2 - (b.y + b.h / 2);
  return Math.sqrt(dx * dx + dy * dy);
}

/** side label → its role ("hypotenuse", "leg", "opposite", "adjacent"). */
function sideRoleMap(sides: unknown): Map<string, string> {
  const map = new Map<string, string>();
  if (!Array.isArray(sides)) return map;
  for (const side of sides) {
    if (!side || typeof side !== "object") continue;
    const s = side as { label?: unknown; role?: unknown; value?: unknown };
    const label = typeof s.label === "string" ? s.label.trim() : "";
    const role = typeof s.role === "string" ? s.role.trim() : "";
    if (label && role) map.set(label, role);
    // A side is also findable by the number printed along it.
    if (typeof s.value === "number" && Number.isFinite(s.value) && role) {
      map.set(String(s.value), role);
    }
  }
  return map;
}

/** Every angle value the problem GAVE, as text — used to colour givens blue. */
function knownAngleValues(facts: GeometryFacts): Set<string> {
  const out = new Set<string>();
  const add = (value: unknown) => {
    if (typeof value === "number" && Number.isFinite(value)) out.add(String(value));
  };
  const addAngle = (angle: unknown) => {
    if (angle && typeof angle === "object") {
      add((angle as { value?: unknown }).value);
    }
  };
  if (Array.isArray(facts.knownAngles)) facts.knownAngles.forEach(addAngle);
  addAngle(facts.knownAngle);
  addAngle(facts.includedAngle);
  return out;
}

/** `A` → `A`; `\theta` → `theta`; keeps ids readable AND safe to compare. */
function slug(text: string): string {
  const cleaned = text
    .replace(/\\/g, "")
    .replace(/[^A-Za-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return cleaned || "1";
}

/** `angle_B`, then `angle_B_2` — two marks may legitimately read the same. */
function uniqueId(id: string, used: Set<string>): string {
  if (!used.has(id)) {
    used.add(id);
    return id;
  }
  for (let n = 2; ; n++) {
    const candidate = `${id}_${n}`;
    if (!used.has(candidate)) {
      used.add(candidate);
      return candidate;
    }
  }
}

const SEMANTIC_TYPE_SET = new Set<string>(SEMANTIC_TYPES);
const ROLE_SET = new Set<string>(ANCHOR_ROLES);

/**
 * Coerce anchors that came back FROM a client.
 *
 * They were derived here at scan time, but they made a round trip through a
 * device and are untrusted on the way back in — the same posture as every other
 * request field. Note what this does NOT do: it never re-derives or repairs
 * meaning. An anchor whose id or box is unusable is dropped, and Numi simply has
 * one fewer place to point.
 */
export function coerceSemanticAnchors(value: unknown): SemanticAnchor[] {
  if (!Array.isArray(value)) return [];
  const out: SemanticAnchor[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    if (!item || typeof item !== "object") continue;
    const raw = item as Record<string, unknown>;
    const id = typeof raw.id === "string" ? raw.id.trim().slice(0, 48) : "";
    if (!id || seen.has(id)) continue;
    const box = coerceBox(raw.box);
    if (!box) continue;
    const type = typeof raw.type === "string" ? raw.type : "";
    const role = typeof raw.role === "string" ? raw.role : "";
    const vertex = typeof raw.vertex === "string" ? raw.vertex.trim().slice(0, 8) : "";
    seen.add(id);
    out.push({
      id,
      type: SEMANTIC_TYPE_SET.has(type) ? (type as SemanticType) : "label",
      label: typeof raw.label === "string" ? raw.label.trim().slice(0, 60) : id,
      ...(vertex ? { vertex } : {}),
      role: ROLE_SET.has(role) ? (role as AnchorRole) : "aside",
      box,
      confidence:
        typeof raw.confidence === "number" && Number.isFinite(raw.confidence)
          ? Math.min(1, Math.max(0, raw.confidence))
          : 0.5,
    });
    if (out.length >= MAX_SEMANTIC_ANCHORS) break;
  }
  return out;
}

/**
 * Render the anchors as the context block Numi receives.
 *
 * The framing matters: this is a MAP of the page, and the instruction attached
 * to it is to point rather than to recite. A model handed a list of values will
 * quote the values ("the 28 in your problem"); a model handed a list of places
 * it can highlight will say "this angle, here" and let the app do the pointing —
 * which is the entire difference between a chatbot and a tutor beside you.
 */
export function anchorContextBlock(anchors: SemanticAnchor[]): string {
  if (anchors.length === 0) return "";
  const lines = [
    "THE PAGE ITSELF — these are the parts of the student's own photo you can point at.",
    "Each line is: id | what it is | what it says. Use the id as the \"target\" of an action to make the app highlight that exact spot on their page.",
  ];
  for (const a of anchors) {
    const where = a.vertex ? ` at vertex ${a.vertex}` : "";
    lines.push(`  ${a.id} | ${a.type}${where} | "${a.label}"`);
  }
  lines.push(
    "When you talk about one of these, POINT at it and describe it by position or role (\"this angle\", \"the highlighted side\", \"the one at the top right\") rather than reading its value out loud. The student is looking at the same page you are."
  );
  return lines.join("\n");
}
