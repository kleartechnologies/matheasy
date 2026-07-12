/**
 * Thin OpenAI wrapper used by the solver and tutor proxies.
 *
 * Centralizes client creation and a JSON-mode helper so the callable functions
 * stay focused on their domain prompts. The API key is passed in from Secret
 * Manager by the caller (never hardcoded).
 */
import OpenAI from "openai";
import { logger } from "firebase-functions/v2";

export function createOpenAI(apiKey: string): OpenAI {
  return new OpenAI({ apiKey });
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

export interface ChatJsonOptions {
  /** Lower = more deterministic. Math wants a steady hand. */
  temperature?: number;
  maxTokens?: number;
}

/**
 * Run a chat completion in JSON mode and return the parsed object.
 *
 * The system prompt MUST instruct the model to return JSON (OpenAI's
 * `json_object` response format requires the word "JSON" to appear). Throws if
 * the model returns unparseable content.
 */
export async function chatJson<T>(
  client: OpenAI,
  model: string,
  system: string,
  user: string,
  options: ChatJsonOptions = {}
): Promise<T> {
  const completion = await client.chat.completions.create({
    model,
    temperature: options.temperature ?? 0.2,
    max_tokens: options.maxTokens ?? 1500,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
  });

  const content = completion.choices[0]?.message?.content;
  if (!content) {
    throw new Error("OpenAI returned an empty response");
  }

  try {
    return JSON.parse(content) as T;
  } catch (err) {
    logger.error("Failed to parse OpenAI JSON response", {
      content: content.slice(0, 500),
    });
    throw new Error("OpenAI returned malformed JSON");
  }
}

export interface ChatVisionJsonOptions {
  /** Lower = more deterministic. Reading a photo wants a steady hand. */
  temperature?: number;
  maxTokens?: number;
}

/**
 * Run a vision chat completion in JSON mode and return the parsed object.
 *
 * The user turn carries both `userText` and an image (`imageDataUri`, a
 * `data:<mime>;base64,...` URI). Like [chatJson], the system prompt MUST
 * instruct the model to return JSON (OpenAI's `json_object` response format
 * requires the word "JSON" to appear). Throws if the model returns unparseable
 * or empty content.
 */
export async function chatVisionJson<T>(
  client: OpenAI,
  model: string,
  system: string,
  imageDataUri: string,
  userText: string,
  options: ChatVisionJsonOptions = {}
): Promise<T> {
  const completion = await client.chat.completions.create({
    model,
    temperature: options.temperature ?? 0.1,
    max_tokens: options.maxTokens ?? 700,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: system },
      {
        role: "user",
        content: [
          { type: "text", text: userText },
          { type: "image_url", image_url: { url: imageDataUri } },
        ],
      },
    ],
  });

  const content = completion.choices[0]?.message?.content;
  if (!content) {
    throw new Error("OpenAI returned an empty response");
  }

  try {
    return JSON.parse(content) as T;
  } catch (err) {
    logger.error("Failed to parse OpenAI vision JSON response", {
      content: content.slice(0, 500),
    });
    throw new Error("OpenAI returned malformed JSON");
  }
}
