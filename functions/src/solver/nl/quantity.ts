/**
 * Reusable natural-language QUANTITY reading for the deterministic solver engines.
 *
 * The single hardest problem in word-problem parsing is: given a named quantity
 * ("radius", "central angle", "principal") and a sentence full of numbers, WHICH
 * number is its value? A naive "first number after the keyword" grabs distractors —
 * "the diameter of a table seating 4 people is 120 cm" ships 4, "the central angle
 * after 2 seconds is 120 degrees" ships 2. The fix is to bind a value only when it
 * is ANCHORED to the quantity, and to reject numbers anchored to a DIFFERENT noun.
 *
 * Two composable anchors are provided:
 *   - readBoundValue()        — adjacency / predication / symbol anchoring.
 *   - readUnitAnchoredValues() — the strongest anchor: a number glued to the
 *                                quantity's own UNIT ("120 degrees", "5 kg"),
 *                                minus recognised distractor contexts.
 * Engines compose these; the domain-specific precedence (e.g. "a degree-marked
 * angle outranks a bare number sitting nearer the phrase") lives in the engine.
 *
 * Golden-rule stance: every helper DECLINES (returns null / omits the value) when
 * no anchored reading exists, rather than borrowing an unrelated number.
 */
import { NUMERIC_TOKEN, parseNumericToken } from "./numeric";

/** Short linking words a value may sit behind and still count as "adjacent" to its
 * quantity name — no distractor NUMBER can hide inside a whitelisted connector, so
 * "radius 7", "radius of 7", "radius = 7 cm", "radius measures 7" all read cleanly. */
const CONNECTOR = String.raw`(?:of|is|are|was|equals?|equal\s+to|measures?|measuring|about|approximately|nearly|around|roughly)`;

export interface BoundValue {
  value: number;
  /** The raw unit token captured immediately after the value, or null. */
  unitRaw: string | null;
}

/**
 * Read the numeric value BOUND to a named quantity, or null. Three anchor tiers,
 * strongest first — the first that matches wins:
 *   A) ADJACENCY   — the value sits on the name through whitelisted connectors only
 *                    ("radius of 7 cm"); a distractor number cannot hide in a
 *                    connector, so a far-off number is never grabbed.
 *   B) PREDICATION — the value is asserted of the name by is/=/measures LATER in the
 *                    same clause; the span may cross a narrative number but STOPS at a
 *                    comma / semicolon / period, so "table seating 4 people is 120 cm"
 *                    → 120, while a value walled off by a comma-parenthetical stays
 *                    ambiguous → no match → the caller declines.
 *   C) SYMBOL      — the bare "r = 7" / "d = 10" form (opts.symbol).
 *
 * `opts.unitSrc` (a units regex SOURCE) captures a trailing unit for display.
 * `opts.rejectTrailer` (a units regex SOURCE) DISQUALIFIES a candidate value that is
 * glued to a foreign unit — "central angle 2 seconds later …" must not bind 2 as the
 * angle; the tier backtracks and the next anchor (or none) is tried instead.
 */
export function readBoundValue(
  text: string,
  name: string,
  opts: { symbol?: string; unitSrc?: string; rejectTrailer?: string } = {}
): BoundValue | null {
  const V = NUMERIC_TOKEN;
  const U = opts.unitSrc ? String.raw`(?:\s*(${opts.unitSrc})(?![a-z]))?` : "";
  // A negative lookahead placed right after the value group: if the number is
  // immediately followed by a foreign unit, this tier fails to match here.
  const R = opts.rejectTrailer ? String.raw`(?!\s*(?:${opts.rejectTrailer})\b)` : "";
  const tierA = new RegExp(
    String.raw`\b${name}\b(?:\s+${CONNECTOR})*\s*[=:]?\s*(${V})${R}${U}`,
    "i"
  );
  // A predication verb introduced by a relative pronoun — "… a circular pond THAT measures
  // 3 m deep IS 10 m" — predicates the RELATIVE-CLAUSE noun (the pond), NOT our quantity;
  // binding its value ships the distractor (3, not the main-clause 10). Skip any
  // "that/which <verb>" so the lazy gap advances to the MAIN-clause predication ("… is 10 m"
  // → 10). This relative-clause firewall generalises to every engine that reads a bound value.
  const tierB = new RegExp(
    String.raw`\b${name}\b[^.;,]*?(?<!\b(?:that|which)\s+)\b(?:is|are|was|equals?|measures?|measuring|equal\s+to)\b\s*[=:]?\s*(${V})${R}${U}`,
    "i"
  );
  const tierC = opts.symbol
    ? new RegExp(String.raw`\b${opts.symbol}\s*=\s*(${V})${R}${U}`, "i")
    : null;

  const m = text.match(tierA) ?? text.match(tierB) ?? (tierC ? text.match(tierC) : null);
  if (!m) return null;
  const value = parseNumericToken(m[1]);
  if (value === null || !Number.isFinite(value)) return null;
  return { value, unitRaw: (opts.unitSrc ? (m[2] ?? null) : null) };
}

export interface UnitAnchoredOpts {
  /** The quantity's unit, as a regex SOURCE that must immediately follow the number
   * ("°|degrees?|deg\\b", "kg|g|grams?"). */
  unitSrc: string;
  /** Numeric-token source to match (defaults to the standard literal). */
  valueSrc?: string;
  /** A trailer that DISQUALIFIES a unit match — a compass point after "degrees" or a
   * temperature scale ("degrees north", "degrees C") means it is not this quantity. */
  disqualifyTrailer?: string;
  /** A context in the lookback window BEFORE the number that marks it a distractor
   * ("bearing of 60°", "latitude 35°"). */
  distractorCtx?: RegExp;
  /** Lookback window for distractorCtx, in characters (default 30). */
  lookback?: number;
}

/**
 * Every number immediately followed by the quantity's UNIT, minus distractor-context
 * and disqualified-trailer matches. This is the strongest anchor — a value glued to
 * its own unit almost certainly belongs to that quantity. Returns the list (the
 * caller decides: exactly one ⇒ use it, two or more ⇒ ambiguous ⇒ decline).
 */
export function readUnitAnchoredValues(text: string, opts: UnitAnchoredOpts): number[] {
  const V = opts.valueSrc ?? NUMERIC_TOKEN;
  const trailer = opts.disqualifyTrailer ? `(${opts.disqualifyTrailer})?` : "";
  const re = new RegExp(String.raw`(${V})\s*\^?\s*(?:${opts.unitSrc})${trailer}`, "gi");
  const out: number[] = [];
  const lb = opts.lookback ?? 30;
  for (const m of text.matchAll(re)) {
    const idx = m.index ?? 0;
    if (opts.distractorCtx && opts.distractorCtx.test(text.slice(Math.max(0, idx - lb), idx))) {
      continue;
    }
    if (opts.disqualifyTrailer && m[2]) continue; // compass / thermal trailer
    const v = parseNumericToken(m[1]);
    if (v !== null && Number.isFinite(v) && v > 0) out.push(v);
  }
  return out;
}
