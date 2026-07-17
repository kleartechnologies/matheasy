/**
 * The teaching layer — an ADDITIVE, LLM-narrated wrap over the FROZEN verified
 * skeleton (spec: docs/matheasy-teaching-engine-spec.md §0, §2, §4).
 *
 * The golden rule (spec §1) extended to pedagogy: every teaching field is either
 * engine-derived metadata or pure "why" narration keyed to a step whose math is
 * already frozen — and NO narration field may state a numeric result the verify
 * gate has not seen. `validateTeaching` is the server-side FIREWALL that enforces
 * this: on any violation the caller strips `teaching` and ships the verified v1
 * payload unchanged. A teaching failure is invisible to correctness.
 *
 * PHASE 0 (this file): the firewall + honest-mode invariants are LIVE and tested;
 * `generateTeaching` / `buildPracticeLadder` are scaffolds (Phase 1 wires the
 * enrichment OpenAI call; Phase 4 the practice ladder). The `teachingEnabled()`
 * flag is OFF, so no teaching is generated in production yet.
 */
import { deriveTeachingMeta } from "./classify";
import {
  PracticeLadder,
  SolvePayload,
  TeachingLayer,
  MethodData,
} from "./types";

// ---------------------------------------------------------------------------
// Scaffolds (filled in later phases; kept here so solve.ts wiring is stable).
// ---------------------------------------------------------------------------

/**
 * Produce the teaching layer for a verified (or honest) skeleton. PHASE 1 wires
 * the single `enrichTeaching` OpenAI call here (one JSON call, subsuming
 * narration, run AFTER verify on the frozen skeleton). Until then it returns
 * undefined and the client renders today's UI.
 */
export async function generateTeaching(): Promise<TeachingLayer | undefined> {
  return undefined;
}

/**
 * Build the (Pro) practice ladder deterministically — NO LLM. PHASE 4 gates each
 * rung through `classify()` family-match + a dry-run `verify()` + a difficulty
 * predicate, and re-verifies on tap. Until then it returns undefined.
 */
export function buildPracticeLadder(): PracticeLadder | undefined {
  return undefined;
}

// ---------------------------------------------------------------------------
// The firewall (spec §4.4) — LIVE.
// ---------------------------------------------------------------------------

/**
 * Prove a teaching layer is safe to attach to `payload`. Returns false (→ strip
 * teaching, ship v1) on ANY of:
 *   • honest-mode violations (a `verified:false`/`routeToTutor` payload must be
 *     `concept_only`, carry no ladder or worked steps, and state NO number);
 *   • a header that disagrees with the engine (methodChosen ≠ examPick, or a
 *     category/difficulty the LLM was not allowed to pick);
 *   • a learningObjective that merely paraphrases the keyTakeaway;
 *   • the STRUCTURAL NUMERIC GATE: any narration field stating a numeric literal
 *     (incl. spelled-out numerals) outside its allow-set (this step's own
 *     expressions + the final answer for per-step fields; the problem + answer +
 *     every step expression for problem-level prose).
 *
 * NOTE: byte-identity of each step `expression` against the pre-enrich frozen
 * skeleton is asserted by the Phase-1 assembler (which holds that skeleton in
 * scope), not here — this function validates the teaching layer against the
 * already-frozen `payload`.
 */
export function validateTeaching(payload: SolvePayload, t: TeachingLayer): boolean {
  const honest = payload.verified !== true || payload.routeToTutor === true;

  // 1) Header anchoring — BOTH paths. The LLM may never pick the engine-owned
  //    category/difficulty, and the forward-goal learningObjective must not merely
  //    restate the recall-cue keyTakeaway.
  const meta = deriveTeachingMeta(payload.problemType);
  if (t.header.category !== meta.category) return false;
  if (t.header.difficulty !== meta.difficulty) return false;
  if (isStringSimilar(t.header.learningObjective, t.keyTakeaway.headline)) {
    return false;
  }

  // 2) Honest mode — maximally conservative: concept only, no answer of any kind.
  if (honest) {
    if (t.depth !== "concept_only") return false;
    if (t.practiceLadder) return false;
    if (payload.methods.some((m) => m.steps.some(hasNarrationBeyondBaseline))) {
      return false;
    }
    // Empty allow-set: reject any numeric VALUE in honest prose. Small structural
    // counting words ("both sides", "two cases") stay exempt via SAFE_COUNTS, but a
    // digit, decimal, fraction, or spelled value ("seven", "1.414") is a leak.
    if (honestProse(t).some((f) => hasNumberOutside(f, EMPTY_ALLOW))) return false;
    return true;
  }

  // 3) Verified path — methodChosen must be the examPick method (name anchoring).
  const pick = payload.methods.find((m) => m.examPick);
  if (pick && t.header.methodChosen !== pick.name) return false;

  // 4) Structural numeric gate — PER STEP (allow = this step's exprs + answer).
  //    operationSymbol IS scrubbed (it renders as a numeric chip, e.g. "− 5").
  //    predictionPrompt/selfExplainPrompt are QUESTIONS and are deliberately NOT
  //    scrubbed (they may use estimation anchors).
  const answerStrings = [payload.finalAnswer?.plain, payload.finalAnswer?.latex];
  for (const m of payload.methods) {
    for (let i = 0; i < m.steps.length; i++) {
      const s = m.steps[i];
      const before = i === 0 ? payload.problemLatex : m.steps[i - 1].expression;
      const allow = numericAllowSet([...answerStrings, before, s.expression]);
      for (const field of [
        s.operation,
        s.operationSymbol,
        s.why,
        s.explanation,
        s.commonMistake,
        s.rule,
      ]) {
        if (field && hasNumberOutside(field, allow)) return false;
      }
    }
  }

  // 4) Structural numeric gate — PROBLEM LEVEL (allow = answer + problem + steps).
  const pAllow = numericAllowSet([
    ...answerStrings,
    payload.problemLatex,
    ...payload.methods.flatMap((m) => m.steps.map((s) => s.expression)),
  ]);
  for (const field of problemProse(t)) {
    if (hasNumberOutside(field, pAllow)) return false;
  }

  // 5) A ladder only ships on a `full` (Pro) payload.
  if (t.practiceLadder && t.depth !== "full") return false;

  return true;
}

/** The problem-level ASSERTION fields the numeric gate scrubs (NOT the question
 * fields, NOT the LaTeX `givens` which merely echo the problem). */
function problemProse(t: TeachingLayer): string[] {
  return [
    t.header.learningObjective,
    t.header.whyMethodChosen,
    t.header.subcategory,
    t.overview.asked,
    t.overview.goal,
    ...t.overview.givens, // LaTeX echoes of the problem — must carry no foreign number
    t.concept.body,
    ...t.concept.definedTerms.flatMap((d) => [d.term, d.plain]),
    ...t.methodRationale.alternatives.flatMap((a) => [a.name, a.whenBetter]),
    ...t.commonMistakes.flatMap((m) => [m.mistake, m.whyTempting, m.fix]),
    t.keyTakeaway.headline,
    t.keyTakeaway.detail ?? "",
    ...(t.translation ?? []),
    ...(t.decompositionPlan ?? []),
    ...t.journey.map((j) => j.summary ?? ""),
  ].filter((s): s is string => Boolean(s));
}

/** Every prose field of an honest-mode layer (numbers forbidden throughout —
 * unlike the verified path, even the prediction question is scrubbed here, since
 * an honest prediction is qualitative and must not assert a value). */
function honestProse(t: TeachingLayer): string[] {
  return [
    t.concept.body,
    ...t.concept.definedTerms.flatMap((d) => [d.term, d.plain]),
    t.overview.asked,
    t.overview.goal,
    t.overview.predictionPrompt,
    ...t.overview.givens,
    t.header.learningObjective,
    t.header.whyMethodChosen,
    t.header.subcategory,
    ...t.methodRationale.alternatives.flatMap((a) => [a.name, a.whenBetter]),
    ...t.commonMistakes.flatMap((m) => [m.mistake, m.whyTempting, m.fix]),
    t.keyTakeaway.headline,
    t.keyTakeaway.detail ?? "",
    ...(t.translation ?? []),
    ...(t.decompositionPlan ?? []),
    ...t.journey.map((j) => j.summary ?? ""),
  ].filter((s): s is string => Boolean(s));
}

/** A worked-step field an honest (answerless) payload must never carry. */
function hasNarrationBeyondBaseline(step: MethodData["steps"][number]): boolean {
  return Boolean(
    step.operation ||
      step.why ||
      step.explanation ||
      step.commonMistake ||
      step.rule ||
      step.operationSymbol ||
      step.selfExplainPrompt
  );
}

// ---------------------------------------------------------------------------
// Structural numeric gate — the primary anti-smuggling defense (spec §4.4).
// ---------------------------------------------------------------------------

/** Structural counting integers that appear in ordinary math prose ("one root",
 * "two brackets", "no solutions") and are never a meaningful smuggled *result*.
 * They are always allowed on the verified path; the gate still catches every
 * decimal, fraction, √, and integer ≥ 4 not present in the skeleton. */
const SAFE_COUNTS = new Set([0, 1, 2, 3]);

/** The honest-mode allow-set: nothing (only SAFE_COUNTS survive the gate). */
const EMPTY_ALLOW: number[] = [];

const EPS = 1e-6;

/**
 * True if `field` states any numeric value (incl. a spelled-out numeral) that is
 * neither a safe counting word nor present in `allow`. This is the primary
 * defense — a narration field may POINT at a number already in the step/answer,
 * never ASSERT a new one.
 *
 * NOTE (accepted limitation, review finding #5): values are compared by MAGNITUDE
 * (`Math.abs`), because reliable signed extraction from LaTeX prose is infeasible
 * (spaces, `\pm`, "minus"). A sign-flipped value in narration is therefore NOT
 * caught here — but the correct answer is always shown FROZEN and separately, so a
 * sign slip in a "why" sentence is a narration-quality issue for the Phase-1
 * enrichment prompt, never an answer substitution.
 */
function hasNumberOutside(field: string, allow: number[]): boolean {
  for (const n of extractNumbers(field)) {
    if (SAFE_COUNTS.has(n)) continue;
    if (!allow.some((a) => Math.abs(a - n) < EPS)) return true;
  }
  return false;
}

/** Canonical absolute values of every numeric literal across `strings`. */
function numericAllowSet(strings: (string | undefined | null)[]): number[] {
  const out: number[] = [];
  for (const s of strings) {
    if (!s) continue;
    for (const n of extractNumbers(s)) out.push(n);
  }
  return out;
}

/** Safe rational: `n/d`, or `n` when `d` is 0 (so a `\frac{a}{0}` can't NaN out). */
function safeDiv(n: string, d: string): number {
  const den = Number(d);
  return den === 0 ? Number(n) : Number(n) / den;
}

/**
 * Ordered alternation over every digit-based numeric form. CRUCIAL for ReDoS
 * safety (review finding #1): each `\s*` run is bounded by REQUIRED literals
 * (braces or digits), so a run of whitespace can never be repartitioned across
 * adjacent optional groups — matching stays linear. Named groups keep the branch
 * dispatch readable; every group name is unique (no duplicate-name reliance).
 */
const NUM_RE = new RegExp(
  [
    // mixed number, braced:  10\frac{1}{2}
    String.raw`(?<mbW>\d+)\\[dt]?frac\{\s*(?<mbN>\d+(?:\.\d+)?)\s*\}\s*\{\s*(?<mbD>\d+(?:\.\d+)?)\s*\}`,
    // mixed number, shorthand:  10\frac12
    String.raw`(?<msW>\d+)\\[dt]?frac(?<msN>\d)(?<msD>\d)`,
    // latex fraction, braced:  \frac{a}{b} (\tfrac/\dfrac too)
    String.raw`\\[dt]?frac\{\s*(?<fbN>-?\d+(?:\.\d+)?)\s*\}\s*\{\s*(?<fbD>-?\d+(?:\.\d+)?)\s*\}`,
    // latex fraction, shorthand:  \frac12
    String.raw`\\[dt]?frac(?<fsN>-?\d)(?<fsD>-?\d)`,
    // square root
    String.raw`\\sqrt\{\s*(?<sqB>-?\d+(?:\.\d+)?)\s*\}`,
    String.raw`\\sqrt(?<sqS>\d)`,
    // scientific notation:  1e3, 2.5E-4
    String.raw`(?<sci>-?\d+(?:\.\d+)?[eE][+-]?\d+)`,
    // ascii fraction:  a/b
    String.raw`(?<afN>\d+(?:\.\d+)?)\/(?<afD>\d+(?:\.\d+)?)`,
    // decimal / integer
    String.raw`(?<dec>-?\d+(?:\.\d+)?)`,
  ].join("|"),
  "g"
);

/**
 * Every numeric literal in `s`, normalized to a canonical NON-NEGATIVE value so
 * that `0.5`, `\frac12`, `1/2`, `1e3`↔`1000`, fullwidth `５` and mixed numbers all
 * compare on equal footing and a smuggled result is caught however it was written.
 * A Unicode decimal digit that NFKC can't fold to ASCII (e.g. Arabic-Indic `٥`) is
 * surfaced as a foreign sentinel so the gate rejects it rather than miss it.
 *
 * Exported for direct unit tests (number-parsing + ReDoS coverage).
 */
export function extractNumbers(s: string): number[] {
  const nums: number[] = [];
  // Fold Unicode digit/format variants (fullwidth ５, superscript ²) to ASCII and
  // strip thousands separators so "1,000" / "1{,}000" read as a single value.
  const norm = s
    .normalize("NFKC")
    .replace(/(\d),(\d{3})(?!\d)/g, "$1$2")
    .replace(/(\d)\{,\}(\d{3})(?!\d)/g, "$1$2");
  for (const m of norm.matchAll(NUM_RE)) {
    const g = m.groups ?? {};
    let value: number;
    if (g.mbW !== undefined) value = Number(g.mbW) + safeDiv(g.mbN, g.mbD);
    else if (g.msW !== undefined) value = Number(g.msW) + safeDiv(g.msN, g.msD);
    else if (g.fbN !== undefined) value = safeDiv(g.fbN, g.fbD);
    else if (g.fsN !== undefined) value = safeDiv(g.fsN, g.fsD);
    else if (g.sqB !== undefined) value = Math.sqrt(Number(g.sqB));
    else if (g.sqS !== undefined) value = Math.sqrt(Number(g.sqS));
    else if (g.sci !== undefined) value = Number(g.sci);
    else if (g.afN !== undefined) value = safeDiv(g.afN, g.afD);
    else if (g.dec !== undefined) value = Number(g.dec);
    else continue;
    if (Number.isFinite(value)) nums.push(Math.abs(value));
  }
  // Spelled-out cardinals (word-boundary; "none"/"someone" don't match "one").
  for (const m of norm.toLowerCase().matchAll(SPELLED_RE)) {
    nums.push(SPELLED[m[0]]);
  }
  // Any Unicode decimal digit NFKC could NOT fold to ASCII is an unparseable
  // numeric form — treat it as a foreign value (Infinity) so both the allow-set
  // gate and honest mode reject it instead of silently missing it.
  if (/\p{Nd}/u.test(norm.replace(/[0-9]/g, ""))) {
    nums.push(Number.POSITIVE_INFINITY);
  }
  return nums;
}

/** Spelled-out numeral → value. Cardinals plus the common multiplier words; the
 * ambiguous ordinals ("first", "third", "half") are deliberately omitted so a
 * phrase like "the first step" is not read as a number. */
const SPELLED: Record<string, number> = {
  zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7,
  eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12, thirteen: 13,
  fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18,
  nineteen: 19, twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60,
  seventy: 70, eighty: 80, ninety: 90, hundred: 100, thousand: 1000,
  once: 1, twice: 2, thrice: 3, single: 1, double: 2, triple: 3, both: 2,
};
const SPELLED_RE = new RegExp(
  `\\b(${Object.keys(SPELLED).join("|")})\\b`,
  "g"
);

// ---------------------------------------------------------------------------
// Text similarity (objective vs takeaway must not be paraphrases — spec §4.4).
// ---------------------------------------------------------------------------

/** True if two strings share ≥70% of their meaningful (≥4-char) tokens (Jaccard),
 * or one contains the other — used to reject a keyTakeaway that merely restates
 * the learningObjective. Conservative threshold so genuinely distinct phrasings
 * (like the golden fixtures') pass. */
function isStringSimilar(a: string, b: string): boolean {
  const na = a.trim().toLowerCase();
  const nb = b.trim().toLowerCase();
  if (!na || !nb) return false;
  if (na.includes(nb) || nb.includes(na)) return true;
  const ta = tokens(a);
  const tb = tokens(b);
  if (ta.size === 0 || tb.size === 0) return false;
  let inter = 0;
  for (const w of ta) if (tb.has(w)) inter++;
  const union = ta.size + tb.size - inter;
  return union > 0 && inter / union >= 0.7;
}

function tokens(s: string): Set<string> {
  return new Set(
    s
      .toLowerCase()
      .replace(/[^a-z0-9 ]/g, " ")
      .split(/\s+/)
      .filter((w) => w.length >= 4)
  );
}
