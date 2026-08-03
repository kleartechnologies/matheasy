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
import {
  add as mjsAdd,
  cross,
  det,
  dot,
  eigs,
  identity,
  inv,
  multiply,
  norm,
  subtract,
  transpose,
} from "mathjs";

import { exactForm } from "./exact";
import { FinalAnswer, RawStep, SolveCandidate } from "./types";

export type LinalgOp =
  | "determinant"
  | "inverse"
  | "eigenvalues"
  | "multiply"
  | "add"
  | "subtract"
  | "rank"
  // Added for the matrix problem sheet, which asks for these far more often
  // than it asks for an eigenvalue.
  | "transpose"
  | "trace"
  | "power" // Aⁿ for a non-negative integer n
  | "element" // the (i, j) entry, written aᵢⱼ
  | "symmetric_split" // A = ½(A+Aᵀ) + ½(A−Aᵀ)
  | "both_products"; // AB and BA together — the point being that they differ

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

/** `a_{13}` / `a_13` / "the element a13" → the (row, col) it names, or null. */
function parseElementIndex(rawLatex: string): [number, number] | null {
  const m = /(?<![A-Za-z])[a-z]\s*_\s*\{?\s*(\d)\s*,?\s*(\d)\s*\}?/.exec(rawLatex);
  if (!m) return null;
  const i = Number(m[1]);
  const j = Number(m[2]);
  return i >= 1 && j >= 1 ? [i, j] : null;
}

/** The integer exponent in `A^{2}` / `A^3`, or null. It also reads the exponent
 * hung directly off the written-out grid — `\begin{pmatrix}…\end{pmatrix}^3`,
 * which names no matrix at all and so matched nothing before. */
function parseMatrixPower(rawLatex: string): number | null {
  const m =
    /(?<![A-Za-z0-9_])[A-Z]\s*\^\s*\{?\s*(\d+)\s*\}?/.exec(rawLatex) ??
    /\\end\{[bp]matrix\}\s*\^\s*\{?\s*(\d+)\s*\}?/.exec(rawLatex);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isInteger(n) && n >= 0 && n <= 12 ? n : null;
}

/** A matrix operation + its matrix (+ a second matrix for A±B / A·B), or null. */
export function parseLinalg(
  rawLatex: string
): { op: LinalgOp; matrix: number[][]; matrixB?: number[][]; args?: number[] } | null {
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
    // "Show that AB = 0 but BA ≠ 0" — the question is about BOTH orders, and
    // returning only AB would answer half of it. Both must be conformable.
    if (
      /\bba\b|\bboth\s+(?:orders?|products?)\b|ab\s*(?:and|,)\s*ba|\bcommute\b/i.test(lower) &&
      a[0].length === b.length &&
      b[0].length === a.length
    ) {
      return { op: "both_products", matrix: a, matrixB: b };
    }
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

  // Naming a single entry — "write down a₁₃ and a₃₁". This is checked before
  // the square-only ops because it works for any shape, and it must lose to a
  // determinant/inverse keyword, hence the hasOuterOp exclusion.
  if (!hasOuterOp && /\belement\b|\bentry\b|\bcomponent\b/.test(lower)) {
    const idx = parseElementIndex(rawLatex);
    if (idx && idx[0] <= matrix.length && idx[1] <= matrix[0].length) {
      return { op: "element", matrix, args: idx };
    }
    return null; // asked for an entry we couldn't pin down — decline
  }

  // Transpose applies to any shape too.
  if (/\btranspose\b|\^\s*\{?\s*(?:T|\\mathsf\{T\}|\\top)\s*\}?/.test(rawLatex) ||
      /\btranspose\b/.test(lower)) {
    return { op: "transpose", matrix };
  }

  // The symmetric / skew-symmetric decomposition.
  if (/\bskew[-\s]?symmetric\b/.test(lower) || (/\bsymmetric\b/.test(lower) && /\bsum\b|\bdecompos|\bexpress\b|\bwrite\b/.test(lower))) {
    if (matrix.length === matrix[0].length) return { op: "symmetric_split", matrix };
    return null;
  }

  if (/\btrace\b|\\operatorname\{tr\}|\btr\s*\(/.test(lower)) {
    if (matrix.length !== matrix[0].length) return null;
    return { op: "trace", matrix };
  }

  // A^n for an integer n ≥ 0. Checked BEFORE the `^{-1}` inverse cue below, and
  // the regex only accepts non-negative integers, so `A^{-1}` never lands here.
  if (!hasOuterOp) {
    const power = parseMatrixPower(rawLatex);
    if (power !== null && matrix.length === matrix[0].length) {
      return { op: "power", matrix, args: [power] };
    }
  }

  let op: LinalgOp | null = null;
  if (/\\begin\{vmatrix\}/.test(rawLatex) || /\bdeterminant\b|\bdet\b|\\det/.test(lower)) {
    op = "determinant";
  } else if (/eigen/.test(lower)) {
    op = "eigenvalues";
  } else if (
    /inverse/.test(lower) ||
    /\}\s*\^\s*\{?\s*-?\s*1/.test(rawLatex) ||
    // `A^{-1}` written against a NAME rather than against the bracket itself —
    // the only form the inverse cue used to miss, and the form a sheet uses.
    /(?<![A-Za-z0-9_])[A-Z]\s*\^\s*\{?\s*-\s*1\s*\}?/.test(rawLatex)
  ) {
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
  linalgArgs?: number[];
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
      case "transpose": {
        const t = toGrid(transpose(A));
        // The gate: (Aᵀ)ᵢⱼ must be Aⱼᵢ for every entry, read off the ORIGINAL —
        // mathjs's own transpose is never consulted for the check.
        if (!t || t.length !== A[0].length || t[0].length !== A.length) return null;
        for (let i = 0; i < t.length; i++) {
          for (let j = 0; j < t[0].length; j++) {
            if (!close(t[i][j], A[j][i])) return null;
          }
        }
        return candidate(matrixAnswer(t), "Transpose", [
          matStep(A),
          resultStep("A^{T} = " + matrixLatex(t)),
        ]);
      }
      case "trace": {
        if (A.length !== A[0].length) return null;
        let tr = 0;
        for (let i = 0; i < n; i++) tr += A[i][i];
        // Independent check: the trace is also the SUM OF THE EIGENVALUES. When
        // the spectrum isn't real the identity still holds but we can't see it,
        // so that case falls back to the (exact) diagonal sum alone.
        const vals = eigenReal(A);
        if (vals && vals.length === n) {
          const s = vals.reduce((x, y) => x + y, 0);
          if (Math.abs(s - tr) > 1e-6 * Math.max(1, Math.abs(tr))) return null;
        }
        return candidate(fmt(tr), "Trace", [
          matStep(A),
          resultStep("\\operatorname{tr}(A) = " + fmtNum(tr)),
        ]);
      }
      case "power": {
        const k = cls.linalgArgs?.[0];
        if (k === undefined || A.length !== A[0].length) return null;
        // Built by repeated multiplication with the hand-rolled product…
        let out = identityGrid(n);
        for (let step = 0; step < k; step++) out = matMul(out, A);
        // …then checked against mathjs's, which shares no code with it.
        let ref = toGrid(identity(n));
        for (let step = 0; step < k && ref; step++) ref = toGrid(multiply(ref, A));
        if (!ref || !sameGrid(out, ref)) return null;
        return candidate(matrixAnswer(out), `A^{${k}}`, [
          matStep(A),
          resultStep(`A^{${k}} = ` + matrixLatex(out)),
        ]);
      }
      case "element": {
        const [i, j] = cls.linalgArgs ?? [];
        if (!i || !j || i > A.length || j > A[0].length) return null;
        const v = A[i - 1][j - 1];
        if (!Number.isFinite(v)) return null;
        return candidate(fmt(v), "Matrix element", [
          matStep(A),
          resultStep(`a_{${i}${j}} = ${fmtNum(v)}`),
        ]);
      }
      case "symmetric_split": {
        if (A.length !== A[0].length) return null;
        const S = A.map((row, i) => row.map((v, j) => (v + A[j][i]) / 2));
        const K = A.map((row, i) => row.map((v, j) => (v - A[j][i]) / 2));
        // Three things must hold, and all three are checked: S is symmetric,
        // K is skew-symmetric, and S + K reconstructs A exactly.
        for (let i = 0; i < n; i++) {
          for (let j = 0; j < n; j++) {
            if (!close(S[i][j], S[j][i])) return null;
            if (!close(K[i][j], -K[j][i])) return null;
            if (!close(S[i][j] + K[i][j], A[i][j])) return null;
          }
        }
        return candidate(
          {
            latex: `${matrixLatex(S)} + ${matrixLatex(K)}`,
            plain: `symmetric: ${matrixAnswer(S).plain}; skew-symmetric: ${matrixAnswer(K).plain}`,
          },
          "Symmetric + skew-symmetric parts",
          [
            matStep(A),
            resultStep("S = \\tfrac{1}{2}(A + A^{T}) = " + matrixLatex(S)),
            resultStep("K = \\tfrac{1}{2}(A - A^{T}) = " + matrixLatex(K)),
            resultStep("A = S + K"),
          ]
        );
      }
      case "both_products": {
        const b = cls.matrixB;
        if (!b || A[0].length !== b.length || b[0].length !== A.length) return null;
        const ab = toGrid(multiply(A, b));
        const ba = toGrid(multiply(b, A));
        // Each product is re-derived by the hand-rolled row×column routine.
        if (!ab || !ba || !sameGrid(ab, matMul(A, b)) || !sameGrid(ba, matMul(b, A))) return null;
        const commutes = sameShape(ab, ba) && sameGrid(ab, ba);
        return candidate(
          {
            latex: `AB = ${matrixLatex(ab)},\\quad BA = ${matrixLatex(ba)}`,
            plain: `AB = ${matrixAnswer(ab).plain}; BA = ${matrixAnswer(ba).plain}`,
          },
          "AB and BA",
          [
            matStep(A),
            resultStep("AB = " + matrixLatex(ab)),
            resultStep("BA = " + matrixLatex(ba)),
            resultStep(
              commutes
                ? "AB = BA \\text{ — these two commute}"
                : "AB \\neq BA \\text{ — matrix multiplication is not commutative}"
            ),
          ]
        );
      }
    }
  } catch {
    return null;
  }
  return null;
}

// ---- Vectors (dot / cross / magnitude) -------------------------------------

export type VectorOp =
  | "dot"
  | "cross"
  | "magnitude"
  | "independent"
  | "spans"
  // Added for the vector-geometry sheets, which are mostly these.
  | "add"
  | "subtract"
  | "angle" // the angle between two vectors
  | "unit" // the unit vector in the direction of a
  | "projection" // the component of a along b
  | "triple" // the scalar triple product a·(b×c)
  | "coplanar" // are three vectors coplanar? (triple product zero)
  | "midpoint" // the midpoint of AB
  | "section" // the point dividing AB in a given ratio
  | "distance_origin_line" // shortest distance from the origin to the line AB
  | "resolve" // components of a vector given its magnitude and direction
  | "perpendicular_lambda" // the λ making a + λb perpendicular to c
  | "line_distance" // shortest distance between two lines, skew or parallel
  | "basis_expansion"; // d written in terms of a non-coplanar a, b, c

/** Numeric vectors written as `(1, 2, 3)` or `\langle 1,2,3 \rangle`.
 * `decoratedLatex` is the pre-`normalizeMacros` text, which is the only place the
 * ijk fallback below can still see a `\mathbf{}` wrapper. */
function extractVectors(rawLatex: string, decoratedLatex: string): number[][] {
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
  return out.length ? out : extractIjkVectors(decoratedLatex);
}

/**
 * Vectors written in the ijk basis — `3\mathbf{i} - 2\mathbf{j} + \mathbf{k}`,
 * which is how the vector sheets write every single one of them, and which the
 * bracket form above cannot see at all.
 *
 * The basis letter must be DECORATED (`\mathbf`, `\vec`, `\hat`, `\underline`,
 * `\boldsymbol`, `\bm`). A bare `i` is not accepted: in this app it is far more
 * likely to be the imaginary unit, and mistaking one for the other would answer
 * a completely different question.
 */
function extractIjkVectors(rawLatex: string): number[][] {
  const BASIS = /(?:[-+]?\s*(?:\d+(?:\.\d+)?)?)\s*\\(?:mathbf|vec|hat|underline|boldsymbol|bm)\s*\{\s*([ijk])\s*\}/g;
  // Each "segment" is one vector: sheets separate them with a comma, "and", or
  // a definition (`\mathbf{a} = …`).
  const segments = rawLatex.split(/,|\band\b|\bwhere\b|;/i);
  const out: number[][] = [];
  for (const seg of segments) {
    const comp: Record<string, number> = {};
    let found = false;
    BASIS.lastIndex = 0;
    for (let m = BASIS.exec(seg); m; m = BASIS.exec(seg)) {
      const head = m[0].slice(0, m[0].indexOf("\\")).replace(/\s+/g, "");
      const sign = head.startsWith("-") ? -1 : 1;
      const digits = head.replace(/^[-+]/, "");
      const coeff = digits === "" ? 1 : Number(digits);
      if (!Number.isFinite(coeff)) return [];
      comp[m[1]] = sign * coeff;
      found = true;
    }
    if (!found) continue;
    // i and j are required; k is optional, so a 2-D vector stays 2-D rather
    // than silently acquiring a third component.
    if (comp.i === undefined && comp.j === undefined) continue;
    const v = [comp.i ?? 0, comp.j ?? 0];
    if (comp.k !== undefined) v.push(comp.k);
    out.push(v);
  }
  // Ragged results (a 2-D and a 3-D vector in one question) are ambiguous —
  // pad only when a k appeared somewhere, since then the plane is z = 0.
  const maxLen = out.reduce((m, v) => Math.max(m, v.length), 0);
  return out.map((v) => (v.length < maxLen ? [...v, ...Array(maxLen - v.length).fill(0)] : v));
}

/** Every bracketed vector together with where it sits, so the words immediately
 * in front of it can be read. */
function vectorsWithIndex(s: string): { v: number[]; start: number; end: number }[] {
  const out: { v: number[]; start: number; end: number }[] = [];
  const re = /\(([-\d.,\s]+)\)|\\langle([-\d.,\s]+)\\rangle/g;
  for (let m = re.exec(s); m; m = re.exec(s)) {
    const body = (m[1] ?? m[2] ?? "").trim();
    if (!body.includes(",")) continue;
    const toks = body.split(",").map((t) => numToken(t));
    if (toks.length >= 2 && toks.every((t) => t !== null)) {
      out.push({ v: toks as number[], start: m.index, end: m.index + m[0].length });
    }
  }
  return out;
}

/**
 * Two lines, each given as a point and a direction.
 *
 * Which of the four vectors is which is the ENTIRE question — read the roles
 * backwards and the answer is a different number that looks just as plausible.
 * So the role is taken from the words in front of each vector, and a line whose
 * two vectors are both points, both directions, or neither is declined.
 */
function parseTwoLines(rawLatex: string): number[][] | null {
  const found = vectorsWithIndex(rawLatex);
  if (found.length !== 4) return null;
  if (!found.every((f) => f.v.length === found[0].v.length && f.v.length >= 2)) return null;

  const roleOf = (gap: string): "point" | "dir" | null => {
    const g = gap.toLowerCase();
    // A scalar multiplier written right against the bracket — the `s` of
    // "r = (1,3,0) + s(2,3,2)" — names a direction as plainly as the word does.
    const dirAt = Math.max(
      g.lastIndexOf("direction"),
      g.lastIndexOf("parallel to"),
      g.search(/[+\-−]\s*(?:\\?(?:lambda|mu|alpha|beta|s|t|u|k)|[λμ])\s*$/) ,
      g.lastIndexOf("along")
    );
    const ptAt = Math.max(
      g.lastIndexOf("through"),
      g.lastIndexOf("point"),
      g.lastIndexOf("passing"),
      g.lastIndexOf("passes")
    );
    if (dirAt < 0 && ptAt < 0) return null;
    return dirAt > ptAt ? "dir" : "point";
  };

  const roles: ("point" | "dir" | null)[] = found.map((f, i) =>
    roleOf(rawLatex.slice(i === 0 ? 0 : found[i - 1].end, f.start))
  );
  // A line has exactly one point and one direction, so naming either one names
  // the other. Only a pair with NO cue at all, or two cues that agree, is
  // genuinely ambiguous.
  for (const [a, b] of [[0, 1], [2, 3]] as const) {
    if (roles[a] === null && roles[b] === null) return null;
    if (roles[a] === null) roles[a] = roles[b] === "dir" ? "point" : "dir";
    if (roles[b] === null) roles[b] = roles[a] === "dir" ? "point" : "dir";
    if (roles[a] === roles[b]) return null;
  }

  const line = (a: number, b: number) =>
    roles[a] === "point" ? [found[a].v, found[b].v] : [found[b].v, found[a].v];
  const [p1, d1] = line(0, 1);
  const [p2, d2] = line(2, 3);
  return [p1, d1, p2, d2];
}

/** An angle written as `30^\circ`, `30 degrees`, `\pi/3`, or a bare number of
 * radians — returned in RADIANS, or null when it isn't there. */
function parseAngleRadians(rawLatex: string): number | null {
  const deg = /(-?\d+(?:\.\d+)?)\s*(?:\^\s*\{?\s*\\circ\s*\}?|\\degree|°|\s*degrees?\b)/i.exec(
    rawLatex
  );
  if (deg) return (Number(deg[1]) * Math.PI) / 180;
  const piFrac = /(-?\d*)\s*\\pi\s*\/\s*(\d+)/.exec(rawLatex);
  if (piFrac) {
    const num = piFrac[1] === "" || piFrac[1] === "+" ? 1 : piFrac[1] === "-" ? -1 : Number(piFrac[1]);
    return (num * Math.PI) / Number(piFrac[2]);
  }
  const fracPi = /\\frac\s*\{\s*(-?\d*)\s*\\pi\s*\}\s*\{\s*(\d+)\s*\}/.exec(rawLatex);
  if (fracPi) {
    const num = fracPi[1] === "" || fracPi[1] === "+" ? 1 : fracPi[1] === "-" ? -1 : Number(fracPi[1]);
    return (num * Math.PI) / Number(fracPi[2]);
  }
  return null;
}

/** The `m : n` of "divides AB in the ratio 2 : 3". */
function parseRatio(rawLatex: string): [number, number] | null {
  const m = /(\d+(?:\.\d+)?)\s*(?::|\\colon)\s*(\d+(?:\.\d+)?)/.exec(rawLatex);
  if (!m) return null;
  const a = Number(m[1]);
  const b = Number(m[2]);
  return a > 0 && b > 0 ? [a, b] : null;
}

/** A vector operation + its operand(s): dot/cross (two), magnitude (one).
 * The cues are deliberately narrow: the magnitude trigger is the vector-specific
 * "magnitude"/"norm" (or \lVert…\rVert bars) — NOT the generic word "length",
 * which collides with intervals, line segments and word problems and would hijack
 * them into a bogus |v|. dot/cross still require TWO clean vector operands, so a
 * stray \cdot/\times (e.g. scalar multiplication) can't trigger one on its own. */
export function parseVectors(
  rawLatex: string,
  decoratedLatex: string = rawLatex
): { op: VectorOp; vectors: number[][]; args?: number[] } | null {
  // A stat word wrapping a vector op ("range of the cross product") is a nested,
  // un-verifiable composition — decline rather than return the raw vector op.
  if (/\b(mean|average|median|mode|variance|deviation|range|summation)\b/i.test(rawLatex)) {
    return null;
  }
  const vecs = extractVectors(rawLatex, decoratedLatex);
  const lower = rawLatex.toLowerCase();

  // --- Resolving a magnitude + direction into components -------------------
  // "A force of magnitude 10 acts at 30° to the x-axis — find its components."
  // This one takes NUMBERS, not vectors, so it is matched before anything that
  // needs an operand list.
  if (
    vecs.length === 0 &&
    /\bcomponents?\b|\bresolve\b/.test(lower) &&
    /\bmagnitude\b|\blength\b|\bforce\b|\bspeed\b|\bvelocity\b/.test(lower)
  ) {
    const theta = parseAngleRadians(rawLatex);
    const mag = /(?:magnitude|length|force|speed|velocity)\D{0,20}?(\d+(?:\.\d+)?)/i.exec(rawLatex);
    if (theta !== null && mag) {
      const L = Number(mag[1]);
      if (L > 0) return { op: "resolve", vectors: [], args: [L, theta] };
    }
    return null; // asked to resolve something we couldn't pin down — decline
  }

  // --- The shortest distance between two lines -----------------------------
  // Four vectors and two lines, so nothing below can reach it. It sits here,
  // before the operand-count cues, because "distance between the LINES" and
  // "distance between the POINTS" are one word apart.
  if (
    /\bdistance\b/.test(lower) &&
    /\blines\b|\bline\b[\s\S]*\bline\b/.test(lower) &&
    !/\borigin\b/.test(lower)
  ) {
    const lines = parseTwoLines(rawLatex);
    if (lines) return { op: "line_distance", vectors: lines };
    return null; // two lines were asked about but couldn't be pinned down
  }

  // --- Solve for the scalar: "find λ so that a + λb ⊥ c" -------------------
  // Ahead of the perpendicular/angle cues below, which would otherwise read the
  // same sentence as a yes/no question about two fixed vectors. It needs the λ to
  // sit BETWEEN the first two vectors, because that is what says which of them is
  // being scaled — get that backwards and the answer is a different number.
  if (
    vecs.length === 3 &&
    vecs.every((v) => v.length === vecs[0].length) &&
    /\bperpendicular\b|\borthogonal\b|\bat\s+right\s+angles\b/.test(lower)
  ) {
    const gaps = vectorGaps(rawLatex);
    if (/^\s*[+\-−]\s*(?:\\lambda|\\mu|\\alpha|\\beta|λ|μ|[a-z])\s*$/i.test(gaps[0] ?? "")) {
      return { op: "perpendicular_lambda", vectors: vecs };
    }
    return null; // asked for a scalar we can't locate — decline, never guess
  }

  // --- "express d in terms of a, b and c" -----------------------------------
  // The split is what makes the operands unambiguous: the target is the vector
  // BEFORE "in terms of", the basis is everything after it. Without that the four
  // vectors are just a list and there is no telling which one is being expanded.
  const termsOf = /\bin\s+terms\s+of\b/i.exec(rawLatex);
  if (termsOf && /\bexpress\b|\bwrite\b|\bresolve\b|\bdecompos/.test(lower)) {
    const head = rawLatex.slice(0, termsOf.index);
    const tail = rawLatex.slice(termsOf.index);
    const target = extractVectors(head, head);
    const basis = extractVectors(tail, tail);
    const n = target[0]?.length;
    if (
      target.length === 1 &&
      basis.length === n &&
      n >= 2 &&
      basis.every((v) => v.length === n)
    ) {
      return { op: "basis_expansion", vectors: [target[0], ...basis] };
    }
    return null; // an expansion we can't pin down is not one we should attempt
  }

  // Linear independence / span — need ≥2 vectors that live in the SAME space.
  const sameLen = vecs.length >= 2 && vecs.every((v) => v.length === vecs[0].length);
  if (sameLen && /linear(?:ly)?\s+(?:in)?depend/.test(lower)) {
    return { op: "independent", vectors: vecs };
  }
  if (sameLen && /\bspan(?:s|ned|ning)?\b/.test(lower)) {
    return { op: "spans", vectors: vecs };
  }

  // --- Three vectors: the scalar triple product and coplanarity ------------
  if (vecs.length === 3 && vecs.every((v) => v.length === 3)) {
    if (/\bcoplanar\b/.test(lower)) return { op: "coplanar", vectors: vecs };
    if (/\btriple\b/.test(lower) || /\bvolume\b.*\bparallelepiped\b/.test(lower)) {
      return { op: "triple", vectors: vecs };
    }
  }

  // --- Two points: midpoint, section, distance from the origin to a line ---
  if (vecs.length === 2 && vecs[0].length === vecs[1].length) {
    if (/\bmid[-\s]?point\b/.test(lower)) return { op: "midpoint", vectors: vecs };
    if (/\bratio\b|\bdivid(?:es|ing)\b|\bsection\b/.test(lower)) {
      const ratio = parseRatio(rawLatex);
      if (ratio) return { op: "section", vectors: vecs, args: ratio };
      return null; // a ratio was asked for but not stated — decline
    }
    if (
      /\bdistance\b|\bperpendicular\s+distance\b|\bshortest\b/.test(lower) &&
      /\borigin\b/.test(lower) &&
      /\bline\b/.test(lower)
    ) {
      return { op: "distance_origin_line", vectors: vecs };
    }
  }

  const magCue =
    /\bmagnitude\b|\bnorm\b/.test(lower) ||
    /\\lVert|\\rVert|\\Vert|\\\|/.test(rawLatex);
  // "the unit vector in the direction of a" — checked before the plain
  // magnitude cue, which the same sentence often also contains.
  if (vecs.length === 1 && /\bunit\s+vector\b|\bnormalis|\bnormaliz|\bdirection\s+cosines?\b/.test(lower)) {
    return { op: "unit", vectors: vecs };
  }
  if (magCue && vecs.length === 1) {
    return { op: "magnitude", vectors: vecs };
  }
  if (vecs.length === 2 && vecs[0].length === vecs[1].length) {
    if (/\bangle\s+between\b|\bangle\b/.test(lower)) return { op: "angle", vectors: vecs };
    if (/\bprojection\b|\bcomponent\s+of\b.*\b(?:along|onto|in\s+the\s+direction)\b|\bresolute\b/.test(lower)) {
      return { op: "projection", vectors: vecs };
    }
  }
  if ((/\bcross\b/.test(lower) || /\\times|×/.test(rawLatex)) && vecs.length === 2) {
    return { op: "cross", vectors: vecs };
  }
  if ((/\bdot\b/.test(lower) || /\\cdot|·/.test(rawLatex)) && vecs.length === 2) {
    return { op: "dot", vectors: vecs };
  }
  // --- Plain vector addition and subtraction -------------------------------
  // Only with an EXPLICIT connective between exactly two operands, so a stray
  // minus sign inside a component can never turn a question into a difference.
  if (vecs.length === 2 && vecs[0].length === vecs[1].length) {
    const gap = vectorGap(rawLatex);
    if (/^\s*\+\s*$/.test(gap)) return { op: "add", vectors: vecs };
    if (/^\s*[-−]\s*$/.test(gap)) return { op: "subtract", vectors: vecs };
  }
  return null;
}

/** The connective between the first two bracketed vectors. */
function vectorGap(rawLatex: string): string {
  return vectorGaps(rawLatex)[0] ?? "";
}

/** Every connective BETWEEN consecutive bracketed vectors, in order — `gaps[0]`
 * separates the first from the second, and so on. */
function vectorGaps(rawLatex: string): string[] {
  const SENTINEL = "@@VEC@@";
  const parts = rawLatex
    .replace(/\(([-\d.,\s]+)\)|\\langle([-\d.,\s]+)\\rangle/g, SENTINEL)
    .split(SENTINEL);
  return parts.slice(1, -1);
}

export function solveVectors(cls: {
  vectorOp?: string;
  vectorData?: number[][];
  vectorArgs?: number[];
}): SolveCandidate | null {
  const op = cls.vectorOp as VectorOp | undefined;
  const vecs = cls.vectorData;
  if (!op || !vecs) return null;
  try {
    switch (op) {
      case "resolve": {
        const [L, theta] = cls.vectorArgs ?? [];
        if (!Number.isFinite(L) || !Number.isFinite(theta) || L <= 0) return null;
        const v = [L * Math.cos(theta), L * Math.sin(theta)];
        // The components must rebuild BOTH the magnitude and the direction they
        // came from — that is the whole content of the claim.
        if (!close(Math.hypot(v[0], v[1]), L)) return null;
        const back = Math.atan2(v[1], v[0]);
        if (Math.abs(Math.cos(back) - Math.cos(theta)) > 1e-9) return null;
        if (Math.abs(Math.sin(back) - Math.sin(theta)) > 1e-9) return null;
        const deg = String(round10((theta * 180) / Math.PI));
        return candidate(vecAnswer(v), "Components", [
          resultStep(`L = ${fmtNum(L)},\\; \\theta = ${deg}^{\\circ}`),
          resultStep(
            `(L\\cos\\theta,\\; L\\sin\\theta) = ${vecLatex(v)}`
          ),
        ]);
      }
      case "add":
      case "subtract": {
        const [a, b] = vecs;
        if (a.length !== b.length) return null;
        const s = op === "add" ? 1 : -1;
        const out = a.map((x, i) => x + s * b[i]);
        // Independent check via mathjs, which never touched the loop above.
        const ref = toVec(op === "add" ? mjsAdd(a, b) : subtract(a, b));
        if (!ref || !sameVec(out, ref)) return null;
        return candidate(vecAnswer(out), op === "add" ? "Vector sum" : "Vector difference", [
          resultStep(`a ${op === "add" ? "+" : "-"} b = ${vecLatex(out)}`),
        ]);
      }
      case "unit": {
        const a = vecs[0];
        const mag = Math.sqrt(a.reduce((s, x) => s + x * x, 0));
        if (!(mag > 1e-12)) return null; // the zero vector has no direction
        const u = a.map((x) => x / mag);
        // Two properties, both checked: û is a unit vector, and scaling it back
        // up by |a| returns the ORIGINAL vector componentwise.
        if (!close(Math.sqrt(u.reduce((s, x) => s + x * x, 0)), 1)) return null;
        for (let i = 0; i < a.length; i++) if (!close(u[i] * mag, a[i])) return null;
        return candidate(vecAnswer(u), "Unit vector", [
          resultStep(`\\lVert a \\rVert = ${fmtNum(mag)}`),
          resultStep(`\\hat{a} = \\frac{a}{\\lVert a \\rVert} = ${vecLatex(u)}`),
        ]);
      }
      case "angle": {
        const [a, b] = vecs;
        if (a.length !== b.length) return null;
        const ma = Math.sqrt(a.reduce((s, x) => s + x * x, 0));
        const mb = Math.sqrt(b.reduce((s, x) => s + x * x, 0));
        if (!(ma > 1e-12) || !(mb > 1e-12)) return null;
        const d = dotN(a, b);
        const cosT = Math.max(-1, Math.min(1, d / (ma * mb)));
        const theta = Math.acos(cosT);
        // The gate: |a||b|cos θ must reproduce the dot product, and θ must be in
        // [0, π] — the range the angle between two vectors is defined on.
        if (theta < -1e-12 || theta > Math.PI + 1e-12) return null;
        if (Math.abs(ma * mb * Math.cos(theta) - d) > 1e-6 * Math.max(1, Math.abs(d))) return null;
        const deg = round10((theta * 180) / Math.PI);
        return candidate(
          { latex: `${fmtNum(deg)}^{\\circ}`, plain: `${fmtNum(deg)} degrees` },
          "Angle between two vectors",
          [
            resultStep(`\\cos\\theta = \\frac{a \\cdot b}{\\lVert a\\rVert\\,\\lVert b\\rVert} = \\frac{${fmtNum(d)}}{${fmtNum(ma)} \\times ${fmtNum(mb)}}`),
            resultStep(`\\theta = ${fmtNum(deg)}^{\\circ}`),
          ]
        );
      }
      case "projection": {
        const [a, b] = vecs;
        if (a.length !== b.length) return null;
        const bb = dotN(b, b);
        if (!(bb > 1e-12)) return null;
        const k = dotN(a, b) / bb;
        const p = b.map((x) => k * x);
        // The two defining properties of a projection, both checked: the
        // remainder a − p is PERPENDICULAR to b, and p lies ALONG b.
        const rem = a.map((x, i) => x - p[i]);
        if (Math.abs(dotN(rem, b)) > 1e-6 * Math.max(1, Math.abs(dotN(a, b)))) return null;
        for (let i = 0; i < b.length; i++) if (!close(p[i], k * b[i])) return null;
        return candidate(vecAnswer(p), "Projection of a onto b", [
          resultStep(`\\text{proj}_b\\,a = \\frac{a \\cdot b}{b \\cdot b}\\,b`),
          resultStep(`= ${vecLatex(p)}`),
        ]);
      }
      case "triple":
      case "coplanar": {
        if (vecs.length !== 3 || !vecs.every((v) => v.length === 3)) return null;
        const [a, b, c] = vecs;
        const bc = [
          b[1] * c[2] - b[2] * c[1],
          b[2] * c[0] - b[0] * c[2],
          b[0] * c[1] - b[1] * c[0],
        ];
        const t = dotN(a, bc);
        // Two INDEPENDENT routes to the same scalar: a·(b×c), the 3×3 cofactor
        // determinant of the rows, and the cyclic identity b·(c×a). All three
        // must agree, or the number goes nowhere.
        const viaDet = cofactorDet([a, b, c]);
        const ca = [
          c[1] * a[2] - c[2] * a[1],
          c[2] * a[0] - c[0] * a[2],
          c[0] * a[1] - c[1] * a[0],
        ];
        const cyclic = dotN(b, ca);
        if (!close(t, viaDet) || !close(t, cyclic)) return null;
        if (op === "triple") {
          return candidate(fmt(t), "Scalar triple product", [
            resultStep(`b \\times c = ${vecLatex(bc)}`),
            resultStep(`a \\cdot (b \\times c) = ${fmtNum(t)}`),
          ]);
        }
        const scale = Math.max(1, ...vecs.flat().map(Math.abs)) ** 3;
        const isCoplanar = Math.abs(t) <= 1e-9 * scale;
        const plain = isCoplanar ? "Yes — they are coplanar" : "No — they are not coplanar";
        return candidate(
          { latex: `\\text{${plain}}`, plain },
          "Coplanarity",
          [
            resultStep(`a \\cdot (b \\times c) = ${fmtNum(t)}`),
            resultStep(
              isCoplanar
                ? "\\text{the triple product is zero} \\Rightarrow \\text{coplanar}"
                : "\\text{the triple product is non-zero} \\Rightarrow \\text{not coplanar}"
            ),
          ]
        );
      }
      case "midpoint": {
        const [a, b] = vecs;
        if (a.length !== b.length) return null;
        const m = a.map((x, i) => (x + b[i]) / 2);
        // The midpoint is the point equidistant from both AND on the segment:
        // M − A must equal B − M exactly.
        for (let i = 0; i < a.length; i++) if (!close(m[i] - a[i], b[i] - m[i])) return null;
        return candidate(vecAnswer(m), "Midpoint", [
          resultStep(`M = \\tfrac{1}{2}(A + B) = ${vecLatex(m)}`),
        ]);
      }
      case "section": {
        const [a, b] = vecs;
        const [m, n] = cls.vectorArgs ?? [];
        if (a.length !== b.length || !(m > 0) || !(n > 0)) return null;
        // P divides AB in the ratio m : n, so AP : PB = m : n.
        const p = a.map((x, i) => (n * x + m * b[i]) / (m + n));
        const ap = p.map((x, i) => x - a[i]);
        const pb = b.map((x, i) => x - p[i]);
        const lenAp = Math.sqrt(ap.reduce((s, x) => s + x * x, 0));
        const lenPb = Math.sqrt(pb.reduce((s, x) => s + x * x, 0));
        // Both defining facts are checked: the ratio of the two pieces is m : n,
        // and P actually lies ON the line (AP is parallel to PB).
        if (!(lenPb > 1e-12)) return null;
        if (Math.abs(lenAp / lenPb - m / n) > 1e-6) return null;
        for (let i = 0; i < a.length; i++) {
          if (Math.abs(ap[i] * n - pb[i] * m) > 1e-6 * Math.max(1, Math.abs(ap[i]))) return null;
        }
        return candidate(vecAnswer(p), `Point dividing AB in ${fmtNum(m)}:${fmtNum(n)}`, [
          resultStep(`P = \\frac{${fmtNum(n)}A + ${fmtNum(m)}B}{${fmtNum(m + n)}} = ${vecLatex(p)}`),
        ]);
      }
      case "distance_origin_line": {
        const [a, b] = vecs;
        if (a.length !== b.length || a.length < 2) return null;
        const dir = b.map((x, i) => x - a[i]);
        const dd = dotN(dir, dir);
        if (!(dd > 1e-12)) return null; // A and B coincide — no line
        // Build the FOOT of the perpendicular, then check it: it must lie on the
        // line, and the vector to it must be perpendicular to the direction.
        const t = -dotN(a, dir) / dd;
        const foot = a.map((x, i) => x + t * dir[i]);
        if (Math.abs(dotN(foot, dir)) > 1e-6 * Math.max(1, Math.sqrt(dd))) return null;
        const d = Math.sqrt(foot.reduce((s, x) => s + x * x, 0));
        // Independent cross-product formula |A × (B−A)| / |B−A| must agree.
        const a3 = pad3(a);
        const dir3 = pad3(dir);
        const c = [
          a3[1] * dir3[2] - a3[2] * dir3[1],
          a3[2] * dir3[0] - a3[0] * dir3[2],
          a3[0] * dir3[1] - a3[1] * dir3[0],
        ];
        const viaCross = Math.sqrt(c.reduce((s, x) => s + x * x, 0)) / Math.sqrt(dd);
        if (!close(d, viaCross)) return null;
        return candidate(fmt(d), "Distance from the origin to the line AB", [
          resultStep(`\\text{foot of the perpendicular} = ${vecLatex(foot)}`),
          resultStep(`d = ${fmtNum(d)}`),
        ]);
      }
      case "line_distance": {
        const [p1, d1, p2, d2] = vecs.map(pad3);
        const n1 = Math.hypot(...d1);
        const n2 = Math.hypot(...d2);
        if (!(n1 > 1e-12) || !(n2 > 1e-12)) return null; // a "line" with no direction
        const w = p2.map((x, i) => x - p1[i]);
        const n = cross3(d1, d2);
        const nLen = Math.hypot(...n);

        // Parallel and skew are different formulas, and the crossover between
        // them is where a wrong answer hides — so the split is explicit.
        const parallel = nLen <= 1e-9 * n1 * n2;
        let d: number;
        let formula: string;
        if (parallel) {
          d = Math.hypot(...cross3(w, d1)) / n1;
          formula = "d = \\frac{|(P_2 - P_1) \\times d_1|}{|d_1|}";
        } else {
          d = Math.abs(dotN(w, n)) / nLen;
          formula = "d = \\frac{|(P_2 - P_1) \\cdot (d_1 \\times d_2)|}{|d_1 \\times d_2|}";
        }
        if (!Number.isFinite(d)) return null;

        // The proof shares no step with the answer: the gap is MINIMISED
        // numerically over both parameters, with no cross product anywhere. A
        // cross-product slip cannot survive agreeing with a search that never
        // used one.
        const gap = (s: number, t: number) =>
          Math.hypot(...p1.map((x, i) => x + s * d1[i] - p2[i] - t * d2[i]));
        const best = minimiseGap(gap);
        if (!best) return null;
        if (!close(d, best.value)) return null;
        // …and at that minimum the joining segment is perpendicular to both
        // lines, which is what "shortest" means.
        const seg = p1.map((x, i) => x + best.s * d1[i] - p2[i] - best.t * d2[i]);
        const segLen = Math.hypot(...seg);
        if (segLen > 1e-9) {
          if (Math.abs(dotN(seg, d1)) > 1e-5 * segLen * n1) return null;
          if (Math.abs(dotN(seg, d2)) > 1e-5 * segLen * n2) return null;
        }

        // `3/√21` is the answer a marker wants; `0.6546536707` is the same
        // number with the exactness taken out of it.
        const surd = exactForm(d);
        const answer: FinalAnswer = surd ? { latex: surd.latex, plain: surd.plain } : fmt(d);

        return candidate(answer, parallel ? "Distance between parallel lines" : "Common perpendicular", [
          resultStep(`P_2 - P_1 = ${vecLatex(w)}`),
          resultStep(parallel ? "d_1 \\parallel d_2" : `d_1 \\times d_2 = ${vecLatex(n)}`),
          resultStep(`${formula} = ${fmtNum(d)}`),
        ]);
      }
      case "perpendicular_lambda": {
        // a + λb ⊥ c  ⇔  (a + λb)·c = 0  ⇔  λ = −(a·c)/(b·c).
        const [a, b, c] = vecs;
        if (a.length !== b.length || a.length !== c.length) return null;
        const bc = dotN(b, c);
        const scale = Math.max(1, ...vecs.flat().map(Math.abs)) ** 2;
        // b ⊥ c already: either every λ works (a ⊥ c too) or none does. Neither is
        // "the value of λ", so decline rather than divide by nothing.
        if (Math.abs(bc) <= 1e-12 * scale) return null;
        const lam = -dotN(a, c) / bc;
        // The proof is the definition itself: build the vector and check it is
        // perpendicular. Then check the answer is the ONLY one, by confirming the
        // dot product genuinely moves as λ moves — a flat one would mean the
        // equation was degenerate and the "solution" meaningless.
        const w = a.map((x, i) => x + lam * b[i]);
        if (Math.abs(dotN(w, c)) > 1e-9 * scale) return null;
        const near = a.map((x, i) => x + (lam + 1) * b[i]);
        if (Math.abs(dotN(near, c)) <= 1e-9 * scale) return null;
        return candidate(
          { latex: `\\lambda = ${fmtNum(lam)}`, plain: `λ = ${fmtNum(lam)}` },
          "Perpendicularity condition",
          [
            resultStep("(a + \\lambda b) \\cdot c = 0"),
            resultStep(
              `\\lambda = -\\frac{a \\cdot c}{b \\cdot c} = -\\frac{${fmtNum(dotN(a, c))}}{${fmtNum(bc)}} = ${fmtNum(lam)}`
            ),
            resultStep(`a + \\lambda b = ${vecLatex(w)},\\quad (a + \\lambda b) \\cdot c = 0`),
          ]
        );
      }
      case "basis_expansion": {
        // d = αa + βb + γc — solve the square system whose COLUMNS are the basis.
        const [d, ...basis] = vecs;
        const n = d.length;
        if (basis.length !== n || basis.some((v) => v.length !== n)) return null;
        // Cramer here is written out for 2×2 and 3×3 only — the sizes the sheets
        // use. A 4-D basis would silently take the 2×2 branch and be wrong.
        if (n !== 2 && n !== 3) return null;
        const cols = basis;
        // The basis has to actually BE a basis: a coplanar (singular) one either
        // has no expansion or infinitely many, and neither is an answer.
        const det = n === 3 ? cofactorDet([cols[0], cols[1], cols[2]]) : det2(cols);
        const scale = Math.max(1, ...vecs.flat().map(Math.abs)) ** n;
        if (Math.abs(det) <= 1e-9 * scale) return null;
        const coeffs: number[] = [];
        for (let j = 0; j < n; j++) {
          // Cramer: replace column j with d.
          const swapped = cols.map((v, k) => (k === j ? d : v));
          const dj = n === 3 ? cofactorDet([swapped[0], swapped[1], swapped[2]]) : det2(swapped);
          coeffs.push(dj / det);
        }
        // Recombine and compare with d. This never touches Cramer's rule again —
        // it is the original equation, checked component by component.
        for (let i = 0; i < n; i++) {
          let s = 0;
          for (let j = 0; j < n; j++) s += coeffs[j] * cols[j][i];
          if (Math.abs(s - d[i]) > 1e-9 * Math.max(1, Math.abs(d[i]))) return null;
        }
        // The target is `v`, never a letter the basis already uses — with four
        // basis vectors, "d = … + d" would name two different things the same.
        const names = ["a", "b", "c", "d"];
        if (n > names.length) return null;
        const term = (k: number, j: number) =>
          `${fmtNum(round10(k))}\\,\\mathbf{${names[j]}}`;
        const termPlain = (k: number, j: number) => `${fmtNum(round10(k))}${names[j]}`;
        const latex =
          "\\mathbf{v} = " +
          coeffs.map((k, j) => term(k, j)).join(" + ").replace(/\+ -/g, "- ");
        const plain =
          "v = " + coeffs.map((k, j) => termPlain(k, j)).join(" + ").replace(/\+ -/g, "- ");
        return candidate({ latex, plain }, "Expansion in a non-coplanar basis", [
          resultStep(
            `\\det[${names.slice(0, n).map((s) => `\\mathbf{${s}}`).join("\\;")}] = ${fmtNum(det)} \\neq 0`
          ),
          resultStep(latex),
        ]);
      }
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
/** The determinant of the 2×2 formed by two 2-D vectors. */
function det2(v: number[][]): number {
  return v[0][0] * v[1][1] - v[0][1] * v[1][0];
}

/** A 2-D vector padded into 3-D so the cross-product formula applies. */
function pad3(v: number[]): number[] {
  return v.length >= 3 ? v.slice(0, 3) : [...v, ...Array(3 - v.length).fill(0)];
}
function toVec(m: unknown): number[] | null {
  return Array.isArray(m) && m.every((x) => typeof x === "number" && Number.isFinite(x))
    ? (m as number[])
    : null;
}
function identityGrid(n: number): number[][] {
  return Array.from({ length: n }, (_, i) =>
    Array.from({ length: n }, (_, j) => (i === j ? 1 : 0))
  );
}
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

function cross3(a: number[], b: number[]): number[] {
  return [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];
}

/**
 * The smallest value of a convex gap function, found by nested ternary search —
 * no cross product, no normal equations, no step the closed form also takes.
 * That independence is the whole point: it is the check, not a second route to
 * the same arithmetic.
 *
 * Nearly-parallel lines put the minimum outside the bracket, where the search
 * returns something too large and the caller declines. That is the correct
 * outcome — the closed form is ill-conditioned there too.
 */
function minimiseGap(
  gap: (s: number, t: number) => number
): { value: number; s: number; t: number } | null {
  const BOUND = 1e4;
  const inner = (s: number): { value: number; t: number } => {
    let lo = -BOUND;
    let hi = BOUND;
    for (let i = 0; i < 200; i++) {
      const a = lo + (hi - lo) / 3;
      const b = hi - (hi - lo) / 3;
      if (gap(s, a) <= gap(s, b)) hi = b;
      else lo = a;
    }
    const t = (lo + hi) / 2;
    return { value: gap(s, t), t };
  };
  let lo = -BOUND;
  let hi = BOUND;
  for (let i = 0; i < 200; i++) {
    const a = lo + (hi - lo) / 3;
    const b = hi - (hi - lo) / 3;
    if (inner(a).value <= inner(b).value) hi = b;
    else lo = a;
  }
  const s = (lo + hi) / 2;
  const { value, t } = inner(s);
  return Number.isFinite(value) ? { value, s, t } : null;
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
