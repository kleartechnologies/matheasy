/**
 * The animation-schema layer — a PURE, MATH-FREE translator that sits between the
 * already-verified deterministic solve and the app's "watch math transform"
 * player.
 *
 * The golden rule (spec §1) is enforced STRUCTURALLY here: this module never
 * computes or alters a math value. It only re-describes the transform mathsteps
 * *already* performed — which token moved, which collapsed, which faded in — as a
 * typed `AnimationSchema`. Every `value` it emits is asserted to be a substring of
 * the verified before/after expression (`assertNoInventedTokens`), so the
 * animation can only ever reference numbers the solver produced. No LLM, no
 * mathjs evaluation, no `Date.now()`/randomness: a deterministic function of its
 * input.
 *
 * Input = the raw `mathsteps.MsStep[]` that `mathsteps.solveEquation()` returns
 * (the same array consumed in `solveViaMathsteps`). This module is NOT yet wired
 * into the response payload — build + review first, integrate after.
 */
import { logger } from "firebase-functions/v2";
import * as mathsteps from "mathsteps";

import { asciiToLatex } from "./latex";

// --- public schema types ----------------------------------------------------

/** How a single step should be animated. The changeType→template table is the
 * PRIMARY driver (treated as more reliable than the one-sided changeGroup tags). */
export type AnimationTemplate =
  | "move_across_equals"
  | "divide_both_sides"
  | "combine_terms"
  | "simplify_in_place"
  | "fade_in_new_line";

export type TokenColor = "pink" | "blue" | "green";
export type TokenHighlight = "circle" | "underline" | "box";

/** One token the player should move/highlight, addressed by AST path.
 * `fromPath === null` ⇒ the token is NEW (no old origin); `toPath === null` ⇒ the
 * token is REMOVED (no new destination). A null side is used ONLY where the
 * pairing genuinely can't be determined structurally — never invented. */
export interface TokenMapping {
  /** Token text as it appears in the expression, e.g. "3", "2x". */
  value: string;
  /** AST path in oldEquation, e.g. "L/1" (left side, 2nd arg). null if new. */
  fromPath: string | null;
  /** AST path in newEquation. null if removed. */
  toPath: string | null;
  color: TokenColor;
  highlight: TokenHighlight;
}

/** One animation instruction — exactly one per equation-solving step. */
export interface AnimationInstruction {
  /** Index into the input `steps` array (aligns with the caller's step list). */
  stepIndex: number;
  /** The mathsteps changeType this instruction was derived from. */
  changeType: string;
  /** oldEquation as (best-effort) LaTeX. */
  beforeLatex: string;
  /** newEquation as (best-effort) LaTeX. */
  afterLatex: string;
  animationTemplate: AnimationTemplate;
  tokens: TokenMapping[];
  /** Stable key the narration layer fills in (never the narration text itself). */
  explanationKey: string;
}

export type AnimationSchema = AnimationInstruction[];

/**
 * changeType → template. This is the PRIMARY animation driver and is treated as
 * more reliable than the (frequently one-sided) changeGroup markers. Any
 * changeType absent from this table falls back to `fade_in_new_line` and is
 * logged once, so the table can be extended.
 *
 * mathsteps really does spell it `SIMPLIFY_ARITHMETIC` (missing the 2nd "C") —
 * matched verbatim, not corrected.
 */
export const TEMPLATE_BY_CHANGE_TYPE: Readonly<Record<string, AnimationTemplate>> = {
  // A term crosses the equals sign (`+c` on the left becomes `-c` on the right).
  SUBTRACT_FROM_BOTH_SIDES: "move_across_equals",
  ADD_TO_BOTH_SIDES: "move_across_equals",
  // The same divisor/multiplier is applied to both sides (the `divide_both_sides`
  // template is the whole multiplicative-both-sides family — mathsteps names the
  // multiply variants inconsistently, so all real spellings are listed).
  DIVIDE_FROM_BOTH_SIDES: "divide_both_sides",
  MULTIPLY_TO_BOTH_SIDES: "divide_both_sides",
  MULTIPLY_BOTH_SIDES_BY_INVERSE_FRACTION: "divide_both_sides",
  MULTIPLY_BOTH_SIDES_BY_NEGATIVE_ONE: "divide_both_sides",
  // A sub-expression is evaluated/reduced in place.
  SIMPLIFY_ARITHMETIC: "simplify_in_place",
  SIMPLIFY_LEFT_SIDE: "simplify_in_place",
  SIMPLIFY_RIGHT_SIDE: "simplify_in_place",
  SIMPLIFY_FRACTION: "simplify_in_place",
  // Multiple like terms merge into one. ADD_POLYNOMIAL_TERMS is the simplest such
  // step (`2x + 3x` → `5x`); it tags the old `+` sum and the new combined term the
  // same way COLLECT does, so resolveCombine's term-diff handles both.
  COLLECT_AND_COMBINE_LIKE_TERMS: "combine_terms",
  ADD_POLYNOMIAL_TERMS: "combine_terms",
};

const DEFAULT_TEMPLATE: AnimationTemplate = "fade_in_new_line";

/** Deterministic styling per template (the colour/highlight the player uses). */
const STYLE_BY_TEMPLATE: Readonly<
  Record<AnimationTemplate, { color: TokenColor; highlight: TokenHighlight }>
> = {
  move_across_equals: { color: "pink", highlight: "circle" },
  divide_both_sides: { color: "blue", highlight: "box" },
  combine_terms: { color: "green", highlight: "underline" },
  simplify_in_place: { color: "blue", highlight: "box" },
  fade_in_new_line: { color: "blue", highlight: "box" },
};

// --- mathsteps runtime node shape -------------------------------------------
//
// The ambient `mathsteps` decl (src/types/mathsteps.d.ts) only exposes `.ascii()`
// + `comparator`, but at runtime each equation also carries `leftNode`/`rightNode`
// — nodes from mathsteps' bundled (old) mathjs. We only ever READ these; the cast
// is localized to `sidesOf` so nothing else in the module touches an untyped node.

/** A read-only view of a mathsteps (old-mathjs) AST node. */
export interface MsMathNode {
  type?: string;
  op?: string;
  fn?: string;
  value?: string | number;
  name?: string;
  args?: MsMathNode[];
  /** The transformation tag mathsteps attaches to participating tokens. */
  changeGroup?: number;
  toString(): string;
}

interface MsEquationNodes {
  leftNode?: MsMathNode;
  rightNode?: MsMathNode;
}

/** A node found to carry a `.changeGroup`, with its value + AST path. */
export interface ChangeGroupHit {
  changeGroup: number;
  /** The node's whitespace-stripped text, e.g. "3", "2x". */
  value: string;
  /** Stable AST path, e.g. "L/1". */
  path: string;
  node: MsMathNode;
}

/** The two sides of an equation as runtime AST nodes (localized cast). */
function sidesOf(eq: mathsteps.MsEquation): { L?: MsMathNode; R?: MsMathNode } {
  const e = eq as unknown as MsEquationNodes;
  return { L: e.leftNode, R: e.rightNode };
}

// --- AST path helper + changeGroup collection -------------------------------

/**
 * Canonical form used BOTH for token text and for the firewall's substring check,
 * so the two can never disagree. Drops whitespace and `*` (implicit vs explicit
 * multiplication compare equal: "2 x", "2*x" → "2x") AND collapses sign pairs, so
 * mathjs's `.toString()` (which renders an internal negative as "a + -b") and its
 * `.ascii()` (which renders the same as "a - b") reduce to the identical string.
 * Without this the firewall would throw on a faithfully-copied value (a false
 * positive that aborts the whole schema) — see the `3x - 1 = 2x + 5` case.
 */
function canonicalizeExpr(raw: string): string {
  let s = raw.replace(/\s+/g, "").replace(/\*/g, "");
  let prev: string;
  do {
    prev = s;
    s = s
      .replace(/\+-/g, "-")
      .replace(/-\+/g, "-")
      .replace(/--/g, "+")
      .replace(/\+\+/g, "+");
  } while (s !== prev);
  return s;
}

/** A node's canonical text, e.g. "3", "2x", "-x-5". */
function nodeText(node: MsMathNode | undefined): string {
  return node ? canonicalizeExpr(String(node.toString())) : "";
}

function isConstant(node: MsMathNode): boolean {
  return node.type === "ConstantNode";
}

/** Depth-first walk producing a stable path per node: the side prefix ("L"/"R"),
 * then "/index" per `.args` descent (e.g. "L/1" = left side, 2nd arg). */
function walk(
  node: MsMathNode | undefined,
  path: string,
  visit: (n: MsMathNode, p: string) => void
): void {
  if (!node) return;
  visit(node, path);
  if (node.args) {
    node.args.forEach((arg, i) => walk(arg, `${path}/${i}`, visit));
  }
}

/** Every node under `node` carrying a `.changeGroup`, with its value + path.
 * `sidePrefix` is "L" or "R" — the equation side this subtree belongs to. */
export function collectChangeGroups(
  node: MsMathNode | undefined,
  sidePrefix: string
): ChangeGroupHit[] {
  const hits: ChangeGroupHit[] = [];
  walk(node, sidePrefix, (n, path) => {
    if (typeof n.changeGroup === "number") {
      hits.push({ changeGroup: n.changeGroup, value: nodeText(n), path, node: n });
    }
  });
  return hits;
}

/** All changeGroup hits across both sides of an equation. */
function equationChangeGroups(eq: mathsteps.MsEquation): ChangeGroupHit[] {
  const { L, R } = sidesOf(eq);
  return [...collectChangeGroups(L, "L"), ...collectChangeGroups(R, "R")];
}

/** The set of changeGroup numbers present in the given hit lists, ascending —
 * so pairing across old/new is order-independent and deterministic. */
function groupNumbers(...lists: ChangeGroupHit[][]): number[] {
  const set = new Set<number>();
  for (const list of lists) for (const h of list) set.add(h.changeGroup);
  return [...set].sort((a, b) => a - b);
}

/** Flatten a `+`/`-` sum into its top-level additive terms, each with its path.
 * A `-` treats its right operand as a (subtracted) term but does NOT re-sign the
 * value — we only ever compare structure, never compute. Non-sum nodes are a
 * single term. */
function sumTerms(node: MsMathNode, path: string): { node: MsMathNode; path: string }[] {
  if (node.op === "+" && node.args) {
    return node.args.flatMap((a, i) => sumTerms(a, `${path}/${i}`));
  }
  if (node.op === "-" && node.args && node.args.length === 2) {
    return [
      ...sumTerms(node.args[0], `${path}/0`),
      { node: node.args[1], path: `${path}/1` },
    ];
  }
  return [{ node, path }];
}

// --- Gap-1 resolvers (deterministic old↔new pairing) ------------------------
//
// changeGroup markers are frequently one-sided. Each resolver reconstructs the
// missing endpoint using ONLY the known semantics of its changeType family +
// structural matching (value equality, term membership). Where a pairing can't
// be determined structurally, the unknown side is left null and we fall back to
// highlighting the whole changed side — never a guessed mapping.

type Style = { color: TokenColor; highlight: TokenHighlight };

/** Which side changed (by text), as a whole-side highlight fallback. Prefers the
 * left when both differ (real solve steps only ever change one side). */
function wholeChangedSide(
  oldEq: mathsteps.MsEquation,
  newEq: mathsteps.MsEquation,
  style: Style
): TokenMapping {
  const o = sidesOf(oldEq);
  const n = sidesOf(newEq);
  const leftChanged = nodeText(o.L) !== nodeText(n.L);
  const side = leftChanged ? "L" : "R";
  const newSide = leftChanged ? n.L : n.R;
  return { value: nodeText(newSide), fromPath: side, toPath: side, ...style };
}

/** SIMPLIFY_* — the same changeGroup tags the changed sub-expr on BOTH sides, so
 * pair old↔new by group number (old sub-expr → new value). */
function resolveSimplify(
  oldEq: mathsteps.MsEquation,
  newEq: mathsteps.MsEquation,
  style: Style
): TokenMapping[] {
  const oldHits = equationChangeGroups(oldEq);
  const newHits = equationChangeGroups(newEq);
  const tokens: TokenMapping[] = [];
  for (const g of groupNumbers(oldHits, newHits)) {
    const oh = oldHits.find((h) => h.changeGroup === g);
    const nh = newHits.find((h) => h.changeGroup === g);
    if (oh && nh) {
      tokens.push({ value: nh.value, fromPath: oh.path, toPath: nh.path, ...style });
    } else if (oh) {
      tokens.push({ value: oh.value, fromPath: oh.path, toPath: null, ...style });
    } else if (nh) {
      tokens.push({ value: nh.value, fromPath: null, toPath: nh.path, ...style });
    }
  }
  // No markers at all (e.g. an untagged SIMPLIFY_LEFT_SIDE) → whole-side highlight.
  return tokens.length ? tokens : [wholeChangedSide(oldEq, newEq, style)];
}

/** Find a TOP-LEVEL additive constant on `side` whose |value| matches — the
 * constant that crossed the equals sign. Nested constants (e.g. a coefficient)
 * are deliberately not matched. */
function findAdditiveConstant(
  side: MsMathNode | undefined,
  prefix: string,
  targetAbs: number
): { path: string } | null {
  if (!side) return null;
  for (const t of sumTerms(side, prefix)) {
    if (isConstant(t.node) && Math.abs(Number(t.node.value)) === targetAbs) {
      return { path: t.path };
    }
  }
  return null;
}

/** SUBTRACT/ADD_FROM_BOTH_SIDES — the changeGroup tags the introduced `±c` on the
 * NEW sides only. Origin = the matching top-level constant on the OLD left;
 * destination = the tagged term on the NEW right (it "moved across"). */
function resolveMoveAcross(
  oldEq: mathsteps.MsEquation,
  newEq: mathsteps.MsEquation,
  style: Style
): TokenMapping[] {
  const newHits = equationChangeGroups(newEq);
  const { L: oldL } = sidesOf(oldEq);
  const tokens: TokenMapping[] = [];
  for (const g of groupNumbers(newHits)) {
    const hits = newHits.filter((h) => h.changeGroup === g);
    const dest = hits.find((h) => h.path.startsWith("R")) ?? hits[0];
    const origin = findAdditiveConstant(oldL, "L", Math.abs(Number(dest.node.value)));
    tokens.push({
      value: dest.value,
      fromPath: origin ? origin.path : null,
      toPath: dest.path,
      ...style,
    });
  }
  return tokens.length ? tokens : [wholeChangedSide(oldEq, newEq, style)];
}

/** Find where `value` originates on `side` — the factor that becomes the
 * divisor/multiplier. Matches either a leading coefficient (`value·x`, e.g. the
 * `2` in `2x` for a divide) or a denominator (`x/value`, e.g. the `3` in `x/3`
 * for a multiply). Returns that constant's path, or null if it isn't structurally
 * a coefficient/denominator (e.g. a fraction multiplier), in which case the
 * caller leaves the origin unknown rather than guessing. */
function findCoefficient(
  side: MsMathNode | undefined,
  prefix: string,
  value: number
): { path: string } | null {
  if (Number.isNaN(value)) return null; // an operator-node multiplier has no scalar
  let found: { path: string } | null = null;
  walk(side, prefix, (n, path) => {
    if (found) return;
    // Leading coefficient: value · x
    if (
      n.op === "*" &&
      n.args &&
      n.args.length >= 2 &&
      isConstant(n.args[0]) &&
      Number(n.args[0].value) === value
    ) {
      found = { path: `${path}/0` };
    }
    // Denominator: x / value
    if (
      n.op === "/" &&
      n.args &&
      n.args.length === 2 &&
      isConstant(n.args[1]) &&
      Number(n.args[1].value) === value
    ) {
      found = { path: `${path}/1` };
    }
  });
  return found;
}

/** DIVIDE_FROM_BOTH_SIDES / MULTIPLY_TO_BOTH_SIDES (+ the BY_INVERSE_FRACTION /
 * BY_NEGATIVE_ONE multiply variants) — the changeGroup tags the divisor/multiplier
 * on BOTH new sides. Pair the left occurrence back to the OLD coefficient/denominator
 * it came from; emit the right occurrence as a new (highlight-only) token so the
 * player shows the operation landing on both sides. A fraction multiplier (an
 * operator node, no scalar value) leaves the origin null rather than guessing. */
function resolveDivide(
  oldEq: mathsteps.MsEquation,
  newEq: mathsteps.MsEquation,
  style: Style
): TokenMapping[] {
  const newHits = equationChangeGroups(newEq);
  const { L: oldL } = sidesOf(oldEq);
  const tokens: TokenMapping[] = [];
  for (const g of groupNumbers(newHits)) {
    const hits = newHits.filter((h) => h.changeGroup === g);
    const leftDivisor = hits.find((h) => h.path.startsWith("L")) ?? hits[0];
    const rightDivisor = hits.find((h) => h.path.startsWith("R"));
    const origin = findCoefficient(oldL, "L", Number(leftDivisor.node.value));
    tokens.push({
      value: leftDivisor.value,
      fromPath: origin ? origin.path : null,
      toPath: leftDivisor.path,
      ...style,
    });
    if (rightDivisor) {
      tokens.push({
        value: rightDivisor.value,
        fromPath: null,
        toPath: rightDivisor.path,
        ...style,
      });
    }
  }
  return tokens.length ? tokens : [wholeChangedSide(oldEq, newEq, style)];
}

/** COLLECT_AND_COMBINE_LIKE_TERMS — the changeGroup tags the whole sum container
 * on both sides. Multiset-diff the top-level terms: terms in old-but-not-new
 * collapsed INTO the single term in new-but-not-old. Map each collapsed term to
 * the combined one. If the diff isn't a clean many→one, fall back to a whole-side
 * highlight rather than guess. */
function resolveCombine(
  oldEq: mathsteps.MsEquation,
  newEq: mathsteps.MsEquation,
  style: Style
): TokenMapping[] {
  const oldHits = equationChangeGroups(oldEq);
  const newHits = equationChangeGroups(newEq);
  for (const g of groupNumbers(oldHits, newHits)) {
    const oh = oldHits.find((h) => h.changeGroup === g);
    const nh = newHits.find((h) => h.changeGroup === g);
    if (!oh?.node.args || !nh?.node.args) continue;
    const oldTerms = sumTerms(oh.node, oh.path);
    const newTerms = sumTerms(nh.node, nh.path);
    const newTextSet = new Set(newTerms.map((t) => nodeText(t.node)));
    const oldTextSet = new Set(oldTerms.map((t) => nodeText(t.node)));
    const collapsed = oldTerms.filter((t) => !newTextSet.has(nodeText(t.node)));
    const combined = newTerms.filter((t) => !oldTextSet.has(nodeText(t.node)));
    if (combined.length === 1 && collapsed.length >= 1) {
      const target = combined[0];
      return collapsed.map((t) => ({
        value: nodeText(t.node),
        fromPath: t.path,
        toPath: target.path,
        ...style,
      }));
    }
  }
  return [wholeChangedSide(oldEq, newEq, style)];
}

/** Dispatch to the resolver for `template`. */
function resolveTokens(
  template: AnimationTemplate,
  oldEq: mathsteps.MsEquation,
  newEq: mathsteps.MsEquation
): TokenMapping[] {
  const style = STYLE_BY_TEMPLATE[template];
  switch (template) {
    case "move_across_equals":
      return resolveMoveAcross(oldEq, newEq, style);
    case "divide_both_sides":
      return resolveDivide(oldEq, newEq, style);
    case "combine_terms":
      return resolveCombine(oldEq, newEq, style);
    case "simplify_in_place":
      return resolveSimplify(oldEq, newEq, style);
    case "fade_in_new_line":
      // The whole new line fades in — no token-level movement to describe.
      return [];
  }
}

// --- golden-rule firewall ---------------------------------------------------

/** Canonical form for substring containment against `.ascii()` — the SAME
 * canonicalization the token values went through (via `nodeText`), so a faithful
 * value can never fail to match on a mere sign-notation difference. */
function normalizeExpr(s: string): string {
  return canonicalizeExpr(s);
}

/**
 * THE FIREWALL. Asserts every token value the animation references is a substring
 * of the verified before/after expression — the animation layer may only surface
 * numbers/expressions the deterministic solver already produced. A violation is a
 * BUG in a resolver (it fabricated a value), so we throw rather than ship a
 * confident-but-invented animation.
 */
export function assertNoInventedTokens(
  instruction: AnimationInstruction,
  oldEq: mathsteps.MsEquation,
  newEq: mathsteps.MsEquation
): void {
  // Check each side independently — never a concatenation — so a token can't
  // "pass" by matching a substring that straddles the old|new seam.
  const before = normalizeExpr(oldEq.ascii());
  const after = normalizeExpr(newEq.ascii());
  for (const token of instruction.tokens) {
    const needle = normalizeExpr(token.value);
    if (needle.length === 0) continue;
    if (!before.includes(needle) && !after.includes(needle)) {
      throw new Error(
        `animationSchema firewall: token "${token.value}" at step ` +
          `${instruction.stepIndex} (${instruction.changeType}) is absent from the ` +
          `verified before/after expression — the animation layer may only ` +
          `reference values the deterministic solver produced (golden rule §1).`
      );
    }
  }
}

// --- public entry point -----------------------------------------------------

/**
 * Build the animation schema from mathsteps' equation-solving steps. One
 * instruction per step that carries both an old and new equation. Pure and
 * side-effect-free apart from a single diagnostic `logger.warn` listing any
 * changeType not yet in `TEMPLATE_BY_CHANGE_TYPE` (so the table can be extended).
 *
 * Throws only if a resolver ever fabricates a token value (the firewall) — which
 * indicates a bug, never bad user input.
 */
export function buildAnimationSchema(steps: mathsteps.MsStep[]): AnimationSchema {
  const schema: AnimationSchema = [];
  const unmapped = new Set<string>();

  steps.forEach((step, i) => {
    const oldEq = step.oldEquation;
    const newEq = step.newEquation;
    if (!oldEq || !newEq) return; // not an equation-solving step (defensive)

    const mapped = TEMPLATE_BY_CHANGE_TYPE[step.changeType];
    if (!mapped) unmapped.add(step.changeType);
    const template = mapped ?? DEFAULT_TEMPLATE;

    const instruction: AnimationInstruction = {
      stepIndex: i,
      changeType: step.changeType,
      beforeLatex: asciiToLatex(oldEq.ascii()),
      afterLatex: asciiToLatex(newEq.ascii()),
      animationTemplate: template,
      tokens: resolveTokens(template, oldEq, newEq),
      explanationKey: `anim.step.${step.changeType}`,
    };

    assertNoInventedTokens(instruction, oldEq, newEq);
    schema.push(instruction);
  });

  if (unmapped.size > 0) {
    logger.warn("buildAnimationSchema.unmappedChangeTypes", {
      types: [...unmapped].sort(),
    });
  }

  return schema;
}
