/**
 * Build the §4 `graph` object for a plottable single-variable problem.
 *
 * The heavy lifting (roots, coefficients) is already done by the deterministic
 * solver; here we just evaluate the plot expression at the key x-values and
 * shape them into labeled points. Returns null when the problem isn't a
 * single-variable function.
 */
import { asciiToLatex, variablesIn } from "./latex";
import { evalReal } from "./verify";
import { CurvePoint, GraphData, GraphKeyPoint } from "./types";

/** The minimal shape both the deterministic and LLM paths can supply. */
export interface GraphInput {
  plotExpression?: string | null;
  roots?: number[];
  quadratic?: { a: number; b: number; c: number };
}

/** Round display coordinates to avoid float noise like `-2.4500000001`. */
function round(n: number): number {
  return Number(n.toFixed(4));
}

export function buildGraph(candidate: GraphInput): GraphData | null {
  const exprAscii = candidate.plotExpression;
  if (!exprAscii) return null;
  const vars = variablesIn(exprAscii);
  if (vars.length !== 1) return null;
  const x = vars[0];

  const points: GraphKeyPoint[] = [];
  const seen = new Set<number>();
  const push = (label: string, xv: number, yv: number) => {
    if (!Number.isFinite(xv) || !Number.isFinite(yv)) return;
    const key = round(xv);
    if (seen.has(key)) return;
    seen.add(key);
    points.push({ label, x: round(xv), y: round(yv) });
  };

  // Roots (equations) — y is 0 by definition of a root.
  for (const r of candidate.roots ?? []) {
    push("root", r, 0);
  }

  // Vertex for quadratics: x = -b/2a.
  if (candidate.quadratic) {
    const { a, b } = candidate.quadratic;
    const xv = -b / (2 * a);
    const yv = evalReal(exprAscii, { [x]: xv });
    push("vertex", xv, yv);
  }

  // y-intercept.
  const y0 = evalReal(exprAscii, { [x]: 0 });
  push("y-intercept", 0, y0);

  if (points.length === 0) return null;

  const [lo, hi] = xWindow(points.map((p) => p.x));
  return {
    kind: "function",
    expression: asciiToLatex(exprAscii),
    keyPoints: points,
    curve: sampleCurve(exprAscii, x, lo, hi),
  };
}

/** A readable x-window around the key points (padded, with a minimum width). */
function xWindow(keyXs: number[]): [number, number] {
  if (keyXs.length === 0) return [-5, 5];
  let lo = Math.min(...keyXs);
  let hi = Math.max(...keyXs);
  if (hi - lo < 1e-6) {
    lo -= 5;
    hi += 5;
  } else {
    const pad = 0.5 * (hi - lo);
    lo -= pad;
    hi += pad;
  }
  if (hi - lo < 4) {
    const mid = (lo + hi) / 2;
    lo = mid - 2;
    hi = mid + 2;
  }
  return [lo, hi];
}

/**
 * Sample the expression across `[lo, hi]` — the DETERMINISTIC curve the client
 * plots. Non-finite samples (domain holes) are skipped.
 */
function sampleCurve(
  exprAscii: string,
  unknown: string,
  lo: number,
  hi: number
): CurvePoint[] {
  const N = 48;
  const out: CurvePoint[] = [];
  for (let i = 0; i <= N; i++) {
    const xv = lo + ((hi - lo) * i) / N;
    const yv = evalReal(exprAscii, { [unknown]: xv });
    if (Number.isFinite(yv)) out.push({ x: round(xv), y: round(yv) });
  }
  return out;
}
