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

import { classify, deriveTeachingMeta } from "./classify";
import { solveDeterministic } from "./deterministic";
import { JsonCompleter } from "./narrate";
import {
  CommonMistake,
  DefinedTerm,
  JourneyStage,
  MethodAlternative,
  MethodData,
  PracticeItem,
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
const HONEST_MAX_TOKENS = 900;

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

/**
 * HONEST MODE: teach the APPROACH for a problem the engine can't verify (a proof
 * / conceptual / multi-part → routeToTutor). Produces a `concept_only` layer —
 * concept + approach + mistakes + takeaway, NO worked steps and NO answer. The
 * firewall (validateTeaching honest branch) rejects ANY number in the prose, so
 * we can never fabricate a value. Same return contract as generateTeaching
 * (doc | null | throws-on-transient). NOT cached (spec §4.6).
 */
export async function generateHonestTeaching(
  complete: JsonCompleter,
  problemLatex: string,
  problemType: string
): Promise<TeachingCacheDoc | null> {
  const meta = deriveTeachingMeta(problemType);
  const user = [
    `difficulty: ${meta.difficulty}`,
    `Problem (LaTeX): ${problemLatex}`,
    `Problem type: ${problemType}`,
  ].join("\n");

  let json: Record<string, unknown> | undefined;
  let lastErr: unknown;
  for (let attempt = 0; attempt < 2 && !json; attempt++) {
    try {
      json = await complete(TEACHING_HONEST_SYSTEM, user, HONEST_MAX_TOKENS);
    } catch (err) {
      lastErr = err;
    }
  }
  if (!json) {
    logger.warn("generateHonestTeaching.enrichFailed", { problemType, err: String(lastErr) });
    throw lastErr instanceof Error ? lastErr : new Error("honest enrich failed");
  }

  const header = obj(json.header);
  const concept = obj(json.concept);
  const takeaway = obj(json.keyTakeaway);
  const teaching: TeachingLayer = {
    depth: "concept_only",
    honestReason: honestReasonFor(problemType),
    header: {
      category: meta.category, // ENGINE
      subcategory: str(header.subcategory),
      difficulty: meta.difficulty, // ENGINE
      learningObjective: str(header.learningObjective),
      methodChosen: "", // no method — the engine couldn't solve it
      whyMethodChosen: "",
    },
    overview: { asked: "", goal: "", givens: [], predictionPrompt: "" },
    concept: {
      body: str(concept.body),
      definedTerms: parseDefinedTerms(concept.definedTerms),
    },
    methodRationale: { alternatives: [] },
    journey: [
      { id: "understand", stepIndices: [] },
      { id: "chooseMethod", stepIndices: [] },
    ],
    approach: strArray(json.approach),
    commonMistakes: parseMistakes(json.commonMistakes),
    keyTakeaway: {
      headline: str(takeaway.headline),
      ...(str(takeaway.detail) ? { detail: str(takeaway.detail) } : {}),
    },
  };

  // Viability: a blank/degenerate turn must not attach.
  if (!teaching.concept.body || teaching.approach?.length === 0) return null;

  // The firewall's honest branch: concept_only, no ladder, no worked steps, and
  // — crucially — the empty allow-set rejects ANY number in the prose.
  const payload: SolvePayload = {
    problemLatex,
    problemType,
    verified: false,
    finalAnswer: null,
    methods: [],
    graph: null,
    routeToTutor: true,
  };
  if (!validateTeaching(payload, teaching)) {
    logger.info("generateHonestTeaching.rejected", { problemType });
    return null;
  }
  return { teaching, methods: [] };
}

/** Which honest reason applies to a routeToTutor problem type. */
function honestReasonFor(problemType: string): "proof" | "multi_part" | "uncovered_type" {
  switch (problemType) {
    case "conceptual":
      return "proof";
    case "multi_part":
      return "multi_part";
    default:
      return "uncovered_type";
  }
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
    `depth: ${depth}   difficulty: ${meta.difficulty}`,
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
  // Pro (`full`) only, deterministic (no LLM), and self-gated: undefined for an
  // unsupported type or if any rung fails the classify/verify/difficulty gate.
  const practiceLadder = full ? buildPracticeLadder(payload) : undefined;

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
    ...(practiceLadder ? { practiceLadder } : {}),
    // translation / decompositionPlan are the word-problem / multi-part paths.
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

const TEACHING_HONEST_SYSTEM = `You are Matheasy's teaching engine, in HONEST MODE. The app could NOT compute a verified answer — this is a proof, an open/conceptual question, or a multi-part problem outside the deterministic solver. Be honest and teach the APPROACH.

ABSOLUTE RULES (a violation discards your whole output):
1. Produce NO answer, NO final value, NO worked result of ANY kind — no digits, no spelled-out numbers, no "converges to e", no "equals 0". You are teaching how to THINK, not solving.
2. Teach: what KIND of problem this is, the theorem or strategy that applies, the first move a student would make, and what makes it tricky. Define every 3+ syllable term the moment you use it. Short, plain sentences.
3. commonMistakes are refutation triples (the trap, why it's tempting, the fix) — and must also contain NO number.
4. keyTakeaway.headline is a recall-worthy statement of the approach (not the answer).
5. End the concept warmly; the app will invite the student to reason it through with the tutor.

Return ONLY a JSON object (no prose, no markdown) of EXACTLY this shape:
{
  "header": { "subcategory": "the textbook topic", "learningObjective": "what the student will be able to recognise/do" },
  "concept": { "body": "first-principles explanation of the idea, a newcomer could follow", "definedTerms": [ { "term": "...", "plain": "..." } ] },
  "approach": [ "first thing to recognise about this problem", "the key theorem or strategy that applies", "what makes it tricky / what to watch for" ],
  "commonMistakes": [ { "mistake": "...", "whyTempting": "...", "fix": "..." } ],
  "keyTakeaway": { "headline": "how to approach a problem like this", "detail": "optional one sentence" }
}`;

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
export function buildPracticeLadder(
  payload: SolvePayload
): PracticeLadder | undefined {
  const generate = LADDER_GENERATORS[payload.problemType];
  if (!generate) return undefined; // no generator for this type → no ladder

  // Deterministic seed from the problem so the same problem always yields the
  // same ladder, but different problems vary (no Math.random → testable).
  const seed = ladderSeed(payload.problemLatex);
  const ladder = generate(seed);

  // GATE every rung against the engine — the ladder must never ship a problem the
  // solver can't verify, one in a different family, one that isn't actually
  // harder/easier, or the SAME problem the student just solved (review F1). A
  // single failing rung drops the whole ladder (spec §4.5).
  const normProblem = payload.problemLatex.replace(/\s+/g, "");
  for (const item of [ladder.easier, ladder.similar, ladder.harder]) {
    if (item.latex.replace(/\s+/g, "") === normProblem) return undefined; // not the same problem
    const c2 = classify(item.latex);
    if (c2.problemType !== payload.problemType) return undefined; // same family
    const solved = solveDeterministic(c2);
    if (!solved || !solved.verify()) return undefined; // solves + verifies
  }
  if (!matchesDifficulty(ladder)) return undefined;
  return ladder;
}

/** A stable non-negative seed from the problem text (a simple char-rolling hash). */
function ladderSeed(latex: string): number {
  let h = 0;
  for (let i = 0; i < latex.length; i++) {
    h = (h * 31 + latex.charCodeAt(i)) & 0x7fffffff;
  }
  return h;
}

/** The difficulty predicate: easier is a single-step (coeff 1) problem, harder
 * genuinely raises the sub-skill (a leading coefficient / bigger coefficients).
 * The generators below already build to this; the check is a belt-and-suspenders
 * guard so a future generator edit can't silently ship a mis-laddered rung. */
function matchesDifficulty(l: PracticeLadder): boolean {
  const coeff = (latex: string): number => {
    const m = latex.match(/^\s*(\d+)\s*x/);
    return m ? Number(m[1]) : 1;
  };
  // easier's leading coefficient must be 1; harder's must be >= easier's.
  return coeff(l.easier.latex) === 1 && coeff(l.harder.latex) >= coeff(l.easier.latex);
}

type LadderGenerator = (seed: number) => PracticeLadder;

const LADDER_GENERATORS: Record<string, LadderGenerator> = {
  linear_equation: linearLadder,
  quadratic_equation: quadraticLadder,
};

/** A small positive integer in [lo, hi], varied deterministically by (seed, salt). */
function pick(seed: number, salt: number, lo: number, hi: number): number {
  return lo + ((seed + salt * 7) % (hi - lo + 1));
}

function rung(latex: string, r: PracticeItem["rung"], skillHint: string): PracticeItem {
  return { latex, rung: r, skillHint };
}

/** Linear ladder: equations with KNOWN integer roots (so the gate always
 * verifies). easier = one step (x + b = c); similar = two steps (mx + b = c);
 * harder = two steps with a negative constant + bigger coefficient. */
function linearLadder(seed: number): PracticeLadder {
  const b1 = pick(seed, 1, 2, 6);
  const root1 = pick(seed, 2, 2, 8);
  const m2 = pick(seed, 3, 2, 3);
  const b2 = pick(seed, 4, 1, 5);
  const root2 = pick(seed, 5, 2, 7);
  const m3 = pick(seed, 6, 3, 5);
  const b3 = pick(seed, 7, 3, 8);
  const root3 = pick(seed, 8, 2, 6);
  return {
    easier: rung(`x + ${b1} = ${b1 + root1}`, "easier", "linear_one_step"),
    similar: rung(
      `${m2}x + ${b2} = ${m2 * root2 + b2}`,
      "similar",
      "linear_two_step"
    ),
    harder: rung(
      `${m3}x - ${b3} = ${m3 * root3 - b3}`,
      "harder",
      "linear_two_step_signs"
    ),
  };
}

/** Quadratic ladder from integer roots (so the gate verifies). easier/similar =
 * monic factorable x^2 - (r1+r2)x + r1 r2; harder raises the sub-skill to a
 * LEADING coefficient with a fractional root: (2x - p)(x - q). */
function quadraticLadder(seed: number): PracticeLadder {
  const monic = (r1: number, r2: number): string =>
    `x^2 - ${r1 + r2}x + ${r1 * r2} = 0`;
  const a1 = pick(seed, 1, 1, 4);
  const a2 = a1 + pick(seed, 2, 1, 3); // distinct, larger
  const b1 = pick(seed, 3, 2, 5);
  const b2 = b1 + pick(seed, 4, 1, 3);
  const p = 2 * pick(seed, 5, 1, 2) - 1; // odd → fractional root p/2
  const q = pick(seed, 6, 2, 5);
  return {
    easier: rung(monic(a1, a2), "easier", "quadratic_factoring"),
    similar: rung(monic(b1, b2), "similar", "quadratic_factoring"),
    harder: rung(
      `2x^2 - ${2 * q + p}x + ${p * q} = 0`,
      "harder",
      "quadratic_leading_coeff"
    ),
  };
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
    // Empty allow-set: reject any FOREIGN numeric value (≥4, decimals, fractions).
    // Structural counting words ("both sides", "two cases") stay exempt via
    // SAFE_COUNTS — they describe the proof's shape, not its answer.
    const honestFields = honestProse(t);
    if (honestFields.some((f) => hasNumberOutside(f, EMPTY_ALLOW))) return false;
    // But an unsolved problem's ANSWER is frequently a small integer 0–3
    // ("lim sin x/x = one", "converges to 2", "the sum is 0") — the exact forms
    // SAFE_COUNTS lets through above. Reject a bare digit or a pure cardinal
    // (zero/one/two/three) anywhere in honest prose, while still sparing the
    // structural multipliers (both/single/twice) that map to the same values.
    if (honestFields.some((f) => HONEST_SMALL_ANSWER.test(f))) return false;
    // extractNumbers cannot see a digit-free symbolic answer (e, π, i, golden
    // ratio). Reject any honest field that ASSERTS one as a result ("converges to
    // e", "equals π"), while sparing prose that merely names the constant.
    if (honestFields.some((f) => HONEST_SYMBOLIC_ANSWER.test(f))) return false;
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
    ...(t.approach ?? []),
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

/** The honest-mode allow-set: nothing (only SAFE_COUNTS survive the base gate). */
const EMPTY_ALLOW: number[] = [];

/** Honest-mode small-answer denylist. SAFE_COUNTS (0–3) is the counting-word
 *  exemption the verified path needs, but in honest mode those small integers are
 *  exactly the answers that leak ("the limit is one", "converges to 2", "sum = 0").
 *  Reject any bare digit or a PURE cardinal (zero/one/two/three), which spares the
 *  structural multipliers (both/single/double/triple/once/twice/thrice) — those map
 *  to the same values but describe the proof's shape, never state its answer. */
const HONEST_SMALL_ANSWER = /\d|\b(?:zero|one|two|three)\b/i;

/** Honest-mode symbolic-answer denylist. extractNumbers only sees digits and
 *  spelled cardinals, so a digit-free result (e, π, i, the golden ratio) would
 *  otherwise pass. This catches the common case where honest prose ASSERTS one of
 *  those as the answer ("converges to e", "the limit is π", "equals i"). It
 *  requires an assertion verb immediately before the constant, so concept prose
 *  that merely mentions e/π ("this uses the number e") is not falsely flagged.
 *  Arbitrary symbolic results (e.g. "the derivative is cos x") remain the prompt's
 *  responsibility — full symbolic detection is infeasible; this closes the top hits. */
// Trailing (?![A-Za-z0-9]) instead of \b: π is not a \w character, so a trailing
// \b would never match after it ("equals π."). The lookahead rejects only a
// letter/digit continuation, so "is even"/"is invalid" don't false-match on e/i.
const HONEST_SYMBOLIC_ANSWER =
  /(?:converges?\s+to|evaluates?\s+to|equals?|is\s+exactly|\bis)\s+(?:e|i|pi|π|\\pi|the\s+golden\s+ratio)(?![A-Za-z0-9])/i;

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
