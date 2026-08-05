/**
 * Canonical multivariate polynomials with EXACT rational coefficients.
 *
 * mathjs's `simplify`/`rationalize` expand a product but never canonicalize the
 * ORDER of a commutative one, so `2x^2(4xy-5) - 8yx^3 + 9x` came back as
 * `8x^3y + 9x - 8yx^3 - 10x^2`: correct, verified, and useless to a learner —
 * the two cubic terms are the same monomial written two ways and simply never
 * met. Photomath prints `-10x^2 + 9x`, and so must we.
 *
 * So: parse to a map from a canonical monomial key to a rational coefficient,
 * do the arithmetic there, and print back. Terms combine because the key is
 * order-independent, and the coefficients stay exact because they are bigint
 * ratios — a worksheet answer of `-4/3` must never surface as `-1.333333`.
 *
 * Anything that isn't polynomial (`sqrt(x)`, `sin t`, a division by a symbol)
 * is folded into an opaque ATOM and carried through as if it were a variable,
 * so `3\sqrt{x} - \sqrt{x}` still collects. An atom is compared by its printed
 * form, which is why the caller must hand us already-canonical ascii.
 */
import { parse, rationalize, type MathNode } from "mathjs";

// --- exact rational arithmetic ----------------------------------------------

export type Rational = { n: bigint; d: bigint };

function bigAbs(a: bigint): bigint {
  return a < 0n ? -a : a;
}
function bigGcd(a: bigint, b: bigint): bigint {
  let x = bigAbs(a);
  let y = bigAbs(b);
  while (y) [x, y] = [y, x % y];
  return x;
}
export function rat(n: bigint, d: bigint = 1n): Rational {
  if (d === 0n) throw new Error("zero denominator");
  if (d < 0n) [n, d] = [-n, -d];
  const g = bigGcd(n, d) || 1n;
  return { n: n / g, d: d / g };
}
const ratAdd = (a: Rational, b: Rational) => rat(a.n * b.d + b.n * a.d, a.d * b.d);
const ratMul = (a: Rational, b: Rational) => rat(a.n * b.n, a.d * b.d);
const ratDiv = (a: Rational, b: Rational) => rat(a.n * b.d, a.d * b.n);
const ratNeg = (a: Rational): Rational => ({ n: -a.n, d: a.d });
const ratIsZero = (a: Rational) => a.n === 0n;

/**
 * A double → the exact ratio it is standing in for.
 *
 * Continued fractions, not a decimal-string read: mathjs's `rationalize` does
 * its coefficient arithmetic in floating point, so `s/(3t) - s/5` arrives with
 * a coefficient of `0.6000000000000001`. Read literally that is
 * `6000000000000001/10^16`, and the "exact" answer came out as a pair of
 * sixteen-digit integers. Snapping to the nearest small-denominator ratio is
 * what keeps thirds as thirds.
 */
function ratFromNumber(x: number): Rational | null {
  if (!Number.isFinite(x)) return null;
  if (Number.isInteger(x) && Math.abs(x) <= Number.MAX_SAFE_INTEGER)
    return rat(BigInt(x));
  const tol = Math.max(Math.abs(x), 1) * 1e-11;
  let [h0, h1] = [0n, 1n];
  let [k0, k1] = [1n, 0n];
  let v = x;
  for (let i = 0; i < 32; i++) {
    const a = Math.floor(v);
    if (!Number.isFinite(a) || Math.abs(a) > 1e15) break;
    const ab = BigInt(a);
    [h0, h1] = [h1, ab * h1 + h0];
    [k0, k1] = [k1, ab * k1 + k0];
    if (k1 === 0n) break;
    if (k1 > 1000000n) break;
    if (Math.abs(Number(h1) / Number(k1) - x) <= tol) return rat(h1, k1);
    const frac = v - a;
    if (frac === 0) break;
    v = 1 / frac;
  }
  return null; // not a worksheet coefficient — let the caller decline
}

export function ratToString(r: Rational): string {
  return r.d === 1n ? r.n.toString() : `${r.n}/${r.d}`;
}

// --- monomials ---------------------------------------------------------------

/** variable → exponent. Only positive integer exponents ever appear. */
type Monomial = Map<string, number>;

/** Order-independent identity of a monomial: `x*y` and `y*x` share this key. */
function monoKey(m: Monomial): string {
  return [...m.entries()]
    .filter(([, e]) => e !== 0)
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([v, e]) => (e === 1 ? v : `${v}^${e}`))
    .join("*");
}

/**
 * Graded lexicographic order, the one a textbook prints in: highest total
 * degree first, then the highest power of the alphabetically-first variable —
 * `2x^2 - 3xy - 2y^2`, not `-3xy + 2x^2 - 2y^2`.
 */
function monoCompare(a: Monomial, b: Monomial): number {
  const d = monoDegree(b) - monoDegree(a);
  if (d !== 0) return d;
  const vars = [...new Set([...a.keys(), ...b.keys()])].sort();
  for (const v of vars) {
    const diff = (b.get(v) ?? 0) - (a.get(v) ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}
function monoMul(a: Monomial, b: Monomial): Monomial {
  const out = new Map(a);
  for (const [v, e] of b) out.set(v, (out.get(v) ?? 0) + e);
  return out;
}
function monoDegree(m: Monomial): number {
  let d = 0;
  for (const e of m.values()) d += e;
  return d;
}

export type Term = { coeff: Rational; vars: Monomial };
/** A polynomial: canonical monomial key → term. Zero terms are never stored. */
export type Poly = Map<string, Term>;

const ZERO: Poly = new Map();

/**
 * A work budget for the whole layer.
 *
 * The reader is happy to accept things that are not really algebra: the ascii
 * pass splits glued letters into implicit products, so the prose "Find the area
 * of a square with side 7" arrives as a genuine twenty-variable monomial — and
 * the multivariate gcd recurses once per variable, branching at every level.
 * That is a hang, not a slow answer. So every term operation costs a unit, the
 * public entry points run inside a budget, and running out DECLINES (returns
 * null) rather than answering late.
 */
class PolyBudgetExceeded extends Error {}
const BUDGET = 200_000;
let budget = 0;
let budgeted = false;

function withBudget<T>(fn: () => T): T | null {
  if (budgeted) return fn(); // already inside one — don't refill it mid-flight
  budgeted = true;
  budget = BUDGET;
  try {
    return fn();
  } catch (e) {
    if (e instanceof PolyBudgetExceeded) return null;
    throw e;
  } finally {
    budgeted = false;
  }
}

function polyAddTerm(p: Poly, t: Term): void {
  if (budgeted && --budget < 0) throw new PolyBudgetExceeded();
  const k = monoKey(t.vars);
  const cur = p.get(k);
  const coeff = cur ? ratAdd(cur.coeff, t.coeff) : t.coeff;
  if (ratIsZero(coeff)) p.delete(k);
  else p.set(k, { coeff, vars: t.vars });
}
function polyAdd(a: Poly, b: Poly): Poly {
  const out: Poly = new Map(a);
  for (const t of b.values()) polyAddTerm(out, t);
  return out;
}
function polyNeg(a: Poly): Poly {
  const out: Poly = new Map();
  for (const [k, t] of a) out.set(k, { coeff: ratNeg(t.coeff), vars: t.vars });
  return out;
}
function polyMul(a: Poly, b: Poly): Poly {
  const out: Poly = new Map();
  for (const x of a.values())
    for (const y of b.values())
      polyAddTerm(out, { coeff: ratMul(x.coeff, y.coeff), vars: monoMul(x.vars, y.vars) });
  return out;
}
function polyPow(a: Poly, n: number): Poly {
  let out = polyConst(rat(1n));
  for (let i = 0; i < n; i++) out = polyMul(out, a);
  return out;
}
function polyConst(c: Rational): Poly {
  if (ratIsZero(c)) return new Map();
  return new Map([["", { coeff: c, vars: new Map() }]]);
}
/** The polynomial's constant value, or null if it has any variable. */
function polyAsConstant(p: Poly): Rational | null {
  if (p.size === 0) return rat(0n);
  if (p.size === 1) {
    const t = p.get("");
    if (t) return t.coeff;
  }
  return null;
}
export function polyIsZero(p: Poly): boolean {
  return p.size === 0;
}
export function polyVars(p: Poly): string[] {
  const s = new Set<string>();
  for (const t of p.values()) for (const [v, e] of t.vars) if (e > 0) s.add(v);
  return [...s].sort();
}
/** Highest power of `v` in the polynomial (0 when it doesn't appear). */
export function polyDegreeIn(p: Poly, v: string): number {
  let d = 0;
  for (const t of p.values()) d = Math.max(d, t.vars.get(v) ?? 0);
  return d;
}

// --- parsing -----------------------------------------------------------------

/**
 * A non-polynomial subtree carried as one opaque symbol (`sqrt(x+1)`, `sin(t)`).
 * Keyed by printed form so two occurrences of the same subtree collect.
 */
class AtomTable {
  private readonly byText = new Map<string, string>();
  readonly source = new Map<string, string>();
  intern(text: string): string {
    const hit = this.byText.get(text);
    if (hit) return hit;
    const name = `$atom${this.byText.size}`;
    this.byText.set(text, name);
    this.source.set(name, text);
    return name;
  }
}

function nodeToPoly(node: MathNode, atoms: AtomTable): Poly | null {
  switch (node.type) {
    case "ConstantNode": {
      const r = ratFromNumber(Number((node as unknown as { value: unknown }).value));
      return r ? polyConst(r) : null;
    }
    case "SymbolNode": {
      const name = (node as unknown as { name: string }).name;
      return new Map([[name, { coeff: rat(1n), vars: new Map([[name, 1]]) }]]);
    }
    case "ParenthesisNode":
      return nodeToPoly((node as unknown as { content: MathNode }).content, atoms);
    case "OperatorNode": {
      const op = node as unknown as { op: string; fn: string; args: MathNode[] };
      if (op.fn === "unaryMinus") {
        const a = nodeToPoly(op.args[0], atoms);
        return a && polyNeg(a);
      }
      if (op.fn === "unaryPlus") return nodeToPoly(op.args[0], atoms);
      const parts = op.args.map((a) => nodeToPoly(a, atoms));
      if (parts.some((p) => p === null)) return null;
      const ps = parts as Poly[];
      switch (op.op) {
        case "+":
          return ps.reduce(polyAdd, ZERO);
        case "-":
          return polyAdd(ps[0], polyNeg(ps[1]));
        case "*":
          return ps.reduce(polyMul);
        case "/": {
          const denom = polyAsConstant(ps[1]);
          if (!denom || ratIsZero(denom)) return null; // rational, not polynomial
          const out: Poly = new Map();
          for (const t of ps[0].values())
            polyAddTerm(out, { coeff: ratDiv(t.coeff, denom), vars: t.vars });
          return out;
        }
        case "^": {
          const e = polyAsConstant(ps[1]);
          if (!e || e.d !== 1n || e.n < 0n || e.n > 64n) return null;
          return polyPow(ps[0], Number(e.n));
        }
        default:
          return null;
      }
    }
    default:
      return null;
  }
}

/**
 * Read an ascii expression as a canonical polynomial. Non-polynomial subtrees
 * become atoms, so `2*sqrt(x) + 3*sqrt(x)` still collects to `5*sqrt(x)`.
 * Returns null when the expression can't be read at all (a bare `/` by a
 * symbol, a symbolic exponent) — the caller falls back to its old behaviour.
 */
export function toPoly(ascii: string): { poly: Poly; atoms: AtomTable } | null {
  let root: MathNode;
  try {
    root = parse(ascii);
  } catch {
    return null;
  }
  return withBudget(() => {
    const atoms = new AtomTable();
    const poly = nodeToPoly(atomize(root, atoms), atoms);
    // Past worksheet width this stopped being algebra and started being prose
    // read as a product of its letters — decline before the gcd recursion sees it.
    if (!poly || polyVars(poly).length > MAX_VARS) return null;
    return { poly, atoms };
  });
}

/** Distinct symbols a real worksheet expression can carry. Prose blows past it. */
const MAX_VARS = 10;

/**
 * Replace every subtree the polynomial reader can't take with an atom symbol.
 * Done as a pre-pass so a single `sqrt` deep inside a product doesn't sink the
 * whole expression — only that subtree becomes opaque.
 */
function atomize(node: MathNode, atoms: AtomTable): MathNode {
  const rebuild = (n: MathNode): MathNode => {
    switch (n.type) {
      case "ConstantNode":
      case "SymbolNode":
        return n;
      case "ParenthesisNode":
        return rebuild((n as unknown as { content: MathNode }).content);
      case "OperatorNode": {
        const op = n as unknown as { op: string; fn: string; args: MathNode[] };
        if (op.op === "^") {
          const exp = op.args[1];
          const ok =
            exp.type === "ConstantNode" &&
            Number.isInteger(Number((exp as unknown as { value: unknown }).value)) &&
            Number((exp as unknown as { value: unknown }).value) >= 0;
          if (!ok) return parse(atoms.intern(n.toString()));
        }
        if (op.op === "/") {
          const den = rebuild(op.args[1]);
          const denConst = toConstant(den);
          if (denConst === null) return parse(atoms.intern(n.toString()));
        }
        if (!["+", "-", "*", "/", "^"].includes(op.op) && op.fn !== "unaryMinus")
          return parse(atoms.intern(n.toString()));
        return n.map(rebuild);
      }
      default:
        // FunctionNode, and anything else — one opaque symbol.
        return parse(atoms.intern(n.toString()));
    }
  };
  return rebuild(node);
}

/** A numeric value for a node that is pure arithmetic, else null. */
function toConstant(n: MathNode): number | null {
  const atoms = new AtomTable();
  const p = nodeToPoly(n, atoms);
  if (!p) return null;
  const c = polyAsConstant(p);
  return c ? Number(c.n) / Number(c.d) : null;
}

// --- printing ----------------------------------------------------------------

function termAscii(t: Term, atomSource: Map<string, string>): string {
  const factors = [...t.vars.entries()]
    .filter(([, e]) => e > 0)
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([v, e]) => {
      const name = atomSource.get(v) ?? v;
      // A call (`sqrt(x)`) already binds tighter than `*`; anything else with an
      // operator in it (`x ^ n`) needs the parens.
      const bare =
        !atomSource.has(v) || /^[A-Za-z_$][A-Za-z0-9_$]*\([^()]*\)$/.test(name);
      const base = bare ? name : `(${name})`;
      return e === 1 ? base : `${base}^${e}`;
    });
  const mag = { n: bigAbs(t.coeff.n), d: t.coeff.d };
  if (!factors.length) return ratToString(mag);
  const body = factors.join("*");
  if (mag.n === 1n) return mag.d === 1n ? body : `${body}/${mag.d}`;
  return mag.d === 1n ? `${mag.n}*${body}` : `${mag.n}*${body}/${mag.d}`;
}

/**
 * Canonical ascii: highest total degree first, ties broken alphabetically, so
 * the same polynomial always prints the same way. Constant term last.
 */
export function polyToAscii(p: Poly, atomSource = new Map<string, string>()): string {
  if (p.size === 0) return "0";
  const terms = [...p.values()].sort((a, b) => monoCompare(a.vars, b.vars));
  let out = "";
  for (const t of terms) {
    const body = termAscii(t, atomSource);
    if (!out) out = t.coeff.n < 0n ? `-${body}` : body;
    else out += t.coeff.n < 0n ? ` - ${body}` : ` + ${body}`;
  }
  return out;
}

/** Canonical ascii for an expression, or null when it isn't polynomial. */
export function canonicalPolynomial(ascii: string): string | null {
  const got = toPoly(ascii);
  if (!got) return null;
  return polyToAscii(got.poly, got.atoms.source);
}

// --- division, gcd, content --------------------------------------------------

/** The rational content: the gcd of the coefficients (as a ratio, so `2/3` and
 * `4/9` share `2/9`). Zero polynomial → 1. */
function polyContent(p: Poly): Rational {
  if (p.size === 0) return rat(1n);
  let n = 0n;
  let d = 1n;
  for (const t of p.values()) {
    n = bigGcd(n, t.coeff.n);
    d = (d * t.coeff.d) / bigGcd(d, t.coeff.d); // lcm
  }
  return rat(n === 0n ? 1n : n, d);
}

/** The monomial every term is divisible by (`6x^2y + 3xy` → `3xy` with the
 * content folded in). Used to cancel the easy part of a fraction. */
function polyCommonFactor(p: Poly): { coeff: Rational; vars: Monomial } {
  const terms = [...p.values()];
  if (!terms.length) return { coeff: rat(1n), vars: new Map() };
  const vars: Monomial = new Map(terms[0].vars);
  for (const t of terms.slice(1)) {
    for (const [v, e] of [...vars]) {
      const other = t.vars.get(v) ?? 0;
      if (other === 0) vars.delete(v);
      else vars.set(v, Math.min(e, other));
    }
  }
  return { coeff: polyContent(p), vars };
}

function polyDivideByTerm(p: Poly, f: { coeff: Rational; vars: Monomial }): Poly {
  const out: Poly = new Map();
  for (const t of p.values()) {
    const vars = new Map(t.vars);
    for (const [v, e] of f.vars) {
      const cur = vars.get(v) ?? 0;
      if (cur - e <= 0) vars.delete(v);
      else vars.set(v, cur - e);
    }
    polyAddTerm(out, { coeff: ratDiv(t.coeff, f.coeff), vars });
  }
  return out;
}

/** Exact division `a / b`, or null when `b` does not divide `a`. Multivariate
 * long division against the lead term under the same ordering `polyToAscii`
 * prints in — terminates because each step strictly lowers the remainder. */
export function polyDivide(a: Poly, b: Poly): Poly | null {
  if (b.size === 0) return null;
  const lead = (p: Poly): Term =>
    [...p.values()].sort((x, y) => monoCompare(x.vars, y.vars))[0];
  let rem = new Map(a) as Poly;
  let quo: Poly = new Map();
  const lb = lead(b);
  for (let guard = 0; rem.size > 0 && guard < 4096; guard++) {
    const lr = lead(rem);
    const vars: Monomial = new Map(lr.vars);
    for (const [v, e] of lb.vars) {
      const cur = vars.get(v) ?? 0;
      if (cur < e) return null; // lead term not divisible → no exact division
      if (cur - e === 0) vars.delete(v);
      else vars.set(v, cur - e);
    }
    const term: Term = { coeff: ratDiv(lr.coeff, lb.coeff), vars };
    polyAddTerm(quo, term);
    const sub = polyMul(b, new Map([[monoKey(term.vars), term]]));
    rem = polyAdd(rem, polyNeg(sub));
  }
  return rem.size === 0 ? quo : null;
}

/**
 * Reduce `num / den` to lowest terms as far as a worksheet needs: cancel the
 * common monomial factor, then — when both are polynomials in ONE variable —
 * the full gcd. Returns the pair unchanged when nothing cancels.
 */
export function reduceFraction(num: Poly, den: Poly): { num: Poly; den: Poly } {
  if (den.size === 0 || num.size === 0) return { num, den };
  // Out of budget = un-cancelled, which is still correct. Never un-answered.
  return withBudget(() => reduceFractionInner(num, den)) ?? { num, den };
}

function reduceFractionInner(num: Poly, den: Poly): { num: Poly; den: Poly } {
  const fn = polyCommonFactor(num);
  const fd = polyCommonFactor(den);
  const vars: Monomial = new Map();
  for (const [v, e] of fn.vars) {
    const other = fd.vars.get(v) ?? 0;
    if (other > 0) vars.set(v, Math.min(e, other));
  }
  const coeff = rat(
    bigGcd(fn.coeff.n * fd.coeff.d, fd.coeff.n * fn.coeff.d),
    fn.coeff.d * fd.coeff.d
  );
  let n = polyDivideByTerm(num, { coeff, vars });
  let d = polyDivideByTerm(den, { coeff, vars });

  // Cancel the common factor. `polyGcd` is only a proposal — it counts for
  // nothing unless it divides BOTH sides exactly, which is checked here.
  const g = polyGcd(n, d);
  if (g.size > 0 && polyVars(g).length + (polyAsConstant(g) ? 0 : 1) > 0) {
    const nn = polyDivide(n, g);
    const dd = polyDivide(d, g);
    if (nn && dd && dd.size > 0) {
      n = nn;
      d = dd;
    }
  }
  return normalizeFraction(n, d);
}

/**
 * Clear fractional coefficients out of both halves and put the sign on top, so
 * the reduced form reads like a printed answer: `2/(3x)`, never `1/(1.5x)` or
 * `-2/(1-x)` left as `2/(x-1)`'s double negative.
 */
function normalizeFraction(n: Poly, d: Poly): { num: Poly; den: Poly } {
  const scale = (p: Poly) => {
    let lcm = 1n;
    for (const t of p.values()) lcm = (lcm * t.coeff.d) / bigGcd(lcm, t.coeff.d);
    return lcm;
  };
  const mult = (p: Poly, k: bigint): Poly => {
    const out: Poly = new Map();
    for (const t of p.values())
      polyAddTerm(out, { coeff: ratMul(t.coeff, rat(k)), vars: t.vars });
    return out;
  };
  const k = (scale(n) * scale(d)) / bigGcd(scale(n), scale(d));
  let num = mult(n, k);
  let den = mult(d, k);

  // Drop a whole-number common factor (6/(9x) → 2/(3x)).
  const g = bigGcd(polyContent(num).n, polyContent(den).n);
  if (g > 1n) {
    num = polyDivideByTerm(num, { coeff: rat(g), vars: new Map() });
    den = polyDivideByTerm(den, { coeff: rat(g), vars: new Map() });
  }
  // A denominator whose LEADING term is negative reads as a double negative.
  const leadNeg = (p: Poly) =>
    p.size > 0 && [...p.values()].sort((a, b) => monoCompare(a.vars, b.vars))[0].coeff.n < 0n;
  if (leadNeg(den)) {
    num = polyNeg(num);
    den = polyNeg(den);
  }
  return { num, den };
}

// --- multivariate gcd --------------------------------------------------------

/** The polynomial split by powers of `v`: index = degree, value = coefficient
 * (itself a polynomial in the OTHER variables). */
function coeffsIn(p: Poly, v: string): Poly[] {
  const out: Poly[] = [];
  for (let i = 0; i <= polyDegreeIn(p, v); i++) out.push(new Map());
  for (const t of p.values()) {
    const e = t.vars.get(v) ?? 0;
    const vars = new Map(t.vars);
    vars.delete(v);
    polyAddTerm(out[e], { coeff: t.coeff, vars });
  }
  return out;
}
/** Divide out the polynomial content, leaving the primitive part. */
function primitivePart(p: Poly, v: string): Poly {
  if (p.size === 0) return p;
  const cs = coeffsIn(p, v).filter((c) => c.size > 0);
  let g = cs[0];
  for (const c of cs.slice(1)) g = polyGcd(g, c);
  const pp = polyDivide(p, g);
  return pp ?? p;
}

/**
 * `a` reduced modulo `b` in the variable `v`, scaled by whatever power of b's
 * leading coefficient makes the division exact. Pseudo-division, because the
 * coefficients here are polynomials — a ring, not a field, so you cannot simply
 * divide by the leading coefficient the way `univariateRemainder` does.
 */
function pseudoRemainder(a: Poly, b: Poly, v: string): Poly {
  const db = polyDegreeIn(b, v);
  const lb = coeffsIn(b, v)[db];
  let r = a;
  for (let guard = 0; guard < 256; guard++) {
    const dr = polyDegreeIn(r, v);
    if (r.size === 0 || dr < db) return r;
    const lr = coeffsIn(r, v)[dr];
    const shift: Poly = new Map();
    for (const t of lr.values()) {
      const vars = new Map(t.vars);
      if (dr - db > 0) vars.set(v, dr - db);
      polyAddTerm(shift, { coeff: t.coeff, vars });
    }
    r = polyAdd(polyMul(lb, r), polyNeg(polyMul(shift, b)));
  }
  return r;
}

/**
 * The greatest common divisor of two multivariate polynomials, by the classic
 * recursion: split off a main variable, gcd the contents recursively, then run
 * Euclid on the primitive parts with pseudo-division.
 *
 * A worksheet's algebraic fractions live or die on this — `(p²-q²)(9p-3q)`
 * over `(3p-q)(p+q)²` only collapses to `3(p-q)/(p+q)` if the common
 * `(3p-q)(p+q)` is actually found. The caller re-checks that the result divides
 * both sides, so a gcd this misses costs an un-cancelled fraction, never a
 * wrong one.
 */
export function polyGcd(a: Poly, b: Poly): Poly {
  if (a.size === 0) return b;
  if (b.size === 0) return a;
  const vars = [...new Set([...polyVars(a), ...polyVars(b)])].sort();
  if (vars.length === 0) {
    return polyConst(rat(bigGcd(polyContent(a).n, polyContent(b).n)));
  }
  const v = vars[0];
  const ca = contentIn(a, v);
  const cb = contentIn(b, v);
  const contentGcd = polyGcd(ca, cb);
  const pa = polyDivide(a, ca) ?? a;
  const pb = polyDivide(b, cb) ?? b;

  let x = pa;
  let y = pb;
  for (let guard = 0; guard < 64 && y.size > 0; guard++) {
    const r = pseudoRemainder(x, y, v);
    x = y;
    y = r.size === 0 ? r : primitivePart(r, v);
  }
  return polyMul(contentGcd, primitivePart(x, v));
}

/** The gcd of a polynomial's coefficients when viewed as a polynomial in `v`. */
function contentIn(p: Poly, v: string): Poly {
  const cs = coeffsIn(p, v).filter((c) => c.size > 0);
  if (!cs.length) return polyConst(rat(1n));
  let g = cs[0];
  for (const c of cs.slice(1)) g = polyGcd(g, c);
  return g;
}

// --- helpers the solvers use -------------------------------------------------

/** `p` written as `A*v + B` with A and B free of `v`, or null if it isn't
 * linear in `v`. This is how a change-of-subject isolates its target. */
export function linearIn(p: Poly, v: string): { a: Poly; b: Poly } | null {
  if (polyDegreeIn(p, v) !== 1) return null;
  const a: Poly = new Map();
  const b: Poly = new Map();
  for (const t of p.values()) {
    const e = t.vars.get(v) ?? 0;
    if (e === 0) polyAddTerm(b, t);
    else {
      const vars = new Map(t.vars);
      vars.delete(v);
      polyAddTerm(a, { coeff: t.coeff, vars });
    }
  }
  return { a, b };
}

/** `p` as `A*v^2 + B*v + C`, or null if it isn't quadratic in `v`. */
export function quadraticIn(p: Poly, v: string): { a: Poly; b: Poly; c: Poly } | null {
  if (polyDegreeIn(p, v) !== 2) return null;
  const a: Poly = new Map();
  const b: Poly = new Map();
  const c: Poly = new Map();
  for (const t of p.values()) {
    const e = t.vars.get(v) ?? 0;
    const vars = new Map(t.vars);
    vars.delete(v);
    const target = e === 2 ? a : e === 1 ? b : c;
    polyAddTerm(target, { coeff: t.coeff, vars });
  }
  return { a, b, c };
}

// --- the one entry point the solvers call ------------------------------------

/** Wrap unless the expression is a single bare symbol or number — a printed
 * `2/(3*x)` must never come out as `2/3*x`, which is a different number. */
function group(ascii: string): string {
  return /^-?[A-Za-z0-9_$.]+$/.test(ascii) ? ascii : `(${ascii})`;
}

/**
 * Fully simplify an ascii expression: expand, collect like terms, and — when it
 * is a quotient — reduce the fraction to lowest terms. Returns null when the
 * expression isn't algebraic enough to normalize, so the caller keeps whatever
 * mathsteps produced.
 *
 * Nothing here is trusted on its own: the caller still puts the result through
 * the substitution gate, which is what makes an aggressive normalizer safe.
 */
export function simplifyAlgebraic(ascii: string): string | null {
  // Cheap pre-gate. `rationalize` below is mathjs's, outside our budget, and a
  // scanned word problem reaches here as a product of its own letters — twenty
  // "variables" it will grind on forever. Real algebra never gets that wide.
  const names = new Set(ascii.match(/[A-Za-z_$][A-Za-z0-9_$]*/g) ?? []);
  if (names.size > MAX_VARS) return null;

  const direct = toPoly(ascii);
  // No atoms means it really is a polynomial — done.
  if (direct && direct.atoms.source.size === 0)
    return polyToAscii(direct.poly, direct.atoms.source);
  // Otherwise the atoms may be FRACTIONS, which `toPoly` had to make opaque but
  // which a common denominator dissolves. Try that before settling.
  return simplifyRational(ascii) ?? (direct ? polyToAscii(direct.poly, direct.atoms.source) : null);
}

/** Put an expression over one denominator and reduce it to lowest terms. */
function simplifyRational(ascii: string): string | null {
  // A quotient by something symbolic — put it over one denominator first.
  let num: MathNode;
  let den: MathNode;
  try {
    const r = rationalize(ascii, {}, true) as unknown as {
      numerator: MathNode;
      denominator: MathNode | null;
    };
    if (!r.denominator) return null;
    num = r.numerator;
    den = r.denominator;
  } catch {
    return null;
  }
  const pn = toPoly(num.toString());
  const pd = toPoly(den.toString());
  if (!pn || !pd) return null;
  const atomSource = new Map([...pn.atoms.source, ...pd.atoms.source]);
  const reduced = reduceFraction(pn.poly, pd.poly);
  const top = polyToAscii(reduced.num, atomSource);
  const bottom = polyToAscii(reduced.den, atomSource);
  if (bottom === "1") return top;
  if (bottom === "0") return null;
  return `${group(top)}/${group(bottom)}`;
}

export { polyAdd, polyNeg, polyMul, polyConst, polyAsConstant };

// --- factorization -----------------------------------------------------------

/**
 * Factorise a polynomial the way the worksheet chapter on factorisation does:
 * pull the common factor, split the rational roots out of a single-variable
 * polynomial, recognise a difference of two squares, and — for the multivariate
 * four-term case (`ax − ay + 2x − 2y`) — group.
 *
 * Returns the factored ascii, or null when the expression is not a polynomial
 * or does not factor at all. Nothing here is trusted on its own: the caller
 * still puts the printed form back through the numeric equality gate, so a bug
 * in this file can cost an answer but can never fake one.
 */
export function factorPolynomial(ascii: string): string | null {
  const got = toPoly(ascii);
  if (!got || got.atoms.source.size > 0 || got.poly.size === 0) return null;
  const factors = withBudget(() => factorList(got.poly, 0));
  if (!factors || factors.length < 2) return null;
  const out = factorsToAscii(factors, got.atoms.source);
  // A single monomial "factors" into itself times 1. That is not a factorisation.
  return out === polyToAscii(got.poly, got.atoms.source) ? null : out;
}

/** Print a factor list as a product, parenthesising anything that is a sum. */
function factorsToAscii(factors: Poly[], atomSource: Map<string, string>): string {
  // A leading `-1` reads as a sign, not as a factor: `-(x - 3)(x + 1)`.
  let sign = "";
  // Repeats collapse into a power: `(x + 1)(x + 1)` is `(x + 1)^2`.
  const seen = new Map<string, number>();
  for (const f of factors) {
    const c = polyAsConstant(f);
    if (c && c.n === -1n && c.d === 1n) {
      sign = sign === "-" ? "" : "-";
      continue;
    }
    if (c && c.n === 1n && c.d === 1n) continue;
    const body = polyToAscii(f, atomSource);
    const text = f.size > 1 ? `(${body})` : body;
    seen.set(text, (seen.get(text) ?? 0) + 1);
  }
  const parts = [...seen].map(([text, n]) => (n === 1 ? text : `${text}^${n}`));
  if (!parts.length) return `${sign}1`;
  return sign + parts.join("*");
}

/** Recursively split `p`; the product of the result is always `p`. */
function factorList(p: Poly, depth: number): Poly[] {
  if (depth > 6 || p.size === 0) return [p];

  // 1. The common factor — content and the monomial every term carries.
  const cf = polyCommonFactor(p);
  const trivial = cf.coeff.n === 1n && cf.coeff.d === 1n && cf.vars.size === 0;
  if (!trivial) {
    const rest = polyDivideByTerm(p, cf);
    const head: Poly = new Map([[monoKey(cf.vars), { coeff: cf.coeff, vars: cf.vars }]]);
    // Only worth reporting if what's left still factors, or the head is real.
    return [head, ...factorList(rest, depth + 1)];
  }
  if (p.size === 1) return [p];

  // 2. A negative lead reads better with the sign outside.
  const lead = [...p.values()].sort((a, b) => monoCompare(a.vars, b.vars))[0];
  if (lead.coeff.n < 0n) {
    const inner = factorList(polyNeg(p), depth + 1);
    if (inner.length > 1) return [polyConst(rat(-1n)), ...inner];
  }

  return (
    factorByRoots(p, depth) ??
    factorDifferenceOfSquares(p, depth) ??
    factorQuadraticInVar(p, depth) ??
    factorByGrouping(p, depth) ??
    [p]
  );
}

/** The polynomial whose square is `p` — only the easy cases: zero, or a single
 * term with even exponents and a square coefficient. */
function polySqrt(p: Poly): Poly | null {
  if (p.size === 0) return ZERO;
  if (p.size !== 1) return null;
  const t = [...p.values()][0];
  if (t.coeff.n < 0n) return null;
  const n = exactSqrt(t.coeff.n);
  const d = exactSqrt(t.coeff.d);
  if (n === null || d === null) return null;
  const vars: Monomial = new Map();
  for (const [v, e] of t.vars) {
    if (e % 2 !== 0) return null;
    vars.set(v, e / 2);
  }
  const out: Poly = new Map();
  polyAddTerm(out, { coeff: rat(n, d), vars });
  return out;
}

/**
 * A quadratic in ONE of its variables whose other variables ride along in the
 * coefficients — `x² + 5xy + 6y²`, `a² − 2ab + b²`. Complete the square over
 * those coefficients: the two factors are `2a·v + b ∓ √(b² − 4ac)`, and the
 * leftover constant is recovered by dividing, which is also the check that the
 * whole construction was legitimate.
 */
function factorQuadraticInVar(p: Poly, depth: number): Poly[] | null {
  for (const v of polyVars(p)) {
    if (polyDegreeIn(p, v) !== 2) continue;
    const q = quadraticIn(p, v);
    if (!q || polyIsZero(q.a)) continue;
    const disc = polyAdd(polyMul(q.b, q.b), polyNeg(polyMul(polyConst(rat(4n)), polyMul(q.a, q.c))));
    const s = polySqrt(disc);
    if (!s) continue;
    const twoAv = polyMul(polyConst(rat(2n)), polyMul(q.a, monomial(v)));
    const build = (sign: -1n | 1n): Poly =>
      polyAdd(polyAdd(twoAv, q.b), polyMul(polyConst(rat(sign)), s));
    const halves = [build(-1n), build(1n)].map((f) => {
      const cf = polyCommonFactor(f);
      return polyDivideByTerm(f, cf);
    });
    if (halves.some((h) => h.size < 2)) continue;
    const k = polyDivide(p, polyMul(halves[0], halves[1]));
    const c = k && polyAsConstant(k);
    if (!c) continue;
    const out = halves.flatMap((h) => factorList(h, depth + 1));
    return c.n === 1n && c.d === 1n ? out : [polyConst(c), ...out];
  }
  return null;
}

/** The polynomial `v`. */
function monomial(v: string): Poly {
  const out: Poly = new Map();
  polyAddTerm(out, { coeff: rat(1n), vars: new Map([[v, 1]]) });
  return out;
}

/** Integer square root, or null when `n` is not a perfect square. */
function exactSqrt(n: bigint): bigint | null {
  if (n < 0n) return null;
  if (n < 2n) return n;
  let x = n;
  let y = (x + 1n) / 2n;
  while (y < x) {
    x = y;
    y = (x + n / x) / 2n;
  }
  return x * x === n ? x : null;
}

/** Positive divisors of `n`, or null when it is too big to enumerate. */
function divisors(n: bigint): bigint[] | null {
  const a = bigAbs(n);
  if (a === 0n || a > 1_000_000n) return null;
  const out: bigint[] = [];
  for (let i = 1n; i * i <= a; i++) {
    if (a % i === 0n) {
      out.push(i);
      if (i * i !== a) out.push(a / i);
    }
  }
  return out;
}

/**
 * Single-variable: hunt for a rational root `p/q` (p divides the constant term,
 * q the leading one), divide `qx − p` out, and recurse. This is what turns
 * `p² + 6p − 16` into `(p − 2)(p + 8)` and it keeps working for a cubic.
 */
function factorByRoots(p: Poly, depth: number): Poly[] | null {
  const vars = polyVars(p);
  if (vars.length !== 1) return null;
  const v = vars[0];
  const deg = polyDegreeIn(p, v);
  if (deg < 2) return null;
  const coeff = (n: number): Rational => {
    for (const t of p.values()) if ((t.vars.get(v) ?? 0) === n) return t.coeff;
    return rat(0n);
  };
  const lc = coeff(deg);
  const c0 = coeff(0);
  if (lc.d !== 1n || c0.d !== 1n) return null; // content was already removed

  const ps = divisors(c0.n);
  const qs = divisors(lc.n);
  if (!ps || !qs) return null;
  for (const q of qs) {
    for (const num of ps) {
      for (const sign of [1n, -1n]) {
        // qx − sign·num, i.e. the root sign·num/q.
        const divisor: Poly = new Map();
        polyAddTerm(divisor, { coeff: rat(q), vars: new Map([[v, 1]]) });
        polyAddTerm(divisor, { coeff: rat(-sign * num), vars: new Map() });
        const quo = polyDivide(p, divisor);
        if (quo) return [divisor, ...factorList(quo, depth + 1)];
      }
    }
  }
  return null;
}

/** `u² − v²` → `(u − v)(u + v)`, including the multivariate `4a² − 9b²`. */
function factorDifferenceOfSquares(p: Poly, depth: number): Poly[] | null {
  if (p.size !== 2) return null;
  const [a, b] = [...p.values()].sort((x, y) => monoCompare(x.vars, y.vars));
  if (a.coeff.n < 0n === b.coeff.n < 0n) return null; // needs opposite signs
  const root = (t: Term): Term | null => {
    const n = exactSqrt(bigAbs(t.coeff.n));
    const d = exactSqrt(t.coeff.d);
    if (n === null || d === null) return null;
    const vars: Monomial = new Map();
    for (const [v, e] of t.vars) {
      if (e % 2 !== 0) return null;
      vars.set(v, e / 2);
    }
    return { coeff: rat(n, d), vars };
  };
  const [ra, rb] = [root(a), root(b)];
  if (!ra || !rb) return null;
  // `a` is the positive one after the sign test above only if it leads; order
  // so the subtraction is written against the positive square.
  const [pos, neg] = a.coeff.n > 0n ? [ra, rb] : [rb, ra];
  const u: Poly = new Map([[monoKey(pos.vars), pos]]);
  const w: Poly = new Map([[monoKey(neg.vars), neg]]);
  const first = polyAdd(u, polyNeg(w));
  const second = polyAdd(u, w);
  return [...factorList(first, depth + 1), ...factorList(second, depth + 1)];
}

/**
 * Grouping: split the terms into two bags, pull each bag's common factor, and
 * if what is left over is the SAME polynomial in both bags, that shared part is
 * a factor. `ax − ay + 2x − 2y` → `a(x − y) + 2(x − y)` → `(a + 2)(x − y)`.
 */
function factorByGrouping(p: Poly, depth: number): Poly[] | null {
  const terms = [...p.values()];
  if (terms.length < 4 || terms.length > 8) return null;
  const n = terms.length;
  // Term 0 always lands in bag A, so each split is considered once.
  for (let mask = 0; mask < 1 << (n - 1); mask++) {
    const a: Term[] = [terms[0]];
    const b: Term[] = [];
    for (let i = 1; i < n; i++) ((mask >> (i - 1)) & 1 ? b : a).push(terms[i]);
    if (!b.length || a.length < 2 || b.length < 2) continue;
    const bag = (ts: Term[]): Poly => {
      const out: Poly = new Map();
      for (const t of ts) polyAddTerm(out, t);
      return out;
    };
    const [pa, pb] = [bag(a), bag(b)];
    const [fa, fb] = [polyCommonFactor(pa), polyCommonFactor(pb)];
    const [qa, qb] = [polyDivideByTerm(pa, fa), polyDivideByTerm(pb, fb)];
    if (qa.size < 2) continue;
    const term = (f: { coeff: Rational; vars: Monomial }): Poly =>
      new Map([[monoKey(f.vars), { coeff: f.coeff, vars: f.vars }]]);
    // Same leftover, or the same up to sign — `x − y` and `y − x` group too.
    for (const [q, head] of [
      [qb, polyAdd(term(fa), term(fb))],
      [polyNeg(qb), polyAdd(term(fa), polyNeg(term(fb)))],
    ] as [Poly, Poly][]) {
      if (polyToAscii(qa) !== polyToAscii(q) || head.size === 0) continue;
      return [...factorList(head, depth + 1), ...factorList(qa, depth + 1)];
    }
  }
  return null;
}

/**
 * Every real root of a single-variable polynomial, exactly — by factoring it
 * and reading the roots off the linear and quadratic pieces. Returns null when
 * the expression isn't a one-variable polynomial, or when a piece of degree 3
 * or more survives factoring (no rational root ⇒ nothing exact to print, so the
 * honest answer is to decline). A piece with a negative discriminant simply
 * contributes no real roots.
 */
export function univariateRealRoots(ascii: string): number[] | null {
  const got = toPoly(ascii);
  if (!got || got.atoms.source.size > 0) return null;
  const vars = polyVars(got.poly);
  if (vars.length !== 1) return null;
  const v = vars[0];
  const factors = withBudget(() => factorList(got.poly, 0));
  if (!factors) return null;

  const roots: number[] = [];
  for (const f of factors) {
    const degree = polyDegreeIn(f, v);
    if (degree === 0) continue;
    const c = (n: number): number => {
      for (const t of f.values()) if ((t.vars.get(v) ?? 0) === n) return Number(t.coeff.n) / Number(t.coeff.d);
      return 0;
    };
    if (degree === 1) {
      roots.push(-c(0) / c(1));
      continue;
    }
    if (degree === 2) {
      const [a, b, k] = [c(2), c(1), c(0)];
      const disc = b * b - 4 * a * k;
      if (disc < 0) continue; // no real root from this piece
      const s = Math.sqrt(disc);
      roots.push((-b + s) / (2 * a), (-b - s) / (2 * a));
      continue;
    }
    return null;
  }
  return roots;
}
