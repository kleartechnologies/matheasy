/**
 * The model policy is the one place a wrong value silently changes EVERY
 * educational workflow at once, so the registry and the call-shape derivation
 * are pinned here.
 *
 * The migration bug these tests exist to prevent: sending a gpt-4o request body
 * (`temperature` + `max_tokens`) to a GPT-5-class reasoning model, which rejects
 * both — and the subtler one, passing the old visible-output budget straight
 * through as `max_completion_tokens`, where the model spends it all on invisible
 * reasoning tokens and returns empty content.
 */
import { describe, expect, it } from "vitest";

import {
  Workflow,
  chatParams,
  fallbackChatParams,
  isReasoningModel,
  isUnsupportedParameterError,
  modelFor,
} from "../src/lib/models";

const DEFAULTS = { temperature: 0.2, maxTokens: 1500 };

/** Every workflow the registry must have an opinion about. */
const ALL: Workflow[] = [
  "ocr",
  "scan",
  "solve",
  "solveRetry",
  "geometry",
  "practice",
  "handwriting",
  "tutor",
  "teach",
];

describe("modelFor", () => {
  it("routes the accuracy-critical workflows to the reasoning tier", () => {
    for (const w of ["ocr", "scan", "solve", "solveRetry", "geometry", "practice", "handwriting"] as Workflow[]) {
      expect(modelFor(w), w).toBe("gpt-5.6-sol");
    }
  });

  it("routes the narrate-only workflows to the narration tier", () => {
    // These two may only ever describe maths the solver already verified, so
    // they are the only places a cheaper tier cannot cost a student a wrong answer.
    expect(modelFor("tutor")).toBe("gpt-5.6-terra");
    expect(modelFor("teach")).toBe("gpt-5.6-terra");
  });

  it("never returns an empty model id", () => {
    for (const w of ALL) expect(modelFor(w).length, w).toBeGreaterThan(0);
  });
});

describe("isReasoningModel", () => {
  it("recognises the GPT-5 family including point releases", () => {
    for (const m of ["gpt-5", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5-mini", "gpt-6"]) {
      expect(isReasoningModel(m), m).toBe(true);
    }
  });

  it("recognises the o-series", () => {
    for (const m of ["o1", "o3", "o4-mini"]) expect(isReasoningModel(m), m).toBe(true);
  });

  it("treats gpt-4o and unknown ids as legacy sampling models", () => {
    // Conservative by design: the legacy shape fails LOUDLY against a reasoning
    // model, whereas the reasoning shape can silently truncate against a legacy one.
    for (const m of ["gpt-4o", "gpt-4-turbo", "gpt-4o-mini", "some-future-thing"]) {
      expect(isReasoningModel(m), m).toBe(false);
    }
  });
});

describe("chatParams on a reasoning model", () => {
  it("omits temperature entirely — any explicit value is a 400", () => {
    const p = chatParams("solve", DEFAULTS);
    expect(p.temperature).toBeUndefined();
    expect("temperature" in p).toBe(false);
  });

  it("sends max_completion_tokens, never the deprecated max_tokens", () => {
    const p = chatParams("solve", DEFAULTS);
    expect(p.max_tokens).toBeUndefined();
    expect(p.max_completion_tokens).toBeDefined();
  });

  it("budgets reasoning headroom ON TOP of the visible-output budget", () => {
    // The whole point: the caller's 1500 visible tokens must still be available
    // after the model has finished thinking.
    const p = chatParams("solve", DEFAULTS);
    expect(p.max_completion_tokens!).toBeGreaterThan(DEFAULTS.maxTokens);
  });

  it("gives a harder-thinking workflow more headroom than an easier one", () => {
    const retry = chatParams("solveRetry", DEFAULTS).max_completion_tokens!;
    const first = chatParams("solve", DEFAULTS).max_completion_tokens!;
    const narrate = chatParams("teach", DEFAULTS).max_completion_tokens!;
    expect(retry).toBeGreaterThan(first);
    expect(first).toBeGreaterThan(narrate);
  });

  it("escalates effort on the retry that follows a failed verification", () => {
    expect(chatParams("solve", DEFAULTS).reasoning_effort).toBe("high");
    expect(chatParams("solveRetry", DEFAULTS).reasoning_effort).toBe("max");
  });

  it("keeps Numi low-effort and the maths workflows high-effort", () => {
    expect(chatParams("tutor", DEFAULTS).reasoning_effort).toBe("low");
    expect(chatParams("scan", DEFAULTS).reasoning_effort).toBe("high");
    expect(chatParams("handwriting", DEFAULTS).reasoning_effort).toBe("high");
  });

  it("honours a per-call effort override and re-budgets headroom for it", () => {
    const low = chatParams("solve", DEFAULTS, { effort: "low" });
    const high = chatParams("solve", DEFAULTS, { effort: "high" });
    expect(low.reasoning_effort).toBe("low");
    expect(low.max_completion_tokens!).toBeLessThan(high.max_completion_tokens!);
  });

  it("asks for terse output on JSON-contract workflows", () => {
    expect(chatParams("scan", DEFAULTS).verbosity).toBe("low");
    expect(chatParams("tutor", DEFAULTS).verbosity).toBe("medium");
  });

  it("sets a model on every workflow", () => {
    for (const w of ALL) expect(chatParams(w, DEFAULTS).model, w).toBeTruthy();
  });
});

describe("chatParams rollback to a legacy model", () => {
  // Pinning BOTH tiers to gpt-4o is the documented incident rollback; it has to
  // reproduce the pre-migration request byte for byte.
  const legacy = (w: Workflow) => {
    process.env.OPENAI_MODEL = "gpt-4o";
    try {
      return chatParams(w, DEFAULTS);
    } finally {
      delete process.env.OPENAI_MODEL;
    }
  };

  it("restores the gpt-4o request shape exactly", () => {
    const p = legacy("solve");
    expect(p.model).toBe("gpt-4o");
    expect(p.temperature).toBe(DEFAULTS.temperature);
    expect(p.max_tokens).toBe(DEFAULTS.maxTokens);
    expect(p.max_completion_tokens).toBeUndefined();
    expect(p.reasoning_effort).toBeUndefined();
    expect(p.verbosity).toBeUndefined();
  });

  it("still honours a per-call temperature override", () => {
    process.env.OPENAI_MODEL = "gpt-4o";
    try {
      expect(chatParams("scan", DEFAULTS, { temperature: 0.1 }).temperature).toBe(0.1);
    } finally {
      delete process.env.OPENAI_MODEL;
    }
  });
});

describe("isUnsupportedParameterError", () => {
  const err = (status: number, message: string) => ({ status, message });

  it("matches a 400 that rejects a parameter", () => {
    expect(isUnsupportedParameterError(err(400, "Unsupported parameter: 'max_tokens'"))).toBe(true);
    expect(
      isUnsupportedParameterError(err(400, "Unsupported value: 'temperature' does not support 0.2"))
    ).toBe(true);
    expect(isUnsupportedParameterError(err(400, "Unknown parameter: 'verbosity'"))).toBe(true);
  });

  it("reads the nested error.message the SDK sometimes uses", () => {
    expect(
      isUnsupportedParameterError({ status: 400, error: { message: "Unsupported parameter: 'top_p'" } })
    ).toBe(true);
  });

  it("does NOT swallow real failures", () => {
    // A content refusal, an auth problem or a rate limit must propagate — retrying
    // them with a smaller body would just hide the actual cause.
    expect(isUnsupportedParameterError(err(400, "Your request was rejected as a result of our safety system"))).toBe(false);
    expect(isUnsupportedParameterError(err(401, "Incorrect API key provided"))).toBe(false);
    expect(isUnsupportedParameterError(err(429, "Rate limit reached"))).toBe(false);
    expect(isUnsupportedParameterError(err(500, "The server had an error"))).toBe(false);
    expect(isUnsupportedParameterError(undefined)).toBe(false);
    expect(isUnsupportedParameterError(new Error("boom"))).toBe(false);
  });
});

describe("fallbackChatParams", () => {
  it("keeps the model and a budget, and drops everything else", () => {
    const p = fallbackChatParams(chatParams("solve", DEFAULTS));
    expect(p.model).toBe("gpt-5.6-sol");
    expect(p.max_completion_tokens).toBeGreaterThan(0);
    expect(p.temperature).toBeUndefined();
    expect(p.reasoning_effort).toBeUndefined();
    expect(p.verbosity).toBeUndefined();
  });

  it("carries a legacy max_tokens budget across as the completion budget", () => {
    const p = fallbackChatParams({ model: "gpt-4o", temperature: 0.2, max_tokens: 900 });
    expect(p.max_completion_tokens).toBe(900);
  });
});
