/**
 * The model policy — which OpenAI model runs which workflow, and how each one
 * has to be CALLED.
 *
 * Two things live here because they are two halves of the same decision:
 *
 *   1. **The registry** (`modelFor`) — the accuracy-critical workflows run on the
 *      reasoning tier, the narrate-only workflows on the cheaper tier. Nothing
 *      outside this file may name a model.
 *   2. **The call shape** (`chatParams`) — GPT-5-class reasoning models REJECT the
 *      sampling parameters gpt-4o required. `temperature` accepts only its default
 *      (any other value is a 400), `top_p` is likewise out, and `max_tokens` is
 *      replaced by `max_completion_tokens`, which additionally has to cover the
 *      model's INVISIBLE reasoning tokens. Send the gpt-4o shape to a reasoning
 *      model and every call fails; send the reasoning shape to gpt-4o and the
 *      output budget is ignored. So the shape is derived from the model, once.
 *
 * That second point is why the migration could not be an `.env` edit.
 */
import {
  DEFAULT_MODEL_NARRATION,
  DEFAULT_MODEL_REASONING,
  OPENAI_MODEL_NARRATION,
  OPENAI_MODEL_OVERRIDE,
  OPENAI_MODEL_REASONING,
} from "../config";

/**
 * Read a model parameter, falling back to the compiled-in default.
 *
 * A `defineString` param resolves to the EMPTY STRING at runtime when its
 * variable is absent from the environment — its `default:` only seeds the deploy
 * prompt. Without this fallback, forgetting one line in `.env` would send
 * `model: ""` on every single call and take the whole app down, which is exactly
 * the kind of failure a config change should not be able to cause.
 */
function modelParam(param: { value(): string }, fallback: string): string {
  return param.value().trim() || fallback;
}

/**
 * Every LLM-backed workflow in the app. Adding one here forces a deliberate
 * choice about which tier it belongs to.
 */
export type Workflow =
  // --- Reasoning tier: output IS maths, or decides what the maths is ---------
  /** Vision transcription of the photo — the OCR stage. */
  | "ocr"
  /** Vision interpretation: OCR correction, topic, structured geometry facts. */
  | "scan"
  /** The constrained candidate solve + step narration. */
  | "solve"
  /** The retry after a candidate failed the verification gate. */
  | "solveRetry"
  /** Geometry/visual scene facts for the animated player. */
  | "geometry"
  /** Practice-question generation. */
  | "practice"
  /** Reading a photo of the student's handwritten working. */
  | "handwriting"
  /**
   * A Numi turn that carries the scanned photo. Numi normally narrates already
   * verified maths, but the moment a turn includes an image she is READING the
   * page — the same job the scanner does — so it runs on the reasoning tier
   * with a model proven on this app's vision path.
   */
  | "tutorVision"
  /**
   * The educational quality judge — the gate that decides whether an
   * explanation may be shown at all.
   *
   * It writes no maths and shows no student a word it produced, so on output it
   * looks like a narration job. It is on the reasoning tier anyway, because it
   * is the last thing standing between a subtly wrong lesson and a child, and a
   * gate that is weaker than what it is gating is not a gate.
   */
  | "quality"
  // --- Narration tier: prose ABOUT maths that is already verified ------------
  /** Numi's tutor replies. */
  | "tutor"
  /** The additive teaching-enrichment layer. */
  | "teach";

/**
 * The workflows that only ever narrate an ALREADY-VERIFIED result. They cannot
 * change an answer: Numi is handed the verified solution as fact (the answer
 * firewall), and the teaching layer is additive over a frozen skeleton. Every
 * other workflow is on the reasoning tier by default.
 */
const NARRATION_WORKFLOWS: ReadonlySet<Workflow> = new Set<Workflow>(["tutor", "teach"]);

/** The model that runs [workflow]. The only place a model id is chosen. */
export function modelFor(workflow: Workflow): string {
  const override = OPENAI_MODEL_OVERRIDE.value().trim();
  if (override) return override;
  return NARRATION_WORKFLOWS.has(workflow)
    ? modelParam(OPENAI_MODEL_NARRATION, DEFAULT_MODEL_NARRATION)
    : modelParam(OPENAI_MODEL_REASONING, DEFAULT_MODEL_REASONING);
}

/**
 * How hard the model thinks before answering. More effort = more (billed,
 * invisible) reasoning tokens and more latency, so it is set per workflow rather
 * than globally.
 */
export type ReasoningEffort = "none" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";

/** How much prose the model wraps around its answer. JSON contracts want `low`. */
export type Verbosity = "low" | "medium" | "high";

/**
 * The default reasoning effort per workflow.
 *
 * Reading a photo and proposing a solution are where a mistake becomes a wrong
 * answer in front of a student, so they think hard. `solveRetry` is the second
 * attempt after the verification gate REJECTED a candidate — the first effort
 * level demonstrably was not enough for that problem, so it escalates. Numi and
 * the teaching layer sit low: they are writing prose about numbers that are
 * already proven, and they are on the latency-visible path.
 */
const EFFORT: Record<Workflow, ReasoningEffort> = {
  ocr: "medium",
  scan: "high",
  solve: "high",
  solveRetry: "max",
  geometry: "high",
  practice: "medium",
  handwriting: "high",
  // Reading the page, but on the latency-visible streaming path with a student
  // waiting — between `scan`'s "high" and `tutor`'s "low".
  tutorVision: "medium",
  // Catching a lesson that is plausible-but-wrong is exactly the job that
  // rewards thinking, and it runs off the student's critical path.
  quality: "high",
  tutor: "low",
  teach: "low",
};

/** JSON-contract workflows want terse output; only Numi writes real prose. */
const VERBOSITY: Record<Workflow, Verbosity> = {
  ocr: "low",
  scan: "low",
  solve: "low",
  solveRetry: "low",
  geometry: "low",
  practice: "low",
  handwriting: "low",
  // Both write Numi's voice, so both write like Numi.
  tutorVision: "medium",
  // A verdict, not an essay: scores and one-line findings.
  quality: "low",
  tutor: "medium",
  teach: "medium",
};

/**
 * Extra `max_completion_tokens` headroom, per effort level, to cover reasoning
 * tokens.
 *
 * On a reasoning model `max_completion_tokens` bounds reasoning tokens AND
 * visible output together. Passing the old gpt-4o visible-output budget straight
 * through is the classic migration bug: the model spends the whole allowance
 * thinking, gets cut off before it emits a character, and the caller sees an
 * EMPTY response rather than an error. These floors are deliberately generous —
 * unused headroom is not billed, a truncated solve is a broken feature.
 */
const REASONING_HEADROOM: Record<ReasoningEffort, number> = {
  none: 0,
  minimal: 1_000,
  low: 2_000,
  medium: 6_000,
  high: 12_000,
  xhigh: 20_000,
  max: 32_000,
};

/**
 * Whether [model] is a reasoning model (GPT-5 family and the o-series) rather
 * than a gpt-4o-style sampling model.
 *
 * Matched by family prefix so a point release (`gpt-5.6-sol`, `gpt-5.7-…`) is
 * covered the day it ships without a code change — which is the whole point of
 * the model being a deploy-time parameter. An unrecognised id is treated as
 * LEGACY: that is the conservative default, since sending the legacy shape to a
 * model that wanted the new one fails loudly and immediately, whereas the
 * reverse can silently truncate.
 */
export function isReasoningModel(model: string): boolean {
  return /^(gpt-[5-9]|gpt-1[0-9]|o[1-9])/.test(model.trim());
}

/** Per-call overrides. `temperature`/`maxTokens` keep their gpt-4o meanings. */
export interface ChatTuning {
  /** Sampling temperature. HONORED ONLY on legacy models; ignored on reasoning. */
  temperature?: number;
  /** The VISIBLE output budget. Reasoning headroom is added on top, not taken from it. */
  maxTokens?: number;
  /** Override the workflow's default reasoning effort. */
  effort?: ReasoningEffort;
  /** Override the workflow's default verbosity. */
  verbosity?: Verbosity;
}

/** The model-shaped half of a Chat Completions request body. */
export interface ChatParams {
  model: string;
  temperature?: number;
  max_tokens?: number;
  max_completion_tokens?: number;
  reasoning_effort?: ReasoningEffort;
  verbosity?: Verbosity;
}

/**
 * Build the model + budget + effort half of a Chat Completions request for
 * [workflow], in the shape that workflow's model actually accepts.
 *
 * [defaultTemperature] and [defaultMaxTokens] are the call site's existing
 * gpt-4o values, so a rollback to gpt-4o reproduces today's behaviour byte for
 * byte.
 */
export function chatParams(
  workflow: Workflow,
  defaults: { temperature: number; maxTokens: number },
  tuning: ChatTuning = {}
): ChatParams {
  const model = modelFor(workflow);
  const maxTokens = tuning.maxTokens ?? defaults.maxTokens;

  if (!isReasoningModel(model)) {
    return {
      model,
      temperature: tuning.temperature ?? defaults.temperature,
      max_tokens: maxTokens,
    };
  }

  const effort = tuning.effort ?? EFFORT[workflow];
  return {
    model,
    // NO temperature / top_p: a reasoning model accepts only the default and
    // 400s on anything else. Determinism now comes from the prompt and the
    // effort level — and, for anything that is actually maths, from the
    // substitution verification gate downstream, which never trusted sampling
    // settings in the first place.
    max_completion_tokens: maxTokens + REASONING_HEADROOM[effort],
    reasoning_effort: effort,
    verbosity: tuning.verbosity ?? VERBOSITY[workflow],
  };
}

/**
 * Whether an OpenAI error is a rejection of a REQUEST PARAMETER (a 400 naming an
 * unsupported/unknown parameter) rather than a real failure.
 *
 * This is the migration safety net. The exact parameter surface of a model tier
 * can differ by account and by model revision; if a parameter we send is not
 * accepted, the caller retries ONCE with the minimal legacy-safe body instead of
 * taking the whole feature down. It is deliberately narrow — it matches only
 * parameter complaints, never a content, auth, quota, or rate-limit error.
 */
export function isUnsupportedParameterError(err: unknown): boolean {
  const e = err as { status?: number; message?: string; error?: { message?: string } };
  const status = e?.status;
  if (status !== 400) return false;
  const message = `${e?.message ?? ""} ${e?.error?.message ?? ""}`.toLowerCase();
  return (
    message.includes("unsupported parameter") ||
    message.includes("unsupported value") ||
    message.includes("unknown parameter") ||
    message.includes("not supported with this model") ||
    (message.includes("max_tokens") && message.includes("max_completion_tokens"))
  );
}

/**
 * The last-resort body used when [isUnsupportedParameterError] fires: model and
 * an output budget, nothing else. Every model generation accepts this.
 */
export function fallbackChatParams(params: ChatParams): ChatParams {
  const budget = params.max_completion_tokens ?? params.max_tokens;
  return { model: params.model, max_completion_tokens: budget };
}
