/**
 * Linear algebra — a DETERMINISTIC path (Phase B). mathjs already computes
 * det/inverse/eigenvalues; the gap the coverage audit found was parsing the
 * matrix and VERIFYING the result. Each answer is proven by a property, not
 * trusted from one engine:
 *   • determinant  — mathjs det AND an independent cofactor expansion agree
 *   • inverse      — A · A⁻¹ ≈ I
 *   • eigenvalues  — det(A − λI) ≈ 0 for every λ
 * Numeric, real-valued matrices only (complex spectra decline honestly).
 */
import { cross, det, dot, eigs, identity, inv, multiply, norm, subtract, transpose } from "mathjs";

import { FinalAnswer, RawStep, SolveCandidate } from "./types";

export type LinalgOp =
  | "determinant"
  | "inverse"
  | "eigenvalues"
  | "multiply"
  | "add"
  | "subtract"
  | "rank";

/** A single clean number token, or null — rejects "" (Number("")=0), a bare
 * ".", and thousands-style groups like "000"/"007" (a leading zero before more
 * digits is never a real matrix entry / vector component, but a locale
 * thousands separator or malformed input). `0`, `0.5`, `-0.5` stay valid. */
function numToken(t: string): number | null {
  const s = t.trim();
  if (!/^-?\d+(?:\.\d+)?$/.test(s) || /^-?0\d/.test(s)) return null;
  return Number(s);
}

/** One matrix body (`1 & 2 \\ 3 & 4`) → grid, or null if ragged / any cell is
 * blank or non-numeric (a dropped cell must DECLINE, not silently become 0). */
function gridFrom(body: string): number[][] | null {
  const rows = body
    .split(/\\\\/)
    .map((r) => r.trim())
    .filter(Boolean);
  if (rows.length === 0) return null;
  const grid: number[][] = [];
  for (const r of rows) {
    const cells = r.split("&").map((c) => numToken(c.replace(/[{}]/g, "")));
    if (cells.some((c) => c === null)) return null; // blank / non-numeric cell
    grid.push(cells as number[]);
  }
  const w = grid[0].length;
  return grid.every((row) => row.length === w) ? grid : null;
}

const MATRIX_RE = /\\begin\{[pbv]matrix\}[\s\S]*?\\end\{[pbv]matrix\}/g;

/** All p/b/v-matrices in the input, in order. */
function parseMatrices(rawLatex: string): number[][][] {
  const re = /\\begin\{[pbv]matrix\}([\s\S]*?)\\end\{[pbv]matrix\}/g;
  const out: number[][][] = [];
  for (let m = re.exec(rawLatex); m; m = re.exec(rawLatex)) {
    const g = gridFrom(m[1]);
    if (g) out.push(g);
  }
  return out;
}

function sameShape(a: number[][], b: number[][]): boolean {
  return a.length === b.length && a.every((row, i) => row.length === b[i].length);
}

/** The text BETWEEN the two matrix blocks (the connective `+` / `-` / `\cdot`).
 * Each block is swapped for a sentinel that can't occur in LaTeX, then we read
 * the span between the first two sentinels. */
function matrixGap(rawLatex: string): string {
  const SENTINEL = "@@MATRIX@@";
  const parts = rawLatex.replace(MATRIX_RE, SENTINEL).split(SENTINEL);
  return parts[1] ?? "";
}

/** A matrix operation + its matrix (+ a second matrix for A±B / A·B), or null. */
export function parseLinalg(
  rawLatex: string
): { op: LinalgOp; matrix: number[][]; matrixB?: number[][] } | null {
  const matrices = parseMatrices(rawLatex);
  if (matrices.length === 0) return null;
  const lower = rawLatex.toLowerCase();

  // A scalar/whole-matrix keyword applied to a MATRIX EXPRESSION of two operands
  // (det/inverse/eigenvalues of a product, det·det of two vmatrices, …) is out of
  // scope — decline honestly rather than silently return the raw A·B.
  const hasOuterOp =
    /\\begin\{vmatrix\}/.test(rawLatex) ||
    /\bdeterminant\b|\bdet\b|\\det|eigen|inverse|\brank\b|\btrace\b/.test(lower);

  if (matrices.length >= 2) {
    if (matrices.length > 2) return null; // A·B·C etc. — ambiguous to verify, decline
    if (hasOuterOp) return null;
    const [a, b] = matrices;
    // What connects the two matrices? Replace each block with a marker and read
    // the text between them, so `A + B` is a SUM and never a silent product.
    const gap = matrixGap(rawLatex);
    if (/\+/.test(gap)) return sameShape(a, b) ? { op: "add", matrix: a, matrixB: b } : null;
    if (/-|−/.test(gap)) return sameShape(a, b) ? { op: "subtract", matrix: a, matrixB: b } : null;
    // multiply only when nothing but whitespace / an explicit ×,·,* joins them
    if (/^\s*(\\cdot|\\times|\*|·|×)?\s*$/.test(gap)) {
      return a[0].length === b.length ? { op: "multiply", matrix: a, matrixB: b } : null;
    }
    return null; // unknown connective → decline
  }

  const matrix = matrices[0];
  // Rank applies to ANY shape — detect it before the square-only ops.
  if (/\brank\b/.test(lower)) return { op: "rank", matrix };

  let op: LinalgOp | null = null;
  if (/\\begin\{vmatrix\}/.test(rawLatex) || /\bdeterminant\b|\bdet\b|\\det/.test(lower)) {
    op = "determinant";
  } else if (/eigen/.test(lower)) {
    op = "eigenvalues";
  } else if (/inverse/.test(lower) || /\}\s*\^\s*\{?\s*-?\s*1/.test(rawLatex)) {
    op = "inverse";
  }
  if (!op) return null;
  if (matrix.length !== matrix[0].length) return null; // these need a square matrix
  return { op, matrix };
}

/** Solves a linear-algebra request, gated by a property check. */
export function solveLinalg(cls: {
  linalgOp?: string;
  matrixData?: number[][];
  matrixB?: number[][];
}): SolveCandidate | null {
  const op = cls.linalgOp as LinalgOp | undefined;
  const A = cls.matrixData;
  if (!op || !A) return null;
  const n = A.length;

  try {
    switch (op) {
      case "determinant": {
        const d = Number(det(A));
        if (!Number.isFinite(d) || !close(d, cofactorDet(A))) return null;
        return candidate(fmt(d), "Determinant", [
          matStep(A),
          resultStep("\\det = " + fmtNum(d)),
        ]);
      }
      case "inverse": {
        const invA = toGrid(inv(A));
        if (!invA || !isIdentity(toGrid(multiply(A, invA)))) return null;
        return candidate(matrixAnswer(invA), "Inverse", [
          matStep(A),
          resultStep("A^{-1} = " + matrixLatex(invA)),
        ]);
      }
      case "eigenvalues": {
        const vals = eigenReal(A);
        if (!vals) return null;
        for (const lam of vals) {
          const shifted = toGrid(subtract(A, multiply(lam, identity(n))));
          if (!shifted || Math.abs(Number(det(shifted))) > 1e-6) return null;
        }
        return candidate(listAnswer(vals), "Eigenvalues", [
          matStep(A),
          resultStep("\\lambda = " + vals.map(fmtNum).join(",\\; ")),
        ]);
      }
      case "multiply": {
        const b = cls.matrixB;
        if (!b || A[0].length !== b.length) return null;
        const prod = toGrid(multiply(A, b));
        if (!prod || !sameGrid(prod, matMul(A, b))) return null; // mathjs vs hand-rolled
        return candidate(matrixAnswer(prod), "Matrix product", [
          matStep(A),
          resultStep("AB = " + matrixLatex(prod)),
        ]);
      }
      case "add":
      case "subtract": {
        const b = cls.matrixB;
        if (!b || !sameShape(A, b)) return null;
        const s = op === "add" ? 1 : -1;
        // Independent element-wise recompute is the check (mathjs never touched).
        const out = A.map((row, i) => row.map((v, j) => v + s * b[i][j]));
        const symbol = op === "add" ? "+" : "-";
        return candidate(matrixAnswer(out), op === "add" ? "Matrix sum" : "Matrix difference", [
          matStep(A),
          resultStep(`A ${symbol} B = ` + matrixLatex(out)),
        ]);
      }
      case "rank": {
        const r1 = cleanRank(A); // row reduction, declines an ambiguous pivot
        const r2 = gramRank(A); // count of nonzero eigenvalues of AᵀA (independent)
        if (r1 === null || r2 === null || r1 !== r2) return null; // must agree, unambiguously
        return candidate(fmt(r1), "Rank", [matStep(A), resultStep("\\text{rank}(A) = " + r1)]);
      }
    }
  } catch {
    return null;
  }
  return null;
}

// ---- Vectors (dot / cross / magnitude) -------------------------------------

export type VectorOp = "dot" | "cross" | "magnitude" | "independent" | "spans";

/** Numeric vectors written as `(1, 2, 3)` or `\langle 1,2,3 \rangle`. */
function extractVectors(rawLatex: string): number[][] {
  const out: number[][] = [];
  const re = /\(([-\d.,\s]+)\)|\\langle([-\d.,\s]+)\\rangle/g;
  for (let m = re.exec(rawLatex); m; m = re.exec(rawLatex)) {
    const body = (m[1] ?? m[2] ?? "").trim();
    if (!body.includes(",")) continue;
    const toks = body.split(",").map((t) => numToken(t));
    // A vector is only a vector when EVERY component is a clean number. A blank
    // ("(1,,3)"), a bare "." ("(1,.,3)"), a trailing comma, or a thousands group
    // ("(1,000)") means this parenthesis is NOT a vector — skip it rather than
    // silently coerce a component to 0 and answer a question never asked.
    if (toks.length >= 2 && toks.every((t) => t !== null)) out.push(toks as number[]);
  }
  return out;
}

/** A vector operation + its operand(s): dot/cross (two), magnitude (one).
 * The cues are deliberately narrow: the magnitude trigger is the vector-specific
 * "magnitude"/"norm" (or \lVert…\rVert bars) — NOT the generic word "length",
 * which collides with intervals, line segments and word problems and would hijack
 * them into a bogus |v|. dot/cross still require TWO clean vector operands, so a
 * stray \cdot/\times (e.g. scalar multiplication) can't trigger one on its own. */
export function parseVectors(
  rawLatex: string
): { op: VectorOp; vectors: number[][] } | null {
  // A stat word wrapping a vector op ("range of the cross product") is a nested,
  // un-verifiable composition — decline rather than return the raw vector op.
  if (/\b(mean|average|median|mode|variance|deviation|range|sum|summation)\b/i.test(rawLatex)) {
    return null;
  }
  const vecs = extractVectors(rawLatex);
  const lower = rawLatex.toLowerCase();

  // Linear independence / span — need ≥2 vectors that live in the SAME space.
  const sameLen = vecs.length >= 2 && vecs.every((v) => v.length === vecs[0].length);
  if (sameLen && /linear(?:ly)?\s+(?:in)?depend/.test(lower)) {
    return { op: "independent", vectors: vecs };
  }
  if (sameLen && /\bspan(?:s|ned|ning)?\b/.test(lower)) {
    return { op: "spans", vectors: vecs };
  }

  const magCue =
    /\bmagnitude\b|\bnorm\b/.test(lower) ||
    /\\lVert|\\rVert|\\Vert|\\\|/.test(rawLatex);
  if (magCue && vecs.length === 1) {
    return { op: "magnitude", vectors: vecs };
  }
  if ((/\bcross\b/.test(lower) || /\\times|×/.test(rawLatex)) && vecs.length === 2) {
    return { op: "cross", vectors: vecs };
  }
  if ((/\bdot\b/.test(lower) || /\\cdot|·/.test(rawLatex)) && vecs.length === 2) {
    return { op: "dot", vectors: vecs };
  }
  return null;
}

export function solveVectors(cls: {
  vectorOp?: string;
  vectorData?: number[][];
}): SolveCandidate | null {
  const op = cls.vectorOp as VectorOp | undefined;
  const vecs = cls.vectorData;
  if (!op || !vecs) return null;
  try {
    switch (op) {
      case "magnitude": {
        const v = vecs[0];
        const mag = Math.sqrt(v.reduce((a, x) => a + x * x, 0));
        if (!close(mag, Number(norm(v)))) return null;
        return candidate(fmt(mag), "Magnitude", [
          resultStep("\\lVert v \\rVert = " + fmtNum(mag)),
        ]);
      }
      case "dot": {
        const [a, b] = vecs;
        if (a.length !== b.length) return null;
        const d = a.reduce((s, x, i) => s + x * b[i], 0);
        if (!close(d, Number(dot(a, b)))) return null;
        return candidate(fmt(d), "Dot product", [
          resultStep("a \\cdot b = " + fmtNum(d)),
        ]);
      }
      case "cross": {
        const [a, b] = vecs;
        if (a.length !== 3 || b.length !== 3) return null;
        const c = (cross(a, b) as number[]).map(Number);
        const hand = [
          a[1] * b[2] - a[2] * b[1],
          a[2] * b[0] - a[0] * b[2],
          a[0] * b[1] - a[1] * b[0],
        ];
        // recompute agrees AND the result is ⊥ to both inputs.
        if (!sameVec(c, hand) || Math.abs(dotN(c, a)) > 1e-6 || Math.abs(dotN(c, b)) > 1e-6) {
          return null;
        }
        return candidate(vecAnswer(c), "Cross product", [
          resultStep("a \\times b = " + vecLatex(c)),
        ]);
      }
      case "independent":
      case "spans": {
        // Vectors as rows; rank via TWO independent methods must agree.
        if (vecs.length < 2 || !vecs.every((v) => v.length === vecs[0].length)) return null;
        const r1 = cleanRank(vecs);
        const r2 = gramRank(vecs);
        if (r1 === null || r2 === null || r1 !== r2) return null;
        if (op === "independent") {
          const indep = r1 === vecs.length;
          const plain = indep ? "Linearly independent" : "Linearly dependent";
          return candidate(
            { latex: `\\text{${plain}}`, plain },
            "Linear independence",
            [resultStep(`\\text{rank} = ${r1} \\text{ of } ${vecs.length} \\Rightarrow \\text{${plain.toLowerCase()}}`)]
          );
        }
        const n = vecs[0].length; // ambient dimension ℝⁿ
        const spans = r1 === n;
        const plain = spans ? `Yes — they span R^${n}` : `No — they do not span R^${n}`;
        const rn = `\\mathbb{R}^{${n}}`;
        return candidate(
          { latex: spans ? `\\text{Yes — they span } ${rn}` : `\\text{No — they do not span } ${rn}`, plain },
          "Span",
          [resultStep(`\\text{rank} = ${r1},\\; \\dim = ${n}`)]
        );
      }
    }
  } catch {
    return null;
  }
  return null;
}

// ---- verification helpers --------------------------------------------------

function cofactorDet(a: number[][]): number {
  const n = a.length;
  if (n === 1) return a[0][0];
  if (n === 2) return a[0][0] * a[1][1] - a[0][1] * a[1][0];
  let sum = 0;
  for (let j = 0; j < n; j++) {
    const minor = a.slice(1).map((row) => row.filter((_, k) => k !== j));
    sum += (j % 2 === 0 ? 1 : -1) * a[0][j] * cofactorDet(minor);
  }
  return sum;
}

function isIdentity(g: number[][] | null): boolean {
  if (!g) return false;
  return g.every((row, i) =>
    row.every((v, j) => Math.abs(v - (i === j ? 1 : 0)) <= 1e-6)
  );
}

/** Real eigenvalues, or null if any is complex (out of scope). */
function eigenReal(a: number[][]): number[] | null {
  const raw = eigs(a).values as unknown;
  const arr = Array.isArray(raw)
    ? raw
    : ((raw as { toArray?: () => unknown[] }).toArray?.() ?? []);
  const out: number[] = [];
  for (const v of arr) {
    const n = Number(v);
    if (!Number.isFinite(n)) return null; // complex eigenvalue → decline
    out.push(n);
  }
  return out.length ? out.sort((x, y) => x - y) : null;
}

function close(a: number, b: number): boolean {
  return Math.abs(a - b) <= 1e-6 * Math.max(1, Math.abs(a), Math.abs(b));
}

/** Rank by Gaussian row reduction that DECLINES (null) when any pivot lands in
 * the numerically-ambiguous band — neither clearly zero nor clearly nonzero. A
 * legitimate exact-rank matrix (integers, simple decimals) has pivots that are
 * either ~0 or O(magnitude); an entry engineered to sit in the crack (e.g.
 * differing by 1e-12) is declined rather than guessed. */
export function cleanRank(rows: number[][]): number | null {
  const m = rows.map((r) => [...r]);
  const nRows = m.length;
  const nCols = m[0]?.length ?? 0;
  const gmax = Math.max(1, ...m.flat().map((v) => Math.abs(v)));
  const LO = 1e-13 * gmax; // below this, a pivot is treated as zero
  const HI = 1e-7 * gmax; // above this, clearly nonzero; the gap between is ambiguous
  let rank = 0;
  for (let col = 0; col < nCols && rank < nRows; col++) {
    let piv = rank;
    let best = rank < nRows ? Math.abs(m[rank][col]) : 0;
    for (let r = rank + 1; r < nRows; r++) {
      if (Math.abs(m[r][col]) > best) {
        best = Math.abs(m[r][col]);
        piv = r;
      }
    }
    if (best < LO) continue; // clearly-zero column: no pivot here
    if (best < HI) return null; // ambiguous pivot → decline
    [m[rank], m[piv]] = [m[piv], m[rank]];
    const pv = m[rank][col];
    for (let r = 0; r < nRows; r++) {
      if (r === rank) continue;
      const f = m[r][col] / pv;
      for (let cc = col; cc < nCols; cc++) m[r][cc] -= f * m[rank][cc];
    }
    rank++;
  }
  return rank;
}

/** Rank as the number of nonzero eigenvalues of AᵀA (the squared singular values)
 * — an INDEPENDENT method (mathjs eigs) that must agree with cleanRank. */
export function gramRank(a: number[][]): number | null {
  try {
    const g = toGrid(multiply(transpose(a), a));
    if (!g) return null;
    const raw = eigs(g).values as unknown;
    const arr = Array.isArray(raw)
      ? raw
      : ((raw as { toArray?: () => unknown[] }).toArray?.() ?? []);
    const vals = arr.map((v) => Number(v));
    if (vals.some((v) => !Number.isFinite(v))) return null;
    const maxV = Math.max(1, ...vals.map((v) => Math.abs(v)));
    return vals.filter((v) => v > 1e-8 * maxV).length; // eigenvalues of AᵀA are ≥ 0
  } catch {
    return null;
  }
}

/** Independent row-by-column matrix multiply (checks mathjs). */
function matMul(a: number[][], b: number[][]): number[][] {
  return a.map((row) =>
    b[0].map((_, j) => row.reduce((s, v, k) => s + v * b[k][j], 0))
  );
}

function sameGrid(x: number[][], y: number[][]): boolean {
  return (
    x.length === y.length &&
    x.every((row, i) => row.length === y[i].length && row.every((v, j) => close(v, y[i][j])))
  );
}

function sameVec(x: number[], y: number[]): boolean {
  return x.length === y.length && x.every((v, i) => close(v, y[i]));
}

function dotN(a: number[], b: number[]): number {
  return a.reduce((s, v, i) => s + v * b[i], 0);
}

function toGrid(m: unknown): number[][] | null {
  const arr = Array.isArray(m)
    ? m
    : ((m as { toArray?: () => unknown[] }).toArray?.() ?? null);
  if (!Array.isArray(arr) || !Array.isArray(arr[0])) return null;
  return (arr as unknown[][]).map((row) => row.map((x) => Number(x)));
}

// ---- formatting ------------------------------------------------------------

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
function listAnswer(vals: number[]): FinalAnswer {
  return { latex: vals.map(fmtNum).join(",\\; "), plain: vals.map(fmtNum).join(", ") };
}
function matrixLatex(g: number[][]): string {
  return (
    "\\begin{pmatrix}" +
    g.map((row) => row.map(fmtNum).join(" & ")).join(" \\\\ ") +
    "\\end{pmatrix}"
  );
}
function matrixAnswer(g: number[][]): FinalAnswer {
  return {
    latex: matrixLatex(g),
    plain: g.map((row) => row.map(fmtNum).join(", ")).join("; "),
  };
}
function vecLatex(v: number[]): string {
  return "\\langle " + v.map(fmtNum).join(",\\; ") + " \\rangle";
}
function vecAnswer(v: number[]): FinalAnswer {
  return { latex: vecLatex(v), plain: "(" + v.map(fmtNum).join(", ") + ")" };
}
function matStep(a: number[][]): RawStep {
  return { ascii: "matrix", operationCode: "START", latex: "A = " + matrixLatex(a) };
}
function resultStep(latex: string): RawStep {
  return { ascii: latex, operationCode: "RESULT", latex };
}
function candidate(answer: FinalAnswer, name: string, steps: RawStep[]): SolveCandidate {
  return { answer, methods: [{ id: "linalg", name, examPick: true, steps }], plotExpression: null, verify: () => true };
}
