// Remainders — "find the remainder when n² + 4 is divided by 7 for n = 3", and
// the family around it: `x mod m`, the last digit of a power, the last two
// digits. Prose with an expression buried in it, so the whole family reached
// the tutor.
//
// The answer forms the number and divides, in BigInt — 7^100 is the actual
// integer, not a float that lost its low digits twenty orders of magnitude ago,
// and the low digits ARE the answer. The gate never forms the number at all: it
// reduces modulo m at every step, so for a big power the two routes don't even
// handle numbers of the same size. Then q·m + r = x is checked exactly.
import { describe, expect, it } from "vitest";
import { classify } from "../src/solver/classify";
import { solveDeterministic } from "../src/solver/deterministic";

function run(latex: string): { type: string; answer: string | null } {
  const cls = classify(latex);
  const cand = solveDeterministic(cls);
  return {
    type: cls.problemType,
    answer: cand && cand.verify() ? (cand.answer.plain ?? null) : null,
  };
}

describe("the sheet question", () => {
  it("a value substituted in first", () => {
    // 3² + 4 = 13 = 1×7 + 6.
    const r = run(
      String.raw`\text{Find the remainder when } n^2 + 4 \text{ is divided by } 7 \text{ for } n = 3`
    );
    expect(r.type).toBe("modular_arithmetic");
    expect(r.answer).toBe("6");
  });

  it("two values, both fixed by the question", () => {
    const r = run(
      String.raw`\text{Find the remainder when } a^2 + b \text{ is divided by } 9 \text{ for } a = 4 \text{ and } b = 2`
    );
    expect(r.answer).toBe("0");
  });

  it("a plain integer", () => {
    const r = run(String.raw`\text{Find the remainder when } 1234 \text{ is divided by } 7`);
    expect(r.answer).toBe("2");
  });

  it("a negative number takes the least non-negative residue", () => {
    // −17 = −4×5 + 3. Not −2: a remainder is in [0, m).
    const r = run(String.raw`\text{Find the remainder when } -17 \text{ is divided by } 5`);
    expect(r.answer).toBe("3");
  });
});

describe("the powers, where a double would have lost the answer", () => {
  it("7^100 mod 13", () => {
    // 7^100 has 85 digits. A double keeps about 16 of them, and the ones it
    // throws away are the ones this question is about.
    const r = run(String.raw`\text{Find the remainder when } 7^{100} \text{ is divided by } 13`);
    expect(r.answer).toBe("9");
  });

  it("the last digit of 7^100", () => {
    const r = run(String.raw`\text{Find the last digit of } 7^{100}`);
    expect(r.answer).toBe("1");
  });

  it("the last two digits of 3^1000", () => {
    const r = run(String.raw`\text{Find the last two digits of } 3^{1000}`);
    expect(r.answer).toBe("1");
  });

  it("written as `mod`", () => {
    const r = run(String.raw`\text{Find } 2^{10} \bmod 11`);
    expect(r.answer).toBe("1");
  });

  it("2^64 mod 1000 — past every safe integer", () => {
    // 2^64 = 18446744073709551616, which no double can hold exactly.
    const r = run(String.raw`\text{Find the remainder when } 2^{64} \text{ is divided by } 1000`);
    expect(r.answer).toBe("616");
  });
});

describe("what it declines rather than guess", () => {
  it("a variable the question never fixed", () => {
    const r = run(String.raw`\text{Find the remainder when } n^2 + 4 \text{ is divided by } 7`);
    expect(r.type).not.toBe("modular_arithmetic");
  });

  it("dividing by 1 is not a remainder question", () => {
    const r = run(String.raw`\text{Find the remainder when } 13 \text{ is divided by } 1`);
    expect(r.type).not.toBe("modular_arithmetic");
  });

  it("a non-integer expression has no remainder", () => {
    const r = run(String.raw`\text{Find the remainder when } \sin(2) \text{ is divided by } 7`);
    expect(r.type).not.toBe("modular_arithmetic");
  });
});

describe("no regression — the arithmetic that already worked", () => {
  it("a plain quadratic is untouched", () => {
    const r = run(String.raw`\text{Solve } x^2 - 5x + 6 = 0`);
    expect(r.type).toBe("quadratic_equation");
    expect(r.answer).toBe("x = 2 or x = 3");
  });

  it("a division with no remainder asked about stays arithmetic", () => {
    expect(classify(String.raw`\frac{1234}{7}`).problemType).not.toBe("modular_arithmetic");
  });

  it("'divided by' inside a word problem is not hijacked", () => {
    expect(
      classify(String.raw`\text{A cake is divided by } 8 \text{ friends. How much does each get?}`)
        .problemType
    ).not.toBe("modular_arithmetic");
  });
});
