/**
 * Initial-value point evaluation for ODEs — a DETERMINISTIC engine (no LLM).
 *
 * For an initial-value problem that asks for the value of the solution at ONE
 * specific point —  dy/dx = f(x, y),  y(a) = y₀,  "find y(b)"  — we integrate the
 * IVP numerically and return y(b) as a VERIFIED convergent value. No closed form
 * is required, so it covers the common exam staple the symbolic ODE path can't:
 * a first/second-order IVP whose solution has no elementary form but whose value
 * at a point is a perfectly well-defined number.
 *
 * THE GOLDEN RULE — we never ship a value we cannot trust:
 *   Two INDEPENDENT integrators evaluate the SAME IVP —
 *     • classical RK4 with step-doubling + Richardson extrapolation, and
 *     • a fixed-step Dormand–Prince DP5 (a different tableau, one order higher) —
 *   and the answer is returned ONLY if (a) RK4 has itself converged under
 *   step-halving, (b) the two integrators agree to a tight relative tolerance, and
 *   (c) the trajectory stays finite (no singularity separates a from b). We DECLINE
 *   (honest couldn't-verify) whenever:
 *     • the problem is UNDERDETERMINED — fewer initial conditions than the order,
 *       conditions at more than one point (a boundary-value problem), or a target
 *       that isn't a plain value y(b);
 *     • the ODE is not explicitly solvable for its highest derivative (implicit /
 *       nonlinear in y′ or y″ — e.g. (y′)² = …);
 *     • a numeric-METHOD qualifier is present ("Euler's method", "step size h = …",
 *       "Runge–Kutta") — that asks for a SPECIFIC approximation, not the true value;
 *     • the integrators disagree, RK4 fails to converge, or the path blows up.
 *   A decline is honest; the LLM-candidate ODE path still handles the symbolic
 *   general/particular solution.
 *
 * We reuse `parseOde` for the residual + variable + initial-condition parsing, so
 * this engine only adds the target-point detection, the determinacy gate, and the
 * numeric integrate-and-cross-check.
 */
import { compile, derivative, parse, EvalFunction } from "mathjs";

import { asciiToLatex } from "./latex";
import { normalizeOdeLatex, parseOde } from "./ode";
import { FinalAnswer, MethodData } from "./types";

export interface OdePointEvalQuery {
  /** Residual F(x, y, dy, ddy) = 0, ascii, in tokens indepVar/depVar/dy/ddy. */
  residual: string;
  depVar: string;
  indepVar: string;
  order: 1 | 2;
  /** The initial point a where every condition is anchored. */
  at: number;
  /** y(a). */
  y0: number;
  /** y′(a) — present iff order === 2. */
  dy0?: number;
  /** The target point b: we return y(b). */
  target: number;
}

// --- numeric constants ------------------------------------------------------
const BLOWUP = 1e12; // |state| beyond this ⇒ a singularity/divergence ⇒ decline
const MAX_SPAN = 1e4; // |b − a| beyond this ⇒ unresolvable by a fixed grid ⇒ decline
const N_START = 64; // initial RK4 step count
const N_MAX = 1 << 16; // 65536 — if RK4 hasn't converged by here, decline (stiff/wiggly)
const CONV_TOL = 1e-9; // RK4 self-convergence (relative) under step doubling
const VERIFY_TOL = 1e-6; // RK4-vs-DP5 agreement (relative) — the golden-rule gate
const SOLVE_EPS = 1e-12; // |∂F/∂(top deriv)| below this ⇒ not solvable here ⇒ decline
// A pole straddled by the grid (never landing on a node) leaves the ENDPOINT
// looking converged — both integrators realize the same analytic continuation
// past the pole — while max|y| along the path grows ~2×/doubling forever. We
// therefore require the PEAK to stabilize too: a bounded solution on [a,b] settles
// its peak (ratio→1), a straddled pole never does. (Empirically ~100%/doubling.)
const PEAK_REL_TOL = 0.25; // max growth in peak|state| per doubling once endpoint-converged
const PEAK_ABS_TOL = 1e-6; // absolute floor so a near-zero peak counts as stable
// A feature in the RHS far narrower than the step (an ultra-thin spike in f) is
// stepped over IDENTICALLY by both integrators, so they "converge" and agree on a
// value that misses it. After convergence we probe |f| densely along the solution
// and compare to the largest |f| the grid actually sampled — a big gap means an
// unresolved spike sits between the nodes. (Catches features down to ~1e-6 wide.)
const SPIKE_PROBE = 1 << 18; // 262144 dense samples of |f| along the converged path
const SPIKE_FACTOR = 4; // dense |f| may exceed the grid's max by at most this ⇒ resolved

// Numeric-method qualifiers: these ask for a SPECIFIC method's approximation
// (which differs from the true value), so the true-value engine must stand down.
const METHOD_QUALIFIER =
  /\b(euler|runge[\s-]*kutta|rk\s*[24]|heun|midpoint\s+method|improved\s+euler|predictor|corrector|taylor\s+series\s+method|picard|step\s*size)\b/i;

/**
 * Detect an initial-value point-evaluation query, or null. Reuses `parseOde` for
 * the residual/variables/initial-conditions; adds the target detection and the
 * determinacy gate that makes the IVP well-posed.
 */
export function parseOdePointEval(rawLatex: string): OdePointEvalQuery | null {
  if (!rawLatex || rawLatex.length > 2000) return null;
  // A numeric-METHOD problem wants that method's approximation, not the true
  // value — stand down so we never answer a different question than was asked.
  if (METHOD_QUALIFIER.test(rawLatex)) return null;

  const ode = parseOde(rawLatex);
  if (!ode) return null;
  const { residual, depVar, indepVar, order, initial } = ode;
  if (order !== 1 && order !== 2) return null;

  // --- dropped conditions: a boundary / over-determining clause parseInitial cannot
  //     read — because its VALUE is symbolic (√5, π, e) OR its POINT is non-numeric
  //     (y(π), y(1e0), y(\frac12), y(.5) — none match parseInitial's `-?\d+(?:\.\d+)?`)
  //     — is silently dropped, so an ill-posed two-point / over-determined problem
  //     would ship as a well-posed IVP. Count EVERY `dep(ANY) =` and `= dep(ANY)`
  //     clause (any paren-free point, any value token); if more exist than
  //     parseInitial could read, a condition was dropped → decline (can't establish
  //     well-posedness). The bare target `dep(b)` carries no adjacent `=`, so it is
  //     never counted, and this counter is always ≥ parseInitial's tally — it only
  //     fires on a genuinely unreadable condition, never over-declines a clean IVP. -
  const norm = normalizeOdeLatex(rawLatex);
  const pt = `${depVar}\\s*'{0,2}\\s*\\([^()]*\\)`;
  const nConditions =
    [...norm.matchAll(new RegExp(`${pt}\\s*=`, "g"))].length +
    [...norm.matchAll(new RegExp(`=\\s*${pt}`, "g"))].length;
  if (nConditions > initial.length) return null;

  // --- target: exactly one  dep(number)  that is NOT an initial condition -----
  const target = findTarget(rawLatex, depVar);
  if (target === null) return null;

  // --- determinacy: a well-posed IVP has `order` conditions, all at ONE point,
  //     at derivative orders 0..order-1 (an IVP, not a BVP, not underdetermined). -
  if (initial.length !== order) return null;
  const at = initial[0].at;
  if (!initial.every((ic) => ic.at === at)) return null; // BVP / mixed points
  const gotOrders = initial.map((ic) => ic.order).sort((a, b) => a - b);
  const wantOrders = order === 1 ? [0] : [0, 1];
  if (gotOrders.length !== wantOrders.length) return null;
  if (!gotOrders.every((o, k) => o === wantOrders[k])) return null;

  if (!Number.isFinite(target) || Math.abs(target - at) > MAX_SPAN) return null;

  const y0 = initial.find((ic) => ic.order === 0)?.value;
  if (y0 === undefined || !Number.isFinite(y0)) return null;
  const dy0 = order === 2 ? initial.find((ic) => ic.order === 1)?.value : undefined;
  if (order === 2 && (dy0 === undefined || !Number.isFinite(dy0))) return null;

  return { residual, depVar, indepVar, order, at, y0, dy0, target };
}

/** The single target point b from a `dep(number)` that carries NO `=` (which would
 * make it an initial/boundary CONDITION — of any RHS form: `= 1`, `= \frac{1}{2}`,
 * `= 2.5e2` …, not just a plain signed digit) and NO prime (y′(b) is out of scope).
 * Returns null unless EXACTLY one such point is present. */
function findTarget(rawLatex: string, dep: string): number | null {
  // Same decoration-stripping parseOde uses (\left\right, &=, :=), plus thin
  // spaces — so a condition written `y(1) &= 5` / `y\left(2\right) = 5` is seen as
  // a CONDITION (its `=` trips the negative lookahead), never a bare target point.
  const norm = normalizeOdeLatex(rawLatex).replace(/\\,|\\;|\\!|\\ |~/g, " ");
  const num = "-?\\d+(?:\\.\\d+)?";
  // dep, no prime, ( number ), NOT followed by `=` (anything after `=` marks it a
  // condition, not a bare target — so `y(2) = \frac{1}{2}` is never the target).
  const re = new RegExp(`${dep}\\s*('{0,2})\\s*\\(\\s*(${num})\\s*\\)(?!\\s*=)`, "g");
  const points = new Set<number>();
  for (const m of norm.matchAll(re)) {
    if (m[1].length !== 0) continue; // y′(b) / y″(b) — a derivative target, out of scope
    points.add(Number(m[2]));
  }
  if (points.size !== 1) return null;
  return [...points][0];
}

// --- solving ----------------------------------------------------------------

type Deriv = (x: number, state: number[]) => number[] | null;

/**
 * Integrate the IVP and return y(target), VERIFIED, or null (couldn't-verify).
 * The whole numeric contract lives here: compile once, build the explicit RHS by
 * solving the residual for the top derivative, then integrate + cross-check.
 */
export function solveOdePointEval(
  q: OdePointEvalQuery
): { answer: FinalAnswer; methods: MethodData[] } | null {
  const evalRes = buildResidualEvaluator(q.residual, q.depVar, q.indepVar);
  if (!evalRes) return null;

  // Symbolic linearity gate (primary): the residual must be AFFINE — A·t + B — in its
  // top-derivative token t. Differentiate F symbolically w.r.t. t; if ∂F/∂t STILL
  // contains t, F is nonlinear in the top derivative — (y′)², or a product of sines
  // sin(π√2 y′)·sin(π√3 y′) crafted to read as linear on ANY fixed sampling lattice —
  // so we decline. A code-reading adversary can null a fixed sampling grid, but cannot
  // make a symbolic derivative forget its variable. (Affineness in the TOP derivative
  // only: y″ = (y′)² is fine — nonlinear in the LOWER derivative, linear in y″.)
  const topToken = q.order === 2 ? "ddy" : "dy";
  if (provablyNonAffineInTop(q.residual, topToken)) return null;

  // The residual must be LINEAR in — and genuinely constrain — the top derivative,
  // else it isn't an explicit ODE we can integrate. Checked across sample states.
  // (Belt-and-suspenders: also catches an unsupported-function nonlinearity the
  // symbolic gate can't differentiate — a |y′| kink, a ⌊y′⌋ jump — via sampling.)
  if (!isExplicitlySolvable(evalRes, q)) return null;

  const deriv = buildDeriv(evalRes, q);
  const state0 = q.order === 2 ? [q.y0, q.dy0 as number] : [q.y0];

  // Degenerate: the target IS the initial point — the value is the given y₀.
  if (q.target === q.at) {
    return format(q, q.y0, /* exact */ true);
  }

  // Uniqueness gate: at a NON-Lipschitz initial state the IVP has more than one
  // solution (e.g. y′ = 3y^{2/3}, y(0)=0 admits y≡0, y=x³, and a family of delayed
  // cubics — Peano gives existence, Picard fails). Both integrators realize the
  // SAME (trivial) branch and agree, so the gate can't see it. Refuse rather than
  // ship one arbitrary branch as "the" value.
  if (!locallyLipschitz(deriv, q.at, state0)) return null;

  // 1) RK4 with step doubling → endpoint convergence + peak stability, then a
  //    Richardson-extrapolated value. We require BOTH the endpoint AND the peak
  //    |state| to settle: a pole straddled by the grid leaves the endpoint looking
  //    converged (the analytic continuation past the pole) while the peak grows
  //    without bound — the only signal that a singularity lies in (a, b).
  let prevEnd: number | null = null;
  let prevPeak: number | null = null;
  let richardson: number | null = null;
  let convergedN = 0;
  for (let n = N_START; n <= N_MAX; n *= 2) {
    const s = rk4(deriv, state0, q.at, q.target, n);
    if (!s) return null; // blow-up / singularity / unsolvable on the path
    const v = s.state[0];
    if (prevEnd !== null && prevPeak !== null) {
      const endConv = Math.abs(v - prevEnd) <= CONV_TOL * (1 + Math.abs(v));
      const peakStable = s.peak <= prevPeak * (1 + PEAK_REL_TOL) + PEAK_ABS_TOL;
      if (endConv && peakStable) {
        richardson = v + (v - prevEnd) / 15; // RK4 error ~ h⁴ ⇒ Richardson is O(h⁵)
        convergedN = n;
        break;
      }
    }
    prevEnd = v;
    prevPeak = s.peak;
  }
  if (richardson === null) return null; // endpoint or peak never settled ⇒ decline

  // 2) Independent Dormand–Prince DP5 (different tableau, order 5) at a fine grid.
  const dpState = dp5(deriv, state0, q.at, q.target, Math.max(256, convergedN));
  if (!dpState) return null;
  const dpValue = dpState[0];

  // 3) The golden-rule gate: two independent integrators must agree.
  if (Math.abs(richardson - dpValue) > VERIFY_TOL * (1 + Math.abs(richardson))) {
    return null;
  }

  // 4) Resolution gate: the grid must actually RESOLVE the RHS. An ultra-thin spike
  //    in f between the nodes is stepped over by both integrators, so they agree on
  //    a value that misses it entirely (e.g. y′ = 10⁶·e^{−10¹²(x−a)²} integrates to
  //    ≈0 instead of √π). A dense probe of |f| along the solution exposes it.
  if (!gridResolvesRhs(deriv, state0, q.at, q.target, convergedN)) return null;

  return format(q, richardson, /* exact */ false);
}

/** Is the initial state a LIPSCHITZ point of the RHS (⇒ the IVP is unique, by
 * Picard–Lindelöf)? We estimate the local Lipschitz constant of the RHS in the
 * solution component at shrinking perturbations δ. At a Lipschitz point the
 * difference quotient settles to the derivative (≈constant); at a non-Lipschitz
 * point (∂f/∂y → ∞, e.g. 3y^{2/3} at y=0) it GROWS without bound as δ→0. Returns
 * true when it can't decide (unevaluable) — the integrator's own guards decide. */
function locallyLipschitz(deriv: Deriv, x: number, state: number[]): boolean {
  const base = deriv(x, state);
  if (!base) return true;
  const Ls: number[] = [];
  for (const d of [1e-2, 1e-4, 1e-6]) {
    let L = NaN;
    // Perturb EVERY state component, not just y: a 2nd-order RHS can be singular in
    // the DERIVATIVE component too (e.g. 3(y′)^{2/3} at y′=0 — Peano non-uniqueness
    // lives in y′, invisible if we only wiggle y = state[0]).
    for (let c = 0; c < state.length; c++) {
      for (const sgn of [1, -1]) {
        const st = state.slice();
        st[c] += sgn * d;
        const f = deriv(x, st);
        if (!f) continue;
        let diff = 0;
        for (let j = 0; j < f.length; j++) diff = Math.max(diff, Math.abs(f[j] - base[j]));
        const cand = diff / d;
        L = Number.isNaN(L) ? cand : Math.max(L, cand);
      }
    }
    Ls.push(L);
  }
  if (Ls.some((v) => Number.isNaN(v))) return true; // couldn't probe ⇒ don't over-decline
  return !(Ls[2] > 8 * Ls[0] + 1 && Ls[2] > Ls[1] && Ls[1] > Ls[0]);
}

/** Does the grid at `n` steps RESOLVE the RHS? Re-integrate storing the trajectory
 * and the largest |f| the grid actually sampled, then probe |f| DENSELY between
 * the nodes (interpolating the state linearly). If the dense probe uncovers a value
 * far larger than anything the grid saw, an unresolved spike sits between the nodes
 * and the "converged" answer is untrustworthy ⇒ false (decline). Returns true when
 * the RHS can't be evaluated (the integrator's own guards already handle that). */
function gridResolvesRhs(deriv: Deriv, s0: number[], xa: number, xb: number, n: number): boolean {
  const h = (xb - xa) / n;
  const states: number[][] = [s0.slice()];
  let s = s0.slice();
  let x = xa;
  let maxGrid = 0;
  const scan = (d: number[]) => {
    for (const v of d) {
      const a = Math.abs(v);
      if (a > maxGrid) maxGrid = a;
    }
  };
  for (let i = 0; i < n; i++) {
    const k1 = deriv(x, s);
    if (!k1) return true;
    const k2 = deriv(x + h / 2, axpy(s, k1, h / 2));
    if (!k2) return true;
    const k3 = deriv(x + h / 2, axpy(s, k2, h / 2));
    if (!k3) return true;
    const k4 = deriv(x + h, axpy(s, k3, h));
    if (!k4) return true;
    scan(k1);
    scan(k2);
    scan(k3);
    scan(k4);
    const ns = s.slice();
    for (let j = 0; j < s.length; j++) ns[j] += (h / 6) * (k1[j] + 2 * k2[j] + 2 * k3[j] + k4[j]);
    s = ns;
    x += h;
    states.push(s.slice());
  }
  const span = xb - xa;
  let maxDense = maxGrid;
  for (let j = 0; j <= SPIKE_PROBE; j++) {
    const xx = xa + (span * j) / SPIKE_PROBE;
    let idx = Math.floor((xx - xa) / h);
    if (idx < 0) idx = 0;
    if (idx >= n) idx = n - 1;
    const frac = (xx - (xa + idx * h)) / h;
    const st = states[idx].map((v, k) => v + frac * (states[idx + 1][k] - v));
    const d = deriv(xx, st);
    if (d) for (const v of d) { const a = Math.abs(v); if (a > maxDense) maxDense = a; }
  }
  return maxDense <= SPIKE_FACTOR * (maxGrid + PEAK_ABS_TOL);
}

/** Compile the residual ONCE and wrap it as a fast finite-real evaluator over the
 * four tokens. Returns null if the residual doesn't compile. */
function buildResidualEvaluator(
  residual: string,
  dep: string,
  indep: string
): ((x: number, y: number, dy: number, ddy: number) => number) | null {
  let code: EvalFunction;
  try {
    parse(residual); // surface a parse error before compiling
    code = compile(residual);
  } catch {
    return null;
  }
  const scope: Record<string, number> = { [indep]: 0, [dep]: 0, dy: 0, ddy: 0 };
  return (x, y, dy, ddy) => {
    scope[indep] = x;
    scope[dep] = y;
    scope.dy = dy;
    scope.ddy = ddy;
    try {
      const v = code.evaluate(scope);
      return typeof v === "number" && Number.isFinite(v) ? v : NaN;
    } catch {
      return NaN;
    }
  };
}

type ResEval = (x: number, y: number, dy: number, ddy: number) => number;

/** Solve the residual for the top derivative at one state (linear solve). The
 * residual is A·t + B in the top-derivative token t; returns −B/A, or NaN when A
 * ≈ 0 (locally unsolvable → a singularity we must not integrate through). */
function solveTop(evalRes: ResEval, q: OdePointEvalQuery, x: number, y: number, dy: number): number {
  const r0 = q.order === 2 ? evalRes(x, y, dy, 0) : evalRes(x, y, 0, 0);
  const r1 = q.order === 2 ? evalRes(x, y, dy, 1) : evalRes(x, y, 1, 0);
  if (!Number.isFinite(r0) || !Number.isFinite(r1)) return NaN;
  const a = r1 - r0;
  if (Math.abs(a) < SOLVE_EPS * (1 + Math.abs(r0) + Math.abs(r1))) return NaN;
  return -r0 / a;
}

/** The explicit RHS of the first-order system: order 1 → [y′]; order 2 → [y′, y″]. */
function buildDeriv(evalRes: ResEval, q: OdePointEvalQuery): Deriv {
  if (q.order === 1) {
    return (x, s) => {
      const d = solveTop(evalRes, q, x, s[0], 0);
      return Number.isFinite(d) ? [d] : null;
    };
  }
  return (x, s) => {
    const dd = solveTop(evalRes, q, x, s[0], s[1]);
    return Number.isFinite(dd) ? [s[1], dd] : null;
  };
}

/** PROVE (symbolically) that the residual is NONLINEAR in its top-derivative token:
 * differentiate F w.r.t. t and report whether ∂F/∂t still contains t. An affine
 * residual A·t + B differentiates to a t-free A ⇒ false (integrable); any genuine
 * nonlinearity — t², sin(t)·sin(t), e^t — leaves t in the derivative ⇒ true ⇒ decline.
 * Returns false when the derivative can't be formed (an unsupported function, e.g.
 * ⌊·⌋ or |·|): we DECLINE only on a POSITIVE proof, leaving the numeric sampling gate
 * to judge, so an undifferentiable-but-linear RHS (⌊x⌋ in the RHS) is not over-declined
 * while an undifferentiable-and-nonlinear one (|y′|) is still caught there by its kink. */
function provablyNonAffineInTop(residual: string, topToken: string): boolean {
  let d: ReturnType<typeof derivative>;
  try {
    d = derivative(parse(residual), topToken);
  } catch {
    return false;
  }
  let hasTop = false;
  d.traverse((node) => {
    const n = node as unknown as { isSymbolNode?: boolean; name?: string };
    if (n.isSymbolNode && n.name === topToken) hasTop = true;
  });
  return hasTop;
}

/** The residual must be linear in AND genuinely depend on the top derivative,
 * across a spread of sample states — otherwise it's implicit / nonlinear in y′
 * (e.g. (y′)²=…) and this engine cannot integrate it safely. */
function isExplicitlySolvable(evalRes: ResEval, q: OdePointEvalQuery): boolean {
  const xs = [q.at, q.at + 0.3, q.at - 0.4, (q.at + q.target) / 2, q.target];
  const ys = [q.y0, q.y0 + 0.7, q.y0 - 0.5];
  const ds = q.order === 2 ? [q.dy0 as number, (q.dy0 as number) + 0.6, 0.2] : [0];
  // Sample the residual as a function of its TOP derivative at UNIFORMLY spaced
  // points spanning zero. Two nonlinearities must break the test:
  //   • an absolute-value kink at 0 (|y′| = … : multi-valued in the derivative) —
  //     hence the symmetric spread INCLUDING negatives and 0 (collinear {0,1,2}
  //     misses it, |t| being a straight line there); and
  //   • a PERIODIC nonlinearity (e.g. sin(π y′), whose zeros sit on the integers) —
  //     hence an IRRATIONAL step, so no sample lands on a zero and integer sampling
  //     can't make sin(π t) look linear. Uniform spacing keeps a genuinely linear
  //     residual at second-difference 0 EXACTLY, for any step.
  // A SINGLE irrational step can still be evaded: a periodic nonlinearity tuned to
  // that step — sin(π√2·y′), whose zeros sit at the multiples of 1/√2 — lands every
  // sample on a zero and reads as linear. Defeat it with TWO incommensurate steps,
  // 1/√2 and 1/√3: √2/√3 is irrational, so no single frequency can put BOTH grids on
  // its zeros. A genuinely linear residual stays at second-difference 0 on either.
  const GRIDS = [Math.SQRT1_2, 1 / Math.sqrt(3)]; // ≈0.7071, ≈0.5774 — incommensurate
  const g = (x: number, y: number, dy: number, t: number) =>
    q.order === 2 ? evalRes(x, y, dy, t) : evalRes(x, y, t, 0);
  let checked = 0;
  for (const H of GRIDS) {
    const TS = [-2 * H, -H, 0, H, 2 * H];
    for (const x of xs) {
      for (const y of ys) {
        for (const dy of ds) {
          const rs = TS.map((t) => g(x, y, dy, t));
          if (!rs.every(Number.isFinite)) continue;
          // Tolerance for "second difference ≈ 0" scales with the residual's VARIATION
          // across the samples (max − min), NOT its magnitude: a huge CONSTANT offset
          // (e.g. (y′)² = 10⁹) inflates Σ|rs| and would swallow a genuine curvature,
          // yet the constant cancels out of both the spread and the true second
          // difference. A quadratic's 2·H² curvature dwarfs 10⁻⁶·spread; anything a
          // linear residual leaves is round-off, orders below that.
          const spread = Math.max(...rs) - Math.min(...rs);
          const tol = 1e-6 * (1 + spread);
          // Linear in the top derivative ⇒ EVERY consecutive second difference ≈ 0.
          for (let k = 1; k < rs.length - 1; k++) {
            if (Math.abs(rs[k + 1] - 2 * rs[k] + rs[k - 1]) > tol) return false;
          }
          // Must genuinely constrain the top derivative somewhere (slope A ≠ 0).
          if (Math.abs(rs[3] - rs[2]) > tol) checked++; // g(H) − g(0) ∝ A
        }
      }
    }
  }
  // At the initial state specifically, it must be solvable (A ≠ 0).
  const s0 = solveTop(evalRes, q, q.at, q.y0, q.order === 2 ? (q.dy0 as number) : 0);
  return checked > 0 && Number.isFinite(s0);
}

// --- integrators ------------------------------------------------------------

function axpy(s: number[], k: number[], f: number): number[] {
  const out = new Array(s.length);
  for (let j = 0; j < s.length; j++) out[j] = s[j] + f * k[j];
  return out;
}

/** Classical fixed-step RK4 from xa to xb in n steps, tracking the peak |state|
 * along the whole path (so a straddled pole shows up as an unbounded peak even
 * when the endpoint looks finite). Null on non-finite/blow-up. */
function rk4(
  deriv: Deriv,
  s0: number[],
  xa: number,
  xb: number,
  n: number
): { state: number[]; peak: number } | null {
  const h = (xb - xa) / n;
  let s = s0.slice();
  let x = xa;
  let peak = Math.max(...s.map((v) => Math.abs(v)));
  for (let i = 0; i < n; i++) {
    const k1 = deriv(x, s);
    if (!k1) return null;
    const k2 = deriv(x + h / 2, axpy(s, k1, h / 2));
    if (!k2) return null;
    const k3 = deriv(x + h / 2, axpy(s, k2, h / 2));
    if (!k3) return null;
    const k4 = deriv(x + h, axpy(s, k3, h));
    if (!k4) return null;
    for (let j = 0; j < s.length; j++) {
      s[j] += (h / 6) * (k1[j] + 2 * k2[j] + 2 * k3[j] + k4[j]);
      if (!Number.isFinite(s[j]) || Math.abs(s[j]) > BLOWUP) return null;
      if (Math.abs(s[j]) > peak) peak = Math.abs(s[j]);
    }
    x += h;
  }
  return { state: s, peak };
}

// Dormand–Prince (DP5) Butcher tableau — the 5th-order solution weights (`B5`).
// A DIFFERENT tableau and one order higher than RK4, so agreement between the two
// is a genuine independent check, not a step-size echo.
const DP_C = [0, 1 / 5, 3 / 10, 4 / 5, 8 / 9, 1];
const DP_A: number[][] = [
  [],
  [1 / 5],
  [3 / 40, 9 / 40],
  [44 / 45, -56 / 15, 32 / 9],
  [19372 / 6561, -25360 / 2187, 64448 / 6561, -212 / 729],
  [9017 / 3168, -355 / 33, 46732 / 5247, 49 / 176, -5103 / 18656],
];
const DP_B5 = [35 / 384, 0, 500 / 1113, 125 / 192, -2187 / 6784, 11 / 84];

/** Fixed-step Dormand–Prince, advancing on the 5th-order weights. Null on
 * non-finite/blow-up. Independent of RK4 (different tableau, higher order). */
function dp5(deriv: Deriv, s0: number[], xa: number, xb: number, n: number): number[] | null {
  const h = (xb - xa) / n;
  let s = s0.slice();
  let x = xa;
  for (let i = 0; i < n; i++) {
    const k: number[][] = [];
    for (let stage = 0; stage < 6; stage++) {
      let si = s.slice();
      for (let j = 0; j < stage; j++) si = axpy(si, k[j], h * DP_A[stage][j]);
      const ki = deriv(x + DP_C[stage] * h, si);
      if (!ki) return null;
      k.push(ki);
    }
    for (let j = 0; j < s.length; j++) {
      let inc = 0;
      for (let stage = 0; stage < 6; stage++) inc += DP_B5[stage] * k[stage][j];
      s[j] += h * inc;
      if (!Number.isFinite(s[j]) || Math.abs(s[j]) > BLOWUP) return null;
    }
    x += h;
  }
  return s;
}

// --- display ----------------------------------------------------------------

function trimNumber(v: number): string {
  const r = Math.round(v);
  if (Math.abs(v - r) <= 1e-7 * (1 + Math.abs(v))) return String(r);
  return String(Number(v.toPrecision(6)));
}

function format(
  q: OdePointEvalQuery,
  value: number,
  exact: boolean
): { answer: FinalAnswer; methods: MethodData[] } {
  const rel = exact ? "=" : "\\approx";
  const relPlain = exact ? "=" : "≈";
  const shown = trimNumber(value);
  const tgt = String(q.target);
  const answer: FinalAnswer = {
    latex: `${q.depVar}(${tgt}) ${rel} ${shown}`,
    plain: `${q.depVar}(${tgt}) ${relPlain} ${shown}`,
  };

  const icLatex =
    q.order === 2
      ? `${q.depVar}(${q.at}) = ${q.y0},\\ ${q.depVar}'(${q.at}) = ${q.dy0}`
      : `${q.depVar}(${q.at}) = ${q.y0}`;
  const residualLatex = residualToLatex(q);

  const methods: MethodData[] = [
    {
      id: "ode_ivp_numeric",
      name: "Solve the initial-value problem",
      examPick: true,
      steps: [
        {
          expression: `${residualLatex} = 0`,
          operation: "The differential equation",
          why: `A ${q.order === 2 ? "second" : "first"}-order equation for ${q.depVar}(${q.indepVar}).`,
        },
        {
          expression: icLatex,
          operation: "Initial condition" + (q.order === 2 ? "s" : ""),
          why: `The value${q.order === 2 ? "s" : ""} at ${q.indepVar} = ${q.at} pin down the one particular solution.`,
        },
        {
          expression: answer.latex,
          operation: "Evaluate at the target point",
          why: `Advance the solution from ${q.indepVar} = ${q.at} to ${q.indepVar} = ${tgt} with a high-order Runge–Kutta method, refined until it converges and confirmed by a second, independent integrator.`,
        },
      ],
    },
  ];
  return { answer, methods };
}

/** Render the residual tokens back to readable LaTeX for the first step. */
function residualToLatex(q: OdePointEvalQuery): string {
  const s = q.residual
    .replace(/\bddy\b/g, `(d2${q.depVar})`)
    .replace(/\bdy\b/g, `(d1${q.depVar})`);
  const latex = asciiToLatex(s);
  return latex
    .replace(new RegExp(`\\(d2${q.depVar}\\)`, "g"), `${q.depVar}''`)
    .replace(new RegExp(`\\(d1${q.depVar}\\)`, "g"), `${q.depVar}'`);
}
