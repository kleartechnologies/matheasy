# Matheasy Teaching Engine — Redesign Specification

*Canonical, build-from source of truth. Reconciles the four specialist deliverables (educational, AI-prompt, backend, client) and folds in both adversarial critiques (teaching-efficacy + golden-rule/feasibility). Where a critique overrode a prior reconciliation ruling, the override is authoritative here and logged in §11. Grounded against `functions/src/solver/types.ts`, `functions/src/solver/{narrate,classify}.ts`, `functions/src/lib/solveCache.ts`, `lib/features/result/domain/{result_models,visual_models}.dart`.*

---

## 0. Design Principles & The Golden Rule

### 0.1 The golden rule, extended to pedagogy

The LLM never invents arithmetic. The answer is computed deterministically (`mathsteps` + `mathjs`), **verified by substituting it back into the original problem**, and only then returned. Uncovered types get a constrained LLM *candidate* that must pass the same substitution gate, else an honest `verified:false`. The teaching layer inherits this unchanged and adds one rule:

> **Every teaching field is either engine-derived (already through the verify gate) or pure "why" narration keyed to a frozen step — and no narration field may state a numeric result the verify gate has not seen.**

### 0.2 The single most important decision

**Teaching is not a tab and not a rewrite — it is an additive narration layer over a frozen verified skeleton, gated by a firewall.** The verified skeleton (`finalAnswer`, every step `expression`, `graph`, `verified`) is frozen *before any teaching call runs*. The teaching LLM is a pure narration function of that frozen skeleton: it receives math, returns words keyed to steps that already exist, and on the primary path emits no math at all. A server-side firewall (`validateTeaching` + structural numeric gate) drops the entire teaching layer on any violation and ships the verified answer unchanged. **A teaching failure is invisible to correctness** — it degrades to exactly today's shipped experience.

### 0.3 Two disjoint field classes (the firewall partition)

| Class | Fields | Why it cannot invent arithmetic |
|---|---|---|
| **ENGINE** (frozen, LLM-never-authors) | `finalAnswer`, step `expression`, `graph.*`, `header.category`, `header.difficulty`, `journey[].stepIndices`, `header.methodChosen` | Produced only by `solveDeterministic`/verified-candidate rebuild or a pure lookup; copied verbatim by the assembler. The model never emits these. |
| **NARRATION** (LLM-authored words) | `operation`, `why`, `explanation`, `commonMistake`, `rule`, `selfExplainPrompt`, `subcategory`, `learningObjective`, `whyMethodChosen`, `overview.*`, `concept.*`, `methodRationale.alternatives`, `commonMistakes[]`, `keyTakeaway`, `translation[]`, `decompositionPlan[]` | Free "why" text keyed to a step whose math is already frozen. May *point at* a value ("subtract the 5"), never *assert* a computed result. |
| **NARRATION → RE-VERIFIED** | `practiceLadder[].latex` | A *problem*, never an answer. Gated by `classify()` + dry-run `verify()` + a difficulty predicate before display; re-enters the full `solve()` gate on tap. |

`beforeLatex`/`afterLatex` are **not on the wire** — they are `expression`-of-this-step and `expression`-of-the-prior-step and are derived client-side (removes a redundant desync surface).

### 0.4 Generation-first (added from the efficacy critique)

Content on screen is not learning. The design forces the student to **predict, retrieve, and self-explain** before it reveals:

1. **Predict before reveal.** The answer banner is gated behind the concept card + a one-tap prediction (`overview.predictionPrompt`). A visible "Just show the answer" escape always exists — the gate is a generation nudge, not a wall, and is A/B-flaggable.
2. **One "why" in the default view.** Every step shows `operation` + `why` with *no tap* — the differentiator (Photomath shows *what* changed; Matheasy shows *why*) is never opt-in.
3. **Elicited self-explanation on the pivotal step.** The engine-marked pivotal step shows a `selfExplainPrompt` ("Your turn: what has to happen to the `+5`?") that the student answers (2-choice or free text) before `why` reveals — the only field that discharges the self-explanation effect, because the *student* produces the explanation.

### 0.5 Honest floor

For `verified:false` / `routeToTutor`, `depth` is forced to `concept_only`, the allow-set is empty, no worked steps / answer / ladder ship, and the journey trims to `understand`+`chooseMethod`. A `honestReason` discriminator (`read_failure | uncovered_type | proof | multi_part`) governs how much is safe to teach: **a `read_failure` (bad OCR/parse) suppresses the concept card entirely and shows only a generic re-scan path** — we never narrate a concept off a skeleton the pipeline just declared unverifiable.

---

## 1. Educational Framework (the pedagogy)

### 1.1 Learning theory → concrete on-screen element

There is a widget for every principle and a principle behind every widget. Nothing on screen is decorative.

| Principle | Discharged by |
|---|---|
| **Worked-example effect** (Sweller) | The one-step-at-a-time stepper, upgraded from `{expression, operation, why}` to carry its *reasoning* in `why`. |
| **Generation / testing effect** (Bjork) | `overview.predictionPrompt` gates the answer reveal; the pivotal-step `selfExplainPrompt` forces a retrieval attempt before the sentence shows. |
| **Self-explanation effect** (Chi) | `selfExplainPrompt` — the **student** answers before `why` reveals (an elicited question, not a sentence to read). |
| **Completion/faded guidance** | Practice Ladder: `easier` (near-worked) → `similar` (independent) → `harder` (transfer, different sub-skill). |
| **Intrinsic vs. extraneous load** (Sweller) | Two-tier disclosure: `operation`+`why`+`before→after` always visible; `explanation`/`commonMistake`/`rule` one tap deeper. Tier-adaptive by `difficulty` (§1.4). |
| **Refutation / misconception-first** (Muller) | Per-step `commonMistake` + the top-3 `commonMistakes` **refutation triple** `{mistake, whyTempting, fix}`. |
| **Concreteness fading / multiple representations** (Bruner, Ainsworth) | Concept overview (anchor→idea→symbol) + the Visual Learning metaphor, which animates **intermediate** verified states (§7). |
| **Advance organizer** (Ausubel) | `overview` + `concept` shown *before* step 1. |
| **Interleaving** (Rohrer) | `harder` rung deliberately requires a *different sub-skill*, feeding the 22-skill adaptive engine. |
| **Metacognition / conditional knowledge** | `whyMethodChosen` (property-of-this-problem) + `methodRationale.alternatives` (when each is better) + Numi's when-to/when-not moves. |
| **Dual coding** (Paivio) | Every step pairs `why` (verbal) with the animated `before→after` transform (visual). |

### 1.2 Reading-level rubric (revised — enforced by jargon-coverage, not Flesch-Kincaid)

FK scores syllables and sentence length and is *blind to conceptual load* — a sentence can be FK-grade-3 and incomprehensible. The gate is therefore:

- **Jargon-coverage gate (the teeth):** every 3+ syllable math term appearing in `concept.body`/`why`/`explanation` **must** have a matching `definedTerms` entry (defined the moment it is used, e.g. *"the discriminant — the part under the square-root sign — …"*). A term without a definition drops that field to fallback. FK is advisory telemetry only.
- **Tier-scaled sentence length:** `primary` ≤ 12 words avg; `secondary`/`preUniversity` ≤ 18; `university` may be denser.
- **Voice:** second person, present tense, concrete nouns, active verbs. Open with a real-world anchor (pizza, money, arrows, a see-saw) before any symbol.
- **Honest claim:** university intuition is *pitched* simply — it is **not** "readable by a 12-year-old." The rigor lives in the steps; the intuition lives in the concept card. A small human-reviewed exemplar set per `ProblemDifficulty` tier calibrates the bar.

### 1.3 Concept-overview micro-structure (prompt rubric → single `body` string)

1. **Anchor** — a familiar picture/story that *is* the idea (1–2 sentences).
2. **The one idea** — the single principle everything rests on (1–2 sentences).
3. **Vocabulary just-in-time** — define only the words the steps use (→ `definedTerms`, ≤ 3).
4. **What we'll do** — one line linking the idea to the coming steps.

> **Primary, `½ + ⅓`:** *"Imagine two pizzas cut differently — one in halves, one in thirds. You can't add '1 slice + 1 slice' because the slices are different sizes. You can only add fractions when the pieces are the same size, so first we re-cut both into sixths."*
> **University, eigenvalues of `[[2,1],[1,2]]`:** *"Picture a matrix as a machine that moves an arrow — usually turning and stretching it. A few special arrows don't turn; the machine only makes them longer or shorter. Those are eigenvectors, and how much each stretches is its eigenvalue."*

### 1.4 Tier-adaptive field density (good pedagogy isn't uniform)

Default visibility keys off `header.difficulty` (ENGINE-derived):

| Tier | Always visible | One tap | Hidden |
|---|---|---|---|
| `primary` | `operation` + `why` + transform | `commonMistake` | `rule` (a university-flavoured label patronises a child) |
| `secondary`/`preUniversity` | `operation` + `why` + transform | `explanation`, `commonMistake`, `rule` chip | — |
| `university` | `operation` + `why` (denser) + transform | `commonMistake`, `rule` chip | anchor prose, hand-holding `explanation` |

---

## 2. Universal Solution Schema (canonical field set)

### 2.1 The trimmed step schema

The critique's #1 finding on the step level: ten fields is extraneous load dressed as rigor. The canonical step keeps the three v1 fields and adds **four** optional narration fields + two mechanism fields — no `title` (collapsed into v1 `operation`), no `objective` (redundant), no `reasoning` (merged into `why`), no `learningTip` (moved to topic-level `keyTakeaway`), no `beforeLatex`/`afterLatex` (derived client-side).

```
StepData  (methods[].steps[i])
  // ── v1, ENGINE-frozen / active-narration, byte-unchanged ──
  expression        string   // ENGINE (verified skeleton). The only math field.
  operation         string   // NARRATION — the action label / eyebrow ("Subtract 5 from both sides")
  why               string   // NARRATION — one sentence, states why the move is VALID (merged why+reasoning). ALWAYS VISIBLE.
  // ── v2 additive, all optional ──
  operationSymbol?  string   // NARRATION — the transform chip ("− 5", "×LCM")
  explanation?      string   // NARRATION — "what changed", collapsed, only when non-obvious (Pro/secondary+)
  commonMistake?    string   // NARRATION — the trap AT THIS STEP, collapsed (Pro)
  rule?             string   // NARRATION — named property label ≤6 words, collapsed (Pro; hidden for primary)
  selfExplainPrompt? string  // NARRATION — an ELICITED QUESTION, pivotal step only
  pivotal?          boolean  // ENGINE-set — the step the journey's `apply` stage points to
```

**`why` never restates arithmetic.** It states *why the move is valid* ("whatever we do to one side we do to the other"), never *what it equals* ("13 − 5 = 8"). Restating the result is forbidden by prompt and caught by the structural numeric gate (§4.4).

### 2.2 The `TeachingLayer` object (authoritative)

```
TeachingLayer
  depth            "full" | "lite" | "concept_only"
  honestReason?    "read_failure" | "uncovered_type" | "proof" | "multi_part"   // concept_only only

  header           TeachingHeader
    category         string    // ENGINE = deriveTeachingMeta().category (snake_case TeachingCategory string)
    subcategory      string    // NARRATION — textbook-index topic
    difficulty       string    // ENGINE = ProblemDifficulty: primary|secondary|preUniversity|university
    learningObjective string   // NARRATION — FORWARD goal "you will be able to…" ≤14 words
    methodChosen     string    // ENGINE-anchored = examPick method name
    whyMethodChosen  string    // NARRATION — PROPERTY of THIS problem, never a speed/quality comparison

  overview         ProblemOverview
    asked            string
    goal             string
    givens           string[]  // LaTeX
    predictionPrompt string    // NARRATION — a one-tap question gating the answer reveal

  concept          ConceptOverview
    body             string    // first-principles, tier-pitched
    definedTerms     [{ term, plain }]

  methodRationale  MethodRationale
    alternatives     [{ name, whenBetter }]        // named + when-better (conditional knowledge)

  journey          JourneyStage[]                   // fixed 6-id model; labels are client constants
    { id, summary?, stepIndices[] }                 // stepIndices ENGINE-derived; ids: understand|chooseMethod|apply|simplify|verify|takeaway

  translation?     string[]                         // word_problem ONLY — English→equation, references only givens
  decompositionPlan? string[]                       // multi_part ONLY — "first solve X, then compute Y"

  commonMistakes   [{ mistake, whyTempting, fix }]  // top 3, topic-level, REFUTATION TRIPLE

  keyTakeaway      { headline, detail? }            // RETRIEVAL CUE (a rule to recall a week later) — distinct from learningObjective

  practiceLadder?  PracticeLadder                   // Pro; omitted for concept_only
    easier | similar | harder : PracticeItem
      latex, plain?, rung, skillHint?               // a PROBLEM, never an answer
```

### 2.3 Wire contract — the v2 `SolvePayload` (additive)

Every v2 key is optional; a v1-only payload is a valid v2 payload. **Capability detection is `teaching != null`** — `schemaVersion` is telemetry only, never a render gate (a mapping slip must never hide a present teaching layer).

```
SolvePayload
  // v1, byte-unchanged: problemLatex, problemType, finalAnswer|null, verified, methods, graph|null, routeToTutor?
  schemaVersion?   number          // = SOLVE_SCHEMA_VERSION (2). Telemetry only.
  teaching?        TeachingLayer    // absent ⇒ client renders today's UI
```

### 2.4 Conflict rulings — as reconciled, with critique overrides (authoritative)

| # | Ruling (final) |
|---|---|
| **R1** | `header.whyMethodChosen` (one property statement) + slim `methodRationale.alternatives:[{name,whenBetter}]`. Method name lives only in `header.methodChosen`. **Override (efficacy #11):** `whyMethodChosen` is a property of *this* problem ("the constant factors into small whole numbers"), never a speed/quality comparison against an unrun method. |
| **R2** | **Overridden (feasibility #4).** Wire `category` = a stable **snake_case string** from the backend-owned `TeachingCategory` union (includes `word_problem`, `conceptual`, `equations`…). The client parses with a **total, non-throwing** lookup (`_teachingCategoryLabel[s] ?? titleCase(s)`), never `ProblemCategory.values.byName`. The 19-value `ProblemCategory` enum stays as the **Visual tier** driver only; `TeachingCategory → ProblemCategory` is a separate total map (§7). Resolves the guaranteed parse crash and Open-Q5. |
| **R3** | Two axes, never conflated. `header.difficulty` = `ProblemDifficulty` (primary/…/university). Practice-item difficulty = `Difficulty` (easy/medium/hard). |
| **R4** | Separate `overview{asked,goal,givens,predictionPrompt}` and `concept{body,definedTerms:[{term,plain}]}`. The 4-part anchor/idea/vocab/preview is a prompt rubric producing `body`. |
| **R5** | **Confirmed + hardened (feasibility #2).** Narration rides as optional fields **directly on `StepData`**. `stepsByMethodId` is **deleted**. `validateTeaching` iterates `payload.methods[examPick].steps[i]` inline. Only examPick steps enriched. |
| **R7** | **Overridden (efficacy #10).** `commonMistakes = [{mistake, whyTempting, fix}]` — the refutation triple; "why it's tempting" is what makes refutation teaching work. |
| **R9** | **Hardened (efficacy #6, feasibility #5).** `buildPracticeLadder` gates each rung through `classify()` family-match **+ dry-run `solveDeterministic().verify()` + a difficulty predicate** (root type, coefficient magnitude, step count). Drop the `latex.includes(finalAnswer.plain)` substring check entirely (it both over- and under-fires; re-verify-on-tap is the real guarantee). `harder` must change sub-skill. |
| **R10** | **Confirmed + split cache (feasibility #7).** `SOLVE_SCHEMA_VERSION=2` telemetry; `TEACHING_SCHEMA_VERSION` string = teaching-cache invalidation only. **Verified core** cached depth-agnostically under the existing `solveCacheKey`; **teaching layer** cached under `sha256(solveCacheKey|TEACHING_SCHEMA_VERSION|depth|language)`. Old v1 docs remain valid cores → no cold-cache spike on the expensive verified math. |
| **R11** | `full | lite | concept_only`. `concept_only` is the only depth allowed with `verified:false`/`routeToTutor`; add `honestReason` discriminator. |
| **R12** | **Overridden (feasibility #1, #6).** `enrichTeaching` **subsumes narration** — one JSON call authors `operation`+`why`+teaching. `narrate.ts` is retained **only as the null-fallback** (invoked when enrich returns null). There are never two competing `why` authors, so no byte-equality gate between them, and the happy path is one call, not two. |
| **R13** | **Hardened (feasibility #9, #12).** 6-id canonical journey. Stage **labels are client constants** (not wired). Wire carries `summary?` + `stepIndices`, and `stepIndices` are **engine-computed in TS from examPick step count** — never accepted from the model. |
| **R14** | Client's deterministic `VisualStrategyResolver.metaphorFor(category, subcategory)` is authoritative for painter choice. Server `params` copied from the **intermediate** verified skeleton (§7). Consistency guard → Tier-2 cards on mismatch. |
| **R15** | See §9. Free must not regress today's per-step `why`. |

---

## 3. AI Prompt Architecture (with full production prompts)

### 3.1 Pass architecture — one call, depth-parameterized, after verify

`enrichTeaching` **replaces** `narrateDeterministic` on the primary path and produces the entire teaching layer (per-step `operation`/`why`/`explanation`/`commonMistake`/`rule`/`operationSymbol`/`selfExplainPrompt` + all problem-level fields) in one JSON object. `depth: "lite"|"full"` shrinks the schema and `max_tokens`, not the call count.

```
solveEquation(uid, latex)
  ├─ rateLimit + quota                                    (unchanged)
  ├─ getCachedCore(latex) HIT → reuse verified core       (existing depth-agnostic key)
  │      MISS → classify → solveDeterministic + verify()  → FROZEN SKELETON (or llm_candidate → verify)
  │             honest? → honestReason set, no answer
  ├─ getCachedTeaching(latex, depth, lang) HIT → attach   ($0)
  │      MISS, teachingEnabled():
  │        enrichTeaching(skeleton, depth, lang)  ── one OpenAI call
  │          fail/null → narrateDeterministic (fallback: operation+why, no teaching)
  │                      fail → humanizeOperation + empty why (today's floor)
  ├─ assembleTeaching(skeleton, enrich)  → firewall (§4.4) + practice validation (§4.5)
  ├─ putCachedCore(latex, core)          (verified only)
  ├─ putCachedTeaching(latex, teaching, depth, lang)   (verified only)
  └─ return payload (+ teaching if it survived validation)
```

**Alignment is by `stepId`, never position or echoed math.** The skeleton tags each step `"<methodId>#<index>"`. The assembler builds `Map<stepId, narration>` and **iterates the skeleton's steps** — a missing key → per-field fallback, an extra/unknown key → dropped, a duplicate → first wins. Length is structurally equal, so one omitted `stepId` can never nuke a whole method (closes feasibility #9). The model never emits `expression`; the assembler injects the engine's copy.

### 3.2 Teaching-Enrichment prompt (`TEACHING_ENRICH_SYSTEM`, verified path)

`temperature: 0.3`, `max_tokens: 2600` (full) / `1200` (lite), JSON mode, static system prompt (prompt-cacheable). `depth`, `difficulty`, `language` ride in the user turn.

```text
SYSTEM (TEACHING_ENRICH_SYSTEM):

You are Matheasy's teaching engine. You write the LEARNING LAYER around a math
problem that has ALREADY been solved and mathematically VERIFIED by a separate
engine. You TEACH — you never compute.

ABSOLUTE RULES (a violation discards your whole output):
1. The math is FINAL. Every expression, the final answer, and every step result
   were proven by the engine. Do NOT recompute, change, reorder, or "double-check"
   them. You author WORDS ONLY, keyed to the step ids I give you. NEVER output any
   LaTeX expression, beforeLatex, afterLatex, answer, or root — only echo "stepId".
2. NEVER restate a computed result in prose. "why"/"explanation" say WHY THE MOVE
   IS VALID, never WHAT IT EQUALS. Forbidden: "so x = 8", "the answer is 5",
   "66 ÷ 5 = 13.2", "adding gives 66", spelled-out results ("x becomes eight").
   If you need a value, refer only to a number already in the step I gave you.
3. Reading level: pitch the CONCEPT simply and define every 3+ syllable math term
   the moment you use it, in the same sentence. Short sentences. University ideas
   are pitched with intuition, not dumbed down — do not claim a 12-year-old could
   follow the rigor.
4. whyMethodChosen: state a PROPERTY OF THIS PROBLEM that makes the method fit
   ("the constant factors into small whole numbers"). NEVER a speed/quality
   comparison against a method that wasn't run ("factoring is faster than the
   formula" is forbidden).
5. learningObjective is a FORWARD goal ("you will be able to…"). keyTakeaway is a
   DIFFERENT sentence: a rule to recall a week later. They must not be paraphrases.
6. commonMistakes are refutation triples: the trap, WHY IT'S TEMPTING, and the fix.
7. selfExplainPrompt: for the ONE pivotal step I flag, write a short QUESTION the
   student answers before the explanation shows (e.g. "What has to happen to the
   +5 to free x?"). A question only — never the answer.

depth "lite": OMIT per-step explanation/commonMistake/rule, methodRationale,
practiceLadder, and give at most 3 commonMistakes at problem level. Keep
per-step operation + why (always) and the concept overview.

Return ONLY a JSON object (no prose, no markdown) of EXACTLY this shape:
{
  "header": { "subcategory": "...", "learningObjective": "...", "whyMethodChosen": "..." },
  "overview": { "asked": "...", "goal": "...", "givens": ["..."], "predictionPrompt": "..." },
  "concept": { "body": "...", "definedTerms": [ { "term": "...", "plain": "..." } ] },
  "methodRationale": { "alternatives": [ { "name": "...", "whenBetter": "..." } ] },
  "translation": [],            // fill ONLY for a word problem: English → equation, step by step
  "decompositionPlan": [],      // fill ONLY for a multi-part problem
  "steps": [
    { "stepId": "factoring#1",
      "operation": "<action label, 2-6 words>",
      "operationSymbol": "<transform chip e.g. '− 5', or ''>",
      "why": "<one sentence: why this move is VALID — never what it equals>",
      "rule": "<named property ≤6 words, or ''>",
      "explanation": "<plain 'what changed', or '' if obvious>",
      "commonMistake": "<the slip AT THIS STEP, or ''>",
      "selfExplainPrompt": "<a question, ONLY on the flagged pivotal step, else ''>" }
  ],
  "commonMistakes": [ { "mistake": "...", "whyTempting": "...", "fix": "..." } ],
  "keyTakeaway": { "headline": "<one recall sentence>", "detail": "<optional>" }
}
Provide exactly one step object per input step, same order, same stepId.
```

```text
USER (built from the frozen skeleton):
depth: full   difficulty: secondary   language: en
Problem (LaTeX): x^2 - 5x + 6 = 0
Problem type: quadratic_equation
Verified final answer: x = 2, x = 3
Method chosen: Factoring (examPick)     Also-available (name only): Quadratic formula
Pivotal stepId: factoring#1
Solved steps (math is FINAL — narrate only, key by stepId):
[ { "stepId":"factoring#0", "operationCode":"START", "after":"x^2 - 5x + 6 = 0" },
  { "stepId":"factoring#1", "operationCode":"FACTOR_SUM_PRODUCT", "after":"(x-2)(x-3)=0" },
  { "stepId":"factoring#2", "operationCode":"ZERO_PRODUCT", "after":"x-2=0 \; or \; x-3=0" },
  { "stepId":"factoring#3", "operationCode":"SOLVE_LINEAR", "after":"x=2 \; or \; x=3" } ]
```

The `after` values let the model *reason about* the math; the schema forbids returning them, and the assembler re-attaches the engine's copy regardless.

### 3.3 Honest-mode enrichment (`TEACHING_HONEST_SYSTEM`)

`temperature: 0.4`, `max_tokens: 900`. **Empty allow-set** — the structural gate rejects *any* numeric literal in any field (closes feasibility #8).

```text
SYSTEM (TEACHING_HONEST_SYSTEM):
You are Matheasy's teaching engine, in HONEST MODE. The app could NOT compute a
verified answer (a proof, an open/conceptual question, or something outside the
solver). Be honest and teach the APPROACH — produce NO answer, NO final value, NO
worked result of ANY kind (no digits, no spelled-out numbers, no "converges to e").
Teach how a student would THINK about it: what kind of problem it is, the theorem
or strategy that applies, the first move, and what to watch for. Define jargon as
you use it. End by inviting the student to reason it out with Numi.

Return ONLY a JSON object of EXACTLY this shape:
{ "header": { "subcategory": "...", "learningObjective": "..." },
  "concept": { "body": "...", "definedTerms": [ { "term":"...", "plain":"..." } ] },
  "approach": [ "first thing to recognise", "the key theorem/strategy", "what makes it tricky" ],
  "commonMistakes": [ { "mistake":"...", "whyTempting":"...", "fix":"..." } ],
  "keyTakeaway": { "headline":"here's how to approach it", "detail":"..." } }
```

*(For `honestReason:"read_failure"` the enrichment call is skipped entirely; the client shows only the generic re-scan path — we never narrate a concept off an unreadable skeleton.)*

### 3.4 Numi tutor prompt (`TUTOR_SYSTEM`, "numi-v2") — deliverable #5

`temperature: 0.6`, `max_tokens: 800`, JSON mode, history replay. **Opens by asking for the student's attempt; diagnoses the typed attempt against `commonMistake`, not a turn counter; chips scaffold the next move, never vend an answer** (closes efficacy #7).

```text
SYSTEM (TUTOR_SYSTEM):
You are Numi, a warm, patient math tutor inside Matheasy, talking with a student
aged 8-18. You TEACH — you do not just answer, and you NEVER simply restate the
step on screen.

OPEN BY ELICITING. Your first move on a new question is to ask the student to
attempt or predict ONE thing — not to explain. Work from THEIR attempt.

DIAGNOSE, DON'T COUNT. When the student gives an attempt, compare it to the known
trap for this step and respond to THEIR specific error with a question that makes
the error visible ("what happens to the sign when you multiply both sides by -1?").
Do not decide to explain based on how many turns have passed — decide based on what
they got wrong or right.

THE FOUR TEACHING MOVES (cover the ones that fit, across the conversation):
  1. WHY IT WORKS — the principle that makes the move valid.
  2. WHEN TO USE — the signal in a problem that says "reach for this".
  3. WHEN NOT TO — the case where it's the wrong tool, and what to use instead.
  4. RECOGNISE THE PATTERN NEXT TIME — a concrete cue they can spot themselves.

SCAFFOLDING: one focused question at a time, then stop and let them try. Escalate
to a direct hint only when they're truly blocked or explicitly ask — give the NEXT
step, never the whole remaining solution.

HONESTY / GOLDEN RULE: the app has already computed and VERIFIED the answer. If
they ask "what's the answer", point them to the verified answer shown on screen and
teach the reasoning — NEVER invent or re-derive a competing number. If unsure, say
so and offer to reason it through together; never bluff a number.

STYLE: concise, encouraging, age-appropriate; define jargon instantly; wrap math in
$...$. Return ONLY: { "reply": "...", "suggestions": ["...","...","..."] }.
```

Optional system riders (the proxy already has the data): the verified answer, the current step's `operation`+`rule`, and — when present — the student's typed attempt, so Numi scaffolds against the real solution and the real error.

### 3.5 Reliability

- **Per-call:** enrich full 0.3/2600, lite 0.3/1200, honest 0.4/900, Numi 0.6/800, `generateLlmCandidate` unchanged 0.2/2000. One retry on transport/parse error with `temperature -= 0.1`.
- **Degrade-never-block:** `enrichTeaching` → null on any failure → `narrateDeterministic` fallback (keeps `operation`+`why`, no regression) → `humanizeOperation`+empty-`why` floor. The verified `finalAnswer`/`verified`/`methods`/`graph` ship regardless.
- **Structural JSON guard:** require `steps` to be an array; coerce every field through length caps; reject the whole enrich object (→ fallback) only if `steps` is absent/not-array. Everything finer is per-field fallback.

---

## 4. Backend Schema & JSON Response (TS interfaces + example fixtures)

### 4.1 `functions/src/solver/types.ts` (additive)

```typescript
export const SOLVE_SCHEMA_VERSION = 2 as const;
export const TEACHING_SCHEMA_VERSION = "teach-v1";

// snake_case string union — NOT a Dart enum; client parses via a total map (never byName)
export type TeachingCategory =
  | "arithmetic" | "fractions" | "algebra" | "equations" | "inequalities"
  | "functions" | "trigonometry" | "calculus" | "statistics" | "probability"
  | "linear_algebra" | "geometry" | "sequences" | "word_problem"
  | "differential_equations" | "conceptual" | "other";
export type Difficulty = "primary" | "secondary" | "preUniversity" | "university";

export interface TeachingHeader {
  category: TeachingCategory; subcategory: string; difficulty: Difficulty;
  learningObjective: string; methodChosen: string; whyMethodChosen: string;
}
export interface ProblemOverview { asked: string; goal: string; givens: string[]; predictionPrompt: string; }
export interface DefinedTerm { term: string; plain: string; }
export interface ConceptOverview { body: string; definedTerms: DefinedTerm[]; }
export interface MethodAlternative { name: string; whenBetter: string; }
export interface MethodRationale { alternatives: MethodAlternative[]; }
export type JourneyStageId = "understand"|"chooseMethod"|"apply"|"simplify"|"verify"|"takeaway";
export interface JourneyStage { id: JourneyStageId; summary?: string; stepIndices: number[]; } // labels client-side
export interface CommonMistake { mistake: string; whyTempting: string; fix: string; }
export interface KeyTakeaway { headline: string; detail?: string; }
export interface PracticeItem { latex: string; plain?: string; rung: "easier"|"similar"|"harder"; skillHint?: string; }
export interface PracticeLadder { easier: PracticeItem; similar: PracticeItem; harder: PracticeItem; }

// per-step narration rides INLINE on StepData (R5); no stepsByMethodId, no beforeLatex/afterLatex
export interface StepData {
  expression: string;               // ENGINE — only math field
  operation: string; why: string;   // active narration (enrich-authored; narrate fallback)
  operationSymbol?: string; explanation?: string; commonMistake?: string;
  rule?: string; selfExplainPrompt?: string; pivotal?: boolean;
}
export interface TeachingLayer {
  depth: "full"|"lite"|"concept_only";
  honestReason?: "read_failure"|"uncovered_type"|"proof"|"multi_part";
  header: TeachingHeader; overview: ProblemOverview; concept: ConceptOverview;
  methodRationale: MethodRationale; journey: JourneyStage[];
  translation?: string[]; decompositionPlan?: string[];
  commonMistakes: CommonMistake[]; keyTakeaway: KeyTakeaway; practiceLadder?: PracticeLadder;
}
export interface SolvePayload {
  problemLatex: string; problemType: string; finalAnswer: FinalAnswer|null;
  verified: boolean; methods: MethodData[]; graph: GraphData|null; routeToTutor?: boolean;
  schemaVersion?: number;           // telemetry only
  teaching?: TeachingLayer;         // capability = (teaching != null)
}
```

### 4.2 Golden fixture — `x^2 - 5x + 6 = 0` (inline steps, no arithmetic-in-prose, property whyMethod, refutation triples)

```json
{
  "schemaVersion": 2,
  "problemLatex": "x^2 - 5x + 6 = 0",
  "problemType": "quadratic_equation",
  "verified": true,
  "finalAnswer": { "latex": "x_1 = 2,\\; x_2 = 3", "plain": "x = 2 or x = 3" },
  "graph": { "kind": "function", "expression": "x^2 - 5x + 6",
    "keyPoints": [ {"label":"root","x":2,"y":0}, {"label":"root","x":3,"y":0}, {"label":"vertex","x":2.5,"y":-0.25} ],
    "curve": [ {"x":1,"y":2}, {"x":2,"y":0}, {"x":2.5,"y":-0.25}, {"x":3,"y":0}, {"x":4,"y":2} ] },
  "methods": [
    { "id": "factoring", "name": "Factoring", "examPick": true, "steps": [
      { "expression": "x^2 - 5x + 6 = 0", "operation": "Start with the equation", "why": "We begin with the quadratic exactly as given, already set to zero." },
      { "expression": "(x - 2)(x - 3) = 0", "operation": "Factor into two brackets", "operationSymbol": "factor",
        "why": "We look for two numbers that multiply to the constant and add to the middle coefficient.",
        "rule": "Sum-product factoring", "explanation": "The pair that multiplies to 6 and adds to -5 is -2 and -3, so the quadratic splits into (x-2)(x-3).",
        "commonMistake": "Choosing the wrong signs and writing (x+2)(x+3).",
        "selfExplainPrompt": "Which pair of numbers multiplies to 6 and adds to -5?", "pivotal": true },
      { "expression": "x - 2 = 0 \\;\\text{or}\\; x - 3 = 0", "operation": "Apply the zero-product rule",
        "why": "A product is zero only when one of its factors is zero, so we split into two simple equations.",
        "rule": "Zero-product property",
        "commonMistake": "Dividing both sides by a bracket, which deletes a solution." },
      { "expression": "x = 2 \\;\\text{or}\\; x = 3", "operation": "Solve each factor",
        "why": "Undoing the subtraction in each bracket isolates x, giving both roots.",
        "commonMistake": "Reporting only one root and forgetting a quadratic usually has two." }
    ] },
    { "id": "quadratic_formula", "name": "Quadratic Formula", "examPick": false, "steps": [
      { "expression": "a=1,\\; b=-5,\\; c=6", "operation": "Identify a, b, c", "why": "The formula needs the three coefficients read off the standard form, keeping each sign." },
      { "expression": "x = \\frac{5 \\pm \\sqrt{25 - 24}}{2}", "operation": "Apply the quadratic formula", "why": "Substituting the coefficients into the formula is always valid for a quadratic." },
      { "expression": "x = \\frac{5 \\pm 1}{2}", "operation": "Simplify the discriminant", "why": "A positive discriminant means two real roots." },
      { "expression": "x = 2 \\;\\text{or}\\; x = 3", "operation": "Find the roots", "why": "The two signs give the two solutions." }
    ] }
  ],
  "teaching": {
    "depth": "full",
    "header": { "category": "equations", "subcategory": "Quadratic equation (factorable, integer roots)",
      "difficulty": "secondary", "learningObjective": "Solve a factorable quadratic using the zero-product rule.",
      "methodChosen": "Factoring", "whyMethodChosen": "The constant factors into small whole numbers, so the equation splits by inspection." },
    "overview": { "asked": "Find every value of x that makes the expression equal zero.",
      "goal": "Rewrite the quadratic as a product of two factors, then set each to zero.",
      "givens": ["x^2 - 5x + 6 = 0", "x is the unknown"],
      "predictionPrompt": "Before we solve: do you think this equation has one answer, two, or none?" },
    "concept": { "body": "A quadratic is an equation where the variable is squared; its graph is a U-shaped parabola. The places the curve crosses the x-axis are the answers, called roots. A parabola can cross twice, touch once, or miss — so a quadratic can have two roots, one, or none.",
      "definedTerms": [ {"term":"quadratic","plain":"an equation whose highest power of x is 2"},
        {"term":"root","plain":"a value of x that makes the expression zero"},
        {"term":"factor","plain":"one of the pieces you multiply together"} ] },
    "methodRationale": { "alternatives": [
      {"name":"Quadratic Formula","whenBetter":"When the quadratic doesn't factor with whole numbers, or you can't spot the factors."},
      {"name":"Completing the Square","whenBetter":"When you also need the vertex, or to derive the formula."} ] },
    "journey": [
      {"id":"understand","summary":"Read the equation; the goal is to find x.","stepIndices":[]},
      {"id":"chooseMethod","summary":"The constant factors cleanly, so factor.","stepIndices":[]},
      {"id":"apply","summary":"Rewrite as (x-2)(x-3)=0.","stepIndices":[1]},
      {"id":"simplify","summary":"Use the zero-product rule and solve each factor.","stepIndices":[2,3]},
      {"id":"verify","summary":"Substitute each root back — both give 0.","stepIndices":[]},
      {"id":"takeaway","summary":"A factorable quadratic solves in one line.","stepIndices":[]} ],
    "commonMistakes": [
      {"mistake":"Getting the signs of the factors wrong.","whyTempting":"Both roots are positive, so students expect plus signs inside the brackets.","fix":"Expand your brackets back and check the middle term is -5x."},
      {"mistake":"Reporting only one root.","whyTempting":"You stop as soon as you find a value that works.","fix":"Two brackets means two equations — set both to zero."},
      {"mistake":"Dividing both sides by a bracket.","whyTempting":"It looks like normal cancelling.","fix":"That deletes a root; use the zero-product rule instead."} ],
    "keyTakeaway": { "headline": "See a factorable quadratic? Factor, then zero each bracket.",
      "detail": "When the numbers factor with whole numbers, the roots fall straight out — no formula needed." },
    "practiceLadder": {
      "easier":  { "latex": "x^2 - 3x + 2 = 0", "rung": "easier", "skillHint": "quadratic_factoring" },
      "similar": { "latex": "x^2 - 7x + 12 = 0", "rung": "similar", "skillHint": "quadratic_factoring" },
      "harder":  { "latex": "2x^2 - 7x + 3 = 0", "rung": "harder", "skillHint": "quadratic_factoring_leading_coeff" }
    }
  }
}
```

The `harder` rung changes sub-skill (leading coefficient ≠ 1) rather than merely flipping a constant's sign — a genuine `harder`, not a disguised `similar`.

### 4.3 Second fixture — mean of a data set (statistics; no graph; arithmetic NOT restated in prose)

```json
{
  "schemaVersion": 2,
  "problemLatex": "\\text{Find the mean of } 4, 8, 15, 16, 23",
  "problemType": "descriptive_statistics_mean",
  "verified": true,
  "finalAnswer": { "latex": "\\bar{x} = 13.2", "plain": "mean = 13.2" },
  "graph": null,
  "methods": [ { "id": "mean_definition", "name": "Arithmetic Mean", "examPick": true, "steps": [
    { "expression": "\\text{values} = \\{4, 8, 15, 16, 23\\}", "operation": "List the values", "why": "Writing out every value makes sure none is missed in the total." },
    { "expression": "4 + 8 + 15 + 16 + 23 = 66", "operation": "Add the values", "operationSymbol": "sum",
      "why": "The mean is built from the grand total, so every value is added together.", "pivotal": true,
      "selfExplainPrompt": "Before dividing — what do we need first, the total or the count?",
      "commonMistake": "Slipping on one term while adding a long list." },
    { "expression": "n = 5", "operation": "Count the values", "why": "We will divide by how many values there are, so the count must be exact.",
      "commonMistake": "Dividing by the largest value instead of the count." },
    { "expression": "\\bar{x} = \\frac{66}{5} = 13.2", "operation": "Divide the total by the count",
      "why": "Sharing the total equally across all the values is exactly what the mean means.",
      "rule": "Mean = sum ÷ count", "commonMistake": "Rounding the decimal away and writing a whole number." }
  ] } ],
  "teaching": {
    "depth": "full",
    "header": { "category": "statistics", "subcategory": "Measure of centre — arithmetic mean",
      "difficulty": "primary", "learningObjective": "Compute the mean of a small data set and say what it represents.",
      "methodChosen": "Arithmetic Mean", "whyMethodChosen": "The question asks for the mean specifically, which is the total shared equally." },
    "overview": { "asked": "Find the average of the five numbers.",
      "goal": "Add all the values, then share the total equally across how many there are.",
      "givens": ["The data set {4, 8, 15, 16, 23}", "There are 5 values"],
      "predictionPrompt": "Quick guess — will the mean be closer to 8 or closer to 20?" },
    "concept": { "body": "The mean is the fair-share number: pour all the values together and split them evenly, and each gets the mean. It describes the middle of a set with one number. Because it uses every value, one very large or very small value pulls it up or down.",
      "definedTerms": [ {"term":"mean","plain":"the total of the values divided by how many there are"},
        {"term":"data set","plain":"the group of numbers you're summarising"} ] },
    "methodRationale": { "alternatives": [
      {"name":"Median","whenBetter":"When extreme outliers would distort the mean."},
      {"name":"Mode","whenBetter":"When you care about the most frequent value, like shoe sizes."} ] },
    "journey": [
      {"id":"understand","summary":"We need the average of five numbers.","stepIndices":[]},
      {"id":"chooseMethod","summary":"'Mean' means sum ÷ count.","stepIndices":[]},
      {"id":"apply","summary":"Add the values, then count them.","stepIndices":[1,2]},
      {"id":"simplify","summary":"Divide the total by the count.","stepIndices":[3]},
      {"id":"verify","summary":"The result sits between the smallest and largest value.","stepIndices":[]},
      {"id":"takeaway","summary":"Mean = total ÷ how many.","stepIndices":[]} ],
    "commonMistakes": [
      {"mistake":"Dividing by the wrong number.","whyTempting":"The largest value is right there and feels significant.","fix":"Divide by the count of values, not by any single value."},
      {"mistake":"Confusing mean with median.","whyTempting":"Both describe 'the middle'.","fix":"Mean = sum ÷ count; median = the middle value once sorted."},
      {"mistake":"Rounding away the decimal.","whyTempting":"Whole numbers feel tidier.","fix":"A mean often isn't whole — keep the decimal."} ],
    "keyTakeaway": { "headline": "To average, total everything then share it out equally.",
      "detail": "The mean always lands between the smallest and largest value — a quick sanity check." },
    "practiceLadder": {
      "easier":  { "latex": "\\text{mean of } 2, 4, 6", "rung": "easier", "skillHint": "mean_small_set" },
      "similar": { "latex": "\\text{mean of } 5, 9, 12, 14, 20", "rung": "similar", "skillHint": "mean_small_set" },
      "harder":  { "latex": "\\text{mean of } 4, 8, 15, 16, 23, 42", "rung": "harder", "skillHint": "mean_with_outlier" }
    }
  }
}
```

Note: no field enumerates partial sums ("4, 12, 27, 43, 66") or restates "66 ÷ 5 = 13.2" — that prose is forbidden (§4.4) and stripped by the numeric gate.

### 4.4 `validateTeaching` — the math-field firewall (rewritten for inline steps + structural numeric gate)

```typescript
export function validateTeaching(payload: SolvePayload, t: TeachingLayer): boolean {
  // 1) Honest-mode invariant
  if (!payload.verified || payload.routeToTutor) {
    if (t.depth !== "concept_only") return false;
    if (t.practiceLadder) return false;
    if (payload.methods.some(m => m.steps.some(hasNarrationBeyondBaseline))) return false;
    // empty allow-set: reject ANY numeric literal in ANY honest-mode prose
    if (containsAnyNumber([t.concept.body, t.keyTakeaway.headline, t.keyTakeaway.detail ?? "",
                           t.overview.asked, t.overview.goal, ...flattenMistakes(t.commonMistakes)])) return false;
  }
  // 2) Header anchoring
  const pick = payload.methods.find(m => m.examPick);
  if (pick && t.header.methodChosen !== pick.name) return false;
  const meta = deriveTeachingMeta(payload); // deterministic; LLM cannot pick category/difficulty
  if (t.header.category !== meta.category || t.header.difficulty !== meta.difficulty) return false;
  if (isStringSimilar(t.header.learningObjective, t.keyTakeaway.headline)) return false; // efficacy #12

  // 3) FIREWALL — only `expression` is math; assert byte-identity to the frozen skeleton,
  //    then STRUCTURALLY scrub every narration field per-step.
  for (const m of payload.methods) {
    for (let i = 0; i < m.steps.length; i++) {
      const s = m.steps[i];
      if (s.expression !== frozen(m.id, i)) return false;              // no re-computed math
      const before = i === 0 ? payload.problemLatex : m.steps[i-1].expression;
      const allow = numericAllowSet([payload.finalAnswer?.plain, before, s.expression]); // this step + answer only
      for (const field of [s.operation, s.why, s.explanation, s.commonMistake, s.rule]) {
        if (field && hasNumberOutside(field, allow)) return false;     // structural, primary defense
      }
    }
  }
  // 4) Problem-level prose: allow-set = answer + problem + all step expressions
  const pAllow = numericAllowSet([payload.finalAnswer?.plain, payload.problemLatex,
                                  ...payload.methods.flatMap(m => m.steps.map(s => s.expression))]);
  for (const f of problemProse(t)) if (hasNumberOutside(f, pAllow)) return false;

  return true; // practice ladder validated separately in buildPracticeLadder (§4.5)
}
```

`hasNumberOutside(field, allow)` — the **structural** primary defense (not the regex scrub): tokenize every numeric literal **including spelled-out cardinals** ("eight"→8, "double"→×2 flagged), normalize each to canonical rational absolute value (parsing `\frac{a}{b}`, `\sqrt`, decimals to a common form so `0.5`/`\frac12`/`1/2` align — closing the `10\frac12`→0.5 class of bug), and reject the field if any token is not in `allow`. The `=n` / "answer is n" regex redaction (`scrub()`) is retained as belt-and-suspenders only. If `validateTeaching` returns false, `solve()` strips `teaching` and ships the verified v1 payload.

### 4.5 `buildPracticeLadder` — real gating (deterministic, no LLM)

```typescript
export function buildPracticeLadder(cls: Classification, p: SolvePayload): PracticeLadder | undefined {
  const cand = { easier: vary(cls, "easier"), similar: vary(cls, "similar"), harder: vary(cls, "harder") };
  for (const rung of ["easier","similar","harder"] as const) {
    const item = cand[rung];
    const c2 = classify(item.latex);
    if (c2.strategy !== cls.strategy) return undefined;                 // same family
    const solved = solveDeterministic(c2); if (!solved || !solved.verify()) return undefined; // dry-run verify
    if (!matchesDifficultyPredicate(item, rung, cls)) return undefined; // root type, coeff magnitude, step count
  }
  return cand; // tap re-enters full solve() — no answer ships in the ladder
}
```

`matchesDifficultyPredicate` is the calibration teeth: e.g. `harder` must add a sub-skill (leading coeff ≠ 1, an extra term, a required negative) and not silently produce irrational roots that flip the difficulty while still passing `verify()`. No `latex.includes(finalAnswer.plain)` check (deleted — it both over- and under-fires).

### 4.6 Caching (split; no cold-cache spike)

```typescript
// verified core — DEPTH-AGNOSTIC, existing key. Old v1 docs are valid cores → no re-solve on cutover.
coreDocId  = sha256(solveCacheKey(latex));
// teaching layer — namespaced; cheap, optional, warmable for top-N before flag flip.
teachDocId = sha256(`${TEACHING_SCHEMA_VERSION}:${depth}:${language}:${solveCacheKey(latex)}`);
```

Only `verified:true` payloads are cached (unchanged). `concept_only` honest teaching is not cached. Both tiers share the one verified core (no double-solve); `operation`+`why` are stored on the core (populated by whichever depth's enrich ran first, or by narrate fallback), so a core hit always yields today's base experience for $0.

### 4.7 Files touched (all additive)

`functions/src/solver/types.ts` (interfaces + versions), new `functions/src/solver/teach.ts` (`generateTeaching`, `validateTeaching`, `buildPracticeLadder`, `deriveTeachingMeta` helper import), `functions/src/solver/classify.ts` (`deriveTeachingMeta` export), `functions/src/proxy/solve.ts` (enrich after verify at the three return sites + `depthForTier` from entitlement), `functions/src/lib/solveCache.ts` (split core/teaching doc ids + depth/lang params), and the client mirror in `lib/features/result/domain/{result_models,teaching_models}.dart`.

---

## 5. Scan Result Screen UX (wireframe + IA)

**The one decision: stop making teaching a tab.** Keep all five tabs (`Solution | Explain | Methods | Practice | Visual ⭐`) — routing, `_visualTabIndex=4`, the practice jump `_selectTab(3)`, and the Pro Visual gate are byte-unchanged. Re-author only the **body of tab 0 (`Solution`)** into a top-to-bottom guided Learning Journey. The other tabs become depth-on-demand.

```
┌───────────────────────────────────────────────┐
│  ‹Back        Solution              Share ▷    │  AppBar (unchanged)
├───────────────────────────────────────────────┤
│  [ scanned photo thumbnail ]                    │  ResultScanImageSlot (unchanged)
│                                                 │
│  ╔══════════ TEACHING HEADER ═══════════════╗   │  NEW TeachingHeaderCard
│  ║ Equations › Quadratic equations · 2ndary  ║   │   category › subcategory · difficulty
│  ║ 🎯 Solve a factorable quadratic with the  ║   │   learningObjective
│  ║    zero-product rule.                     ║   │
│  ╚═══════════════════════════════════════════╝  │
│                                                 │
│  ┌────────── ① CONCEPT OVERVIEW ────────────┐   │  NEW ConceptOverviewCard
│  │ 🧠 A quadratic's graph is a U-shaped curve;│   │   first-principles; tap a jargon chip
│  │    where it crosses the x-axis are the     │   │   → inline definition (AnimatedCrossFade)
│  │    answers…  [quadratic] [root] [factor]   │   │   ▸ asked / goal / givens
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌──── PREDICT BEFORE YOU SEE THE ANSWER ────┐   │  NEW prediction gate (generation)
│  │ 🤔 One answer, two, or none?  [1][2][none] │   │   overview.predictionPrompt
│  │                         Just show answer → │   │   escape always present
│  └───────────────────────────────────────────┘  │
│  ┌────────── ANSWER BANNER (revealed) ───────┐   │  ResultHeader (answer + ✓verified + ▶Play)
│  │  x = 2 or x = 3      ✓ verified   ▶ Play   │   │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ● Understand ─ ○ Method ─ ○ Apply ─ ○ Simplify ─ ○ Verify ─ ○ Takeaway  NEW LearningJourneyRail
│  ▔▔▔▔▔ (sticky scroll-spy; labels are client constants; tappable, 48dp) ▔▔▔▔▔
│                                                 │
│  ┌────────── ② WHY THIS METHOD ─────────────┐   │  NEW WhyThisMethodCard
│  │ ✅ Factoring (chosen)                      │   │   methodChosen + whyMethodChosen (property)
│  │ The constant factors into small whole      │   │
│  │ numbers, so it splits by inspection.       │   │
│  │ ▸ Also: Quadratic formula · Completing sq. │   │   alternatives (names) [compare →] Methods
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌──── ③ APPLY — step 2 (pivotal) ──────────┐   │  ENRICHED StepCard (§6)
│  │ Factor into two brackets            [factor]│   │   operation + operationSymbol chip
│  │   x²-5x+6=0  →  (x-2)(x-3)=0                │   │   before→after (what-changed accent)
│  │   ✍ Your turn: which pair × to 6, + to -5? │   │   selfExplainPrompt (answer before why)
│  │   › why (always visible after attempt)     │   │   ALWAYS-VISIBLE why
│  │   ⚠ Common slip · 📐 Rule   ▾              │   │   one tap: commonMistake + rule (Pro)
│  └───────────────────────────────────────────┘  │
│     [ Next step · 2 of 4 ▾ ]   Reveal all       │  _RevealControls (kept)
│                                                 │
│  ┌────────── ④ VERIFY ───────────────────────┐  │  _VerifyCard (kept; MatheasyBubble)
│  │ 🤖 Check: (2)²-5(2)+6 = 0 ✓                │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌──── ⑤ COMMON MISTAKES (top 3, refute) ────┐  │  NEW CommonMistakesCard {mistake→why→fix}
│  ┌──── ⑥ KEY TAKEAWAY (gold accent) ─────────┐  │  NEW KeyTakeawayCard (distinct from objective)
│  ┌──── PRACTICE LADDER (Pro; teaser if free) ┐  │  NEW PracticeLadderCard 🟢🟡🔴 + XP
│  ┌──── VISUAL LEARNING (flagship hero) ──────┐  │  _VisualLearningHero (kept; → Visual tab)
│                                                 │
│  💬 Numi: "Want to try the next move yourself, │  NEW NumiInviteStrip (four moves as scaffolds)
│     or see when NOT to factor?"                 │
├───────────────────────────────────────────────┤
│      ⌂ Save    ⟳ Practice    💬 Ask Matheasy    │  ResultActionBar (unchanged)
└───────────────────────────────────────────────┘
```

**Honest states preserved and extended.** `routeToTutor`/`verified:false` still short-circuit to `ResultTutorInvite`/`ResultCouldntVerify`. For `honestReason ∈ {uncovered_type, proof, multi_part}` they render only non-answer cards (header, concept/approach, refutation mistakes, takeaway-as-approach). For `honestReason:"read_failure"` they render **only the generic re-scan path** — no concept card off an unreadable skeleton.

---

## 6. Flutter Widget Hierarchy

New widgets under `lib/features/result/presentation/widgets/teaching/`; the enriched step card replaces `_StepCard` inside `solution_tab.dart`. Everything reuses `AppCard`, `context.colors`, `AppTypography`, `AppSpacing`, `AppRadius`, `MathText`/`AdaptiveMath`, `SegmentedControl`, `MatheasyBubble`, `Pressable`, `MatheasyBrandAvatar`.

```
ResultScreen (unchanged shell; ListView + SegmentedControl over 5 tabs)
└─ _buildTab(0) → SolutionTab (re-authored Learning Journey)
   ├─ TeachingHeaderCard(header)                          // breadcrumb + 🎯 learningObjective
   ├─ ConceptOverviewCard(concept, overview, onOpenExplain)
   │     • body (MathText) + Wrap<JargonChip(term→AnimatedCrossFade definition)>
   │     • ProblemOverviewRow(asked/goal/givens) ; "Read it three ways →" → Explain tab
   ├─ PredictionGate(overview.predictionPrompt, onPredict, onSkip)   // NEW — gates ↓
   ├─ ResultHeader(result, onPlay, onRescan)              // answer, revealed after predict/skip
   ├─ LearningJourneyRail(journey, activeStage, onTapStage)          // sticky scroll-spy
   │     • labels are const JourneyStage.label (client-side); chips ≥48dp; scroll-spy via GlobalKeys
   ├─ WhyThisMethodCard(header, methodRationale, onCompare→_selectTab(2))
   ├─ [_MethodSwitcher]  (kept, only when methods.length > 1)
   ├─ for each shown step → StepCard(step, number, isLast, previousLatex, pulse, tier)
   │     ├─ eyebrow: operation + _OperationChip(operationSymbol)
   │     ├─ _StepExpression(expression, previousLatex, isAnswer)      // before→after accent
   │     ├─ if step.pivotal && !answered → SelfExplainBox(selfExplainPrompt)  // gates why
   │     ├─ ALWAYS: why (bodySmall)                        // one 'why' in default view
   │     └─ DEEPER (one tap, tier-gated): commonMistake (warningContainer) + rule chip + explanation
   ├─ [_RevealControls] / _VerifyCard  (kept)
   ├─ CommonMistakesCard(commonMistakes)                  // MistakeRow(✗ mistake · why tempting · ✓ fix)
   ├─ KeyTakeawayCard(keyTakeaway)                        // gold-accent left border; ⭐ headline
   ├─ PracticeLadderCard(practiceLadder, onAttempt, onOpenFull→_selectTab(3))  // Pro; teaser if free
   ├─ [_VisualLearningHero]  (kept; → Visual tab, Pro gate intact)
   └─ NumiInviteStrip(context, onMove, onAsk)             // MatheasyBubble + 4 move chips (scaffold)
```

**Tier-adaptive disclosure** (§1.4): `StepCard` reads `header.difficulty` to decide what is always-visible vs one-tap vs hidden. **Accessibility/tokens:** every toggle/chip is `Semantics(button:true, expanded:…)` with ≥48dp targets; animations gate on `MediaQuery.disableAnimationsOf`; mistakes use `warningContainer`/`onWarningContainer`, fixes `onSuccessContainer`, takeaway `gold`/`goldLight`, header `primaryTint`; emerald text uses `primaryDark`/`primaryLight` (never `AppColors.primary`); no gradient behind white label text except the existing hero. `brand_contrast_test.dart` enforces it.

### Client models (`teaching_models.dart`, additive, null-safe)

All fields default null/empty so **old and cached payloads still parse**; each card renders only when its model's `isEmpty` is false. Category parses via a **total** map, never `byName`:

```dart
String teachingCategoryLabel(String s) => _labels[s] ?? _titleCase(s);   // total; never throws
ProblemCategory visualCategoryFor(String teachingCat) => _toVisual[teachingCat] ?? ProblemCategory.other;
```

`SolutionStep` gains optional `operationSymbol, explanation, commonMistake, rule, selfExplainPrompt, pivotal`; `beforeLatex` is derived from the previous step client-side (not read from the wire). `ResultData` gains `header, overview, concept, methodRationale, journey, commonMistakes, keyTakeaway, practiceLadder, honestReason`.

---

## 7. Visual Learning Engine Architecture (per-category)

The engine turns "one tier per category" into "**one teaching metaphor per (category, subcategory)**, chosen deterministically on-device" — never a second LLM guess, so the picture can never disagree with the verified answer. **Metaphors animate the process (intermediate verified states), not just the answer** (closes efficacy #13).

**Deterministic resolver** — pure Dart switch in `application/visual_strategy_resolver.dart` (input is the *Visual* `ProblemCategory`, mapped from `TeachingCategory` via the total map):

```dart
VisualConceptKind metaphorFor(ProblemCategory c, String subcategory) => switch (c) {
  ProblemCategory.fractions    => VisualConceptKind.fractionBar,        // animate the re-cut to sixths
  ProblemCategory.percentages  => VisualConceptKind.pieChart,           // NEW
  ProblemCategory.ratios       => VisualConceptKind.comparisonBlocks,   // NEW
  ProblemCategory.algebra      => subcategory.contains('factor')
                                    ? VisualConceptKind.areaModel        // NEW
                                    : VisualConceptKind.balanceScale,    // NEW — animate the subtraction
  ProblemCategory.functions ||
  ProblemCategory.graphs       => VisualConceptKind.linearGraph,         // reuse / parabolaGraph
  ProblemCategory.calculus     => subcategory.contains('integral')
                                    ? VisualConceptKind.areaUnderCurve    // reuse
                                    : VisualConceptKind.tangentSlope,     // NEW
  ProblemCategory.geometry     => VisualConceptKind.geometryShape,       // reuse / scene player
  ProblemCategory.trigonometry => VisualConceptKind.labelledTriangle,    // NEW (+ unitCircle reuse)
  ProblemCategory.statistics   => VisualConceptKind.distribution,        // NEW
  ProblemCategory.probability  => VisualConceptKind.probabilityTree,     // NEW
  ProblemCategory.vectors      => VisualConceptKind.vectorArrows,        // NEW
  ProblemCategory.matrices ||
  ProblemCategory.linearAlgebra=> VisualConceptKind.generic,             // Tier-2 cards
  _                            => VisualConceptKind.generic,
};
```

**Process, not decoration.** Each painter reads numeric `params` copied from the **intermediate** verified step expressions — `fractionBar` animates `½+⅓ → 3/6+2/6 → 5/6` (the re-cut), `balanceScale` animates the `2x+5=13 → 2x=8` subtraction, `tangentSlope` uses the derivative value at the marked point. Where only a static answer-picture is possible for a category, it **does not** render as a Pro "Visual Learning" animation — it falls to Tier-2 cards.

**Consistency guard.** `VisualResponseMapper` cross-checks the painter's `answerLatex` against the Solution tab's; on mismatch it drops to Tier-2 cards rather than paint a wrong picture (same posture as the geometry `tryBuild` gate). New painters extend `concept_painter.dart` under the existing `VisualConcept{kind,caption,params,labels,points}` contract; unknown kind → `generic` (no paint crash — the discipline that caught the geometry tick-param crash). `VisualConceptKind` gains the +9 kinds additively. **Pro gate unchanged:** `generateVisualSolution` and `isProProvider` are byte-identical; free users still hit `_openVisualPaywall`.

---

## 8. Numi Tutor Behaviour

Numi is `tutorReply {reply, suggestions}` with `problemLatex` + optional `visualStep` riders. The upgrade makes it a tutor, not a lookup with a Socratic skin (closes efficacy #7):

- **Opens by eliciting.** On a new question Numi's first move asks the student to attempt or predict one thing — it never fires a pre-authored chip answer as its opener.
- **Diagnoses the attempt, not the turn count.** The proxy passes the student's typed attempt; Numi compares it to the step's `commonMistake` and responds to *their* specific error with a question that makes it visible. The ask-vs-tell decision reads what they got wrong, not a stall counter.
- **Chips scaffold the next move, they don't vend answers.** The four moves (Why it works / When to use / When NOT to / Recognise the pattern) surface the *not-yet-covered* conditional knowledge; tapping one seeds a Socratic turn, not an FAQ answer.
- **Golden rule in chat.** On "just tell me," Numi points to the verified answer already on screen and teaches the reasoning — never invents a competing number. Honest states seed "help me work through this" (no `answerLatex`).

**Context (`TutorLaunchContext`, additive):** `learningObjective`, `conceptSummary` (=`concept.body`), `currentStep:StepContext{index, operation, before, after, rule}`, `teachingMove`, and — when present — the student's typed attempt. Step-aware "explain THIS step" long-press carries `StepContext` so Numi answers about that exact transformation. The `{reply, suggestions}` shape is unchanged (a prompt swap + additive riders).

---

## 9. Monetization & Free-vs-Pro

Preserve RevenueCat gating (entitlement `pro`, server-authoritative), keep the **Visual tab strictly Pro** (`generateVisualSolution` unchanged), and **never regress today's free per-step `why`**.

| Tier | `depth` | What ships |
|---|---|---|
| **Free** | `lite` | Teaching header · Problem overview **+ prediction gate** · **Concept overview** (the first-principles hook) · Learning Journey rail · per-step **`operation` + always-visible `why`** · the pivotal-step **`selfExplainPrompt`** (the generation hook) · **Key Takeaway** · **top-3 Common Mistakes (refutation triple)**. |
| **Pro** (`pro`) | `full` | Everything in lite **plus** per-step **`rule` + `explanation` + `commonMistake`** · **method alternatives** · **Practice Ladder** · the entire **Visual Learning tab** (unchanged Pro gate). |
| Either, on failure | `concept_only` | Honest sections only, gated by `honestReason`. Never cached. |

**Why this converts and stays honest:** free gives the *taste* of a real teacher — a concept from first principles, a prediction that makes them think, one "why" per step, a self-explanation moment, and the three traps — dramatically better than today, with **no regression** (free keeps per-step `why`). Pro owns the *depth*: named rules, per-step traps, method trade-offs, an immediate practice ladder, and animated process-metaphors. **Server-authoritative:** `const depthForTier = (await hasPro(uid)) ? "full" : "lite";` — never the client flag. Free users see the Practice Ladder as a paywall teaser (consistent with the already-Pro Adaptive Practice Engine) routing to `_openVisualPaywall`. **Cost-safe:** free and Pro teaching layers cache separately (`teachDocId`), both share one verified core, and cache hits cost $0.

---

## 10. Phased Implementation Plan

Five independently shippable, reversible slices. At **every** phase, `finalAnswer`/`verified`/`methods`/`graph` are produced by the unchanged verify-gated pipeline *before* any teaching code runs. A single server flag `teachingEnabled()` is the kill switch. **Verify gate each phase:** `flutter analyze` · `flutter test` · `cd functions && npm run build` · `npx vitest run`, **plus a full adversarial review** (the workflow that found the ODE collapsed-residual and the `10\frac12`→0.5 parse bug — not a self-review).

**Phase 0 — Schema + backend scaffold, flag OFF.** Add `SOLVE_SCHEMA_VERSION`/`TEACHING_SCHEMA_VERSION`, the interfaces, inline optional `StepData` fields, `deriveTeachingMeta(cls)` in `classify.ts`, empty `teach.ts` (`generateTeaching`→undefined), `validateTeaching`, `buildPracticeLadder`, and the split-cache doc ids. `teachingEnabled()`→false. Server emits `schemaVersion:2` and no `teaching`. Vitest fixtures for `validateTeaching` (accept the two golden fixtures; reject each firewall violation, incl. spelled-out and non-equational numeric leaks). *Risk: none — no call, no route/gate touched.*

**Phase 1 — Backend enrichment (`lite`), flag ON for a small %.** Real `enrichTeaching` (one JSON call, **subsumes narration**, after verify, on the frozen skeleton) + assembler firewall + structural numeric gate. `narrate.ts` retained only as the null-fallback. Warm the top-N teaching docs before flipping. Monitor `validateTeaching` rejection rate, `teaching.enrichFailed`, latency, token spend vs the global daily ceiling. **Adversarial red-team specifically targets spelled-out and non-equational numeric leaks and honest-mode value leaks.** *Risk: teaching LLM cost — mitigated by shared cache, the existing solve rate limit, and a daily-token circuit-breaker that short-circuits enrich to null (verified answers keep shipping).*

**Phase 2 — Client models + graceful render (no new UX).** `teaching_models.dart`, additive `SolutionStep`/`ResultData` fields, total category parser, null-safe `fromJson`. Enriched steps fold onto today's Solution tab; teaching cards render only when non-empty. Dart mapper test against both golden fixtures **and** a v1 payload (must reproduce today's `ResultData`). *Risk: none — no GoRouter/paywall/RevenueCat change.*

**Phase 3 — The Learning Journey UX.** Re-author tab-0 body; new `widgets/teaching/*` incl. the **prediction gate** and pivotal-step **self-explain box**. Preserve `_tabLabels`, `_visualTabIndex=4`, `_selectTab(3)`, the Visual gate, all five tabs. Honest states short-circuit as today, now with `honestReason`-gated cards. Widget tests for two-tier disclosure, prediction gate, reduce-motion, and `brand_contrast_test.dart`. Adversarial review of honest-state rendering (no fabricated step/answer; `read_failure` shows only re-scan). *Risk: touching the Result screen near routing — mitigated by leaving tab structure + Visual gate byte-identical; feature-flag the new body.*

**Phase 4 — Pro depth + Visual teaching engine.** `depthForTier` from entitlement; `full` ships per-step `rule`/`explanation`/`commonMistake` + `methodRationale.alternatives` + validated `practiceLadder`. Extend `VisualConceptKind` (+9), new painters (process animation from intermediate states), deterministic `VisualStrategyResolver`, consistency guard. Painter smoke tests (unknown kind → generic, no crash); vitest for `full` validation + practice `classify()`/dry-run/predicate gating. Adversarial review: can a Pro-depth step or painter contradict the verified answer? *Risk: monetization boundary — mitigated by server-side entitlement + separate free/Pro cache entries.*

**Phase 5 — Numi upgrade.** Swap `SYSTEM_PROMPT` to the elicit-first, diagnose-the-attempt prompt; additive `TutorLaunchContext` fields + the typed-attempt rider; four-move scaffolding chips. `tutor.ts` vitest with a stubbed `JsonCompleter` (never emits a competing number); `flutter test` for chip/context wiring. Adversarial review of the "just tell me the answer" path. *Risk: low — `{reply, suggestions}` unchanged; reversible by reverting the prompt.*

---

## 11. Changes Made From Critique (changelog)

**From the golden-rule / feasibility critique (blockers first):**

- **[BLOCKER #1] Killed the two-`why` byte-equality collision.** `enrichTeaching` now **subsumes** narration (authors `operation`+`why`+teaching in one call); `narrate.ts` is the null-fallback only. No two `why` authors coexist, so no byte-equality gate between them — the layer can actually attach. (Overrides reconciled R12.)
- **[BLOCKER #2] Deleted `stepsByMethodId`.** Narration is inline on `StepData` (R5); `validateTeaching` rewritten to iterate `methods[examPick].steps[i]`; both fixtures rewritten to the inline shape. The firewall is now live code, not dead code.
- **[#3, #8, #16] Structural numeric firewall replaces the defeatable scrub.** Primary defense: reject any narration field with a numeric token (incl. **spelled-out numerals**, canonical-rational-normalized) outside a **per-step** allow-set (`finalAnswer` + this step's own expressions — not the union). Prompt forbids restating arithmetic; fixtures purged of "66 ÷ 5 = 13.2"-style prose. Honest mode uses an empty allow-set (rejects any number). The `=n` regex is now belt-and-suspenders.
- **[#4] Fixed the guaranteed category parse crash.** Wire `category` is a snake_case `TeachingCategory` string with a **total, non-throwing** client parser; `ProblemCategory` stays as the Visual-tier driver via a separate total map. Never `byName`. (Overrides reconciled R2; resolves Open-Q5.)
- **[#5] Real practice-ladder gating.** Dropped `latex.includes(finalAnswer.plain)`; `buildPracticeLadder` runs `classify()` + dry-run `verify()` + a difficulty predicate and drops failing rungs.
- **[#6] One call, not two** (folded into #1).
- **[#7] Split the cache.** Verified core stays under the existing depth-agnostic key (old v1 docs remain valid → no cold-cache spike); teaching cached by `version|depth|language`. Warm top-N before flag flip.
- **[#9] Index alignment made unbreakable.** Assembler always iterates the frozen skeleton as a `Map<stepId, narration>` lookup; `stepIndices` computed deterministically in TS, never accepted from the model.
- **[#10] Dropped `beforeLatex`/`afterLatex` from the wire** — derived client-side; removed their validator branches (a redundant desync surface).
- **[#11] `teaching != null` is the only capability gate;** `schemaVersion` is telemetry.
- **[#12] Journey trimmed** — labels are client constants; wire carries only `summary`+`stepIndices`.

**From the teaching-efficacy critique:**

- **[#1] Added the prediction gate** (`overview.predictionPrompt`) — the answer is revealed after a one-tap prediction (with a "just show the answer" escape), restoring the generation effect the design was built on.
- **[#2] Promoted one `why` to always-visible** on every step — the differentiator is no longer opt-in behind a tap.
- **[#3] Cut the step schema from ten fields to a lean core** — `title`→collapsed into v1 `operation`; deleted `objective` (redundant), `reasoning` (merged into `why`), `learningTip` (moved to `keyTakeaway`); `rule`/`explanation`/`commonMistake` are Pro-depth, one tap deeper.
- **[#4] Added elicited self-explanation** (`selfExplainPrompt` on the engine-marked pivotal step) — the student produces the explanation before `why` reveals.
- **[#5, #14] Scoped partial-coverage categories honestly** and gave them wire homes: `translation[]` for `word_problem`, `decompositionPlan[]` for `multi_part`; proofs/analysis are concept + Numi only; geometry is numeric-only (no constructions/two-column proofs); the probability contradiction is dropped.
- **[#6] Fixed the practice calibration** — `harder` changes sub-skill (`2x²−7x+3=0`, leading coeff ≠ 1) and must pass a difficulty predicate, not merely `verify()`.
- **[#7] Numi elicits and diagnoses** — opens by asking for an attempt, diagnoses the *typed attempt* against `commonMistake` (not a turn counter), chips scaffold rather than vend answers.
- **[#8] Dropped the false "12-year-old" claim for university;** the reading-level gate is now **jargon-coverage** (every 3+ syllable term must be in `definedTerms`) plus tier-scaled sentence length and a human-reviewed exemplar set — FK is advisory only.
- **[#9] Field density is now tier-adaptive** — default visibility keys off `header.difficulty`.
- **[#10] `commonMistakes` is a refutation triple** `{mistake, whyTempting, fix}` (overrides reconciled R7).
- **[#11] `whyMethodChosen` is a property of this problem,** never a speed/quality comparison against an unrun method.
- **[#12] `learningObjective` (forward goal) and `keyTakeaway` (retrieval cue) are defined distinct** and a string-similarity validator rejects paraphrases.
- **[#13] Visual metaphors animate the process** (intermediate verified states); static answer-pictures fall to Tier-2 cards rather than pose as Pro "Visual Learning."
- **[#15] Split honest failure by `honestReason`** — a `read_failure` (bad OCR) suppresses the concept card and shows only a generic re-scan path, so we never confidently teach the concept of a misread problem.

**Net:** the verified `solve→verify` path is untouched and sound. The teaching layer is a single-call, cache-shared, firewalled narration over a frozen skeleton that now *forces generation* (predict, self-explain, attempt-diagnosed tutoring) instead of just delivering more prose — and every field either came through the verify gate or is words that structurally cannot assert a number the gate never saw.