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
