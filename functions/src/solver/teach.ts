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
import { logger } from "firebase-functions/v2";

import { deriveTeachingMeta } from "./classify";
import { JsonCompleter } from "./narrate";
import {
  CommonMistake,
  DefinedTerm,
  JourneyStage,
  MethodAlternative,
  MethodData,
  PracticeLadder,
  SolvePayload,
  TeachingCacheDoc,
  TeachingLayer,
} from "./types";

/** The Pro/Free teaching depth (honest `concept_only` is a separate path). */
export type EnrichDepth = "lite" | "full";

// ---------------------------------------------------------------------------
// Scaffolds (filled in later phases; kept here so solve.ts wiring is stable).
// ---------------------------------------------------------------------------

const ENRICH_MAX_TOKENS = 1600;
const FULL_MAX_TOKENS = 2600;

/**
 * Produce the (lite) teaching layer for a VERIFIED skeleton via ONE OpenAI call,
 * validate it through the firewall, and return the cache doc to attach + store.
 * Returns undefined on any failure → the caller ships the verified v1 payload.
 *
 * PHASE 1 scope (spec §10): verified path, `lite` depth only. Deliberately does
 * NOT subsume narration (spec R12) — `operation`/`why` stay engine/narrate-owned
 * on the frozen core, and this call adds ONLY the additive teaching layer plus
 * per-step `operationSymbol`/`selfExplainPrompt`/`pivotal`. That keeps the
 * verified+narrated core byte-unchanged (zero regression) and sidesteps the
 * two-`why`-authors problem entirely. Pro `full` depth (rule/explanation/
 * per-step mistake/methodRationale/practiceLadder) and honest-mode enrichment
 * are later phases.
 */
export async function generateTeaching(
  complete: JsonCompleter,
  payload: SolvePayload,
  depth: EnrichDepth = "lite"
): Promise<TeachingCacheDoc | null> {
  // Return contract:
  //   • a doc  → attach + cache it;
  //   • null   → a DETERMINISTIC no-teaching outcome (honest guard, no examPick, or
  //              a firewall/viability rejection) — safe for the caller to NEGATIVE-
  //              cache so a reliably-failing problem is not re-enriched every solve;
  //   • throws → a TRANSIENT completer failure — the caller ships v1 and does NOT
  //              negative-cache, so a later solve can still succeed.
  //
  // `depth`: "lite" (Free) authors the base layer; "full" (Pro) ALSO adds the
  // per-step rule/explanation/commonMistake and method alternatives — the deeper,
  // Pro-only fields the Phase-3 client renders one tap deeper.
  if (payload.verified !== true || payload.routeToTutor === true) return null;
  // Require a real exam-pick method — never silently anchor teaching to methods[0].
  const pick = payload.methods.find((m) => m.examPick);
  if (!pick || pick.steps.length === 0) return null;

  const pivotalIndex = pickPivotalIndex(pick.steps.length);
  const user = enrichUserMessage(payload, pick, pivotalIndex, depth);
  const maxTokens = depth === "full" ? FULL_MAX_TOKENS : ENRICH_MAX_TOKENS;

  let json: Record<string, unknown> | undefined;
  let lastErr: unknown;
  for (let attempt = 0; attempt < 2 && !json; attempt++) {
    try {
      json = await complete(TEACHING_ENRICH_SYSTEM, user, maxTokens);
    } catch (err) {
      lastErr = err;
    }
  }
  if (!json) {
    logger.warn("generateTeaching.enrichFailed", {
      problemType: payload.problemType,
      err: String(lastErr),
    });
    throw lastErr instanceof Error ? lastErr : new Error("teaching enrich failed");
  }

  const doc = assembleTeaching(payload, pick, pivotalIndex, json, depth);
  if (!doc) {
    logger.info("generateTeaching.rejected", { problemType: payload.problemType });
    return null;
  }
  return doc;
}

/** The pivotal step the journey's `apply` stage points at: the central
 * transformation, chosen deterministically (never model-supplied). */
function pickPivotalIndex(len: number): number {
  return len > 0 ? Math.floor((len - 1) / 2) : -1;
}

/** The 6-stage journey with ENGINE-computed step indices (spec R13): `apply`
 * points at the pivotal step, `simplify` at everything after it. Phase-1 lite
 * ships LABEL-ONLY stages (no `summary`) — per-stage summaries are a `full`/Phase-3
 * addition (they would be model-authored and scrubbed via `problemProse`). */
function buildJourney(len: number, pivotal: number): JourneyStage[] {
  const after: number[] = [];
  for (let i = pivotal + 1; i < len; i++) after.push(i);
  return [
    { id: "understand", stepIndices: [] },
    { id: "chooseMethod", stepIndices: [] },
    { id: "apply", stepIndices: pivotal >= 0 ? [pivotal] : [] },
    { id: "simplify", stepIndices: after },
    { id: "verify", stepIndices: [] },
    { id: "takeaway", stepIndices: [] },
  ];
}

/** Build the enrichment user turn from the FROZEN skeleton (the examPick method).
 * The model may reason about the `after` expressions but must never return them. */
function enrichUserMessage(
  payload: SolvePayload,
  pick: MethodData,
  pivotalIndex: number,
  depth: EnrichDepth
): string {
  const meta = deriveTeachingMeta(payload.problemType);
  const steps = pick.steps.map((s, i) => ({
    stepId: `${pick.id}#${i}`,
    after: s.expression,
  }));
  // For `full`, ground the alternatives in the OTHER methods the engine actually
  // produced (name only) — the model may add standard ones too.
  const others = payload.methods.filter((m) => m.id !== pick.id).map((m) => m.name);
  return [
    `depth: ${depth}   difficulty: ${meta.difficulty}   language: en`,
    `Problem (LaTeX): ${payload.problemLatex}`,
    `Problem type: ${payload.problemType}`,
    payload.finalAnswer ? `Verified final answer: ${payload.finalAnswer.plain}` : "",
    `Method chosen: ${pick.name}`,
    depth === "full" && others.length
      ? `Also-available methods (name only): ${others.join(", ")}`
      : "",
    pivotalIndex >= 0 ? `Pivotal stepId: ${pick.id}#${pivotalIndex}` : "",
    `Solved steps (math is FINAL — narrate only, key by stepId):`,
    JSON.stringify(steps),
  ]
    .filter(Boolean)
    .join("\n");
}

/**
 * Merge the model's narration into the frozen skeleton and build + VALIDATE the
 * teaching layer. Engine-owned fields (category/difficulty/methodChosen/journey/
 * pivotal) are set here, never taken from the model. Per-step extras land INLINE
 * on the examPick method's steps only (R5). Returns the cache doc, or undefined
 * if the firewall rejects the result.
 */
function assembleTeaching(
  payload: SolvePayload,
  pick: MethodData,
  pivotalIndex: number,
  json: Record<string, unknown>,
  depth: EnrichDepth
): TeachingCacheDoc | undefined {
  const meta = deriveTeachingMeta(payload.problemType);
  const header = obj(json.header);
  const overview = obj(json.overview);
  const concept = obj(json.concept);
  const takeaway = obj(json.keyTakeaway);
  const stepExtras = parseStepExtras(json.steps);
  const full = depth === "full";

  // Deep-copy methods so the enriched inline fields never mutate the frozen core.
  const methods = payload.methods.map((m) => ({
    ...m,
    steps: m.steps.map((s) => ({ ...s })),
  }));
  const pickClone = methods.find((m) => m.id === pick.id);
  if (pickClone) {
    pickClone.steps.forEach((s, i) => {
      const extra = stepExtras.get(`${pick.id}#${i}`);
      const symbol = str(extra?.operationSymbol);
      if (symbol) s.operationSymbol = symbol;
      if (i === pivotalIndex) {
        s.pivotal = true;
        const prompt = str(extra?.selfExplainPrompt);
        if (prompt) s.selfExplainPrompt = prompt;
      }
      // Pro (`full`) only: the deeper per-step fields. Ignored for `lite` even if
      // the model returned them, so a free user never gets Pro depth.
      if (full) {
        const rule = str(extra?.rule);
        const explanation = str(extra?.explanation);
        const commonMistake = str(extra?.commonMistake);
        if (rule) s.rule = rule;
        if (explanation) s.explanation = explanation;
        if (commonMistake) s.commonMistake = commonMistake;
      }
    });
  }

  const teaching: TeachingLayer = {
    depth,
    header: {
      category: meta.category, // ENGINE
      subcategory: str(header.subcategory),
      difficulty: meta.difficulty, // ENGINE
      learningObjective: str(header.learningObjective),
      methodChosen: pick.name, // ENGINE-anchored
      whyMethodChosen: str(header.whyMethodChosen),
    },
    overview: {
      asked: str(overview.asked),
      goal: str(overview.goal),
      givens: strArray(overview.givens),
      predictionPrompt: str(overview.predictionPrompt),
    },
    concept: {
      body: str(concept.body),
      definedTerms: parseDefinedTerms(concept.definedTerms),
    },
    // Pro (`full`) only — free users get no method comparison.
    methodRationale: {
      alternatives: full ? parseAlternatives(json.methodRationale) : [],
    },
    journey: buildJourney(pick.steps.length, pivotalIndex),
    commonMistakes: parseMistakes(json.commonMistakes),
    keyTakeaway: {
      headline: str(takeaway.headline),
      ...(str(takeaway.detail) ? { detail: str(takeaway.detail) } : {}),
    },
    // practiceLadder (deterministic, Pro) is a later increment; translation /
    // decompositionPlan are word-problem / multi-part paths.
  };

  // Minimum viability (#2): a degenerate/blank model turn must NOT attach or get
  // cached — require the two load-bearing narration fields, else ship v1.
  if (!teaching.concept.body || !teaching.header.learningObjective) return undefined;

  const candidate: SolvePayload = { ...payload, methods, teaching };
  if (!validateTeaching(candidate, teaching)) return undefined;
  return { teaching, methods };
}

/** True iff a cached teaching doc's step expressions still byte-match the LIVE
 * verified core — guards the cross-cache-boundary overlay (#5): the teaching and
 * core caches have independent TTLs, so a stale teaching doc must never replace a
 * freshly re-solved core's methods with mismatched working. */
export function methodsAlign(core: MethodData[], cached: MethodData[]): boolean {
  if (core.length !== cached.length) return false;
  for (let i = 0; i < core.length; i++) {
    if (core[i].id !== cached[i].id) return false;
    if (core[i].steps.length !== cached[i].steps.length) return false;
    for (let j = 0; j < core[i].steps.length; j++) {
      if (core[i].steps[j].expression !== cached[i].steps[j].expression) return false;
    }
  }
  return true;
}

// --- enrichment prompt ------------------------------------------------------

const TEACHING_ENRICH_SYSTEM = `You are Matheasy's teaching engine. You write the LEARNING LAYER around a math problem that has ALREADY been solved and mathematically VERIFIED by a separate engine. You TEACH — you never compute.

ABSOLUTE RULES (a violation discards your whole output):
1. The math is FINAL. Every expression and the final answer were proven by the engine. Do NOT recompute, change, reorder, or re-derive them. You author WORDS ONLY, keyed to the step ids I give you. NEVER output any LaTeX expression, answer, or root.
2. NEVER restate a computed result. Your sentences say WHY a move is valid or WHAT a concept means — never WHAT SOMETHING EQUALS. Forbidden: "so x = 8", "the answer is 5", "66 ÷ 5 = 13.2", spelled-out results ("x becomes eight"). If you must mention a number, use only one that already appears in the problem or a step I gave you.
3. Reading level: pitch the CONCEPT simply and define every 3+ syllable math term the moment you use it, in the same sentence. Short sentences. University ideas are pitched with intuition, not dumbed down.
4. whyMethodChosen: state a PROPERTY OF THIS PROBLEM that makes the method fit ("the constant factors into small whole numbers"). NEVER a speed/quality comparison against another method.
5. learningObjective is a FORWARD goal ("Solve a factorable quadratic…"). keyTakeaway.headline is a DIFFERENT sentence — a rule to recall a week later. They must NOT be paraphrases of each other.
6. commonMistakes are refutation triples: the trap, WHY IT'S TEMPTING, and the fix. Give at most 3.
7. selfExplainPrompt: ONLY for the one pivotal step id I flag, write a short QUESTION the student answers before they see the reasoning (e.g. "Which pair of numbers multiplies to 6 and adds to -5?"). A question only — never the answer. Leave it "" for every other step.
8. operationSymbol: a tiny transform chip for a step ("− 5", "×2", "factor") or "" — never a full expression.
9. givens: restate ONLY what the problem gives (its numbers/relations). Introduce NO new number.
10. DEPTH — I tell you depth: "lite" or "full". For "lite", leave every step's "rule"/"explanation"/"commonMistake" as "" and "methodRationale.alternatives" as []. For "full", FILL them: rule = the named property/law that makes THIS step valid (≤6 words, e.g. "Zero-product property"); explanation = one plain sentence on what changed at this step and why; commonMistake = the specific slip a student makes AT THIS step; methodRationale.alternatives = 1-2 OTHER named methods, each with WHEN it is the better choice (conditional knowledge — a property of the problem, never a speed claim).

Return ONLY a JSON object (no prose, no markdown) of EXACTLY this shape:
{
  "header": { "subcategory": "...", "learningObjective": "...", "whyMethodChosen": "..." },
  "overview": { "asked": "...", "goal": "...", "givens": ["restate each given"], "predictionPrompt": "a one-tap question inviting a guess before the answer" },
  "concept": { "body": "first-principles explanation a newcomer could follow", "definedTerms": [ { "term": "...", "plain": "..." } ] },
  "methodRationale": { "alternatives": [ { "name": "other method", "whenBetter": "when it is the better choice (full only)" } ] },
  "steps": [ { "stepId": "<echo the id>", "operationSymbol": "<chip or ''>", "selfExplainPrompt": "<question ONLY on the pivotal step, else ''>", "rule": "<named property, full only, else ''>", "explanation": "<plain what-changed, full only, else ''>", "commonMistake": "<slip at THIS step, full only, else ''>" } ],
  "commonMistakes": [ { "mistake": "...", "whyTempting": "...", "fix": "..." } ],
  "keyTakeaway": { "headline": "one memorable rule", "detail": "optional one-sentence expansion" }
}
Provide exactly one step object per input step, same order, same stepId.`;

// --- coercion helpers -------------------------------------------------------

interface StepExtra {
  operationSymbol?: unknown;
  selfExplainPrompt?: unknown;
  // Pro (`full`) only:
  rule?: unknown;
  explanation?: unknown;
  commonMistake?: unknown;
}

function obj(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : {};
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function strArray(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v.map(str).filter(Boolean);
}

function parseStepExtras(v: unknown): Map<string, StepExtra> {
  const map = new Map<string, StepExtra>();
  if (!Array.isArray(v)) return map;
  for (const raw of v) {
    const o = obj(raw);
    const id = str(o.stepId);
    if (id && !map.has(id)) map.set(id, o as StepExtra);
  }
  return map;
}

function parseDefinedTerms(v: unknown): DefinedTerm[] {
  if (!Array.isArray(v)) return [];
  const out: DefinedTerm[] = [];
  for (const raw of v) {
    const o = obj(raw);
    const term = str(o.term);
    const plain = str(o.plain);
    if (term && plain) out.push({ term, plain });
  }
  return out;
}

function parseMistakes(v: unknown): CommonMistake[] {
  if (!Array.isArray(v)) return [];
  const out: CommonMistake[] = [];
  for (const raw of v) {
    const o = obj(raw);
    const mistake = str(o.mistake);
    const whyTempting = str(o.whyTempting);
    const fix = str(o.fix);
    if (mistake && fix) out.push({ mistake, whyTempting, fix });
    if (out.length === 3) break;
  }
  return out;
}

/** Method alternatives from `methodRationale.alternatives` (Pro `full` only). */
function parseAlternatives(v: unknown): MethodAlternative[] {
  const alts = obj(v).alternatives;
  if (!Array.isArray(alts)) return [];
  const out: MethodAlternative[] = [];
  for (const raw of alts) {
    const a = obj(raw);
    const name = str(a.name);
    const whenBetter = str(a.whenBetter);
    if (name) out.push({ name, whenBetter });
    if (out.length === 2) break;
  }
  return out;
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
  //    The allow-set DELIBERATELY includes the true finalAnswer, so narration may
  //    restate it — prompt rule 2 ("never restate a result") is model guidance the
  //    firewall does not enforce; the firewall enforces "no FOREIGN number".
  //    operationSymbol IS scrubbed (renders as a numeric chip, e.g. "− 5").
  //    selfExplainPrompt IS scrubbed (a self-explain question references THIS step's
  //    own numbers). The problem-level predictionPrompt is the ONLY exempt field —
  //    it is an estimation question that may use round anchors not in the skeleton,
  //    so the client MUST render it unmistakably as a question, never as narration.
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
        s.selfExplainPrompt,
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

  // 6) Symmetric to (5): a `lite` layer must carry NO Pro-only fields (the deeper
  //    per-step fields + method alternatives). The assembler already gates these
  //    on depth, so this is defense-in-depth against a future refactor (review #3).
  if (t.depth === "lite") {
    if (t.methodRationale.alternatives.length > 0) return false;
    for (const m of payload.methods) {
      for (const s of m.steps) {
        if (s.rule || s.explanation || s.commonMistake) return false;
      }
    }
  }

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
