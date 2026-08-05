/**
 * Integrals — the last big NO CANDIDATE topic. Term-by-term antiderivatives for
 * the school core: powers (including roots and negative powers), constants,
 * sin/cos/e^u/1/u with a LINEAR inner function, and sums of those.
 *
 * Everything else — products of variable factors (∫x·cosx needs parts,
 * ∫x·e^{x²} needs substitution), rational functions, nested compositions —
 * DECLINES, which lands on the LLM-candidate tier exactly as before this engine
 * existed. Declining is safe; a wrong rule application is not.
 *
 * The gates are the two that already existed for the LLM path:
 *   • indefinite — `verifyDerivative`: d/dx(F) must equal the integrand at
 *     sampled points (mathjs differentiates, a numeric comparison decides).
 *   • definite — `numericIntegrate`: two independent quadrature rules must
 *     agree with F(b) − F(a).
 * So this engine cannot ship an antiderivative its own derivative disproves.
 */
import { parse } from "mathjs";

import { asciiToLatex, variablesIn } from "./latex";
import { exactForm } from "./exact";
import {
  closeEnough,
  evalReal,
  numericIntegrate,
  verifyDerivative,
} from "./verify";
import type { Classification, RawStep, SolveCandidate } from "./types";

// --- rationals (exact coefficients, so `3·x³/3` can never be printed) --------

interface Rat {
  p: number;
  q: number; // reduced, q > 0
}

function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

function rat(p: number, q = 1): Rat {
  if (q < 0) {
    p = -p;
    q = -q;
  }
  const g = gcd(Math.abs(p), q) || 1;
  return { p: p / g, q: q / g };
}

/** The small exact fraction `v` is, or null — coefficients here must be exact. */
function ratOf(v: number): Rat | null {
  if (!Number.isFinite(v)) return null;
  for (let q = 1; q <= 1000; q++) {
    const p = Math.round(v * q);
    if (Math.abs(v - p / q) < 1e-9) return rat(p, q);
  }
  return null;
}

const mulR = (a: Rat, b: Rat): Rat => rat(a.p * b.p, a.q * b.q);
const divR = (a: Rat, b: Rat): Rat => rat(a.p * b.q, a.q * b.p);
const addR = (a: Rat, b: Rat): Rat => rat(a.p * b.q + b.p * a.q, a.q * b.q);
const ratAscii = (r: Rat): string => (r.q === 1 ? String(r.p) : `${r.p}/${r.q}`);

// --- term shapes -------------------------------------------------------------

/** A linear inner function a·x + b, kept with its printed source. */
interface Lin {
  a: number;
  b: number;
  src: string;
}

type Shape =
  | { kind: "const" }
  | { kind: "power"; inner: Lin; n: Rat } // (ax+b)^n, n ≠ −1
  | { kind: "recip"; inner: Lin } // 1/(ax+b)
  | { kind: "sin" | "cos" | "exp"; inner: Lin };

interface Term {
  coeff: Rat;
  shape: Shape;
}

type LooseNode = {
  type?: string;
  op?: string;
  fn?: { name?: string };
  name?: string;
  content?: LooseNode;
  args?: LooseNode[];
  toString(): string;
};

/** `expr` measured as linear in `unknown` — a·x + b with constant a ≠ 0. */
function asLinear(node: LooseNode, unknown: string): Lin | null {
  const src = node.toString();
  const vars = variablesIn(src);
  if (!vars.includes(unknown) || vars.some((v) => v !== unknown)) return null;
  const at = (x: number) => evalReal(src, { [unknown]: x });
  const f0 = at(0);
  const f1 = at(1);
  const f2 = at(2);
  if ([f0, f1, f2].some((v) => !Number.isFinite(v))) return null;
  const a = f1 - f0;
  if (Math.abs(a) < 1e-12) return null;
  if (Math.abs(f2 - (2 * a + f0)) > 1e-9) return null; // not linear
  return { a, b: f0, src };
}

function unwrap(node: LooseNode): LooseNode {
  return node.type === "ParenthesisNode" && node.content
    ? unwrap(node.content)
    : node;
}

/** The constant value of a node holding no unknown, or null. */
function constOf(node: LooseNode, unknown: string): number | null {
  const src = node.toString();
  if (variablesIn(src).includes(unknown)) return null;
  const v = evalReal(src);
  return Number.isFinite(v) ? v : null;
}

/**
 * One additive term decomposed into `coeff × shape`, or null when it is not a
 * shape this engine owns. Conservative on purpose: two variable factors, an
 * irrational coefficient, a non-constant exponent — all decline.
 */
function decomposeTerm(raw: LooseNode, unknown: string): Term | null {
  let coeff = rat(1);
  let variablePart: LooseNode | null = null;
  let recipLin: Lin | null = null;
  let recipPower: { inner: Lin; n: Rat } | null = null;

  const take = (node: LooseNode): boolean => {
    const n = unwrap(node);
    if (n.type === "OperatorNode" && n.op === "-" && n.args?.length === 1) {
      coeff = mulR(coeff, rat(-1));
      return take(n.args[0]);
    }
    if (n.type === "OperatorNode" && n.op === "*" && n.args?.length === 2) {
      return take(n.args[0]) && take(n.args[1]);
    }
    if (n.type === "OperatorNode" && n.op === "/" && n.args?.length === 2) {
      const den = constOf(n.args[1], unknown);
      if (den !== null) {
        // variable / constant — fold the constant into the coefficient.
        const r = ratOf(den);
        if (!r || r.p === 0) return false;
        coeff = divR(coeff, r);
        return take(n.args[0]);
      }
      const num = constOf(n.args[0], unknown);
      if (num !== null) {
        // constant / variable — a reciprocal or negative-power shape.
        const r = ratOf(num);
        if (!r) return false;
        coeff = mulR(coeff, r);
        return placeReciprocal(n.args[1]);
      }
      return false; // variable / variable — a rational function, not ours
    }
    const c = constOf(n, unknown);
    if (c !== null) {
      const r = ratOf(c);
      if (!r) return false; // π-scaled coefficients etc. — decline
      coeff = mulR(coeff, r);
      return true;
    }
    if (variablePart !== null) return false; // two variable factors → parts/sub
    variablePart = n;
    return true;
  };

  /** `constant / <node>` — record the denominator as a shape. */
  const placeReciprocal = (node: LooseNode): boolean => {
    if (variablePart !== null) return false;
    const n = unwrap(node);
    // 1/x^k → x^(−k)
    if (n.type === "OperatorNode" && n.op === "^" && n.args?.length === 2) {
      const k = constOf(n.args[1], unknown);
      const base = asLinear(unwrap(n.args[0]), unknown);
      const kr = k !== null ? ratOf(k) : null;
      if (base && kr && kr.p > 0) {
        variablePart = {
          toString: () => `RECIP_POWER`,
          type: "__recip_power",
          args: [n.args[0]],
          content: undefined,
        } as unknown as LooseNode;
        recipPower = { inner: base, n: rat(-kr.p, kr.q) };
        return true;
      }
      return false;
    }
    const lin = asLinear(n, unknown);
    if (!lin) return false;
    variablePart = {
      toString: () => `RECIP`,
      type: "__recip",
    } as unknown as LooseNode;
    recipLin = lin;
    return true;
  };

  if (!take(raw)) return null;

  // Pure constant term.
  if (variablePart === null) return { coeff, shape: { kind: "const" } };

  // Re-read the closure-mutated locals under their declared types — TS's flow
  // analysis otherwise narrows them to their initial null at this point.
  const vp = variablePart as LooseNode;
  const recip = recipLin as Lin | null;
  const recipPow = recipPower as { inner: Lin; n: Rat } | null;

  if (vp.type === "__recip" && recip) {
    return { coeff, shape: { kind: "recip", inner: recip } };
  }
  if (vp.type === "__recip_power" && recipPow) {
    if (recipPow.n.p === -recipPow.n.q) {
      return { coeff, shape: { kind: "recip", inner: recipPow.inner } };
    }
    return {
      coeff,
      shape: { kind: "power", inner: recipPow.inner, n: recipPow.n },
    };
  }

  // x, or any linear expression, to the first power.
  {
    const lin = asLinear(vp, unknown);
    if (lin) return { coeff, shape: { kind: "power", inner: lin, n: rat(1) } };
  }

  // u^k with constant k; e^u is the exponential.
  if (vp.type === "OperatorNode" && vp.op === "^" && vp.args?.length === 2) {
    const base = unwrap(vp.args[0]);
    if (base.type === "SymbolNode" && base.name === "e") {
      const inner = asLinear(unwrap(vp.args[1]), unknown);
      return inner ? { coeff, shape: { kind: "exp", inner } } : null;
    }
    const k = constOf(vp.args[1], unknown);
    const kr = k !== null ? ratOf(k) : null;
    const inner = asLinear(base, unknown);
    if (!inner || !kr) return null;
    if (kr.p === -kr.q) return { coeff, shape: { kind: "recip", inner } };
    return { coeff, shape: { kind: "power", inner, n: kr } };
  }

  if (vp.type === "FunctionNode") {
    const name = vp.fn?.name;
    const arg = vp.args?.[0];
    if (!arg) return null;
    if (name === "sqrt") {
      const inner = asLinear(unwrap(arg), unknown);
      return inner
        ? { coeff, shape: { kind: "power", inner, n: rat(1, 2) } }
        : null;
    }
    if (name === "sin" || name === "cos" || name === "exp") {
      const inner = asLinear(unwrap(arg), unknown);
      if (!inner) return null;
      const kind = name === "exp" ? "exp" : name;
      return { coeff, shape: { kind, inner } };
    }
  }

  return null;
}

/** Top-level additive split; each term keeps its sign as a flag, so the
 * display can write `− ∫ 2x dx` instead of `∫ −(2x) dx`. */
interface SignedTerm {
  node: LooseNode;
  neg: boolean;
}

function splitTerms(node: LooseNode, negate: boolean, out: SignedTerm[]): void {
  const n = unwrap(node);
  if (n.type === "OperatorNode" && (n.op === "+" || n.op === "-") && n.args?.length === 2) {
    splitTerms(n.args[0], negate, out);
    splitTerms(n.args[1], n.op === "-" ? !negate : negate, out);
    return;
  }
  if (n.type === "OperatorNode" && n.op === "-" && n.args?.length === 1) {
    splitTerms(n.args[0], !negate, out);
    return;
  }
  out.push({ node: n, neg: negate });
}

// --- integration -------------------------------------------------------------

interface Integrated {
  /** The integrated term, WITHOUT its outer coefficient. */
  bodyAscii: string;
  /** The extra factor the rule itself introduces (1/(n+1), 1/a, −1/a …). */
  factor: Rat;
  rule: "POWER_RULE" | "CONSTANT_RULE" | "STANDARD_INTEGRAL";
}

/** `inner.src` printed for use inside a larger expression. */
function innerShown(inner: Lin, unknown: string): string {
  return inner.src === unknown ? unknown : `(${inner.src})`;
}

/** Integrate ONE shape; the caller multiplies the term coefficient back on. */
function integrateShape(shape: Shape, unknown: string): Integrated | null {
  switch (shape.kind) {
    case "const":
      return { bodyAscii: unknown, factor: rat(1), rule: "CONSTANT_RULE" };
    case "power": {
      const { inner, n } = shape;
      const a = ratOf(inner.a);
      if (!a || a.p === 0) return null;
      const m = addR(n, rat(1)); // n + 1 (never 0 — recip is its own shape)
      const u = innerShown(inner, unknown);
      const powAscii =
        m.p === m.q
          ? u
          : `${u}^${m.q === 1 && m.p > 0 ? m.p : `(${ratAscii(m)})`}`;
      return {
        bodyAscii: powAscii,
        factor: divR(rat(1), mulR(a, m)),
        rule: "POWER_RULE",
      };
    }
    case "recip": {
      const a = ratOf(shape.inner.a);
      if (!a || a.p === 0) return null;
      return {
        bodyAscii: `log(abs(${shape.inner.src}))`,
        factor: divR(rat(1), a),
        rule: "STANDARD_INTEGRAL",
      };
    }
    case "sin":
    case "cos":
    case "exp": {
      const a = ratOf(shape.inner.a);
      if (!a || a.p === 0) return null;
      const u = shape.inner.src;
      const body =
        shape.kind === "sin"
          ? `cos(${u})`
          : shape.kind === "cos"
            ? `sin(${u})`
            : `e^${innerShown(shape.inner, unknown)}`;
      const sign = shape.kind === "sin" ? rat(-1) : rat(1);
      return {
        bodyAscii: body,
        factor: mulR(sign, divR(rat(1), a)),
        rule: "STANDARD_INTEGRAL",
      };
    }
  }
}

/** `c · body` as ascii, with 1/−1/fraction coefficients printed properly. */
function withCoeff(c: Rat, bodyAscii: string): string {
  if (c.p === 0) return "0";
  if (bodyAscii === "") return ratAscii(c);
  const mag = rat(Math.abs(c.p), c.q);
  const sign = c.p < 0 ? "-" : "";
  if (mag.p === 1 && mag.q === 1) return `${sign}${bodyAscii}`;
  if (mag.q === 1) return `${sign}${mag.p}*${bodyAscii}`;
  return `${sign}(${ratAscii(mag)})*${bodyAscii}`;
}

/** Join integrated terms into one expression: `a - b + c`, not `a + -b`. */
function joinSigned(parts: string[]): string {
  let out = "";
  for (const part of parts) {
    if (out === "") {
      out = part;
    } else if (part.startsWith("-")) {
      out += ` - ${part.slice(1)}`;
    } else {
      out += ` + ${part}`;
    }
  }
  return out;
}

interface Antiderivative {
  ascii: string;
  steps: RawStep[];
}

/** `(\frac{1}{3})x³` → `\tfrac{1}{3}x³` — the parens exist only in ascii, to
 * bind the coefficient; the fraction bar carries that grouping in latex. */
function dropCoeffParens(latex: string): string {
  return latex.replace(
    /\\?\(\s*\\frac\{([^{}]+)\}\{([^{}]+)\}\s*\\?\)/g,
    "\\tfrac{$1}{$2}"
  );
}

function tex(ascii: string): string {
  return dropCoeffParens(asciiToLatex(ascii));
}

function step(operationCode: string, ascii: string, latex?: string): RawStep {
  return { ascii, operationCode, latex: latex ?? tex(ascii) };
}

const intLatex = (body: string, unknown: string) =>
  `\\int ${asciiToLatex(body)} \\, d${unknown}`;

/**
 * The antiderivative of `integrand`, with one visible step per applied rule —
 * or null when any term falls outside the owned shapes.
 */
export function antiderivative(
  integrand: string,
  unknown: string
): Antiderivative | null {
  let tree: LooseNode;
  try {
    tree = parse(integrand) as unknown as LooseNode;
  } catch {
    return null;
  }
  const termNodes: SignedTerm[] = [];
  splitTerms(tree, false, termNodes);
  if (termNodes.length === 0 || termNodes.length > 6) return null;

  const terms: Term[] = [];
  for (const { node, neg } of termNodes) {
    const t = decomposeTerm(node, unknown);
    if (!t) return null;
    terms.push(neg ? { ...t, coeff: mulR(t.coeff, rat(-1)) } : t);
  }

  const steps: RawStep[] = [];
  const signedJoin = (pieces: { text: string; neg: boolean }[]) =>
    pieces
      .map((p, i) =>
        i === 0 ? `${p.neg ? "-" : ""}${p.text}` : `${p.neg ? "-" : "+"} ${p.text}`
      )
      .join(" ");
  if (terms.length > 1) {
    steps.push({
      ascii: signedJoin(
        termNodes.map((t) => ({ text: `int(${t.node.toString()})`, neg: t.neg }))
      ),
      operationCode: "SPLIT_TERMS",
      latex: signedJoin(
        termNodes.map((t) => ({
          text: `\\int ${asciiToLatex(t.node.toString())} \\, d${unknown}`,
          neg: t.neg,
        }))
      ),
    });
  }

  const integratedParts: string[] = [];
  for (let i = 0; i < terms.length; i++) {
    const done = integrateShape(terms[i].shape, unknown);
    if (!done) return null;
    const full = withCoeff(mulR(terms[i].coeff, done.factor), done.bodyAscii);
    integratedParts.push(full);
    // The step shows the UNSIGNED integral of the term as written; the term's
    // own sign is already inside `full` via the coefficient.
    const sign = termNodes[i].neg ? "-" : "";
    steps.push({
      ascii: `${sign}int(${termNodes[i].node.toString()}) = ${full}`,
      operationCode: done.rule,
      latex: `${sign}${intLatex(termNodes[i].node.toString(), unknown)} = ${tex(full)}`,
    });
  }

  const ascii = joinSigned(integratedParts);
  if (terms.length > 1) steps.push(step("COMBINE_TERMS", ascii));
  return { ascii, steps };
}

// --- candidates --------------------------------------------------------------

function fractionAnswer(value: number): { plain: string; latex: string } {
  const exact = exactForm(value);
  if (exact) return { plain: exact.plain, latex: exact.latex };
  const r = ratOf(value);
  if (r && r.q !== 1) {
    return {
      plain: `${r.p}/${r.q}`,
      latex: `\\tfrac{${r.p}}{${r.q}}`,
    };
  }
  const s = String(Math.round(value * 1e6) / 1e6);
  return { plain: s, latex: s };
}

/** Deterministic integral solve — indefinite and definite. Null → LLM tier. */
export function solveIntegral(cls: Classification): SolveCandidate | null {
  const integrand = cls.integrand;
  if (!integrand) return null;
  const unknown = cls.unknown;
  const found = antiderivative(integrand, unknown);
  if (!found) return null;
  const F = found.ascii;

  const startAscii = `int(${integrand})`;
  const start: RawStep = {
    ascii: startAscii,
    operationCode: "START",
    latex:
      cls.lowerBound !== undefined && cls.upperBound !== undefined
        ? `\\int_{${asciiToLatex(cls.lowerBound)}}^{${asciiToLatex(cls.upperBound)}} ${asciiToLatex(integrand)} \\, d${unknown}`
        : intLatex(integrand, unknown),
  };

  // --- indefinite: F + C, gated by differentiating back --------------------
  if (cls.lowerBound === undefined || cls.upperBound === undefined) {
    if (!verifyDerivative(F, integrand, unknown)) return null;
    const withC = `${F} + C`;
    return {
      answer: { plain: withC, latex: `${tex(F)} + C` },
      methods: [
        {
          id: "antiderivative",
          name: "Integrate term by term",
          examPick: true,
          steps: [
            start,
            ...found.steps,
            step("ADD_CONSTANT", withC, `${tex(F)} + C`),
          ],
        },
      ],
      plotExpression: null,
      verify: () => verifyDerivative(F, integrand, unknown),
    };
  }

  // --- definite: F(b) − F(a), gated by independent quadrature --------------
  const lower = cls.lowerBound;
  const upper = cls.upperBound;
  const lo = evalReal(lower);
  const hi = evalReal(upper);
  if (!Number.isFinite(lo) || !Number.isFinite(hi)) return null;
  const atHi = evalReal(F, { [unknown]: hi });
  const atLo = evalReal(F, { [unknown]: lo });
  if (!Number.isFinite(atHi) || !Number.isFinite(atLo)) return null;
  const value = atHi - atLo;

  const sub = (bound: string) => {
    // A bare bound (a number, `pi`) substitutes as-is; anything with an
    // operator keeps parens so precedence survives.
    const shown = /^[a-z0-9.]+$/i.test(bound.trim()) ? bound.trim() : `(${bound})`;
    try {
      type N = LooseNode & { transform(cb: (n: LooseNode) => LooseNode): LooseNode };
      return (parse(F) as unknown as N)
        .transform((n) =>
          n.type === "SymbolNode" && n.name === unknown
            ? (parse(shown) as unknown as LooseNode)
            : n
        )
        .toString();
    } catch {
      return F;
    }
  };
  const show = fractionAnswer(value);
  const showHi = fractionAnswer(atHi);
  const showLo = fractionAnswer(atLo);

  return {
    answer: show,
    methods: [
      {
        id: "definite_integral",
        name: "Integrate, then evaluate the bounds",
        examPick: true,
        steps: [
          start,
          ...found.steps,
          step(
            "FUNDAMENTAL_THEOREM",
            `[${F}] from ${lower} to ${upper}`,
            `\\Bigl[${tex(F)}\\Bigr]_{${asciiToLatex(lower)}}^{${asciiToLatex(upper)}}`
          ),
          step(
            "EVALUATE_UPPER",
            `${sub(upper)} = ${showHi.plain}`,
            `${tex(sub(upper))} = ${showHi.latex}`
          ),
          step(
            "EVALUATE_LOWER",
            `${sub(lower)} = ${showLo.plain}`,
            `${tex(sub(lower))} = ${showLo.latex}`
          ),
          step(
            "SUBTRACT_BOUNDS",
            showLo.plain.startsWith("-")
              ? `${showHi.plain} - (${showLo.plain}) = ${show.plain}`
              : `${showHi.plain} - ${showLo.plain} = ${show.plain}`,
            showLo.plain.startsWith("-")
              ? `${showHi.latex} - \\left(${showLo.latex}\\right) = ${show.latex}`
              : `${showHi.latex} - ${showLo.latex} = ${show.latex}`
          ),
        ],
      },
    ],
    plotExpression: variablesIn(integrand).length === 1 ? integrand : null,
    // The independent gate: two quadrature rules agreeing with each other AND
    // with the antiderivative difference.
    verify: () => {
      const numeric = numericIntegrate(integrand, unknown, lower, upper);
      return Number.isFinite(numeric) && closeEnough(numeric, value);
    },
  };
}
