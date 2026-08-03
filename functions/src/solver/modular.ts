/**
 * Remainders — "find the remainder when n² + 4 is divided by 7 for n = 3", and
 * the family around it: `x mod m`, the last digit of a power, the last two
 * digits.
 *
 * These read as prose with an equation buried in them, so the whole family went
 * to the tutor.
 *
 * TWO ROUTES, and they share no step:
 *  • The ANSWER forms the number and divides: `x = qm + r`, in BigInt, so
 *    `7^100` is the actual integer and not a float that lost its low digits
 *    twenty orders of magnitude ago.
 *  • The GATE never forms the number at all. It reduces mod m as it goes —
 *    every add, multiply and power taken modulo m at each step — so the two
 *    routes have no arithmetic in common, and for a big power they don't even
 *    handle numbers of the same size. Then `q·m + r = x` is checked exactly.
 *
 * BigInt throughout, because the interesting questions here are exactly the
 * ones a double cannot represent.
 */
import { MathNode, parse } from "mathjs";

import { latexToAscii, unwrapProse } from "./latex";
import { FinalAnswer, RawStep, SolveCandidate } from "./types";

const MAX_MODULUS = 1_000_000_000;
const MAX_EXPONENT = 100_000;

export interface ModularQuery {
  /** The integer expression, as ascii. */
  exprAscii: string;
  /** Values the question fixes: "for n = 3". */
  substitutions: Record<string, bigint>;
  modulus: bigint;
  /** How the question put it, for the working. */
  label: string;
}

// ---------------------------------------------------------------------------
// parsing
// ---------------------------------------------------------------------------

const DIGIT_WORDS = new Map<string, number>([
  ["one", 1], ["two", 2], ["three", 3], ["four", 4], ["five", 5], ["six", 6],
]);

export function parseModular(rawLatex: string): ModularQuery | null {
  const prose = unwrapProse(rawLatex);

  let exprLatex: string | null = null;
  let modulus: bigint | null = null;
  let label = "";

  const remainder =
    /\bremainder\s+(?:when|of)\s+([\s\S]+?)\s+(?:is\s+)?divided\s+by\s+(\d+)/i.exec(prose) ??
    /\b([\s\S]+?)\s+is\s+divided\s+by\s+(\d+)[\s\S]*\bremainder\b/i.exec(prose);
  if (remainder) {
    exprLatex = remainder[1];
    modulus = BigInt(remainder[2]);
    label = `\\text{remainder mod } ${remainder[2]}`;
  }

  if (!exprLatex) {
    const mod = /([\s\S]+?)\s*(?:\\pmod\s*\{?|\\bmod\s*|\bmod(?:ulo)?\b)\s*\{?\s*(\d+)\s*\}?/i.exec(prose);
    if (mod && /\bremainder\b|\bmod|\bwhat\b|\bfind\b|\bcompute\b|\bcalculate\b|\bevaluate\b/i.test(prose)) {
      exprLatex = mod[1];
      modulus = BigInt(mod[2]);
      label = `\\text{mod } ${mod[2]}`;
    }
  }

  if (!exprLatex) {
    // "the last digit of 7^100" is `mod 10`; "the last two digits" is `mod 100`.
    const digits = /\blast\s+(\d+|one|two|three|four|five|six)?\s*digits?\s+of\s+([\s\S]+)$/i.exec(prose);
    if (digits) {
      const n = digits[1] ? DIGIT_WORDS.get(digits[1].toLowerCase()) ?? parseInt(digits[1], 10) : 1;
      if (!Number.isInteger(n) || n < 1 || n > 9) return null;
      exprLatex = digits[2];
      modulus = 10n ** BigInt(n);
      label = `\\text{last ${n === 1 ? "digit" : `${n} digits`}}`;
    }
  }

  if (!exprLatex || modulus === null) return null;
  if (modulus < 2n || modulus > BigInt(MAX_MODULUS)) return null;

  // "for n = 3", "when n = 3", "with n = 3" — every fixed value the question
  // gives, taken off the end so it doesn't end up inside the expression.
  const substitutions: Record<string, bigint> = {};
  const fix = /\b(?:for|when|with|where|if|given|and)\s+([a-zA-Z])\s*=\s*(-?\d+)/gi;
  for (let m = fix.exec(prose); m; m = fix.exec(prose)) {
    substitutions[m[1]] = BigInt(m[2]);
  }
  exprLatex = exprLatex
    .replace(/\b(?:for|when|with|where|if|given|and)\s+[a-zA-Z]\s*=\s*-?\d+/gi, " ")
    .replace(/^[\s\S]*?\b(?:of|that|is|find|compute|calculate|evaluate|what)\b\s*:?\s*(?=[-+(\\\d[a-zA-Z])/i, "")
    .trim();
  if (!exprLatex) return null;

  const exprAscii = latexToAscii(exprLatex).trim();
  if (!exprAscii) return null;

  // It has to be an integer expression, and every symbol in it has to be one the
  // question fixed a value for. Otherwise the remainder depends on something
  // nobody said.
  const probe = integerValue(exprAscii, substitutions);
  if (probe === null) return null;

  return { exprAscii, substitutions, modulus, label };
}

// ---------------------------------------------------------------------------
// route one: form the number, then divide
// ---------------------------------------------------------------------------

/**
 * The exact integer value of an ascii expression, in BigInt.
 *
 * Deliberately narrow: `+ − × ^` over integers and the fixed symbols, and
 * nothing else. A division or a function would take the value out of the
 * integers, where "remainder" means nothing, so it declines rather than
 * rounding something into place.
 */
function integerValue(ascii: string, subs: Record<string, bigint>): bigint | null {
  let root: MathNode;
  try {
    root = parse(ascii);
  } catch {
    return null;
  }
  const walk = (node: MathNode): bigint | null => {
    const n = node as unknown as {
      type: string;
      op?: string;
      fn?: unknown;
      args?: MathNode[];
      name?: string;
      value?: unknown;
      content?: MathNode;
    };
    switch (n.type) {
      case "ConstantNode": {
        const v = Number(n.value);
        if (!Number.isInteger(v) || Math.abs(v) > Number.MAX_SAFE_INTEGER) return null;
        return BigInt(v);
      }
      case "SymbolNode":
        return n.name && n.name in subs ? subs[n.name] : null;
      case "ParenthesisNode":
        return n.content ? walk(n.content) : null;
      case "OperatorNode": {
        const args = n.args ?? [];
        if (args.length === 1) {
          const a = walk(args[0]);
          if (a === null) return null;
          if (n.op === "-") return -a;
          if (n.op === "+") return a;
          return null;
        }
        if (args.length !== 2) return null;
        const a = walk(args[0]);
        const b = walk(args[1]);
        if (a === null || b === null) return null;
        switch (n.op) {
          case "+":
            return a + b;
          case "-":
            return a - b;
          case "*":
            return a * b;
          case "^": {
            if (b < 0n || b > BigInt(MAX_EXPONENT)) return null;
            return a ** b;
          }
          case "/": {
            // Only when it divides exactly — otherwise it is not an integer.
            if (b === 0n || a % b !== 0n) return null;
            return a / b;
          }
          default:
            return null;
        }
      }
      default:
        return null;
    }
  };
  return walk(root);
}

// ---------------------------------------------------------------------------
// route two: never form the number — reduce mod m at every step
// ---------------------------------------------------------------------------

function powMod(base: bigint, exp: bigint, m: bigint): bigint | null {
  if (exp < 0n) return null;
  let result = 1n;
  let b = ((base % m) + m) % m;
  let e = exp;
  while (e > 0n) {
    if (e & 1n) result = (result * b) % m;
    b = (b * b) % m;
    e >>= 1n;
  }
  return result;
}

/** The same expression evaluated entirely inside ℤ/mℤ. For `7^100 mod 10` this
 * never holds a number bigger than 100 — it is not the other route with a `%`
 * on the end, it is a different computation. */
function modularValue(ascii: string, subs: Record<string, bigint>, m: bigint): bigint | null {
  let root: MathNode;
  try {
    root = parse(ascii);
  } catch {
    return null;
  }
  const norm = (v: bigint) => ((v % m) + m) % m;
  const walk = (node: MathNode): bigint | null => {
    const n = node as unknown as {
      type: string;
      op?: string;
      args?: MathNode[];
      name?: string;
      value?: unknown;
      content?: MathNode;
    };
    switch (n.type) {
      case "ConstantNode": {
        const v = Number(n.value);
        if (!Number.isInteger(v) || Math.abs(v) > Number.MAX_SAFE_INTEGER) return null;
        return norm(BigInt(v));
      }
      case "SymbolNode":
        return n.name && n.name in subs ? norm(subs[n.name]) : null;
      case "ParenthesisNode":
        return n.content ? walk(n.content) : null;
      case "OperatorNode": {
        const args = n.args ?? [];
        if (args.length === 1) {
          const a = walk(args[0]);
          if (a === null) return null;
          return n.op === "-" ? norm(-a) : n.op === "+" ? a : null;
        }
        if (args.length !== 2) return null;
        // The EXPONENT is not reduced mod m — it counts multiplications, it is
        // not one of them. Reducing it there is the classic way to get a
        // plausible wrong answer out of modular arithmetic.
        if (n.op === "^") {
          const base = walk(args[0]);
          const exp = integerValue(argAscii(args[1]), subs);
          if (base === null || exp === null) return null;
          return powMod(base, exp, m);
        }
        const a = walk(args[0]);
        const b = walk(args[1]);
        if (a === null || b === null) return null;
        switch (n.op) {
          case "+":
            return norm(a + b);
          case "-":
            return norm(a - b);
          case "*":
            return norm(a * b);
          default:
            return null; // division has no meaning here without an inverse
        }
      }
      default:
        return null;
    }
  };
  return walk(root);
}

function argAscii(node: MathNode): string {
  try {
    return node.toString();
  } catch {
    return "";
  }
}

function step(latex: string, code: string): RawStep {
  return { ascii: latex, operationCode: code, latex };
}

export function solveModular(cls: { modular?: ModularQuery }): SolveCandidate | null {
  const q = cls.modular;
  if (!q) return null;

  const x = integerValue(q.exprAscii, q.substitutions);
  if (x === null) return null;
  const m = q.modulus;
  const r = ((x % m) + m) % m;

  // The gate. Same question, no shared arithmetic.
  const viaMod = modularValue(q.exprAscii, q.substitutions, m);
  if (viaMod === null || viaMod !== r) return null;

  // And the division identity has to close exactly.
  const quotient = (x - r) / m;
  if (quotient * m + r !== x) return null;
  if (r < 0n || r >= m) return null;

  const plain = r.toString();
  const answer: FinalAnswer = { latex: plain, plain };

  const subs = Object.entries(q.substitutions)
    .map(([k, v]) => `${k} = ${v}`)
    .join(", ");
  const steps: RawStep[] = [];
  if (subs) steps.push(step(`\\text{with } ${subs}`, "SUBSTITUTE"));
  // A number thousands of digits long is not working anybody can read.
  if (x.toString().length <= 40) {
    steps.push(step(`${q.exprAscii} = ${x}`, "EVALUATE"));
    steps.push(step(`${x} = ${quotient} \\times ${m} + ${r}`, "DIVIDE"));
  } else {
    steps.push(step(`\\text{reduce each step modulo } ${m}`, "EVALUATE"));
  }
  steps.push(step(`${q.label} = ${r}`, "RESULT"));

  return {
    answer,
    methods: [{ id: "modular", name: "Division with remainder", examPick: true, steps }],
    plotExpression: null,
    verify: () => true,
  };
}
