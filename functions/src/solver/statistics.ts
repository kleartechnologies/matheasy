/**
 * Descriptive statistics — a DETERMINISTIC solver path (Phase A). A statistic
 * over a given data set is computed by mathjs AND, independently, by a
 * hand-rolled definition; the two must agree before anything ships. That
 * two-path agreement IS the verification — the golden rule holds without an
 * equation to substitute into.
 */
import { mean, median, std, sum as mjSum, variance } from "mathjs";

import { FinalAnswer, RawStep, SolveCandidate } from "./types";

export type StatKind =
  | "mean"
  | "median"
  | "mode"
  | "variance"
  | "std"
  | "range"
  | "sum"
  | "min"
  | "max";

const KEYWORDS: readonly [RegExp, StatKind][] = [
  [/\b(mean|average)\b/i, "mean"],
  [/\bmedian\b/i, "median"],
  [/\bmode\b/i, "mode"],
  [/(standard\s*deviation|std\s*dev|\bstd\b|σ|\bsigma\b)/i, "std"],
  [/\bvariance\b/i, "variance"],
  [/\brange\b/i, "range"],
  [/\bsum(?:mation)?\b/i, "sum"],
  [/\b(minimum|min)\b/i, "min"],
  [/\b(maximum|max)\b/i, "max"],
];

export interface StatQuery {
  stat: StatKind;
  data: number[];
}

/**
 * A descriptive-statistics request: a stat keyword + a comma-separated data set
 * of ≥2 numbers (e.g. `mean of 2, 4, 6, 8`, `median(3,1,4,1,5)`), or null.
 */
export function parseStatistics(rawLatex: string): StatQuery | null {
  let stat: StatKind | null = null;
  for (const [re, s] of KEYWORDS) {
    if (re.test(rawLatex)) {
      stat = s;
      break;
    }
  }
  if (!stat) return null;

  // The data set = the longest comma-separated run of ≥2 numbers (avoids
  // grabbing a stray count like "the first 5 values").
  const runs = rawLatex.match(/-?\d+(?:\.\d+)?(?:\s*,\s*-?\d+(?:\.\d+)?)+/g);
  if (!runs) return null;
  const best = runs.slice().sort((a, b) => b.length - a.length)[0];
  const data = best
    .split(",")
    .map((t) => Number(t.trim()))
    .filter((x) => Number.isFinite(x));
  if (data.length < 2) return null;
  return { stat, data };
}

/** Solves a descriptive-statistics request, gated by an independent recompute. */
export function solveStatistics(cls: {
  statKind?: string;
  statData?: number[];
}): SolveCandidate | null {
  const stat = cls.statKind as StatKind | undefined;
  const data = cls.statData;
  if (!stat || !data || data.length < 2) return null;

  const n = data.length;
  const rawSum = data.reduce((a, b) => a + b, 0);
  const m = rawSum / n;

  let value = NaN; // mathjs result
  let independent = NaN; // hand-rolled, for the cross-check
  let modeVals: number[] | null = null;
  let label: string = stat;

  switch (stat) {
    case "mean":
      value = Number(mean(data));
      independent = rawSum / n;
      break;
    case "sum":
      value = Number(mjSum(data));
      independent = rawSum;
      break;
    case "min":
      value = Math.min(...data);
      independent = data.reduce((a, b) => Math.min(a, b), Infinity);
      break;
    case "max":
      value = Math.max(...data);
      independent = data.reduce((a, b) => Math.max(a, b), -Infinity);
      break;
    case "range":
      value = Math.max(...data) - Math.min(...data);
      independent =
        data.reduce((a, b) => Math.max(a, b), -Infinity) -
        data.reduce((a, b) => Math.min(a, b), Infinity);
      break;
    case "median":
      value = Number(median(data));
      independent = medianOf(data);
      break;
    case "variance":
      value = Number(variance(data, "uncorrected"));
      independent = data.reduce((a, x) => a + (x - m) ** 2, 0) / n;
      label = "population variance (σ²)";
      break;
    case "std":
      value = Number(std(data, "uncorrected"));
      independent = Math.sqrt(data.reduce((a, x) => a + (x - m) ** 2, 0) / n);
      label = "population standard deviation (σ)";
      break;
    case "mode":
      modeVals = modesOf(data);
      if (!modeVals) return null; // all distinct → no clear mode; decline honestly
      break;
  }

  const verify = (): boolean => {
    if (stat === "mode") {
      const again = modesOf(data);
      return again != null && sameNumbers(again, modeVals!);
    }
    return (
      Number.isFinite(value) &&
      Number.isFinite(independent) &&
      Math.abs(value - independent) <= 1e-9 * Math.max(1, Math.abs(value))
    );
  };
  if (!verify()) return null;

  const answer: FinalAnswer =
    stat === "mode"
      ? {
          latex: modeVals!.map(fmtNum).join(",\\; "),
          plain: modeVals!.map(fmtNum).join(", "),
        }
      : fmt(value);

  return {
    answer,
    methods: [{ id: "statistic", name: title(stat), examPick: true, steps: stepsFor(stat, label, data, answer) }],
    plotExpression: null,
    verify,
  };
}

// ---- pure helpers ----------------------------------------------------------

function medianOf(data: number[]): number {
  const s = [...data].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/** Value(s) with the highest frequency, sorted; null when every value is unique. */
function modesOf(data: number[]): number[] | null {
  const freq = new Map<number, number>();
  for (const x of data) freq.set(x, (freq.get(x) ?? 0) + 1);
  const maxFreq = Math.max(...freq.values());
  if (maxFreq <= 1) return null;
  return [...freq.entries()]
    .filter(([, c]) => c === maxFreq)
    .map(([v]) => v)
    .sort((a, b) => a - b);
}

function sameNumbers(a: number[], b: number[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

function round10(v: number): number {
  return Math.round(v * 1e10) / 1e10;
}
function fmtNum(v: number): string {
  return String(round10(v));
}
function fmt(v: number): FinalAnswer {
  const s = fmtNum(v);
  return { latex: s, plain: s };
}

function title(stat: StatKind): string {
  return { mean: "Mean", median: "Median", mode: "Mode", variance: "Variance", std: "Standard deviation", range: "Range", sum: "Sum", min: "Minimum", max: "Maximum" }[stat];
}

function stepsFor(stat: StatKind, label: string, data: number[], answer: FinalAnswer): RawStep[] {
  const list = data.map(fmtNum).join(",\\; ");
  const n = data.length;
  const sum = fmtNum(data.reduce((a, b) => a + b, 0));
  const start: RawStep = {
    ascii: `data ${data.join(", ")}`,
    operationCode: "START",
    latex: `\\text{Data: } ${list}\\quad (n=${n})`,
  };
  const formula: Record<StatKind, string> = {
    mean: `\\bar{x} = \\frac{\\sum x}{n} = \\frac{${sum}}{${n}}`,
    sum: `\\sum x = ${sum}`,
    median: `\\text{middle of the sorted data}`,
    mode: `\\text{the most frequent value(s)}`,
    range: `\\max - \\min`,
    min: `\\min(\\text{data})`,
    max: `\\max(\\text{data})`,
    variance: `\\sigma^2 = \\frac{\\sum (x-\\bar{x})^2}{n}`,
    std: `\\sigma = \\sqrt{\\dfrac{\\sum (x-\\bar{x})^2}{n}}`,
  };
  return [
    start,
    { ascii: label, operationCode: "COMPUTE", latex: formula[stat] },
    { ascii: answer.plain, operationCode: "RESULT", latex: `${label} = ${answer.latex}` },
  ];
}
