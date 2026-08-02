/**
 * Thin OpenAI wrapper used by the solver and tutor proxies.
 *
 * Centralizes client creation and a JSON-mode helper so the callable functions
 * stay focused on their domain prompts. The API key is passed in from Secret
 * Manager by the caller (never hardcoded).
 */
import OpenAI from "openai";
import { logger } from "firebase-functions/v2";

import {
  ChatParams,
  ChatTuning,
  Workflow,
  chatParams,
  fallbackChatParams,
  isUnsupportedParameterError,
} from "./models";

export function createOpenAI(apiKey: string): OpenAI {
  return new OpenAI({ apiKey });
}

/**
 * Send one Chat Completions request for [workflow] and return the message text.
 *
 * Everything model-specific is concentrated here:
 *
 *   • the model, effort, verbosity and token budget come from the registry, so
 *     no call site names a model;
 *   • a 400 that rejects a PARAMETER (not the content) is retried once with the
 *     minimal legacy-safe body — the migration net, loudly logged so a
 *     misconfigured tier shows up in the logs instead of hiding as a fallback;
 *   • a `length` finish is reported as truncation rather than as the misleading
 *     "empty response". On a reasoning model an over-tight budget is spent on
 *     invisible reasoning tokens and the content comes back EMPTY, which is
 *     otherwise indistinguishable from a refusal.
 */
async function completeText(
  client: OpenAI,
  workflow: Workflow,
  messages: OpenAI.Chat.ChatCompletionMessageParam[],
  defaults: { temperature: number; maxTokens: number },
  tuning: ChatTuning
): Promise<string> {
  const params = chatParams(workflow, defaults, tuning);

  const send = async (p: ChatParams) =>
    client.chat.completions.create({
      ...p,
      response_format: { type: "json_object" },
      messages,
    } as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming);

  let completion;
  try {
    completion = await send(params);
  } catch (err) {
    if (!isUnsupportedParameterError(err)) throw err;
    const retry = fallbackChatParams(params);
    logger.warn("openai.parameterRejected — retrying with the minimal body", {
      workflow,
      model: params.model,
      err: String(err),
    });
    completion = await send(retry);
  }

  const choice = completion.choices[0];
  const content = choice?.message?.content;
  if (!content) {
    if (choice?.finish_reason === "length") {
      // Almost always a budget that did not cover the model's reasoning tokens.
      logger.error("openai.truncated — raise the token budget for this workflow", {
        workflow,
        model: params.model,
        budget: params.max_completion_tokens ?? params.max_tokens,
        usage: completion.usage,
      });
      throw new Error("OpenAI response was truncated before any content");
    }
    throw new Error("OpenAI returned an empty response");
  }
  return content;
}

export interface ModerationVerdict {
  flagged: boolean;
  categories: string[];
}

/**
 * COPPA safety gate for the vision path (spec §10). Screens an image with
 * OpenAI's free `omni-moderation-latest` model BEFORE the paid vision call so
 * inappropriate content is never processed into an answer.
 *
 * Deliberately fails OPEN (returns `flagged:false`) on any moderation-service
 * error: an outage must not take the whole scanner down, and the caller's
 * math-only output contract is the backstop — a flagged image that slipped
 * through can still only ever come back as `isMath:false` → rejected. It fails
 * CLOSED (`flagged:true`) only on a real, positive moderation flag.
 */
export async function moderateImage(
  client: OpenAI,
  imageDataUri: string
): Promise<ModerationVerdict> {
  try {
    const result = await client.moderations.create({
      model: "omni-moderation-latest",
      input: [{ type: "image_url", image_url: { url: imageDataUri } }],
    });
    const first = result.results?.[0];
    if (!first) return { flagged: false, categories: [] };
    const categories = Object.entries(first.categories ?? {})
      .filter(([, on]) => on === true)
      .map(([name]) => name);
    return { flagged: first.flagged === true, categories };
  } catch (err) {
    logger.warn("Image moderation unavailable — proceeding on the math-only backstop", {
      err: String(err),
    });
    return { flagged: false, categories: [] };
  }
}

/** Parse a JSON-mode response, logging the offending text on failure. */
function parseJson<T>(content: string, what: string): T {
  try {
    return JSON.parse(content) as T;
  } catch (err) {
    logger.error(`Failed to parse OpenAI ${what} response`, {
      content: content.slice(0, 500),
    });
    throw new Error("OpenAI returned malformed JSON");
  }
}

export type ChatJsonOptions = ChatTuning;

/**
 * Run a chat completion in JSON mode and return the parsed object.
 *
 * The system prompt MUST instruct the model to return JSON (OpenAI's
 * `json_object` response format requires the word "JSON" to appear). Throws if
 * the model returns unparseable content.
 */
export async function chatJson<T>(
  client: OpenAI,
  workflow: Workflow,
  system: string,
  user: string,
  options: ChatJsonOptions = {}
): Promise<T> {
  const content = await completeText(
    client,
    workflow,
    [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
    { temperature: 0.2, maxTokens: 1500 },
    options
  );
  return parseJson<T>(content, "JSON");
}

export type ChatVisionJsonOptions = ChatTuning;

/** One image in a vision turn, with a label the model can refer to. */
export interface VisionImage {
  /** A `data:<mime>;base64,...` URI. */
  dataUri: string;
  /** What this image IS, e.g. "ORIGINAL PHOTO" — prefixed to it in the turn. */
  label?: string;
}

/**
 * Run a vision chat completion in JSON mode over ONE OR MORE images.
 *
 * Multiple images are how the scanner gives the model every view of the same
 * page — the original photo AND the contrast-enhanced render — so it can fall
 * back to whichever is legible where the other is not. Each image is preceded by
 * its own text label so the model knows which is which; without labels a second
 * image reads as a second, unrelated problem.
 *
 * Like [chatJson], the system prompt MUST instruct the model to return JSON.
 */
export async function chatVisionJson<T>(
  client: OpenAI,
  workflow: Workflow,
  system: string,
  images: string | VisionImage[],
  userText: string,
  options: ChatVisionJsonOptions = {}
): Promise<T> {
  const list: VisionImage[] =
    typeof images === "string" ? [{ dataUri: images }] : images;
  if (list.length === 0) {
    throw new Error("chatVisionJson requires at least one image");
  }

  const content: OpenAI.Chat.ChatCompletionContentPart[] = [
    { type: "text", text: userText },
  ];
  for (const image of list) {
    if (image.label) content.push({ type: "text", text: image.label });
    content.push({ type: "image_url", image_url: { url: image.dataUri } });
  }

  const text = await completeText(
    client,
    workflow,
    [
      { role: "system", content: system },
      { role: "user", content },
    ],
    { temperature: 0.1, maxTokens: 700 },
    options
  );
  return parseJson<T>(text, "vision JSON");
}
