// Proofs / abstract algebra / real analysis (Phase D) — there is no answer to
// compute-and-verify, so these route to the AI tutor (routeToTutor:true) rather
// than the solver faking a proof or returning a misleading "couldn't verify".
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const NEVER: JsonCompleter = async () => {
  throw new Error("a conceptual prompt must NOT reach the LLM candidate tier");
};

async function run(input: string) {
  const c = classify(input);
  const p = await solve(c, NEVER);
  return { strategy: c.strategy, verified: p.verified, routeToTutor: p.routeToTutor, type: p.problemType };
}

describe("classify + solve — conceptual (route to tutor)", () => {
  const proofs = [
    String.raw`Prove that \sqrt{2} is irrational`,
    String.raw`Prove by induction that 1 + 2 + \dots + n = \frac{n(n+1)}{2}`,
    String.raw`Disprove that every prime is odd`,
    String.raw`Prove that the sum of two even numbers is even`,
  ];
  const algebra = [
    String.raw`Show that Z/6Z is a cyclic group`,
    String.raw`Prove that the kernel of a homomorphism is a normal subgroup`,
    String.raw`Is the map f(x)=2x a group homomorphism?`,
    String.raw`Show that f is injective and surjective`,
  ];
  const analysis = [
    String.raw`Prove that f is uniformly continuous on [0,1]`,
    String.raw`Does the series \sum 1/n^2 converge?`,
    String.raw`Find the supremum of the set \{1 - 1/n\}`,
    String.raw`Show the sequence a_n = 1/n converges`,
  ];

  for (const p of [...proofs, ...algebra, ...analysis]) {
    it(`routes to tutor: ${p.slice(0, 48)}`, async () => {
      const r = await run(p);
      expect(r).toMatchObject({
        strategy: "conceptual",
        verified: false,
        routeToTutor: true,
        type: "conceptual",
      });
    });
  }
});

describe("conceptual detector does NOT hijack solvable problems", () => {
  const solvable = [
    String.raw`x^2 - 5x + 6 = 0`,
    String.raw`\frac{d}{dx}(\sin x)`,
    String.raw`Maclaurin series of e^x to order 4`,
    String.raw`\det \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}`,
    String.raw`Find the 5th term of the arithmetic sequence 2, 4, 6`,
    String.raw`A farmer has 3 fields and 12 cows, how many per field?`,
    String.raw`Find the mean of 2, 4, 6, 8`,
    String.raw`y' = 2y`,
  ];
  for (const s of solvable) {
    it(`not conceptual: ${s.slice(0, 48)}`, () => {
      expect(classify(s).strategy).not.toBe("conceptual");
    });
  }
});
