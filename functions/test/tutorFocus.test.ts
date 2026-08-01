import { describe, expect, it } from "vitest";

import { findSpan, isWrappableSpan, verifyTutorFocus } from "../src/proxy/tutorFocus";

const PROBLEM = "x^2 + 8x + 4 = 0";

describe("verifyTutorFocus — the equation itself", () => {
  it("accepts a focus on the problem the student is working on", () => {
    const { focus } = verifyTutorFocus(
      {
        latex: PROBLEM,
        caption: "the coefficient of x",
        spans: [{ text: "8x", role: "operation" }],
      },
      [PROBLEM]
    );
    expect(focus).toEqual({
      latex: PROBLEM,
      caption: "the coefficient of x",
      spans: [{ text: "8x", role: "operation" }],
    });
  });

  // The golden rule. An equation the app never verified is an unverified claim,
  // and a highlight card renders it in the app's own voice.
  it("drops an equation the app never verified", () => {
    const { focus, reason } = verifyTutorFocus(
      {
        latex: "x^2 + 8x + 5 = 0",
        caption: "here",
        spans: [{ text: "5", role: "known" }],
      },
      [PROBLEM]
    );
    expect(focus).toBeNull();
    expect(reason).toMatch(/not verified/);
  });

  it("drops a rearranged form of the verified equation", () => {
    const { focus } = verifyTutorFocus(
      {
        latex: "8x = -x^2 - 4",
        caption: "moved across",
        spans: [{ text: "8x", role: "operation" }],
      },
      [PROBLEM]
    );
    expect(focus).toBeNull();
  });

  // Whitespace carries no meaning in LaTeX, so a spacing difference is the same
  // equation — but what SHIPS is the app's copy, never the model's.
  it("matches through whitespace and returns the app's own copy", () => {
    const { focus } = verifyTutorFocus(
      {
        latex: "x^2+8x+4=0",
        caption: "the constant",
        spans: [{ text: "4", role: "known" }],
      },
      [PROBLEM]
    );
    expect(focus?.latex).toBe(PROBLEM);
  });

  it("drops a focus with no equation, no caption, or nothing to point at", () => {
    expect(verifyTutorFocus({ caption: "x", spans: [] }, [PROBLEM]).focus).toBeNull();
    expect(
      verifyTutorFocus({ latex: PROBLEM, spans: [{ text: "4", role: "known" }] }, [
        PROBLEM,
      ]).focus
    ).toBeNull();
    expect(verifyTutorFocus(null, [PROBLEM]).focus).toBeNull();
    expect(verifyTutorFocus("x = 4", [PROBLEM]).focus).toBeNull();
  });
});

describe("verifyTutorFocus — the answer firewall", () => {
  // In Hint / Solve Together the model is never TOLD the step results, so it
  // can only guess them — and a guess has nothing to match.
  const withoutAnswer = [PROBLEM];
  const withAnswer = [PROBLEM, "x = -2 + \\sqrt{3}", "x^2 + 8x = -4"];

  it("lets a mode that may reveal results highlight one", () => {
    const { focus } = verifyTutorFocus(
      {
        latex: "x^2 + 8x = -4",
        caption: "after moving the 4 across",
        spans: [{ text: "-4", role: "answer" }],
      },
      withAnswer
    );
    expect(focus?.latex).toBe("x^2 + 8x = -4");
  });

  it("drops the same highlight in a mode the results are withheld from", () => {
    const { focus } = verifyTutorFocus(
      {
        latex: "x^2 + 8x = -4",
        caption: "after moving the 4 across",
        spans: [{ text: "-4", role: "answer" }],
      },
      withoutAnswer
    );
    expect(focus).toBeNull();
  });
});

describe("verifyTutorFocus — the spans", () => {
  const ok = (spans: unknown) =>
    verifyTutorFocus({ latex: PROBLEM, caption: "look here", spans }, [PROBLEM]).focus;

  it("drops a span that is not in the equation", () => {
    expect(ok([{ text: "9x", role: "operation" }])).toBeNull();
  });

  it("drops a span with an unknown role rather than colouring it wrongly", () => {
    expect(ok([{ text: "8x", role: "correct" }])).toBeNull();
    expect(ok([{ text: "8x", role: "" }])).toBeNull();
  });

  it("keeps the good spans and drops the bad ones", () => {
    const focus = ok([
      { text: "8x", role: "operation" },
      { text: "nope", role: "known" },
      { text: "4", role: "known" },
    ]);
    expect(focus?.spans).toEqual([
      { text: "8x", role: "operation" },
      { text: "4", role: "known" },
    ]);
  });

  it("gives each repeat its own occurrence instead of stacking them", () => {
    const { focus } = verifyTutorFocus(
      {
        latex: "x + x = 4",
        caption: "both terms",
        spans: [
          { text: "x", role: "unknown" },
          { text: "x", role: "known" },
        ],
      },
      ["x + x = 4"]
    );
    expect(focus?.spans).toHaveLength(2);
  });

  // Spec Part 8: highlight ONLY the current part. Lighting the whole line up is
  // the same as lighting none of it.
  it("drops a span that covers the entire equation", () => {
    expect(ok([{ text: PROBLEM, role: "answer" }])).toBeNull();
    expect(ok([{ text: "x^2+8x+4=0", role: "answer" }])).toBeNull();
  });

  it("caps the number of highlights", () => {
    const focus = ok([
      { text: "x^2", role: "unknown" },
      { text: "8x", role: "operation" },
      { text: "4", role: "known" },
      { text: "0", role: "answer" },
    ]);
    expect(focus?.spans).toHaveLength(3);
  });

  it("returns the app's own characters for a span, not the model's spacing", () => {
    const { focus } = verifyTutorFocus(
      {
        latex: "2 x + 1 = 5",
        caption: "the term",
        spans: [{ text: "2x", role: "unknown" }],
      },
      ["2 x + 1 = 5"]
    );
    expect(focus?.spans[0].text).toBe("2 x");
    expect(focus?.latex.includes(focus!.spans[0].text)).toBe(true);
  });

  it("drops a span that would corrupt the LaTeX", () => {
    const latex = "\\frac{1}{2} + x = 3";
    const drop = (text: string) =>
      verifyTutorFocus({ latex, caption: "c", spans: [{ text, role: "known" }] }, [
        latex,
      ]).focus;
    expect(drop("\\fr")).toBeNull(); // splits a command
    expect(drop("{1")).toBeNull(); // unbalanced brace
    expect(drop("\\frac{1}{2}")).not.toBeNull(); // the whole command is fine
  });
});

describe("isWrappableSpan", () => {
  it("rejects a span that leaves an operator dangling", () => {
    expect(isWrappableSpan("x^2 + 1", 0, 2)).toBe(false); // "x^"
    expect(isWrappableSpan("x^2 + 1", 1, 3)).toBe(false); // "^2"
    expect(isWrappableSpan("x^2 + 1", 0, 3)).toBe(true); // "x^2"
  });

  it("rejects alignment markup, which only parses at the top level", () => {
    const latex = "x &= 1 \\\\ y &= 2";
    expect(isWrappableSpan(latex, 2, 4)).toBe(false); // "&="
  });
});

describe("findSpan", () => {
  it("skips an occurrence another highlight has already claimed", () => {
    expect(findSpan("x + x", "x", [])).toEqual([0, 1]);
    expect(findSpan("x + x", "x", [[0, 1]])).toEqual([4, 5]);
    expect(findSpan("x + x", "x", [[0, 1], [4, 5]])).toBeNull();
  });

  it("finds nothing for an empty needle", () => {
    expect(findSpan("x + 1", "", [])).toBeNull();
    expect(findSpan("x + 1", "   ", [])).toBeNull();
  });
});
