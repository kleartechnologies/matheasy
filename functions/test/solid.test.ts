import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import { parseSolid, solveSolid } from "../src/solver/solid";
import { JsonCompleter } from "../src/solver/narrate";

// The solid engine is DETERMINISTIC: a "show that" claim is proven by putting it
// back into the constraint the problem states, and an optimum has to pass the
// second-derivative test AND beat every other point in the domain. The LLM never
// touches the math — this completer proves it, since any call throws.
const NEVER: JsonCompleter = async () => {
  throw new Error("the solid engine must not call the LLM");
};

/** End-to-end: classify → solve. A declined problem falls through to the
 * llm_candidate tier, where NEVER throws — surfaced here as `declined: true`. */
async function run(latex: string) {
  const cls = classify(latex);
  try {
    const payload = await solve(cls, NEVER);
    return { strategy: cls.strategy, payload, declined: false as const };
  } catch {
    return { strategy: cls.strategy, payload: null, declined: true as const };
  }
}

/** The exact question from the scanned exam page, as the OCR hands it over. */
const GLASS = String.raw`\text{A drinking glass, in the shape of a cylinder, must hold } 200 \text{ m}\ell \text{ of liquid when full. Show that the height of the glass, } h \text{, can be expressed as } h = \frac{200}{\pi r^2}`;

describe("parseSolid — reading the problem", () => {
  it("reads the scanned cylinder question", () => {
    const spec = parseSolid(GLASS)!;
    expect(spec).toBeTruthy();
    expect(spec.shape).toBe("cylinder");
    expect(spec.symbols).toMatchObject({ height: "h", radius: "r" });
    expect(spec.constraint).toMatchObject({ quantity: "volume", value: 200 });
    expect(spec.task.kind).toBe("show_that");
    if (spec.task.kind !== "show_that") throw new Error("unreachable");
    expect(spec.task.target).toBe("h");
    expect(spec.task.claimOf).toBe("dimension");
  });

  it("keeps the millilitre unit that `\\ell` writes", () => {
    // `\ell` is not an ASCII word character, so a `\b`-terminated unit match
    // silently loses the constraint and the whole problem becomes unsolvable.
    const spec = parseSolid(GLASS)!;
    expect(spec.constraint?.value).toBe(200);
  });

  it("binds the radius from the claim when the figure labels it", () => {
    // The symbols are often only on the DIAGRAM, which the OCR cannot read. One
    // unnamed dimension and one free letter in the claim is a forced binding.
    const spec = parseSolid(
      String.raw`A cylinder must hold 200 ml. Show that h = \frac{200}{\pi x^2}`
    )!;
    expect(spec.symbols.radius).toBe("x");
  });

  it("declines when no solid is named", () => {
    expect(
      parseSolid(String.raw`A container holds 200 ml. Show that h = \frac{200}{\pi r^2}`)
    ).toBeNull();
  });

  it("declines when two different solids are named", () => {
    // A cone on top of a cylinder is a composite; neither catalogue formula is it.
    expect(
      parseSolid(
        String.raw`A cylinder topped by a cone holds 200 ml. Show that h = \frac{200}{\pi r^2}`
      )
    ).toBeNull();
  });

  it("declines a self-referential claim", () => {
    expect(
      parseSolid(String.raw`A cylinder holds 200 ml. Show that h = \frac{200}{\pi r^2 h}`)
    ).toBeNull();
  });

  it("does not read a later sub-question's equation as this one's claim", () => {
    const spec = parseSolid(
      String.raw`A cylinder must hold 200 ml. Show that h = \frac{200}{\pi r^2}. \\ Hence A = 2\pi r^2 + \frac{400}{r}`
    )!;
    if (spec.task.kind !== "show_that") throw new Error("unreachable");
    expect(spec.task.claimedLatex).toContain("200");
    expect(spec.task.claimedLatex).not.toContain("400");
  });
});

describe("solveSolid — the substitution gate IS the proof", () => {
  it("proves the scanned cylinder question", () => {
    const out = solveSolid(parseSolid(GLASS)!)!;
    expect(out).toBeTruthy();
    expect(out.answer.latex).toBe("h = \\frac{200}{\\pi r^2}");
    const steps = out.methods[0].steps;
    expect(steps[0].expression).toBe("V = \\pi r^2 h");
    expect(steps[1].expression).toContain("= 200");
    expect(steps.at(-1)!.expression).toBe("h = \\frac{200}{\\pi r^2}");
    expect(steps.at(-1)!.pivotal).toBe(true);
  });

  it("REFUSES a claim with the wrong constant", () => {
    // The single most important test here: substituting 100/πr² into πr²h gives
    // 100, not the 200 the problem states, so this cannot be shown.
    const spec = parseSolid(
      String.raw`A cylinder must hold 200 ml. Show that the height h = \frac{100}{\pi r^2}`
    )!;
    expect(solveSolid(spec)).toBeNull();
  });

  it("REFUSES a claim with the wrong exponent", () => {
    const spec = parseSolid(
      String.raw`A cylinder must hold 200 ml. Show that the height h = \frac{200}{\pi r^3}`
    )!;
    expect(solveSolid(spec)).toBeNull();
  });

  it("REFUSES a claim that is right for a DIFFERENT solid", () => {
    // 600/πr² is the cone answer; on a cylinder it is simply false.
    const spec = parseSolid(
      String.raw`A cylinder must hold 200 ml. Show that the height h = \frac{600}{\pi r^2}`
    )!;
    expect(solveSolid(spec)).toBeNull();
  });

  it("proves the cone version with its own 1/3 factor", () => {
    const out = solveSolid(
      parseSolid(String.raw`A cone has volume 300 cm^3. Show that the height h = \frac{900}{\pi r^2}`)!
    )!;
    expect(out.answer.latex).toBe("h = \\frac{900}{\\pi r^2}");
  });

  it("proves a derived surface area, eliminating the height first", () => {
    const spec = parseSolid(
      String.raw`A closed cylindrical tin must hold 500 cm^3. Show that the total surface area is A = 2\pi r^2 + \frac{1000}{r}`
    )!;
    const out = solveSolid(spec)!;
    expect(out).toBeTruthy();
    const ops = out.methods[0].steps.map((s) => s.operation);
    expect(ops).toContain("Make h the subject");
    expect(out.answer.latex).toBe("A = 2\\pi r^2 + \\frac{1000}{r}");
  });

  it("REFUSES a surface-area claim when the text never says open or closed", () => {
    // An open glass and a sealed can have different areas. "Which one" is not
    // inferable, so it is not inferred.
    const spec = parseSolid(
      String.raw`A cylindrical tin must hold 500 cm^3. Show that the total surface area is A = 2\pi r^2 + \frac{1000}{r}`
    );
    expect(spec === null || solveSolid(spec) === null).toBe(true);
  });

  it("emits LaTeX with no undefined macros", () => {
    // `\cdot` collapsing used to fuse into `\pir` / `\cdotr`, which render as
    // nothing at all — a step the student cannot read is a step that failed.
    const out = solveSolid(
      parseSolid(
        String.raw`A closed cylindrical tin must hold 500 cm^3. Show that the total surface area is A = 2\pi r^2 + \frac{1000}{r}`
      )!
    )!;
    for (const step of out.methods[0].steps) {
      expect(step.expression).not.toMatch(/\\pi[a-zA-Z]/);
      expect(step.expression).not.toMatch(/\\cdot[a-zA-Z]/);
    }
  });
});

describe("solveSolid — optimisation", () => {
  const MIN = String.raw`The total surface area of the glass is A = 2\pi r^2 + \frac{400}{r}. Determine the value of r for which A is a minimum.`;

  it("finds the minimising radius in exact form", () => {
    const out = solveSolid(parseSolid(MIN)!)!;
    expect(out).toBeTruthy();
    // 4πr − 400/r² = 0 ⟹ r³ = 100/π ⟹ r = ∛(100/π) ≈ 3.1692
    expect(out.answer.latex).toContain("\\sqrt[3]{\\frac{100}{\\pi}}");
    expect(out.answer.latex).toContain("3.1692");
  });

  it("runs the second-derivative test as its own step", () => {
    const out = solveSolid(parseSolid(MIN)!)!;
    const ops = out.methods[0].steps.map((s) => s.operation);
    expect(ops).toContain("Confirm it is a minimum");
  });

  it("REFUSES to call a minimum a maximum", () => {
    // Same function, but the question asks for a maximum. It has none — the
    // second-derivative test is positive — so there is nothing honest to return.
    const spec = parseSolid(
      String.raw`The total surface area is A = 2\pi r^2 + \frac{400}{r}. Determine the value of r for which A is a maximum.`
    )!;
    expect(solveSolid(spec)).toBeNull();
  });

  it("declines an objective that still has two unknowns", () => {
    expect(
      parseSolid(
        String.raw`The area is A = 2\pi r h + \frac{400}{r}. Determine the value of r for which A is a minimum.`
      )
    ).toBeNull();
  });
});

describe("routing — the false 'system of equations' message is gone", () => {
  it("classifies the scanned question as a solid derivation, not a system", () => {
    const cls = classify(GLASS);
    expect(cls.strategy).toBe("solid");
    expect(cls.problemType).toBe("formula_derivation");
    // The exact regression: two variables in one equation used to land here.
    expect(cls.problemType).not.toBe("system_of_equations");
  });

  it("returns a verified payload end to end, with no LLM call", async () => {
    const { strategy, payload, declined } = await run(GLASS);
    expect(strategy).toBe("solid");
    expect(declined).toBe(false);
    expect(payload!.verified).toBe(true);
    expect(payload!.finalAnswer.latex).toBe("h = \\frac{200}{\\pi r^2}");
    expect(payload!.methods[0].steps.length).toBeGreaterThanOrEqual(3);
  });

  it("never calls a single equation a system, whatever the engine does with it", () => {
    // The second half of the same defect. Even for a two-variable equation the
    // solid engine declines, the client must not be handed "system_of_equations"
    // — it renders that as "this system may have several solutions", and there
    // is no system. One equation ⇒ `beyond_solver`, which is true.
    const cls = classify(String.raw`\pi r^2 h = 200`);
    expect(cls.problemType).toBe("beyond_solver");
  });

  it("still calls a real system a system", () => {
    const cls = classify(String.raw`y = x^2 + 1 \\ y = x^3 - 2`);
    expect(cls.problemType).toBe("system_of_equations");
  });

  it("a problem the engine cannot prove still routes away honestly", async () => {
    // A wrong claim must NOT come back verified. It falls through to the
    // candidate tier, where the throwing completer stands in for "not answered".
    const { payload } = await run(
      String.raw`A cylinder must hold 200 ml. Show that the height h = \frac{100}{\pi r^2}`
    );
    expect(payload?.verified).not.toBe(true);
  });
});
