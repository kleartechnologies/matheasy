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
