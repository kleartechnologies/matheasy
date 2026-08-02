/**
 * CIRCLE CORPUS SNAPSHOT — the permanent form of the HEAD-differential gate.
 *
 * THE BLIND SPOT THIS CLOSES. Every probe set is a list of cases some earlier round already
 * thought of, so it can only guard those. Broadening a reader to rescue a solvable problem
 * quietly re-opens a trap whose ONE known phrasing happens not to be in the set — and the whole
 * suite stays green while it happens. That is exactly how two confident-wrong answers were
 * re-introduced in ROUND 32 with 916 tests passing: a subject-free "at the centre of a circular
 * X" guard swallowed every genuine sweep, and a "cover the floor" relation started answering an
 * area to a question asked in metres. Neither had a probe, because neither had ever failed.
 *
 * The fix is to stop asking "do the known cases still pass?" and start asking "did ANY answer
 * change?". `circle-corpus.ts` is a mechanical cross-product — each trap family × the synonym
 * sets the guards actually key on, the same trap said a hundred ways — and this file pins the
 * engine's answer to every one of them. A change that alters any answer fails here and has to
 * be looked at and re-baselined ON PURPOSE.
 *
 * TO RE-BASELINE: run `npx vitest run test/circleCorpus.test.ts -u`. Read the diff before you
 * commit it. A `null → value` line is the dangerous direction: production used to decline that
 * input and now answers it, which is a candidate confident-wrong answer that did not exist
 * before. A `value → null` line is honest but is lost coverage.
 */
import { describe, expect, it } from "vitest";

import { parseCircle, solveCircle } from "../src/solver/circle";
import { CORPUS } from "./circle-corpus";

const answer = (text: string): string | null => {
  try {
    const shape = parseCircle(text);
    if (!shape) return null;
    return solveCircle(shape)?.answer.plain ?? null;
  } catch {
    return null;
  }
};

describe("circle — adversarial corpus snapshot", () => {
  it("pins the engine's answer to every generated case", () => {
    const snapshot: Record<string, string | null> = {};
    for (const c of CORPUS) snapshot[c.text] = answer(c.text);
    expect(snapshot).toMatchSnapshot();
  });

  // The families where declining is unambiguously right whatever the wording. These are
  // asserted rather than snapshotted: an answer here is a golden-rule violation, not a diff.
  it("never answers a case from a must-decline family", () => {
    const answered = CORPUS.filter((c) => c.mustDecline && answer(c.text) !== null);
    expect(answered.map((c) => `[${c.family}] ${c.text} → ${answer(c.text)}`)).toEqual([]);
  });

  // …and the floor beneath all of it: over-declining is honest, but a plain circle must solve.
  it("still answers every plain, solvable circle", () => {
    const plain = CORPUS.filter((c) => c.family === "plain-solvable");
    expect(plain.length).toBeGreaterThan(50);
    expect(plain.filter((c) => answer(c.text) === null).map((c) => c.text)).toEqual([]);
  });
});
