/**
 * Incremental extraction of Numi's `reply` out of a JSON response that is still
 * being generated (spec Part 18 — first token in under two seconds).
 *
 * `tutorReply` asks the model for a JSON object, which is normally an all-or-
 * nothing thing: you cannot `JSON.parse` half a document, so the student stares
 * at a typing dot until the last token lands. This scanner walks the raw text as
 * it streams and hands back the decoded characters of the `reply` value only —
 * so the words appear as they are written, while `card`, `meta` and everything
 * else still go through the normal parse-and-verify path at the end.
 *
 * It is a real (if minimal) JSON scanner rather than a regex: it tracks string
 * and nesting state, so a `"reply"` sitting inside another value can't hijack
 * it, and it survives the model reordering its keys. It decodes escapes,
 * including `\uXXXX` split across chunk boundaries — LaTeX arrives as `\\frac`
 * on the wire and must reach the student as `\frac`.
 */

const SIMPLE_ESCAPES: Record<string, string> = {
  '"': '"',
  "\\": "\\",
  "/": "/",
  b: "\b",
  f: "\f",
  n: "\n",
  r: "\r",
  t: "\t",
};

type Phase = "seek" | "value" | "done";

export class ReplyStreamer {
  private phase: Phase = "seek";

  // ---- structural scan (phase "seek") ----
  private depth = 0;
  private inString = false;
  private escaped = false;
  private token = "";
  private lastKey = "";
  /** The next string to OPEN is the value of `reply`. */
  private expectValue = false;

  // ---- value decode (phase "value") ----
  private valueEscaped = false;
  /** Partial `\uXXXX` carried across a chunk boundary. */
  private unicode: string | null = null;
  private decoded = "";

  /** Everything of `reply` decoded so far. */
  get text(): string {
    return this.decoded;
  }

  /** True once the `reply` string has been closed — later keys are ignored. */
  get done(): boolean {
    return this.phase === "done";
  }

  /**
   * Feed the next slice of raw JSON. Returns the newly decoded characters of
   * `reply` (empty when this slice was structure, another field, or a partial
   * escape).
   */
  push(chunk: string): string {
    if (this.phase === "done" || !chunk) return "";
    const before = this.decoded.length;
    for (const char of chunk) {
      if (this.phase === "value") {
        if (!this.consumeValueChar(char)) break;
      } else {
        this.consumeSeekChar(char);
      }
    }
    return this.decoded.slice(before);
  }

  /** Scan structure until the opening quote of `reply`'s value. */
  private consumeSeekChar(char: string): void {
    if (this.inString) {
      if (this.escaped) {
        this.escaped = false;
        this.token += char;
      } else if (char === "\\") {
        this.escaped = true;
      } else if (char === '"') {
        this.inString = false;
        this.lastKey = this.token;
        this.token = "";
      } else {
        this.token += char;
      }
      return;
    }

    switch (char) {
      case '"':
        // A string is opening. If the last `key:` we saw was `reply`, this is
        // the value we came for.
        if (this.expectValue) {
          this.expectValue = false;
          this.phase = "value";
          return;
        }
        this.inString = true;
        this.token = "";
        return;
      case ":":
        // Only a top-level key names the field we want; `reply` nested inside a
        // card or meta object is somebody else's business.
        this.expectValue = this.depth === 1 && this.lastKey === "reply";
        return;
      case "{":
      case "[":
        this.depth++;
        this.expectValue = false;
        return;
      case "}":
      case "]":
        this.depth--;
        this.expectValue = false;
        return;
      case ",":
        this.expectValue = false;
        return;
      default:
        // Whitespace and the leading characters of a non-string value (`null`,
        // a number) — nothing to track.
        return;
    }
  }

  /**
   * Decode one character of the `reply` string. Returns false once the string
   * has closed, so the caller stops feeding this chunk.
   */
  private consumeValueChar(char: string): boolean {
    if (this.unicode !== null) {
      this.unicode += char;
      if (this.unicode.length === 4) {
        const code = Number.parseInt(this.unicode, 16);
        // A malformed escape is dropped rather than rendered as garbage — the
        // sentence around it still reads.
        if (Number.isFinite(code) && /^[0-9a-fA-F]{4}$/.test(this.unicode)) {
          this.decoded += String.fromCharCode(code);
        }
        this.unicode = null;
      }
      return true;
    }

    if (this.valueEscaped) {
      this.valueEscaped = false;
      if (char === "u") {
        this.unicode = "";
        return true;
      }
      this.decoded += SIMPLE_ESCAPES[char] ?? char;
      return true;
    }

    if (char === "\\") {
      this.valueEscaped = true;
      return true;
    }

    if (char === '"') {
      this.phase = "done";
      return false;
    }

    this.decoded += char;
    return true;
  }
}
