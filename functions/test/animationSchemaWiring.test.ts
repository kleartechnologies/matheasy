import { afterEach, describe, expect, it, vi } from "vitest";
import { logger } from "firebase-functions/v2";

import * as animation from "../src/solver/animationSchema";
import { classify } from "../src/solver/classify";
import { finalizeAnimationSidecar, solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";
import type { SolvePayload } from "../src/solver/types";

/**
 * A completer that satisfies narrateDeterministic WITHOUT a network call: it
 * returns empty narration, which assembleMethods tolerates (it falls back to
 * humanized operation labels). Deterministic solves still invoke it once, so the
 * solve is fully exercised — only the "why" text is stubbed.
 */
const narrateStub: JsonCompleter = async () => ({});

const FLAG = "ANIMATION_SCHEMA_ENABLED";
function setFlag(on: boolean): void {
  if (on) process.env[FLAG] = "true";
  else delete process.env[FLAG];
}

/** A minimal verified payload carrying a schema — stands in for a cache entry
 * written while the flag was ON (its exact contents don't matter to egress). */
function payloadWithSchema(): SolvePayload {
  return {
    problemLatex: "2x + 3 = 7",
    problemType: "linear_equation",
    finalAnswer: { latex: "x = 2", plain: "x = 2" },
    verified: true,
    methods: [],
    graph: null,
    animationSchema: [
      {
        stepIndex: 0,
        changeType: "SUBTRACT_FROM_BOTH_SIDES",
        beforeLatex: "2x + 3 = 7",
        afterLatex: "2x = 4",
        animationTemplate: "move_across_equals",
        tokens: [],
        explanationKey: "anim.step.SUBTRACT_FROM_BOTH_SIDES",
      },
    ],
  };
}

/** A pre-feature cache entry — a verified payload with NO animationSchema field. */
function payloadWithoutSchema(): SolvePayload {
  return {
    problemLatex: "2x + 3 = 7",
    problemType: "linear_equation",
    finalAnswer: { latex: "x = 2", plain: "x = 2" },
    verified: true,
    methods: [],
    graph: null,
  };
}

describe("animation-schema wiring", () => {
  afterEach(() => {
    setFlag(false);
    vi.restoreAllMocks();
  });

  // (1) Flag OFF → no field, and the verified solve is otherwise unchanged.
  it("flag OFF → payload has no animationSchema; solve output unchanged", async () => {
    setFlag(false);
    const p = await solve(classify("2x + 3 = 7"), narrateStub);
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = 2");
    expect(p.methods.length).toBeGreaterThan(0);
    expect("animationSchema" in p).toBe(false);
    expect(p.animationSchema).toBeUndefined();
  });

  // (2) Flag ON, mathsteps path → the field is present and well-formed.
  it("flag ON + mathsteps path → animationSchema present and well-formed", async () => {
    setFlag(true);
    const p = await solve(classify("2x + 3 = 7"), narrateStub);
    expect(p.verified).toBe(true);
    expect(p.finalAnswer?.plain).toBe("x = 2"); // the verified math is unchanged
    expect(p.animationSchema).toBeDefined();

    const schema = p.animationSchema!;
    expect(Array.isArray(schema)).toBe(true);
    expect(schema.length).toBeGreaterThan(0);
    for (const inst of schema) {
      expect(typeof inst.stepIndex).toBe("number");
      expect(typeof inst.changeType).toBe("string");
      expect(typeof inst.animationTemplate).toBe("string");
      expect(Array.isArray(inst.tokens)).toBe(true);
      expect(typeof inst.explanationKey).toBe("string");
    }
    // Sanity: it's the REAL schema, not a stub — the subtract step moves across =.
    expect(schema.some((i) => i.animationTemplate === "move_across_equals")).toBe(true);
  });

  // (2b) Flag ON but a NON-mathsteps path (arithmetic) → field absent (req 2: never
  // synthesize steps for paths that don't produce equation MsStep[]).
  it("flag ON + non-mathsteps path → animationSchema absent (no synthesis)", async () => {
    setFlag(true);
    const p = await solve(classify("7 + 5 \\times 3"), narrateStub);
    expect(p.verified).toBe(true);
    expect(p.animationSchema).toBeUndefined();
  });

  // (3) THE CRITICAL TEST: flag ON, buildAnimationSchema throws → the verified
  // solve STILL returns normally, the field is absent, and the failure is logged.
  // Proves the sidecar is strictly non-load-bearing.
  it("flag ON + buildAnimationSchema throws → verified solve still returns, field absent, warn logged", async () => {
    setFlag(true);
    const warn = vi.spyOn(logger, "warn").mockImplementation(() => undefined as never);
    const build = vi
      .spyOn(animation, "buildAnimationSchema")
      .mockImplementation(() => {
        throw new Error("injected animation failure (e.g. a firewall throw)");
      });

    const p = await solve(classify("2x + 3 = 7"), narrateStub);

    expect(build).toHaveBeenCalled(); // the wiring really did attempt to build
    expect(p.verified).toBe(true); // ...but the verified solve is unharmed
    expect(p.finalAnswer?.plain).toBe("x = 2");
    expect(p.methods.length).toBeGreaterThan(0);
    expect(p.animationSchema).toBeUndefined(); // sidecar omitted
    expect(warn).toHaveBeenCalled(); // failure logged
  });

  // (4) THE GUARD TEST: flag ON, a pre-feature payload (no schema) → finalize does
  // NOT backfill (no schema added) and does NOT invoke the builder. Pins the
  // no-backfill decision so a future change can't silently re-solve on cache hits.
  it("flag ON + pre-feature payload → NOT backfilled on the egress/hit path", () => {
    setFlag(true);
    const build = vi.spyOn(animation, "buildAnimationSchema");
    const p = payloadWithoutSchema();

    finalizeAnimationSidecar(p, true);

    expect(p.animationSchema).toBeUndefined(); // no backfill
    expect(build).not.toHaveBeenCalled(); // no re-build on the hit path
  });

  // (5) Egress strip: a payload cached while ON, served while OFF, comes back with
  // the field stripped — a true kill switch even against a stale cached schema.
  it("flag OFF + payload cached while ON → animationSchema stripped on egress", () => {
    const p = payloadWithSchema();
    expect(p.animationSchema).toBeDefined(); // present as if from cache

    finalizeAnimationSidecar(p, false);

    expect(p.animationSchema).toBeUndefined();
    expect("animationSchema" in p).toBe(false);
  });
});
