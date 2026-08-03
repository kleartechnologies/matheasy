/**
 * A matrix carrying a parameter, and the question "for what values of it does
 * this have determinant zero?" — the singular / non-invertible / no-inverse
 * family, and the characteristic equation `det(A − λI) = 0` along with it.
 *
 * The existing matrix reader takes numeric cells only, so a grid with an `a²` in
 * it was not a matrix at all and the whole question fell through to be read as
 * an expression.
 *
 * TWO ROUTES, and they share no step:
 *  • The ANSWER: `det A(p)` is a polynomial in `p`, so it is read off by
 *    evaluating the determinant at integer sample points and interpolating —
 *    no symbolic expansion, no cofactor algebra in symbols. Its roots then come
 *    from a sign scan and bisection.
 *  • The GATE is the golden rule stated literally: each value is substituted
 *    back into the ORIGINAL cells and the determinant computed there from the
 *    numbers, by LU. If it isn't zero, nothing is returned.
 *
 * Completeness is checked too. The interpolated polynomial has a known degree,
 * so a scan over Cauchy's bound can promise it found every real value — and if
 * the interpolation doesn't reproduce the determinant away from its own sample
 * points, it isn't the right polynomial and the engine declines.
 */
import { parse } from "mathjs";

import { exactForm } from "./exact";
import { latexToAscii, unwrapProse } from "./latex";
import { FinalAnswer, RawStep, SolveCandidate } from "./types";
import { evalReal } from "./verify";

const MAX_N = 6;
const MAX_DEGREE = 12;

const GREEK = [
  "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta",
  "theta", "vartheta", "iota", "kappa", "lambda", "mu", "nu", "xi", "rho",
  "sigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega",
];
const GREEK_LETTERS = "αβγδεζηθικλμνξρστυφχψω";
const GREEK_FROM_CHAR = new Map(
  [..."αβγδεζηθικλμνξρστυφχψω"].map((ch, i) => [
    ch,
    ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota",
      "kappa", "lambda", "mu", "nu", "xi", "rho", "sigma", "tau", "upsilon",
      "phi", "chi", "psi", "omega"][i],
  ])
);

/**
 * `\lambda` and `λ` both become `lambda`.
 *
 * mathjs cannot parse a backslash, so a characteristic matrix written the way
 * every textbook writes it — `2 − λ` down the diagonal — was not an expression
 * at all and the whole question declined.
 */
function deGreek(ascii: string): string {
  let out = ascii;
  for (const g of GREEK) out = out.replace(new RegExp(`\\\\${g}\\b`, "g"), g);
  for (const [ch, name] of GREEK_FROM_CHAR) out = out.split(ch).join(name);
  return out;
}

/** The display spelling of a de-greeked parameter: `lambda` → `λ`. */
function reGreek(name: string): string {
  const i = GREEK.indexOf(name);
  if (i < 0) return name;
  for (const [ch, n] of GREEK_FROM_CHAR) if (n === name) return ch;
  return GREEK_LETTERS[i] ?? name;
}

export interface ParamDetQuery {
  /** The grid, cell by cell, as ascii expressions in `parameter`. */
  cells: string[][];
  parameter: string;
  /** How the matrix was written, for the working. */
  matrixLatex: string;
}

const ASK_RE =
  /\bdeterminant\s+(?:is\s+|be\s+|equals?\s+|of\s+zero|zero)|\bdet\s*(?:\([^)]*\))?\s*=\s*0|\bsingular\b|\bnot\s+invertible\b|\bnon-?invertible\b|\bno\s+inverse\b|\bfails?\s+to\s+be\s+invertible\b/i;

const VALUES_RE =
  /\bfor\s+(?:what|which)\s+values?\b|\bfind\s+(?:all\s+)?(?:the\s+)?values?\b|\bdetermine\s+(?:all\s+)?(?:the\s+)?values?\b|\bfor\s+(?:what|which)\s+[a-z\\]+\s+(?:is|does)\b/i;

/** The parameter the question names, when it names one — "for what values of a". */
function namedParameter(s: string): string | null {
  const m =
    /\bvalues?\s+of\s+(?:the\s+(?:parameter|scalar|constant)\s+)?\$?\\?([a-zA-Z]+)\$?/i.exec(s) ??
    /\bfor\s+(?:what|which)\s+\$?\\?([a-zA-Z]+)\$?\s+(?:is|does|do)\b/i.exec(s);
  if (!m) return null;
  const name = m[1];
  if (/^(?:the|a|an|it|this|matrix)$/i.test(name)) return null;
  return name;
}

/** Every free symbol of an ascii expression, ignoring function names. */
function symbolsOf(ascii: string): string[] {
  const out = new Set<string>();
  try {
    parse(ascii).traverse((node, path, parent) => {
      const n = node as unknown as { type: string; name?: string };
      if (n.type !== "SymbolNode" || !n.name) return;
      if (parent && (parent as unknown as { type: string }).type === "FunctionNode" && path === "fn") {
        return;
      }
      if (["e", "pi", "tau", "i"].includes(n.name)) return;
      out.add(n.name);
    });
  } catch {
    return [];
  }
  return [...out];
}

export function parseParamDet(rawLatex: string): ParamDetQuery | null {
  // The word-level reading needs the prose without its `\text{…}` wrappers —
  // "values of } b \text{" has a brace exactly where the parameter should be,
  // so the question's own name for it was never seen. The GRID still comes from
  // the raw LaTeX, which is where `\begin{pmatrix}` lives.
  const prose = unwrapProse(rawLatex);
  if (!ASK_RE.test(prose)) return null;
  if (!VALUES_RE.test(prose)) return null;

  const block = /\\begin\{([pbv])matrix\}([\s\S]*?)\\end\{\1matrix\}/.exec(rawLatex);
  if (!block) return null;
  // Exactly one grid; two would be a different question about a product.
  if (/\\begin\{[pbv]matrix\}/g.test(rawLatex.slice(block.index + block[0].length))) return null;

  const rows = block[2]
    .split(/\\\\/)
    .map((r) => r.trim())
    .filter(Boolean);
  if (rows.length < 2 || rows.length > MAX_N) return null;

  const cells: string[][] = [];
  for (const r of rows) {
    const row = r.split("&").map((c) => deGreek(latexToAscii(c)).trim());
    if (row.some((c) => !c)) return null;
    cells.push(row);
  }
  const n = cells.length;
  if (!cells.every((row) => row.length === n)) return null; // a determinant needs a square

  const symbols = new Set<string>();
  for (const row of cells) for (const c of row) for (const s of symbolsOf(c)) symbols.add(s);
  if (symbols.size !== 1) return null; // no parameter, or more than one
  const parameter = [...symbols][0];

  // If the question names a parameter, it has to be the one in the grid.
  const named = namedParameter(prose);
  if (named && deGreek(named) !== parameter) return null;

  return { cells, parameter, matrixLatex: block[0] };
}

// ---------------------------------------------------------------------------
// the answer: interpolate det(A(p)), then find its roots by sign change
// ---------------------------------------------------------------------------

/** Determinant by LU with partial pivoting — numbers only, no symbols. */
function det(m: number[][]): number {
  const n = m.length;
  const a = m.map((r) => [...r]);
  let sign = 1;
  for (let k = 0; k < n; k++) {
    let piv = k;
    for (let i = k + 1; i < n; i++) if (Math.abs(a[i][k]) > Math.abs(a[piv][k])) piv = i;
    if (Math.abs(a[piv][k]) < 1e-14) return 0;
    if (piv !== k) {
      [a[k], a[piv]] = [a[piv], a[k]];
      sign = -sign;
    }
    for (let i = k + 1; i < n; i++) {
      const f = a[i][k] / a[k][k];
      for (let j = k; j < n; j++) a[i][j] -= f * a[k][j];
    }
  }
  let d = sign;
  for (let k = 0; k < n; k++) d *= a[k][k];
  return d;
}

function detAt(q: ParamDetQuery, p: number): number {
  const grid: number[][] = [];
  for (const row of q.cells) {
    const out: number[] = [];
    for (const c of row) {
      let v: number;
      try {
        v = evalReal(c, { [q.parameter]: p });
      } catch {
        return NaN;
      }
      if (!Number.isFinite(v)) return NaN;
      out.push(v);
    }
    grid.push(out);
  }
  return det(grid);
}

function lagrange(xs: number[], ys: number[]): number[] | null {
  const n = xs.length;
  const out = new Array<number>(n).fill(0);
  for (let i = 0; i < n; i++) {
    let basis = [1];
    let denom = 1;
    for (let j = 0; j < n; j++) {
      if (j === i) continue;
      denom *= xs[i] - xs[j];
      const next = new Array<number>(basis.length + 1).fill(0);
      for (let k = 0; k < basis.length; k++) {
        next[k + 1] += basis[k];
        next[k] -= basis[k] * xs[j];
      }
      basis = next;
    }
    if (!Number.isFinite(denom) || denom === 0) return null;
    for (let k = 0; k < basis.length; k++) out[k] += (ys[i] * basis[k]) / denom;
  }
  return out.every(Number.isFinite) ? out : null;
}

/**
 * The coefficients of `det A(p)`, ascending.
 *
 * The degree is not known up front — the cells can carry powers — so it is
 * raised until the interpolation reproduces the determinant at points it was
 * never fitted through. A grid that isn't polynomial in the parameter never
 * passes that, and is declined.
 */
function detPolynomial(q: ParamDetQuery): number[] | null {
  const probe = [0.31, -1.7, 2.45, -3.9, 5.15];
  for (let degree = 1; degree <= MAX_DEGREE; degree++) {
    const xs = Array.from({ length: degree + 1 }, (_, i) => i - Math.floor(degree / 2));
    const ys = xs.map((x) => detAt(q, x));
    if (!ys.every(Number.isFinite)) return null;
    const coeffs = lagrange(xs, ys);
    if (!coeffs) continue;
    let agrees = true;
    for (const x of probe) {
      const actual = detAt(q, x);
      const model = coeffs.reduce((s, c, k) => s + c * x ** k, 0);
      if (!Number.isFinite(actual) || Math.abs(actual - model) > 1e-7 * Math.max(1, Math.abs(actual))) {
        agrees = false;
        break;
      }
    }
    if (agrees) {
      let top = coeffs.length - 1;
      while (top > 0 && Math.abs(coeffs[top]) < 1e-9) top--;
      return coeffs.slice(0, top + 1);
    }
  }
  return null;
}

function bisect(f: (x: number) => number, a: number, b: number): number | null {
  let lo = a;
  let hi = b;
  let flo = f(lo);
  if (!Number.isFinite(flo)) return null;
  if (flo === 0) return lo;
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (mid === lo || mid === hi) break;
    const fm = f(mid);
    if (!Number.isFinite(fm)) return null;
    if (fm === 0) return mid;
    if (flo * fm < 0) hi = mid;
    else {
      lo = mid;
      flo = fm;
    }
  }
  return (lo + hi) / 2;
}

/** `v` as a small fraction, when it is one. The values that make a matrix
 * singular are usually integers, and "1" is a better answer than "1.0000000". */
function asRational(v: number): { text: string; value: number } | null {
  for (let den = 1; den <= 64; den++) {
    const num = Math.round(v * den);
    if (Math.abs(v - num / den) < 1e-9 * Math.max(1, Math.abs(v))) {
      return { text: den === 1 ? String(num) : `${num}/${den}`, value: num / den };
    }
  }
  return null;
}

/**
 * `v` as `p ± q√d` when it is one.
 *
 * The characteristic equation of a symmetric matrix lands here constantly —
 * `1 − √2` is the eigenvalue, and `-0.414214` is the same number with the
 * mathematics taken out of it. `exactForm` handles a bare surd but not one
 * with an integer beside it, which is the shape a quadratic root takes.
 */
function asQuadraticSurd(v: number): { text: string; latex: string } | null {
  for (let den = 1; den <= 12; den++) {
    for (let p = -40; p <= 40; p++) {
      const rest = v - p / den;
      const sq = (rest * den) ** 2;
      const d = Math.round(sq);
      if (d < 2 || d > 4000) continue;
      if (Math.abs(sq - d) > 1e-7 * Math.max(1, sq)) continue;
      if (Number.isInteger(Math.sqrt(d))) continue; // a perfect square is rational
      const sign = rest < 0 ? "-" : "+";
      const surd = `√${d}`;
      const num = p === 0 ? `${rest < 0 ? "-" : ""}${surd}` : `${p} ${sign} ${surd}`;
      const lnum = p === 0 ? `${rest < 0 ? "-" : ""}\\sqrt{${d}}` : `${p} ${sign} \\sqrt{${d}}`;
      return den === 1
        ? { text: num, latex: lnum }
        : { text: `(${num})/${den}`, latex: `\\frac{${lnum}}{${den}}` };
    }
  }
  return null;
}

function step(latex: string, code: string): RawStep {
  return { ascii: latex, operationCode: code, latex };
}

export function solveParamDet(cls: { paramDet?: ParamDetQuery }): SolveCandidate | null {
  const q = cls.paramDet;
  if (!q) return null;

  const coeffs = detPolynomial(q);
  if (!coeffs || coeffs.length < 2) return null; // constant determinant: never zero, or always

  // Cauchy's bound, so the scan below can promise it found every real value.
  const lead = Math.abs(coeffs[coeffs.length - 1]);
  if (!(lead > 1e-9)) return null;
  let worst = 0;
  for (let k = 0; k < coeffs.length - 1; k++) worst = Math.max(worst, Math.abs(coeffs[k]) / lead);
  const R = 1 + worst;
  if (!Number.isFinite(R) || R > 1e6) return null;

  const poly = (x: number) => coeffs.reduce((s, c, k) => s + c * x ** k, 0);
  const N = 20000;
  const h = (2 * R) / N;
  const roots: number[] = [];
  let prevX = -R;
  let prevY = poly(prevX);
  for (let i = 1; i <= N; i++) {
    const x = -R + i * h;
    const y = poly(x);
    if (prevY === 0) roots.push(prevX);
    else if (prevY * y < 0) {
      const r = bisect(poly, prevX, x);
      if (r !== null) roots.push(r);
    }
    prevX = x;
    prevY = y;
  }
  if (poly(R) === 0) roots.push(R);

  // A repeated root touches the axis without crossing, so the scan can walk
  // straight past it. Every stationary point of the polynomial is a candidate.
  const dcoeffs = coeffs.slice(1).map((c, k) => c * (k + 1));
  const dpoly = (x: number) => dcoeffs.reduce((s, c, k) => s + c * x ** k, 0);
  let px = -R;
  let py = dpoly(px);
  for (let i = 1; i <= N; i++) {
    const x = -R + i * h;
    const y = dpoly(x);
    if (py * y < 0) {
      const s = bisect(dpoly, px, x);
      if (s !== null && Math.abs(poly(s)) < 1e-7 * Math.max(1, Math.abs(lead))) roots.push(s);
    }
    px = x;
    py = y;
  }

  // Tidy each to the exact value where there is one, then dedupe. `√6` is the
  // answer a marker wants; `2.44949` is the same number with the exactness
  // taken out of it.
  const values: { text: string; latex: string; value: number }[] = [];
  for (const r of roots.sort((a, b) => a - b)) {
    const rat = asRational(r);
    const surd = rat ? null : (exactForm(r) ?? null);
    const quad = rat || surd ? null : asQuadraticSurd(r);
    const value = rat ? rat.value : r;
    const decimal = String(Math.round(r * 1e6) / 1e6);
    const text = rat?.text ?? surd?.plain ?? quad?.text ?? decimal;
    const latex = rat?.text ?? surd?.latex ?? quad?.latex ?? decimal;
    if (values.some((v) => Math.abs(v.value - value) < 1e-7)) continue;
    values.push({ text, latex, value });
  }
  if (values.length > MAX_DEGREE) return null;

  const shown = reGreek(q.parameter);
  if (!values.length) {
    // No sign change and no stationary point on the axis, anywhere inside
    // Cauchy's bound — and every real root of a polynomial is inside it. So
    // "there is no such value" is a RESULT, not a failure to find one, and
    // saying it is better than an "I couldn't verify this".
    for (let i = 0; i <= 400; i++) {
      const d = detAt(q, -R + (2 * R * i) / 400);
      if (!Number.isFinite(d) || Math.abs(d) < 1e-12) return null;
    }
    const none = `no real values of ${shown}`;
    return {
      answer: { latex: `\\text{${none}}`, plain: none },
      methods: [
        {
          id: "param_det",
          name: "Determinant as a polynomial in the parameter",
          examPick: true,
          steps: [
            step(`\\det ${q.matrixLatex} \\neq 0 \\text{ for all real } ${latexName(q.parameter)}`, "RESULT"),
          ],
        },
      ],
      plotExpression: null,
      verify: () => true,
    };
  }

  // --- The gate: put each value back into the matrix as printed ------------
  // This is the golden rule stated literally. The interpolation, the Cauchy
  // bound and the bisection are all upstream of this line; none of them is
  // consulted here. Only the original cells are.
  const scale = Math.max(1, ...q.cells.flat().map((c) => {
    const v = Math.abs(evalRealSafe(c, q.parameter, 1));
    return Number.isFinite(v) ? v : 1;
  }));
  for (const v of values) {
    const d = detAt(q, v.value);
    if (!Number.isFinite(d) || Math.abs(d) > 1e-7 * scale ** q.cells.length) return null;
  }
  // And a value that is NOT in the list must give a determinant that is not
  // zero, or the list is incomplete.
  for (const probe of [0.137, -2.61, 4.29]) {
    if (values.some((v) => Math.abs(v.value - probe) < 1e-6)) continue;
    const d = detAt(q, probe);
    if (!Number.isFinite(d)) return null;
    if (Math.abs(d) < 1e-12) return null;
  }

  const plain = values.map((v) => `${shown} = ${v.text}`).join(" or ");
  const answer: FinalAnswer = {
    latex: values.map((v) => `${latexName(q.parameter)} = ${v.latex}`).join(" \\text{ or } "),
    plain,
  };

  const polyText = coeffs
    .map((c, k) => ({ c, k }))
    .filter(({ c }) => Math.abs(c) > 1e-9)
    .reverse()
    .map(({ c, k }) => {
      const cr = asRational(c);
      const cs = cr ? cr.text : String(Math.round(c * 1e6) / 1e6);
      if (k === 0) return cs;
      const power = k === 1 ? shown : `${shown}^${k}`;
      return cs === "1" ? power : cs === "-1" ? `-${power}` : `${cs}${power}`;
    })
    .join(" + ")
    .replace(/\+ -/g, "- ");

  const steps: RawStep[] = [
    step(`\\det ${q.matrixLatex} = ${polyText}`, "EXPAND_DETERMINANT"),
    step(`${polyText} = 0`, "SET_ZERO"),
    step(plain, "RESULT"),
  ];

  return {
    answer,
    methods: [
      { id: "param_det", name: "Determinant as a polynomial in the parameter", examPick: true, steps },
    ],
    plotExpression: null,
    verify: () => true,
  };
}

/** The LaTeX spelling of a de-greeked parameter: `lambda` → `\lambda`. */
function latexName(name: string): string {
  return GREEK.includes(name) ? `\\${name}` : name;
}

function evalRealSafe(expr: string, variable: string, at: number): number {
  try {
    return evalReal(expr, { [variable]: at });
  } catch {
    return NaN;
  }
}
