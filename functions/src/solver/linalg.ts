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
import { cross, det, dot, eigs, identity, inv, multiply, norm, subtract } from "mathjs";

import { FinalAnswer, RawStep, SolveCandidate } from "./types";

export type LinalgOp = "determinant" | "inverse" | "eigenvalues" | "multiply";

/** One matrix body (`1 & 2 \\ 3 & 4`) → grid, or null if ragged/non-numeric. */
function gridFrom(body: string): number[][] | null {
  const rows = body
    .split(/\\\\/)
    .map((r) => r.trim())
    .filter(Boolean);
  if (rows.length === 0) return null;
  const grid = rows.map((r) => r.split("&").map((c) => Number(c.replace(/[{}\s]/g, ""))));
  const w = grid[0].length;
  return grid.every((row) => row.length === w && row.every(Number.isFinite)) ? grid : null;
}

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

/** A matrix operation + its matrix (+ a second matrix for A·B), or null. */
export function parseLinalg(
  rawLatex: string
): { op: LinalgOp; matrix: number[][]; matrixB?: number[][] } | null {
  const matrices = parseMatrices(rawLatex);
  if (matrices.length === 0) return null;

  // Two matrices side by side (or with ×/·) → multiply, when conformable.
  if (matrices.length >= 2) {
    const [a, b] = matrices;
    return a[0].length === b.length ? { op: "multiply", matrix: a, matrixB: b } : null;
  }

  const matrix = matrices[0];
  const lower = rawLatex.toLowerCase();
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
    }
  } catch {
    return null;
  }
  return null;
}

// ---- Vectors (dot / cross / magnitude) -------------------------------------

export type VectorOp = "dot" | "cross" | "magnitude";

/** Numeric vectors written as `(1, 2, 3)` or `\langle 1,2,3 \rangle`. */
function extractVectors(rawLatex: string): number[][] {
  const out: number[][] = [];
  const re = /\(([-\d.,\s]+)\)|\\langle([-\d.,\s]+)\\rangle/g;
  for (let m = re.exec(rawLatex); m; m = re.exec(rawLatex)) {
    const body = (m[1] ?? m[2] ?? "").trim();
    if (!body.includes(",")) continue;
    const v = body.split(",").map((t) => Number(t.trim())).filter(Number.isFinite);
    if (v.length >= 2) out.push(v);
  }
  return out;
}

/** A vector operation + its operand(s): dot/cross (two), magnitude (one). */
export function parseVectors(
  rawLatex: string
): { op: VectorOp; vectors: number[][] } | null {
  const vecs = extractVectors(rawLatex);
  const lower = rawLatex.toLowerCase();
  if (/magnitude|norm|length/.test(lower) && vecs.length === 1) {
    return { op: "magnitude", vectors: vecs };
  }
  if ((/cross/.test(lower) || /\\times|×/.test(rawLatex)) && vecs.length === 2) {
    return { op: "cross", vectors: vecs };
  }
  if ((/dot/.test(lower) || /\\cdot|·/.test(rawLatex)) && vecs.length === 2) {
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
