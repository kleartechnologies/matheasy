/**
 * `ReplyStreamer` — pulling Numi's `reply` out of a JSON document that is still
 * being written (spec Part 18).
 *
 * The interesting cases are all about arriving in pieces: an escape sequence
 * split down the middle, a `"reply"` that isn't the field we want, a document
 * that never finishes. Every test feeds the same document through more than one
 * chunking so the result can't depend on where the network split it.
 */
import { describe, it, expect } from "vitest";

import { ReplyStreamer } from "../src/proxy/tutorStream";

/** Feed `doc` through a streamer in slices of `size`, returning what came out. */
function run(doc: string, size: number): { emitted: string; streamer: ReplyStreamer } {
  const streamer = new ReplyStreamer();
  let emitted = "";
  for (let i = 0; i < doc.length; i += size) {
    emitted += streamer.push(doc.slice(i, i + size));
  }
  return { emitted, streamer };
}

/** Every chunking from one-char-at-a-time to the whole document at once. */
function everyChunking(doc: string): string[] {
  const sizes = [1, 2, 3, 5, 7, 13, doc.length || 1];
  return sizes.map((size) => run(doc, size).emitted);
}

describe("ReplyStreamer", () => {
  it("emits the reply text and nothing else", () => {
    const doc = JSON.stringify({
      reply: "Nice — what is attached to x here?",
      suggestions: ["giveHint"],
      card: null,
    });
    for (const emitted of everyChunking(doc)) {
      expect(emitted).toBe("Nice — what is attached to x here?");
    }
    expect(run(doc, 4).streamer.done).toBe(true);
  });

  it("decodes LaTeX backslashes however the chunks fall", () => {
    // On the wire this is `"$\\frac{1}{2}$"`; the student must get `$\frac{1}{2}$`.
    const doc = JSON.stringify({ reply: "Halve it: $\\frac{1}{2}$ of 8." });
    for (const emitted of everyChunking(doc)) {
      expect(emitted).toBe("Halve it: $\\frac{1}{2}$ of 8.");
    }
  });

  it("decodes quotes, newlines and unicode escapes across chunk boundaries", () => {
    const text = 'She said "yes"\nand ½ of it—exactly.';
    const doc = JSON.stringify({ reply: text });
    for (const emitted of everyChunking(doc)) {
      expect(emitted).toBe(text);
    }
  });

  it("handles an escaped unicode sequence split mid-escape", () => {
    const streamer = new ReplyStreamer();
    let out = streamer.push('{"reply": "a\\u00');
    out += streamer.push('bd b"}');
    expect(out).toBe("a½ b");
    expect(streamer.text).toBe("a½ b");
  });

  it("stops at the closing quote and ignores the rest of the document", () => {
    const doc = JSON.stringify({
      reply: "Two.",
      meta: { mistake: "sign slip", reply: "not this one" },
    });
    for (const emitted of everyChunking(doc)) {
      expect(emitted).toBe("Two.");
    }
  });

  it("finds reply even when the model puts it last", () => {
    const doc = JSON.stringify({
      suggestions: ["giveHint", "showSolution"],
      card: null,
      meta: { conceptsCovered: ["inverse operations"], checkpoint: true },
      reply: "Subtract 5 from both sides.",
    });
    for (const emitted of everyChunking(doc)) {
      expect(emitted).toBe("Subtract 5 from both sides.");
    }
  });

  it("is not hijacked by the word reply inside another value", () => {
    const doc = JSON.stringify({
      meta: { mistake: 'wrote "reply": "wrong" on the page' },
      reply: "The real one.",
    });
    for (const emitted of everyChunking(doc)) {
      expect(emitted).toBe("The real one.");
    }
  });

  it("is not hijacked by a nested reply key", () => {
    const doc = JSON.stringify({
      card: { kind: "quiz", reply: "decoy" },
      reply: "The real one.",
    });
    for (const emitted of everyChunking(doc)) {
      expect(emitted).toBe("The real one.");
    }
  });

  it("keeps what it has when the document is cut off mid-reply", () => {
    // What a max_tokens truncation actually looks like: no closing quote.
    const streamer = new ReplyStreamer();
    const emitted = streamer.push('{"reply": "Start by isolating $x$. First we');
    expect(emitted).toBe("Start by isolating $x$. First we");
    expect(streamer.done).toBe(false);
    expect(streamer.text).toBe("Start by isolating $x$. First we");
  });

  it("emits nothing for a document with no reply field", () => {
    const doc = JSON.stringify({ suggestions: ["giveHint"], card: null });
    for (const emitted of everyChunking(doc)) {
      expect(emitted).toBe("");
    }
  });

  it("emits nothing for a non-string reply", () => {
    for (const emitted of everyChunking('{"reply": null, "card": null}')) {
      expect(emitted).toBe("");
    }
    for (const emitted of everyChunking('{"reply": 42}')) {
      expect(emitted).toBe("");
    }
  });

  it("handles an empty reply without claiming to be unfinished", () => {
    const { emitted, streamer } = run('{"reply": "", "card": null}', 3);
    expect(emitted).toBe("");
    expect(streamer.done).toBe(true);
  });

  it("survives leading whitespace and pretty-printed output", () => {
    const doc = `\n  {\n    "reply" : "Indented.",\n    "card": null\n  }`;
    for (const emitted of everyChunking(doc)) {
      expect(emitted).toBe("Indented.");
    }
  });

  it("ignores empty pushes and pushes after the reply closed", () => {
    const streamer = new ReplyStreamer();
    expect(streamer.push("")).toBe("");
    streamer.push('{"reply": "Done."}');
    expect(streamer.push('{"reply": "again"}')).toBe("");
    expect(streamer.text).toBe("Done.");
  });

  it("accumulates text that matches the sum of the deltas", () => {
    const doc = JSON.stringify({ reply: "One two three four five." });
    const { emitted, streamer } = run(doc, 2);
    expect(streamer.text).toBe(emitted);
    expect(streamer.text).toBe("One two three four five.");
  });
});
