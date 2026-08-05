/**
 * Percentages and ratios — the most-asked school topics that had NO engine at
 * all: "20% of 80", "30 is what percent of 120", "increase 240 by 15%",
 * "share 60 in the ratio 2:3", "simplify 12:18", "x : 12 = 3 : 4" every one
 * returned NO CANDIDATE and fell to the LLM tier.
 *
 * The parse gate is strict, same posture as `parseCircle`: one recognised
 * shape, plain numbers, or it returns null and classification falls through
 * unchanged. The solver computes deterministically and each candidate carries a
 * `verify()` that re-derives the claim from the parsed numbers along the
 * definitional path — (p/100)·base for a part, sum + cross-ratio for a share —
 * so nothing ships on the parser's say-so alone.
 */
import { asciiToLatex } from "./latex";
import type { RawMethod, RawStep, SolveCandidate } from "./types";

// --- task shapes -------------------------------------------------------------

export type PercentTask =
  | { kind: "percent_of"; p: number; base: number }
  | { kind: "what_percent"; part: number; whole: number }
  | {
      kind: "change_by_percent";
      base: number;
      p: number;
      direction: "increase" | "decrease";
    }
  | { kind: "share_ratio"; total: number; parts: number[] }
  | { kind: "simplify_ratio"; parts: number[] }
  | {
      kind: "proportion";
      /** `left[0] : left[1] = right[0] : right[1]`, one entry is the unknown. */
      left: [string, string];
      right: [string, string];
      unknown: string;
    };

// --- parsing -----------------------------------------------------------------

/** Number with optional decimal part. */
const NUM = "\\d+(?:\\.\\d+)?";

/**
 * The prose flattened for matching: `\text{…}` unwrapped, `\%` → `%`, latex
 * spacing collapsed. Lowercased — every regex below assumes it.
 */
function flatten(rawLatex: string): string {
  return rawLatex
    .replace(/\\text\s*\{([^{}]*)\}/g, " $1 ")
    .replace(/\\%/g, "%")
    .replace(/\\[,;:!]|\\\\|[{}$]|\\left|\\right/g, " ")
    .replace(/[?.!]\s*$/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function ratioParts(text: string): number[] | null {
  const m = text.split(":").map((s) => s.trim());
  if (m.length < 2 || m.length > 3) return null;
  const parts = m.map(Number);
  if (parts.some((v) => !Number.isInteger(v) || v <= 0)) return null;
  return parts;
}

/** The strict prose gate. Returns null for anything not clearly one shape. */
export function parsePercent(rawLatex: string): PercentTask | null {
  const s = flatten(rawLatex);
  // A proportion written with ratio colons: `x : 12 = 3 : 4` (exactly one
  // unknown letter among four slots). Checked FIRST — it contains no percent
  // sign and would otherwise fall to the mangled-colon equation path.
  {
    const m = new RegExp(
      `^(?:solve\\s+)?([a-z]|${NUM}) : ([a-z]|${NUM}) = ([a-z]|${NUM}) : ([a-z]|${NUM})$`
    ).exec(s);
    if (m) {
      const slots = [m[1], m[2], m[3], m[4]];
      const letters = slots.filter((t) => /^[a-z]$/.test(t));
      if (letters.length === 1 && letters[0] !== "e") {
        return {
          kind: "proportion",
          left: [slots[0], slots[1]],
          right: [slots[2], slots[3]],
          unknown: letters[0],
        };
      }
      return null;
    }
  }

  // "what is 20% of 80" / "find 25% of 320" / "20% of 80"
  {
    const m = new RegExp(
      `^(?:what is |find |calculate |work out )?(${NUM})\\s*% of (${NUM})$`
    ).exec(s);
    if (m) return { kind: "percent_of", p: Number(m[1]), base: Number(m[2]) };
  }

  // "30 is what percent of 120" / "what percentage of 50 is 30"
  {
    const m = new RegExp(
      `^(${NUM}) is what percent(?:age)? of (${NUM})$`
    ).exec(s);
    if (m) return { kind: "what_percent", part: Number(m[1]), whole: Number(m[2]) };
  }
  {
    const m = new RegExp(
      `^what percent(?:age)? of (${NUM}) is (${NUM})$`
    ).exec(s);
    if (m) return { kind: "what_percent", part: Number(m[2]), whole: Number(m[1]) };
  }

  // "increase 240 by 15%" / "decrease 80 by 25%"
  {
    const m = new RegExp(
      `^(increase|decrease) (${NUM}) by (${NUM})\\s*%$`
    ).exec(s);
    if (m) {
      return {
        kind: "change_by_percent",
        direction: m[1] as "increase" | "decrease",
        base: Number(m[2]),
        p: Number(m[3]),
      };
    }
  }

  // "divide 60 in the ratio 2:3" / "share 91 in the ratio 3:4(:5)"
  {
    const m = new RegExp(
      `^(?:divide|share|split) (${NUM}) (?:in|into) the ratio ((?:${NUM})(?:\\s*:\\s*${NUM}){1,2})$`
    ).exec(s);
    if (m) {
      const parts = ratioParts(m[2]);
      if (parts) return { kind: "share_ratio", total: Number(m[1]), parts };
    }
  }

  // "simplify the ratio 12:18" / "simplify 12:18(:24)"
  {
    const m = new RegExp(
      `^(?:simplify|write in simplest form|express in simplest form)(?: the ratio)? ((?:${NUM})(?:\\s*:\\s*${NUM}){1,2})$`
    ).exec(s);
    if (m) {
      const parts = ratioParts(m[1]);
      if (parts) return { kind: "simplify_ratio", parts };
    }
  }

  return null;
}

// --- formatting --------------------------------------------------------------

function trim(v: number): string {
  return String(Math.round(v * 1e9) / 1e9);
}

function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

function step(operationCode: string, ascii: string, latex?: string): RawStep {
  return { ascii, operationCode, latex: latex ?? asciiToLatex(ascii) };
}

function method(id: string, name: string, steps: RawStep[]): RawMethod[] {
  return [{ id, name, examPick: true, steps }];
}

function answerOf(plain: string, latex?: string) {
  return { plain, latex: latex ?? plain };
}

const TOL = 1e-9;

// --- solving -----------------------------------------------------------------

/** Deterministic solve of a parsed task; every branch carries its own gate. */
export function solvePercent(task: PercentTask): SolveCandidate | null {
  switch (task.kind) {
    case "percent_of": {
      const { p, base } = task;
      const value = (p / 100) * base;
      const product = p * base;
      const steps: RawStep[] = [
        step("START", `${p}% of ${base}`, `${p}\\% \\text{ of } ${base}`),
        step(
          "PERCENT_MEANS",
          `${p}% = ${p}/100`,
          `${p}\\% = \\tfrac{${p}}{100}`
        ),
        step(
          "WRITE_PRODUCT",
          `(${p}/100) * ${base}`,
          `\\tfrac{${p}}{100} \\times ${base}`
        ),
        step(
          "MULTIPLY_OUT",
          `${trim(product)} / 100`,
          `\\tfrac{${trim(product)}}{100}`
        ),
        step("COMPUTE", trim(value)),
      ];
      return {
        answer: answerOf(trim(value)),
        methods: method("percent_of", "Turn the percent into a fraction", steps),
        plotExpression: null,
        verify: () => Math.abs((p / 100) * base - value) <= TOL,
      };
    }

    case "what_percent": {
      const { part, whole } = task;
      if (whole === 0) return null;
      const value = (part / whole) * 100;
      const g =
        Number.isInteger(part) && Number.isInteger(whole)
          ? gcd(Math.abs(part), Math.abs(whole))
          : 1;
      const steps: RawStep[] = [
        step(
          "START",
          `${part} out of ${whole}`,
          `\\text{${part} out of ${whole}}`
        ),
        step(
          "WRITE_FRACTION",
          `${part}/${whole}`,
          `\\tfrac{${part}}{${whole}}`
        ),
      ];
      if (g > 1) {
        steps.push(
          step(
            "SIMPLIFY_FRACTION",
            `${part / g}/${whole / g}`,
            `\\tfrac{${part / g}}{${whole / g}}`
          )
        );
      }
      steps.push(
        step(
          "TIMES_100",
          `(${part / g}/${whole / g}) * 100% = ${trim(value)}%`,
          `\\tfrac{${part / g}}{${whole / g}} \\times 100\\% = ${trim(value)}\\%`
        ),
        step("COMPUTE", `${trim(value)}%`, `${trim(value)}\\%`)
      );
      return {
        answer: answerOf(`${trim(value)}%`, `${trim(value)}\\%`),
        methods: method("what_percent", "Write it as a fraction of the whole", steps),
        plotExpression: null,
        verify: () => Math.abs((value / 100) * whole - part) <= TOL,
      };
    }

    case "change_by_percent": {
      const { base, p, direction } = task;
      const part = (p / 100) * base;
      const value = direction === "increase" ? base + part : base - part;
      const op = direction === "increase" ? "+" : "-";
      const word = direction === "increase" ? "Increase" : "Decrease";
      const steps: RawStep[] = [
        step(
          "START",
          `${word.toLowerCase()} ${base} by ${p}%`,
          `\\text{${word} } ${base} \\text{ by } ${p}\\%`
        ),
        step(
          "PERCENT_MEANS",
          `${p}% = ${p}/100`,
          `${p}\\% = \\tfrac{${p}}{100}`
        ),
        step(
          "FIND_PART",
          `(${p}/100) * ${base} = ${trim(part)}`,
          `\\tfrac{${p}}{100} \\times ${base} = ${trim(part)}`
        ),
        step(
          direction === "increase" ? "ADD_PART" : "SUBTRACT_PART",
          `${base} ${op} ${trim(part)} = ${trim(value)}`
        ),
        step("COMPUTE", trim(value)),
      ];
      return {
        answer: answerOf(trim(value)),
        methods: method(
          "change_by_percent",
          "Find the part, then apply it",
          steps
        ),
        plotExpression: null,
        verify: () =>
          Math.abs(base * (1 + (direction === "increase" ? 1 : -1) * p / 100) - value) <=
          TOL,
      };
    }

    case "share_ratio": {
      const { total, parts } = task;
      const totalParts = parts.reduce((a, b) => a + b, 0);
      if (totalParts === 0) return null;
      const one = total / totalParts;
      const shares = parts.map((k) => k * one);
      const ratioText = parts.join(" : ");
      const steps: RawStep[] = [
        step(
          "START",
          `share ${total} in the ratio ${ratioText}`,
          `\\text{Share } ${total} \\text{ in the ratio } ${parts.join(" : ")}`
        ),
        step(
          "TOTAL_PARTS",
          `${parts.join(" + ")} = ${totalParts}`,
          `${parts.join(" + ")} = ${totalParts} \\text{ parts}`
        ),
        step(
          "ONE_PART",
          `${total} / ${totalParts} = ${trim(one)}`,
          `${total} \\div ${totalParts} = ${trim(one)} \\text{ per part}`
        ),
        ...parts.map((k, i) =>
          step(
            "EACH_SHARE",
            `${k} * ${trim(one)} = ${trim(shares[i])}`,
            `${k} \\times ${trim(one)} = ${trim(shares[i])}`
          )
        ),
        step(
          "RESULT",
          shares.map(trim).join(" : "),
          shares.map(trim).join(" : ")
        ),
      ];
      return {
        answer: answerOf(shares.map(trim).join(" : ")),
        methods: method("share_ratio", "Share by parts", steps),
        plotExpression: null,
        // The shares must add back to the total AND stay in the stated ratio.
        verify: () =>
          Math.abs(shares.reduce((a, b) => a + b, 0) - total) <= 1e-6 &&
          shares.every((s, i) => Math.abs(s * parts[0] - shares[0] * parts[i]) <= 1e-6),
      };
    }

    case "simplify_ratio": {
      const { parts } = task;
      const g = parts.reduce((a, b) => gcd(a, b));
      if (g <= 1) return null; // already simplest — nothing to teach
      const reduced = parts.map((v) => v / g);
      const steps: RawStep[] = [
        step("START", parts.join(" : ")),
        step(
          "FIND_GCD",
          `GCD(${parts.join(", ")}) = ${g}`,
          `\\gcd(${parts.join(", ")}) = ${g}`
        ),
        step(
          "DIVIDE_ALL_PARTS",
          parts.map((v) => `${v}/${g}`).join(" : "),
          parts.map((v) => `\\tfrac{${v}}{${g}}`).join(" : ")
        ),
        step("RESULT", reduced.join(" : ")),
      ];
      return {
        answer: answerOf(reduced.join(" : ")),
        methods: method("simplify_ratio", "Divide by the common factor", steps),
        plotExpression: null,
        // Same ratio (cross products) and nothing left to cancel.
        verify: () =>
          reduced.every(
            (r, i) => r * parts[0] === reduced[0] * parts[i]
          ) && reduced.reduce((a, b) => gcd(a, b)) === 1,
      };
    }

    case "proportion": {
      const { left, right, unknown } = task;
      const slots = [left[0], left[1], right[0], right[1]];
      const idx = slots.indexOf(unknown);
      if (idx === -1) return null;
      const nums = slots.map((t) => (t === unknown ? NaN : Number(t)));
      if (nums.filter((v) => !Number.isNaN(v)).length !== 3) return null;
      const [a, b, c, d] = nums;
      // Cross-multiplying a:b = c:d gives a·d = b·c; solve for whichever slot
      // is the unknown. Zero denominators decline.
      let value: number;
      switch (idx) {
        case 0: value = (b * c) / d; break;
        case 1: value = (a * d) / c; break;
        case 2: value = (a * d) / b; break;
        default: value = (b * c) / a; break;
      }
      if (!Number.isFinite(value)) return null;
      // After cross-multiplying, one side is `k·unknown` and the other is the
      // product `m` of the two known numbers on the diagonal.
      const k = [d, c, b, a][idx];
      const m = idx === 0 || idx === 3 ? b * c : a * d;
      const given = `${slots[0]} : ${slots[1]} = ${slots[2]} : ${slots[3]}`;
      const steps: RawStep[] = [
        step("GIVEN", given),
        step(
          "WRITE_AS_FRACTIONS",
          `${slots[0]}/${slots[1]} = ${slots[2]}/${slots[3]}`,
          `\\tfrac{${slots[0]}}{${slots[1]}} = \\tfrac{${slots[2]}}{${slots[3]}}`
        ),
        step("CROSS_MULTIPLY", `${trim(k)}${unknown} = ${trim(m)}`),
        step(
          "DIVIDE_BOTH_SIDES",
          `${unknown} = ${trim(m)}/${trim(k)}`,
          `${unknown} = \\tfrac{${trim(m)}}{${trim(k)}}`
        ),
        step("FIND_ROOTS", `${unknown} = ${trim(value)}`),
      ];
      return {
        answer: answerOf(`${unknown} = ${trim(value)}`),
        methods: method("proportion", "Cross-multiply", steps),
        plotExpression: null,
        roots: [value],
        // Substituted back into the proportion as printed.
        verify: () => {
          const at = (t: string) => (t === unknown ? value : Number(t));
          const [A, B, C, D] = slots.map(at);
          return (
            Math.abs(B) > TOL &&
            Math.abs(D) > TOL &&
            Math.abs(A / B - C / D) <= 1e-6
          );
        },
      };
    }
  }
}
