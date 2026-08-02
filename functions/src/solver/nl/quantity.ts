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

/**
 * Units that no LENGTH ever carries. A symbol is a letter, and a letter is reused across
 * the sciences: "a circular loop of wire has RESISTANCE R = 4 OHMS" bound 4 as the radius
 * and shipped 16π as a verified area for a problem with no radius at all. The unit is what
 * settles it — a quantity glued to a foreign unit is a foreign quantity, whatever letter
 * names it. Pass as `rejectTrailer` wherever a length is read; the mirror of NON_ANGLE_UNIT.
 */
export const NON_LENGTH_UNIT = String.raw`ohms?|Ω|volts?|amps?|amperes?|watts?|joules?|newtons?|pascals?|bars?|hertz|hz|kg|kilograms?|grams?|g|mg|tonnes?|tons?|lbs?|pounds?|ounces?|oz|litres?|liters?|ml|gallons?|seconds?|secs?|s|minutes?|mins?|hours?|hrs?|days?|weeks?|years?|°|degrees?|celsius|fahrenheit|kelvin|rpm|percent|%|moles?|coulombs?|farads?|teslas?|lumens?|lux|decibels?|db|calories?|cal|kj|kw|mph|kph|km\/h|m\/s`;

/** Short linking words a value may sit behind and still count as "adjacent" to its
 * quantity name — no distractor NUMBER can hide inside a whitelisted connector, so
 * "radius 7", "radius of 7", "radius = 7 cm", "radius measures 7" all read cleanly. */
const CONNECTOR = String.raw`(?:of|is|are|was|equals?|equal\s+to|measures?|measuring|about|approximately|nearly|around|roughly)`;

/** Which anchor bound the value — strongest first. Callers use this to arbitrate
 * against their OWN domain idioms: an engine that reads "6 cm across" as a diameter must
 * beat a bare "d = 2 mm" (a thickness) but must NOT silently beat a named "diameter 4 cm"
 * (a second circle) — the two need different outcomes, so the tier has to be visible. */
export type BoundTier =
  | "attributive"
  | "label"
  | "postpositive"
  | "adjacency"
  | "predication"
  | "symbol";

export interface BoundValue {
  value: number;
  /** The raw unit token captured immediately after the value, or null. */
  unitRaw: string | null;
  /** Which tier matched (see BoundTier). */
  tier: BoundTier;
  /** Character offset of the reading in the source text, so a caller can ask WHICH CLAUSE
   * it came from — the only way to tell a value predicated of the asked figure from one
   * predicated of some other noun in a neighbouring sentence. */
  index: number;
}

/** Words that open a SUBORDINATE clause whose predication belongs to that clause's own
 * subject, not to our quantity: a relative pronoun ("the pond THAT measures 3 m deep is
 * 10 m") or a subordinating conjunction ("the radius WHEN the water level IS 2 m deep is
 * 14 m", "a circle drawn WHILE the pen width is 1 mm", "a table WHERE each setting is 40
 * cm wide"). Binding the subordinate clause's value ships the distractor, so tier B skips
 * past it to the MAIN-clause predication. One shared list — every engine reads prose. */
const SUBORDINATOR =
  String.raw`that|which|who|whom|whose|when|whenever|while|whilst|where|wherever|if|unless|until|after|before|once|since|although|though`;

/**
 * Is the reading at `index` inside a SUBORDINATE clause?
 *
 * The same firewall tier B applies inline, exposed for callers that need it on text they
 * match themselves. A detail asserted in a relative or subordinating clause describes some
 * OTHER noun ("a circular tank THAT MEASURES 3 M TALL is 10 m" measures nothing about the
 * tank's circle), so a guard keyed on the bare presence of a word fires on scenery. Every
 * engine that reads prose needs this, which is why it lives here and not in one of them.
 */
export function isSubordinate(text: string, index: number): boolean {
  const start = Math.max(
    0,
    ...[";", ",", ".", "?", "!"].map((p) => text.lastIndexOf(p, index) + 1)
  );
  // A subordinator governs the words that FOLLOW IT UNTIL THE MAIN VERB RESUMES, not the
  // whole rest of the sentence. Scanning back to the last punctuation mark made "a circular
  // tray WHOSE diameter is 20 cm HOLDS a circular plate 6 CM ACROSS" look subordinate at the
  // plate — the reading was dropped and the tray's 20 cm sized the plate (100π for a true
  // 9π). Six words is the practical reach of a relative clause; past that the main clause has
  // resumed. Bounded lookback, not clause-to-punctuation.
  const WINDOW = 6;
  const words = text.slice(start, index).trim().split(/\s+/);
  const near = words.slice(Math.max(0, words.length - WINDOW)).join(" ");
  return new RegExp(String.raw`\b(?:${SUBORDINATOR})\b`, "i").test(near);
}

/** Every occurrence of `re` in `text` that is NOT inside a subordinate clause. */
export function mainClauseMatches(text: string, re: RegExp): RegExpMatchArray[] {
  const g = new RegExp(re.source, re.flags.includes("g") ? re.flags : `${re.flags}g`);
  return [...text.matchAll(g)].filter((m) => !isSubordinate(text, m.index ?? 0));
}

/**
 * Read the numeric value BOUND to a named quantity, or null. Four anchor tiers,
 * strongest first — the first that matches wins:
 *   A0) POSTPOSITIVE — the value precedes the name through "in" ("7 cm in radius"), an
 *                    explicit anchor that beats any later distractor in the same sentence.
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
  // A00) ATTRIBUTIVE — the value modifies the name DIRECTLY, with no preposition at all:
  // "a 14 CM DIAMETER circle", "a 5 CM RADIUS disc". English forms compound modifiers this
  // way constantly, and it was the one anchor with no tier: "A 14 cm diameter circle sits on
  // a round table WHOSE DIAMETER IS 90 cm" skipped the attributive 14 entirely and predicated
  // the TABLE's 90 onto the circle. Strongest tier — an adjacent premodifier cannot belong to
  // any other noun.
  // The tier yields to an explicit PREDICATION of a VALUE ("a 6 cm radius is 7 cm" — whatever
  // that means, the predication is the stronger claim) and to a following "of". It must NOT
  // yield to a copula generally: "A circle with a 6 CM RADIUS IS DRAWN on a card 40 cm wide"
  // states the radius attributively and then says what was done with the circle, and blocking
  // on the bare "is" threw the only real given away — the engine then had no dimension at all
  // and declined a perfectly determinate problem (and, before the span filter, sized the card).
  const tierA00 = new RegExp(
    String.raw`(${V})${R}${U}\s+\b${name}\b(?!\s+(?:is|are|was)\s*[=:]?\s*(?:${V})|\s+of\b)`,
    "i"
  );
  // A0) POSTPOSITIVE — the value precedes the name through "in" ("7 cm IN RADIUS",
  // "120 cm in diameter"). This is an explicit anchor, so it outranks the forward tiers:
  // without it "a disc is 7 cm in radius AND the table … is 100 cm wide" fell through to
  // tier B, which walked past the coordinating "and" and bound the DISTRACTOR (100).
  const tierA0 = new RegExp(
    String.raw`(${V})${R}${U}\s+in\s+\b${name}\b`,
    "i"
  );
  // A GEOMETRIC POINT LABEL sits between the quantity and its value in the commonest
  // textbook-diagram phrasing there is: "radius OA = 7 cm", "diameter AB = 20 cm". No tier
  // allowed anything between the name and the connector, so nothing was read and a figure
  // caption's number got picked up instead. The label is only admitted when an EQUALS SIGN
  // follows it — that is what proves the token is a label and not a stray word.
  const tierLabel = new RegExp(
    String.raw`\b${name}\s+[a-z]{1,4}\s*[=:]\s*(${V})${R}${U}`,
    "i"
  );
  const tierA = new RegExp(
    String.raw`\b${name}\b(?:\s+${CONNECTOR})*\s*[=:]?\s*(${V})${R}${U}`,
    "i"
  );
  // A predication verb introduced by a SUBORDINATOR — "… a circular pond THAT measures
  // 3 m deep IS 10 m", "… the radius WHEN the water level IS 2 m deep is 14 m" — predicates
  // the SUBORDINATE clause's own subject (the pond, the water level), NOT our quantity;
  // binding its value ships the distractor (3 / 2, not the main-clause 10 / 14). Skip any
  // "<subordinator> <short noun phrase> <verb>" so the lazy gap advances to the MAIN-clause
  // predication. The pronoun may be a possessive with its own noun head ("a pizza WHOSE
  // CRUST IS 2 cm wide is 15 cm"), hence the 0–3-word gap. This subordinate-clause firewall
  // generalises to every engine that reads a bound value out of prose.
  const tierB = new RegExp(
    String.raw`\b${name}\b[^.;,]*?(?<!\b(?:${SUBORDINATOR})\s+(?:\w+\s+){0,3})\b(?:is|are|was|equals?|measures?|measuring|equal\s+to)\b\s*[=:]?\s*(${V})${R}${U}`,
    "i"
  );
  const tierC = opts.symbol
    ? new RegExp(String.raw`\b${opts.symbol}\s*=\s*(${V})${R}${U}`, "i")
    : null;

  const tiers: Array<[BoundTier, RegExp | null]> = [
    ["attributive", tierA00],
    ["postpositive", tierA0],
    ["label", tierLabel],
    ["adjacency", tierA],
    ["predication", tierB],
    ["symbol", tierC],
  ];
  for (const [tier, re] of tiers) {
    const m = re ? text.match(re) : null;
    if (!m) continue;
    const value = parseNumericToken(m[1]);
    if (value === null || !Number.isFinite(value)) return null;
    return { value, unitRaw: opts.unitSrc ? (m[2] ?? null) : null, tier, index: m.index ?? 0 };
  }
  return null;
}

/**
 * EVERY anchored reading of a named quantity, across all four tiers, in text order.
 *
 * `readBoundValue` answers "what is the radius?" — it returns the single best-anchored
 * value and is silent about competition. But a sentence can name the SAME quantity for
 * TWO DIFFERENT OBJECTS ("a coin 2 cm IN DIAMETER lies on a plate whose DIAMETER IS 30
 * cm"), and there the best anchor is simply the wrong object's: the engine shipped π cm²
 * for a true 225π. The single-value reader cannot see that, because the competition is
 * exactly what it discards.
 *
 * So expose the whole set and let the caller arbitrate. The safe arbitration — used by
 * every engine — is: when the quantity NAME occurs more than once AND the readings
 * disagree, two objects are in play, nothing in the text says which one is asked, and the
 * honest outcome is to DECLINE. (A single name occurrence read at two tiers is the same
 * mention seen twice — "a disc IS 7 cm IN RADIUS and the table … is 100 cm wide" — and
 * must NOT be treated as a conflict, which is why the caller checks the occurrence count
 * rather than the reading count.)
 */
export function readBoundValues(
  text: string,
  name: string,
  opts: { symbol?: string; unitSrc?: string; rejectTrailer?: string } = {}
): BoundValue[] {
  const V = NUMERIC_TOKEN;
  const U = opts.unitSrc ? String.raw`(?:\s*(${opts.unitSrc})(?![a-z]))?` : "";
  const R = opts.rejectTrailer ? String.raw`(?!\s*(?:${opts.rejectTrailer})\b)` : "";
  const sources: Array<[BoundTier, string]> = [
    [
      "attributive",
      String.raw`(${V})${R}${U}\s+\b${name}\b(?!\s+(?:is|are|was)\s*[=:]?\s*(?:${V})|\s+of\b)`,
    ],
    ["postpositive", String.raw`(${V})${R}${U}\s+in\s+\b${name}\b`],
    ["label", String.raw`\b${name}\s+[a-z]{1,4}\s*[=:]\s*(${V})${R}${U}`],
    ["adjacency", String.raw`\b${name}\b(?:\s+${CONNECTOR})*\s*[=:]?\s*(${V})${R}${U}`],
    [
      "predication",
      String.raw`\b${name}\b[^.;,]*?(?<!\b(?:${SUBORDINATOR})\s+(?:\w+\s+){0,3})\b(?:is|are|was|equals?|measures?|measuring|equal\s+to)\b\s*[=:]?\s*(${V})${R}${U}`,
    ],
  ];
  if (opts.symbol) sources.push(["symbol", String.raw`\b${opts.symbol}\s*=\s*(${V})${R}${U}`]);

  const out: BoundValue[] = [];
  for (const [tier, src] of sources) {
    for (const m of text.matchAll(new RegExp(src, "gi"))) {
      const value = parseNumericToken(m[1]);
      if (value === null || !Number.isFinite(value)) continue;
      out.push({ value, unitRaw: opts.unitSrc ? (m[2] ?? null) : null, tier, index: m.index ?? 0 });
    }
  }
  return out;
}

/** How many times a quantity NAME is mentioned — the "how many objects are in play?"
 * signal that turns a set of disagreeing readings into a decidable ambiguity. */
export function countMentions(text: string, name: string): number {
  return [...text.matchAll(new RegExp(String.raw`\b${name}\b`, "gi"))].length;
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

/** The idioms that state a figure's WIDTH across its middle — i.e. its diameter — without
 * ever naming "diameter": "a tabletop IS 90 CM WIDE", "a courtyard 40 M ACROSS". */
// "LONG" IS NOT A SPAN. It was added here in ROUND 23 and had to come straight back out: the
// same three words carry three incompatible readings, and nothing local distinguishes them —
//   • a RADIAL ARM: "the minute hand is 14 CM LONG", "a rope 7 M LONG" → that IS the radius;
//   • a BOUNDARY: "a circular path around the pond is 44 M LONG", "a wire 88 CM LONG bent into
//     a circle" → that is the CIRCUMFERENCE (and the inverse problem, which this engine
//     declines);
//   • a DISC: "a circular lawn is 30 M LONG" → the diameter.
// Reading all three as a diameter shipped exactly-half answers for the first group and
// π-times-too-big ones for the second, all as verified:true. Only "across"/"wide"/"in width"/
// "in diameter" mean the span through the middle unambiguously; "long" is left unread, so
// those problems decline honestly instead.
// EDGE-TO-OPPOSITE-EDGE is the same span said the long way: "a circular tray measures 30 cm
// FROM ONE RIM TO THE OPPOSITE RIM" is a diameter by construction — the qualifier "opposite"
// (or "other") is what makes the chord pass through the centre, so a plain "from A to B" is
// still not read. Unread, the tray's own span was skipped and a nearby object's diameter got
// bound instead.
const SPAN_IDIOM =
  String.raw`across|wide|broad|in\s+width|in\s+diameter`
  + String.raw`|from\s+(?:one\s+|the\s+)?(?:rim|edge|side|end|point|lip)\s+to\s+the\s+(?:opposite|other|far)\s+(?:rim|edge|side|end|point|lip)`;

export interface SpanReading {
  /** The HEAD NOUN the span is predicated of ("tabletop", "courtyard"). */
  subject: string;
  value: number;
  unitRaw: string | null;
  /** Character offset of the span in the source text. */
  index: number;
}

/**
 * Every "N units WIDE / ACROSS / LONG" span in the text, each tagged with the noun it is
 * predicated OF.
 *
 * A bare list of span values is not enough, because the decisive question is never "what
 * spans are stated?" but "does this span belong to the figure being ASKED about?".
 * "A circular fountain sits in a courtyard 40 M ACROSS. Find the area of the fountain."
 * states exactly one span, so a count-based ambiguity check sees nothing wrong — and the
 * engine sized the COURTYARD, asserting 400π m² for a fountain whose size the text never
 * gives. Conversely "A circular table IS 120 CM WIDE. A plate on it is 24 CM ACROSS. Find
 * the area of the table." states two, and a count-based check declines a problem that is
 * perfectly determinate once you know which noun each span attaches to.
 *
 * So bind the subject. Both English orders are read: the COPULA form ("a tabletop IS 90 cm
 * wide") and the bare APPOSITIVE ("a courtyard 40 m across"). The subject captured is the
 * head noun — the word immediately governing the span — which is what `findAskObject`
 * returns for the ask side, so the two are directly comparable.
 */
/**
 * Words that can never BE the subject of a span. A relativiser or preposition sits in the
 * captured slot whenever the real subject is further left ("the table it rests ON is 100 cm
 * wide", "a plate on IT is 24 cm across") — reading them as nouns invents a figure. Since an
 * unattributable span is exactly what this reader exists to exclude, drop the reading.
 */
const NON_SUBJECT =
  /^\d+$|^(?:it|its|this|that|these|those|there|they|them|he|she|him|her|which|who|whose|whom|where|when|and|or|but|of|on|in|at|by|to|from|with|about|as|is|are|was|were|be|been|measures?|the|a|an|each|every|some|any|all|one|two|three)$/i;

/** Prepositions that open a MODIFIER phrase inside a noun phrase. The head noun sits BEFORE
 * one of these, never inside it: in "a plate ON THE TABLE is 24 cm across" the subject is the
 * plate, not the table. "of" is deliberately absent — it usually introduces the real referent
 * ("the top OF THE TIN is 20 cm across"), so truncating there would lose it. */
const PP_HEAD =
  /^(?:on|in|at|upon|atop|inside|within|under|underneath|beneath|below|beside|near|next|against|by|over|above|behind|between|among|around|round|alongside|opposite)$/i;

/**
 * The HEAD NOUN of the noun phrase ending at `end` — the subject the span is predicated of.
 *
 * The regexes below capture the ONE word sitting before the copula, and that word is the head
 * only when nothing modifies it. Add the commonest modifier there is — a locative phrase — and
 * the capture lands on the phrase's object or its pronoun instead: "A circular tin ON IT is 20
 * cm across" captured "it", which NON_SUBJECT (rightly) refuses, so the tin's span was DROPPED
 * ENTIRELY. The scenery's own width was then the only span left in the text, nothing flagged a
 * conflict, and a SHELF's 60 cm was bound as the tin's diameter — 900π cm² asserted
 * verified:true for a true 100π. Dropping a reading is not the safe direction when a competing
 * one survives.
 *
 * So resolve the head properly: strip a TRAILING modifier phrase, then take the LAST content
 * word of what remains (English NP heads are final). Returns null when the phrase has no
 * content word at all, which is the one case where dropping IS right.
 *
 * Only a TRAILING PP is stripped, and only when the span is predicated through a COPULA. The
 * first cut of this walked LEFT-to-right and truncated at the first preposition it met, which
 * is the wrong side of the phrase entirely: in "A circle is DRAWN ON a card 40 cm wide" it
 * kept "a circle is drawn" and returned the PARTICIPLE "drawn" as the subject — a word the
 * text does describe as circular, so the card's width was admitted as the circle's diameter
 * (400π cm² for a true 36π, and 900π for a circle that is never measured at all). In the
 * ATTRIBUTIVE form ("a card 40 cm wide") the noun the span modifies is the one right in front
 * of it, with nothing to strip; only the copular form ("a circular table IN IT is 90 cm
 * across") puts a modifier between the head and the span.
 */
function headNounBefore(text: string, end: number, stripTrailingPP: boolean): string | null {
  const start = Math.max(
    0,
    ...[";", ",", ".", "?", "!"].map((p) => text.lastIndexOf(p, Math.max(0, end - 1)) + 1)
  );
  const words = text
    .slice(start, end)
    .trim()
    .split(/\s+/)
    .map((w) => w.toLowerCase().replace(/[^a-z0-9]/g, ""))
    .filter(Boolean);
  let np = words;
  if (stripTrailingPP) {
    // A trailing PP is short — a preposition plus a determiner and a noun at most — so only
    // the last three slots are candidates. Anything further left is the head's own material.
    for (let i = np.length - 1; i >= 0 && i >= np.length - 3; i--) {
      if (PP_HEAD.test(np[i])) {
        np = np.slice(0, i);
        break;
      }
    }
  }
  for (let i = np.length - 1; i >= 0; i--) {
    if (!NON_SUBJECT.test(np[i])) return np[i];
  }
  return null;
}

/**
 * The NOUN a NAMED dimension is predicated of — "a board WHOSE DIAMETER is 30 cm" → "board",
 * "a circular plate WITH A DIAMETER OF 30 cm" → "plate", "the RADIUS OF the pizza is 15 cm" →
 * "pizza". Returns null when the text attaches the dimension to no noun at all.
 *
 * `readSpanReadings` already binds a subject to the "N cm wide/across" IDIOM, and the engines
 * use it to throw out a span stated of scenery. A dimension stated by NAME needs exactly the
 * same treatment and had none: the ownership is stated just as explicitly ("whose", "with a",
 * "of the"), but the value readers return a bare number, so a dimension belonging to some other
 * object was indistinguishable from the asked figure's own. "A circular badge is pinned to a
 * board WHOSE DIAMETER IS 30 CM. Find the area OF THE BADGE." shipped 225π cm² — the BOARD's
 * area — for a badge whose size the text never states.
 *
 * Clause-level tests cannot separate these: the owner and the asked figure sit in the SAME
 * clause ("a BUTTON sits on a circular PLATE with a diameter of 30 cm"), so a clause that
 * mentions the ask object still says nothing about which noun the dimension belongs to. Only
 * the noun does.
 */
export function dimensionOwner(text: string, name: string): string | null {
  const V = NUMERIC_TOKEN;
  // Frames that name their owner, in decreasing explicitness. Each captures the noun phrase
  // ENDING where the owner is (group 1 is the material before the dimension) or the owner NP
  // directly (the "of" frame, where the owner FOLLOWS the name).
  const before: string[] = [
    // "<NP> whose <name> is V" / "<NP> whose <name> measures V"
    String.raw`(.*?)\bwhose\s+${name}\b[^.;?!]{0,20}?(?:is|are|was|=|:|measures?)\s*(?:${V})`,
    // "<NP> with a <name> of V" / "<NP> having a <name> of V" / "<NP> HAS a <name> of V" —
    // possession is stated by the verb as often as by the preposition ("The box holding it
    // HAS A DIAMETER OF 40 cm"), and without the verb arm the box's diameter was read as the
    // TRAY's (400π for a true 225π).
    String.raw`(.*?)\b(?:with|having|has|have|had|of)\s+(?:a|an|its|the)?\s*${name}\s+(?:of\s+)?(?:${V})`,
    // "<NP> is V <unit-ish> in <name>" — the postpositive idiom.
    String.raw`(.*?)\b(?:is|are|was|measures?)\s+(?:${V})\s*[a-z]{0,4}\s+in\s+${name}\b`,
    // …and the same idiom with NO copula, where the dimension modifies the noun directly:
    // "A COIN 2 CM IN DIAMETER lies on a circular table", "A TIN LID 8 CM IN DIAMETER is
    // placed on a circular table". This is the ordinary way a bystander object is sized, and
    // with only the copular arm present the dimension had no owner at all — so the veto never
    // fired and the coin's 2 cm sized the TABLE (π cm² for a table the text gives a
    // circumference for). `readSpanReadings` has had the attributive arm all along; the
    // NAMED-dimension reader needs it for the same reason.
    String.raw`(.*?)\b(?:${V})\s*[a-z]{0,4}\s+in\s+${name}\b`,
  ];
  for (const src of before) {
    const m = new RegExp(src, "i").exec(text);
    if (m) {
      const owner = headNounBefore(text, (m.index ?? 0) + m[1].length, true);
      if (owner) return owner;
    }
  }
  // "the <name> of <NP> is V" — here the owner FOLLOWS the name, and the NP head is its last
  // content word ("the radius of a circular pizza" → "pizza").
  //
  // "of" is doing two different jobs in English and only one of them names an owner: "the
  // radius OF THE PIZZA" (ownership) and "a radius OF 9 M" (the VALUE). Without the digit
  // guard the value frame captured "9 m" and returned the UNIT as the owning noun, so every
  // ordinary "has a radius of 9 m" looked like it belonged to something called "m" and the
  // problem's own given was vetoed away.
  const after = new RegExp(
    String.raw`\b${name}\s+of\s+(?!\d)(?:the\s+|a\s+|an\s+|its\s+|this\s+|that\s+)?(?!\d)((?:\w+\s+){0,2}\w+)\b`,
    "i"
  ).exec(text);
  const headOf = (np: string): string | null => {
    const words = np.split(/\s+/).map((w) => w.toLowerCase());
    for (let i = words.length - 1; i >= 0; i--) {
      if (!NON_SUBJECT.test(words[i])) return words[i];
    }
    return null;
  };
  if (after) {
    const head = headOf(after[1]);
    if (head) return head;
  }
  // The PRENOMINAL form — "A 2 CM DIAMETER COIN lies on a circular plate" — states the owner
  // AFTER the dimension, as the head of the noun phrase the whole measure modifies. Neither the
  // "before" frames (the owner precedes) nor the "of" frame (an explicit preposition) can see
  // it, so the coin's 2 cm was an ownerless given and sized the PLATE.
  const prenominal = new RegExp(
    String.raw`\b(?:${V})\s*[a-z]{0,4}[-\s]+${name}\s+((?:\w+\s+){0,2}\w+)\b`,
    "i"
  ).exec(text);
  if (prenominal) {
    const head = headOf(prenominal[1]);
    if (head) return head;
  }
  return null;
}

export function readSpanReadings(text: string, unitSrc: string): SpanReading[] {
  const V = NUMERIC_TOKEN;
  // The unit is REQUIRED. A bare "measures 30 wide" is a stray descriptor of some scenery
  // ("a sector that measures 30 wide"), not a stated diameter, and admitting it let a
  // subordinate clause's number size the figure.
  const U = String.raw`\s*(${unitSrc})(?![a-z])`;
  const sources: ReadonlyArray<readonly [string, boolean]> = [
    // "a circular tabletop IS 90 cm wide", "the pond MEASURES 12 m across" — COPULAR, so a
    // modifier may sit between the head and the copula and has to be stripped.
    [String.raw`\b(\w+)\s+(?:is|are|was|were|measures?)\s+(${V})${U}\s*(?:${SPAN_IDIOM})\b`, true],
    // "a courtyard 40 m across", "a plate 24 cm wide" — and the APPOSITIVE-WITH-COMMA form
    // "a circular badge, 2 1/2 cm across". Without the optional comma the subject slot fell
    // onto the mixed number's WHOLE PART ("2") and the value onto its FRACTION ("1/2"),
    // shipping 1/16 π for a true 25/16 π. (A bare numeral is barred from the subject slot
    // by NON_SUBJECT, so the corrupt reading cannot come back by another route.)
    // …and the ATTRIBUTIVE form, where the span modifies the noun directly in front of it.
    [String.raw`\b(\w+)\s*,?\s+(${V})${U}\s+(?:${SPAN_IDIOM})\b`, false],
  ];
  const out: SpanReading[] = [];
  const seen = new Set<string>();
  for (const [src, stripTrailingPP] of sources) {
    for (const m of text.matchAll(new RegExp(src, "gi"))) {
      const value = parseNumericToken(m[2]);
      if (value === null || !Number.isFinite(value) || value <= 0) continue;
      // Both sources open with `\b(\w+)`, so the match starts at the captured word — the head
      // is resolved over the phrase ENDING there, which returns that same word whenever it is
      // already the head and repairs it when a modifier intervened.
      const subject = headNounBefore(text, (m.index ?? 0) + m[1].length, stripTrailingPP);
      if (subject === null) continue;
      // A span inside a SUBORDINATE clause describes a detail of the figure, not the figure:
      // "the radius of a pizza WHOSE CRUST IS 2 CM WIDE is 15 cm" measures the crust, and
      // "a table WHERE EACH SETTING IS 40 CM WIDE" measures a place setting. Look back to the
      // nearest clause boundary; a subordinator in that window disqualifies the reading.
      if (isSubordinate(text, m.index ?? 0)) continue;
      const key = `${subject}:${value}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({ subject, value, unitRaw: m[3] ?? null, index: m.index ?? 0 });
    }
  }
  return out;
}
