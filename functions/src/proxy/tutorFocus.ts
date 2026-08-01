/**
 * The golden-rule gate for the equation Numi highlights while she explains
 * (spec Parts 7–8).
 *
 * Highlighting looks harmless — it only tints part of a line — but the LINE
 * itself is an assertion. If the model were allowed to send its own LaTeX, a
 * highlight card would become a second, unverified answer displayed in the
 * app's own voice, right under a verified one. So a focus may only ever point
 * at maths the app ALREADY has on screen and has already checked:
 *
 *   - the problem the student is working on,
 *   - the step they tapped, or
 *   - a VERIFIED step result — and only in a mode allowed to show results.
 *
 * The model's own LaTeX is never echoed back: a match returns the app's copy of
 * the string, so what renders is byte-for-byte what was verified. Highlighted
 * spans must be substrings of that copy, which means a highlight can only ever
 * point *within* verified maths — it can never add to it.
 *
 * Pure — no Firebase/OpenAI imports — so the gate is unit-testable in isolation.
 */

import { deriveTutorSketch, TutorSketchOut } from "./tutorSketch";

/** The six roles of the semantic colour system (spec Part 7). */
export const FOCUS_ROLES = [
  "answer",
  "known",
  "operation",
  "unknown",
  "mistake",
  "aside",
] as const;

export type FocusRole = (typeof FOCUS_ROLES)[number];

const ROLE_SET = new Set<string>(FOCUS_ROLES);

export interface FocusSpanOut {
  /** An exact substring of the focus LaTeX. */
  text: string;
  role: FocusRole;
}

export interface TutorFocusOut {
  /** The app's own copy of the equation — never the model's. */
  latex: string;
  /** One short line naming what is highlighted, in the student's language. */
  caption: string;
  spans: FocusSpanOut[];
  /**
   * An optional drawing of the same maths (spec Part 9). Every number in it is
   * derived from [latex] by the app — see `deriveTutorSketch`.
   */
  sketch?: TutorSketchOut;
}

export interface FocusVerdict {
  focus: TutorFocusOut | null;
  /** Why a focus was dropped — logged, never shown to the student. */
  reason: string;
}

const MAX_SPANS = 3;
const MAX_CAPTION = 140;
const MAX_LATEX = 300;

/** Non-whitespace characters of [s], with their indices in [s]. */
function compact(s: string): { text: string; index: number[] } {
  let text = "";
  const index: number[] = [];
  for (let i = 0; i < s.length; i++) {
    if (/\s/.test(s[i])) continue;
    text += s[i];
    index.push(i);
  }
  return { text, index };
}

/**
 * Whether `latex[start..end)` can be wrapped in `\textcolor{…}{…}` without
 * changing what the equation means. Mirrors `colorizeLatex` on the client — the
 * client re-checks too, but a span that could break rendering should never be
 * sent in the first place.
 */
export function isWrappableSpan(latex: string, start: number, end: number): boolean {
  const span = latex.slice(start, end);
  if (!span.trim()) return false;
  // Alignment markup only parses at the top level of an environment.
  if (span.includes("&") || span.includes("\\\\")) return false;
  // A trailing operator would be left with nothing to operate on; a leading
  // script with no base.
  if (/[\^_\\]$/.test(span)) return false;
  if (span.startsWith("^") || span.startsWith("_")) return false;

  let depth = 0;
  for (let i = 0; i < span.length; i++) {
    if (i > 0 && span[i - 1] === "\\") continue; // an escaped brace is a glyph
    if (span[i] === "{") depth++;
    if (span[i] === "}" && --depth < 0) return false;
  }
  if (depth !== 0) return false;

  // Neither edge may fall inside a `\command` name.
  for (const m of latex.matchAll(/\\[a-zA-Z]+/g)) {
    const from = m.index ?? 0;
    const to = from + m[0].length;
    if (from < start && start < to) return false;
    if (from < end && end < to) return false;
  }
  return true;
}

/**
 * Locate [needle] inside [latex], tolerating differences in whitespace, and
 * return the matching range in the ORIGINAL string.
 *
 * Whitespace is not meaningful in LaTeX, so a model that writes `8x` should
 * still find `8 x`. Returns the range so the caller can substitute the app's own
 * characters for the model's.
 */
export function findSpan(
  latex: string,
  needle: string,
  taken: Array<[number, number]>
): [number, number] | null {
  const hay = compact(latex);
  const pin = compact(needle);
  if (!pin.text) return null;

  let from = 0;
  for (;;) {
    const at = hay.text.indexOf(pin.text, from);
    if (at < 0) return null;
    const start = hay.index[at];
    const end = hay.index[at + pin.text.length - 1] + 1;
    const free = !taken.some(([s, e]) => start < e && s < end);
    if (free && isWrappableSpan(latex, start, end)) return [start, end];
    from = at + 1;
  }
}

/** Two LaTeX strings that differ only in whitespace are the same equation. */
function sameLatex(a: string, b: string): boolean {
  return compact(a).text === compact(b).text;
}

function str(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

/**
 * Verify a focus the model proposed against the maths the app is allowed to
 * show it pointing at.
 *
 * [allowed] is built by the caller from the CURRENT mode's context: the problem
 * and the tapped step always, verified step results only in modes that may
 * reveal them. That is what makes the answer firewall cover highlighting too —
 * in Hint mode a highlight of the answer line has nothing to match and is
 * dropped, exactly as the answer itself would be.
 *
 * A focus with no surviving span is dropped: an equation with nothing
 * highlighted teaches nothing the reply didn't already say.
 */
export function verifyTutorFocus(raw: unknown, allowed: string[]): FocusVerdict {
  if (!raw || typeof raw !== "object") return { focus: null, reason: "" };
  const focus = raw as {
    latex?: unknown;
    caption?: unknown;
    spans?: unknown;
    sketch?: unknown;
  };

  const claimed = str(focus.latex, MAX_LATEX);
  if (!claimed) return { focus: null, reason: "focus: missing latex" };

  // Take the APP's copy of the equation, not the model's.
  const verified = allowed
    .map((s) => (typeof s === "string" ? s.trim() : ""))
    .filter((s) => s.length > 0 && s.length <= MAX_LATEX)
    .find((s) => sameLatex(s, claimed));
  if (!verified) {
    return { focus: null, reason: "focus: latex is not verified maths on screen" };
  }

  const caption = str(focus.caption, MAX_CAPTION);
  if (!caption) return { focus: null, reason: "focus: missing caption" };

  const rawSpans = Array.isArray(focus.spans) ? focus.spans : [];
  const whole = compact(verified).text;
  const taken: Array<[number, number]> = [];
  const spans: FocusSpanOut[] = [];

  for (const item of rawSpans) {
    if (spans.length >= MAX_SPANS) break;
    if (!item || typeof item !== "object") continue;
    const span = item as { text?: unknown; role?: unknown };
    const text = str(span.text, 80);
    if (!text) continue;
    const role = str(span.role, 20).toLowerCase();
    if (!ROLE_SET.has(role)) continue;
    // Lighting up the entire line is the same as lighting up none of it.
    if (compact(text).text.length >= whole.length) continue;

    const at = findSpan(verified, text, taken);
    if (!at) continue;
    taken.push(at);
    spans.push({ text: verified.slice(at[0], at[1]), role: role as FocusRole });
  }

  if (spans.length === 0) {
    return { focus: null, reason: "focus: no span matched the verified equation" };
  }

  // The drawing is derived from the app's copy of the equation, so it can only
  // ever picture maths that already passed the gate above.
  const sketch = deriveTutorSketch(verified, focus.sketch);

  return {
    focus: { latex: verified, caption, spans, ...(sketch ? { sketch } : {}) },
    reason: "",
  };
}
