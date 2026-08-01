/**
 * Circle mensuration engine — DETERMINISTIC, golden-rule.
 *
 * Solves the exam staple "area / circumference of a circle" (and arc length /
 * sector area given a central angle) from a single given radius OR diameter.
 * The formulae are exact (A = πr², C = 2πr, arc = 2πr·θ/360, sector = πr²·θ/360),
 * so the answer is returned in EXACT π-form (49π, not 153.94) with a decimal
 * alongside. The LLM is never called to compute — it only narrates the "why".
 *
 * Golden-rule safety rests on a STRICT parse gate, because the only real risk in
 * a closed-form formula is MISREADING the problem:
 *  - The figure must be a plain circle: any other shape word (triangle, square,
 *    rectangle, polygon, cylinder, sphere, cone, …) or "inscribed/circumscribed"
 *    DECLINES — those are different (or compound) formulae.
 *  - Exactly ONE unambiguous given is required: a named radius XOR a named
 *    diameter. Both-at-once, neither, or several candidate numbers → DECLINE.
 *    A fractional / mixed-number given (½, 3/4, 2½) is read at its true value.
 *  - Arc length / sector area require an explicit central angle in DEGREES; a
 *    RADIAN angle (π-multiple or bare "rad") DECLINES — nothing verifies the angle
 *    read, so a misread radian would ship silently. An ambiguous angle DECLINES.
 *  - Any partial or compound figure — semicircle / half / quarter / quadrant /
 *    segment / annulus / concentric / shaded region / two circles — DECLINES.
 *  - "Find the radius/diameter FROM an area/circumference" (the inverse problem)
 *    is NOT handled here — only forward mensuration from a linear given.
 *  - The rendered exact answer is re-checked against an independent numeric
 *    recompute (verify()), so a formatting slip can never ship a wrong number.
 */
import { fraction } from "mathjs";

import { cleanLatex } from "./latex";
import { hasLocaleAmbiguousNumber, NUMERIC_TOKEN, parseNumericToken } from "./nl/numeric";
import { readBoundValue, readUnitAnchoredValues } from "./nl/quantity";
import { FinalAnswer, MethodData } from "./types";

export type CircleTarget =
  | "area"
  | "circumference"
  | "diameter"
  | "arc_length"
  | "sector_area";

export interface CircleSpec {
  target: CircleTarget;
  /** The circle's radius, in the given unit (diameter is halved on the way in). */
  radius: number;
  /** How the given arrived — for the narration only. */
  givenKind: "radius" | "diameter";
  givenValue: number;
  /** Central angle in DEGREES (arc_length / sector_area only). */
  angleDeg?: number;
  /** A detected length unit ("cm", "m", …) for display, or null. */
  unit: string | null;
}

/** Length units accepted right after a given (display only). Longest-first so a
 * bare "m" never peels off "metres"; the ambiguous bare "in"/"ft" are dropped. */
const UNIT_SRC = String.raw`centimet(?:er|re)s?|millimet(?:er|re)s?|kilomet(?:er|re)s?|metres?|meters?|inches|inch|feet|foot|cm|mm|km|m`;

/** Other-figure words that make a bare circle formula unsafe → decline. A CRESCENT /
 * LUNE is a two-arc region strictly inside the disc — a bare πr² would ship the whole
 * disc for a proper sub-region. */
const OTHER_SHAPE =
  /\b(triangle|square|rectangle|rhombus|parallelogram|trapezoid|trapezium|polygon|pentagon|hexagon|cylinder|cylindrical|cylindric|sphere|spherical|spheroid|globe|cone|conical|conic|frustum|torus|toroidal|pyramid|tetrahedron|ellipse|oval|annulus|ring|hemisphere|prism|cube|crescent|lune)\b/i;

/** A 3-D SOLID's surface — the "curved / lateral surface" (2πrh cylinder, πrl cone) or a
 * "slant height" — is not a plane-circle quantity; the circle engine would ship the flat
 * base πr² (the "cylindrical tank … curved surface" → 49π-not-140π leak). Decline: this
 * engine sizes 2-D circles only. ("surface area" alone is already declined at the gate.) */
const SOLID_SURFACE = /\b(?:curved|lateral)\s+surface\b|\bslant\s+height\b/i;
const INSCRIBED = /\b(inscrib|circumscrib)/i;

/** Material REMOVED from the disc (a hole bored / cut out, a hollow washer) makes the
 * figure an annulus-like difference, NOT a plain circle: πr² would answer the full disc
 * and ignore the removed area (the "plate of radius 10 with a hole of area 36π cut out"
 * leak, which shipped 100π instead of 64π). Decline — this engine sizes whole circles. */
const REMOVED_MATERIAL =
  /\bhole\b|\bcut\s+out\b|\bhollow\b|\bpunched\s+out\b|\bbored\b|\bdrilled\b|\b(?:a\s+)?(?:half|quarter|third|fifth|sixth|eighth)\s+(?:is\s+|was\s+|has\s+been\s+)?removed\b|\b(?:a\s+|the\s+)?(?:smaller\s+|inner\s+|small\s+)?(?:circle|disc|disk|hole)\s+(?:is\s+|was\s+|has\s+been\s+)?(?:removed|cut\s+away|taken\s+out)\b/i;

/** A disc BISECTED by a diameter — folded along it, divided by it, or a region bounded
 * by a diameter together with an arc — is a SEMICIRCLE (half-disc), not a whole circle:
 * πr² ships DOUBLE the true ½πr². These half-disc figures carry no "semicircle/half"
 * keyword, so they slip PARTIAL_COMPOUND; catch the diameter-bisection phrasings here. */
// A disc "cut / divided / split ALONG (through / across / by) a diameter" is bisected into
// two semicircles — the ask ("the flat-topped shape", "the larger part") is a HALF-disc, and
// πr² ships DOUBLE. These carry no "semicircle/half" keyword and evade PARTIAL_COMPOUND, so
// the cut-along-a-diameter phrasing is caught here alongside the fold/divide-by forms.
const HALF_DISC =
  /\bfold(?:ed|s|ing)?\b[^.]*\bdiameter\b|\bdivided\s+by\s+(?:a\s+|its\s+|the\s+)?diameter\b|\b(?:cut|divided?|split|sliced|halved|sawn|sawed|separated)\b[^.]*\b(?:along|across|through|down|by|on)\b[^.]*\bdiameter\b|\b(?:bounded|enclosed)\s+by\b[^.]*\bdiameter\b[^.]*\barc\b|\b(?:bounded|enclosed)\s+by\b[^.]*\barc\b[^.]*\bdiameter\b|\beach\s+half\b|\bsplit\s+down\s+the\s+middle\b|\b(?:straight\s+line|line|cut)\s+through\s+(?:its\s+|the\s+)?cent(?:re|er)\b|\bhalf[\s-]?moon\b|\bhalfmoon\b|\blunette\b|\bd[\s-]?shaped\b/i;

/** A circle PARTITIONED into pieces, or physically transformed, where the ask is a
 * PART (one slice / the folded shape). A bare πr² would answer the whole disc — off
 * by the number of pieces (or by 2 for a fold). These are partial figures that this
 * whole-circle engine cannot size without an explicit angle, so decline. Distinct
 * from PARTIAL_COMPOUND (named half/quarter/segment): here the partition is described
 * as a physical cut/fold into slices/wedges/pieces, or a per-slice ask. */
const PARTITIONED_FIGURE =
  /\bfold(?:ed|s|ing)?\s+in(?:to)?\s+(?:two|half|halves)\b|\b(?:cut|divided?|split|sliced|partitioned)\s+in(?:to)?\s+\w+\s+(?:equal\s+)?(?:slices?|pieces?|parts?|sectors?|wedges?)\b|\b(?:one|each|a\s+single|per|every)\s+(?:slice|wedge|piece)\b|\b(?:slice|wedge)\s+of\s+(?:the\s+|a\s+)?(?:pizza|pie|cake|circle|disc|disk)\b/i;

/** Partial or compound circle figures — a bare πr²/2πr answer would be WRONG for
 * any of these (they need a different, or a difference-of, formula), so decline.
 * Covers spaced/hyphenated spellings that slip a plain `\bsemicircle\b`, plus the
 * plural "circles" (two circles / concentric / shaded-between). A fraction of a
 * circle may be worded with an interposed "of" ("half OF the circle") or as a
 * physical cut ("the circle is cut in half"), both of which slipped the old
 * `\bhalf\s+(?:a|the)?\s*circle`; catch the fraction-of-circle and cut/divided
 * phrasings explicitly so a semicircle/quadrant can never be read as a whole. */
// `semi-circular`/`quarter-circular` are the ADJECTIVE forms — the noun gate
// `semi[\s-]?circle` needs the literal "circle" (c-i-r-c-l-e), so "circular"
// (c-i-r-c-u-l-a-r) slipped and got a bare πr². A pluralised numerator fraction
// ("three quarters", "two-thirds", "seven eighths") likewise evaded the singular
// "half/quarter … circle" clause. "annular" is the ring/washer adjective.
// A PARTIAL modifier ("half"/"quarter"/"a third"/a numeric "3/4") applied to a
// circle/circular/DISC/DISK is a partial figure too — "half a circular disc"
// (an "a" interposed before "circular", no literal "circle" noun) and "3/4 of a
// circle" both slipped the old clause and got the WHOLE-disc πr². A FULL "circular
// disc" (no partial modifier) is genuinely a whole circle and still resolves.
const PARTIAL_COMPOUND =
  /\bsemi[\s-]?circle|\bhalf[\s-]?circle|\bquarter[\s-]?circle|\bsemi[\s-]?circular|\bhalf[\s-]?circular|\bquarter[\s-]?circular|\bsemi[\s-]?dis[ck]|\bhalf[\s-]?dis[ck]|\bquarter[\s-]?dis[ck]|\bannular|\bquadrant|\bsegment|\bchord|\bshaded|\bunshaded|\bconcentric|\bwasher|\bcircles\b|\binner\b|\bouter\b|\bbetween\b|\b(?:\d+\s*\/\s*\d+|0?\.\d+)\s+of\s+(?:a\s+|an\s+|the\s+|one\s+)?(?:circle|circular|disc|disk)\b|\b\d+\s*\/\s*\d+\s+(?:a\s+|an\s+|the\s+|one\s+)?(?:circle|circular|disc|disk)\b|\b(?:half|quarter|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+(?:of\s+)?(?:a\s+|an\s+|the\s+|one\s+)?(?:circle|circular|disc|disk)\b|\b(?:two|three|four|five|six|seven|eight|nine|ten)[\s-]+(?:halves|thirds|quarters|fourths|fifths|sixths|sevenths|eighths|ninths|tenths)\b|\bcut\s+in(?:to)?\s+(?:two\s+)?(?:half|halves)\b|\bdivided\s+in(?:to)?\b|\bbisect|\bhalved\b|\bsplit\s+in(?:to)?\b|\btwo\s+(?:equal\s+)?(?:halves|parts|pieces|portions)\b|\b(?:one|each)\s+(?:half|part|piece|portion)\b|\bcut\s+in(?:to)?\s+(?:two\s+)?(?:equal\s+)?(?:parts?|pieces?|portions?)\b|\binto\s+(?:two\s+)?(?:equal\s+)?portions?\b/i;

/**
 * Parse a circle-mensuration query, or null (→ not this engine). Deliberately
 * conservative: it declines anything it can't read UNAMBIGUOUSLY.
 */
export function parseCircle(rawLatex: string): CircleSpec | null {
  // Parse-integrity: an irrational given written with \sqrt (or the √ glyph) cannot
  // survive the macro-strip below — cleanLatex deletes "\sqrt" and leaves the bare
  // radicand, so "radius \sqrt{2}" would be misread as radius 2 (area 4π, not the true
  // 2π), and the verify gate re-derives from the SAME misread so it can't catch it. There
  // is no faithful flattening of a radical here → decline honestly.
  if (/\\sqrt\b|√/.test(rawLatex)) return null;

  // Flatten to prose. Convert fractions to "a/b" and mixed numbers to "a b/c",
  // and preserve π / ° BEFORE the generic macro strip (which would otherwise
  // delete them — turning "\frac{1}{2}" into "1 2" and "\pi/3" into "/3", the
  // two mis-reads that shipped wrong radii and wrong angles).
  let text = cleanLatex(rawLatex)
    .replace(/\\text\s*\{([^{}]*)\}/g, " $1 ")
    .replace(/(\d+)\s*\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/g, " $1 $2/$3 ") // mixed number
    .replace(/\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/g, " $1/$2 ") // plain fraction
    .replace(/\\pi\b/gi, " π ")
    .replace(/\\circ\b/g, " ° ")
    .replace(/\\[a-zA-Z]+/g, " ")
    .replace(/[{}$]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  // Two DIFFERENTLY-labelled circles ("circle 1 … circle 2", "circle number 1 …
  // circle number 2") ⇒ a compound figure. The label may be written bare or with an
  // explicit "number"/"no."/"#" tag.
  const LABEL = String.raw`\s+(?:number|no\.?|#)?\s*(\d+)`;
  const ordinals = new Set(
    [...text.matchAll(new RegExp(String.raw`\bcircle${LABEL}\b`, "gi"))].map((m) => m[1])
  );
  if (ordinals.size >= 2) return null;
  // Otherwise strip a single ordinal label's number ("circle 2", "circle number 4",
  // "figure 3") so it is not mistaken for the radius/diameter — but KEEP it when a
  // unit follows (a length). Without the "number"/"no."/"#" arm, "the diameter of
  // circle number 4 is 10 cm" leaked the LABEL "4" as the diameter (→ r=2, area 4π).
  text = text.replace(
    new RegExp(
      String.raw`\b(circle|figure|fig|diagram|shape|part|question|q)${LABEL}\b(?!\s*(?:cm|mm|km|m\b|°|deg|metre|meter|inch|feet|foot))`,
      "gi"
    ),
    "$1"
  );
  const lower = text.toLowerCase();

  // A comma glued between digits ("radius 1,000", "12,5 cm") is locale-ambiguous —
  // a thousands separator in en, the decimal separator across the app's many European
  // locales. The two readings differ by orders of magnitude and nothing downstream can
  // disambiguate, so a guess would ship a confidently-wrong verified answer. Decline.
  if (hasLocaleAmbiguousNumber(text)) return null;

  // Parse-integrity: a CHAINED-ARITHMETIC given ("d = 2 × 7 = 14", "radius r = 3 × 4 =
  // 12", "diameter is 4 times 5 = 20") states the value as a mini-calculation. The
  // macro-strip above deletes "\times" to a space ("2 \times 7" → "2 7") and cleanLatex
  // cannot re-derive the product, so the value reader grabs the FIRST operand (2/3/4) as
  // the given — a wrong linear value the verify gate then re-derives from and rubber-
  // stamps. There is no faithful flattening of the arithmetic → decline honestly.
  const chainedGiven =
    /\\(?:times|cdot|ast)\b/.test(rawLatex) ||
    /\b(?:radius|diameter|r|d)\b[^.;]{0,20}\d[\d.\s]*(?:×|✕|·|\*|\btimes\b|multiplied\s+by)\s*\d/i.test(
      lower
    ) ||
    /\b(?:radius|diameter|r|d)\b[^.;]{0,20}=\s*\d[\d.\s]*=\s*\d/i.test(lower);
  if (chainedGiven) return null;

  // A COMPARISON given ("diameter is 3 cm less than 15 cm", "radius 4 cm more than 6 cm",
  // "radius 2 more centimetres than a 10 cm rod") defines the value by arithmetic relative
  // to another number; the reader grabs the delta (2, 3, 4) as the radius/diameter and the
  // verify gate re-derives from that same wrong read. Allow an interposed unit word between
  // the comparator and "than" ("more CENTIMETRES than") — an earlier "\s+than" form required
  // them adjacent and missed it. Decline — nothing here recomputes the comparison.
  if (
    /\b(?:radius|diameter)\b[^.;]{0,40}\b(?:more|less|greater|fewer|longer|shorter|larger|smaller|bigger)\b[^.;0-9]{0,20}\bthan\b/i.test(
      lower
    )
  ) {
    return null;
  }

  // A MULTIPLIER relational ("radius 3 times that of a smaller circle", "diameter 5 times
  // the …") defines the value as a FACTOR of another quantity; the reader binds the bare
  // multiplier (3, 5) as the radius/diameter (shipping 9π for a true 144π). The word-form
  // multipliers (twice/double/triple) are caught by RELATIONAL_GIVEN below; this catches the
  // numeric "N times" form. Decline — the relation is arithmetic nothing downstream redoes.
  if (/\b(?:radius|diameter)\b[^.;]{0,20}\d+(?:\.\d+)?\s*times\b/i.test(lower)) return null;

  // A dimension word bound to a bare COUNT rather than a length ("a diameter of 12 hour
  // markings", "a diameter of 36 spokes") states how many PARTS span the figure, not its
  // size; the real linear measure is the unit-anchored number elsewhere ("… measures 30 cm
  // across", "… is 60 cm across"). The reader grabs the count (12, 36) as the diameter and
  // halves it, ignoring the true cm dimension — a given-misread the verify gate re-derives
  // from. A number glued to a length unit (cm/mm/m/inch/…) is a genuine dimension and is
  // exempted by the negative lookahead; a number followed by any OTHER word is a count →
  // decline honestly rather than ship a figure sized from a part-count.
  if (
    /\b(?:radius|diameter)\s+of\s+\d+(?:\.\d+)?\s+(?!(?:cm|mm|m|km|centimet(?:re|er)s?|millimet(?:re|er)s?|kilomet(?:re|er)s?|met(?:re|er)s?|inch(?:es)?|feet|foot|ft|yards?|in)\b)[a-z]/i.test(
      lower
    )
  ) {
    return null;
  }

  // Parse-integrity: a π (or "pi") inside the LINEAR given ("radius 2π cm", "diameter π m")
  // is an irrational measure. The macro-strip turns "2\pi" → "2 π" and the value reader
  // takes the bare 2, shipping 4π for a true 4π³ area — and the verify gate re-derives from
  // the same misread. There is no faithful flattening of the radical-like π → decline. (A π
  // used as an ANGLE is handled in detectAngleDeg; this guards the LINEAR given.)
  if (/\b(?:radius|diameter|r|d)\b[^.;]{0,12}\d[\d.\s]*(?:π|pi(?![a-z]))/i.test(text)) return null;

  // Must be about a circle (or its arc/sector) — and ONLY a plain, whole circle.
  const mentionsCircle = /\bcircle|\bcircular\b/.test(lower);
  const mentionsArc = /\barc\b/.test(lower);
  const mentionsSector = /\bsector\b/.test(lower);
  if (!mentionsCircle && !mentionsArc && !mentionsSector) return null;
  if (OTHER_SHAPE.test(lower) || INSCRIBED.test(lower)) return null;
  // A "great circle" is the SPHERE's equatorial cross-section and "surface area" is a
  // 3-D quantity; a flat-circle engine that answered either would ship πr² where 4πr²
  // is meant (the gate's "great circle of a spherical ball → surface area" leak).
  if (/\bgreat\s+circle\b/.test(lower) || /\bsurface\s+area\b/.test(lower)) return null;
  if (SOLID_SURFACE.test(lower)) return null;
  if (PARTIAL_COMPOUND.test(lower)) return null;
  if (PARTITIONED_FIGURE.test(lower)) return null;
  if (REMOVED_MATERIAL.test(lower)) return null;
  if (HALF_DISC.test(lower)) return null;

  // A region "enclosed / bounded by an arc AND (the two) radii" is a SECTOR described
  // without the "sector" keyword — a bare πr² ships the whole disc (the "90° angle at the
  // centre" quarter → 36π-not-9π leak). The sector needs its angle applied via the θ/360
  // factor, which this whole-figure area path does not do, so decline. (The diameter-and-arc
  // half-disc form is caught by HALF_DISC just above.)
  if (
    /\b(?:enclosed|bounded)\s+by\b[^.]*\barc\b[^.]*\bradi(?:i|us)\b/i.test(lower) ||
    /\b(?:enclosed|bounded)\s+by\b[^.]*\bradi(?:i|us)\b[^.]*\barc\b/i.test(lower)
  ) {
    return null;
  }

  // A FRACTION of the asked quantity ("half the area", "a third of the area of the
  // circle", "3/4 of the circumference") is a PARTIAL quantity. PARTIAL_COMPOUND only
  // fires when the fraction word sits on "circle/disc"; with "the area of" interposed
  // ("half THE AREA OF the circle") it slips through and the engine ships the FULL πr²
  // (double, triple the true value). Detect the fraction modifier on the target noun
  // itself (area/circumference/perimeter) and decline — this engine sizes whole figures.
  if (
    /\b(?:half|a\s+third|a\s+quarter|a\s+fifth|a\s+sixth|one[\s-](?:half|third|quarter|fifth|sixth)|two[\s-]thirds|three[\s-]quarters?|\d+\s*\/\s*\d+)\s+(?:of\s+)?(?:the\s+|its\s+)?(?:area|circumference|perimeter)\b/i.test(
      lower
    )
  ) {
    return null;
  }

  // A PERCENTAGE of the asked quantity ("50% of the area", "75% of the circumference") is
  // the same partial-quantity ask as the word/ratio fractions above, just written with a
  // percent literal the fraction reader doesn't match. The engine ships the FULL πr² / 2πr,
  // dropping the scale factor (50% → 2× too big, 75% → 4/3× too big). Decline — this engine
  // sizes whole figures, consistent with the fraction-of-quantity guard above.
  if (
    /\b\d+(?:\.\d+)?\s*(?:%|percent)\s+(?:of\s+)?(?:the\s+|its\s+)?(?:area|circumference|perimeter)\b/i.test(
      lower
    )
  ) {
    return null;
  }

  // A sector clause ALONGSIDE an explicit whole-circle ask ("area of the WHOLE
  // circle, given a sector of 120°") is an ambiguous compound: whole area? sector
  // area? the difference? Nothing downstream re-verifies which is meant, and the
  // sector→area target rule would silently apply the θ/360 factor to a whole-circle
  // ask (shipping the sector's value, off by θ/360). Decline rather than guess.
  const wholeCircleAsk =
    /\b(whole|entire|full)\s+circle\b/.test(lower) || /\btotal\s+area\b/.test(lower);
  if (mentionsSector && wholeCircleAsk) return null;

  // A MAJOR / MINOR / REFLEX sector or arc needs the reflex-angle (360−θ) formula and
  // a correct read of WHICH angle is the given vs the asked one — e.g. "the minor
  // sector has central angle 90°, find the MAJOR sector area" wants 270/360, not the
  // given 90/360. Nothing downstream re-verifies that, so applying θ/360 blindly ships
  // the minor value for a major ask (or vice-versa). Decline (honest) rather than guess.
  if (/\b(?:major|minor|reflex)\b/.test(lower) && (mentionsSector || mentionsArc)) return null;

  // Class A — INVERSE problem (given area/circumference, find radius/diameter). The
  // givenRe below only reads a linear given (radius/diameter = N); it CANNOT invert
  // an area or circumference, so it would silently ignore the real given and fabricate
  // a linear value from whatever number it does see (e.g. "area 49π, find radius" →
  // reads nothing linear, or worse mis-binds the 49). The recompute()/verify() gate is
  // blind to this — it re-derives from the SAME misread. Decline: this engine only does
  // the FORWARD direction (linear → area/circumference).
  const asksLinear =
    /\b(?:find|calculate|determine|compute|obtain|give|state|work\s+out)\s+(?:the\s+|a\s+|its\s+)?(?:radius|diameter)\b/i.test(lower)
    || /\bwhat\s+(?:is|'s|are)\s+(?:the\s+)?(?:radius|diameter)\b/i.test(lower);
  const mentionsAreaOrCirc = /\b(?:area|circumference)\b/.test(lower);
  if (asksLinear && mentionsAreaOrCirc) return null;

  // Class B — RELATIONAL given ("the radius is half the diameter of 16 cm", "radius
  // twice the …"). The linear value is defined by a WORD relationship to another
  // quantity, not stated directly; givenRe grabs the trailing number as if it were the
  // radius/diameter itself, off by the relational factor. Nothing re-checks the read.
  const RELATIONAL_GIVEN =
    /\b(?:radius|diameter)\b[^0-9.;]*\b(?:half|twice|double|thrice|triple|third|quarter)\b[^0-9.;]*\d/i;
  if (RELATIONAL_GIVEN.test(lower)) return null;

  // Class E — TWO circles by count (each with its own linear given), phrased so the
  // `\bcircles\b`/ordinal compound guards above miss it ("A circle of radius 5 … another
  // circle of radius 8 … total area"). Two independent linear givens ⇒ a compound
  // figure this single-circle engine would answer for only ONE of them. Decline.
  const linearGivenG = (kw: string) =>
    new RegExp(
      String.raw`\b${kw}\b(?:(?!\b(?:area|circumference|perimeter|radius|diameter)\b)[^0-9=:,;()])*[=:]?\s*(?:${NUMERIC_TOKEN})`,
      "gi"
    );
  const nLinear =
    [...lower.matchAll(linearGivenG("radius"))].length +
    [...lower.matchAll(linearGivenG("diameter"))].length;
  if (nLinear >= 2) return null;

  // A COMPOUND ASK names TWO distinct output quantities — "find the AREA … AND the length
  // of fencing", "the area and the circumference". This engine returns ONE verified
  // quantity; the boundary cue would silently ship only the circumference and drop the
  // explicit area ask (the "area of a garden … and the length of fencing" → 14π-not-49π
  // leak). A DIRECT area ask ("find the area", not the prepositional "around the area")
  // co-occurring with a boundary-length ask is a two-part question → decline honestly.
  const directAreaAsk =
    /\b(?:find|calculate|determine|compute|work\s+out|obtain|give|state|evaluate)\s+(?:the\s+|its\s+|a\s+|an\s+|this\s+)?area\b/.test(
      lower
    ) || /\bwhat\s+(?:is|'s|are)\s+(?:the\s+)?area\b/.test(lower);
  if (
    directAreaAsk &&
    /\band\b[^.?!]*\b(?:circumference|perimeter|(?:length|amount)\s+of\s+(?:fenc\w+|edging|rope|wire|ribbon|border|string|braid|railing|kerb|curb|boundary))\b/.test(
      lower
    )
  ) {
    return null;
  }

  // --- Target quantity (exactly one, unambiguous) -------------------------
  const target = detectTarget(lower, mentionsSector);
  if (!target) return null;

  // An ARC is named AND a central angle is present, yet the target resolved to the whole-
  // circle CIRCUMFERENCE — the "distance/length around [it | its edge | an arc | its arc]"
  // phrasings the arc-length cue (which needs the literal "around the arc") doesn't capture.
  // Shipping 2πr drops the θ/360 factor and answers the whole circle for an arc ask. The
  // genuine arc-length asks ("arc length", "length of the arc") already resolve to
  // arc_length above; this ambiguous residue declines. (No angle ⇒ a real whole-circle
  // circumference that merely mentions an arc → keep.)
  if (target === "circumference" && mentionsArc) {
    const arcAngle = detectAngleDeg(text);
    if (arcAngle !== undefined && arcAngle > 0 && arcAngle < 360) return null;
    // The angle may be in RADIANS (or otherwise unparsed by the degrees-only reader, which
    // returns undefined); an arc that STILL carries a "subtends …", radian, or named-angle
    // clause is an arc-length ask (rθ) that this circumference target would over-ship as the
    // whole 2πr — the "π/3 radians … distance around the edge of the arc" → 12π-not-2π leak.
    // (A bare arc with NO angle clause is a genuine whole-circle circumference → keep above.)
    if (
      /\bsubtends?\b/i.test(lower) ||
      /\bradians?\b|\brad\b/i.test(lower) ||
      /\b(?:central|sector)\s+angle\b/i.test(lower)
    ) {
      return null;
    }
  }

  // "area of the/an arc" is ill-posed — an arc is a 1-D curve and has no area. The
  // reader would ship πr² (or a sector value); neither is what "area of the arc" names.
  // Decline honestly rather than answer a malformed ask.
  if (/\barea\s+of\s+(?:the\s+|an?\s+)?arc\b/.test(lower)) return null;

  // "circumference / perimeter OF THE ARC" is equally ill-posed — an arc is an open curve
  // with no circumference, and "perimeter of an arc" names no single figure. The reader
  // lands on the bare circumference/perimeter token, ships the WHOLE circle 2πr, and drops
  // the stated central angle (the "circumference of the arc … 90°" → 20π-not-5π leak).
  // Decline; the arc length is asked as "arc length" / "length of the arc", not this.
  if (/\b(?:circumference|perimeter)\s+of\s+(?:the\s+|an?\s+)?arc\b/.test(lower)) return null;

  // A DANGLING central angle on a WHOLE-circle area ask — with no "sector"/"arc" noun to
  // host it ("Find the area of a circle radius 6 … central angle 60") — is ambiguous: the
  // angle goes unused, so a SECTOR is almost certainly meant. Shipping πr² silently drops
  // the stated angle. Decline. (When a SECTOR/ARC noun IS present, the angle belongs to
  // that feature and "area of the circle" is an unambiguous whole-disc ask → keep.)
  if (target === "area" && !mentionsSector && !mentionsArc) {
    const stray = detectAngleDeg(text);
    if (stray !== undefined && stray > 0 && stray < 360) return null;
  }

  // --- The linear given: radius XOR diameter ------------------------------
  // The value may be a fraction/mixed number; the display unit is captured from
  // RIGHT BESIDE the number, so a distractor length elsewhere ("a path 2 m wide")
  // can never lend its unit to the answer.
  // The old reader grabbed the FIRST number after the keyword — which is a DISTRACTOR
  // whenever the real value trails a narrative number ("the diameter of a circular
  // table seating 4 people is 120 cm" shipped d=4, not 120). Read in three tiers:
  //   A) ADJACENCY — the value sits on the keyword through only short linking words
  //      (of / is / = / measures …). No distractor number can hide inside a whitelisted
  //      connector, so "radius 7", "radius of 7", "radius = 7 cm" read cleanly, and
  //      "radius 7 cm … the temperature is 20°" still takes 7 (never the far 20).
  //   B) PREDICATION — the value is asserted of the keyword by an "is/=/measures" LATER
  //      in the SAME clause; the span may cross a narrative number but NOT a comma /
  //      semicolon / period, so "…seating 4 people is 120 cm" → 120 while a value walled
  //      off by a comma-parenthetical ("diameter, on a 4 mm grid, is 20 cm") stays
  //      ambiguous → no match → decline.
  //   C) SYMBOL — the bare "r = 7" / "d = 10" form.
  // (This anchoring lives in the shared nl/quantity reader, reused by every engine.)
  const radiusRead = readBoundValue(lower, "radius", { symbol: "r", unitSrc: UNIT_SRC });
  const diameterRead = readBoundValue(lower, "diameter", { symbol: "d", unitSrc: UNIT_SRC });

  const hasR = radiusRead !== null;
  const hasD = diameterRead !== null;
  // Need exactly one named linear given. Both separately named is ambiguous → decline.
  if (hasR === hasD) return null;

  const read = (hasR ? radiusRead : diameterRead)!;
  const givenValue = read.value;
  if (!Number.isFinite(givenValue) || givenValue <= 0) return null;
  const givenKind: "radius" | "diameter" = hasR ? "radius" : "diameter";
  const radius = hasR ? givenValue : givenValue / 2;
  if (!Number.isFinite(radius) || radius <= 0) return null;
  const unit = read.unitRaw ? normalizeUnit(read.unitRaw) : null;

  // A "find the radius/diameter" target from a radius/diameter given is a no-op
  // mis-parse — the target must differ from what was handed in.
  if (target === "diameter" && givenKind === "diameter") return null;

  // --- Central angle (arc length / sector area only) ----------------------
  let angleDeg: number | undefined;
  if (target === "arc_length" || target === "sector_area") {
    angleDeg = detectAngleDeg(text);
    if (angleDeg === undefined || angleDeg <= 0 || angleDeg > 360) return null;
  }

  return { target, radius, givenKind, givenValue, angleDeg, unit };
}

/** Which single quantity is asked. Returns null if zero or several match. */
function detectTarget(
  lower: string,
  mentionsSector: boolean
): CircleTarget | null {
  // "arc length", "length of the arc", and the descriptive "distance/length around (or
  // along) the arc" all ask for ARC LENGTH. The last phrasing shares the word "around"
  // with circumference, so it MUST be claimed here (and excluded from wantsCirc below),
  // else it ships the whole circumference 2πr for an arc ask (dropping the θ/360 factor).
  const wantsArc =
    /\barc\s+length\b|\blength\s+of\s+(?:the\s+)?arc\b/.test(lower) ||
    /\b(?:distance|length|way)\s+(?:all\s+the\s+way\s+)?a?round\s+(?:the\s+)?arc\b/.test(lower) ||
    /\b(?:distance|length)\s+along\s+(?:the\s+)?arc\b/.test(lower);
  // Disambiguate WHICH area is asked. "sector area" / "area of the sector" is the
  // sector; "area of the circle" is the whole disc; a bare "area" with a sector
  // clause present is genuinely ambiguous (whole? sector? the difference?) and is
  // declined below rather than silently applying the θ/360 sector factor to a
  // whole-circle ask (the "Find the area of the circle" ⇒ 25π-not-100π leak).
  // The possessive "the circle's sector" has "sector" as its head noun (the sector is
  // asked), but "area of the circle['s]" substring-matched the whole-circle pattern
  // (the \b after "circle" lands on the apostrophe) and dropped the θ/360 factor —
  // shipping πr² for a sector ask. Let the sector pattern absorb an interposed
  // possessive ("circle's sector"), and forbid the whole-circle pattern from firing
  // when "'s sector" follows, so the sector target wins.
  // "circle sector" (spaced compound) and "circle's sector" both name the SECTOR as the
  // head noun. Absorb an interposed "circle['s] " before "sector" so the sector target
  // wins; without it "area of the circle sector" matched the whole-circle pattern and
  // shipped πr² (dropping θ/360) — the 36π-not-9π leak. Correspondingly forbid the
  // whole-circle pattern when a bare or possessive "sector" follows "circle".
  const asksSectorArea =
    /\bsector(?:'s|s)?\s+area\b|\barea\s+of\s+(?:the\s+|a\s+|its\s+)?(?:circle['’]?s?\s+)?sector\b/.test(
      lower
    );
  const asksCircleArea =
    /\barea\s+of\s+(?:the\s+|a\s+|its\s+)?circle\b(?!(?:['’]?s)?\s+sector)/.test(lower) ||
    /\bcircle(?:'s|s)?\s+area\b/.test(lower);
  // "area" counts ONLY when it is the ASKED OBJECT — the direct object of the ask verb
  // ("find the area", "what is the area") or "area of the circle/sector" / "the
  // circle['s]/sector['s] area". A DESCRIPTIVE "area" that merely NAMES the region — "a
  // large grassy area", "covers an area", and crucially "a circular AREA" (a synonym for
  // the disc) — is scenery, not the ask. The old `find…[^.?]*area` spanned the whole
  // clause, so "Find the BOUNDARY of a circular area" and "Find the LENGTH AROUND the
  // circular area" both matched `find … area` and shipped πr² for a circumference ask.
  // Requiring "area" to sit right after the verb (through a determiner only) makes the
  // asked object decide, so a "circular area" naming-phrase no longer fires wantsArea.
  // A BOUNDARY-LENGTH ask names the perimeter through the physical thing laid along it
  // ("find the length of fencing to go around it") — the asked quantity is a LENGTH
  // (circumference), and any "area" in the sentence is the enclosed region it borders.
  // The cue MUST be governed by the ask verb in the SAME sentence: a "fencing" mention in
  // a SEPARATE descriptive clause ("Find the area … the amount of fencing was recorded
  // separately", "… fencing runs around it") is scenery, and earlier looser forms of this
  // cue matched it there and wrongly suppressed the explicit "Find the area", shipping
  // circumference. Requiring "<ask verb> … length/amount of fencing" within one sentence
  // (no . ? ! between) ties the boundary length to the actual ask.
  // An explicit DIRECT area ask ("find the AREA of …", "what is the area of …", "the
  // circle's area") makes area the ask verb's OBJECT; a boundary-length phrase in a
  // SUBORDINATE clause ("… a circular garden THAT NEEDS a length of ribbon around it") is
  // then scenery, not the ask. Without this the greedy boundaryCue below spans [^.?!]* into
  // the relative clause and ships circumference for an explicit area ask. (A genuine
  // TWO-part "area AND length of fencing" ask is a compound and is declined earlier.)
  const directAreaObjectAsk =
    /\b(?:find|calculate|determine|compute|work\s+out|obtain|give|state|evaluate)\s+(?:the\s+|its\s+|a\s+|an\s+|this\s+)?area\s+of\b/.test(
      lower
    ) ||
    /\bwhat\s+(?:is|'s|are)\s+(?:the\s+)?area\s+of\b/.test(lower) ||
    /\b(?:circle|sector|disc|disk)(?:'s|’s)?\s+area\b/.test(lower);
  const boundaryCue =
    !directAreaObjectAsk &&
    /\b(?:find|calculate|determine|compute|work\s+out|obtain|what\s+is|what's|how\s+much|how\s+long)\b[^.?!]*\b(?:length|amount)\s+of\s+(?:fenc\w+|edging|rope|wire|ribbon|tape|trim|border|string|braid|railing|kerb|curb)\b/.test(
      lower
    );
  const wantsArea =
    !boundaryCue &&
    (/\b(?:find|calculate|determine|compute|work\s+out|obtain|give|state|evaluate)\s+(?:the\s+|its\s+|a\s+|an\s+|this\s+)?area\b/.test(
      lower
    ) ||
      /\bwhat\s+(?:is|'s|are)\s+(?:the\s+)?area\b/.test(lower) ||
      /\barea\s+of\s+(?:the\s+|a\s+|an\s+|its\s+|this\s+|each\s+)?(?:circle|sector|disc|disk)\b/.test(
        lower
      ) ||
      /\b(?:circle|sector)(?:'s|’s|s)?\s+area\b/.test(lower));
  // The area/perimeter of a NON-circle region (an annular path / ring / band that
  // borders the circle) is a compound figure this engine cannot compute — a bare
  // πr² would answer the inner disc, not the region. Decline.
  // Allow an interposed adjective ("area of the CIRCULAR path", "a running track") — the
  // old pattern required the region noun to sit right after the determiner, so "area of
  // the circular path" slipped through and shipped the inner disc's πr² for the annulus.
  const asksRegionArea =
    /\b(?:area|perimeter)\s+of\s+(?:the\s+|a\s+|its\s+)?(?:[a-z]+\s+){0,2}(?:path|border|ring|annulus|region|band|track|walkway|margin|frame|rim|lane|road|gap|space)\b/.test(
      lower
    );
  if (asksRegionArea) return null;
  // Circumference is also asked as "the distance around", "the length of the boundary",
  // "the perimeter/boundary length" — the old reader only knew the literal word
  // "circumference"/"perimeter", so those phrasings fell through to a wrong (or absent)
  // target. A sector's boundary is arc + 2 radii, NOT the circumference, so the
  // descriptive phrasings only count for a WHOLE circle (guard on !mentionsSector).
  // A SECTOR has no "circumference" — its boundary is arc + 2 radii. The literal token
  // was ungated, so "circumference of a sector" shipped 2πr (the whole circle). Gate it
  // behind !mentionsSector like every other circumference cue; a sector-circumference ask
  // then finds no target and declines.
  const wantsCirc =
    !mentionsSector &&
    (/\bcircumference\b/.test(lower) ||
      boundaryCue ||
        /\b(?:distance|length|way)\s+(?:all\s+the\s+way\s+)?a?round\b(?!\s+(?:the\s+)?arc\b)/.test(lower) ||
        /\baround\s+(?:the\s+|its\s+|a\s+)?(?:circle|circular|disc|disk|edge|rim|boundary|plot|garden|pond|region|outside)\b/.test(
          lower
        ) ||
        /\b(?:length|distance)\s+of\s+(?:the\s+|its\s+|a\s+)?(?:boundary|perimeter|edge|rim|circumference)\b/.test(
          lower
        ) ||
        /\bboundary\s+of\b/.test(lower) ||
        /\b(?:boundary|perimeter)\s+length\b/.test(lower) ||
        /\bperimeter\b/.test(lower));
  // "diameter" is the ASKED quantity only when it is NOT a given — a diameter
  // immediately followed by a number ("with diameter 10", "diameter = 10") is the
  // GIVEN, not the target. Without this guard "Calculate the AREA of a circle with
  // diameter 10" reads "calculate…diameter" as a second target and wrongly declines.
  const diameterIsGiven = /\bdiameter\b[^0-9=:]*[=:]?\s*-?\d/.test(lower);
  const wantsDiameter =
    !diameterIsGiven &&
    /\bdiameter\b.*\?|\bfind\b[^.]*\bdiameter\b|\bcalculate\b[^.]*\bdiameter\b/.test(
      lower
    );

  const hits: CircleTarget[] = [];
  if (wantsArc) hits.push("arc_length");
  if (wantsArea) {
    // An explicit sector-area ask wins; an explicit circle-area ask is the whole
    // disc; a plain circle (no sector) is its own area. A bare "area" alongside a
    // sector clause is ambiguous → decline.
    if (asksSectorArea) hits.push("sector_area");
    else if (asksCircleArea) hits.push("area");
    else if (!mentionsSector) hits.push("area");
    else return null;
  }
  if (wantsCirc) hits.push("circumference");
  if (wantsDiameter) hits.push("diameter");

  // Exactly one distinct target keeps the read unambiguous.
  const distinct = [...new Set(hits)];
  return distinct.length === 1 ? distinct[0] : null;
}

/**
 * A central angle in DEGREES ("60°", "angle of 60 degrees", "central angle 90").
 * A RADIAN angle is declined: nothing downstream re-verifies the angle read (the
 * internal recompute reuses the SAME angle), so a misread radian would ship
 * silently — and the old π-stripping flatten misread "π/3" as 3°. An honest
 * decline is the safe outcome.
 */
function detectAngleDeg(text: string): number | undefined {
  // 1) An explicit "radian"/"rad" WORD is decisive → decline. No degree problem says
  //    "radian", so this never over-declines a real degree case. GRADIANS (gons) are a
  //    third angular unit (100 gon = 90°); the reader would take "100 gradians" as 100° and
  //    ship a confident wrong angle, so decline them too — this engine reads degrees only.
  if (/\bradians?\b|\brad\b/i.test(text)) return undefined;
  if (/\bgradians?\b|\bgons?\b|\bgrads?\b/i.test(text)) return undefined;

  // 1a) An angle "at the circumference" is an INSCRIBED angle — half the central angle by
  //     the inscribed-angle theorem — not the central angle a sector/arc formula needs.
  //     The reader takes the stated degrees as central and ships exactly half (or double)
  //     the true value. Converting inscribed→central (×2) is a read nothing downstream
  //     verifies, so decline honestly. (The central angle is stated "at the centre".)
  if (/\bat\s+the\s+circumference\b/i.test(text)) return undefined;

  // 1b) DEGREES-MINUTES(-SECONDS) notation ("30 degrees 45 minutes", "30° 45'") — the
  //     degree reader keeps only the whole-degree part and silently drops the arcminutes/
  //     arcseconds (30°45′ read as 30°, ~2.5% low). The minutes/seconds sit RIGHT AFTER
  //     the degree number (digits/whitespace only between), so this never fires on a
  //     narrative time ("… 30 degrees. It ran for 45 minutes"). Decline honestly.
  if (
    /\d\s*(?:°|degrees?|deg\b)[\s,]*(?:and\s+)?\d+\s*(?:['′]|minutes?\b|arcmin\w*)/i.test(text) ||
    /\d\s*['′][\s,]*(?:and\s+)?\d+\s*(?:''|″|seconds?\b|arcsec\w*)/i.test(text)
  ) {
    return undefined;
  }

  // 1b-2) A bare ARCMINUTE / ARCSECOND angle ("central angle 120 minutes", "angle of 36'")
  //   with NO whole-degree part is measured in minutes/seconds OF ARC — a unit this
  //   degrees-only engine cannot convert. Worse, the value reader drops the last digit when
  //   it rejects the "minutes" trailer ("120 minutes" → 12, "36 minutes" → 3), shipping a
  //   fabricated angle. The minute/second unit must sit on the ANGLE's OWN number
  //   (adjacency only) AND no degree token may be present, so a narrative TIME offset
  //   ("central angle after 2 seconds is 120 degrees" — which carries "degrees") is
  //   untouched. Decline honestly. (A degrees+minutes DMS pair is handled at 1b above.)
  if (
    !/°|\bdegrees?\b|\bdeg\b/i.test(text) &&
    /\b(?:central\s+angle|sector\s+angle|angle)\b\s*(?:of|=|:|is|measures?|measuring|equal\s+to)?\s*\d+(?:\.\d+)?\s*(?:['′]|minutes?\b|arcmin\w*|''|″|seconds?\b|arcsec\w*)/i.test(
      text
    )
  ) {
    return undefined;
  }

  // 1c) A REVOLUTION-unit angle ("1/2 turn", "1/6 revolution", "1/4 rev", "0.75 rotations")
  //     measures the angle in FULL TURNS (×360°), not degrees. The fraction reader mis-splits
  //     "1/2 turn" and grabs a bare "1" as 1°, shipping an angle off by ×360. This engine has
  //     no revolution→degree conversion the verify gate can re-check, so decline honestly. The
  //     number must sit RIGHT ON the unit, so a narrative "a wheel turns" (no number) is safe.
  if (/\b(?:\d+\s*\/\s*\d+|\d+(?:\.\d+)?)\s*(?:turns?|revs?|revolutions?|rotations?)\b/i.test(text)) {
    return undefined;
  }

  // 2) ANY π used as an angle VALUE ⇒ radians ⇒ decline — checked UP FRONT, before a
  //    reader can strip the π and mis-read the bare coefficient as degrees ("1.5π" →
  //    "1.5°", "0.5π" → "0.5°"; the π-forms the old ANGVAL alternation failed to keep).
  //    A "take π = 3.14" / "π = 22/7" clause merely DEFINES π's numeric value, so strip
  //    that definition first; ANY π/"pi" surviving (π/3, 2π/3, 1.5π, a bare π) is a
  //    radian angle nothing downstream can verify → decline.
  //    "pi" is matched when it is not part of a larger word ("pizza", "spiral") but
  //    INCLUDING a digit-glued form ("2pi/3", "2pi") — a bare `\bpi\b` needs a word boundary
  //    the "2p" junction does not have, so "central angle 2pi/3" slipped the guard and
  //    shipped 1/10 π (the angle read as a bare 2°) instead of declining as radians.
  const PI_TOKEN = String.raw`π|(?<![a-z])pi(?![a-z])`;
  const withoutPiDef = text.replace(
    new RegExp(String.raw`(?:${PI_TOKEN})\s*[=≈:]\s*\d[\d.\/]*`, "gi"),
    " "
  );
  if (new RegExp(String.raw`(?:${PI_TOKEN})`, "i").test(withoutPiDef)) return undefined;

  // 2b) A RELATIONAL angle — "half of 120°", "1/4 of a full turn", "two-thirds of a
  //     revolution", "1/3 of 90 degrees", "2/3 of a right angle" — is not a directly-
  //     stated measure. The reader would grab the literal number ("120", "1/3") and ship
  //     a wrong angle; computing the relation is a mis-read nothing downstream verifies.
  //     Both the fraction-word forms and a literal "a/b of …", and both "of a full turn"
  //     and "of a right angle", are declined. Honest decline rather than guess.
  if (
    /\b(?:half|third|quarter|fifth|sixth|two[\s-]thirds|three[\s-]quarters?|\d+\s*\/\s*\d+)\s+of\b/i.test(
      text
    ) ||
    /\bof\s+(?:a\s+|one\s+)?(?:full|complete|whole)\s+(?:turn|revolution|rotation|circle)\b/i.test(text) ||
    /\bof\s+(?:a\s+|one\s+)?right\s+angle\b/i.test(text)
  ) {
    return undefined;
  }

  // 3) NAMED — the value ANCHORED to the "central angle" phrase, read by the shared
  //    quantity reader (adjacency / predication). A number glued to a foreign TIME /
  //    COUNT / LENGTH unit ("after 2 seconds", "3 sides", "20 cm") is rejected as a
  //    distractor, so the reader returns the true angle ("central angle 60" → 60,
  //    "central angle after 2 seconds is 120 degrees" → 120). Because it is anchored to
  //    the angle's OWN name, a name-anchored value outranks a stray degree-marked number
  //    on another noun ("central angle 60 … the oven is set to 200 degrees" → 60, not 200).
  const NON_ANGLE_UNIT = String.raw`seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?|people|persons?|students?|players?|sides?|turns?|revolutions?|laps?|rounds?|cm|mm|km|metres?|meters?|inch(?:es)?|feet|foot`;
  const named =
    readBoundValue(text, "central angle", { rejectTrailer: NON_ANGLE_UNIT })?.value ??
    readBoundValue(text, "sector angle", { rejectTrailer: NON_ANGLE_UNIT })?.value ??
    null;

  // 4) MARKED — numbers welded to the DEGREE unit, minus compass / thermal / bearing
  //    distractors ("bearing of 60°", "35° north", "300° Celsius", "oven set to 200°") and
  //    ORIENTATION distractors — a degree describing how the whole figure is TILTED / sloped
  //    / rotated in space ("inclined at 30°", "the page is tilted 25°", "a ramp rises at 30°")
  //    is never the sector's central angle; it must lose to the stated "angle N".
  const marked = readUnitAnchoredValues(text, {
    valueSrc: NUMERIC_TOKEN,
    unitSrc: String.raw`°|degrees?|deg\b`,
    disqualifyTrailer: String.raw`\s*(?:north|south|east|west|[nsew]\b|celsius|centigrade|fahrenheit|[cf]\b)`,
    distractorCtx:
      /\b(?:bearing|latitude|longitude|azimuth|heading|temperature|thermostat|oven|compass|inclin\w*|tilt\w*|slop\w*|slant\w*|lean\w*|rotat\w*|ramp|page|banked?|pitched?|elevat\w*|depress\w*|view\w*|observ\w*|sunlight|sunbeam|sun|light|ray|beam|glare|glanc\w*|sight|camera|eye|incidence|incident|watch\w*|look\w*)\b/i,
  });

  // 5) CENTRAL (legacy phrase reader) — for the "angle at the centre" / "subtends an
  //    angle of N … centre" phrasings the named reader above doesn't cover. The gap
  //    stops before a digit / clause boundary / radius-diameter word so it never reaches
  //    an unrelated number. (π is already handled at step 2, so NUMERIC_TOKEN is enough.)
  const GAP = String.raw`(?:(?!\bradius\b|\bdiameter\b|[.,;\d])[\s\S])*?`;
  const central =
    text.match(
      new RegExp(
        String.raw`\bangle\s+at\s+(?:the\s+)?cent(?:re|er)\b${GAP}(${NUMERIC_TOKEN})`,
        "i"
      )
    ) ??
    text.match(
      new RegExp(
        String.raw`\bsubtends?\s+(?:an?\s+angle\s+of\s+)?(${NUMERIC_TOKEN})\b[^.]*?\bcent(?:re|er)\b`,
        "i"
      )
    );
  const centralVal = central ? parseNumericToken(central[1].trim()) : null;

  // PRECEDENCE:
  //  • Two or more degree-marked numbers ⇒ genuinely ambiguous ⇒ decline.
  //  • A value anchored to the angle's OWN name wins (it is the most specific signal) —
  //    both the "central/sector angle" reader AND the definitional "at the centre" /
  //    "subtends N … centre" phrase outrank a stray degree-marked number on a DIFFERENT
  //    object ("a nearby ramp rises at 30°", "declination 15°"), which is a distractor.
  //  • Else a single degree-marked number is the angle.
  //  • Else the generic "angle N" fallback.
  if (marked.length >= 2) return undefined;
  if (named !== null && Number.isFinite(named)) return named;
  if (centralVal !== null && Number.isFinite(centralVal)) return centralVal;
  if (marked.length === 1) return marked[0];
  // A plain number in an "angle …" phrase, read as degrees — the number must sit
  // DIRECTLY on the "angle" word (optional connector only), so a missing angle declines
  // instead of borrowing a far-off radius value.
  const fallback = text.match(
    new RegExp(
      String.raw`\bangle\b\s*(?:of|is|are|was|=|:|measuring|equal\s+to|equals)?\s*(${NUMERIC_TOKEN})\b`,
      "i"
    )
  );
  if (fallback) {
    const v = parseNumericToken(fallback[1]);
    if (v !== null && Number.isFinite(v)) return v;
  }
  return undefined;
}

function normalizeUnit(u: string): string {
  const m = u.toLowerCase();
  if (m === "cm" || /^cent/.test(m)) return "cm";
  if (m === "mm" || /^milli/.test(m)) return "mm";
  if (m === "km" || /^kilo/.test(m)) return "km";
  if (m === "m" || /^met/.test(m)) return "m";
  if (/^inch/.test(m)) return "in";
  if (/^f/.test(m)) return "ft"; // feet / foot
  return m;
}

/**
 * Solve deterministically. The answer is EXACT π-form; an INTERNAL verify re-checks
 * the rendered value against an independent numeric recompute so a formatting slip
 * can never ship a wrong number — a failed check returns null (→ honest decline),
 * exactly like the enumerate-and-verify trig engine. Returns MethodData directly
 * (the steps are self-contained; no LLM narration is needed or wanted).
 */
export function solveCircle(
  spec: CircleSpec
): { answer: FinalAnswer; methods: MethodData[] } | null {
  const { target, radius, angleDeg } = spec;
  const PI = Math.PI;

  // (coefficient of π, numeric value, squared-unit?) for each target.
  let piCoeff: number; // exact rational coefficient k so value = k·π (or plain k for diameter)
  let usesPi: boolean;
  let squaredUnit: boolean;
  let value: number;
  let label: string;

  switch (target) {
    case "area":
      piCoeff = radius * radius;
      usesPi = true;
      squaredUnit = true;
      value = PI * radius * radius;
      label = "Area of the circle";
      break;
    case "circumference":
      piCoeff = 2 * radius;
      usesPi = true;
      squaredUnit = false;
      value = 2 * PI * radius;
      label = "Circumference of the circle";
      break;
    case "diameter":
      piCoeff = 2 * radius; // radius given → diameter = 2r (no π)
      usesPi = false;
      squaredUnit = false;
      value = 2 * radius;
      label = "Diameter of the circle";
      break;
    case "arc_length":
      if (angleDeg === undefined) return null;
      piCoeff = 2 * radius * (angleDeg / 360);
      usesPi = true;
      squaredUnit = false;
      value = 2 * PI * radius * (angleDeg / 360);
      label = "Arc length";
      break;
    case "sector_area":
      if (angleDeg === undefined) return null;
      piCoeff = radius * radius * (angleDeg / 360);
      usesPi = true;
      squaredUnit = true;
      value = PI * radius * radius * (angleDeg / 360);
      label = "Sector area";
      break;
    default:
      return null;
  }
  if (!Number.isFinite(value)) return null;

  const unitTex = spec.unit ? `\\,\\text{${spec.unit}}${squaredUnit ? "^2" : ""}` : "";
  const unitPlain = spec.unit ? ` ${spec.unit}${squaredUnit ? "²" : ""}` : "";

  const exact = usesPi
    ? piCoeffLatex(piCoeff)
    : { latex: trim(piCoeff), plain: trim(piCoeff), rendered: Number(trim(piCoeff)) };
  const decimal = trim(Number(value.toFixed(4)));

  const answer: FinalAnswer = usesPi
    ? {
        latex: `${exact.latex}${unitTex} \\approx ${decimal}${unitTex}`,
        plain: `${exact.plain}${unitPlain} ≈ ${decimal}${unitPlain}`,
      }
    : {
        latex: `${exact.latex}${unitTex}`,
        plain: `${exact.plain}${unitPlain}`,
      };

  // Golden-rule gate (INTERNAL): an independent recompute of the SAME quantity from
  // the raw given, plus a check that the rendered exact coefficient really equals
  // that value. A wrong formula or a mis-rendered coefficient fails here → decline.
  const recomputed = recompute(spec);
  if (recomputed === null) return null;
  if (Math.abs(recomputed - value) > 1e-9 * (1 + Math.abs(value))) return null;
  const rendered = usesPi ? piCoeff * PI : piCoeff;
  if (Math.abs(rendered - value) > 1e-9 * (1 + Math.abs(value))) return null;
  // The float check above trusts full precision; the DISPLAYED exact coefficient
  // can still round wrong (a tiny 1.52e-6 shown as "0.000002π", +31% off). Re-check
  // the value the rendered string actually represents, and decline if it drifts.
  const renderedValue = usesPi ? exact.rendered * PI : exact.rendered;
  if (Math.abs(renderedValue - value) > 1e-6 * (1 + Math.abs(value))) return null;
  // A non-zero value whose 4-d.p. decimal collapses to 0 would display "≈ 0" — an
  // unusable, misleading answer. Decline rather than ship it.
  if (Math.abs(value) > 1e-9 && Number(decimal) === 0) return null;

  const methods = buildMethods(spec, label, exact, decimal, unitTex);
  return { answer, methods };
}

/** Recompute the target from the given via the canonical formula (independent of
 * the display path), for the verify() cross-check. */
function recompute(spec: CircleSpec): number | null {
  const { target, radius, angleDeg } = spec;
  const PI = Math.PI;
  switch (target) {
    case "area":
      return PI * radius ** 2;
    case "circumference":
      return PI * (2 * radius); // C = πd
    case "diameter":
      return radius + radius; // 2r via addition (a genuinely different path)
    case "arc_length":
      return angleDeg === undefined ? null : (angleDeg / 360) * (2 * PI * radius);
    case "sector_area":
      return angleDeg === undefined ? null : (angleDeg / 360) * (PI * radius ** 2);
    default:
      return null;
  }
}

/** Render k·π exactly: integer or simple fraction coefficient, else decimal·π.
 * `rendered` is the numeric coefficient the STRING actually represents, so the
 * caller can gate on the displayed value (not just the full-precision float). */
function piCoeffLatex(k: number): { latex: string; plain: string; rendered: number } {
  if (Math.abs(k) < 1e-12) return { latex: "0", plain: "0", rendered: 0 };
  const c = coeffStrings(k);
  if (c.isOne) return { latex: `\\pi`, plain: `π`, rendered: 1 };
  if (c.isNegOne) return { latex: `-\\pi`, plain: `-π`, rendered: -1 };
  if (c.frac) {
    return {
      latex: `${c.frac.sign}\\tfrac{${c.frac.n}}{${c.frac.d}}\\pi`,
      plain: `${c.frac.sign}${c.frac.n}/${c.frac.d} π`,
      rendered: (c.frac.sign === "-" ? -1 : 1) * (c.frac.n / c.frac.d),
    };
  }
  return { latex: `${c.decimal}\\pi`, plain: `${c.decimal}π`, rendered: Number(c.decimal) };
}

/** Classify a coefficient as ±1, a small fraction, or a decimal. */
function coeffStrings(k: number): {
  isOne: boolean;
  isNegOne: boolean;
  frac: { sign: string; n: number; d: number } | null;
  decimal: string;
} {
  if (Math.abs(k - 1) < 1e-12) return { isOne: true, isNegOne: false, frac: null, decimal: "1" };
  if (Math.abs(k + 1) < 1e-12) return { isOne: false, isNegOne: true, frac: null, decimal: "-1" };
  if (Number.isInteger(k)) {
    return { isOne: false, isNegOne: false, frac: null, decimal: String(k) };
  }
  try {
    const fr = fraction(Number(k.toFixed(10))) as unknown as {
      n: bigint;
      d: bigint;
      s: number;
    };
    const n = Number(fr.n);
    const d = Number(fr.d);
    if (d !== 1 && d <= 10000) {
      return {
        isOne: false,
        isNegOne: false,
        frac: { sign: fr.s < 0 ? "-" : "", n, d },
        decimal: trim(k),
      };
    }
  } catch {
    /* fall through to decimal */
  }
  return { isOne: false, isNegOne: false, frac: null, decimal: trim(k) };
}

function buildMethods(
  spec: CircleSpec,
  label: string,
  exact: { latex: string; plain: string },
  decimal: string,
  unitTex: string
): MethodData[] {
  const { target, radius, givenKind, givenValue, angleDeg } = spec;
  const formula: Record<CircleTarget, string> = {
    area: `A = \\pi r^2`,
    circumference: `C = 2\\pi r`,
    diameter: `d = 2r`,
    arc_length: `\\ell = 2\\pi r \\cdot \\dfrac{\\theta}{360}`,
    sector_area: `A = \\pi r^2 \\cdot \\dfrac{\\theta}{360}`,
  };
  const formulaWhy: Record<CircleTarget, string> = {
    area: "Every circle's area is π times the square of its radius.",
    circumference: "The distance around a circle is 2π times its radius.",
    diameter: "The diameter spans the circle: twice the radius.",
    arc_length:
      "An arc is the fraction θ/360 of the whole circumference 2πr.",
    sector_area: "A sector is the fraction θ/360 of the whole area πr².",
  };
  const givenStep =
    givenKind === "diameter"
      ? `d = ${trim(givenValue)} \\Rightarrow r = ${trim(radius)}`
      : `r = ${trim(radius)}`;
  const subWhy =
    givenKind === "diameter"
      ? `The diameter is given, so halve it to get the radius r = ${trim(radius)}.`
      : `Substitute the given radius r = ${trim(radius)}${
          angleDeg !== undefined ? ` and angle θ = ${trim(angleDeg)}°` : ""
        }.`;

  const steps = [
    {
      expression: formula[target],
      operation: "Formula",
      why: formulaWhy[target],
    },
    {
      expression:
        angleDeg !== undefined
          ? `${givenStep},\\; \\theta = ${trim(angleDeg)}^\\circ`
          : givenStep,
      operation: "Substitute the given values",
      why: subWhy,
    },
    {
      expression: `${exact.latex}${unitTex} \\approx ${decimal}${unitTex}`,
      operation: "Result — exact, then to 4 d.p.",
      why: `The exact value is ${exact.plain}; π kept exact, then evaluated to ${decimal}.`,
    },
  ];

  return [{ id: "circle_mensuration", name: label, examPick: true, steps }];
}

/** Trim floating fuzz: `12.250000001` → `12.25`, `7` → `7`. Plain `toFixed(6)`
 * silently rounds a sub-1e-6 magnitude to `0` / `0.000002`, which would ship a
 * WRONG exact display for a tiny coefficient (1.52e-6 shown as "0.000002"); for
 * |n| < 1e-3 keep significant figures instead so the value survives. The caller's
 * rendered-coefficient gate then declines anything that still can't be shown. */
function trim(n: number): string {
  if (Number.isInteger(n)) return String(n);
  const abs = Math.abs(n);
  if (abs > 0 && abs < 1e-3) return String(Number(n.toPrecision(6)));
  return String(Number(n.toFixed(6)));
}
