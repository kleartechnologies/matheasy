/**
 * SWEEP — Politeknik "Basic Algebra" lecture notes & worksheet (eISBN 978-967-2760-23-8).
 *
 * Every worked example and exercise item in the book, run through the real
 * classify -> solve pipeline with an EMPTY completer (no LLM candidate, no
 * narration) so the number it prints is honest deterministic coverage.
 */
import { describe, expect, it } from "vitest";

import { classify } from "../src/solver/classify";
import { solve } from "../src/proxy/solve";
import type { JsonCompleter } from "../src/solver/narrate";

const noLlm: JsonCompleter = async () => ({});

export const BASIC_ALGEBRA: { id: string; latex: string }[] = [
  // ---- 1.1 worked examples --------------------------------------------
  { id: "ex1.1-1", latex: "2(a - 6) = -a - 13" },
  { id: "ex1.1-2", latex: "\\frac{2x-3}{4} = \\frac{x+1}{5}" },
  { id: "ex1.1-3", latex: "(2x+1)(3x^2 - x + 4)" },
  { id: "ex1.1-4", latex: "xy + 3yx - 4y^2x" },

  // ---- EXERCISE 1.0 : simplify expressions -----------------------------
  { id: "e1.0-i", latex: "3a + 4ba - 2a^2 + 4a^2 + 6a" },
  { id: "e1.0-ii", latex: "a^{-1} + 2a^{-2} + 3a^{-2}" },
  { id: "e1.0-iii", latex: "-2a^2bc^2 - (-6a^2bc^2)" },
  { id: "e1.0-iv", latex: "-\\frac{2y}{3}(9y - 3z + 6x)" },
  { id: "e1.0-v", latex: "8x + 4y - y + 3x + z" },
  { id: "e1.0-vi", latex: "3x^2 + 5 + 4x^3 - x^2 + 2x^3 + 9" },
  { id: "e1.0-vii", latex: "2x^2(4xy - 5) - 8yx^3 + 9x" },
  { id: "e1.0-viii", latex: "3a(2b - 3c + 4d) - 2a(3b - c + 6d)" },
  { id: "e1.0-ix", latex: "6 + 4(3 - x)" },
  { id: "e1.0-x", latex: "2(3x+1) - (2x-3)" },
  { id: "e1.0-xi", latex: "-x(x^2 + 4x - 3)" },
  { id: "e1.0-xii", latex: "2(3p+2) - 3(2p-3)" },

  // ---- 1.2 factorization worked examples -------------------------------
  // The chapter asks for a PRODUCT, and the instruction is what says so.
  { id: "ex1.2-1", latex: "\\text{Factorise } p^2 + 6p - 16" },
  { id: "ex1.2-2", latex: "x^2 - 8x = -15" },
  { id: "ex1.2-3", latex: "5x^2 + 7x - 9 = 4x^2 + x - 18" },
  { id: "ex1.2-4", latex: "\\text{Factorise } ax - ay + 2x - 2y" },

  // ---- EXERCISE 2.0 : solve equations ----------------------------------
  { id: "e2.0-i", latex: "x^2 - 5x - 10 = -4" },
  { id: "e2.0-ii", latex: "3 - x - 2x^2 = 0" },
  { id: "e2.0-iii", latex: "\\frac{2x+7}{3x-2} = x" },
  { id: "e2.0-iv", latex: "x^2 - 2x = 15" },
  { id: "e2.0-v", latex: "p^2 = -10p - 9" },
  { id: "e2.0-vi", latex: "m^2 - 7m + 16 = 4" },
  { id: "e2.0-vii", latex: "3x^2 - 2x(x-3) + 9" },
  { id: "e2.0-viii", latex: "x^2 + 4x - 9 = 2(x-3)" },
  { id: "e2.0-ix", latex: "\\frac{3x(x-1)}{2} = x + 6" },
  { id: "e2.0-x", latex: "4x^2 - 15 = 17x" },
  { id: "e2.0-xi", latex: "5x^2 + 4x = 3(2 - x)" },
  { id: "e2.0-xii", latex: "x - 1 = \\frac{6-3x}{2x}" },

  // ---- 1.3 expansion worked examples -----------------------------------
  { id: "ex1.3-1", latex: "(x+2)(x+3)" },
  { id: "ex1.3-2", latex: "(2x+y)(x-2y)" },
  { id: "ex1.3-3", latex: "(2x+1)^2" },
  { id: "ex1.3-4", latex: "(x-2y)^2" },

  // ---- EXERCISE 3.0 : expansion ----------------------------------------
  { id: "e3.0-i", latex: "(x+2)(3x^2 + 2x - 1)" },
  { id: "e3.0-ii", latex: "-7x(2x-5)" },
  { id: "e3.0-iii", latex: "(4x^2 + \\frac{3}{2}y^2)^2" },
  { id: "e3.0-iv", latex: "2(x+1) - 3(4 - 2x)" },
  { id: "e3.0-v", latex: "2(x+1) = 3(4 - 2x)" },
  { id: "e3.0-vi", latex: "(x+1)^2 = 4(x+4)" },
  { id: "e3.0-vii", latex: "2x(3x - 4y) - (x-y)(x+3y)" },
  { id: "e3.0-viii", latex: "(2y - 3x)(x - 4y)" },
  { id: "e3.0-ix", latex: "(p-q)(p+q) + p(p-q)" },
  { id: "e3.0-x", latex: "2(x - 3y)^2 + xy" },

  // ---- 1.4 fraction worked examples ------------------------------------
  { id: "ex1.4-1", latex: "\\frac{2x+2}{3} - \\frac{x+5}{3}" },
  { id: "ex1.4-2", latex: "\\frac{2x}{7} + \\frac{x}{14}" },
  { id: "ex1.4-3", latex: "\\frac{s}{3t} - \\frac{s}{5}" },
  { id: "ex1.4-4", latex: "\\frac{3}{10x} + \\frac{2}{15x}" },
  { id: "ex1.4-5", latex: "\\frac{3}{x+2} \\times \\frac{2x+4}{9x}" },
  { id: "ex1.4-6", latex: "\\frac{15x}{4x-8} \\div \\frac{3x}{(x-2)^2}" },
  // fraction EQUATIONS
  { id: "ex1.4-a", latex: "\\frac{2x-1}{3} + x = 3" },
  { id: "ex1.4-b", latex: "\\frac{x+1}{2} + \\frac{x+3}{5} = 6" },
  { id: "ex1.4-c", latex: "3 - \\frac{5}{x+1} = 1" },
  { id: "ex1.4-d", latex: "\\frac{1}{x} + \\frac{1}{2x} + \\frac{1}{3x} = 11" },

  // ---- EXERCISE 4.0 : simplify algebraic fractions ---------------------
  { id: "e4.0-i", latex: "\\frac{2h+3}{7k^2} - \\frac{h-4}{7k^2}" },
  { id: "e4.0-ii", latex: "\\frac{2}{p+q} + \\frac{5r^2}{4r}" },
  { id: "e4.0-iii", latex: "\\frac{2a}{3} - \\frac{3a}{5}" },
  { id: "e4.0-iv", latex: "\\frac{1}{6n} + \\frac{n}{3m^2}" },
  { id: "e4.0-v", latex: "\\frac{x}{3} - \\frac{x^2-4}{6x}" },
  { id: "e4.0-vi", latex: "\\frac{x}{3} - \\frac{x+2}{5}" },
  {
    id: "e4.0-vii",
    latex: "\\frac{3b-a}{4a-10b} \\div \\frac{5a^2-15ab}{6a^2-15ab}",
  },
  {
    id: "e4.0-viii",
    latex: "\\frac{p^2-q^2}{3p-q} \\times \\frac{9p-3q}{(p+q)^2}",
  },
  { id: "e4.0-ix", latex: "\\frac{4x}{x-2y} \\div \\frac{10xy}{4x-8y}" },
  { id: "e4.0-x", latex: "\\frac{a^2-9}{3ab} \\times \\frac{6b^2}{a+3}" },
  {
    id: "e4.0-xi",
    latex: "\\frac{(p+q)^2}{12p+9q} \\div \\frac{p^2-q^2}{8p+6q}",
  },
  { id: "e4.0-xii", latex: "\\frac{14ab^2 \\times 3dc^2}{35a^3b^3}" },

  // ---- 2.0 change of subject : worked examples -------------------------
  { id: "ex2.0-1", latex: "2x - 5y = 10 \\quad [x]" },
  { id: "ex2.0-2", latex: "y = \\frac{x+3}{x-8} \\quad [x]" },
  { id: "ex2.0-3", latex: "V = \\frac{1}{3}\\pi r^2 h \\quad [r]" },
  { id: "ex2.0-4", latex: "x = 2 + \\sqrt{\\frac{x}{y}} \\quad [y]" },
  { id: "ex2.0-5", latex: "s = vt - \\frac{1}{2}at^2 \\quad [a]" },

  // ---- EXERCISE 5.0 : make the bracketed variable the subject ----------
  // The book prints the target in brackets after the formula; so do we.
  { id: "e5.0-1", latex: "v = u + at \\quad [t]" },
  { id: "e5.0-2", latex: "4(x-y) = 5y - 3 \\quad [y]" },
  { id: "e5.0-3", latex: "2x + a = b(x-2) \\quad [x]" },
  { id: "e5.0-4", latex: "3y = \\sqrt{5x} - 9 \\quad [x]" },
  { id: "e5.0-5", latex: "\\frac{x}{6} - 5 = y \\quad [x]" },
  { id: "e5.0-6", latex: "\\frac{p}{q} = \\frac{2x}{x+5} \\quad [x]" },
  { id: "e5.0-7", latex: "p = \\frac{3r+7t}{tr} \\quad [t]" },
  { id: "e5.0-8", latex: "m = \\frac{p}{p-5} \\quad [p]" },
  { id: "e5.0-9", latex: "h - 3 = \\frac{\\sqrt{k+1}}{2} \\quad [k]" },
  { id: "e5.0-10", latex: "\\sqrt{\\frac{x+y}{x-y}} = \\frac{1}{3} \\quad [y]" },

  // ---- 3.1 / 3.2 simultaneous worked examples --------------------------
  { id: "ex3.1-1", latex: "5x - 2y = 17, \\quad 6x + 2y = 16" },
  { id: "ex3.1-2", latex: "5x + 2y = 17, \\quad 4x + y = 10" },
  { id: "ex3.1-3", latex: "-2x + 4y = -4, \\quad 5x - 3y = 24" },
  { id: "ex3.2-1", latex: "-2x + y = -16, \\quad -4x - 3y = -12" },
  { id: "ex3.2-2", latex: "-3x - 4y = 6, \\quad 3x + 6y = -12" },
  {
    id: "ex3.2-3",
    latex: "\\frac{x}{3} + \\frac{y}{5} = 7, \\quad \\frac{x}{6} - \\frac{2y}{5} = -4",
  },

  // ---- EXERCISE 6.0 : elimination --------------------------------------
  { id: "e6.0-1", latex: "x - 3y = 1, \\quad 2x + 5y = 35" },
  { id: "e6.0-2", latex: "3x + y = -1, \\quad 2x + 4y = 10" },
  { id: "e6.0-3", latex: "2x + 5y = 1, \\quad 3x - 2y = 30" },
  { id: "e6.0-4", latex: "5x - 6y = 28, \\quad 4x - 4y = 24" },
  { id: "e6.0-5", latex: "6x + 2y = -2, \\quad 4x - 3y = 29" },
  { id: "e6.0-6", latex: "5x - 3y = 33, \\quad 3x - 9y = 63" },

  // ---- EXERCISE 7.0 : substitution -------------------------------------
  { id: "e7.0-1", latex: "x + y = 10, \\quad 2x + y = 17" },
  { id: "e7.0-2", latex: "3x + 2y = 23, \\quad 2x - y = 6" },
  { id: "e7.0-3", latex: "2x - 4y = 2, \\quad 3x + 4y = 23" },
  { id: "e7.0-4", latex: "4x + 2y = 24, \\quad 7x + 2y = 33" },
  { id: "e7.0-5", latex: "3x + 2y = 7, \\quad 2x + 9y = 43" },
  { id: "e7.0-6", latex: "3x + 4y = 11, \\quad 7x - 3y = 1" },
];

describe("Basic Algebra worksheet sweep", () => {
  // Every problem in the book solves AND verifies. This is a corpus regression:
  // if a change drops one, the failure names it rather than quietly lowering a
  // percentage — /tmp/sweep.txt carries the full row-by-row detail.
  it("solves and verifies every problem in the worksheet", async () => {
    const rows: string[] = [];
    let ok = 0;
    for (const p of BASIC_ALGEBRA) {
      let verified = false;
      let answer = "";
      let type = "";
      try {
        const out = await solve(classify(p.latex), noLlm);
        verified = out.verified;
        answer = out.finalAnswer?.plain ?? "(none)";
        type = out.problemType;
      } catch (e) {
        answer = `THREW ${(e as Error).message}`;
      }
      if (verified) ok++;
      rows.push(
        `${verified ? "PASS" : "FAIL"}  ${p.id.padEnd(11)} ${type.padEnd(22)} ${p.latex}  =>  ${answer}`
      );
    }
    const { writeFileSync } = await import("node:fs");
    writeFileSync(
      "/tmp/sweep.txt",
      `${rows.join("\n")}\n\nVERIFIED ${ok}/${BASIC_ALGEBRA.length}\n`
    );
    const failures = rows.filter((r) => r.startsWith("FAIL"));
    expect(failures, failures.join("\n")).toEqual([]);
    expect(ok).toBe(BASIC_ALGEBRA.length);
  }, 120_000);
});
