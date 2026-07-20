/**
 * Multilingual learning: turns the learner's BCP-47 language code (sent on every
 * AI request as `language`) into an LLM writing-language directive.
 *
 * The rule that makes the whole feature safe: instructional PROSE is written in
 * the learner's language; mathematical NOTATION is never translated — numbers,
 * variables, operators, function names (sin/cos/log), symbols (π/∫/Σ) and LaTeX
 * stay universal. Adding a language = one entry here + the client `AppLanguage`.
 */

const LANGUAGE_NAMES: Record<string, string> = {
  en: "English",
  ar: "Arabic (العربية)",
  "zh-Hans": "Simplified Chinese (简体中文)",
  "zh-Hant": "Traditional Chinese (繁體中文)",
  hr: "Croatian (Hrvatski)",
  cs: "Czech (Čeština)",
  da: "Danish (Dansk)",
  nl: "Dutch (Nederlands)",
  fi: "Finnish (Suomi)",
  fr: "French (Français)",
  de: "German (Deutsch)",
  he: "Hebrew (עברית)",
  hi: "Hindi (हिन्दी)",
  hu: "Hungarian (Magyar)",
  "id-ID": "Bahasa Indonesia",
  it: "Italian (Italiano)",
  ja: "Japanese (日本語)",
  ko: "Korean (한국어)",
  "ms-MY": "Bahasa Melayu (Malay)",
  nb: "Norwegian Bokmål (Norsk Bokmål)",
  fa: "Persian (فارسی)",
  pl: "Polish (Polski)",
  pt: "Portuguese (Português)",
  ro: "Romanian (Română)",
  ru: "Russian (Русский)",
  sk: "Slovak (Slovenčina)",
  es: "Spanish (Español)",
  sv: "Swedish (Svenska)",
  th: "Thai (ไทย)",
  tr: "Turkish (Türkçe)",
  uk: "Ukrainian (Українська)",
  vi: "Vietnamese (Tiếng Việt)",
};

/** The human language name for a code, defaulting to English. */
export function languageName(code?: string): string {
  return LANGUAGE_NAMES[code ?? "en"] ?? "English";
}

/**
 * The effective CONTENT language a code resolves to. An unsupported code produces
 * English content (languageDirective returns "" for it), so it must share the
 * "en" cache bucket — never its own — or a later deploy that adds that code would
 * serve stale English. Use this to key any language-namespaced AI cache.
 */
export function contentLanguage(code?: string): string {
  return code && LANGUAGE_NAMES[code] ? code : "en";
}

/**
 * A system-prompt directive that makes the model write ALL instructional text in
 * the learner's language while keeping math notation universal. Returns "" for
 * English (the default) so existing English prompts are byte-unchanged.
 *
 * Append it to a callable's system prompt: `SYSTEM_PROMPT + languageDirective(language)`.
 */
export function languageDirective(code?: string): string {
  if (!code || code === "en" || !LANGUAGE_NAMES[code]) return "";
  const name = LANGUAGE_NAMES[code];
  return `

LANGUAGE — the learner reads ${name}. Write ALL instructional and explanatory text (prompts, step descriptions, hints, explanations, answer options, feedback, encouragement) in ${name}.
NEVER translate or alter mathematical notation — keep it EXACTLY as-is, in universal form: numbers, variables (x, y, θ), operators (+ − × ÷ = < >), exponents (x²), function names (sin, cos, tan, log, ln), symbols (π, ∫, Σ, √, ∞, °, %), matrices, units, and ALL LaTeX. Only the surrounding words change to ${name}. Do NOT wrap or explain your language choice; simply write in ${name}.`;
}
