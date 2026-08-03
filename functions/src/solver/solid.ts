/**
 * Solid-geometry word problems: the "show that …" derivation and the calculus
 * optimisation that follows it.
 *
 * This is the exam question that arrives as a photograph of a textbook page:
 *
 *   "A drinking glass, in the shape of a cylinder, must hold 200 mℓ of liquid
 *    when full.
 *    10.1  Show that the height of the glass, h, can be expressed as h = 200/πr².
 *    10.2  Show that the total surface area is A = πr² + 400/r.
 *    10.3  Determine the value of r for which A is a minimum."
 *
 * Before this engine, 10.1 reached `classify` as prose containing two variables
 * and no solvable single-unknown equation, so it fell through to the
 * `system_of_equations` tutor route — and the client, reading that type, told the
 * student "this system of equations may have several solutions". Every word of
 * that was false: there is no system, and the answer is printed in the question.
 *
 * ── Why this is golden-rule clean (spec §1) ────────────────────────────────
 *
 * A "show that" question is the one case where the answer is NOT ours to invent:
 * the textbook states it. So the engine never derives-and-trusts. It takes the
 * claimed expression, SUBSTITUTES IT BACK into the constraint the problem states,
 * and requires the constraint to hold IDENTICALLY — at many sample points across
 * a wide range of the remaining variable, not at one lucky point. If
 * `πr²·(200/πr²) = 200` for every r we try, the claim is proven; if the OCR
 * misread a digit, or the textbook line was mis-transcribed, the identity breaks
 * at the first sample and the engine declines. The derivation shown as working is
 * built separately by isolating the target, and is itself re-checked against the
 * claim before it ships.
 *
 * The optimisation path has no printed answer to lean on, so it is held to a
 * stricter standard: the objective must be a genuine single-variable function,
 * its critical point must satisfy f'(x) = 0 to tolerance, the second-derivative
 * test must confirm the sense that was ASKED for, and the extremum must survive a
 * dense sweep of the domain (a local minimum that some other point beats is not
 * the minimum, and shipping it would be a confident wrong answer).
 *
 * ── Deliberate limits (each DECLINES rather than guesses) ──────────────────
 *
 *  - Two different solids named in one problem (a cone on a cylinder) — the
 *    composite formulas are not these, and picking one would answer the wrong
 *    question.
 *  - A surface-area constraint on a shape whose openness the text never states.
 *    An open-topped can and a sealed one have different areas; "which one" is not
 *    inferable from "a container", so it is not inferred.
 *  - A claimed expression that still mentions the variable it defines
 *    (`h = h + 1`), or that mentions a symbol the shape has no dimension for.
 *  - Any ask that is not a single show-that or a single optimisation.
 */
import { derivative, parse, rationalize, simplify } from "mathjs";

import { asciiToLatex, cleanLatex, latexToAscii, variablesIn } from "./latex";
import { findAskClause } from "./nl/ask";
import {
  hasAmbiguousNumberGrouping,
  maskReferenceLabels,
  normalizeNumericGlyphs,
} from "./nl/numeric";
import { FinalAnswer, MethodData, StepData } from "./types";
import { evalReal } from "./verify";

// ---------------------------------------------------------------------------
// The shape catalogue
// ---------------------------------------------------------------------------

export type SolidShape =
  | "cylinder"
  | "cone"
  | "sphere"
  | "hemisphere"
  | "cube"
  | "cuboid"
  | "square_prism"
  | "square_pyramid";

/** The named dimensions a shape can have. The SYMBOL for each is read from the
 * problem — a textbook is as likely to write `x` for a side as `s`. */
export type SolidRole = "radius" | "height" | "side" | "length" | "width";

/** Which quantity a constraint fixes, or an objective optimises. */
export type SolidQuantity =
  | "volume"
  | "total_surface_area"
  | "curved_surface_area";

/** Formulas for one shape, as ascii-math templates over role symbols. */
interface ShapeDef {
  /** The dimensions this shape is described by. */
  roles: SolidRole[];
  /** Volume, in terms of the role symbols. */
  volume: (s: Sym) => string;
  /** Total (closed) surface area — every face. */
  totalSurface: ((s: Sym) => string) | null;
  /** Curved / lateral surface only — no ends. */
  curvedSurface: ((s: Sym) => string) | null;
  /** Surface with ONE end open (a can with no lid, a glass). */
  openSurface: ((s: Sym) => string) | null;
  /** LaTeX for the same formulas, for the working. */
  latex: (s: Sym) => Partial<Record<SolidQuantity | "open_surface_area", string>>;
}

/** Role → the symbol this problem uses for it. */
type Sym = Partial<Record<SolidRole, string>>;

const r = (s: Sym): string => s.radius ?? "r";
const h = (s: Sym): string => s.height ?? "h";
const a = (s: Sym): string => s.side ?? "s";
const l = (s: Sym): string => s.length ?? "l";
const w = (s: Sym): string => s.width ?? "w";

const SHAPES: Record<SolidShape, ShapeDef> = {
  cylinder: {
    roles: ["radius", "height"],
    volume: (s) => `pi*${r(s)}^2*${h(s)}`,
    totalSurface: (s) => `2*pi*${r(s)}^2 + 2*pi*${r(s)}*${h(s)}`,
    curvedSurface: (s) => `2*pi*${r(s)}*${h(s)}`,
    openSurface: (s) => `pi*${r(s)}^2 + 2*pi*${r(s)}*${h(s)}`,
    latex: (s) => ({
      volume: `V = \\pi ${r(s)}^2 ${h(s)}`,
      total_surface_area: `A = 2\\pi ${r(s)}^2 + 2\\pi ${r(s)} ${h(s)}`,
      curved_surface_area: `A = 2\\pi ${r(s)} ${h(s)}`,
      open_surface_area: `A = \\pi ${r(s)}^2 + 2\\pi ${r(s)} ${h(s)}`,
    }),
  },
  cone: {
    roles: ["radius", "height"],
    volume: (s) => `(1/3)*pi*${r(s)}^2*${h(s)}`,
    totalSurface: (s) =>
      `pi*${r(s)}^2 + pi*${r(s)}*sqrt(${r(s)}^2 + ${h(s)}^2)`,
    curvedSurface: (s) => `pi*${r(s)}*sqrt(${r(s)}^2 + ${h(s)}^2)`,
    openSurface: null,
    latex: (s) => ({
      volume: `V = \\tfrac{1}{3}\\pi ${r(s)}^2 ${h(s)}`,
      total_surface_area: `A = \\pi ${r(s)}^2 + \\pi ${r(s)}\\sqrt{${r(s)}^2 + ${h(s)}^2}`,
      curved_surface_area: `A = \\pi ${r(s)}\\sqrt{${r(s)}^2 + ${h(s)}^2}`,
    }),
  },
  sphere: {
    roles: ["radius"],
    volume: (s) => `(4/3)*pi*${r(s)}^3`,
    totalSurface: (s) => `4*pi*${r(s)}^2`,
    curvedSurface: (s) => `4*pi*${r(s)}^2`,
    openSurface: null,
    latex: (s) => ({
      volume: `V = \\tfrac{4}{3}\\pi ${r(s)}^3`,
      total_surface_area: `A = 4\\pi ${r(s)}^2`,
      curved_surface_area: `A = 4\\pi ${r(s)}^2`,
    }),
  },
  hemisphere: {
    roles: ["radius"],
    volume: (s) => `(2/3)*pi*${r(s)}^3`,
    totalSurface: (s) => `3*pi*${r(s)}^2`,
    curvedSurface: (s) => `2*pi*${r(s)}^2`,
    openSurface: (s) => `2*pi*${r(s)}^2`,
    latex: (s) => ({
      volume: `V = \\tfrac{2}{3}\\pi ${r(s)}^3`,
      total_surface_area: `A = 3\\pi ${r(s)}^2`,
      curved_surface_area: `A = 2\\pi ${r(s)}^2`,
      open_surface_area: `A = 2\\pi ${r(s)}^2`,
    }),
  },
  cube: {
    roles: ["side"],
    volume: (s) => `${a(s)}^3`,
    totalSurface: (s) => `6*${a(s)}^2`,
    curvedSurface: null,
    openSurface: (s) => `5*${a(s)}^2`,
    latex: (s) => ({
      volume: `V = ${a(s)}^3`,
      total_surface_area: `A = 6${a(s)}^2`,
      open_surface_area: `A = 5${a(s)}^2`,
    }),
  },
  cuboid: {
    roles: ["length", "width", "height"],
    volume: (s) => `${l(s)}*${w(s)}*${h(s)}`,
    totalSurface: (s) =>
      `2*(${l(s)}*${w(s)} + ${l(s)}*${h(s)} + ${w(s)}*${h(s)})`,
    curvedSurface: null,
    openSurface: (s) =>
      `${l(s)}*${w(s)} + 2*${l(s)}*${h(s)} + 2*${w(s)}*${h(s)}`,
    latex: (s) => ({
      volume: `V = ${l(s)}${w(s)}${h(s)}`,
      total_surface_area: `A = 2(${l(s)}${w(s)} + ${l(s)}${h(s)} + ${w(s)}${h(s)})`,
      open_surface_area: `A = ${l(s)}${w(s)} + 2${l(s)}${h(s)} + 2${w(s)}${h(s)}`,
    }),
  },
  square_prism: {
    roles: ["side", "height"],
    volume: (s) => `${a(s)}^2*${h(s)}`,
    totalSurface: (s) => `2*${a(s)}^2 + 4*${a(s)}*${h(s)}`,
    curvedSurface: (s) => `4*${a(s)}*${h(s)}`,
    openSurface: (s) => `${a(s)}^2 + 4*${a(s)}*${h(s)}`,
    latex: (s) => ({
      volume: `V = ${a(s)}^2 ${h(s)}`,
      total_surface_area: `A = 2${a(s)}^2 + 4${a(s)}${h(s)}`,
      curved_surface_area: `A = 4${a(s)}${h(s)}`,
      open_surface_area: `A = ${a(s)}^2 + 4${a(s)}${h(s)}`,
    }),
  },
  square_pyramid: {
    roles: ["side", "height"],
    volume: (s) => `(1/3)*${a(s)}^2*${h(s)}`,
    totalSurface: null,
    curvedSurface: null,
    openSurface: null,
    latex: (s) => ({ volume: `V = \\tfrac{1}{3}${a(s)}^2 ${h(s)}` }),
  },
};

/** The nouns that name each solid. A shape is only recognised by its own name —
 * "container", "tank", "box" without a shape word is not enough to pick formulas. */
const SHAPE_NOUNS: Record<SolidShape, RegExp> = {
  cylinder: /\bcylind(?:er|rical)\b/i,
  cone: /\bcon(?:e|ical)\b/i,
  hemisphere: /\bhemispher(?:e|ical)\b/i,
  sphere: /\bspher(?:e|ical)\b|\bball\b/i,
  cube: /\bcub(?:e|ic|oidal)?\b/i,
  cuboid: /\bcuboid\b|\brectangular\s+(?:box|prism|block|tank|container)\b/i,
  square_prism: /\bsquare[-\s]?based?\s+(?:prism|box|tank|container)\b/i,
  square_pyramid: /\bsquare[-\s]?based?\s+pyramid\b/i,
};

// ---------------------------------------------------------------------------
// The parsed problem
// ---------------------------------------------------------------------------

/** A constraint the problem fixes: "must hold 200 mℓ" → volume = 200. */
export interface SolidConstraint {
  quantity: SolidQuantity;
  value: number;
  /** The unit as written, for the working ("mℓ", "cm^3"); null when bare. */
  unit: string | null;
}

export type SolidTask =
  | {
      kind: "show_that";
      /** The symbol the claim defines, e.g. "h". */
      target: string;
      /** The claimed expression, as written (LaTeX) and as ascii for mathjs. */
      claimedLatex: string;
      claimedAscii: string;
      /** Which quantity the claim is FOR — a dimension, or a named area/volume. */
      claimOf: "dimension" | SolidQuantity;
    }
  | {
      kind: "optimize";
      sense: "min" | "max";
      /** The variable to optimise over. */
      variable: string;
      /** The objective as ascii, already in ONE variable. */
      objectiveAscii: string;
      /** How it reads in the problem, for the working. */
      objectiveLatex: string;
      /** The name the problem gives it ("A", "the surface area"). */
      objectiveName: string;
    };

export interface SolidSpec {
  shape: SolidShape | null;
  symbols: Sym;
  constraint: SolidConstraint | null;
  /**
   * Is the solid open at one end? `null` means the text never says — and that is
   * load-bearing, not a shrug: an open glass and a sealed can have different
   * surface areas, so a surface-area result is only produced when this is known.
   */
  open: boolean | null;
  task: SolidTask;
}

// ---------------------------------------------------------------------------
// Reading the problem
// ---------------------------------------------------------------------------

/**
 * Flatten the LaTeX to prose while KEEPING the mathematics as LaTeX.
 *
 * The circle engine's flatten strips every macro, which is right when only words
 * and plain numbers matter. Here the claimed expression IS the answer, so `\frac`
 * and `\pi` have to survive — a flatten that turned `\frac{200}{\pi r^2}` into
 * "200 r 2" would leave nothing to verify against.
 */
function flattenKeepingMath(rawLatex: string): string {
  return normalizeNumericGlyphs(rawLatex)
    .replace(/\\text(?:rm|it|bf|sf)?\s*\{([^{}]*)\}/g, " $1 ")
    .replace(/\\mathrm\s*\{([^{}]*)\}/g, " $1 ")
    .replace(/\\(?:quad|qquad|,|;|:|!|\s)/g, " ")
    .replace(/\$/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Prose only — macros stripped — for the word-level readers (shape, cues). */
function proseOnly(mixed: string): string {
  return maskReferenceLabels(
    mixed
      .replace(/\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/g, " $1/$2 ")
      .replace(/\\pi\b/gi, " π ")
      // `\ell` carries the UNIT in "200 m\ell" — deleting it with the other
      // macros would leave "200 m", a length, and the volume constraint would be
      // lost. It has to become a letter before the macro sweep, not after.
      .replace(/\\ell\b/g, "ℓ")
      .replace(/\\[a-zA-Z]+/g, " ")
      .replace(/[{}]/g, " ")
      .replace(/\s+/g, " ")
      .trim()
  );
}

/**
 * Split into clauses at sentence ends and LaTeX row breaks.
 *
 * Without this, an expression capture that runs to end-of-string swallows the
 * sentence AFTER the one it wanted — "A = 2πr² + 400/r. Determine the value of r"
 * captures the question as part of the function. A decimal point is safe: the
 * split needs whitespace after the period, and `3.5` has none.
 */
function segments(mixed: string): string[] {
  return mixed
    .split(/\\\\|(?<=[.;])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

/** Which solid the problem is about, or null when none / more than one. */
function readShape(prose: string): SolidShape | null {
  const found: SolidShape[] = [];
  for (const [shape, re] of Object.entries(SHAPE_NOUNS) as [SolidShape, RegExp][]) {
    if (re.test(prose)) found.push(shape);
  }
  if (found.length === 0) return null;
  // "cube" is a substring-ish of "cuboid" and "square-based prism" also matches
  // the generic prism noun, so a text naming the MORE specific shape matches two
  // patterns. Prefer the specific one; only genuinely different solids decline.
  const narrow = (a: SolidShape, b: SolidShape): boolean =>
    (a === "cuboid" && b === "cube") ||
    (a === "hemisphere" && b === "sphere") ||
    (a === "square_pyramid" && b === "square_prism");
  const kept = found.filter((f) => !found.some((g) => g !== f && narrow(g, f)));
  return kept.length === 1 ? kept[0] : null;
}

/** The symbol a role is written with, read from an explicit declaration. */
const ROLE_WORD: Record<SolidRole, RegExp> = {
  radius: /radius/i,
  height: /height|depth|tall/i,
  side: /side|edge|base/i,
  length: /length/i,
  width: /width|breadth/i,
};

/**
 * Read "with height h and radius r", "the height of the glass, h", "radius = r".
 *
 * Only a SINGLE-LETTER symbol counts, and only when it sits adjacent to the role
 * word — a length quoted as a NUMBER ("height 12 cm") declares no symbol, and a
 * letter two clauses away belongs to something else.
 */
function readSymbols(mixed: string): Sym {
  const out: Sym = {};
  for (const [role, word] of Object.entries(ROLE_WORD) as [SolidRole, RegExp][]) {
    const source = word.source;
    const patterns = [
      // "height h", "height, h,", "height of h"
      new RegExp(String.raw`\b(?:${source})\b\s*,?\s*(?:of\s+|=\s*)?([a-zA-Z])\b(?![a-zA-Z(])`, "i"),
      // "the height of the glass, h," — a role, its owner, then the symbol
      new RegExp(
        String.raw`\b(?:${source})\b\s+of\s+(?:the\s+|a\s+|an\s+|its\s+)?\w+\s*,\s*([a-zA-Z])\b(?![a-zA-Z(])`,
        "i"
      ),
      // "h is the height", "h, the radius,"
      new RegExp(String.raw`\b([a-zA-Z])\b\s*(?:is|,)\s*(?:the\s+)?(?:${source})\b`, "i"),
    ];
    for (const re of patterns) {
      const m = re.exec(mixed);
      // A bare article/preposition letter ("a", "I") is a word, not a symbol.
      if (m && !/^[aAI]$/.test(m[1])) {
        out[role] = m[1];
        break;
      }
    }
  }
  return out;
}

/** Words that fix a VOLUME, and the ones that fix a SURFACE AREA. */
const VOLUME_CUE =
  /\b(?:volume|capacity|holds?|hold|contains?|contain|filled\s+with)\b/i;
const AREA_CUE = /\b(?:surface\s+area|area\s+of\s+(?:the\s+)?(?:metal|material|card|cardboard|sheet))\b/i;
const CURVED_CUE = /\b(?:curved|lateral)\s+surface\b/i;
const OPEN_CUE =
  /\bopen(?:\s+(?:at\s+the\s+)?top|[-\s]topped|\s+box|\s+container|\s+tank|\s+cylinder)?\b|\bwithout\s+(?:a\s+)?(?:lid|top|cover)\b|\bno\s+(?:lid|top|cover)\b/i;
const CLOSED_CUE = /\bclosed\b|\bsealed\b|\bwith\s+(?:a\s+)?(?:lid|top|cover)\b/i;

/**
 * A number written in the prose, with any unit glued to it.
 *
 * The tail is `(?![a-zA-Z0-9])` and NOT `\b`: `ℓ` is outside the ASCII word class
 * that `\b` is defined over, so "200 mℓ" — the exact unit on the scanned page —
 * would fail a word-boundary check and the volume constraint would vanish.
 */
const VALUE_WITH_UNIT =
  /(\d+(?:\.\d+)?)\s*(m\s*ℓ|mℓ|ml|millilitres?|milliliters?|litres?|liters?|cm\s*\^?\s*3|cm³|m\s*\^?\s*3|m³|mm\s*\^?\s*3|mm³|cm\s*\^?\s*2|cm²|m\s*\^?\s*2|m²|mm\s*\^?\s*2|mm²)(?![a-zA-Z0-9])/gi;

/**
 * Normalise a written unit to a canonical LaTeX form.
 *
 * The `unit` is rendered as-is into the working, so it is stored as LaTeX rather
 * than as plain text: `\text{m}\ell` renders the millilitre symbol, while
 * `\text{mℓ}` would swallow it into an upright text run.
 */
function canonicalUnit(raw: string): { unit: string; kind: "volume" | "area" } {
  const u = raw.toLowerCase().replace(/\s+/g, "");
  if (/^(mℓ|ml|millilitres?|milliliters?)$/.test(u)) {
    return { unit: "\\text{m}\\ell", kind: "volume" };
  }
  if (/^(litres?|liters?)$/.test(u)) return { unit: "\\ell", kind: "volume" };
  if (/^(cm\^?3|cm³)$/.test(u)) return { unit: "\\text{cm}^3", kind: "volume" };
  if (/^(m\^?3|m³)$/.test(u)) return { unit: "\\text{m}^3", kind: "volume" };
  if (/^(mm\^?3|mm³)$/.test(u)) return { unit: "\\text{mm}^3", kind: "volume" };
  if (/^(cm\^?2|cm²)$/.test(u)) return { unit: "\\text{cm}^2", kind: "area" };
  if (/^(m\^?2|m²)$/.test(u)) return { unit: "\\text{m}^2", kind: "area" };
  return { unit: "\\text{mm}^2", kind: "area" };
}

/**
 * The one quantity the problem FIXES, e.g. "must hold 200 mℓ when full".
 *
 * Returns null unless exactly one dimensioned value is stated: a problem with two
 * competing numbers ("holds 200 mℓ and the metal costs 3 per cm²") gives no
 * unambiguous constraint, and picking one would be a guess.
 *
 * The number is taken AS WRITTEN. 1 mℓ is 1 cm³ by definition, so a textbook that
 * states 200 mℓ and prints h = 200/πr² is self-consistent with no conversion; a
 * problem that states litres and prints a cm-based answer will simply fail the
 * substitution gate below, which is the honest outcome.
 */
function readConstraint(prose: string): SolidConstraint | null {
  const matches = [...prose.matchAll(VALUE_WITH_UNIT)];
  if (matches.length !== 1) return null;
  const [, digits, rawUnit] = matches[0];
  const value = Number(digits);
  if (!Number.isFinite(value) || value <= 0) return null;
  const { unit, kind } = canonicalUnit(rawUnit);

  if (kind === "volume") {
    if (!VOLUME_CUE.test(prose)) return null;
    return { quantity: "volume", value, unit };
  }
  if (!AREA_CUE.test(prose)) return null;
  return {
    quantity: CURVED_CUE.test(prose) ? "curved_surface_area" : "total_surface_area",
    value,
    unit,
  };
}

/** Is the solid open at one end? `null` when the text does not say. */
function readOpenness(prose: string): boolean | null {
  if (CLOSED_CUE.test(prose)) return false;
  if (OPEN_CUE.test(prose)) return true;
  return null;
}

// ---------------------------------------------------------------------------
// Reading the ask
// ---------------------------------------------------------------------------

const SHOW_THAT =
  /\b(?:show|prove|verify|deduce|establish)\s+(?:that|:)?\s*/i;

/**
 * Pull `<symbol> = <expression>` out of the text that FOLLOWS a "show that".
 *
 * The expression is taken greedily to the end of the clause and then trimmed back
 * token by token until what remains parses as mathematics containing only the
 * symbols this problem is about. That is what lets a trailing full stop, a
 * following sentence, or an OCR'd "." survive without a bespoke rule for each.
 */
function readShowThat(
  mixed: string
): { target: string; latex: string; lead: string } | null {
  // Only the clause that carries the "show that" — a later sub-question's
  // equation must never be mistaken for this one's claim.
  const clause = segments(mixed).find((s) => SHOW_THAT.test(s));
  if (!clause) return null;
  const at = SHOW_THAT.exec(clause);
  if (!at) return null;
  const after = clause.slice(at.index + at[0].length);
  // The claim is the LAST `x = …` in the clause: "show that the height of the
  // glass, h, can be expressed as h = 200/πr²" names the symbol twice, and it is
  // the one carrying the expression that matters.
  const eq = /(?:^|[\s,;:(])([a-zA-Z])(?:_\{?[0-9a-zA-Z]+\}?)?\s*=\s*([^=]+)$/;
  const trimmed = after.trim();
  const m = eq.exec(trimmed);
  if (!m) return null;
  const expr = trimToMath(m[2]);
  if (!expr) return null;
  // The words BETWEEN "show that" and the equation are what name the claim's
  // subject ("the total surface area is A = …"). Anything earlier in the problem
  // describes the constraint instead, and reading that as the subject makes
  // "must hold 200 mℓ … show that h = …" look like a claim about volume.
  return { target: m[1], latex: expr, lead: trimmed.slice(0, m.index + m[0].indexOf("=")) };
}

/**
 * Trim trailing prose and punctuation until what remains is real mathematics.
 *
 * A textbook writes "h = 200/πr², where r is the radius in cm." — the expression
 * and the sentence that follows it are not separated by anything a regex can see,
 * so tokens come off the end until the remainder parses.
 */
function trimToMath(raw: string): string | null {
  let expr = raw.trim();
  for (let guard = 0; guard < 32 && expr.length > 0; guard++) {
    const trimmed = expr.replace(/[.,;:]+$/, "").trim();
    if (isParseableMath(trimmed)) return trimmed;
    const cut = trimmed.replace(/\s*\S+$/, "").trim();
    if (cut === expr) break;
    expr = cut;
  }
  return null;
}

/** Does this LaTeX fragment convert to something mathjs can evaluate? */
function isParseableMath(latex: string): boolean {
  if (!latex || /[=<>]/.test(latex)) return false;
  const ascii = latexToAscii(latex);
  if (!ascii.trim()) return false;
  // A fragment of prose ("expressed as") converts to a product of letters, which
  // parses fine — so require at least one digit or operator, i.e. actual maths.
  if (!/[0-9+\-*/^]/.test(ascii)) return false;
  try {
    parse(ascii);
    return true;
  } catch {
    return false;
  }
}

const MIN_CUE = /\b(?:minimum|minimise|minimize|least|smallest|cheapest)\b/i;
const MAX_CUE = /\b(?:maximum|maximise|maximize|greatest|largest|most)\b/i;
const OPTIMIZE_ASK =
  /\b(?:find|determine|calculate|compute|work\s+out|obtain|what)\b/i;

/**
 * "Determine the value of r for which A is a minimum."
 *
 * Requires all three of: an ask cue, a sense (min/max), and a named variable —
 * "discuss the minimum" is not a computation, and an ask with no variable does
 * not say what to solve for.
 */
function readOptimizeAsk(
  mixed: string
): { sense: "min" | "max"; variable: string } | null {
  const scope = findAskClause(proseOnly(mixed)) ?? proseOnly(mixed);
  if (!OPTIMIZE_ASK.test(scope)) return null;
  const isMin = MIN_CUE.test(scope);
  const isMax = MAX_CUE.test(scope);
  if (isMin === isMax) return null; // neither, or contradictory
  const v =
    /\bvalue\s+of\s+([a-zA-Z])\b/i.exec(scope) ??
    /\bfor\s+which\s+([a-zA-Z])\b/i.exec(scope) ??
    /\b([a-zA-Z])\s+(?:for\s+which|that\s+(?:gives|makes))\b/i.exec(scope);
  if (!v || /^[aAI]$/.test(v[1])) return null;
  return { sense: isMin ? "min" : "max", variable: v[1] };
}

/**
 * An objective the problem states OUTRIGHT — "A = 2πr² + 400/r", the result of
 * the show-that part immediately above the optimisation part.
 *
 * This is the safest source there is: nothing is inferred about openness or which
 * surface is meant, because the function is printed in the question. It is tried
 * before any shape formula.
 */
function readStatedObjective(
  mixed: string,
  variable: string
): { name: string; latex: string; ascii: string } | null {
  const re = /(?:^|[\s,;:(])([A-Za-z])(?:_\{?[0-9a-zA-Z]+\}?)?\s*=\s*([^=]+)$/;
  let best: { name: string; latex: string; ascii: string } | null = null;
  for (const segment of segments(mixed)) {
    const m = re.exec(segment);
    if (!m || m[1] === variable) continue; // that is the unknown, not the objective
    const latex = trimToMath(m[2]);
    if (!latex) continue;
    const ascii = latexToAscii(latex);
    const vars = variablesIn(ascii);
    // Exactly the one variable we optimise over — an objective still carrying a
    // second unknown is not yet a function of one variable, and differentiating
    // it would silently treat that unknown as a constant.
    if (vars.length === 1 && vars[0] === variable) {
      best = { name: m[1], latex, ascii };
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// parseSolid — the classifier's entry point
// ---------------------------------------------------------------------------

/**
 * Read a solid-geometry show-that / optimisation problem, or return null.
 *
 * Null is the common case and always the safe one: the caller carries on to the
 * existing classification, which is exactly today's behaviour.
 */
export function parseSolid(rawLatex: string): SolidSpec | null {
  if (!rawLatex || !rawLatex.trim()) return null;
  const mixed = flattenKeepingMath(rawLatex);
  const prose = proseOnly(mixed);
  // Same parse-integrity guard the circle engine uses: a digit group whose
  // separator could be a decimal point or a thousands mark has two readings that
  // differ by orders of magnitude, and nothing downstream can tell them apart.
  if (hasAmbiguousNumberGrouping(prose)) return null;

  const shape = readShape(prose);
  const symbols = readSymbols(mixed);

  // --- The show-that branch ------------------------------------------------
  const claim = readShowThat(mixed);
  if (claim) {
    // A show-that with no NAMED solid has no formula to substitute into, so it is
    // left to the existing tutor route rather than claimed and then declined —
    // returning a spec here would turn an honest "let's work through it" into a
    // "couldn't verify", which is a worse answer than the one we already gave.
    if (!shape) return null;
    const claimedAscii = latexToAscii(claim.latex);
    const vars = variablesIn(claimedAscii);
    // A claim that restates its own subject proves nothing, and one that has no
    // free variable at all is a numeric equality, not a derivation.
    if (vars.includes(claim.target)) return null;
    // Is the claim FOR a dimension (h = …) or for a named quantity (A = …)?
    const claimOf = readClaimSubject(claim.lead, claim.target, shape, symbols);
    if (!claimOf) return null;
    // Bind the remaining shape dimension to the symbol the claim actually uses,
    // when the prose never declared it. For a cylinder whose height is claimed,
    // the single free variable in `200/πr²` IS the radius.
    const bound = bindFromClaim(shape, symbols, claim.target, claimOf, vars);
    if (!bound) return null;
    return {
      shape,
      symbols: bound,
      constraint: readConstraint(prose),
      open: readOpenness(prose),
      task: {
        kind: "show_that",
        target: claim.target,
        claimedLatex: claim.latex,
        claimedAscii,
        claimOf,
      },
    };
  }

  // --- The optimisation branch ---------------------------------------------
  const ask = readOptimizeAsk(mixed);
  if (!ask) return null;
  const stated = readStatedObjective(mixed, ask.variable);
  if (stated) {
    return {
      shape,
      symbols,
      constraint: readConstraint(prose),
      open: readOpenness(prose),
      task: {
        kind: "optimize",
        sense: ask.sense,
        variable: ask.variable,
        objectiveAscii: stated.ascii,
        objectiveLatex: stated.latex,
        objectiveName: stated.name,
      },
    };
  }
  // No printed objective — build one from the shape and the constraint. Every
  // ingredient must be unambiguous or this declines.
  const built = buildObjective(shape, symbols, prose, ask.variable);
  if (!built) return null;
  return {
    shape,
    symbols: built.symbols,
    constraint: built.constraint,
    open: readOpenness(prose),
    task: {
      kind: "optimize",
      sense: ask.sense,
      variable: ask.variable,
      objectiveAscii: built.ascii,
      objectiveLatex: built.latex,
      objectiveName: built.name,
    },
  };
}

/** Is the claimed symbol one of the shape's DIMENSIONS, or a named quantity? */
function readClaimSubject(
  lead: string,
  target: string,
  shape: SolidShape,
  symbols: Sym
): "dimension" | SolidQuantity | null {
  // Declared as a dimension symbol ⇒ a dimension.
  for (const role of Object.keys(symbols) as SolidRole[]) {
    if (symbols[role] === target) return "dimension";
  }
  // The conventional letter for one of THIS shape's dimensions ⇒ a dimension.
  // Checked before the word cues: `h` on a cylinder means the height whatever
  // else the sentence happens to mention.
  for (const role of SHAPES[shape].roles) {
    if (defaultSymbol(role) === target) return "dimension";
  }
  // Otherwise the words introducing the claim name what it is.
  if (CURVED_CUE.test(lead)) return "curved_surface_area";
  if (AREA_CUE.test(lead)) return "total_surface_area";
  if (VOLUME_CUE.test(lead)) return "volume";
  for (const role of Object.keys(ROLE_WORD) as SolidRole[]) {
    if (ROLE_WORD[role].test(lead)) return "dimension";
  }
  return null;
}

function defaultSymbol(role: SolidRole): string {
  return role === "radius"
    ? "r"
    : role === "height"
      ? "h"
      : role === "side"
        ? "s"
        : role === "length"
          ? "l"
          : "w";
}

/**
 * Complete the symbol map using the claim itself.
 *
 * A textbook often labels the figure rather than the sentence ("Figure: cylinder
 * with height h and radius r" may be a picture, not text the OCR can read). When
 * the shape has exactly one dimension left unaccounted for and the claim has
 * exactly one free variable, the binding is forced — there is nothing else it
 * could be. Any looser situation declines.
 */
function bindFromClaim(
  shape: SolidShape | null,
  symbols: Sym,
  target: string,
  claimOf: "dimension" | SolidQuantity,
  claimVars: string[]
): Sym | null {
  if (!shape) return symbols;
  const out: Sym = { ...symbols };
  const roles = SHAPES[shape].roles;

  if (claimOf === "dimension") {
    // The claimed symbol names one of the roles. If the prose did not say which,
    // fall back to the role whose DEFAULT symbol it is.
    const known = roles.find((role) => out[role] === target);
    if (!known) {
      const byDefault = roles.find((role) => defaultSymbol(role) === target);
      if (!byDefault) return null;
      out[byDefault] = target;
    }
  }
  // Assign every still-unnamed role from the claim's free variables.
  const unnamed = roles.filter((role) => !out[role]);
  const spare = claimVars.filter((v) => !Object.values(out).includes(v));
  if (unnamed.length === 0) return spare.length === 0 ? out : null;

  // A letter that IS a role's conventional symbol belongs to that role — `r` in
  // `2πr² + 400/r` is the radius, whichever order the roles are listed in.
  for (const role of unnamed) {
    const conventional = defaultSymbol(role);
    const at = spare.indexOf(conventional);
    if (at >= 0) {
      out[role] = conventional;
      spare.splice(at, 1);
    }
  }
  // Whatever is left: one unnamed role and one spare letter is forced (there is
  // nothing else it could mean); more than one of each is a guess about which
  // letter is which dimension, so decline.
  const stillUnnamed = roles.filter((role) => !out[role]);
  if (spare.length > 0) {
    if (spare.length > 1 || stillUnnamed.length !== 1) return null;
    out[stillUnnamed[0]] = spare[0];
  }
  // Roles the claim never mentions are the ones the constraint ELIMINATES — a
  // total surface area written in r alone has already absorbed the height. Their
  // symbol is arbitrary because it cancels, so the conventional letter is used;
  // the substitution gate below still has to pass either way.
  for (const role of roles) {
    if (!out[role]) out[role] = defaultSymbol(role);
  }
  // …unless that collides, which would fuse two distinct dimensions into one.
  const used = roles.map((role) => out[role]);
  if (new Set(used).size !== used.length) return null;
  return out;
}

/** Build a one-variable objective from the shape formulas + the constraint. */
function buildObjective(
  shape: SolidShape | null,
  symbols: Sym,
  prose: string,
  variable: string
): {
  ascii: string;
  latex: string;
  name: string;
  symbols: Sym;
  constraint: SolidConstraint;
} | null {
  if (!shape) return null;
  const constraint = readConstraint(prose);
  if (!constraint) return null;
  const def = SHAPES[shape];
  // Fill any undeclared role with its conventional symbol — but only when the
  // ask's variable is one of them, so we never optimise over a letter the shape
  // does not have.
  const sym: Sym = { ...symbols };
  for (const role of def.roles) if (!sym[role]) sym[role] = defaultSymbol(role);
  if (!def.roles.some((role) => sym[role] === variable)) return null;
  // Two roles exactly: one is the variable, the constraint eliminates the other.
  if (def.roles.length !== 2) return null;
  const otherRole = def.roles.find((role) => sym[role] !== variable);
  if (!otherRole) return null;
  const other = sym[otherRole] as string;

  // The objective is whichever surface the problem names — and if it never says
  // whether the solid is open or closed, there is no answer to give.
  const wantsArea = AREA_CUE.test(prose) || CURVED_CUE.test(prose);
  if (!wantsArea) return null;
  if (constraint.quantity !== "volume") return null;
  const open = readOpenness(prose);
  const objective = CURVED_CUE.test(prose)
    ? def.curvedSurface
    : open === true
      ? def.openSurface
      : open === false
        ? def.totalSurface
        : null;
  if (!objective) return null;
  const kind: SolidQuantity | "open_surface_area" = CURVED_CUE.test(prose)
    ? "curved_surface_area"
    : open
      ? "open_surface_area"
      : "total_surface_area";

  // Eliminate the other dimension using the constraint.
  const eliminated = isolate(def.volume(sym), other, constraint.value);
  if (!eliminated) return null;
  const ascii = `(${objective(sym)})`.replace(
    new RegExp(String.raw`\b${other}\b`, "g"),
    `(${eliminated.ascii})`
  );
  const vars = variablesIn(ascii);
  if (vars.length !== 1 || vars[0] !== variable) return null;
  return {
    ascii,
    latex: def.latex(sym)[kind] ?? asciiToLatex(ascii),
    name: "A",
    symbols: sym,
    constraint,
  };
}

// ---------------------------------------------------------------------------
// Isolation — solving `formula = value` for one symbol
// ---------------------------------------------------------------------------

/**
 * Solve `expr(sym…) = value` for `target`, when the dependence is a single power.
 *
 * Every formula in the catalogue is a monomial in each of its dimensions (πr²h is
 * h¹; s³ is s³), so the target's exponent is discovered by sampling rather than
 * assumed: evaluate the formula at two values of the target and read the exponent
 * off the ratio. A dependence that is NOT a clean power (a cone's slant height,
 * where r appears inside a root as well as outside) fails the check and declines,
 * which is why the cone's surface area never pretends to isolate.
 */
function isolate(
  expr: string,
  target: string,
  value: number
): { ascii: string; latex: string; power: number } | null {
  const others = variablesIn(expr).filter((v) => v !== target);
  // A probe assignment for the other variables; two different ones, so a formula
  // that only accidentally looks like a power at one point cannot pass.
  const probes = [1.7, 2.9];
  let power: number | null = null;
  for (const p of probes) {
    const scope: Record<string, number> = {};
    for (const v of others) scope[v] = p;
    const at1 = evalReal(expr, { ...scope, [target]: 1 });
    const at2 = evalReal(expr, { ...scope, [target]: 2 });
    if (!Number.isFinite(at1) || !Number.isFinite(at2) || at1 === 0) return null;
    const k = Math.log2(at2 / at1);
    if (!Number.isFinite(k)) return null;
    const rounded = Math.round(k);
    if (rounded < 1 || rounded > 4 || Math.abs(k - rounded) > 1e-9) return null;
    if (power !== null && power !== rounded) return null;
    power = rounded;
  }
  if (power === null) return null;
  // coefficient = expr with target = 1 (valid because expr = coeff · targetᵏ).
  const coeffAscii = `(${expr})`.replace(new RegExp(String.raw`\b${target}\b`, "g"), "(1)");
  // Confirm the factorisation holds where it will actually be used, not just at
  // the probe points: expr must equal coeff · targetᵏ everywhere we sample.
  for (const t of [0.6, 1.4, 3.3]) {
    for (const p of probes) {
      const scope: Record<string, number> = { [target]: t };
      for (const v of others) scope[v] = p;
      const lhs = evalReal(expr, scope);
      const rhs = evalReal(coeffAscii, scope) * Math.pow(t, power);
      if (!Number.isFinite(lhs) || !Number.isFinite(rhs)) return null;
      if (Math.abs(lhs - rhs) > 1e-9 * (1 + Math.abs(lhs))) return null;
    }
  }
  const quotient = `(${value})/(${coeffAscii})`;
  // Build the display fraction by hand rather than simplifying the quotient:
  // mathjs turns `500/(πr²)` into `500/r²/π`, which sets as a fraction inside a
  // fraction. The numerator and denominator are already separate here, so the
  // readable form is free.
  const denominator = prettyLatex(coeffAscii);
  const fraction = `\\frac{${trimNumber(value)}}{${denominator}}`;
  return {
    ascii: power === 1 ? quotient : `(${quotient})^(1/${power})`,
    latex: power === 1 ? fraction : `\\sqrt[${power}]{${fraction}}`,
    power,
  };
}

// ---------------------------------------------------------------------------
// Solving
// ---------------------------------------------------------------------------

/** Sample points for the identity gate — a wide, deterministic spread of
 * positive values, because every dimension of a solid is a positive length. */
const POSITIVE_SAMPLES = [0.35, 0.8, 1.3, 2.1, 3.7, 5.2, 8.9, 14.3];
const IDENTITY_TOL = 1e-9;
/** How many samples must evaluate cleanly before a verdict is trustworthy. */
const MIN_IDENTITY_SAMPLES = 5;

/**
 * Solve a parsed solid problem, or return null for an honest decline.
 *
 * Like the circle engine, the verification is INTERNAL and unconditional: a null
 * here means "could not be proven", never "probably right".
 */
export function solveSolid(
  spec: SolidSpec
): { answer: FinalAnswer; methods: MethodData[] } | null {
  return spec.task.kind === "show_that"
    ? solveShowThat(spec, spec.task)
    : solveOptimize(spec, spec.task);
}

// --- show that -------------------------------------------------------------

function solveShowThat(
  spec: SolidSpec,
  task: Extract<SolidTask, { kind: "show_that" }>
): { answer: FinalAnswer; methods: MethodData[] } | null {
  const { shape, symbols, constraint } = spec;
  if (!shape || !constraint) return null;
  const def = SHAPES[shape];

  // Which formula does the constraint fix?
  const constraintExpr = formulaFor(def, constraint.quantity, symbols, null);
  if (!constraintExpr) return null;

  // The claim must be ABOUT one of the shape's dimensions for the substitution
  // gate to have somewhere to put it. (A claim about a derived AREA is proven by
  // the same gate, but by substituting the eliminated dimension first — handled
  // below.)
  const targetIsDimension = def.roles.some((role) => symbols[role] === task.target);

  if (targetIsDimension) {
    if (!identityHolds(constraintExpr, task.target, task.claimedAscii, constraint.value)) {
      return null;
    }
    return {
      answer: showThatAnswer(task),
      methods: [
        showThatMethod(spec, task, constraintExpr, constraint, def, null),
      ],
    };
  }

  // A claim about a NAMED QUANTITY ("show that A = πr² + 400/r") is proven by
  // building that quantity from the shape formulas, eliminating the constrained
  // dimension, and checking the result matches the claim everywhere.
  if (task.claimOf === "dimension") return null;
  // A total-surface claim on a solid whose openness the text never states has two
  // different right answers, so it is not answered at all.
  if (task.claimOf === "total_surface_area" && spec.open === null) return null;
  const target = formulaFor(def, task.claimOf, symbols, spec.open);
  if (!target) return null;
  const freeVar = variablesIn(task.claimedAscii)[0];
  if (!freeVar) return null;
  const other = def.roles
    .map((role) => symbols[role])
    .find((s): s is string => !!s && s !== freeVar);
  if (!other) return null;
  const eliminated = isolate(constraintExpr, other, constraint.value);
  if (!eliminated) return null;
  const built = `(${target})`.replace(
    new RegExp(String.raw`\b${other}\b`, "g"),
    `(${eliminated.ascii})`
  );
  if (!expressionsAgree(built, task.claimedAscii, freeVar)) return null;
  return {
    answer: showThatAnswer(task),
    methods: [
      showThatMethod(spec, task, constraintExpr, constraint, def, {
        eliminatedSymbol: other,
        eliminatedLatex: eliminated.latex,
        objectiveLatex: def.latex(symbols)[objectiveKey(task.claimOf, spec.open)] ?? "",
      }),
    ],
  };
}

/**
 * The substitution gate: does putting the claimed expression back into the
 * constraint satisfy it IDENTICALLY?
 *
 * This is the whole proof. `πr²·(200/πr²) = 200` for every r tried means the
 * claim is right; one sample that misses means it is not, and a single sample
 * that lands on a lucky coincidence cannot outvote the rest.
 */
function identityHolds(
  constraintExpr: string,
  target: string,
  claimed: string,
  value: number
): boolean {
  const others = variablesIn(constraintExpr).filter((v) => v !== target);
  let checked = 0;
  for (let i = 0; i < POSITIVE_SAMPLES.length; i++) {
    const scope: Record<string, number> = {};
    // Each variable gets a DIFFERENT value, walking the sample list at its own
    // offset. Setting them all equal would let a claim that confuses two
    // dimensions (l·w·h vs l³) pass every test it was ever given.
    others.forEach((v, j) => {
      scope[v] = POSITIVE_SAMPLES[(i + j * 3) % POSITIVE_SAMPLES.length];
    });
    const claimedValue = evalReal(claimed, scope);
    if (!Number.isFinite(claimedValue)) continue;
    const got = evalReal(constraintExpr, { ...scope, [target]: claimedValue });
    if (!Number.isFinite(got)) continue;
    if (Math.abs(got - value) > IDENTITY_TOL * (1 + Math.abs(value))) return false;
    checked++;
  }
  return checked >= MIN_IDENTITY_SAMPLES;
}

/** Do two single-variable expressions agree across the sample grid? */
function expressionsAgree(a: string, b: string, variable: string): boolean {
  let checked = 0;
  for (const x of POSITIVE_SAMPLES) {
    const av = evalReal(a, { [variable]: x });
    const bv = evalReal(b, { [variable]: x });
    if (!Number.isFinite(av) || !Number.isFinite(bv)) continue;
    if (Math.abs(av - bv) > IDENTITY_TOL * (1 + Math.abs(av))) return false;
    checked++;
  }
  return checked >= MIN_IDENTITY_SAMPLES;
}

/** Which catalogue LaTeX entry a claimed quantity corresponds to. */
function objectiveKey(
  quantity: SolidQuantity,
  open: boolean | null
): SolidQuantity | "open_surface_area" {
  if (quantity !== "total_surface_area") return quantity;
  return open ? "open_surface_area" : "total_surface_area";
}

function formulaFor(
  def: ShapeDef,
  quantity: SolidQuantity,
  symbols: Sym,
  open: boolean | null
): string | null {
  if (quantity === "volume") return def.volume(symbols);
  if (quantity === "curved_surface_area") return def.curvedSurface?.(symbols) ?? null;
  if (open === true) return def.openSurface?.(symbols) ?? null;
  return def.totalSurface?.(symbols) ?? null;
}

function showThatAnswer(
  task: Extract<SolidTask, { kind: "show_that" }>
): FinalAnswer {
  return {
    latex: `${task.target} = ${task.claimedLatex}`,
    plain: `${task.target} = ${latexToAscii(task.claimedLatex)}`,
  };
}

/** The working a teacher would write on the board. */
function showThatMethod(
  spec: SolidSpec,
  task: Extract<SolidTask, { kind: "show_that" }>,
  constraintExpr: string,
  constraint: SolidConstraint,
  def: ShapeDef,
  derivation: {
    eliminatedSymbol: string;
    eliminatedLatex: string;
    objectiveLatex: string;
  } | null
): MethodData {
  const shapeName = (spec.shape ?? "solid").replace(/_/g, " ");
  const unit = constraint.unit ? `\\,${constraint.unit}` : "";
  const quantityWord =
    constraint.quantity === "volume" ? "volume" : "surface area";
  const formulaLatex =
    def.latex(spec.symbols)[constraint.quantity] ??
    `${constraint.quantity === "volume" ? "V" : "A"} = ${asciiToLatex(constraintExpr)}`;

  const steps: StepData[] = [
    {
      expression: formulaLatex,
      operation: "Start from the formula",
      why: `The ${quantityWord} of a ${shapeName} is a standard result — write it down before anything is substituted.`,
    },
    {
      expression: `${rhsOf(formulaLatex, constraintExpr)} = ${trimNumber(constraint.value)}${unit}`,
      operation: "Use the given value",
      why: `The problem fixes the ${quantityWord} at ${trimNumber(constraint.value)}, so the formula becomes an equation rather than a definition.`,
    },
  ];

  if (!derivation) {
    // The claim IS one of the dimensions: rearranging the constraint is the
    // whole proof, so the last line is the required form itself.
    steps.push({
      expression: `${task.target} = ${task.claimedLatex}`,
      operation: `Make ${task.target} the subject`,
      why: `Divide both sides by everything multiplying ${task.target}. Substituting this back reproduces the given ${quantityWord} exactly, which is what "show that" asks for.`,
      pivotal: true,
    });
  } else {
    // The claim is a DERIVED quantity, so the constrained dimension is made the
    // subject first and then substituted into the formula for what was asked.
    const { eliminatedSymbol: e } = derivation;
    steps.push(
      {
        expression: `${e} = ${derivation.eliminatedLatex}`,
        operation: `Make ${e} the subject`,
        why: `The constraint ties the two dimensions together, so ${e} can be written purely in terms of the other one.`,
      },
      {
        expression: derivation.objectiveLatex,
        operation: "Write the formula for what was asked",
        why: `This still has both dimensions in it — which is why ${e} had to be found first.`,
      },
      {
        expression: `${task.target} = ${task.claimedLatex}`,
        operation: `Substitute ${e} and simplify`,
        why: `Replacing ${e} leaves one variable only, and it lands exactly on the expression the question asked us to show.`,
        pivotal: true,
      }
    );
  }

  return {
    id: "show_that",
    name: "Rearranging the formula",
    examPick: true,
    steps,
  };
}

// --- optimisation ----------------------------------------------------------

/** Where to look for a critical point, and how finely. A length is positive, and
 * exam answers sit well inside this window. */
const OPT_LO = 1e-4;
const OPT_HI = 1e4;
const OPT_STEPS = 4000;

function solveOptimize(
  spec: SolidSpec,
  task: Extract<SolidTask, { kind: "optimize" }>
): { answer: FinalAnswer; methods: MethodData[] } | null {
  const { variable, objectiveAscii, sense } = task;
  let d1: string;
  let d2: string;
  try {
    d1 = derivative(objectiveAscii, variable).toString();
    d2 = derivative(d1, variable).toString();
  } catch {
    return null;
  }

  const critical = findCriticalPoint(d1, variable);
  if (critical === null) return null;

  // The second-derivative test must confirm the sense the question ASKED for. A
  // question asking for a minimum, answered with a maximum, is a wrong answer.
  const curvature = evalReal(d2, { [variable]: critical });
  if (!Number.isFinite(curvature) || curvature === 0) return null;
  if (sense === "min" && curvature <= 0) return null;
  if (sense === "max" && curvature >= 0) return null;

  // …and the extremum must be GLOBAL over the domain. A local dip that some other
  // point beats is not "the minimum", and shipping it would be confidently wrong.
  const best = evalReal(objectiveAscii, { [variable]: critical });
  if (!Number.isFinite(best)) return null;
  for (let i = 0; i <= OPT_STEPS; i++) {
    const x = OPT_LO * Math.pow(OPT_HI / OPT_LO, i / OPT_STEPS);
    const y = evalReal(objectiveAscii, { [variable]: x });
    if (!Number.isFinite(y)) continue;
    if (sense === "min" && y < best - 1e-7 * (1 + Math.abs(best))) return null;
    if (sense === "max" && y > best + 1e-7 * (1 + Math.abs(best))) return null;
  }

  const exact = exactRoot(d1, critical);
  const decimal = trimNumber(Number(critical.toFixed(4)));
  const valueAt = trimNumber(Number(best.toFixed(4)));
  const answer: FinalAnswer = exact
    ? {
        latex: `${variable} = ${exact.latex} \\approx ${decimal}`,
        plain: `${variable} = ${exact.plain} ≈ ${decimal}`,
      }
    : { latex: `${variable} \\approx ${decimal}`, plain: `${variable} ≈ ${decimal}` };

  const senseWord = sense === "min" ? "minimum" : "maximum";
  const steps: StepData[] = [];
  // When the problem fixes a quantity, open with it — that constraint is what
  // turned a two-variable shape into a one-variable function, and a student who
  // skips it has no idea where the objective came from.
  if (spec.constraint && spec.shape) {
    const def = SHAPES[spec.shape];
    const constraintExpr = formulaFor(
      def,
      spec.constraint.quantity,
      spec.symbols,
      spec.open
    );
    if (constraintExpr) {
      const unit = spec.constraint.unit ? `\\,${spec.constraint.unit}` : "";
      const formulaLatex = def.latex(spec.symbols)[spec.constraint.quantity] ?? "";
      steps.push({
        expression: `${rhsOf(formulaLatex, constraintExpr)} = ${trimNumber(spec.constraint.value)}${unit}`,
        operation: "The constraint",
        why: `This fixed ${spec.constraint.quantity === "volume" ? "volume" : "area"} is what lets one dimension be written in terms of the other, leaving a single variable to optimise.`,
      });
    }
  }
  steps.push(
    {
      expression: `${task.objectiveName} = ${task.objectiveLatex}`,
      operation: "The function to optimise",
      why: `Everything is now in terms of ${variable} alone, which is what makes calculus possible here.`,
    },
    {
      expression: `\\frac{d${task.objectiveName}}{d${variable}} = ${prettyLatex(d1)}`,
      operation: "Differentiate",
      why: `The gradient of ${task.objectiveName} tells us how it responds to a change in ${variable}.`,
    },
    {
      expression: `${prettyLatex(d1)} = 0`,
      operation: "Set the derivative to zero",
      why: `At a ${senseWord} the curve is momentarily flat, so its gradient is zero there.`,
      pivotal: true,
    },
    {
      expression: answer.latex,
      operation: `Solve for ${variable}`,
      why: "This is the only positive solution, and a length cannot be negative.",
    },
    {
      expression: `\\frac{d^2${task.objectiveName}}{d${variable}^2} ${curvature > 0 ? ">" : "<"} 0`,
      operation: "Confirm it is a " + senseWord,
      why:
        curvature > 0
          ? "The second derivative is positive, so the curve is concave up — this stationary point is a minimum, not a maximum."
          : "The second derivative is negative, so the curve is concave down — this stationary point is a maximum, not a minimum.",
    },
    {
      expression: `${task.objectiveName}_{\\text{${senseWord}}} = ${valueAt}`,
      operation: `The ${senseWord} value`,
      why: `Substituting ${variable} back into ${task.objectiveName} gives the ${senseWord} itself.`,
    }
  );

  return {
    answer,
    methods: [
      { id: "optimization", name: "Differentiate and test", examPick: true, steps },
    ],
  };
}

/**
 * The single positive root of `f'(x) = 0`, or null.
 *
 * A scan for sign changes across a log-spaced grid finds every root in the window
 * without assuming a form; bisection then refines it. TWO roots means the answer
 * is not unique from this analysis alone, so it declines rather than pick one.
 */
function findCriticalPoint(d1: string, variable: string): number | null {
  const roots: number[] = [];
  let prevX = OPT_LO;
  let prevY = evalReal(d1, { [variable]: prevX });
  for (let i = 1; i <= OPT_STEPS; i++) {
    const x = OPT_LO * Math.pow(OPT_HI / OPT_LO, i / OPT_STEPS);
    const y = evalReal(d1, { [variable]: x });
    if (Number.isFinite(prevY) && Number.isFinite(y) && prevY * y < 0) {
      roots.push(bisect(d1, variable, prevX, x));
    }
    if (Number.isFinite(y)) {
      prevX = x;
      prevY = y;
    }
  }
  const distinct = roots.filter(
    (r0, i) => roots.findIndex((r1) => Math.abs(r1 - r0) < 1e-6 * (1 + Math.abs(r0))) === i
  );
  if (distinct.length !== 1) return null;
  const root = distinct[0];
  // The refined root must actually satisfy f'(x) = 0 — a sign change across a
  // POLE (1/x flips sign at 0 with no root) would otherwise pass.
  const residual = evalReal(d1, { [variable]: root });
  if (!Number.isFinite(residual)) return null;
  const scale = Math.max(
    Math.abs(evalReal(d1, { [variable]: root * 1.1 })),
    Math.abs(evalReal(d1, { [variable]: root * 0.9 })),
    1
  );
  return Math.abs(residual) < 1e-6 * scale ? root : null;
}

function bisect(expr: string, variable: string, lo: number, hi: number): number {
  let a0 = lo;
  let b0 = hi;
  let fa = evalReal(expr, { [variable]: a0 });
  for (let i = 0; i < 200; i++) {
    const mid = (a0 + b0) / 2;
    const fm = evalReal(expr, { [variable]: mid });
    if (!Number.isFinite(fm)) break;
    if (fa * fm <= 0) {
      b0 = mid;
    } else {
      a0 = mid;
      fa = fm;
    }
  }
  return (a0 + b0) / 2;
}

/**
 * The exact form of a critical point, when the stationary equation is a clean
 * two-term polynomial — which is what every textbook optimisation reduces to.
 *
 * `4πr³ − 400 = 0` gives r = ∛(100/π), and printing that alongside the decimal is
 * the form a teacher marks. Anything else returns null and only the decimal shows,
 * which is honest: the root genuinely is just a number.
 */
function exactRoot(d1: string, root: number): { latex: string; plain: string } | null {
  let coeffs: number[];
  try {
    const numeric = d1.replace(/\bpi\b/g, `(${Math.PI})`);
    const rat = rationalize(numeric, {}, true);
    coeffs = rat.coefficients as number[];
  } catch {
    return null;
  }
  if (!Array.isArray(coeffs) || coeffs.length < 2) return null;
  const nonZero = coeffs
    .map((c, power) => ({ c, power }))
    .filter(({ c }) => Math.abs(c) > 1e-12);
  if (nonZero.length !== 2) return null;
  const [low, high] = nonZero;
  if (low.power !== 0) return null;
  const power = high.power;
  const ratio = -low.c / high.c;
  if (!(ratio > 0)) return null;
  // Sanity: the exact form must reproduce the numeric root we verified.
  if (Math.abs(Math.pow(ratio, 1 / power) - root) > 1e-6 * (1 + root)) return null;
  const radicand = describeRatio(ratio);
  if (!radicand) return null;
  const rootLatex =
    power === 2
      ? `\\sqrt{${radicand.latex}}`
      : `\\sqrt[${power}]{${radicand.latex}}`;
  const rootPlain =
    power === 2
      ? `√(${radicand.plain})`
      : power === 3
        ? `∛(${radicand.plain})`
        : power === 4
          ? `∜(${radicand.plain})`
          : `(${radicand.plain})^(1/${power})`;
  return { latex: rootLatex, plain: rootPlain };
}

/** Write a positive number as `p`, `p/q`, `p/(qπ)` or `pπ/q` when it is one. */
function describeRatio(x: number): { latex: string; plain: string } | null {
  const near = (a: number, b: number): boolean => Math.abs(a - b) < 1e-9 * (1 + Math.abs(b));
  for (let q = 1; q <= 64; q++) {
    const p = Math.round(x * q);
    if (p > 0 && near(x, p / q)) {
      return q === 1
        ? { latex: `${p}`, plain: `${p}` }
        : { latex: `\\frac{${p}}{${q}}`, plain: `${p}/${q}` };
    }
    const pPi = Math.round(x * q * Math.PI);
    if (pPi > 0 && near(x, pPi / (q * Math.PI))) {
      return q === 1
        ? { latex: `\\frac{${pPi}}{\\pi}`, plain: `${pPi}/π` }
        : { latex: `\\frac{${pPi}}{${q}\\pi}`, plain: `${pPi}/(${q}π)` };
    }
    const pOverPi = Math.round((x * q) / Math.PI);
    if (pOverPi > 0 && near(x, (pOverPi * Math.PI) / q)) {
      return q === 1
        ? { latex: `${pOverPi}\\pi`, plain: `${pOverPi}π` }
        : { latex: `\\frac{${pOverPi}\\pi}{${q}}`, plain: `${pOverPi}π/${q}` };
    }
  }
  return null;
}

/**
 * Render an ascii expression as the LaTeX a teacher would write.
 *
 * A raw `asciiToLatex` of a machine-built expression comes back as
 * `2 \cdot \pi \cdot r \cdot ((500)/((\pi \cdot r^2 \cdot (1))))` — correct, and
 * unreadable. mathjs `simplify` collapses the scaffolding and `toTex` sets it
 * properly.
 *
 * Simplification is COSMETIC ONLY and is checked before it is trusted: the
 * simplified form must agree numerically with the original across the sample
 * grid, or the plain conversion is used instead. A prettier step that says
 * something different from the verified one is not a step worth having.
 */
function prettyLatex(ascii: string): string {
  try {
    const node = simplify(ascii);
    const vars = variablesIn(ascii);
    for (const x of POSITIVE_SAMPLES) {
      const scope: Record<string, number> = {};
      vars.forEach((v, i) => {
        scope[v] = POSITIVE_SAMPLES[(POSITIVE_SAMPLES.indexOf(x) + i * 3) % POSITIVE_SAMPLES.length];
      });
      const before = evalReal(ascii, scope);
      const after = evalReal(node.toString(), scope);
      if (!Number.isFinite(before) || !Number.isFinite(after)) continue;
      if (Math.abs(before - after) > 1e-9 * (1 + Math.abs(before))) {
        return asciiToLatex(ascii);
      }
    }
    return tidyTex(node.toTex({ parenthesis: "auto", implicit: "hide" }));
  } catch {
    return asciiToLatex(ascii);
  }
}

/**
 * Cosmetic clean-up of mathjs TeX: `4\cdot{ r}^{3}\cdot\pi` → `4r^{3}\pi`.
 *
 * Purely typographic — braces and explicit multiplication dots that a person
 * would not write. Nothing here changes what the expression means, and `\cdot` is
 * only dropped where a symbol follows, so `2\cdot3` keeps its dot rather than
 * silently becoming the number 23.
 */
function tidyTex(tex: string): string {
  return (
    tex
      .replace(/\{\s+/g, "{")
      // Unwrap single-symbol braces BEFORE the `\cdot` pass — otherwise `\cdot{r}`
      // hides the letter behind a brace, the dot survives, and unwrapping after
      // fuses them into the undefined macro `\cdotr`.
      .replace(/\{([a-zA-Z])\}/g, "$1")
      // A SPACE, not an empty string: `\pi\cdot r` collapsed to `\pi r` renders,
      // but collapsed to `\pir` is again an undefined macro that fails to draw.
      .replace(/\\cdot\s*(?=[a-zA-Z]|\\pi\b|\\frac|\\sqrt|\\left)/g, " ")
      .replace(/\s{2,}/g, " ")
      .trim()
  );
}

/**
 * The right-hand side of a catalogue formula (`V = \pi r^2 h` → `\pi r^2 h`).
 *
 * The hand-written catalogue LaTeX is the readable one — an `asciiToLatex` round
 * trip of the same formula comes back peppered with `\cdot`, which is not how a
 * teacher writes πr²h. Falls back to the conversion when there is no `=` to cut.
 */
function rhsOf(formulaLatex: string, fallbackAscii: string): string {
  const at = formulaLatex.indexOf("=");
  return at >= 0 ? formulaLatex.slice(at + 1).trim() : asciiToLatex(fallbackAscii);
}

/** Drop a trailing `.0` so integers read as integers. */
function trimNumber(x: number): string {
  return Number.isInteger(x) ? String(x) : String(Number(x.toFixed(6)));
}

/** Exposed for the classifier: does this text even look like a solid problem? */
export function looksLikeSolid(rawLatex: string): boolean {
  const prose = proseOnly(flattenKeepingMath(cleanLatex(rawLatex)));
  return (
    Object.values(SHAPE_NOUNS).some((re) => re.test(prose)) &&
    (SHOW_THAT.test(prose) || MIN_CUE.test(prose) || MAX_CUE.test(prose))
  );
}

/** Re-exported so tests can reach the catalogue without duplicating it. */
export const SOLID_SHAPES = SHAPES;
