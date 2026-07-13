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
import { det, eigs, identity, inv, multiply, subtract } from "mathjs";

import { FinalAnswer, RawStep, SolveCandidate } from "./types";

export type LinalgOp = "determinant" | "inverse" | "eigenvalues";

/** Parse `\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}` (p/b/v-matrix) → grid. */
function parseMatrix(rawLatex: string): number[][] | null {
  const m = rawLatex.match(
    /\\begin\{[pbv]matrix\}([\s\S]*?)\\end\{[pbv]matrix\}/
  );
  if (!m) return null;
  const rows = m[1]
    .split(/\\\\/)
    .map((r) => r.trim())
    .filter(Boolean);
  if (rows.length === 0) return null;
  const grid = rows.map((r) =>
    r.split("&").map((c) => Number(c.replace(/[{}\s]/g, "")))
  );
  const width = grid[0].length;
  if (!grid.every((row) => row.length === width && row.every(Number.isFinite))) {
    return null;
  }
  return grid;
}

/** A matrix operation + its square matrix, or null. */
export function parseLinalg(
  rawLatex: string
): { op: LinalgOp; matrix: number[][] } | null {
  const matrix = parseMatrix(rawLatex);
  if (!matrix) return null;

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
  // det / inverse / eigenvalues all require a square matrix.
  if (matrix.length !== matrix[0].length) return null;
  return { op, matrix };
}

/** Solves a linear-algebra request, gated by a property check. */
export function solveLinalg(cls: {
  linalgOp?: string;
  matrixData?: number[][];
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
function matStep(a: number[][]): RawStep {
  return { ascii: "matrix", operationCode: "START", latex: "A = " + matrixLatex(a) };
}
function resultStep(latex: string): RawStep {
  return { ascii: latex, operationCode: "RESULT", latex };
}
function candidate(answer: FinalAnswer, name: string, steps: RawStep[]): SolveCandidate {
  return { answer, methods: [{ id: "linalg", name, examPick: true, steps }], plotExpression: null, verify: () => true };
}
