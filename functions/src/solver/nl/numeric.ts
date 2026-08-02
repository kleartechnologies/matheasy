/**
 * Reusable natural-language NUMERIC-LITERAL reading for the deterministic solver
 * engines. Word-problem parsing recurs across domains (circle mensuration today;
 * geometry, rate/work, finance tomorrow), and every one of them must read a number
 * out of prose the SAME safe way. Centralising it here means a locale or format
 * quirk is fixed once, for all engines, instead of re-discovered per engine.
 *
 * Golden-rule stance: when a literal is AMBIGUOUS, these helpers surface that so the
 * caller can DECLINE. An honest decline never violates the golden rule; a silently
 * truncated number ("1,000" → 1) does.
 */

/**
 * A numeric literal token, as a regex SOURCE (no anchors, no flags) so callers can
 * embed it. Order matters: a MIXED number ("2 1/2") is listed first so its two
 * integers are not split into "2" and "1/2"; then a bare fraction ("3/4"); then a
 * decimal/integer. Contains NO capturing groups, so it is safe to wrap in one.
 */
export const NUMERIC_TOKEN = String.raw`\d+\s+\d+\s*\/\s*\d+|\d+\s*\/\s*\d+|\d+(?:\.\d+)?`;

/**
 * Parse a numeric token to its value: a mixed number ("2 1/2" → 2.5), a fraction
 * ("3/4" → 0.75), or a plain decimal/integer. Returns null when unreadable or a
 * zero denominator — the caller then declines.
 */
export function parseNumericToken(tok: string): number | null {
  const t = tok.trim();
  let m: RegExpMatchArray | null;
  if ((m = t.match(/^(\d+)\s+(\d+)\s*\/\s*(\d+)$/))) {
    const c = Number(m[3]);
    return c === 0 ? null : Number(m[1]) + Number(m[2]) / c;
  }
  if ((m = t.match(/^(\d+)\s*\/\s*(\d+)$/))) {
    const c = Number(m[2]);
    return c === 0 ? null : Number(m[1]) / c;
  }
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

/**
 * Unicode fraction glyphs → their ASCII "a/b" form. A vulgar fraction is a REAL value
 * that a digit reader silently truncates: "7½ cm" reads as 7 (area 49π for a true
 * 225/4 π) and "22½°" as 22. Expanded here they become tokens NUMERIC_TOKEN already
 * parses exactly — glued to a digit the result is the mixed number "7 1/2", standalone
 * it is a plain fraction. The whole Unicode "Number Forms" fraction block is covered,
 * not a hand-picked subset: the gate reached ⅑ and ⅐ the moment ½ and ¾ were fixed.
 */
const VULGAR_FRACTIONS: ReadonlyArray<readonly [string, string]> = [
  ["½", "1/2"], ["⅓", "1/3"], ["⅔", "2/3"], ["¼", "1/4"], ["¾", "3/4"],
  ["⅕", "1/5"], ["⅖", "2/5"], ["⅗", "3/5"], ["⅘", "4/5"], ["⅙", "1/6"],
  ["⅚", "5/6"], ["⅐", "1/7"], ["⅛", "1/8"], ["⅜", "3/8"], ["⅝", "5/8"],
  ["⅞", "7/8"], ["⅑", "1/9"], ["⅒", "1/10"], ["↉", "0/3"],
];

/**
 * A TeX control word ends at the first NON-LETTER — `\sqrt2` and `\times20` are as much
 * `\sqrt` and `\times` as `\sqrt{2}` is. `\b` is therefore the WRONG boundary for a macro
 * test: it needs a non-word character to sit on, and the "t2" junction has none, so every
 * unbraced form slipped past. Two parse-integrity guards were written with `\b` and both
 * failed open on exactly the inputs they existed to stop — `\sqrt2` was flattened to a bare
 * 2 (4π shipped for a true 2π) and `3\times20 degrees` to a bare 3 (3/10 π for a true 6π).
 * One helper so no engine has to remember the rule again.
 */
export function texMacro(...names: string[]): RegExp {
  return new RegExp(String.raw`\\(?:${names.join("|")})(?![a-zA-Z])`, "i");
}

/** Superscript digits → their ASCII form, so "10²" can be read as the power it is. */
const SUPERSCRIPT_DIGIT: Record<string, string> = {
  "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
  "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
};

/**
 * Shift a decimal literal's POINT by `exp` places, exactly — string surgery on the digits,
 * never a float multiply. "1.5" shifted by 2 is "150"; by −2 it is "0.015". Returns null if
 * the mantissa is not a plain decimal literal.
 */
function shiftDecimal(mantissa: string, exp: number): string | null {
  const t = mantissa.trim();
  const neg = t.startsWith("-");
  const raw = t.replace(/^[-+]/, "");
  if (!/^\d+(?:\.\d+)?$/.test(raw)) return null;
  const [ip, fp = ""] = raw.split(".");
  let digits = ip + fp;
  let point = ip.length + exp;
  if (point <= 0) {
    digits = "0".repeat(1 - point) + digits;
    point = 1;
  }
  if (point > digits.length) digits += "0".repeat(point - digits.length);
  const ipart = digits.slice(0, point).replace(/^0+(?=\d)/, "");
  const fpart = digits.slice(point).replace(/0+$/, "");
  return `${neg ? "-" : ""}${ipart}${fpart ? `.${fpart}` : ""}`;
}

/** `base^exp` for a decimal base and a small non-negative integer exponent, exactly (BigInt
 * on the scaled mantissa, then one decimal-point shift). Null when it is not that shape. */
function powDecimal(base: string, exp: number): string | null {
  if (!Number.isInteger(exp) || exp < 0 || exp > 8) return null;
  const raw = base.trim();
  if (!/^\d+(?:\.\d+)?$/.test(raw)) return null;
  const [ip, fp = ""] = raw.split(".");
  return shiftDecimal((BigInt(ip + fp) ** BigInt(exp)).toString(), -fp.length * exp);
}

/**
 * Resolve every EXPONENT form a numeric given can be written in to a plain decimal literal:
 * a superscript power ("10²"), a caret power ("10^2", "2^3", "10^{2}"), E-notation
 * ("1.5e2"), and scientific notation ("1.5 × 10^2", "1.5\times10^{2}").
 *
 * The numeric token is a DECIMAL literal, so a reader that meets one of these takes the
 * MANTISSA and silently drops the exponent — "radius 10² cm" read as radius 10 (100π for a
 * true 10000π), "radius 1.5e2 cm" as 1.5 (9/4 π for a true 22500π). The exponent also ate
 * the unit: the trailing "cm" sat behind the "^2" the reader never consumed, so the answers
 * came out unitless too. Every one shipped verified:true, because the verify gate re-derives
 * from the SAME truncated given.
 *
 * Resolving is exact (decimal-point shifts and BigInt powers, no floats) and unambiguous —
 * there is no second reading of "10^2" — so this is a canonicalisation, not a guess.
 */
export function canonicalizeExponents(text: string): string {
  let out = text.replace(/(\d)([⁰¹²³⁴⁵⁶⁷⁸⁹]+)/g, (_m, d: string, sup: string) =>
    `${d}^${[...sup].map((c) => SUPERSCRIPT_DIGIT[c]).join("")}`
  );
  // Scientific notation first — its "10^n" tail would otherwise be eaten by the plain-power
  // rule below, leaving a bare "1.5 100" the reader would take as 1.5.
  out = out.replace(
    /(\d+(?:\.\d+)?)\s*(?:[x×✕*·]|\\times|\\cdot)\s*10\s*\^\s*\{?\s*([+-]?\d+)\s*\}?/gi,
    (m0: string, mant: string, e: string) => shiftDecimal(mant, Number(e)) ?? m0
  );
  out = out.replace(
    /(?<![a-zA-Z])(\d+(?:\.\d+)?)[eE]([+-]?\d+)(?![\d.])/g,
    (m0: string, mant: string, e: string) => shiftDecimal(mant, Number(e)) ?? m0
  );
  // A plain power. The digit before the caret is required, so a squared UNIT ("36 cm^2") and
  // the radian/gradian superscripts ("2^{c}", "2^{g}") are both left untouched.
  out = out.replace(
    /(\d+(?:\.\d+)?)\s*\^\s*\{?\s*(\d+)\s*\}?/g,
    (m0: string, b: string, e: string) => powDecimal(b, Number(e)) ?? m0
  );
  return out;
}

/**
 * Normalise the numeric GLYPHS in a text so the plain readers see plain ASCII:
 * every vulgar fraction is expanded, and the typographic fraction slashes (U+2044
 * FRACTION SLASH "⁄", U+2215 DIVISION SLASH "∕") become "/". The slash matters as
 * much as the glyphs — "radius 3⁄4 m" is NOT "3/4" to a `\d+\s*\/\s*\d+` token, so
 * the reader took a bare 3 and shipped 9π for a true 9/16 π.
 *
 * Call this on the flattened prose BEFORE any value is read. Engine-agnostic: a
 * glyph quirk is fixed once here for every engine instead of per engine.
 */
export function normalizeNumericGlyphs(text: string): string {
  // Unicode has FIVE π's beyond U+03C0 — the Mathematical Alphanumeric Symbols block spells
  // the same letter bold/italic/sans/mono, and OCR and copy-paste from a typeset paper hand
  // us those. "central angle of 2𝜋/3" (U+1D70B) is a RADIAN angle, but no π-guard matched the
  // glyph, so the reader stripped it and shipped the bare 2 as 2 DEGREES — 1/5 π cm² for a
  // true 12π. Fold them all to the plain letter before anything reads the text.
  let out = text.replace(/[\u{1D6D1}\u{1D70B}\u{1D745}\u{1D77F}\u{1D7B9}\u03D6]/gu, "π");
  out = out.replace(/[⁄∕]/g, "/");
  // `\frac12` — the UNBRACED fraction. Every \frac reader in the codebase required braces,
  // so the generic macro-strip deleted "\frac" and glued the numerator to the denominator:
  // "radius \frac12 cm" became radius 12 (144π shipped for a true π/4). Expanded here it is
  // the ordinary "a/b" token the readers already parse exactly.
  out = out.replace(/\\frac\s*(\d)\s*(\d)(?!\d)/g, " $1/$2 ");
  for (const [glyph, ascii] of VULGAR_FRACTIONS) {
    out = out.split(glyph).join(` ${ascii} `);
  }
  return canonicalizeExponents(out);
}

/**
 * A number that IDENTIFIES the problem rather than measuring anything — "In EXAMPLE 5 the
 * diameter AB = 14 cm", "QUESTION 12: the diameter is 20 cm", "Fig. 3", "Exercise 7(b)".
 *
 * It is a LABEL, and the readers cannot tell a label from a given: "Example 5 diameter AB =
 * 14 cm" bound the 5 as the diameter and shipped 25/4 π for a true 49π — the real given, two
 * words later, never got a look in. Masking the label's digits (they become "#", which no
 * numeric token can match) is exact and reversible-free: a label number is never an input to
 * any computation, in any domain, so this is safe for every engine that reads prose.
 */
/**
 * A MEASURED number is never a label. Several label words — "table", "step", "part",
 * "number", "page" — are also ordinary nouns a figure can be ("a circular TABLE 40 cm
 * across"), and masking there deletes a real given: the table lost its own span and the
 * competing object's radius was used instead (2500π for a true 400π). The unit — or a
 * measure word like "across"/"wide" — is what tells a dimension from an index, so a
 * number carrying one is left alone. This is the general discriminator, not a per-noun
 * exemption: it holds for every label word and every domain.
 */
const MEASURED = String.raw`(?:cm|mm|km|m|metres?|meters?|inch(?:es)?|ft|feet|foot|yd|yards?|°|deg|degrees?|rad|radians?)\b|(?:across|wide|long|deep|high|tall|thick|broad|by)\b`;

const REFERENCE_LABEL = new RegExp(
  String.raw`\b(?:example|examples|question|questions|exercise|exercises|problem|problems|fig|figs`
    + String.raw`|figure|figures|diagram|diagrams|no|nos|number|part|parts|item|items|section|chapter`
    // `(?![.\d])` pins the number WHOLE: without it the digits backtrack ("40" → "4") until
    // the unit guard is looking at a digit instead of the unit, and the guard never fires.
    + String.raw`|page|pages|table|step|steps|q|ex)\b\.?\s*(\d+(?:\.\d+)?)(?!\.\d)(?!\s*(?:\d|\/\s*\d))(?!\s*(?:${MEASURED}))`,
  "gi"
);

/** Blank out every reference-label number in the text (see REFERENCE_LABEL). */
export function maskReferenceLabels(text: string): string {
  return text.replace(REFERENCE_LABEL, (m, digits: string) => m.slice(0, m.length - digits.length) + "#");
}

/**
 * A number written with an interior comma between digits — "1,000", "12,5",
 * "3,14159" — is LOCALE-AMBIGUOUS: it is a thousands separator in en/US notation
 * but the DECIMAL separator across de/fr/es/it/nl/pt… The app ships in 32
 * languages, so we cannot know which is meant, and the two readings differ by
 * orders of magnitude ("12,5" = 12.5 or 125?; "1,000" = 1000 or 1.0?). A parser
 * that guessed would ship a confidently-wrong verified answer. Any engine reading a
 * numeric given must DECLINE when this is present rather than truncate at the comma.
 *
 * Note the intentional NO-SPACE requirement (`\d,\d`): "3, 4, or 5" (a list) and
 * "circle, radius 7" (a clause comma) are NOT matched — only a comma glued between
 * two digits, which is always a single formatted literal.
 */
export const LOCALE_AMBIGUOUS_NUMBER = /\d,\d/;

/** True when the text contains a locale-ambiguous comma-in-number (see above). */
export function hasLocaleAmbiguousNumber(text: string): boolean {
  return LOCALE_AMBIGUOUS_NUMBER.test(text);
}

/**
 * The SPACE is the OTHER thousands separator — SI/ISO 31-0 prescribes it precisely BECAUSE
 * the comma is locale-ambiguous, and it is the standard grouping across fr/ru/pl/sv/cs and
 * most scientific typesetting. "The radius of a circle is 1 000 cm" therefore means 1000, but
 * a reader tokenising on digits takes the leading "1" and the trailing group swallows the
 * unit too — π shipped, unitless, for a true 1000000π cm². A 10⁶ undercount, verified:true,
 * because the gate re-derives from the same truncated given.
 *
 * Unlike the exponent forms in `canonicalizeExponents`, this has a SECOND reading: a space is
 * also just a space, so "in 2024 500 pupils entered" is two numbers and joining them would
 * fabricate one. A separator whose two readings differ by orders of magnitude is exactly the
 * case the comma rule declines, so this declines with it rather than guessing.
 */
export const SPACE_GROUPED_NUMBER = /\d\s+\d{3}(?!\d)/;

/** True when a numeric literal in the text is written with an AMBIGUOUS digit grouping —
 * either separator. One predicate so an engine cannot guard against one and not the other. */
export function hasAmbiguousNumberGrouping(text: string): boolean {
  return LOCALE_AMBIGUOUS_NUMBER.test(text) || SPACE_GROUPED_NUMBER.test(text);
}
