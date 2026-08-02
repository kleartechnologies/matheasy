/**
 * Reading prose the way the quality checks need to read it.
 *
 * Two problems make this less trivial than it looks.
 *
 * 1. **Maths is not prose.** `x^2 - 4x + 3 = 0` inside a sentence is not
 *    vocabulary, is not English, and must not count towards sentence length or
 *    script ratios. Every check that looks at WORDS strips the maths first.
 * 2. **The app speaks 32 languages.** A check that recognises "we simplify" is a
 *    check that works in one of them. So each check here is built in two
 *    layers: a language-INDEPENDENT signal (script, length, structure, declared
 *    references) that holds everywhere, and an English lexicon that sharpens it
 *    where we can be precise. The subjective, per-language half is the judge's
 *    job — it reads all 32 — and the deterministic half never guesses.
 *
 * Nothing here computes mathematics. It strips it, counts it, and looks at what
 * is left.
 */

// ---------------------------------------------------------------------------
// Stripping maths out of prose
// ---------------------------------------------------------------------------

/** `$…$`, `\(…\)`, `\[…\]` — an explicitly delimited math span. */
const MATH_SPAN = /\$[^$]*\$|\\\([\s\S]*?\\\)|\\\[[\s\S]*?\\\]/g;

/** A LaTeX command with its braces: `\frac{1}{2}`, `\sqrt{x}`, `\circ`. */
const LATEX_CMD = /\\[a-zA-Z]+\s*(?:\{[^{}]*\})*/g;

/** A hyphen between two letters is a hyphen. `-` between anything else is a minus. */
const WORD_HYPHEN = /(?<=\p{L})-(?=\p{L})/u;

/** An operator that is unambiguously arithmetic (`-` is not: see [WORD_HYPHEN]). */
const OPERATOR = /[=+*/^<>±×÷≤≥≠]/;

/** The characters a mathematical token may be built from — Latin only, by design. */
const MATH_CHARS = /^[A-Za-z0-9^_().\-+*/=<>±×÷≤≥≠%°|]+$/;

/** Sentence punctuation clinging to a token: `-3,` classifies like `-3`. */
const TRIM_LEFT = /^[("'“‘\[]+/;
const TRIM_RIGHT = /[.,;:!?)"'”’\]]+$/;

/**
 * Whether one whitespace-separated token reads as mathematics.
 *
 * Token-at-a-time, because the obvious regex — "an operator plus everything
 * around it" — cannot be written safely. Its trailing character class has to
 * admit letters and spaces (`2x + 4y = 10`), and the moment it does, one minus
 * sign swallows the rest of the sentence: `is -2 and -3, so the quadratic
 * splits into two brackets` collapses to `is`, and every length, vocabulary and
 * language check downstream then reads a sentence that stops halfway. Judging
 * each token on its own puts a hard floor under how much prose a stray operator
 * can destroy: one word.
 */
function mathyToken(token: string): boolean {
  const core = token.replace(TRIM_LEFT, "").replace(TRIM_RIGHT, "");
  if (!core) return false;
  if (!MATH_CHARS.test(core)) return false; // any other script is prose
  if (/\d/.test(core)) return true;
  if (OPERATOR.test(core)) return true;
  if (core.includes("-")) return !WORD_HYPHEN.test(core); // `-x` yes, `well-known` no
  return core.length === 1; // a lone letter is a variable
}

/** Split ASCII off its neighbours so `角度は2x=10です` tokenises into three pieces. */
const SCRIPT_EDGE = /(?<=[^\x00-\x7F])(?=[\x00-\x7F])|(?<=[\x00-\x7F])(?=[^\x00-\x7F])/g;

/**
 * Drop maximal runs of mathematical tokens.
 *
 * A run is only dropped if it carries a digit or an operator somewhere, so the
 * `x` in "the value of x" survives as a word while "x = 3" does not. Without
 * that rule every English `a` and `I` would be read as a variable and silently
 * deducted from the sentence length the difficulty checks measure.
 */
function stripMathRuns(text: string): string {
  const tokens = text.replace(SCRIPT_EDGE, " ").split(/\s+/);
  const out: string[] = [];
  let run: string[] = [];

  const flush = () => {
    if (run.length === 0) return;
    const joined = run.join(" ");
    if (!/\d/.test(joined) && !OPERATOR.test(joined) && !joined.includes("-")) {
      out.push(...run); // a bare variable, kept as a word
    }
    run = [];
  };

  for (const token of tokens) {
    if (mathyToken(token)) run.push(token);
    else {
      flush();
      out.push(token);
    }
  }
  flush();
  return out.join(" ");
}

/** A standalone number, including decimals, percents and degrees. */
const BARE_NUMBER = /\b\d+(?:[.,]\d+)?\s*(?:%|°)?/g;

/**
 * The words left when the maths is taken out.
 *
 * Used by every length, script and vocabulary check, so that "Divide by 2" and
 * "Divide by 174.5" are the same length of explanation — because as teaching,
 * they are.
 */
export function proseOnly(text: string): string {
  const stripped = stripMathRuns(text.replace(MATH_SPAN, " ").replace(LATEX_CMD, " "));
  return stripped.replace(BARE_NUMBER, " ").replace(/\s+/g, " ").trim();
}

/** Sentence terminators across the scripts the app supports. */
const SENTENCE_END = /[.!?;:]+|[。．！？；]+|[؟۔]+|[।॥]+|\n+/;

/** Split into sentences, dropping empties. Math is left in place. */
export function sentences(text: string): string[] {
  return text
    .split(SENTENCE_END)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

/** Scripts that do not separate words with spaces. */
const SPACELESS = /[一-鿿぀-ヿ฀-๿]/;

/**
 * Roughly how many words a piece of prose is.
 *
 * Chinese, Japanese and Thai do not put spaces between words, so a space count
 * would report every sentence as one word and every brevity check would fire on
 * every Japanese explanation. Characters ÷ 1.7 is the standard approximation and
 * is close enough for "is this sentence too long to follow?".
 */
export function wordCount(text: string): number {
  const prose = proseOnly(text);
  if (!prose) return 0;
  if (SPACELESS.test(prose)) {
    const dense = prose.replace(/\s+/g, "").length;
    return Math.max(1, Math.round(dense / 1.7));
  }
  return prose.split(/\s+/).filter(Boolean).length;
}

/** The words of a piece of prose, lower-cased, for lexicon matching. */
export function words(text: string): string[] {
  return proseOnly(text)
    .toLowerCase()
    .split(/[^\p{L}\p{M}'-]+/u)
    .filter(Boolean);
}

// ---------------------------------------------------------------------------
// Script and language
// ---------------------------------------------------------------------------

export type ScriptId =
  | "latin"
  | "arabic"
  | "hebrew"
  | "devanagari"
  | "cyrillic"
  | "han"
  | "kana"
  | "hangul"
  | "thai";

const SCRIPT_RANGES: Array<[ScriptId, RegExp]> = [
  ["arabic", /[؀-ۿݐ-ݿﭐ-﷿]/],
  ["hebrew", /[֐-׿]/],
  ["devanagari", /[ऀ-ॿ]/],
  ["cyrillic", /[Ѐ-ӿ]/],
  ["kana", /[぀-ヿ]/],
  ["hangul", /[가-힯ᄀ-ᇿ]/],
  ["han", /[一-鿿㐀-䶿]/],
  ["thai", /[฀-๿]/],
  ["latin", /[A-Za-zÀ-ɏ]/],
];

/**
 * The script a language is written in, or null when it uses the Latin alphabet
 * and therefore cannot be told apart from English by script alone.
 */
export function expectedScript(language: string): ScriptId | null {
  const code = language.toLowerCase();
  if (code.startsWith("ar") || code.startsWith("fa")) return "arabic";
  if (code.startsWith("he")) return "hebrew";
  if (code.startsWith("hi")) return "devanagari";
  if (code.startsWith("ru") || code.startsWith("uk")) return "cyrillic";
  if (code.startsWith("ja")) return "kana";
  if (code.startsWith("ko")) return "hangul";
  if (code.startsWith("zh")) return "han";
  if (code.startsWith("th")) return "thai";
  return null;
}

/**
 * What fraction of the letters in [text] belong to [script].
 *
 * Japanese legitimately mixes kana with han, so a kana target accepts both —
 * anything else would flag every correct Japanese sentence.
 */
export function scriptRatio(text: string, script: ScriptId): number {
  const prose = proseOnly(text);
  let total = 0;
  let hit = 0;
  for (const ch of prose) {
    let matched: ScriptId | null = null;
    for (const [id, re] of SCRIPT_RANGES) {
      if (re.test(ch)) {
        matched = id;
        break;
      }
    }
    if (!matched) continue;
    total++;
    if (matched === script) hit++;
    else if (script === "kana" && matched === "han") hit++;
    else if (script === "han" && matched === "kana") hit++;
  }
  return total === 0 ? 1 : hit / total;
}

/**
 * English function words. A sentence built out of these is an English sentence,
 * whatever language it was supposed to be in.
 *
 * Function words, not content words: "triangle" appears untranslated in plenty
 * of correct Malay prose, but "we then divide both sides by" does not.
 */
const ENGLISH_MARKERS = new Set([
  "the", "and", "of", "to", "we", "you", "is", "are", "was", "this", "that",
  "then", "so", "because", "both", "sides", "with", "from", "into", "which",
  "what", "when", "have", "has", "can", "will", "would", "should", "each",
  "every", "there", "their", "them", "our", "your", "for", "not", "but",
  "now", "here", "also", "just", "only", "same", "than", "first", "next",
  "finally", "step", "value", "answer", "number", "solve", "find", "get",
]);

/**
 * English markers that are ALSO ordinary words in another language. Flagging
 * these would report correct Dutch, German or Danish prose as English.
 */
const NATIVE_OVERLAP: Record<string, string[]> = {
  nl: ["of", "is", "we", "not", "so", "for", "in", "van", "step", "the"],
  de: ["so", "in", "will", "for", "was", "of", "hat", "man", "step"],
  da: ["so", "for", "is", "in", "of", "have", "her", "and"],
  nb: ["so", "for", "is", "in", "of", "have", "her", "and"],
  sv: ["for", "is", "in", "of", "so", "har", "and"],
  af: ["is", "of", "the"],
  id: ["are", "so", "step"],
  ms: ["are", "so", "step"],
  it: ["and", "no", "in", "che"],
  es: ["no", "in", "so", "con"],
  pt: ["no", "in", "so", "com", "a"],
  fr: ["a", "in", "so", "car", "the"],
  ro: ["a", "in", "nu", "so"],
  pl: ["to", "so", "in", "we", "nie"],
  cs: ["to", "so", "in", "we"],
  sk: ["to", "so", "in", "we"],
  hr: ["to", "so", "in", "we", "no"],
  hu: ["is", "a", "the", "so"],
  fi: ["on", "in", "so"],
  tr: ["ne", "bu", "so"],
  vi: ["can", "la", "so", "co"],
};

/** The markers that actually signal English for a given target language. */
function markersFor(language: string): Set<string> {
  const base = language.toLowerCase().split(/[-_]/)[0];
  const native = new Set(NATIVE_OVERLAP[base] ?? []);
  const out = new Set<string>();
  for (const m of ENGLISH_MARKERS) if (!native.has(m)) out.add(m);
  return out;
}

/**
 * Whether a single sentence reads as English when it should not.
 *
 * Sentence-level rather than document-level because the failure this catches is
 * an untranslated instruction stranded in otherwise-correct prose — "Divide both
 * sides by 2." sitting in the middle of a Spanish lesson. A document-wide ratio
 * would average that away.
 */
export function readsAsEnglish(sentence: string, language: string): boolean {
  const markers = markersFor(language);
  const w = words(sentence);
  if (w.length < 4) return false; // too short to judge; "OK!" is not English prose
  let hits = 0;
  for (const word of w) if (markers.has(word)) hits++;
  // Three distinct-enough hits, or a third of the sentence: either is far past
  // what a borrowed technical term explains.
  return hits >= 3 || hits / w.length >= 0.34;
}

// ---------------------------------------------------------------------------
// English lexicons — precision where we have it
// ---------------------------------------------------------------------------

/**
 * Terms that carry a definition. Using one before introducing it is check 4 and
 * check 10; the list is English because the check is, and the judge covers the
 * other 31 languages.
 */
export const TECHNICAL_TERMS = [
  "coefficient", "vertex", "denominator", "numerator", "hypotenuse",
  "discriminant", "integrand", "limit", "derivative", "integral", "asymptote",
  "quadratic", "linear", "factorise", "factorize", "expand", "substitute",
  "simplify", "inverse", "reciprocal", "radian", "sine", "cosine", "tangent",
  "logarithm", "exponent", "polynomial", "variance", "median", "quartile",
  "probability", "permutation", "combination", "matrix", "determinant",
  "eigenvalue", "gradient", "intercept", "parabola", "congruent", "similar",
  "bisector", "perpendicular", "parallel", "theorem", "converge", "diverge",
] as const;

/**
 * A term counts as introduced if the prose defines it near where it appears.
 *
 * Split into word cues and punctuation cues because a substring test on "is"
 * would find it inside "this", "consists" and "basis" — and a definition check
 * that passes on the word "this" passes on everything.
 */
const DEFINITION_WORD_CUES = [
  "is", "are", "means", "called", "tells", "shows", "written", "stands",
  "represents", "gives", "value", "number", "name",
];

const DEFINITION_MARK_CUES = ["(", "—", ":", "i.e.", "that is", "which is"];

/**
 * Whether [term] is introduced rather than merely used, somewhere in [text].
 *
 * The cue has to sit RIGHT AFTER the term, because that is where a definition
 * puts it: "the discriminant is b²-4ac", "the discriminant (b²-4ac)". Sweep a
 * wider window and "use the discriminant to decide how many roots there are"
 * counts as a definition on the strength of the "are" at the end of the
 * sentence — and a definition check that passes on that passes on anything.
 *
 * Still deliberately generous within that reach: a definition can be phrased a
 * hundred ways, and a false "you never explained this" on good prose is worse
 * than a missed one on mediocre prose, because the judge sees it too.
 */
export function introducesTerm(text: string, term: string): boolean {
  const lower = text.toLowerCase();
  const at = lower.indexOf(term);
  if (at < 0) return false;
  const near = lower.slice(at + term.length, at + term.length + 30);
  if (DEFINITION_MARK_CUES.some((cue) => near.includes(cue))) return true;
  return DEFINITION_WORD_CUES.some((cue) => new RegExp(`\\b${cue}\\b`).test(near));
}

/**
 * Vague instructions — the "we simplify" family. A step narration built out of
 * one of these tells the student what happened but not what to DO.
 */
export const VAGUE_INSTRUCTIONS = [
  "we simplify", "simplify it", "simplify this", "we solve", "solve it",
  "we compute", "compute it", "we calculate", "calculate it", "do the maths",
  "do the math", "work it out", "as before", "as above", "obviously",
  "clearly", "it follows", "trivially", "and so on", "etc.",
];

/** Phrases that point at something on the page (check 5, English half). */
export const VISUAL_DEIXIS = [
  "highlighted", "circled", "underlined", "shown here", "look at the",
  "notice the", "see the", "this angle", "this triangle", "the diagram",
  "the figure", "the shape shown", "in the picture", "marked in",
  "the arrow", "glowing", "in green", "in blue", "in gold", "in red",
];

/** Phrases that admit doubt (checks 13 and 14, English half). */
export const UNCERTAINTY_MARKERS = [
  "may have", "might have", "may be", "might be", "could be", "not sure",
  "unsure", "check", "confirm", "double-check", "looks like", "if i read",
  "i think", "possibly", "appears to", "can you confirm", "let's look",
  "let us look", "verify the question", "read incorrectly", "misread",
];

/** Whether any phrase from [lexicon] occurs in [text]. */
export function containsAny(text: string, lexicon: readonly string[]): boolean {
  const lower = text.toLowerCase();
  return lexicon.some((phrase) => lower.includes(phrase));
}

/** Every phrase from [lexicon] that occurs in [text]. */
export function matchesIn(text: string, lexicon: readonly string[]): string[] {
  const lower = text.toLowerCase();
  return lexicon.filter((phrase) => lower.includes(phrase));
}

/** Whether the check's English lexicons can be trusted for this language. */
export function isEnglish(language: string): boolean {
  return language.toLowerCase().split(/[-_]/)[0] === "en";
}

// ---------------------------------------------------------------------------
// Digits
// ---------------------------------------------------------------------------

/** The zero of every decimal digit system the supported languages write in. */
const DIGIT_ZEROS = [
  0x0660, // Arabic-Indic          ٠
  0x06f0, // Extended Arabic-Indic ۰
  0x0966, // Devanagari            ०
  0x09e6, // Bengali               ০
  0x0a66, // Gurmukhi              ੦
  0x0ae6, // Gujarati              ૦
  0x0b66, // Oriya                 ୦
  0x0be6, // Tamil                 ௦
  0x0c66, // Telugu                ౦
  0x0ce6, // Kannada               ೦
  0x0d66, // Malayalam             ൦
  0x0e50, // Thai                  ๐
  0x0ed0, // Lao                   ໐
  0x0f20, // Tibetan               ༠
  0x1040, // Myanmar               ၀
  0x17e0, // Khmer                 ០
];

/**
 * Rewrite non-ASCII decimal digits as ASCII.
 *
 * Arabic and Hindi lessons write their numbers in Arabic-Indic and Devanagari
 * digits, and those code points survive NFKC untouched — so the solver's number
 * extractor, quite correctly for its own purposes, reports them as unparseable
 * foreign values. Folding them first is what lets the same "did the prose invent
 * a number?" check run over all 32 languages instead of hard-failing every
 * correct Arabic explanation.
 */
export function foldDigits(text: string): string {
  return text.replace(/\p{Nd}/gu, (ch) => {
    const code = ch.codePointAt(0)!;
    if (code >= 0x30 && code <= 0x39) return ch;
    for (const zero of DIGIT_ZEROS) {
      if (code >= zero && code <= zero + 9) return String(code - zero);
    }
    return ch;
  });
}

/**
 * Canonical form of a mathematical expression, for equality comparison only.
 *
 * Comparison — not evaluation. `2x+4` and `2 x + 4` are the same string once the
 * cosmetics are gone; whether either equals `2(x+2)` is a mathematical question
 * and this layer does not get to ask it.
 */
export function canonicalExpression(expr: string): string {
  return foldDigits(expr)
    .replace(/\\left|\\right|\\!|\\,|\\;|\\ /g, "")
    .replace(/[$\s]/g, "")
    .replace(/\\cdot|\\times/g, "*")
    .replace(/\{|\}/g, "")
    .toLowerCase();
}
