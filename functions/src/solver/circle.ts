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
import { findAskClause, findAskObject } from "./nl/ask";
import {
  canonicalizeExponents,
  hasAmbiguousNumberGrouping,
  maskReferenceLabels,
  normalizeNumericGlyphs,
  NUMERIC_TOKEN,
  parseNumericToken,
  texMacro,
} from "./nl/numeric";
import {
  countMentions,
  isSubordinate,
  readBoundValue,
  dimensionOwner,
  readBoundValues,
  mainClauseMatches,
  NON_LENGTH_UNIT,
  readSpanReadings,
  readUnitAnchoredValues,
} from "./nl/quantity";
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
// The ADJECTIVE forms matter as much as the nouns: "a RECTANGULAR sheet … a circle is cut
// from it" and "a HEXAGONAL tile has a circle stamped on it" both ask for the OTHER figure's
// area, and a noun-only gate let them through to a bare πr² (the circle's own area shipped
// for the card/tile). List the -al/-ular adjectives alongside their nouns.
const OTHER_SHAPE =
// The polygon list stopped at "decagon", so a REGULAR DODECAGON with an inscribed circle read
// as a plain circle problem and shipped the circle's own 49π for the polygon's area. Any
// -gon is another figure; list the rest of the names and the generic "n-gon" form with them.
  /\b(\d+-gon|n-gon|triangle|triangular|square|rectangle|rectangular|rhombus|rhombic|parallelogram|trapezoid|trapezoidal|trapezium|polygon|polygonal|pentagon|pentagonal|hexagon|hexagonal|heptagon|heptagonal|octagon|octagonal|nonagon|nonagonal|decagon|decagonal|hendecagon|undecagon|dodecagon|dodecagonal|icosagon|cylinder|cylindrical|cylindric|sphere|spherical|spheroid|globe|cone|conical|conic|frustum|kite|quadrilateral|deltoid|torus|toroidal|pyramid|pyramidal|tetrahedron|ellipse|elliptical|oval|annulus|ring|hemisphere|prism|prismatic|cube|cubical|crescent|lune)\b/i;

/** A PART of the disc asked through a non-"sector" noun — a "wedge", a "pie slice", "one
 * quarter", the share "each friend receives", or "the area of the circle COVERED BY the
 * sector". None carries the literal "sector" token the sector target needs, so the whole-disc
 * πr² shipped for a proper sub-region (36π for a true 9π). This engine sizes whole circles;
 * decline honestly rather than answer the wrong figure. */
// The "region of the disc claimed by a sub-figure" idiom has many verbs, not just
// "covered": "the area of the circle TAKEN UP BY / OCCUPIED BY / SWEPT BY the sector".
// Each names a proper sub-region for which πr² ships the whole disc, so read them as one
// class rather than listing the single verb the gate happened to fire with.
// The same relation is stated in BOTH VOICES, and only the passive was read. English turns
// "the area of the circle COVERED BY THE SECTOR" into "the area of the circle THAT THE SECTOR
// COVERS / TAKES UP / SPANS" without changing a thing about the figure asked for, and the
// active form shipped the whole disc (36π for a true 6π). The passive verb list was short of
// "spanned" too, and the sub-region can be introduced by "in"/"within" with ANY determiner
// ("contained IN THAT sector") — "that"/"this" were missing from the set. So: one verb class,
// one determiner class, both voices, rather than the one phrasing each gate happened to hit.
const SUBREGION_NOUN = String.raw`(?:sector|arc|wedge|slice|segment|piece|portion|o[a-z]\b)`;
const SUBREGION_DET = String.raw`(?:the\s+|a\s+|an\s+|its\s+|that\s+|this\s+|each\s+|one\s+)?`;
// "taken UP by the sector" and "taken by the sector" are one idiom; requiring the particle
// left "What area of the circle is TAKEN BY the sector?" looking like a whole-disc ask, and
// the 60 degrees it states went unused (144π shipped for a true 24π).
const SUBREGION_PASSIVE = String.raw`(?:covered|taken(?:\s+up)?|occupied|filled|swept|spanned|subtended|enclosed|bounded|contained|claimed|cut\s+off|marked\s+off)`;
const SUBREGION_ACTIVE = String.raw`(?:takes?\s+up|took\s+up|covers?|occupies|occupied|fills?|spans?|sweeps?|encloses?|claims?|uses?|contains?)`;
const PART_OF_DISC_ASK = new RegExp(
  String.raw`\bwedges?\b|\bslices?\b|\bpieces?\b|\bportions?\b|\bshares?\b`
    + String.raw`|\b${SUBREGION_PASSIVE}\s+(?:by|in|within|inside)\s+${SUBREGION_DET}${SUBREGION_NOUN}`
    + String.raw`|\b(?:that|which)\s+${SUBREGION_DET}${SUBREGION_NOUN}\s+${SUBREGION_ACTIVE}\b`
    + String.raw`|\b(?:with)?in(?:side)?\s+${SUBREGION_DET}(?:sector|arc|wedge|slice|segment)\b|`
    + String.raw`\bshared?\s+(?:equally\s+)?(?:among|between|by)\b|\beach\s+(?:gets|receives|takes|has)\b|\barea\s+each\b|\beach\s+(?:friend|person|child|student|guest|pupil|player|member)\b|\b(?:one|each|a\s+single)\s+(?:quarter|half|third|fifth|sixth|eighth)\b|\b(?:cut|divided?|split|sliced|shared)\s+in(?:to)?\s+(?:\w+\s+)?(?:quarters|halves|thirds|fifths|sixths|eighths)\b`,
  "i"
);

/** A 3-D SOLID's surface — the "curved / lateral surface" (2πrh cylinder, πrl cone) or a
 * "slant height" — is not a plane-circle quantity; the circle engine would ship the flat
 * base πr² (the "cylindrical tank … curved surface" → 49π-not-140π leak). Decline: this
 * engine sizes 2-D circles only. ("surface area" alone is already declined at the gate.) */
// The curved face of a solid is named by "surface", but equally by "side", "face" or
// "wall" ("the area of the CURVED SIDE of a circular tin of radius 5 and height 10" →
// 25π shipped for the true 2πrh = 100π). Same quantity, four head nouns.
const SOLID_SURFACE = /\b(?:curved|lateral)\s+(?:surface|side|face|wall)\b|\bslant\s+height\b/i;
// "Inscribed" is the TEXTBOOK word for it; the everyday statement of the same configuration
// is "drawn INSIDE a regular dodecagon SO THAT IT TOUCHES EVERY SIDE". Same figure pair, same
// decline — the relation (a circle tangent to every side of a containing figure) is what
// makes it inscribed, not the Latin verb.
const INSCRIBED =
  /\b(inscrib|circumscrib)|\btouch\w*\s+(?:every|each|all(?:\s+of)?)\s+(?:the\s+)?(?:sides?|edges?|corners?|vertices)\b/i;

/** Material REMOVED from the disc (a hole bored / cut out, a hollow washer) makes the
 * figure an annulus-like difference, NOT a plain circle: πr² would answer the full disc
 * and ignore the removed area (the "plate of radius 10 with a hole of area 36π cut out"
 * leak, which shipped 100π instead of 64π). Decline — this engine sizes whole circles. */
const REMOVED_MATERIAL =
  /\bhole\b|\bcut\s+out\b|\bcut\s+from\b|\bhollow\b|\bpunched\s+out\b|\bbored\b|\bdrilled\b|\b(?:a\s+)?(?:half|quarter|third|fifth|sixth|eighth)\s+(?:is\s+|was\s+|has\s+been\s+)?removed\b|\b(?:a\s+|the\s+)?(?:smaller\s+|inner\s+|small\s+)?(?:circle|disc|disk|hole)\s+(?:is\s+|was\s+|has\s+been\s+)?(?:removed|cut\s+away|taken\s+out)\b/i;

/** A disc BISECTED by a diameter — folded along it, divided by it, or a region bounded
 * by a diameter together with an arc — is a SEMICIRCLE (half-disc), not a whole circle:
 * πr² ships DOUBLE the true ½πr². These half-disc figures carry no "semicircle/half"
 * keyword, so they slip PARTIAL_COMPOUND; catch the diameter-bisection phrasings here. */
// A disc "cut / divided / split ALONG (through / across / by) a diameter" is bisected into
// two semicircles — the ask ("the flat-topped shape", "the larger part") is a HALF-disc, and
// πr² ships DOUBLE. These carry no "semicircle/half" keyword and evade PARTIAL_COMPOUND, so
// the cut-along-a-diameter phrasing is caught here alongside the fold/divide-by forms.
// A LINE LAID ALONG A DIAMETER bisects the disc just as a CUT along one does — "A fence RUNS
// ALONG A DIAMETER. Find the area of the ground on the east side." is a half-disc, and the
// engine shipped the whole 400π for a true 200π. The cut/divide verbs were the only ones
// listed; a fence/wall/path/line merely LYING on the diameter divides it exactly as well.
const HALF_DISC =
  /\b(?:runs?|running|lies|lying|laid|drawn|placed|built|set|erected|stretch(?:es|ed|ing)?|goes|passes)\s+(?:\w+\s+){0,2}?(?:along|across|down|through|over|on)\s+(?:a|the|its|one)\s+diameter\b|\bfold(?:ed|s|ing)?\b[^.]*\bdiameter\b|\bdivided\s+by\s+(?:a\s+|its\s+|the\s+)?diameter\b|\b(?:cut|divided?|split|sliced|halved|sawn|sawed|separated)\b[^.]*\b(?:along|across|through|down|by|on)\b[^.]*\bdiameter\b|\b(?:bounded|enclosed)\s+by\b[^.]*\bdiameter\b[^.]*\barc\b|\b(?:bounded|enclosed)\s+by\b[^.]*\barc\b[^.]*\bdiameter\b|\beach\s+half\b|\bsplit\s+down\s+the\s+middle\b|\b(?:straight\s+line|line|cut)\s+through\s+(?:its\s+|the\s+)?cent(?:re|er)\b|\bhalf[\s-]?moon\b|\bhalfmoon\b|\blunette\b|\bd[\s-]?shaped\b|\b(?:flat|level|straight|horizontal)\s+(?:floor|base|bottom|top|ground|edge|side|face|line)\b[^.]{0,60}?\bcent(?:re|er)\b/i;

/** A QUALIFIED HALF — "the NORTHERN half", "its LOWER half", "the upper half" — is a
 * half-disc named by a positional / visual qualifier instead of the word "semicircle",
 * so it slips both HALF_DISC (no diameter verb) and PARTIAL_COMPOUND (the qualifier sits
 * between the determiner and "half"). πr² ships DOUBLE the true ½πr². The qualifier set is
 * a closed class — compass points, position words, and the shading/colour words a diagram
 * uses to name one half — so this generalises without swallowing "is half the diameter". */
// A CHORD FROM ONE RIM POINT TO THE ONE DIRECTLY OPPOSITE is a diameter, said without the
// word: "separated by a straight fence running FROM ONE POINT ON THE RIM TO THE POINT DIRECTLY
// OPPOSITE" bisects the disc, and the part on one side of it is a half — πr² shipped double
// (900π m² for a true 450π). The half is then named POSITIONALLY ("only THE PART of the field
// NORTH OF the fence"), which QUALIFIED_HALF misses because the noun is "part", not "half".
// …and the same chord with its two endpoints named by COMPASS BEARING instead of by the word
// "opposite": "a straight path FROM THE NORTH POINT OF ITS EDGE TO THE SOUTH POINT OF ITS EDGE"
// is a diameter stated as plainly as English allows, and the guard — which required the literal
// "directly/diametrically opposite" — shipped the whole 400π for a true 200π. Any two distinct
// compass points of the rim joined by a straight line cut the disc into pieces this engine
// cannot size, whether or not they happen to be antipodal, so all of them decline.
const COMPASS_POINT = String.raw`north|south|east|west|northern|southern|eastern|western|top|bottom`;
const DIAMETRAL_CHORD = new RegExp(
  String.raw`\bfrom\s+(?:one|a|any)\s+point\s+on\s+(?:the\s+|its\s+)?(?:rim|edge|circumference|boundary|perimeter)\s+to\s+(?:the\s+)?(?:point\s+)?(?:directly\s+|diametrically\s+)?opposite\b`
    + String.raw`|\bdiametrically\s+opposite\b`
    + String.raw`|\bfrom\s+(?:the\s+|its\s+)?(?:${COMPASS_POINT})\s+(?:point|end|edge|side|rim)\b[^.?!]{0,40}?`
    + String.raw`\bto\s+(?:the\s+|its\s+)?(?:${COMPASS_POINT})\s+(?:point|end|edge|side|rim)\b`,
  "i"
);
// …and the same positional half named as "the area of the ground ON THE EAST SIDE of the
// fence". The noun there is neither "part" nor "half", so both readers missed it; what marks
// it is the SIDE OF A DIVIDING LINE, which is a closed enough class to match directly.
// …and the head noun is not always "part": "find the area of THE GROUND TO THE EAST OF the
// path" names the same positional half with an ordinary scenery noun, so the "part of" frame
// missed it entirely. What marks the region is the SIDE-OF-A-DIVIDING-LINE relation, and that
// holds whatever noun carries it — so the noun slot is opened up rather than enumerated.
const POSITIONAL_PART =
  /\b(?:area|region|portion|surface)\s+of\s+(?:the\s+|its\s+|a\s+)?\w+\s+(?:that\s+(?:is|lies)\s+)?(?:to\s+the\s+)?(?:north|south|east|west|left|right|above|below)\s+of\s+(?:the|its|that|this|a)\b|\b(?:only\s+)?the\s+part\s+of\s+(?:the\s+|its\s+|a\s+)?\w+\s+(?:that\s+(?:is|lies)\s+)?(?:to\s+the\s+)?(?:north|south|east|west|above|below|left|right|nearer|nearest|further|farther|inside|outside|beyond)\s+(?:of\s+)?(?:the|its|that|this)\b|\bon\s+the\s+(?:north|south|east|west|left|right|upper|lower|near|far|other|inner|outer)(?:ern)?\s+side\b(?:\s+of\s+(?:the|that|this|its|a)\s+(?:fence|line|wall|path|diameter|chord|cut|divide|boundary|road|track|hedge|wire|string|rope|barrier|partition|screen))?/i;

const QUALIFIED_HALF =
  /\b(?:the|its|this|that|a)\s+(?:north(?:ern)?|south(?:ern)?|east(?:ern)?|west(?:ern)?|upper|lower|top|bottom|left|right|near|far|front|back|first|second|other|remaining|shaded|unshaded|painted|colou?red|red|blue|green|yellow|grey|gray|black|white)\s+half\b/i;

/** A NON-CIRCLE composite region — "the area of the tile NOT COVERED by the circle", "the
 * area of the card THAT REMAINS" — is an outer figure MINUS the disc. The circle engine
 * lands on the only circle in sight and ships πr², i.e. exactly the part that was taken
 * AWAY (16π shipped for a true 64 − 16π). This engine sizes whole circles; decline. */
const COMPOSITE_REGION_ASK =
  /\bnot\s+(?:covered|occupied|taken|filled|used)\b|\bthat\s+remains\b|\bremaining\b|\bleft\s+over\b|\bleftover\b|\bouts(?:ide|ide\s+of)\s+(?:the\s+|a\s+)?(?:circle|disc|disk)\b|\bwasted\b|\bunused\b|\bnot\s+part\s+of\b/i;

/** A POLYGON stated by its dimensions rather than its name — "a card measuring 12 cm BY
 * 12 cm", "a tile OF SIDE 8 cm" — is another figure the circle sits in or on. OTHER_SHAPE
 * catches the named forms; these dimensional signatures carry no shape noun at all, and a
 * bare πr² answered the circle when the outer figure was asked. */
const SIDED_FIGURE_DIMS = new RegExp(
  String.raw`\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC})?\s*(?:by|×|✕)\s*\d+(?:\.\d+)?\s*(?:${UNIT_SRC})\b|\bof\s+side\s+\d|\bdiagonals?\b|\bsides?\s+of\s+length\s+\d|\ball\s+(?:four|three|five|six|eight)\s+(?:sides|walls|edges)\b`
    + String.raw`|\blength\s+(?:of\s+)?\d[^.]{0,30}\bwidth\b|\bwidth\s+(?:of\s+)?\d[^.]{0,30}\blength\b`,
  "i"
);

/** An ANNULAR BAND laid around the circle, stated as a WIDTH rather than as a named ring —
 * "surrounded by grass out to a fence 3 M AWAY", "bordered by a path 2 M WIDE". The region
 * asked is outer² − inner², and the engine ships the INNER disc's πr² (49π for a true 51π).
 * A second radial distance qualified by wide/away/beyond/thick is the annulus signature. */
const SURROUND_BAND = new RegExp(
  String.raw`\b(?:surrounded|bordered|edged|ringed|encircled|framed|fringed)\s+by\b[^.]*?\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC}|yards?|ft)\s*(?:wide|away|beyond|out|thick|broad|across|in\s+width|in\s+thickness)\b`
    // …and the same band with its width stated as a NOUN — "surrounded by a grass border OF
    // WIDTH 2 M", "ringed by flagstones OF WIDTH 1 M". Every arm here read the width as an
    // ADJECTIVE trailing its number ("2 m wide"), so the noun order matched nothing and the
    // engine sized the inner disc (9π m² asserted for a true 16π). Any length at all inside a
    // "surrounded by …" clause is the band's, and a band is an annulus this engine declines.
    + String.raw`|\b(?:surrounded|bordered|edged|ringed|encircled|framed|fringed)\s+by\b[^.]{0,60}?\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC}|yards?|ft)\b`
    + String.raw`|\b(?:width|thickness|breadth)\s+(?:of\s+)?\d+(?:\.\d+)?\s*(?:${UNIT_SRC}|yards?|ft)\b[^.]{0,40}?\b(?:a?round|encircl\w+|surround\w+|border\w*)\b`
    // …or a covering that OVERHANGS the figure — "a cloth which OVERHANGS THE EDGE BY 10 CM",
    // "a mat that EXTENDS 3 CM BEYOND it all the way round". The thing asked about is a
    // SECOND, larger circle (r + the overhang); the engine sized the one underneath it
    // (1600π cm² for a true 2500π). Both word orders occur, so read both.
    + String.raw`|\b(?:overhang\w*|overlap\w*|extend\w*|project\w*|protrud\w*|hangs?\s+over|sticks?\s+out)\b[^.]{0,40}?\b(?:by|beyond|past|over)\s+\d+(?:\.\d+)?\s*(?:${UNIT_SRC}|yards?|ft)\b`
    + String.raw`|\b(?:overhang\w*|overlap\w*|extend\w*|project\w*|protrud\w*|hangs?\s+over|sticks?\s+out)\b[^.]{0,20}?\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC}|yards?|ft)\s*(?:beyond|past|over|out\s+from|clear\s+of)\b`
    // …or a named BAND whose width is given without a "surrounded by" verb at all: "a tractor
    // mows a STRIP 3 M WIDE around the edge". Same annulus, same πr² undercount.
    // The band is also named by what it is MADE OF rather than by its shape — a pizza's
    // CRUST, a plate's rim-glaze, an iced BORDER. "A circular pizza has a radius of 15 cm.
    // The crust is 2 cm WIDE." is the same annulus (outer² − inner²), and the engine not only
    // missed it but bound the band's own 2 cm as the figure's diameter — π cm² for a true 56π.
    // …but only for a band that is ADDED AROUND the figure. A CRUST / HEM / TRIM is part of
    // the figure it is named on: a pizza's radius already includes its crust, so "the radius
    // of a circular pizza whose crust is 2 cm wide is 15 cm. Find the area OF THE PIZZA" has
    // one unambiguous answer (225π) and listing those nouns here declined it. They only
    // matter when the band ITSELF is the ask — which `asksRegionArea` below already declines.
    // "a wooden rim 5 cm ACROSS all the way round" states the band's WIDTH — "across" is the
    // diameter idiom on a figure but the width idiom on a band, and the width-adjective list
    // did not hold it, so the annulus shipped as the whole disc (1600π for a true 375π).
    + String.raw`|\b(?:strip|band|border|margin|ring|verge|rim|edging|kerb|curb|frame|halo|corona)\b[^.]{0,40}?\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC}|yards?|ft)\s*(?:wide|broad|thick|across|in\s+width|in\s+thickness|in\s+breadth)\b`
    // A PATH/TRACK/LANE is only an annulus when it ENCIRCLES the figure — "a path 2 m wide
    // runs PAST a circle" is ordinary scenery, and listing those nouns unconditionally
    // declined it. The encircling relation is the signature, not the noun.
    // "runs JUST OUTSIDE it" is the encircling relation stated as a POSITION rather than as a
    // motion — a walk lying outside a closed curve for its whole length IS around it (a true
    // 44π annulus shipped as π m², the band's own width bound as the circle's diameter).
    // "past", by contrast, stays out: passing a circle is not enclosing it.
    + String.raw`|\b(?:path|pathway|walkway|walk|footpath|track|lane|road|apron|surround)\b[^.]{0,40}?\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC}|yards?|ft)\s*(?:wide|broad|thick|in\s+width)\b[^.]{0,40}?\b(?:a?round|encircl\w+|surround\w+|outside|about)\b`
    // …and the same band with the WIDTH STATED FIRST: "A PATH 1 M IN WIDTH runs around it".
    + String.raw`|\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC}|yards?|ft)\s*(?:wide|broad|in\s+width)\b[^.]{0,30}?\b(?:runs?|goes?|lies|laid|surrounds?|borders?|encircles?)\b[^.]{0,20}?\b(?:a?round|about)\b`
    // …or an OFFSET stated from the figure's own EDGE — "a circular fence built 2 M OUT FROM
    // ITS EDGE". That names a SECOND, larger circle of radius r + 2, and the engine sized the
    // inner one (25π for a true 49π). The band need not be named at all for the offset to
    // create the outer circle, so the distance-from-the-edge phrasing is its own signature.
    + String.raw`|\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC}|yards?|ft)\s*(?:out|outside|away|beyond|clear|further|farther|back)\s*(?:from|of)\s+(?:its|the|that)\s+(?:edge|rim|boundary|perimeter|circumference|side|wall|bank|kerb|curb)\b`
    // …and the same offset with NO "from": "a fence put up 3 M OUTSIDE IT", "a cloth that hangs
    // 20 CM OVER THE EDGE", "a net that hangs 2 M PAST THE EDGE", "a rope pegged 1 M OUTSIDE THE
    // EDGE all the way round". What creates the second, larger circle is a DISTANCE followed by
    // an OUTWARD relation to the figure or its edge — not any particular verb, and not the
    // preposition "from". Listing the verbs ("built", "put up", "hangs", "pegged", …) can never
    // keep up; the distance-then-outward-relation shape is the signature. All four shipped the
    // INNER circle (49π m² for a true 100π, 4900π cm² for a true 8100π).
    + String.raw`|\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC}|yards?|ft)\s*(?:out|outside|away|beyond|past|over|clear|further|farther|back)\s*(?:from|of)?\s*(?:it\b|(?:its|the|that)\s+(?:edge|rim|boundary|perimeter|circumference|side|lip|brim|top|circle|disc|disk))`
    // …or a WALL/RIM stated as a THICKNESS beside an internal radius — "a pipe has an INTERNAL
    // RADIUS of 4 cm and its metal WALL IS 1 CM THICK". The cross-section asked is the ANNULUS
    // (outer² − inner²); πr² on the inner radius overstates it (16π for a true 9π).
    + String.raw`|\b(?:wall|rim|shell|casing|lining|coating|tyre|tire|jacket|sleeve|skin|layer)\b[^.]{0,40}?\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC})\s*thick\b`
    + String.raw`|\bthickness\s+of\s+(?:the\s+)?(?:wall|rim|shell|casing|lining|metal|glass|plastic)\b`,
  "i"
);

/** The SIDE surface of a 3-D solid asked WITHOUT the words "curved surface" — the paper
 * LABEL that "covers its side", the "curved part" of a party hat, a "sloping side". Each is
 * a cylinder's 2πrh or a cone's πrl; the circle engine finds the only radius in sight and
 * ships the flat base πr² (49π for a true 140π label, 25π for a true 60π cone). SOLID_SURFACE
 * catches the textbook wording; these are the everyday ones, same quantity. Decline. */
/** A FRACTION of the whole figure, named with ANY noun ("a third of the pizza", "a quarter
 * covered by frost"). PARTIAL_COMPOUND requires the noun to be circle/disc/circular; this is
 * the same ask with the everyday noun the corpus actually uses. */
const FRACTION_OF_FIGURE =
  /\b(?:a|one|two|three|another)\s+(?:half|halves|third|thirds|quarter|quarters|fourth|fourths|fifth|fifths|sixth|sixths|seventh|sevenths|eighth|eighths|ninth|ninths|tenth|tenths)\s+of\b|\b(?:half|quarter|third|two[\s-]thirds|three[\s-]quarters)\s+(?:covered|filled|shaded|painted|eaten|used|occupied|planted|frosted)\b|\b(?:eats?|ate|eaten|takes?|took|uses?|used|covers?|shades?|paints?|removes?|keeps?)\s+(?:a|one)\s+(?:half|third|quarter|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\b/i;

/** N times ROUND the boundary — "the distance around it for 2 LAPS" is N·2πr, not 2πr. */
// N STRANDS is the same multiplicity stated as a COUNT OF THE MATERIAL rather than a count of
// trips: "THREE STRANDS of rope are to be RUN AROUND it. Find the TOTAL length of rope" is
// 3·2πr, and the engine shipped one circuit (14π m for a true 42π). Turns, coils, loops, wraps
// and layers all say it the same way.
const MULTIPLE_CIRCUITS =
  /\b(?:twice|thrice)\s+(?:a)?round\b|\b(?:\d+|two|three|four|five|six|several|many)\s+(?:laps|circuits|rounds|revolutions|times\s+(?:a)?round)\b|\bround\s+(?:it|the\s+\w+)\s+(?:\d+|two|three|four)\s+times\b|\b(?:\d+|two|three|four|five|six|seven|eight|nine|ten|several)\s+(?:strands?|turns?|coils?|loops?|wraps?|layers?|lengths?|rows?|bands?|rings?|circles?)\b[^.?!]{0,60}?\b(?:a?round|encircl\w+|surround\w+|fenc\w+|enclos\w+|ring|rings|bind\w*|tie\w*|border\w*)\b/i;

/** The dimension given INDIRECTLY — as a fraction of itself ("a quarter of the diameter is
 * 2 cm") or as an unevaluated sum ("the diameter is 3 cm plus 5 cm"). Either way the number
 * in the text is NOT the dimension, and binding it directly ships a scaled-wrong answer. */
const INDIRECT_DIMENSION =
  /\b(?:half|quarter|third|fourth|fifth|sixth|eighth|tenth|\d+\s*\/\s*\d+)\s+of\s+(?:the\s+|a\s+|its\s+)?(?:radius|diameter)\b|\b(?:radius|diameter)\b[^.;]{0,40}?\d+(?:\.\d+)?\s*(?:[a-z]{1,3}\s*)?(?:plus|\+|minus|added\s+to|increased\s+by|decreased\s+by|less)\s+\d/i;

/** A COVERING ask — "how much TURF is needed to COVER the lawn", "how much PAINT to cover the
 * ceiling". It names a MATERIAL rather than the word "area", but the quantity asked for is the
 * surface it spreads over, i.e. πr². Both an area CUE and a boundary-cue suppressor. */
/** A stated LENGTH that is the figure's BOUNDARY, not a span across it: "a circular path
 * around the pond is 44 m long", "a circular racetrack is 400 m long", "a wire 88 cm long is
 * bent into a circle". The size is then given as a CIRCUMFERENCE, and recovering r = C/2π is
 * the INVERSE problem this engine declines by design. */
const BOUNDARY_LENGTH_GIVEN =
  /\b(?:path|track|racetrack|racecourse|moat|ditch|fence|fencing|wire|rope|string|cord|ribbon|tape|band|belt|hoop|edging|border|boundary|circumference|perimeter|kerb|curb|rim)\b[^.?!]*\b\d+(?:\.\d+)?\s*[a-z]*\s*(?:long|in\s+length)\b|\b(?:bent|shaped|formed|twisted|made)\s+in(?:to)?\s+(?:a\s+|the\s+)?(?:circle|circular|ring|hoop|loop)\b/i;

/** The MATERIAL a covering ask names fixes the DIMENSION of the answer, and it does so far
 * more reliably than the verb or the covered object: fencing / ribbon / wire / tape / edging
 * are sold by LENGTH, turf / paint / carpet / tiles by AREA. Keying on the covered OBJECT
 * instead produced both errors in one round — "How much TURF … to cover it right up to the
 * EDGE" shipped a circumference because "edge" appeared, and "How much FENCING … to cover the
 * OUTSIDE" shipped an area because it did not. */
const LINEAR_MATERIAL_SRC = String.raw`fenc\w+|edging|kerb|curb|rope|cord|string|wire|ribbon|tape|trim|braid|lace|hem|piping|beading|railing|skirting|chain|hose|cable|thread|belt|strip|hedg\w+|garland|wreath|bunting|tinsel|guttering|moulding|molding|weatherstrip\w*|flashing|banding`;

/** …and the AREA materials. The dimension of a covering ask is fixed by WHAT IS BEING USED, so
 * the list has to exist on both sides: "How much GLASS is needed for the window?" is πr², and
 * with only the linear list in place it resolved to the SEAL running round the rim and shipped
 * a circumference (10π m for a true 25π m²). */
const AREA_MATERIAL_SRC = String.raw`turf|sod|grass\s+seed|paint|glass|carpet|carpeting|lino|linoleum|fabric|cloth|felt|canvas|leather|paper|card|foil|film|plastic|vinyl|icing|frosting|varnish|lacquer|wax|plaster|render|mulch|gravel|sand|tiles?|tiling|mesh|netting|wallpaper|veneer|laminate`;

/** The material that fixes the dimension is the one being SUPPLIED — the head of the "how much
 * ___" — not any material noun elsewhere in the sentence. Scanning the whole clause let the
 * BOUNDARY the covering runs up to decide instead: "How much TURF is needed to cover the lawn
 * UP TO THE HEDGE?" matched "hedge" and shipped a circumference (10π m for a true 25π m²). So
 * bind the material to the quantifier, through a "<measure> of" slot at most ("how much
 * turf", "what LENGTH OF ribbon", "how many METRES OF mesh"). */
const MATERIAL_HEAD = String.raw`\b(?:how\s+much|how\s+many|what)\s+(?:\w+\s+of\s+|\w+\s+)??`;

const COVERING_LINEAR_ASK = new RegExp(
  String.raw`${MATERIAL_HEAD}(?:${LINEAR_MATERIAL_SRC})\b`,
  "i"
);

/**
 * WHAT THE MATERIAL DOES outranks WHAT THE MATERIAL IS.
 *
 * The two material lists are a PROXY for the answer's dimension — a good one, because most
 * asks state only the material. But when the ask states the RELATION outright, the relation is
 * a FACT about this problem and the material is a generalisation about shops, and the fact has
 * to win. Both directions failed in one round:
 *
 *   "How much TAPE is needed to COVER THE WHOLE TOP of a circular lid?"  → 20π cm  (true 100π cm²)
 *   "How much FELT is needed to GO ONCE ROUND THE RIM of a circular drum?" → 225π cm² (true 30π cm)
 *
 * Tape is sold by length and felt by area, so the material lists answered both backwards. But
 * a covering that GOES ROUND a boundary is a length whatever it is cut from, and one that
 * COVERS A FACE is an area whatever it is sold in. Note how narrow each cue is: the encircling
 * one needs a MOTION verb plus "round"/"along" (so "cover it right up to the EDGE" — a limit,
 * not a circuit — is untouched), and the surface one needs an explicit 2-D face noun.
 */
// The VERB list can never be complete — "felt sewn AROUND THE HEM", "braid tacked round the
// rim" — and an unrecognised verb left the ask looking like a plain area ask, so an area
// material shipped πr² for a true 2πr. What makes the relation encircling is not the verb but
// the OBJECT: "around/along <a boundary noun>" is an encircling relation whoever does it.
const ENCIRCLING_RELATION_ASK =
  /\b(?:go(?:es|ing)?|run(?:s|ning)?|pass(?:es|ing)?|wrap(?:s|ped|ping)?|fit(?:s|ted|ting)?|stretch(?:es|ed|ing)?|reach(?:es|ing)?|extend(?:s|ing)?|lie|lies|laid|wind(?:s|ing)?|loop(?:s|ed|ing)?|sew(?:s|n|ed|ing)?|stitch(?:es|ed|ing)?|tack(?:s|ed|ing)?|bind(?:s|ing)?|bound|tie(?:s|d)?|fasten(?:s|ed|ing)?|nail(?:s|ed|ing)?|glue(?:s|d)?|paste(?:s|d)?|clip(?:s|ped|ping)?)\s+(?:\w+\s+){0,2}?(?:a?round|along)\b|\b(?:a?round|along)\s+(?:the|its|a|one|each)\s+(?:\w+\s+){0,1}?(?:hem|rim|rims|edge|edges|border|borders|boundary|circumference|perimeter|lip|brim|margin|kerb|curb|selvage|fringe)\b/i;

// A FLOOR is a face like a top or a base — "cover the whole FLOOR of a circular room" is a
// surface relation, and leaving the noun out let the unit in "how many METRES of carpet" set
// a length target for a plainly two-dimensional ask (6π m for a true 9π m²).
const SURFACE_COVER_ASK = new RegExp(
  // The face may be named behind ADJECTIVES the list cannot enumerate ("cover A CIRCULAR
  // FLOOR"), so a short modifier gap sits before the head noun…
  String.raw`\bcover\w*\s+(?:the\s+|its\s+|a\s+|an\s+|one\s+)?(?:whole\s+|entire\s+|complete\s+|full\s+|flat\s+|upper\s+|lower\s+)*(?:\w+\s+){0,2}?(?:top|bottom|base|face|surface|underside|disc|disk|area|floor|ground|deck|court|rink|pitch|lawn|field)\b`
    // …and COMPLETELY covering an object is a surface relation with no face word at all:
    // "How much tape is needed to cover the lid COMPLETELY?" registered as a linear ask
    // (tape is sold by the metre) and shipped the lid's 2πr boundary for its πr² face.
    + String.raw`|\bcover\w*\s+(?:the|its|a|an|this|that)\s+(?:\w+\s+){0,2}?\b(?:completely|entirely|fully|wholly|all\s+over)\b`
    + String.raw`|\bcover\w*\s+(?:the|its|a|an)\s+(?:whole|entire|complete|full)\s+\w+`,
  "i"
);

/** A material SUPPLIED FOR a face is the same surface relation as one COVERING it. The covering
 * cue is written in VERBS, and an ask can state the relation with no verb at all: "How many
 * METRES of carpet are needed FOR THE FLOOR of a circular room of radius 3 m?" left the stated
 * unit to set a length target for a plainly two-dimensional ask (6π m for a true 9π m²). The
 * material must be an AREA material, so "how much EDGING for the rim" is untouched. */
const SURFACE_SUPPLY_ASK = new RegExp(
  String.raw`${MATERIAL_HEAD}(?:${AREA_MATERIAL_SRC})\b[^.?!]{0,40}?\b(?:for|on|onto|over|across)\s+`
    + String.raw`(?:the\s+|its\s+|a\s+|an\s+)?(?:whole\s+|entire\s+|complete\s+|full\s+|flat\s+)*`
    + String.raw`(?:\w+\s+){0,2}?(?:top|bottom|base|face|surface|underside|disc|disk|floor|ground|deck|court|rink|pitch|lawn|field)\b`,
  "i"
);

/** The ask can name the answer's DIMENSION outright, in the unit it wants: "HOW MANY METRES OF
 * mesh are needed to go right round …" is a length however the material is classified (mesh is
 * sold by area, and the area list duly shipped 16π m² for a true 8π m). A stated unit of
 * measure is the most direct statement of the target there is, so it outranks every material
 * and covered-object heuristic below. */
const LENGTH_UNIT_ASK =
  /\bhow\s+(?:much|many)\s+(?:linear\s+|running\s+)?(?:m|cm|mm|km|metres?|meters?|centimet(?:re|er)s?|millimet(?:re|er)s?|kilomet(?:re|er)s?|inch(?:es)?|feet|foot|ft|yards?|yds?)\b\s+of\b/i;

// A covering ask is as often an IMPERATIVE as a question — "FIND the amount of tape needed to
// cover the whole top of the lid" carried no area cue at all under a "how much/many/what"-only
// opener, so the ask registered no target and a determinate problem declined.
const COVERING_AREA_ASK =
  /\b(?:how\s+much|how\s+many|what|find|calculate|determine|compute|work\s+out|obtain)\b[^.?!]*\b(?:cover|covering|covered|carpet|carpeting|tile|tiling|turf|turfing|paint|painting|resurface|resurfacing|seed|sow)\b(?![^.?!]*\b(?:fenc\w+|edging|kerb|curb|rope|cord|string|wire|ribbon|tape|trim|braid|lace|hem|piping|beading|railing|skirting|chain|hose|cable|thread|belt|strip)\b)/i;

/** …and the mirror image: a covering ask whose OBJECT is the BOUNDARY — "how much FENCING is
 * needed to cover the BOUNDARY", "what LENGTH of ribbon will cover the EDGE". Covering a line
 * is a LENGTH. Introducing COVERING_AREA_ASK without this made every one of these ship an
 * AREA (25π m² for a true 10π m) — the cue has to look at what is covered, not just at the
 * verb. A material named with an explicit "length of" is a boundary ask outright. */
// The verb and noun lists here track ENCIRCLING_RELATION_ASK's — fastening a material to a
// boundary ("felt SEWN around the HEM of a circular mat") is the same relation as running it
// round one, and with the words missing the ask registered no target at all and declined a
// determinate problem.
const COVERING_BOUNDARY_ASK =
  /\b(?:how\s+much|how\s+many|what)\b[^.?!]*\b(?:cover|covering|go|goes|run|runs|fit|fits|wrap|wraps|sew|sewn|sews|stitch|stitches|stitched|tack|tacks|tacked|bind|binds|bound|tie|ties|tied|fasten|fastens|fastened|nail|nails|nailed|glue|glues|glued|clip|clips|clipped)\w*\b[^.?!]*\b(?:boundary|outline|edge|rim|perimeter|circumference|border|hem|lip|brim|margin|fringe|selvage)\b/i;

/** The region a SECTOR or ARC claims out of the disc, phrased so that the words "area of the
 * circle" still appear — actively ("how much of the circle's area does the sector cover"), or
 * by naming the bounding radii as SEGMENTS ("enclosed by OA, the arc AB and OB"). */
const SECTOR_REGION_ASK =
  /\bdoes\s+the\s+(?:sector|arc|wedge|slice|segment)\s+(?:cover|occupy|take|fill|span)\b|\b(?:enclosed|bounded|formed|cut\s+off|marked\s+off)\s+by\s+[^.]*\barc\b|\bcircumference\s+cut\s+off\b|\b(?:octant|sextant|quadrant)\b/i;

/**
 * A SPHERE/BALL wearing the adjective "circular". Its surface is 4πr², not πr².
 * Every named ball is a BALL — `\bball\b` does not match "football", "basketball" or
 * "netball", so "how much leather covers a circular FOOTBALL of radius 11 cm" shipped
 * a quarter of the true surface (121π for 484π). The compound is the ordinary way a
 * ball is named, so match the head of the compound, not just the bare word.
 */
const SPHERE_FIGURE =
  /\b(?:\w*ball|sphere|spherical|globe|balloon|orb|dome|hemisphere|marble|pearl|bead|bubble|melon|planet|moon)\b/i;

const SIDE_SURFACE_ASK_EXTRA = /\bon\s+the\s+side\s+of\b|\baround\s+the\s+side\s+of\b/i;
const SIDE_SURFACE_ASK =
  // "the paper that WRAPS its side" is the same lateral-surface ask as "COVERS its side"; the
  // verb list held only the covering family, so a 2πrh wrap shipped the flat disc's πr²
  // (25π for a true 120π). A verb of enclosing is a verb of covering.
  /\b(?:label|wrapper|wrapping)\b|\b(?:covers?|covering|wraps?|wrapped|encircles?|encircling|goes)\s+(?:right\s+)?(?:a?round\s+)?(?:its|the)\s+side\b|\bcurved\s+(?:part|portion|section)\b|\b(?:make|makes|form|forms|construct|constructs)\s+(?:its|the)\s+side\b|\bslop(?:ing|ed)\s+side\b|\bslant(?:ing|ed)?\s+side\b|\bboth\s+(?:faces|sides|surfaces)\b|\beach\s+(?:face|side|surface)\b|\b(?:all\s+over|inside\s+and\s+out|entire\s+surface|whole\s+surface|total\s+surface\s+area)\b/i;

/** TWO CONCENTRIC circles — "a flowerbed of radius 3 m sits AT THE CENTRE OF a circular lawn
 * whose edge is 7 M FROM THAT CENTRE" — make the asked region an ANNULUS (outer² − inner²),
 * and the engine sizes the inner disc it happened to read (9π for a true 40π). SURROUND_BAND
 * catches the band stated as a WIDTH; this catches it stated as a SECOND RADIUS from the
 * shared centre, the other half of the same idiom. Decline: this engine sizes one circle. */
const CONCENTRIC_PAIR = new RegExp(
  // The shared centre is named by more than one noun — "sits IN THE MIDDLE OF a circular lawn"
  // is the same figure-inside-a-figure as "at the centre of". The PLACEMENT VERB is what makes
  // this a second FIGURE rather than a point: an instrument merely standing at the centre
  // ("a sprinkler at the centre of a circular field SWEEPS through 120°") introduces no second
  // circle at all, and a subject-free form of this pattern declined every genuine sweep.
  String.raw`\b(?:sits|lies|stands|is|are|placed|set|centred|centered)\b[^.]*?\b(?:at|in)\s+the\s+(?:cent(?:re|er)|middle|heart)\s+of\s+(?:a|an|the|another)\b[^.]*?\bcircular\b`
    + String.raw`|\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC})\s+(?:away\s+)?from\s+(?:that|the|its|the\s+same)\s+(?:cent(?:re|er)|point|spot)\b`
    + String.raw`|\b(?:inside|within)\s+(?:a|an|the|another)\b[^.]*\bcircular\b[^.]*\bwhose\s+edge\s+is\b`,
  "i"
);

/** ANY bare "half" / "halves" left in the text after the numeric glyphs are normalised is a
 * HALF-FIGURE ask — "the resulting half", "the area each half covers" — and πr² ships DOUBLE.
 * HALF_DISC and QUALIFIED_HALF chase specific phrasings; the qualifier set is open-ended
 * ("the RESULTING half"), so the honest rule is that this engine sizes whole circles and any
 * half at all is out of scope. ("7½" is expanded to "7 1/2" upstream and carries no word.) */
const ANY_HALF = /\bhalf\b|\bhalves\b/i;

/**
 * A named FRACTION of the figure — "its NORTH-EASTERN QUARTER", "ONE-QUARTER of the field is
 * planted", "A SIXTEENTH of the field" — asks about a sub-region, not the disc. The whole-disc
 * formula answers 4× or 16× too much, and the fraction is stated in words the value readers
 * never look at, so nothing downstream can catch it. A COMPASS quarter is the same claim said
 * geographically. `half` has its own guard above; this is every other denominator.
 */
const FRACTIONAL_PART =
  new RegExp(
    String.raw`\b(?:north|south|east|west|northern|southern|eastern|western|top|bottom|left|right|upper|lower|shaded|unshaded|near|far)`
      + String.raw`(?:[\s-]?(?:east|west|eastern|western|hand))?\s+(?:\w+\s+){0,1}?`
      + String.raw`(?:quarter|third|fifth|sixth|eighth|tenth|twelfth|sixteenth|portion|part|section|piece|region)\b`
      + String.raw`|\b(?:a|one|1)[\s-](?:quarter|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|twelfth|sixteenth|twentieth)\s+of\s+(?:the|this|that|its|each|a)\b`
      + String.raw`|\b\d+\s*\/\s*\d+\s+of\s+(?:the|this|that|its|a)\b`,
    "i"
  );

/** A TRANSFORMED dimension — "find the area when the radius is TRIPLED", "the area of a circle
 * with TWICE the radius" — asks about a DIFFERENT circle from the one whose radius is given.
 * The reader binds the stated radius and ignores the scaling, shipping 25π for a true 225π.
 * Applying the factor is a read nothing downstream verifies → decline. */
const SCALED_DIMENSION =
  /\b(?:radius|diameter)\b[^.]{0,40}?\b(?:doubled|tripled|trebled|quadrupled|halved|increased|decreased|reduced|enlarged|scaled|multiplied)\b|\b(?:twice|thrice|double|triple|two|three|four|\d+)\s+times\s+(?:the\s+|its\s+|that\s+)?(?:radius|diameter)\b|\b(?:twice|thrice|double|triple)\s+(?:the\s+|its\s+)?(?:radius|diameter)\b/i;

/** SEVERAL circles, one ask. "FOUR IDENTICAL circular badges EACH have a diameter of 6 cm.
 * Find the TOTAL area of the four badges", "There are 5 CIRCULAR TILES each of radius 3 cm",
 * "the total area of BOTH FACES of a coin" — the engine sizes ONE figure and ships it as the
 * total (9π for a true 36π). Multiplying by the count is arithmetic nothing downstream
 * re-checks, so decline. Two independent signatures: a count-word on a PLURAL circular noun,
 * and a TOTAL/COMBINED ask carrying explicit multiplicity ("each", "both", "identical"). */
const MULTIPLE_FIGURES = new RegExp(
  // The counted noun is the HEAD of the phrase, and "circular" is only one of its modifiers:
  // "two circular FLOWER BEDS", "two circular TABLE TOPS". Requiring the plural immediately
  // after "circular" meant a single intervening modifier let the whole class through, and the
  // engine sized ONE bed and shipped it as the total (6π m for a true 12π m). Walk to the head.
  String.raw`\b(?:\d+|two|three|four|five|six|seven|eight|nine|ten|several|many)\s+(?:identical\s+|equal\s+|congruent\s+|similar\s+|same\s+|small\s+|large\s+)*(?:(?:circular|round)\s+(?:\w+\s+){0,2}?\w+s|circles|discs|disks)\b`
    // "each" and "total" routinely sit in DIFFERENT sentences — "…each of radius 3 m. Find the
    // TOTAL length of edging." — and `[^.]` could never bridge the full stop between them.
    + String.raw`|\b(?:total|combined|overall|altogether)\b[\s\S]{0,100}?\b(?:each|both|identical|congruent|apiece|per\s+\w+)\b`
    + String.raw`|\b(?:each|both|identical|congruent|apiece)\b[\s\S]{0,100}?\b(?:total|combined|overall|altogether)\b`
    // TWO SURFACES OF ONE FIGURE are two figures for this purpose — "the total area of the TWO
    // FACES of a coin", "cover the TOP AND THE BOTTOM of a cushion" — and the engine shipped
    // exactly half by sizing one of them. So is a "PAIR of circular badges", which names its
    // multiplicity with a noun instead of a numeral.
    + String.raw`|\b(?:both|two|all)\s+(?:faces|sides|surfaces|halves)\b`
    + String.raw`|\b(?:top|front|upper\s+face|one\s+face)\s+and\s+(?:the\s+)?(?:bottom|back|underside|lower\s+face|other\s+face)\b`
    + String.raw`|\b(?:a\s+)?pair\s+of\b`
    // …and the plain CONJUNCTION of two named surfaces: "the TOTAL area of THE LID AND THE
    // BASE". The top-and-bottom arm above lists the pairs by name, which can never keep up —
    // what makes it two figures is the "total … of X and Y" shape, so match that instead. The
    // engine sized one of them and shipped exactly half (25π cm² for a true 50π).
    + String.raw`|\b(?:total|combined|overall)\s+(?:area|surface)\b[^.?!]{0,40}?\bof\s+(?:the\s+|its\s+|a\s+)?\w+\s+and\s+(?:the\s+|its\s+|a\s+)?\w+\b`,
  "i"
);

/** A circle PARTITIONED into pieces, or physically transformed, where the ask is a
 * PART (one slice / the folded shape). A bare πr² would answer the whole disc — off
 * by the number of pieces (or by 2 for a fold). These are partial figures that this
 * whole-circle engine cannot size without an explicit angle, so decline. Distinct
 * from PARTIAL_COMPOUND (named half/quarter/segment): here the partition is described
 * as a physical cut/fold into slices/wedges/pieces, or a per-slice ask. */
// A FOLD of any description halves (or quarters) the disc — "folded ONCE so the edges meet
// exactly", "the folded shape". The old clause required "folded INTO two", so the everyday
// wordings shipped the whole πr², double the truth. Any fold at all is out of scope here.
const PARTITIONED_FIGURE =
  /\bfold(?:ed|s|ing)\b|\b(?:fold|cut|divided?|split|sliced|partitioned|quartered)(?:ed|s|ing)?\s+in(?:to)?\s+(?:two|three|four|five|six|seven|eight|nine|ten|half|halves|\d+)\b|\b(?:cut|divided?|split|sliced|partitioned)\s+in(?:to)?\s+\w+\s+(?:equal\s+)?(?:slices?|pieces?|parts?|sectors?|wedges?)\b|\b(?:smallest|largest|biggest|resulting)\s+(?:resulting\s+)?(?:figure|shape|piece|part|region)\b|\b(?:one|each|a\s+single|per|every)\s+(?:slice|wedge|piece)\b|\b(?:slice|wedge)\s+of\s+(?:the\s+|a\s+)?(?:pizza|pie|cake|circle|disc|disk)\b/i;

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
  /\bsemi[\s-]?circle|\bhalf[\s-]?circle|\bquarter[\s-]?circle|\bsemi[\s-]?circular|\bhalf[\s-]?circular|\bquarter[\s-]?circular|\bsemi[\s-]?dis[ck]|\bhalf[\s-]?dis[ck]|\bquarter[\s-]?dis[ck]|\bannular|\bquadrant|\bsegment|\bchord|\bshaded|\bunshaded|\bconcentric|\bwasher|\bcircles\b|\binner\b|\bouter\b|\binternal\b|\bexternal\b|\bbetween\b|\barch(?:es|way|ways|ed)?\b|\b(?:\d+\s*\/\s*\d+|0?\.\d+)\s+of\s+(?:a\s+|an\s+|the\s+|one\s+)?(?:circle|circular|disc|disk)\b|\b\d+\s*\/\s*\d+\s+(?:a\s+|an\s+|the\s+|one\s+)?(?:circle|circular|disc|disk)\b|\b(?:half|quarter|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+(?:of\s+)?(?:a\s+|an\s+|the\s+|one\s+)?(?:circle|circular|disc|disk)\b|\b(?:two|three|four|five|six|seven|eight|nine|ten)[\s-]+(?:halves|thirds|quarters|fourths|fifths|sixths|sevenths|eighths|ninths|tenths)\b|\bcut\s+in(?:to)?\s+(?:two\s+)?(?:half|halves)\b|\bdivided\s+in(?:to)?\b|\bbisect|\bhalved\b|\bsplit\s+in(?:to)?\b|\btwo\s+(?:equal\s+)?(?:halves|parts|pieces|portions)\b|\b(?:one|each)\s+(?:half|part|piece|portion)\b|\bcut\s+in(?:to)?\s+(?:two\s+)?(?:equal\s+)?(?:parts?|pieces?|portions?)\b|\binto\s+(?:two\s+)?(?:equal\s+)?portions?\b|\b(?:right\s+)?(?:through|across)\s+the\s+middle\b|\bfrom\s+edge\s+to\s+edge\b|\bon\s+one\s+side\s+of\b/i;

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
  // `\b` is the wrong boundary for a TeX macro — a control word ends at the first NON-LETTER,
  // so "\sqrt2" (no braces) has no boundary at the "t2" junction and slipped this guard
  // entirely, shipping 4π for a true 2π. texMacro spells the boundary correctly.
  if (texMacro("sqrt").test(rawLatex) || /√/.test(rawLatex)) return null;

  // Flatten to prose. Convert fractions to "a/b" and mixed numbers to "a b/c",
  // and preserve π / ° BEFORE the generic macro strip (which would otherwise
  // delete them — turning "\frac{1}{2}" into "1 2" and "\pi/3" into "/3", the
  // two mis-reads that shipped wrong radii and wrong angles).
  // Vulgar fractions ("7½") and typographic fraction slashes ("3⁄4") are expanded to
  // plain "a/b" FIRST, by the shared glyph normaliser — a digit reader silently truncates
  // them ("7½"→7, "3⁄4"→3) and the verify gate re-derives from the same truncation.
  let text = normalizeNumericGlyphs(cleanLatex(rawLatex))
    .replace(/\\text\s*\{([^{}]*)\}/g, " $1 ")
    .replace(/(\d+)\s*\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/g, " $1 $2/$3 ") // mixed number
    .replace(/\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/g, " $1/$2 ") // plain fraction
    .replace(/\\pi\b/gi, " π ")
    .replace(/\\circ\b/g, " ° ")
    .replace(/\\[a-zA-Z]+/g, " ")
    .replace(/[{}$]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  // A REFERENCE-LABEL number ("In Example 5 diameter AB = 14 cm") measures nothing; masking it
  // stops the value readers binding a problem number as a given. (Runs AFTER the LaTeX flatten
  // so "Fig.~3" and "\text{Question 12}" are labels by the time they are seen.)
  text = maskReferenceLabels(text);

  // Two DIFFERENTLY-labelled circles ("circle 1 … circle 2", "circle number 1 …
  // circle number 2") ⇒ a compound figure. The label may be written bare or with an
  // explicit "number"/"no."/"#" tag.
  // The label number must be read WHOLE. With `\d+` the decimal given in "A circle 12.5 cm
  // in diameter" matched as the label "12" (the unit guard below saw the "." next, not a
  // unit), so the strip left ".5 cm" and shipped 25/4 π for a true 625/16 π. `(?![.\d])`
  // stops the digits BACKTRACKING back into that same shape once the decimal is allowed.
  // …and a label number is never followed by ANOTHER number: "a circle 3 1/2 cm in radius"
  // and "a circle 1/2 cm in radius" strip-matched the labels "circle 3" and "circle 1",
  // leaving "1/2" and "/2" as the given (49/4 π shipped as 1/4 π, a 49× undercount). The
  // decimal guard is written `(?!\.\d)` rather than `(?![.\d])` so an ordinary sentence-final
  // label ("… in circle 2. Find its area") is still stripped.
  const LABEL =
    String.raw`\s+(?:number|no\.?|#)?\s*(\d+(?:\.\d+)?)(?!\.\d)(?!\s*(?:\d|\/\s*\d))`;
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
      // "Fig. 2" — the abbreviation carries a FULL STOP, which `\s+` in LABEL cannot cross, so
      // every "In Fig. 2 radius OA = 7 cm" leaked the FIGURE NUMBER as the dimension (4π for a
      // true 49π; "In Fig. 7 …" made the angle 7°). Allow the abbreviating period.
      String.raw`\b(circle|figure|fig|diagram|shape|part|question|q)\.?${LABEL}\b(?!\s*(?:cm|mm|km|m\b|°|deg|metre|meter|inch|feet|foot|across|wide|long|deep|in\s+diameter|in\s+radius))`,
      "gi"
    ),
    "$1"
  );
  // SEMI-DIAMETER is the classical name for the RADIUS, and it embeds the literal token
  // "diameter" — so `\bdiameter\b` matched and the value was HALVED, shipping 25/4 π for a
  // true 25π. Normalise the synonym away before any dimension is read; this is a lexical
  // rename, not a computation, so it cannot introduce an unverified arithmetic step.
  text = text.replace(/\bsemi[\s-]?diameters?\b/gi, "radius");
  const lower = text.toLowerCase();

  // An AMBIGUOUS DIGIT GROUPING — a comma glued between digits ("radius 1,000", "12,5 cm")
  // or a space-separated group ("1 000 cm") — has two readings that differ by orders of
  // magnitude: the comma is a thousands separator in en and the DECIMAL separator across the
  // app's many European locales, and a space is both the SI thousands separator and an
  // ordinary space. Nothing downstream can disambiguate, and the reader silently truncates at
  // the separator (1 000 → 1, a 10⁶ undercount that verifies against itself). Decline both.
  if (hasAmbiguousNumberGrouping(text)) return null;

  // Parse-integrity: a CHAINED-ARITHMETIC given ("d = 2 × 7 = 14", "radius r = 3 × 4 =
  // 12", "diameter is 4 times 5 = 20") states the value as a mini-calculation. The
  // macro-strip above deletes "\times" to a space ("2 \times 7" → "2 7") and cleanLatex
  // cannot re-derive the product, so the value reader grabs the FIRST operand (2/3/4) as
  // the given — a wrong linear value the verify gate then re-derives from and rubber-
  // stamps. There is no faithful flattening of the arithmetic → decline honestly.
  // The ANGLE slot takes the same mini-calculation ("a central angle of 2 x 30 degrees",
  // "3\times20 degrees"), and it had no arm here at all: the reader grabbed the first operand
  // and shipped 2° for a true 60° (1/5 π cm² for a true 6π). Same defect, same decline — and
  // note the macro boundary, which is why the `\times` arm above missed "3\times20" outright.
  // …tested on the CANONICALISED source, because SCIENTIFIC NOTATION is spelled with the same
  // macro ("1.5\times10^{2} cm") and is not a chain at all — canonicalizeExponents has already
  // resolved it to a plain literal, exactly, so no `\times` survives for this guard to trip on.
  const chainedGiven =
    texMacro("times", "cdot", "ast").test(canonicalizeExponents(rawLatex)) ||
    /\b(?:radius|diameter|r|d)\b[^.;]{0,20}\d[\d.\s]*(?:×|✕|·|\*|\btimes\b|multiplied\s+by)\s*\d/i.test(
      lower
    ) ||
    /\b(?:angle|θ|theta)\b[^.;]{0,30}\d[\d.\s]*(?:×|✕|·|\*|\bx\b|\btimes\b|multiplied\s+by)\s*\d/i.test(
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
  // A FRACTION OF THE FIGURE stated pronominally — "HALF OF IT is planted with grass", "a
  // third of the lawn" — is a partial region; PARTIAL_COMPOUND only fires when the fraction
  // word sits on a circle/disc noun, so the pronoun form shipped the WHOLE πr² (double the
  // true half). Decline: this engine sizes whole figures.
  if (
    /\b(?:half|a\s+third|a\s+quarter|a\s+fifth|a\s+sixth|two[\s-]thirds|three[\s-]quarters?)\s+of\s+(?:it|this|that|them|the\s+(?:circle|disc|disk|field|lawn|garden|plot|pond|area|region|surface))\b/i.test(
      lower
    )
  ) {
    return null;
  }
  // A COMPOUND MULTI-UNIT measure ("radius is 1 m 20 cm", "diameter 2 ft 6 in") states ONE
  // length across two units; the reader takes only the first part (1 m for a true 1.2 m,
  // shipping π for 1.44π) and the verify gate re-derives from that same truncation. Summing
  // the parts is a unit conversion nothing downstream re-checks → decline honestly.
  if (
    /\b\d+(?:\.\d+)?\s*(?:m|km|metres?|meters?|kilomet(?:re|er)s?|ft|feet|foot|yards?)\s+\d+(?:\.\d+)?\s*(?:cm|mm|centimet(?:re|er)s?|millimet(?:re|er)s?|in\b|inch(?:es)?)\b/i.test(
      lower
    )
  ) {
    return null;
  }
  if (PARTIAL_COMPOUND.test(lower)) return null;
  if (PARTITIONED_FIGURE.test(lower)) return null;
  if (REMOVED_MATERIAL.test(lower)) return null;
  if (HALF_DISC.test(lower)) return null;
  if (QUALIFIED_HALF.test(lower)) return null;
  if (DIAMETRAL_CHORD.test(lower)) return null;
  if (POSITIONAL_PART.test(lower)) return null;
  if (COMPOSITE_REGION_ASK.test(lower)) return null;
  if (SIDED_FIGURE_DIMS.test(lower)) return null;
  if (SURROUND_BAND.test(lower)) return null;
  if (SIDE_SURFACE_ASK.test(lower) || SIDE_SURFACE_ASK_EXTRA.test(lower)) return null;
  // A FRACTION of the figure — "Ravi eats A THIRD OF the pizza", "a window is A QUARTER
  // COVERED by frost". PARTIAL_COMPOUND catches these only when the noun is literally
  // circle/disc, so with any everyday noun the engine shipped the WHOLE πr² (144π for a
  // true 48π). The fraction is stated, but applying it is arithmetic nothing re-checks.
  if (FRACTION_OF_FIGURE.test(lower)) return null;
  // A MULTIPLE of the whole — "the distance around it FOR 2 LAPS" is 2·2πr, and the engine
  // shipped one lap. Same class as the N-figures total, on the boundary instead of the area.
  if (MULTIPLE_CIRCUITS.test(lower)) return null;
  // The given is a FRACTION of the dimension ("A QUARTER OF THE DIAMETER is 2 cm") or an
  // ARITHMETIC EXPRESSION ("the diameter is 3 cm PLUS 5 cm"). The reader bound the stated
  // number as the dimension itself, so it shipped π for a true 16π — a 16× undercount.
  if (INDIRECT_DIMENSION.test(lower)) return null;
  // The asked region is the part of the disc a SECTOR/ARC claims, phrased ACTIVELY ("how much
  // of the circle's area DOES THE SECTOR COVER?") or by naming the bounding segments instead
  // of the word "radii" ("enclosed by OA, the arc AB and OB"). Both satisfied the whole-circle
  // area cue while the sector noun set the angle-host flag, so the dangling-angle guard was
  // bypassed too and the stated angle was silently discarded — πr² for a true πr²·θ/360.
  // The size is stated as the figure's BOUNDARY length, not as a span across it ("a circular
  // path around the pond is 44 m long", "a wire 88 cm long bent into a circle"). Deriving
  // r = C/2π is the INVERSE problem this engine declines by design; reading the number as a
  // diameter shipped π² times the true area.
  if (BOUNDARY_LENGTH_GIVEN.test(lower)) return null;
  // ANGULAR UNITS that look like degrees but are not: ARC MINUTES / SECONDS (1/60 and 1/3600
  // of a degree) and CENTESIMAL degrees (grads, 1/100 of a right angle) both read as a bare
  // number and shipped 60× / 1.11× the true arc.
  if (
    /\b(?:arc|angular)\s+(?:minutes?|seconds?)\b|\b(?:minutes?|seconds?)\s+of\s+arc\b|\barc\s?(?:min|sec)s?\b/i.test(
      lower
    ) ||
    /\bcentesimal\b|\bnew\s+degrees?\b/i.test(lower)
  ) {
    return null;
  }
  // An angle given as a RATE ("rotates through 15 degrees EVERY SECOND … the sector it sweeps
  // IN 4 SECONDS") must be multiplied by the elapsed time. The reader bound the rate itself,
  // shipping a quarter of the true sector. Rate arithmetic is a read nothing re-checks.
  if (
    /\b(?:°|degrees?|deg\b|revolutions?|turns?)\s*(?:\/|per|every|each|a)\s*(?:second|minute|hour|sec\b|min\b|hr\b|s\b)/i.test(
      lower
    )
  ) {
    return null;
  }
  // A SECTOR'S PERIMETER — "the total length of the arc AND THE TWO RADII bounding it" — is
  // arc + 2r, a COMPOUND of two quantities. The arc cue matched the substring "length of the
  // arc" and the trailing radii were silently dropped (3π cm for a true 3π + 12 cm).
  if (
    /\barc\b[^.?!]*\band\b[^.?!]*\b(?:two\s+)?(?:radii|radius|straight\s+(?:sides|edges))\b|\bperimeter\s+of\s+(?:the\s+|a\s+)?sector\b|\b(?:total|combined)\s+(?:length|distance)\s+(?:of|around)\b[^.?!]*\barc\b/i.test(
      lower
    )
  ) {
    return null;
  }
  // The disc PARTITIONED into named parts, and one part asked for ("fenced into four equal
  // PLOTS … the area of one PLOT", "sliced right down the middle … one of the two parts").
  if (
    /\b(?:divided|split|fenced|partitioned|sectioned|marked|separated|cut)\s+(?:up\s+)?in(?:to)?\s+(?:\w+\s+){0,2}(?:equal\s+)?(?:plots?|parts?|pieces?|sections?|regions?|beds?|areas?|portions?)\b/i.test(
      lower
    ) ||
    /\b(?:one|each|every)\s+(?:of\s+the\s+\w+\s+)?(?:plot|bed|section|region|part|piece|portion)\b/i.test(
      lower
    ) ||
    /\b(?:right\s+)?(?:down|through|across)\s+the\s+middle\b/i.test(lower)
  ) {
    return null;
  }
  // A 3-D tube/vessel named with a LENGTH or HEIGHT beside its radius is a cylinder — its
  // outside is 2πrL, not πr². The "curved surface" wording was guarded; the bare "coat the
  // OUTSIDE of the pipe" wording was not.
  // A HEIGHT IS NOT A CIRCLE'S DIMENSION. "A circular candle has a radius of 3 cm and IS 12 CM
  // TALL. Find the area of the wax ON THE SIDE" is a cylinder's 2πrh; the engine answered the
  // flat base (9π for a true 72π). Any main-clause height/depth given alongside the radius
  // means the figure is a solid, whatever noun names it — the vessel list below caught only
  // the ones we had thought of. (Subordinate clauses still describe, not dimension: "a
  // circular tank THAT MEASURES 3 M TALL is 10 m across" is an ordinary circle.)
  if (
    mainClauseMatches(
      lower,
      new RegExp(
        // DEEP is the same statement as TALL — extent along the axis the circle does not
        // have. It was in the vessel-list guard below and missing here, so "a circular
        // swimming POOL … is 2 M DEEP. How much paint covers the WALL inside?" (a cylinder's
        // 2πrh) came back as the mouth's πr², 25π for a true 20π. Likewise a depth stated as
        // a NOUN ("a circular jar of radius 3 cm and DEPTH 10 CM") — the height arm read only
        // "height", so the jar's 2πrh ask shipped 9π for a true 60π.
        String.raw`\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC})?\s*(?:tall|high|deep|in\s+height|in\s+depth)\b`
          + String.raw`|\b(?:height|depth)\s+(?:of\s+)?(?:is\s+)?\d`,
        "i"
      )
    ).length > 0
  ) {
    return null;
  }
  // The height must be asserted of the vessel in the MAIN clause: "a circular tank THAT
  // MEASURES 3 M TALL is 10 m [across]" states a depth in a relative clause describing the
  // tank, and the ask is still an ordinary circle. Reuse the shared subordinate-clause
  // firewall rather than re-deriving one here.
  if (
    // A WELL is a vessel like any other on this list, and "is 10 m DEEP" states its height in
    // the one adjective the list was missing — so "the area of its WALL" (the cylinder's 2πrh)
    // came back as the mouth's πr², 9π m² for a true 60π. Both gaps are the same gap: the
    // vocabulary of a hole-shaped vessel and the vocabulary of downward extent.
    /\b(?:pipe|tube|hose|drum|barrel|tin|can|tank|silo|roller|pillar|column|log|rod|straw|duct|chimney|well|shaft|borehole|bore|cistern|vat|bucket|bin|pit|trough|tower|flue|culvert|jar|jug|pot|bowl|mug|cup|vase|flask|beaker|tumbler|kettle|pool|basin|crate|carton|canister)\b/i.test(
      lower
    ) &&
    mainClauseMatches(lower, /\b(?:length|height|depth|tall|long|high|deep)\b/i).length > 0
  ) {
    return null;
  }
  if (SECTOR_REGION_ASK.test(lower)) return null;
  // A SPHERE is not a circle: "a circular BALL covered in leather" wants 4πr², and πr² ships
  // a quarter of it. The word "circular" makes it look like this engine's job; it is not.
  if (SPHERE_FIGURE.test(lower)) return null;
  // …and the SPHERE named by its OUTER LAYER rather than by its shape. `SPHERE_FIGURE` is a
  // noun list, and a noun list in a safety position fails open: "a circular WATERMELON … the
  // area of its SKIN" and "a circular ORANGE … the area of its PEEL" both shipped the flat
  // disc πr² (144π for a true 576π, 16π for a true 64π). Match the ASK instead of the fruit:
  // a skin / peel / rind / shell / husk wraps a SOLID, so its area is a 3-D surface whatever
  // the figure is called. This engine does not do 3-D surfaces → decline.
  if (
    /\barea\s+of\s+(?:its|the|his|her|their)\s+(?:outer\s+|whole\s+|entire\s+|total\s+)?(?:skin|peel|peeling|rind|shell|husk|hide|bark|crust|casing|coat|coating|jacket)\b/i.test(
      lower
    ) ||
    /\b(?:skin|peel|rind|husk|shell)\s+(?:area|surface)\b/i.test(lower)
  ) {
    return null;
  }
  // "the area of THE PART OF the face that the minute hand passes over" asks for a SUB-REGION
  // of the circle, exactly like "the area of the circle IT WETS" — the head noun names the
  // whole figure but the restrictive clause carves a piece out of it, and the engine shipped
  // the whole disc (100π for a true 25π). A part-of ask is never the whole.
  if (
    /\b(?:area|perimeter)\s+of\s+(?:the|that|this)\s+(?:part|portion|piece|region|section|bit|share|slice)\s+of\b/i.test(
      lower
    )
  ) {
    return null;
  }
  // SCIENTIFIC NOTATION in a given ("radius 1.5 x 10^2 cm") — the reader bound the MANTISSA
  // (1.5) and dropped the exponent, shipping 9/4 π for a true 22500π.
  if (/\d\s*(?:[x\u00d7*]|\\times)\s*10\s*[\^]/i.test(lower)) return null;
  if (CONCENTRIC_PAIR.test(lower)) return null;
  if (ANY_HALF.test(lower)) return null;
  if (FRACTIONAL_PART.test(lower)) return null;
  // A stated REACH is a second radius. "A circular lawn has a radius of 12 m. A sprinkler at
  // the centre THROWS WATER 4 M. Find the area the sprinkler waters." has two circles in it,
  // and the engine bound the lawn's radius for a region the sprinkler's reach defines (144π
  // for a true 16π). Which one the ask means is a judgement no reader here can make safely.
  if (
    new RegExp(
      String.raw`\b(?:throws?|sprays?|squirts?|shoots?|projects?|reach(?:es)?|extends?|carries|travels?)`
        + String.raw`\s+(?:\w+\s+){0,3}?\d+(?:\.\d+)?\s*(?:${UNIT_SRC})\b`
        // A reach does not need a verb of throwing to be stated: a TETHER states it as an
        // instrument with a length. "A circular field has a radius of 20 m. A goat is TETHERED
        // at its centre WITH A 5 M ROPE" defines the grazed region by the ROPE, and the engine
        // sized the field (400π for a true 25π). Rope, chain, lead, hose: the same second radius
        // the throwing verbs state, written as a noun.
        + String.raw`|\b\d+(?:\.\d+)?\s*(?:${UNIT_SRC})\s+(?:long\s+)?(?:rope|cord|chain|lead|leash|string|tether|hose|wire|cable|strap|arm)\b`
        + String.raw`|\b(?:rope|cord|chain|lead|leash|string|tether|hose|wire|cable|strap|arm)\s+`
        + String.raw`(?:of\s+length\s+|that\s+is\s+|which\s+is\s+|measuring\s+|is\s+)\d+(?:\.\d+)?\s*(?:${UNIT_SRC})\b`,
      "i"
    ).test(lower)
  ) {
    return null;
  }
  // A COMPARATIVE second figure — "a circle of radius 4 cm is drawn inside A LARGER CIRCLE.
  // Find the area of THE LARGER CIRCLE" — names a figure whose dimension the text never gives.
  // The engine answered with the only radius in sight, i.e. the WRONG circle's.
  if (/\b(?:larger|bigger|smaller|outer|inner|second|third|other|another)\s+(?:circle|disc|disk|ring)\b/i.test(lower)) {
    return null;
  }
  // A boundary walked MORE THAN ONCE — "a rope is wound around it TWICE" — is a multiple of
  // the circumference, and shipping 2πr answers half the rope (8π for a true 16π).
  if (/\b(?:twice|thrice|two|three|four|five|\d+)\s+(?:times\s+)?(?:a?round|about)\b|\b(?:a?round)\b[^.?!]{0,25}\b(?:twice|thrice|\d+\s+times)\b/i.test(lower)) {
    return null;
  }
  // A COMPOUND MIXED-UNIT given — "a radius of 3 cm 5 mm" — is one length written in two
  // units. The reader takes the first number and drops the rest (9π for a true 49/4 π).
  if (
    /\b\d+(?:\.\d+)?\s*(?:m|metres?|meters?|cm|centimet(?:re|er)s?|ft|feet|foot|yards?|yds?)\s+\d+(?:\.\d+)?\s*(?:cm|centimet(?:re|er)s?|mm|millimet(?:re|er)s?|in|inch(?:es)?)\b/i.test(
      lower
    )
  ) {
    return null;
  }
  if (SCALED_DIMENSION.test(lower)) return null;
  if (MULTIPLE_FIGURES.test(lower)) return null;

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

  // A PERCENTAGE OF ANYTHING ("50% of the area", "60 percent of a circular field", "a
  // central angle 30% of 360°") is a DERIVED quantity: the stated number is a scale factor,
  // not the measure. The engine ships the FULL πr² / 2πr (or takes the percentage itself as
  // the value), dropping the factor entirely. Restricting this to "% of the AREA" left the
  // identical "% of the FIGURE" form ("the area of 60 percent of a circular field" → 400π
  // for a true 240π) shipping. A percent-of anywhere in a circle problem is a scale factor
  // nothing downstream recomputes → decline, honestly and uniformly.
  if (/\b\d+(?:\.\d+)?\s*(?:%|percent)\s+of\b/i.test(lower)) return null;

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

  // A PART-OF-DISC noun is only dangerous when the resolved target is the WHOLE figure: then
  // πr² / 2πr answers the entire disc for a proper sub-region ("area of the WEDGE cut by an
  // arc of 90°" → 36π for a true 9π). When the target is sector_area / arc_length the θ/360
  // factor is applied and the same nouns are legitimate scenery ("the central angle for 1 of
  // the SLICES is 40°, find the sector area" resolves correctly), so gate on the target
  // rather than declining the vocabulary outright.
  if ((target === "area" || target === "circumference") && PART_OF_DISC_ASK.test(lower)) {
    return null;
  }

  // An ARC is named AND a central angle is present, yet the target resolved to the whole-
  // circle CIRCUMFERENCE — the "distance/length around [it | its edge | an arc | its arc]"
  // phrasings the arc-length cue (which needs the literal "around the arc") doesn't capture.
  // Shipping 2πr drops the θ/360 factor and answers the whole circle for an arc ask. The
  // genuine arc-length asks ("arc length", "length of the arc") already resolve to
  // arc_length above; this ambiguous residue declines. (No angle ⇒ a real whole-circle
  // circumference that merely mentions an arc → keep.)
  if (target === "circumference" && mentionsArc) {
    // The in-range case is handled by the whole-figure dangling-angle guard below; what is
    // left here is an angle the degrees reader could NOT parse (radians, or two competing
    // degree-marked values). An arc that still carries a "subtends …", radian, named-angle,
    // or any DEGREE token is an arc-length ask (rθ) that this circumference target would
    // over-ship as the whole 2πr — the "π/3 radians … distance around the edge of the arc"
    // → 12π-not-2π leak, and the "arc from the 90 degree position to the 150 degree
    // position" → 24π-not-4π leak, where the angle is a DIFFERENCE of two marked values and
    // the reader rightly refused to pick one. (A bare arc with NO angle clause at all is a
    // genuine whole-circle circumference and still ships.)
    if (
      /\bsubtends?\b/i.test(lower) ||
      /\bradians?\b|\brad\b/i.test(lower) ||
      /\b(?:central|sector)\s+angle\b/i.test(lower) ||
      /°|\bdegrees?\b|\bdeg\b/i.test(lower)
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

  // A DANGLING central angle on a WHOLE-FIGURE target. πr² and 2πr use NO angle, so a
  // stated in-range central angle is necessarily unused — which means a sector/arc was
  // meant, or the problem is compound. Either way shipping the whole figure silently
  // discards a given: the answer would be byte-identical if the angle read 5° or 300°.
  //
  // This guard used to switch OFF whenever a "sector"/"arc" NOUN appeared, on the theory
  // that the angle then belonged to that feature. But the noun is routinely NARRATIVE —
  // "a searchlight … rotates through an ARC of 45 degrees. Find the area lit", "a wiper
  // SWEEPS through an arc of 60°" — and the exemption turned each into a confident πr² that
  // was 8× and 6× too large. A mere mention cannot tell us who owns the angle.
  //
  // What CAN: whether the ask NAMES the whole figure. "Find the area OF THE CIRCLE" beside a
  // sector clause is an explicit whole-disc ask and the angle is genuinely scenery; "find the
  // area LIT / WATERED / IT CLEANS" names a region whose shape the prose never pins down, and
  // the swept angle is the only thing that could pin it. Likewise a literal "circumference"
  // names the whole boundary, while "the distance it travels around the circle" does not.
  // So the exemption now needs BOTH: a sector/arc noun for the angle to belong to, AND an ask
  // that explicitly names the whole figure. With no such noun at all the angle is dangling
  // however the ask is worded ("the area of a circle radius 6 with central angle 60" — the
  // angle can only mean a sector), and with the noun present but a merely descriptive ask the
  // swept region is what was asked. Either way: decline.
  if (target === "area" || target === "circumference") {
    const angleHostNoun = mentionsSector || mentionsArc;
    // The test is on the ASK, not on the text — the whole point of the exemption is what was
    // ASKED FOR. Run over the whole text, any scenery sentence carrying the word satisfied it:
    // "A circular field … has radius 30 m. THE PERIMETER IS FENCED. A cow walks along the arc
    // from A to B, where angle AOB is 120. What distance does the cow walk around the edge?"
    // exempted itself on the fence and shipped the whole 60π circumference for a true 20π arc.
    // Deleting that one scenery sentence made the same problem decline — a guard a bystander
    // sentence can switch off is not a guard. (No readable ask ⇒ fall back to the full text.)
    const askClause = findAskClause(lower) ?? lower;
    const namesWholeFigure =
      target === "area"
        ? asksWholeCircleArea(askClause)
        : /\bcircumference\b|\bperimeter\b/.test(askClause);
    //
    // And the guard must fail CLOSED. It used to test `stray !== undefined`, so an angle the
    // reader could NOT read (radians, π/2, a sweep "from 30° to 120°", "2^{c}") switched the
    // safety OFF and the whole disc shipped — 100π for a true 25π, while the SAME problem
    // written "90 degrees" declined correctly. "I cannot read this angle" is the strongest
    // reason to decline, not a reason to proceed; only genuinely angle-free prose passes.
    if (!angleHostNoun || !namesWholeFigure) {
      const stray = readAngle(text);
      if (stray.kind === "unreadable") return null;
      if (stray.kind === "deg" && stray.value > 0 && stray.value < 360) return null;
    }
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
  // TWO CIRCLES, one ask. A sentence may name the SAME dimension for two different objects
  // — "a COIN 2 cm IN DIAMETER lies on a circular plate whose DIAMETER IS 30 cm", "a pond of
  // DIAMETER 12 m has a fountain 60 cm IN DIAMETER at its centre" — and the best-anchored
  // reading is then the WRONG object's (π cm² shipped for a true 225π). The single-value
  // reader cannot see the competition, because discarding it is its job; ask the shared
  // reader for EVERY reading instead and decline when two disagree.
  //
  // The test is on the NAME's occurrence count, not the reading count: one mention read at
  // two tiers is the same object seen twice ("a disc IS 7 cm IN RADIUS and the table … is 100
  // cm wide" — postpositive 7 and a loose predication 100 off the SAME "radius"), and that
  // must keep shipping 49π. Two mentions with two values is two objects → decline.
  for (const name of ["radius", "diameter"] as const) {
    if (countMentions(lower, name) < 2) continue;
    const values = new Set(
      readBoundValues(lower, name, { unitSrc: UNIT_SRC }).map((b) => b.value)
    );
    if (values.size >= 2) return null;
  }

  // `rejectTrailer` — a value welded to a NON-LENGTH unit is not a length, whatever letter
  // names it ("resistance R = 4 ohms" is not a 4-unit radius; see NON_LENGTH_UNIT).
  const LEN = { unitSrc: UNIT_SRC, rejectTrailer: NON_LENGTH_UNIT };
  let radiusRead = readBoundValue(lower, "radius", { symbol: "r", ...LEN });
  let diameterRead = readBoundValue(lower, "diameter", { symbol: "d", ...LEN });

  // "N cm ACROSS" is the everyday way to state a DIAMETER ("a circular plate is 20 cm
  // across"), and it names no keyword at all — so the reader ignored it and bound whatever
  // "diameter"/"d" it could find elsewhere: a SECOND circle's ("the label on it has diameter
  // 4 cm" → 4π for a true 100π) or a foreign symbol read ("its thickness is d = 2 mm" → π mm²
  // for a true 9π cm²). Read the idiom explicitly, then arbitrate by ANCHOR TIER:
  //   • a NAME-anchored diameter/radius elsewhere with a different value ⇒ two circles are
  //     in play ⇒ genuinely ambiguous ⇒ decline (this engine sizes one circle);
  //   • a bare SYMBOL read ("d = 2 mm") is the weakest anchor and loses to the explicit
  //     postpositive idiom, so the lid's own 6 cm is used.
  //
  // And the idiom must be counted like a NAMED dimension. It was read with a single
  // non-global exec — FIRST match wins — while the two-object firewall above loops only over
  // the literal words "radius"/"diameter". So a sentence carrying TWO bare "across" phrases
  // ("A hall is 4 M ACROSS. A circular table in it is 90 CM ACROSS") registered no conflict
  // at all and sized the HALL: 4π m² for a true 2025π cm². Collect every match.
  // …and the idiom must be bound to the object being ASKED about. Counting values alone is
  // both too weak and too strong: "a circular fountain sits in a courtyard 40 M ACROSS" states
  // ONE span and the engine sized the courtyard (400π m² for a fountain the text never
  // measures), while "a table IS 120 CM WIDE. A plate on it is 24 CM ACROSS" states TWO and is
  // perfectly determinate. Read every span WITH its subject noun and keep only the ones
  // predicated of the asked figure.
  const askObject = findAskObject(lower);
  const clauseOf = (i: number): string => {
    const start = Math.max(0, ...[";", ".", "?", "!"].map((p) => lower.lastIndexOf(p, i) + 1));
    const endRel = lower.slice(i).search(/[;.?!]/);
    return lower.slice(start, endRel === -1 ? lower.length : i + endRel);
  };
  // SUBJECT-BOUND NAMED DIMENSIONS. The same principle the spans below are read under has to
  // govern "radius"/"diameter" too: a dimension is only this problem's input when it is
  // predicated of the figure the question ASKS about. "A circular LAWN is 30 m long. A
  // circular POT of DIAMETER 40 CM stands on it. Find the circumference of the LAWN." states
  // no usable size for the lawn at all, yet the reader took the pot's 40 and shipped 40π m as
  // verified:true. The veto is deliberately narrow — it fires only when the reading's own
  // clause introduces a COMPETING circular figure and never names the asked one — so an
  // ordinary pronoun continuation ("A circular garden … It has a radius of 7 m.") still reads.
  // The ask object must be a figure the TEXT names, not just a word inside the question. "How
  // much area of TURF is needed?" asks about a material that appears nowhere else, and vetoing
  // the lawn's own radius because its clause never says "turf" declined a determinate problem.
  const askObjectIsNamed =
    askObject !== null && countMentions(lower, askObject) >= 2;
  const foreignFigure = (b: { index: number } | null): boolean => {
    if (b === null || askObject === null || !askObjectIsNamed) return false;
    const clause = clauseOf(b.index);
    if (new RegExp(String.raw`\b${askObject}\b`, "i").test(clause)) return false;
    return /\b(?:circular|circle|round|disc|disk)\b/i.test(clause);
  };
  // …and the veto has to be keyed on the NOUN, not on the clause. The owner and the asked
  // figure routinely share a clause — "a circular BADGE is pinned to a BOARD whose diameter is
  // 30 cm", "a BUTTON sits on a circular PLATE with a diameter of 30 cm" — so a clause test
  // that finds the ask object present concludes, wrongly, that the dimension is the asked
  // figure's. Both shipped the OTHER object's area (225π cm²) as verified:true for a figure the
  // text never measures. When the text states WHOSE dimension it is and that owner is not the
  // asked figure, the reading is not this problem's given.
  // A PART inherits its whole's dimensions: "a SECTOR of a circle OF RADIUS 6 cm" states the
  // sector's radius by stating the circle's, and vetoing it because the owner ("circle") is not
  // the ask object ("sector") declined every sector problem in the corpus. Ownership only
  // separates DISTINCT objects, so a part-of-a-circle ask is exempt.
  const PART_OF_CIRCLE = /^(?:sectors?|arcs?|segments?|quadrants?|semicircles?|halves|half|slices?|wedges?|regions?|pieces?|circles?|discs?|disks?|circumferences?|perimeters?|edges?|rims?|boundar(?:y|ies))$/i;
  const ownedByOther = (name: string): boolean => {
    // Same precondition as the clause veto: the ask object must be a figure the TEXT names, not
    // just a word inside the question. "How much area of TURF is needed?" and "the area of the
    // sector WATERED" both head on a word that appears once and is not a figure at all, and
    // vetoing the lawn's / circle's own radius against it declined determinate problems.
    if (askObject === null || !askObjectIsNamed || PART_OF_CIRCLE.test(askObject)) return false;
    const owner = dimensionOwner(lower, name);
    return owner !== null && owner !== askObject;
  };
  if (foreignFigure(radiusRead) || ownedByOther("radius")) radiusRead = null;
  if (foreignFigure(diameterRead) || ownedByOther("diameter")) diameterRead = null;
  const spans = readSpanReadings(lower, UNIT_SRC);
  // A span predicated of a noun the text never calls CIRCULAR cannot be a circle's diameter.
  // "A corridor is 3 m wide. A circular rug in it is 120 cm across. Find ITS circumference."
  // answers its ask with a pronoun, so there is no ask object to filter by — and the corridor's
  // width was bound as the rug's diameter (3π m for a true 120π cm). Only one of the two nouns
  // is ever described as circular, and that is decidable without resolving the pronoun.
  /** Words that END a noun phrase: nothing past one of these modifies the same head. */
  const NP_BOUNDARY =
    "on|in|at|of|to|from|by|with|upon|atop|inside|within|under|underneath|beneath|below|" +
    "beside|near|next|against|over|above|behind|between|among|around|round|alongside|" +
    "opposite|and|or|but|the|a|an|is|are|was|were|be|been|it|its|that|which|whose|" +
    "drawn|placed|set|laid|resting|sitting|lying|standing|pinned|stuck|glued|painted";
  const subjectIsCircular = (subject: string): boolean =>
    // The subject may BE the circle rather than be described as one — "a circle 14 cm across"
    // needs no adjective, and requiring one would have demanded the text say "circular circle".
    /^(?:circles?|discs?|disks?|rings?|hoops?|sectors?|semicircles?)$/i.test(subject) ||
    // …or be described as one by a PREMODIFIER: "a circular flower BED", "a round dinner
    // PLATE". The gap is for the adjectives and nouns that stack inside one noun phrase, so a
    // FUNCTION WORD in it means the phrase has already ended and the two nouns are separate
    // things: in "a CIRCLE on a CARD 40 cm wide" the filler is "on a", and admitting it made
    // the CARD count as circular — its width was bound as the circle's diameter and 400π cm²
    // shipped for a circle the text never measures. Bar the function words from the gap.
    new RegExp(
      String.raw`\b(?:circular|round|circle|disc|disk)\b(?:\s+(?!(?:${NP_BOUNDARY})\b)\w+){0,2}\s+\b${subject}\b`,
      "i"
    ).test(lower);
  // …and a span on a non-circular subject is not merely LOWER PRIORITY than one on a circular
  // subject, it is INADMISSIBLE. Preferring the circular spans and falling back to all of them
  // still bound the scenery whenever NO span was circular: "A circle with a 6 cm radius is
  // drawn ON A CARD 40 CM WIDE. Find its area." shipped 400π for a true 36π, and "A circle is
  // drawn on a SHELF 60 cm wide" — where the circle is never measured at all and the honest
  // answer is a decline — shipped 900π. A card's width is not a circle's diameter under any
  // reading, so the fallback was never sound; drop those spans outright.
  //
  // The one span with no circular marking that MUST still be admitted is a span on the figure
  // the question is ABOUT: "A pizza is 30 cm across. Find the area of the pizza." never calls
  // the pizza circular, but the ask names it as the circle. That is the same subject-binding
  // rule the ask object already encodes, so it costs nothing to keep.
  const admissible = spans.filter(
    (sp) => sp.subject === askObject || subjectIsCircular(sp.subject)
  );
  const circularSpans = admissible.filter((sp) => subjectIsCircular(sp.subject));
  const ownSpans =
    askObject !== null
      ? admissible.filter((sp) => sp.subject === askObject)
      : circularSpans.length > 0
        ? circularSpans
        : admissible;
  // A span is stated, but none of it is about the asked figure. That is fatal only when the
  // span is the ONLY size in the text — then the figure is simply unmeasured ("a circular
  // fountain sits in a courtyard 40 M ACROSS"). When the asked figure carries a dimension of
  // its own, the span is scenery and must not veto it ("a PATH 2 M WIDE runs past a circle of
  // RADIUS 14 CM" is a perfectly ordinary distractor problem).
  if (
    spans.length > 0 &&
    askObject !== null &&
    ownSpans.length === 0 &&
    radiusRead === null &&
    diameterRead === null
  ) {
    return null;
  }
  if (new Set(ownSpans.map((sp) => sp.value)).size >= 2) return null;
  const acrossM = ownSpans[0] ?? null;
  if (acrossM) {
    const acrossVal = acrossM.value;
    // A span predicated of the ASKED figure ("a circular TABLETOP IS 90 CM WIDE … find the
    // area of the TABLETOP") is the strongest possible anchor: subject and ask are the same
    // noun. A radius named in a clause that never mentions that noun ("A COASTER on it has
    // radius 5 cm") belongs to something else, and treating it as a conflict declined a
    // perfectly determinate problem. Disown it — but only when the ask object is known AND
    // the span is its own; anything weaker still conflicts below.
    const spanIsAsked = askObject !== null && acrossM.subject === askObject;
    const foreign = (b: { index: number } | null): boolean =>
      spanIsAsked &&
      b !== null &&
      !new RegExp(String.raw`\b${askObject}\b`, "i").test(clauseOf(b.index));
    if (foreign(radiusRead)) radiusRead = null;
    if (foreign(diameterRead)) diameterRead = null;
    // ANY disagreeing reading elsewhere — named OR symbolic — means a second circle may be in
    // play, and nothing in the text says which one is asked. The symbol tier used to LOSE to
    // the across idiom on the theory that "d" was a foreign quantity ("its thickness is d = 2
    // mm"), but the same shape is far more often the asked circle's own diameter ("a tabletop
    // with D = 120 CM has a coaster 10 CM ACROSS" → 25π shipped for a true 3600π). A weak
    // anchor cannot tell those apart, so disagreement now declines in both directions.
    // A named dimension asserted INSIDE A SUBORDINATE CLAUSE belongs to the noun that clause
    // describes, not to the figure the main clause is about: "a circular tray WHOSE DIAMETER
    // IS 20 CM holds a circular plate 6 CM ACROSS" measures the TRAY. Treating it as a rival
    // reading of the plate's own span declined a perfectly determinate problem. Only applied
    // when the span IS the asked figure's, so a weaker anchor still conflicts below.
    if (spanIsAsked && radiusRead !== null && isSubordinate(lower, radiusRead.index)) {
      radiusRead = null;
    }
    if (spanIsAsked && diameterRead !== null && isSubordinate(lower, diameterRead.index)) {
      diameterRead = null;
    }
    const namedConflict =
      (radiusRead !== null && radiusRead.value * 2 !== acrossVal) ||
      (diameterRead !== null && diameterRead.value !== acrossVal);
    if (namedConflict) return null;
    if (diameterRead === null) {
      diameterRead = {
        value: acrossVal,
        unitRaw: acrossM.unitRaw,
        tier: "postpositive",
        index: acrossM.index,
      };
    }
  }

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

/**
 * True when the ask NAMES THE WHOLE CIRCLE as the figure whose area is wanted ("the area
 * of the circle", "the circle's area") — as opposed to describing a REGION whose shape the
 * prose never pins down ("the area lit", "the area watered", "the area it cleans").
 *
 * That distinction is what decides whether a stray central angle is safe to ignore, so it
 * is read in ONE place and reused by both the target detector and the dangling-angle guard.
 * "SECTOR area of a circle" is excluded by the lookbehind: there the circle is the sector's
 * possessor, not a competing whole-figure ask.
 */
function asksSectorAreaPhrase(lower: string): boolean {
  return /\bsector(?:'s|s)?\s+area\b|\barea\s+of\s+(?:the\s+|a\s+|its\s+)?(?:circle['’]?s?\s+)?sector\b/.test(
    lower
  );
}

/**
 * A RESTRICTIVE clause hung on a noun ("the circle IT WETS", "the region the beam LIGHTS",
 * "the part he PAINTED") names the ground an agent actually reaches — a sub-region — not
 * the figure it is attached to. It narrows the referent, so the clause outranks the head noun.
 *
 * This is the same distinction the doc above draws between "the area of the circle" and "the
 * area watered"; what was missing is that a text can write BOTH at once. "Find the area of the
 * circle IT WETS" (sprinkler sweeping 60°) matched the whole-circle phrase on its head noun and
 * shipped 36π for a true 6π.
 *
 * [ROUND 32] The first fix listed the COVERAGE VERBS, and a closed vocabulary in this position
 * fails OPEN: "the circle it SOAKS" and "the circle it GRAZES" were not on the list, so both
 * shipped the whole disc — 6× and 4× the true value. The structure is what is knowable; the
 * verb is not. So ANY clause of this shape narrows, EXCEPT when its verb merely IDENTIFIES the
 * figure ("the circle the boy DREW", "the circle that is SHOWN in Fig. 3") — identification
 * picks the same figure out, it does not carve a piece off it. Now an unknown verb declines
 * (honest) instead of asserting a whole disc (wrong), which is the direction this has to fail.
 */
const IDENTIFYING_VERB =
  String.raw`shows?|showed|shown|draws?|drew|drawn|gives?|gave|given|marks?|marked|labels?`
  + String.raw`|labell?ed|describes?|described|pictures?|pictured|illustrates?|illustrated`
  + String.raw`|mentions?|mentioned|names?|named|calls?|called|sees?|saw|seen|studies|studied`
  + String.raw`|considers?|considered|examines?|examined|wants?|wanted|needs?|needed|has|have`
  + String.raw`|had|is|are|was|were|represents?|represented|denotes?|denoted|makes?|made`;

const RESTRICTIVE_CLAUSE =
  new RegExp(
    // Anchored: only a clause hung DIRECTLY on the noun modifies it. A stray verb in a later
    // sentence is scenery and must not narrow an otherwise plain whole-circle ask.
    String.raw`^\s+(?:that\s+|which\s+|who\s+)?`
      + String.raw`(?:it|he|she|they|we|you|the\s+\w+|a\s+\w+|an\s+\w+|his\s+\w+|her\s+\w+`
      + String.raw`|their\s+\w+|its\s+\w+|each\s+\w+|every\s+\w+)\s+`
      + String.raw`(?!(?:${IDENTIFYING_VERB})\b)\w+\b`
      // …and the same clause in the PASSIVE ("the circle THAT IS SHADED"), where the participle
      // carries the verb. An identifying participle ("that is shown") is excluded the same way.
      + String.raw`|^\s+(?:that|which)\s+(?:is|was|are|were|has\s+been|had\s+been)\s+`
      + String.raw`(?!(?:${IDENTIFYING_VERB})\b)\w+ed\b`,
    ""
  );

function asksWholeCircleArea(lower: string): boolean {
  const whole = /(?<!\bsector\s)\barea\s+of\s+(?:the\s+|a\s+|its\s+)?circle\b(?!(?:['’]?s)?\s+sector)/;
  const m = whole.exec(lower);
  if (m && !RESTRICTIVE_CLAUSE.test(lower.slice(m.index + m[0].length))) return true;
  return /\bcircle(?:'s|s)?\s+area\b/.test(lower);
}

/**
 * Which single quantity is asked. Returns null if zero or several match.
 *
 * Read from the ASK CLAUSE first. A word problem is scenery plus one question, and a
 * target noun sitting in the scenery hijacked the ask: "A fence runs along its PERIMETER.
 * How much AREA does the garden cover?" shipped a circumference, and "The AREA of the
 * circle … is given in the table. How LONG is the elastic …?" shipped an area. Every cue
 * for the wrong target lived in a scenery sentence. Scoping to the ask sentence resolves
 * the whole class without a per-phrase rule, and falling back to the full text when the
 * ask alone is inconclusive can only surface MORE competing cues — never fewer — so the
 * fallback is never the less conservative reading.
 */
function detectTarget(
  lower: string,
  mentionsSector: boolean
): CircleTarget | null {
  // The DUAL-AREA ambiguity is a property of the WHOLE text, not of the ask clause: "The
  // SECTOR AREA is shown in the diagram … What is the AREA OF THE CIRCLE of radius 8 cm?"
  // has one explicit phrase in each sentence, and nothing can say which is the ask and which
  // is scenery. Scoping to the ask sentence sees only one of them, so this must be evaluated
  // before the scoping and applied to whichever area target the scoped pass resolves.
  const dualAreaAsk = asksSectorAreaPhrase(lower) && asksWholeCircleArea(lower);
  const settle = (t: CircleTarget | null): CircleTarget | null =>
    dualAreaAsk && (t === "area" || t === "sector_area") ? null : t;

  const ask = findAskClause(lower);
  if (ask !== null) {
    const scoped = settle(detectTargetIn(ask, mentionsSector));
    if (scoped !== null) return scoped;
  }
  return settle(detectTargetIn(lower, mentionsSector));
}

function detectTargetIn(
  lower: string,
  mentionsSector: boolean
): CircleTarget | null {
  // "arc length", "length of the arc", and the descriptive "distance/length around (or
  // along) the arc" all ask for ARC LENGTH. The last phrasing shares the word "around"
  // with circumference, so it MUST be claimed here (and excluded from wantsCirc below),
  // else it ships the whole circumference 2πr for an arc ask (dropping the θ/360 factor).
  // The arc may be referred to through its EDGE ("the length around the EDGE OF THE arc"),
  // which the bare "around the arc" cue missed — the ask then fell through to the whole
  // circumference and shipped 2πr for an arc (24π for a true 4π).
  const wantsArc =
    /\barc\s+length\b|\blength\s+of\s+(?:the\s+)?arc\b/.test(lower) ||
    /\b(?:distance|length|way)\s+(?:all\s+the\s+way\s+)?a?round\s+(?:the\s+)?(?:(?:edge|rim|outside|curve)\s+of\s+(?:the\s+|an?\s+)?)?arc\b/.test(
      lower
    ) ||
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
  const asksSectorArea = asksSectorAreaPhrase(lower);
  const asksCircleArea = asksWholeCircleArea(lower);
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
  // The ask verb's object may carry a QUANTIFYING ADJECTIVE ("the TOTAL area", "the whole
  // area") or a trailing participle instead of "of" ("the area COVERED BY grass", "the area
  // IT OCCUPIES"). Requiring the literal "area of" missed all three, so boundaryCue won and
  // shipped the CIRCUMFERENCE for an explicit area ask (6π m for a true 9π m²). Any "area"
  // standing as the ask verb's direct object suppresses a subordinate boundary-length clause.
  const directAreaObjectAsk =
    /\b(?:find|calculate|determine|compute|work\s+out|obtain|give|state|evaluate)\s+(?:the\s+|its\s+|a\s+|an\s+|this\s+)?(?:total\s+|whole\s+|entire\s+|full\s+|exact\s+|approximate\s+|combined\s+)?area\b/.test(
      lower
    ) ||
    /\bwhat\s+(?:is|'s|are)\s+(?:the\s+)?(?:total\s+|whole\s+|entire\s+|full\s+)?area\b/.test(lower) ||
    // "HOW MUCH AREA does the garden cover?", "WHAT AREA of pizza is there?" — an area ask
    // posed as a quantity question rather than "find the area". Unrecognised, it left the ask
    // with no area cue at all and a scenery "perimeter"/"boundary" won the target.
    /\b(?:how\s+much|how\s+many|what)\s+(?:\w+\s+){0,2}area\b/.test(lower) ||
    // A COVERING ask names no "area" noun at all — "HOW MUCH PAINT is needed to COVER the
    // whole ceiling?", "HOW MUCH TURF is needed to cover the lawn?". The ask clause therefore
    // carried no area cue, detection fell back to the whole text, and a scenery boundary
    // ("a cornice runs along the boundary", "a fence around the circle") won the target and
    // shipped 6π m for a true 9π m². Covering a surface IS an area quantity.
    (COVERING_AREA_ASK.test(lower) && !COVERING_LINEAR_ASK.test(lower)) ||
    /\b(?:circle|sector|disc|disk)(?:'s|’s)?\s+area\b/.test(lower);
  // The boundary object may carry a DETERMINER and an adjective — "the length of THE fence",
  // "the length of THE METAL STRIP fitted to its edge". Requiring the noun to sit directly on
  // "of" missed both, so the cue never fired, an "area of a circular garden" SCENERY phrase
  // became the target, and the engine shipped 49π m² for an explicit "find the length of the
  // fence" ask (a true 14π m — wrong quantity AND wrong dimension).
  const boundaryCue =
    !directAreaObjectAsk &&
    // "AMOUNT of tape" states a quantity, not a dimension — unlike "LENGTH of tape" it takes
    // its shape from the relation that follows, so an explicit SURFACE relation overrides it
    // ("the amount of tape needed to COVER THE WHOLE TOP of the lid" is the lid's face, and
    // the boundary reading shipped 10π cm for a true 25π cm²).
    !SURFACE_COVER_ASK.test(lower) &&
    /\b(?:find|calculate|determine|compute|work\s+out|obtain|what\s+is|what's|how\s+much|how\s+long)\b[^.?!]*\b(?:length|amount)\s+of\s+(?:the\s+|a\s+|its\s+)?(?:[a-z]+\s+){0,2}(?:fenc\w+|edging|rope|wire|ribbon|tape|trim|border|string|braid|railing|kerb|curb|strip|band|cord|chain|beading|moulding|molding|piping|hoop|elastic|hose|cable|thread|lace|belt|track|tyre|tire)\b/.test(
      lower
    );
  // The same quantifying adjectives allowed in directAreaObjectAsk ("the TOTAL area") must be
  // allowed here, else "Calculate the total area of a circular pond" resolves NO target at all
  // and over-declines a plain, solvable area ask. The "area of a CIRCULAR <noun>" adjective
  // form is admitted too — "area of a circular pond" is as much a whole-disc ask as "of the
  // circle", and requiring the literal noun missed every real-world circular-<thing> problem.
  // THE TARGET IS READ FROM THE ASK, THE GIVENS FROM THE WHOLE TEXT. Every cue below used to
  // scan the entire problem, so a quantity merely MENTIONED in the scenery captured the
  // target: "The AREA of a circular garden of radius 6 m is shown on the plan. Find the LENGTH
  // of the hedge that surrounds it." shipped 36π m², and "A RIBBON runs around the edge of a
  // circular rug… How much SPACE does the rug take up?" shipped 6π m. Both sentences state the
  // wrong quantity in the scenery and the right one in the ask. nl/ask.ts exists for exactly
  // this; the target cues just had never been scoped to it. Givens keep reading `lower` — only
  // WHICH QUANTITY IS ASKED narrows. (findAskClause returns null for single-sentence problems,
  // where scenery and ask are inseparable, so the scope simply widens back to the full text.)
  const ask = findAskClause(lower) ?? lower;
  // The material lists only decide the dimension when the ask does not state the relation
  // itself — see ENCIRCLING_RELATION_ASK / SURFACE_COVER_ASK. A linear material spread over a
  // FACE is an area ask; an area material run ROUND a boundary is a length ask.
  const surfaceRelationAsk = SURFACE_COVER_ASK.test(ask) || SURFACE_SUPPLY_ASK.test(ask);
  const linearMaterialAsk = COVERING_LINEAR_ASK.test(ask) && !surfaceRelationAsk;
  // A SURFACE relation outranks the material ("how much TAPE to cover the whole TOP" is the
  // face), and a stated length unit does not beat it either, because area materials are SOLD
  // BY THE METRE ("how many metres of CARPET for the floor" is the floor's area). But those
  // two overrides may not BOTH be spent at once: "how many METRES of FENCING to cover the
  // FLOOR" states a length unit AND names a length-only material, and answering it with an
  // area contradicts the very unit the question asks for. Two signals say length, one says
  // area, and nothing can be simultaneously right — so decline rather than pick a side.
  if (
    surfaceRelationAsk &&
    LENGTH_UNIT_ASK.test(ask) &&
    COVERING_LINEAR_ASK.test(ask) &&
    !new RegExp(String.raw`${MATERIAL_HEAD}(?:${AREA_MATERIAL_SRC})\b`, "i").test(ask)
  ) {
    return null;
  }
  const areaMaterialAsk =
    new RegExp(String.raw`${MATERIAL_HEAD}(?:${AREA_MATERIAL_SRC})\b`, "i").test(ask) &&
    !ENCIRCLING_RELATION_ASK.test(ask);
  const wantsArea =
    !boundaryCue &&
    // …but a stated length unit does NOT outrank an explicit SURFACE relation: carpet is sold
    // by the metre and still covers a floor in two dimensions.
    (!LENGTH_UNIT_ASK.test(ask) || surfaceRelationAsk) &&
    (/\b(?:find|calculate|determine|compute|work\s+out|obtain|give|state|evaluate)\s+(?:the\s+|its\s+|a\s+|an\s+|this\s+)?(?:total\s+|whole\s+|entire\s+|full\s+|exact\s+|approximate\s+|combined\s+)?area\b/.test(
      ask
    ) ||
      /\bwhat\s+(?:is|'s|are)\s+(?:the\s+)?(?:total\s+|whole\s+|entire\s+|full\s+)?area\b/.test(ask) ||
      /\b(?:how\s+much|how\s+many|what)\s+(?:\w+\s+){0,2}area\b/.test(ask) ||
      // "How much SPACE does the rug take up on the floor?", "how much ROOM does it occupy" —
      // an area ask that never says "area". Same for a named AREA MATERIAL ("how much GLASS
      // is needed for the window").
      /\b(?:how\s+much|how\s+many)\s+(?:\w+\s+){0,2}(?:space|room|surface|coverage)\b/.test(ask) ||
      (areaMaterialAsk && !linearMaterialAsk) ||
      /\barea\s+of\s+(?:the\s+|a\s+|an\s+|its\s+|this\s+|each\s+)?(?:circle|sector|disc|disk|circular\s+\w+)\b/.test(
        ask
      ) ||
      /\b(?:circle|sector)(?:'s|’s|s)?\s+area\b/.test(ask) ||
      // A COVERING ask is an AREA ask even though it names no "area" noun — "HOW MUCH TURF is
      // needed to COVER the lawn?", "how much PAINT to cover the ceiling?". Registering it only
      // as a boundary-cue SUPPRESSOR was not enough: with no positive area cue the target fell
      // through to a scenery "fence around the circle" and shipped 16π m for a true 64π m².
      (COVERING_AREA_ASK.test(ask) && !linearMaterialAsk));
  // The area/perimeter of a NON-circle region (an annular path / ring / band that
  // borders the circle) is a compound figure this engine cannot compute — a bare
  // πr² would answer the inner disc, not the region. Decline.
  // Allow an interposed adjective ("area of the CIRCULAR path", "a running track") — the
  // old pattern required the region noun to sit right after the determiner, so "area of
  // the circular path" slipped through and shipped the inner disc's πr² for the annulus.
  // The surround laid AROUND a circular feature is named by many nouns — a "paved surround",
  // "the paving", a patio/apron/deck/verge. Each is an annulus (outer² − inner²) the circle
  // engine answered with the INNER disc's πr² (49π for a true 32π), so list them alongside
  // the path/border/ring forms.
  const asksRegionArea =
    /\b(?:area|perimeter)\s+of\s+(?:the\s+|a\s+|its\s+)?(?:[a-z]+\s+){0,2}(?:path|pathway|footpath|border|ring|annulus|region|band|strip|track|walkway|walk|margin|frame|rim|lane|road|gap|space|paving|pavement|paved|surround|apron|deck|patio|verge|kerbing|curbing|moat|edging|surface|crust|hem|trim)\b/.test(
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
    (/\bcircumference\b/.test(ask) ||
      boundaryCue ||
        (LENGTH_UNIT_ASK.test(ask) && !surfaceRelationAsk) ||
        /\b(?:distance|length|way)\s+(?:all\s+the\s+way\s+)?a?round\b(?!\s+(?:the\s+)?arc\b)/.test(ask) ||
        /\baround\s+(?:the\s+|its\s+|a\s+)?(?:circle|circular|disc|disk|edge|rim|boundary|plot|garden|pond|region|outside)\b/.test(
          ask
        ) ||
        /\b(?:length|distance)\s+of\s+(?:the\s+|its\s+|a\s+)?(?:boundary|perimeter|edge|rim|circumference)\b/.test(
          ask
        ) ||
        // A LENGTH OF SOMETHING THAT GOES ROUND IT is a circumference however the thing is
        // named — "the length of the hedge that SURROUNDS it", "the garland laid ALONG THE
        // EDGE". Listing boundary nouns could never keep up; what makes it a circumference is
        // the encircling relation, so match that instead.
        (/\b(?:length|distance)\s+of\b[^.?!]{0,60}?\b(?:surrounds?|surrounding|encircles?|encircling|goes?\s+(?:all\s+the\s+way\s+)?a?round|runs?\s+a?round|borders?|bounds?|rings?)\b/.test(
          ask
        ) &&
          !directAreaObjectAsk) ||
        (/\b(?:length|distance)\s+of\b[^.?!]{0,60}?\balong\s+(?:the\s+|its\s+)?(?:edge|rim|boundary|perimeter|circumference|side)\b/.test(
          ask
        ) &&
          !directAreaObjectAsk) ||

        /\bboundary\s+of\b/.test(ask) ||
        (COVERING_BOUNDARY_ASK.test(ask) && linearMaterialAsk) ||
        // …and a covering that GOES ROUND the boundary is a length however the material is
        // classified: "how much FELT is needed to go once round the RIM" (225π cm² shipped for
        // a true 30π cm). The encircling relation plus a boundary object is as explicit a
        // statement of a perimeter quantity as the word "circumference" is.
        (COVERING_BOUNDARY_ASK.test(ask) && ENCIRCLING_RELATION_ASK.test(ask)) ||
        linearMaterialAsk ||
        // "WHAT LENGTH of ribbon will cover the edge…" — a material asked for by LENGTH is a
        // boundary quantity whatever verb follows.
        /\bwhat\s+length\s+of\b/.test(ask) ||
        /\b(?:boundary|perimeter)\s+length\b/.test(ask) ||
        // "HOW LONG is the trim / must the wire be" asks a boundary LENGTH. Without this cue
        // a problem whose ask is the length but whose scenery mentions an area ("…the area of
        // the circle is printed underneath") saw only the area target and shipped 49π for a
        // true 14π. Registering it makes both targets fire, and the two-target rule below
        // declines the ambiguous pair honestly.
        /\bhow\s+long\s+(?:is|are|must|should|will|would)\b[^.?!]*\b(?:wire|trim|rim|edge|edging|boundary|braid|ribbon|rope|string|tape|border|fence|fencing|band|strip|cord|chain|track|elastic|hoop|hose|cable|thread|lace|belt|tyre|tire)\b/.test(
          ask
        ) ||
        /\bperimeter\b/.test(ask));
  // "diameter" is the ASKED quantity only when it is NOT a given — a diameter
  // immediately followed by a number ("with diameter 10", "diameter = 10") is the
  // GIVEN, not the target. Without this guard "Calculate the AREA of a circle with
  // diameter 10" reads "calculate…diameter" as a second target and wrongly declines.
  const diameterIsGiven = /\bdiameter\b[^0-9=:]*[=:]?\s*-?\d/.test(ask);
  const wantsDiameter =
    !diameterIsGiven &&
    /\bdiameter\b.*\?|\bfind\b[^.]*\bdiameter\b|\bcalculate\b[^.]*\bdiameter\b/.test(
      ask
    );

  const hits: CircleTarget[] = [];
  if (wantsArc) hits.push("arc_length");
  if (wantsArea) {
    // BOTH an explicit sector-area phrase AND an explicit circle-area phrase present is
    // ambiguous — which one is the ask and which is scenery? "The SECTOR AREA is shown in
    // the diagram … What is the AREA OF THE CIRCLE of radius 8 cm?" asks the whole disc, yet
    // the sector-wins rule applied θ/360 and shipped 16π for a true 64π. Nothing here can
    // tell ask from scenery, so decline rather than let precedence guess.
    if (asksSectorArea && asksCircleArea) return null;
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
/**
 * The result of trying to read a central angle. THREE states, not two — this distinction
 * is the whole point:
 *
 *   • "none"       — the text carries no angular content at all. A whole-circle ask is
 *                    safe: there is no angle to have been dropped.
 *   • "unreadable" — angular content IS present but no degree value can be read from it
 *                    safely (radians, π, gradians, DMS, a swept range with two marks, an
 *                    arithmetic expression). This is the reader saying "I cannot read
 *                    this", and it must make every caller MORE careful, never less.
 *   • "deg"        — a trustworthy degree value.
 *
 * The old reader collapsed the first two into `undefined`, and the dangling-angle guard
 * tested `stray !== undefined`. So an angle the reader could NOT read switched the safety
 * OFF: "a sprinkler … turns through an angle of π/2. Find the area watered" shipped the
 * WHOLE disc 100π for a true 25π, and the same problem written "90 degrees" declined
 * correctly. An unreadable given is the strongest possible reason to decline, so the
 * states are now distinct and the guard fails CLOSED.
 */
type AngleRead =
  | { kind: "none" }
  | { kind: "unreadable" }
  | { kind: "deg"; value: number };

const NO_ANGLE: AngleRead = { kind: "none" };
const UNREADABLE_ANGLE: AngleRead = { kind: "unreadable" };

/** Does the text carry ANGULAR content at all? Most "cannot read it" branches below are
 * angular by construction (a radian word, a degree mark, a DMS pair). Two are not: a π
 * anywhere in the text, and the relational "half of …" family, both of which fire on
 * plenty of angle-free prose ("give the area in terms of π", "half of the circle"). Those
 * two branches are gated on this so an angle-free problem still reads as "none". */
const ANGULAR_CONTENT =
  /\bangles?\b|°|\bdegrees?\b|\bdeg\b|\bradians?\b|\brads?\b|\bgradians?\b|\bgons?\b|\bgrads?\b|\bsubtends?\b|\bsubtended\b|\bsectors?\b|\barcs?\b|\bsweeps?\b|\bsweeping\b|\bswept\b|\bcircular\s+measure\b|\brevolutions?\b|\b(?:turns?|rotates?)\s+through\b/i;

/** Degrees per named angle unit — exact, so these are READ, not declined. */
const NAMED_ANGLE_DEG: Record<string, number> = { right: 90, straight: 180 };
/** Small spelled-out counts a named angle may be multiplied by ("TWO right angles"). */
const COUNT_WORDS: Record<string, number> = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4 };

/** Thin adapter: the degree value when one can be read, else undefined. */
function detectAngleDeg(text: string): number | undefined {
  const r = readAngle(text);
  return r.kind === "deg" ? r.value : undefined;
}

function readAngle(text: string): AngleRead {
  // 1) An explicit "radian"/"rad" WORD is decisive → decline. No degree problem says
  //    "radian", so this never over-declines a real degree case. GRADIANS (gons) are a
  //    third angular unit (100 gon = 90°); the reader would take "100 gradians" as 100° and
  //    ship a confident wrong angle, so decline them too — this engine reads degrees only.
  // "rad" is also written "rads", and gradians as "grades" — the clipped plurals a `\brad\b`
  // / `\bgrads?\b` alternation misses. Each shipped its value as DEGREES ("1.5 rads" → 1/12 π
  // for a true 15 cm; "100 grades" → 250/9 π for a true 25π). Match the whole family.
  if (/\brad(?:s|ian|ians)?\b/i.test(text)) return UNREADABLE_ANGLE;
  if (/\bgradians?\b|\bgons?\b|\bgrads?\b/i.test(text)) return UNREADABLE_ANGLE;
  // …and the SAME units written with NO SPACE — "a central angle of 2rad", "100gon". A word
  // boundary needs a non-word character to sit on, and the "2r"/"0g" junction has none, so
  // every glued form slipped both guards above and shipped its value as DEGREES (1/5 π cm²
  // for a true 36 cm²). Anchor on the digit instead of on a boundary that isn't there.
  if (/\d\s*(?:rad(?:s|ian|ians)?|gons?|grads?|gradians?)\b/i.test(text)) return UNREADABLE_ANGLE;
  // The SUPERSCRIPT notation for the same two units — 2^{c} is 2 radians ("c" for circular
  // measure), 2^{g} is 2 gradians. Nothing else writes a superscript letter after an angle
  // value, and the reader saw only the bare 2 and shipped it as 2° (1/10 π cm for a true
  // 18 cm). The caret is required, so a plain "2 cm" can never match.
  // Written with a caret ("2^{c}") OR with the Unicode MODIFIER LETTER ("2ᶜ", "2ᵍ"), which
  // survives the LaTeX flatten as a single character and carries no caret at all.
  if (/\d\s*\^\s*\{?\s*[cg]\s*\}?(?![a-z])/i.test(text)) return UNREADABLE_ANGLE;
  if (/\d\s*[\u1D9C\u1D4D]/.test(text)) return UNREADABLE_ANGLE;
  // "grade" is only an angular unit when a NUMBER sits on it ("100 grades"); "grade 8" is a
  // school year, so require the number-before-unit order that a real unit always takes.
  if (/\d\s*grades?\b/i.test(text)) return UNREADABLE_ANGLE;
  //    "in CIRCULAR MEASURE" is the textbook name for radians ("an angle of 1.2 in circular
  //    measure"); the reader took 1.2 as DEGREES and shipped 1/15 π for a true rθ = 12 cm.
  if (/\bcircular\s+measure\b/i.test(text)) return UNREADABLE_ANGLE;

  // 1a) An angle "at the circumference" is an INSCRIBED angle — half the central angle by
  //     the inscribed-angle theorem — not the central angle a sector/arc formula needs.
  //     The reader takes the stated degrees as central and ships exactly half (or double)
  //     the true value. Converting inscribed→central (×2) is a read nothing downstream
  //     verifies, so decline honestly. (The central angle is stated "at the centre".)
  if (/\bat\s+the\s+circumference\b/i.test(text)) return UNREADABLE_ANGLE;

  // 1a-2) …and the SAME inscribed angle located any other way. "at the circumference" is one
  //     phrasing of a general fact — THE VERTEX IS NOT THE CENTRE — and the others all leaked:
  //     "angle ACB is 40° WHERE C LIES ON THE CIRCUMFERENCE" (shipped 2π cm for a true 4π),
  //     "subtends 30° AT A POINT R ON THE CIRCUMFERENCE" (27π cm² for a true 54π). Match the
  //     fact, not the phrase: any statement that the angle's vertex sits ON the curve.
  if (
    /\b(?:lies|lie|lying|sits|sitting|stands|is|are)\s+on\s+the\s+(?:circumference|circle|arc|curve)\b/i.test(text) ||
    /\bat\s+(?:a|the|some|any)\s+point\s+\w{0,12}?\s*on\s+the\s+(?:circumference|circle|arc|curve|major|minor)\b/i.test(
      text
    ) ||
    /\bon\s+the\s+(?:circumference|arc)\b[^.?!]{0,30}?\bangle\b/i.test(text)
  ) {
    return UNREADABLE_ANGLE;
  }

  // 1a-3) A THREE-LETTER angle name states its own vertex: the MIDDLE letter. "angle AOB" is
  //     central when O is the centre; "angle OAB" is a base angle of the isosceles triangle
  //     OAB, and reading its 50° as the central angle shipped 25/9 π cm for a true 40/9 π —
  //     the text never says "circumference" anywhere, so 1a and 1a-2 could not see it.
  //     The centre is whatever letter the text names as the centre, defaulting to the
  //     universal O. A vertex that is not the centre is not a central angle → decline.
  //     [ROUND 32] Reading only the FIRST name was enough to reject a lone inscribed angle, but
  //     a text that names BOTH — "Angle AOB is 40. Angle OAB is 70 degrees." — needs each name
  //     judged on its own vertex. The degree MARK sat on the distractor there, so the marked
  //     tier downstream shipped the base angle 70 as the central angle (14/3 π for a true 8/3 π).
  //     So collect every named angle with the value predicated on it: a CENTRAL-vertex name is
  //     the most specific statement of the central angle a text can make, and a non-central one
  //     is a distractor that must never be read as central.
  //     The keyword is matched case-INsensitively but the vertex letters case-SENSITIVELY: a
  //     sentence-initial "Angle AOB" is the commonest way these are written, and a `/…/g`
  //     without the fold silently matched nothing at all.
  const centres = new Set<string>();
  for (const m of text.matchAll(/[Cc]ent(?:re|er)\s+(?:is\s+)?(?:at\s+)?([A-Z])\b/g)) centres.add(m[1]);
  for (const m of text.matchAll(/\b([A-Z])\s+is\s+the\s+[Cc]ent(?:re|er)\b/g)) centres.add(m[1]);
  if (centres.size === 0) centres.add("O");
  const vertexCentralVals: number[] = [];
  let sawVertexName = false;
  let sawNonCentralVertex = false;
  for (const m of text.matchAll(/(?:\b[Aa]ngles?\s+|∠\s*)([A-Z])([A-Z])([A-Z])\b/g)) {
    sawVertexName = true;
    const central = centres.has(m[2]);
    if (!central) sawNonCentralVertex = true;
    const after = text.slice((m.index ?? 0) + m[0].length);
    const val = new RegExp(
      String.raw`^\s*(?:is|are|was|were|=|:|of|measures?|measuring|equals?|equal\s+to)?\s*(${NUMERIC_TOKEN})\b`,
      "i"
    ).exec(after);
    const v = val ? parseNumericToken(val[1]) : null;
    if (central && v !== null && Number.isFinite(v)) vertexCentralVals.push(v);
  }
  const distinctVertexVals = [...new Set(vertexCentralVals)];
  // A named angle at the centre, stated once → that IS the central angle. Stated twice with
  // different values → ambiguous. Named angles but none at the centre → nothing central was
  // ever stated, and the numbers in the text belong to other vertices → decline.
  if (distinctVertexVals.length > 1) return UNREADABLE_ANGLE;
  if (distinctVertexVals.length === 0 && sawVertexName && sawNonCentralVertex) {
    return UNREADABLE_ANGLE;
  }
  // The VALUE is carried to the precedence block below rather than returned here: every unit
  // guard between here and there (radians, DMS, revolutions) still has to run on it.
  const vertexVal = distinctVertexVals.length === 1 ? distinctVertexVals[0] : null;

  // 1b) A value stated AT THE CENTRE is a CENTRAL ANGLE whatever verb introduces it — "a
  //     circular fan of radius 20 cm OPENS π/2 AT THE CENTRE". Nothing in that sentence is on
  //     the ANGULAR_CONTENT word list (no "angle", no "sector", no degree mark), so the whole
  //     text read as angle-free, the π branch below never ran, and the ask resolved to the
  //     WHOLE disc — 400π cm² for a true 100π. "At the centre" is the phrase that makes an
  //     angle central; a π on it is a radian measure this engine declines by design.
  if (/π[^.?!]{0,30}\bat\s+the\s+cent(?:re|er)\b/i.test(text)) return UNREADABLE_ANGLE;

  // 1b) DEGREES-MINUTES(-SECONDS) notation ("30 degrees 45 minutes", "30° 45'") — the
  //     degree reader keeps only the whole-degree part and silently drops the arcminutes/
  //     arcseconds (30°45′ read as 30°, ~2.5% low). The minutes/seconds sit RIGHT AFTER
  //     the degree number (digits/whitespace only between), so this never fires on a
  //     narrative time ("… 30 degrees. It ran for 45 minutes"). Decline honestly.
  if (
    /\d\s*(?:°|degrees?|deg\b)[\s,]*(?:and\s+)?\d+\s*(?:['′]|minutes?\b|arcmin\w*)/i.test(text) ||
    /\d\s*['′][\s,]*(?:and\s+)?\d+\s*(?:''|″|seconds?\b|arcsec\w*)/i.test(text)
  ) {
    return UNREADABLE_ANGLE;
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
    return UNREADABLE_ANGLE;
  }

  // 1b-3) …and the SAME arcminute/arcsecond unit with the angle noun at a DISTANCE from the
  //   number: "an arc SUBTENDS 120' AT THE CENTRE", "the ANGLE at the centre IS 120'", "an arc
  //   subtends 30 MINUTES at the centre". Guard 1b-2 requires the unit to sit on the angle
  //   noun's own connector, so any material between them — a locative ("at the centre"), a
  //   verb ("subtends") — broke it and the reader took the bare number as DEGREES: 4π cm
  //   shipped for a true π/15 cm, a 60× overstatement. The unit is the same unit wherever the
  //   angle noun sits, so match the two in either order across a short window, still requiring
  //   an ANGULAR anchor (angle / subtend / at the centre) so a narrative duration is untouched.
  //   Arcminutes are outside a degrees-only reader either way → decline honestly.
  const DMS_UNIT = String.raw`(?:['′]|''|″|\bminutes?\b|\barcmin\w*|\bseconds?\b|\barcsec\w*)`;
  const ANGLE_ANCHOR = String.raw`(?:\bangle\b|\bsubtend\w*|\bat\s+the\s+cent(?:re|er)\b)`;
  if (
    !/°|\bdegrees?\b|\bdeg\b/i.test(text) &&
    (new RegExp(String.raw`${ANGLE_ANCHOR}[^.?!]{0,40}?\d+(?:\.\d+)?\s*${DMS_UNIT}`, "i").test(
      text
    ) ||
      new RegExp(String.raw`\d+(?:\.\d+)?\s*${DMS_UNIT}[^.?!]{0,40}?${ANGLE_ANCHOR}`, "i").test(
        text
      ))
  ) {
    return UNREADABLE_ANGLE;
  }

  // 1c) A REVOLUTION-unit angle ("1/2 turn", "1/6 revolution", "1/4 rev", "0.75 rotations")
  //     measures the angle in FULL TURNS (×360°), not degrees. The fraction reader mis-splits
  //     "1/2 turn" and grabs a bare "1" as 1°, shipping an angle off by ×360. This engine has
  //     no revolution→degree conversion the verify gate can re-check, so decline honestly. The
  //     number must sit RIGHT ON the unit, so a narrative "a wheel turns" (no number) is safe.
  if (/\b(?:\d+\s*\/\s*\d+|\d+(?:\.\d+)?)\s*(?:turns?|revs?|revolutions?|rotations?)\b/i.test(text)) {
    return UNREADABLE_ANGLE;
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
  //    Gated on ANGULAR_CONTENT: a π with no angular content anywhere is a "give your
  //    answer in terms of π" instruction, not an unreadable angle.
  if (new RegExp(String.raw`(?:${PI_TOKEN})`, "i").test(withoutPiDef)) {
    return ANGULAR_CONTENT.test(text) ? UNREADABLE_ANGLE : NO_ANGLE;
  }

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
    // The SPELLED-OUT ordinal fractions are the same class, and the gate reached the ones the
    // hand-picked list omitted: "a central angle of ONE FOURTH OF 360 degrees" bound the base
    // 360 and shipped the WHOLE disc (144π for a true 36π). Cover the numerator words with
    // the full ordinal set, singular and plural, rather than the few that had been seen.
    /\b(?:a|one|two|three|four|five|six|seven|eight|nine|ten)[\s-]+(?:halves?|thirds?|fourths?|quarters?|fifths?|sixths?|sevenths?|eighths?|ninths?|tenths?|twelfths?)\s+of\b/i.test(
      text
    ) ||
    /\bof\s+(?:a\s+|one\s+)?(?:full|complete|whole)\s+(?:turn|revolution|rotation|circle)\b/i.test(text) ||
    // …and the modifier is optional: "a central angle of 0.5 OF A REVOLUTION" measures the
    // angle in TURNS (×360°), but with no "full/complete/whole" the guard missed it and the
    // reader took 0.5 as DEGREES (1/45 π for a true 8π). "circle" is deliberately NOT in this
    // arm — "sector OF A CIRCLE" is the commonest phrasing in the corpus and means no such thing.
    /\bof\s+(?:a\s+|one\s+|the\s+)?(?:turn|revolution|rotation|rev)s?\b/i.test(text) ||
    /\bof\s+(?:a\s+|one\s+)?right\s+angle\b/i.test(text) ||
    // A PERCENTAGE of another angle ("30% of 360 degrees", "25 percent of 360°") — the reader
    // grabbed the percentage itself (25) or the base (360) as the angle, shipping 5/4 π for a
    // true 9/2 π. Computing the product is a read nothing downstream verifies → decline.
    /\b\d+(?:\.\d+)?\s*(?:%|percent)\s+of\b/i.test(text) ||
    // A MULTIPLIER of another angle ("double 45 degrees", "twice 30°", "three times 20°") —
    // the reader binds the base (45) and drops the factor, shipping half the true value.
    // The base may be a DIGIT ("twice 30°") or a NAMED angle ("TWICE A RIGHT ANGLE"), and the
    // comparative may be spelled out ("twice AS LARGE AS 40 degrees"). Only the digit form was
    // covered, so "twice a right angle" fell through to the named reader below, which bound the
    // DETERMINER "a" as its count and shipped 90° for a true 180° — exactly half.
    /\b(?:double|twice|thrice|triple|tripled|doubled|(?:\d+(?:\.\d+)?|two|three|four|five|six|seven|eight|nine|ten)\s*times)\s+(?:as\s+\w+\s+as\s+)?(?:of\s+|that\s+of\s+)?(?:a\s+|an\s+|one\s+|the\s+)?(?:angles?\s+of\s+)?(?:\d|right\s+angle|straight\s+angle)/i.test(
      text
    ) ||
    // The comparative written the OTHER way round — "30 degrees MORE THAN a right angle",
    // "15 degrees LESS THAN a straight angle". The sum/difference is arithmetic nothing
    // downstream redoes, and the reader bound the bare named angle (90/180) instead.
    /\b(?:more|less|greater|larger|smaller|fewer)\s+than\s+(?:a\s+|an\s+|one\s+|the\s+)?(?:right|straight)\s+angle/i.test(
      text
    ) ||
    // A comparative OFFSET from a stated base — "10 degrees MORE THAN a right angle", "10
    // degrees BELOW 90 degrees". The offset needs no "than" to be a comparative: below / above /
    // under / over / short of take their base directly, and with only the "than" forms listed
    // the reader bound the OFFSET (10) and dropped the base, shipping π cm² for a true 8π.
    // …and the offset only counts when it has a NUMERIC (or named-angle) BASE. "40 degrees
    // ABOVE THE HORIZONTAL" is an ORIENTATION with no base to offset from — declining it killed
    // the lighthouse sweep, which is a legitimate read. A base is what makes it arithmetic.
    /\d+(?:\.\d+)?\s*(?:°|degrees?|deg\b)\s+(?:(?:more|less|greater|larger|smaller|fewer)\s+than|below|above|under|over|short\s+of|beyond|past)\s+(?:a\s+|an\s+|the\s+|one\s+)?(?:\d|right\s+angle|straight\s+angle|full\s+turn)/i.test(
      text
    ) ||
    // SUB-UNITS of a degree (DMS: "30 degrees 45 min") and NON-STANDARD angular units
    // (artillery MILS, whose very definition varies by convention: 1/6400 vs 1/6000 turn).
    // The reader consumed only the leading number, shipping 30° for 30°45′ and reading
    // "200 mils" as 200 DEGREES — 18× the true value under any mil convention.
    /\d+\s*(?:°|degrees?|deg\b)\s*\d+\s*(?:'|\u2032|\bmin(?:ute)?s?\b)/i.test(text) ||
    /\b\d+(?:\.\d+)?\s*mils?\b/i.test(text) ||
    // A SUPPLEMENT / COMPLEMENT ("supplementary to 120 degrees", "the complement of 30°") is
    // 180−θ / 90−θ, not the stated number; the reader shipped the base (120) for a true 60.
    /\b(?:supplementar\w*|complementar\w*|supplement|complement)\b/i.test(text)
  ) {
    // Gated like the π branch: "HALF OF the circle is grass" is a region phrase, not an
    // unreadable angle, and must not make an angle-free problem read as angular.
    return ANGULAR_CONTENT.test(text) ? UNREADABLE_ANGLE : NO_ANGLE;
  }

  // 2c) A NAMED ANGLE UNIT — "2 RIGHT ANGLES", "a right angle", "2 STRAIGHT ANGLES" — is an
  //     exact multiple of 90°/180°, the standard textbook way to state 180° and 360°. The
  //     reader had no idea: it took the COUNT as the angle and shipped 2° ("subtends 2 right
  //     angles" → 7/45 π cm for a true 14π cm — a confident answer 90× too small). The
  //     conversion is exact integer arithmetic, so this is READ, not declined, and returns
  //     early — otherwise the "subtends N … centre" phrase reader downstream binds the bare
  //     count. (A RELATIONAL "2/3 OF a right angle" is caught by 2b just above and declines.)
  const namedAngle = new RegExp(
    String.raw`\b(${NUMERIC_TOKEN}|an?|one|two|three|four)\s+(right|straight)\s+angles?\b`,
    "i"
  ).exec(text);
  if (namedAngle) {
    // A COMPOUND angle — "ONE RIGHT ANGLE PLUS 30 DEGREES" — is a sum, and reading only the
    // named part drops the rest (90° shipped for a true 120°). The named reader would return
    // early and hide it, so the continuation is checked first. It must be followed by another
    // angle quantity, so a plain coordinating "and" elsewhere in the prose is untouched.
    if (
      /\b(?:right|straight)\s+angles?\s*(?:plus|and|\+|minus|less|more\s+than)\s+(?:a\s+|an\s+|one\s+|two\s+)?(?:\d+(?:\.\d+)?\s*(?:°|degrees?|deg\b)|(?:right|straight)\s+angles?)/i.test(
        text
      )
    ) {
      return UNREADABLE_ANGLE;
    }
    const word = namedAngle[1].toLowerCase();
    const count = COUNT_WORDS[word] ?? parseNumericToken(word);
    const unitDeg = NAMED_ANGLE_DEG[namedAngle[2].toLowerCase()];
    if (count === null || !Number.isFinite(count) || count <= 0) return UNREADABLE_ANGLE;
    return { kind: "deg", value: count * unitDeg };
  }

  // 2d) An ARITHMETIC EXPRESSION as the angle ("a central angle of 30 + 45 degrees") states
  //     a SUM, and the reader binds one operand ("30") and drops the rest — shipping 12π for
  //     a true 30π. Evaluating the expression is a read nothing downstream re-checks, so
  //     decline. The operator must sit BETWEEN two numbers that carry the degree unit, so a
  //     narrative minus/hyphen elsewhere in the prose is untouched.
  if (/\d\s*[+\-−×*]\s*\d+(?:\.\d+)?\s*(?:°|degrees?|deg\b)/i.test(text)) {
    return UNREADABLE_ANGLE;
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
      // "rotat…" marks an ORIENTATION ("the page is rotated 25°") — but "rotates THROUGH 45
      // degrees" is a SWEEP, and the angle swept IS the central angle. Treating it as a
      // distractor made detectAngleDeg return undefined, which switched OFF the dangling-angle
      // guard and let a searchlight's whole-disc πr² ship (400π for a true 50π sector). The
      // preposition is what separates the two senses: "through" sweeps, "at"/"by" orients.
      // ROTATION IS A SWEEP, FULL STOP. `rotat\w*(?!\s+through)` was here to catch "the page is
      // rotated 25°", and it threw away the real swept angle of every problem that says
      // "a sprinkler ROTATES 120 DEGREES" without the preposition — leaving the problem's
      // actual distractor ("the feed pipe is SET AT 40 degrees") as the only surviving
      // candidate, so the engine shipped a third of the true area as verified:true. What marks
      // an orientation is not the verb but the STATIC MOUNTING PREDICATE that governs it —
      // "set at", "braced at", "mounted at", "angled to" — so match that instead. A verb of
      // motion never orients; a verb of installation never sweeps.
      /\b(?:bearing|latitude|longitude|azimuth|heading|temperature|thermostat|oven|compass|inclin\w*|tilt\w*|slop\w*|slant\w*|lean\w*|ramp|page|banked?|pitched?|elevat\w*|depress\w*|view\w*|observ\w*|sunlight|sunbeam|sun|light|ray|beam|glare|glanc\w*|sight|camera|eye|incidence|incident|watch\w*|look\w*)\b|\b(?:set|mounted|fixed|braced|held|positioned|angled|placed|installed|attached|aligned|oriented|propped|rested?|standing|stands)\s+(?:up\s+)?(?:at|to)\b/i,
  });

  // 5) CENTRAL (legacy phrase reader) — for the "angle at the centre" / "subtends an
  //    angle of N … centre" phrasings the named reader above doesn't cover. The gap
  //    stops before a digit / clause boundary / radius-diameter word so it never reaches
  //    an unrelated number. (π is already handled at step 2, so NUMERIC_TOKEN is enough.)
  //    The number is picked by SCANNING forward from the anchor and REJECTING every candidate
  //    welded to a foreign unit — the same "a value on a foreign unit is a distractor" rule the
  //    `named` reader gets through `rejectTrailer`. The old gap simply stopped at the first
  //    digit, so any label between the phrase and the angle was taken instead, and in a pie
  //    chart there always is one: "the angle at the centre of the sector FOR 8 PUPILS IS 90"
  //    bound 8 (4/5 π for a true 9π). Marking the survivor as degree-marked or not stays the
  //    tie-breaker against the `marked` tier below.
  const scanCentral = (
    anchor: RegExp
  ): { value: number; marked: boolean } | null => {
    const a = anchor.exec(text);
    if (!a) return null;
    // Stay inside the anchor's own clause, and never read past a radius/diameter given.
    let rest = text.slice((a.index ?? 0) + a[0].length).split(/[.;?!]/)[0] ?? "";
    const stop = rest.search(/\b(?:radius|diameter)\b/i);
    if (stop >= 0) rest = rest.slice(0, stop);
    const scan = new RegExp(NUMERIC_TOKEN, "gi");
    for (let m = scan.exec(rest); m; m = scan.exec(rest)) {
      const trailer = rest.slice(m.index + m[0].length);
      if (/^\s*(?:°|degrees?|deg\b)/i.test(trailer)) {
        const v = parseNumericToken(m[0].trim());
        if (v !== null && Number.isFinite(v)) return { value: v, marked: true };
        continue;
      }
      // A COUNT or a foreign unit riding the number ("8 pupils", "sector 2", "after 3 seconds",
      // "20 cm") makes it a label on a different noun. Plural common nouns are counted too —
      // the pie-chart tally is written in whatever the survey counted, and no list can hold
      // every such noun, so the general shape (a number + a plural word) is what is rejected.
      if (
        new RegExp(String.raw`^\s*(?:${NON_ANGLE_UNIT})\b`, "i").test(trailer) ||
        /^\s+[a-z]{3,}s\b/.test(trailer)
      ) {
        continue;
      }
      const v = parseNumericToken(m[0].trim());
      if (v !== null && Number.isFinite(v)) return { value: v, marked: false };
    }
    return null;
  };
  const centralRead =
    scanCentral(new RegExp(String.raw`\bangle\s+at\s+(?:the\s+)?cent(?:re|er)\b`, "i")) ??
    (() => {
      const m = text.match(
        new RegExp(
          String.raw`\bsubtends?\s+(?:an?\s+angle\s+of\s+)?(${NUMERIC_TOKEN})\b[^.]*?\bcent(?:re|er)\b`,
          "i"
        )
      );
      if (!m) return null;
      const v = parseNumericToken(m[1].trim());
      if (v === null || !Number.isFinite(v)) return null;
      const after = text.slice((m.index ?? 0) + m[0].indexOf(m[1]) + m[1].length);
      return { value: v, marked: /^\s*(?:°|degrees?|deg\b)/i.test(after) };
    })();
  const centralVal = centralRead?.value ?? null;
  const centralMarked = centralRead?.marked ?? false;

  // PRECEDENCE:
  //  • Two or more degree-marked numbers ⇒ genuinely ambiguous ⇒ decline.
  //  • A value anchored to the angle's OWN name wins (it is the most specific signal) —
  //    both the "central/sector angle" reader AND the definitional "at the centre" /
  //    "subtends N … centre" phrase outrank a stray degree-marked number on a DIFFERENT
  //    object ("a nearby ramp rises at 30°", "declination 15°"), which is a distractor.
  //  • Else a single degree-marked number is the angle.
  //  • Else the generic "angle N" fallback.
  // A SWEPT angle IS the central angle, by definition — the region a beam/sprinkler/wiper
  // sweeps through IS the sector. Reading it needs its own tier because the distractor list
  // above is written in NOUNS ("beam", "light", "sight") and a searchlight problem says
  // "beam" in the very sentence that states the sweep: "A searchlight has a BEAM that sweeps
  // 150 degrees … The tower is INCLINED at an angle of 5 degrees" lost 150 to the noun and
  // 5 to the mounting predicate, leaving the bare "angle of N" fallback to ship the TOWER's
  // tilt as the sector angle (25/2 π for a true 375π). The governing VERB outranks any noun
  // in the neighbourhood: a verb of sweeping states the swept angle whatever the scenery.
  // The verbs split into TWO families, and only one of them is unconditionally a sweep:
  //  • SWEEP verbs (sweep, scan, traverse) name the covering of a region — they always sweep.
  //  • TURN verbs (rotate, turn, swing, revolve, pivot) name a rigid motion. A BEAM that
  //    rotates sweeps; a DISC that rotates is merely re-oriented and covers nothing new.
  //    So a turn verb is a sweep only when an AGENT is doing it.
  const SWEEP_VERB = String.raw`sweeps?|swept|sweeping|scans?|scanned|scanning|traverses?|traversed`;
  const TURN_VERB =
    String.raw`rotat(?:es?|ed|ing)|turns?|turned|turning|swings?|swung|swinging`
    + String.raw`|revolves?|revolved|revolving|pivots?|pivoted|pivoting`;
  const swept = text.match(
    new RegExp(
      String.raw`\b(?:(${SWEEP_VERB})|(${TURN_VERB}))\s+`
        + String.raw`(?:through\s+|over\s+|by\s+|round\s+|around\s+)?(?:an?\s+angle\s+of\s+)?`
        + String.raw`(${NUMERIC_TOKEN})\s*(?:°|degrees?|deg\b)`,
      "i"
    )
  );
  // …but a FIGURE that rotates is being re-oriented, not swept: "an arc … subtends 40 degrees
  // at the centre O. THE CIRCLE IS THEN ROTATED THROUGH 120 DEGREES about O" states a rigid
  // motion that changes no length and no area, and reading it as the central angle shipped 6π
  // for a true 2π. A sweep needs a sweeper — a beam, an arm, a sprinkler — so the tier yields
  // whenever the subject of the verb is the figure itself. (The two competing degree-marked
  // values then meet the ambiguity rule and the problem declines honestly.)
  const sweptSubject = swept
    ? text.slice(Math.max(0, (swept.index ?? 0) - 40), swept.index ?? 0)
    : "";
  // …and the test for "is it the figure turning?" has to FAIL CLOSED. It was a list of figure
  // nouns, and a list in a safety position ships whatever it has not heard of: "The DISH is then
  // turned through 240 degrees about O" was not in it, so a rigid re-orientation was read as the
  // central angle (28π cm for a true 7π). Invert it — a TURN verb sweeps only when a known
  // SWEEPER is its subject; anything else (a dish, a tray, a noun we have never seen) is a
  // figure being re-oriented, and the angle is not read from it.
  const SWEEPER =
    /\b(?:sprinkler|sprayer|hose|nozzle|jet|beam|light|lamp|searchlight|spotlight|lighthouse|torch|laser|radar|sonar|scanner|camera|wiper|blade|fan|arm|hand|pointer|needle|pendulum|boom|crane|gate|door|barrier|turnstile|antenna|aerial|dish\s+aerial|sweeper|brush|rake|mower|robot)\b/i;
  const sweptIsTurnVerb = Boolean(swept?.[2]);
  const sweptVal =
    swept && (!sweptIsTurnVerb || SWEEPER.test(sweptSubject))
      ? parseNumericToken(swept[3])
      : null;

  // A THREE-LETTER ANGLE NAME STATES ITS OWN VERTEX (the middle letter), so when that letter is
  // the centre the angle it names IS the central angle — the most specific signal in the text,
  // ahead of every reader below. "O is the centre. Angle AOB is 40. Angle OAB is 70 degrees"
  // gave the degree-marked BASE angle (70) to `marked` and shipped 14/3 π for a true 8/3 π.
  if (vertexVal !== null && Number.isFinite(vertexVal)) return { kind: "deg", value: vertexVal };
  if (named !== null && Number.isFinite(named)) return { kind: "deg", value: named };
  if (sweptVal !== null && Number.isFinite(sweptVal)) return { kind: "deg", value: sweptVal };
  if (marked.length >= 2) return UNREADABLE_ANGLE;
  if (
    centralVal !== null &&
    Number.isFinite(centralVal) &&
    (centralMarked || marked.length === 0)
  ) {
    return { kind: "deg", value: centralVal };
  }
  if (marked.length === 1) return { kind: "deg", value: marked[0] };
  if (centralVal !== null && Number.isFinite(centralVal)) return { kind: "deg", value: centralVal };
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
    // …but an angle governed by a MOUNTING predicate describes how the apparatus is HELD, not
    // how far it turns ("the tower is inclined at an angle of 5 degrees"). Reading it as the
    // central angle is a confident wrong sector; there is no other angle to fall back to, so
    // fail closed. (The sweep tier above already rescued the texts that state a real sweep.)
    const before = text.slice(Math.max(0, (fallback.index ?? 0) - 60), fallback.index ?? 0);
    const MOUNTED =
      /\b(?:inclin\w*|tilt\w*|slop\w*|slant\w*|lean\w*|bank\w*|pitch\w*|elevat\w*|depress\w*|rais\w*|mounted|fixed|braced|held|positioned|angled|installed|attached|aligned|oriented|propped|set\s+up|set)\b[^.?!]{0,40}$/i;
    if (MOUNTED.test(before)) return UNREADABLE_ANGLE;
    const v = parseNumericToken(fallback[1]);
    if (v !== null && Number.isFinite(v)) return { kind: "deg", value: v };
  }
  // Nothing readable. Fail CLOSED: if the text carries angular content we simply could not
  // read it (the state that used to masquerade as "no angle"); only genuinely angle-free
  // prose reports "none".
  return ANGULAR_CONTENT.test(text) ? UNREADABLE_ANGLE : NO_ANGLE;
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
  // REPRESENTABILITY. Beyond 2^53 a double no longer carries every integer, so the rendered
  // digits stop being the answer: r = 1234567891 cm printed …488188000π for a true …487881π —
  // a WRONG EXACT RATIONAL, which is a golden-rule violation however plausible it looks.
  // Nothing downstream can catch it, because the verify gate recomputes in the same doubles.
  if (
    Math.abs(piCoeff) > Number.MAX_SAFE_INTEGER ||
    Math.abs(value) > Number.MAX_SAFE_INTEGER
  ) {
    return null;
  }

  // EXACTNESS. The displayed exact form must be the TRUE value, not the best rational that
  // agrees with a 15-digit double (see exactPiCoeff). A coefficient whose exact numerator or
  // denominator no longer fits a safe integer cannot be published honestly → decline.
  const ratCoeff = exactPiCoeff(target, radius, angleDeg);
  if (!ratCoeff) return null;
  const SAFE = BigInt(Number.MAX_SAFE_INTEGER);
  const absN = ratCoeff.n < 0n ? -ratCoeff.n : ratCoeff.n;
  if (absN > SAFE || ratCoeff.d > SAFE) return null;

  const unitTex = spec.unit ? `\\,\\text{${spec.unit}}${squaredUnit ? "^2" : ""}` : "";
  const unitPlain = spec.unit ? ` ${spec.unit}${squaredUnit ? "²" : ""}` : "";

  const exact = usesPi
    ? piCoeffLatex(piCoeff, ratCoeff)
    : { latex: trim(piCoeff), plain: trim(piCoeff), rendered: Number(trim(piCoeff)) };
  const decimal = trim(Number(value.toFixed(4)));
  // …and the other end of the scale. `piCoeffLatex` rounds |k| < 1e-12 to "0" to scrub float
  // noise, and the 4-decimal display underflows too, so a colony of radius 0.0000006 m shipped
  // "0 m² ≈ 0 m²" — a confident assertion that a strictly positive area is ZERO. A display
  // that cannot represent the answer must decline, not round it away.
  if (value > 0 && (Number(decimal) === 0 || exact.plain === "0")) return null;

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

/** Greatest common divisor over BigInt, for reducing an exactly-computed coefficient. */
function bigGcd(a: bigint, b: bigint): bigint {
  let x = a < 0n ? -a : a;
  let y = b < 0n ? -b : b;
  while (y) {
    const t = x % y;
    x = y;
    y = t;
  }
  return x;
}

/**
 * The exact rational a double is MEANT to hold, or null when no simple one reproduces it.
 *
 * Every given in this engine comes from a decimal literal or a vulgar fraction, so the value
 * IS rational — the double is just its nearest representation. Continued-fraction convergents
 * enumerate the candidates in increasing denominator; the first one that maps back to the SAME
 * double is the value (7.111111111111111 → 64/9, 111111.1111 → 1111111111/10000). Nothing is
 * accepted on a printed-digits match, which is exactly how the old renderer went wrong.
 */
function ratOf(x: number): { n: bigint; d: bigint } | null {
  if (!Number.isFinite(x)) return null;
  if (x === 0) return { n: 0n, d: 1n };
  const sign = x < 0 ? -1n : 1n;
  const v = Math.abs(x);
  // THE LITERAL IS THE VALUE. Every given here is read from source text, and JS prints the
  // SHORTEST decimal that round-trips — which for a typed decimal is exactly the typed digits.
  // Going straight to continued fractions instead handed back 3218779434/17197549 for a plain
  // "93.5825051" (true 935825051/5000000): a different rational that merely shares the double,
  // published as an exact coefficient. Convergents are the FALLBACK, for values that could not
  // have been typed as a decimal at all — a vulgar fraction like 1/3 prints as 0.3333333333333333,
  // and 16+ significant digits is the signature of a double reconstructing a repeating value.
  const lit = /^(\d+)(?:\.(\d+))?$/.exec(String(v));
  if (lit) {
    const frac = lit[2] ?? "";
    const significant = `${lit[1]}${frac}`.replace(/^0+/, "");
    if (significant.length <= 15) {
      const n = BigInt(`${lit[1]}${frac}`);
      const d = 10n ** BigInt(frac.length);
      const g = bigGcd(n, d);
      if (g > 0n) return { n: (sign * n) / g, d: d / g };
    }
  }
  let h0 = 0n;
  let h1 = 1n;
  let k0 = 1n;
  let k1 = 0n;
  let f = v;
  const LIMIT = BigInt(Number.MAX_SAFE_INTEGER);
  for (let i = 0; i < 64; i++) {
    const whole = Math.floor(f);
    if (!Number.isSafeInteger(whole)) return null;
    const a = BigInt(whole);
    const h2 = a * h1 + h0;
    const k2 = a * k1 + k0;
    if (h2 > LIMIT || k2 > LIMIT) return null;
    if (Number(h2) / Number(k2) === v) return { n: sign * h2, d: k2 };
    h0 = h1;
    h1 = h2;
    k0 = k1;
    k1 = k2;
    const rest = f - whole;
    if (rest === 0) return null;
    f = 1 / rest;
  }
  return null;
}

/**
 * The coefficient k (as in "k·π") computed EXACTLY, in rationals, straight from the givens —
 * not reverse-engineered from the double.
 *
 * A double coefficient carries at most ~15 significant digits, so r = 111111.1111 cm produced
 * r² = 12345679009.876543 and the renderer dutifully published 24691358019753/2000 — a
 * confident, WRONG exact rational (true: 1234567900987654321/100000000). The substitution gate
 * is structurally blind to it: it re-squares the same double and agrees with itself. Computing
 * the coefficient in exact integer arithmetic is the only thing that can tell the two apart —
 * and when the exact value needs more digits than the display contract can carry, the honest
 * result is to decline.
 */
function exactPiCoeff(
  target: CircleTarget,
  radius: number,
  angleDeg: number | undefined
): { n: bigint; d: bigint } | null {
  const r = ratOf(radius);
  if (!r) return null;
  const a = angleDeg === undefined ? { n: 1n, d: 1n } : ratOf(angleDeg);
  if (!a) return null;
  let n: bigint;
  let d: bigint;
  switch (target) {
    case "area":
      n = r.n * r.n;
      d = r.d * r.d;
      break;
    case "circumference":
    case "diameter":
      n = 2n * r.n;
      d = r.d;
      break;
    case "arc_length":
      n = 2n * r.n * a.n;
      d = r.d * a.d * 360n;
      break;
    case "sector_area":
      n = r.n * r.n * a.n;
      d = r.d * r.d * a.d * 360n;
      break;
    default:
      return null;
  }
  const g = bigGcd(n, d);
  if (g === 0n) return null;
  return { n: n / g, d: d / g };
}

/** Render k·π exactly: integer or simple fraction coefficient, else decimal·π.
 * `rendered` is the numeric coefficient the STRING actually represents, so the
 * caller can gate on the displayed value (not just the full-precision float). */
function piCoeffLatex(
  k: number,
  rat: { n: bigint; d: bigint } | null = null
): { latex: string; plain: string; rendered: number } {
  if (Math.abs(k) < 1e-12) return { latex: "0", plain: "0", rendered: 0 };
  // Exact arithmetic wins whenever the result is small enough to show: the fraction is then
  // computed, never guessed. Both forms below are derived from `rat` (the EXACT coefficient),
  // never from the double — a decimal read off the float is exactly how 730303/720000000 π
  // shipped as "0.001014π" and 15999992000001/16000000000000 π collapsed to "1π".
  //
  // Which form: the fraction when it is small enough to READ (d ≤ 10000 — "3/4 π" beats
  // "0.75π"), otherwise the exact decimal when the coefficient TERMINATES (841/800000 is
  // unreadable; its exact decimal 0.00105125 says the same thing), otherwise — a repeating
  // expansion — the fraction whatever its size, because it is the only exact form there is.
  if (rat && rat.d !== 1n) {
    const dec = exactDecimalString(rat);
    if (rat.d <= 10000n || dec === null) {
      const sign = rat.n < 0n ? "-" : "";
      const n = rat.n < 0n ? -rat.n : rat.n;
      return {
        latex: `${sign}\\tfrac{${n}}{${rat.d}}\\pi`,
        plain: `${sign}${n}/${rat.d} π`,
        rendered: (sign === "-" ? -1 : 1) * (Number(n) / Number(rat.d)),
      };
    }
    return { latex: `${dec}\\pi`, plain: `${dec}π`, rendered: Number(dec) };
  }
  if (rat && rat.d === 1n) {
    const v = Number(rat.n);
    if (v === 1) return { latex: `\\pi`, plain: `π`, rendered: 1 };
    if (v === -1) return { latex: `-\\pi`, plain: `-π`, rendered: -1 };
    return { latex: `${v}\\pi`, plain: `${v}π`, rendered: v };
  }
  const c = coeffStrings(k);
  if (c.isOne) return { latex: `\\pi`, plain: `π`, rendered: 1 };
  if (c.isNegOne) return { latex: `-\\pi`, plain: `-π`, rendered: -1 };
  // The fallback fraction comes from mathjs `fraction()`, which returns the best CONTINUED-
  // FRACTION CONVERGENT — an APPROXIMATION. Printed unqualified it asserts an exact value that
  // is simply not the number: 960120/121 π was displayed for a true 28565553719/3600000 π.
  // The decimal beside it was right, which is why every numeric re-check passed. A fraction is
  // an EXACTNESS CLAIM, so print one only when it round-trips to the coefficient exactly;
  // otherwise the decimal is the honest form.
  if (c.frac && (c.frac.sign === "-" ? -1 : 1) * (c.frac.n / c.frac.d) === k) {
    return {
      latex: `${c.frac.sign}\\tfrac{${c.frac.n}}{${c.frac.d}}\\pi`,
      plain: `${c.frac.sign}${c.frac.n}/${c.frac.d} π`,
      rendered: (c.frac.sign === "-" ? -1 : 1) * (c.frac.n / c.frac.d),
    };
  }
  return { latex: `${c.decimal}\\pi`, plain: `${c.decimal}π`, rendered: Number(c.decimal) };
}

/**
 * The EXACT decimal expansion of a rational, or null when it does not terminate.
 *
 * This is the honest alternative to reading a decimal off the double: the double for
 * 15999992000001/16000000000000 is 0.9999995000000624 (last digit already lost) and every
 * rounding of it — including `toFixed(6)`, which shipped a flat "1" — is a *different* number
 * from the answer. A terminating rational has an exact finite string; compute it in BigInt.
 * A repeating one (any prime factor besides 2 and 5) has none, and returns null so the caller
 * prints the fraction instead.
 */
function exactDecimalString(rat: { n: bigint; d: bigint }): string | null {
  if (rat.d <= 0n) return null;
  let rest = rat.d;
  let twos = 0;
  let fives = 0;
  while (rest % 2n === 0n) {
    rest /= 2n;
    twos++;
  }
  while (rest % 5n === 0n) {
    rest /= 5n;
    fives++;
  }
  if (rest !== 1n) return null; // repeating expansion — no finite decimal exists
  const places = Math.max(twos, fives);
  if (places > 30) return null; // longer than any display could carry honestly
  const scaled = (rat.n * 10n ** BigInt(places)) / rat.d; // exact by construction
  const sign = scaled < 0n ? "-" : "";
  const digits = (scaled < 0n ? -scaled : scaled).toString().padStart(places + 1, "0");
  const intPart = digits.slice(0, digits.length - places);
  const fracPart = places === 0 ? "" : digits.slice(digits.length - places).replace(/0+$/, "");
  return `${sign}${intPart}${fracPart ? `.${fracPart}` : ""}`;
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
  // mathjs `fraction()` returns the best CONTINUED-FRACTION CONVERGENT, which is an
  // APPROXIMATION, not the value. For r = 1000.2 the true coefficient 1000400.04 = 25010001/25
  // came back as 10003000000/9999 — a different rational that merely agrees to the printed
  // decimals. Rendering it asserts a WRONG EXACT RATIONAL, and the substitution gate cannot
  // catch it because the decimal it verifies against does match. Build the fraction EXACTLY
  // from the value's own decimal expansion instead: n/10^m reduced, which is exact whenever
  // the coefficient terminates (it always does — every input is a decimal literal).
  const asFrac = (n: number, d: number) => ({
    isOne: false,
    isNegOne: false,
    frac: { sign: k < 0 ? "-" : "", n: Math.abs(n), d },
    decimal: trim(k),
  });
  // 1) TERMINATING — exact by construction (1000400.04 = 25010001/25).
  const exact = exactRational(k);
  if (exact && exact.d !== 1 && exact.d <= 10000) return asFrac(exact.n, exact.d);
  // 2) REPEATING — 100/3 and 4096/81 have no finite decimal, so step 1 cannot see them and
  // they are still the genuinely exact answer. mathjs's convergent is the right CANDIDATE
  // here; what was missing is that it was TRUSTED. Accept it only when it reproduces the
  // value to full double precision — that is what separates the true 100/3 from the bogus
  // 10003000000/9999, which agrees only to the digits that happen to get printed.
  try {
    const fr = fraction(Number(k.toPrecision(15))) as unknown as { n: bigint; d: bigint };
    const n = Number(fr.n);
    const d = Number(fr.d);
    if (d !== 1 && d <= 10000 && Number.isSafeInteger(n)) {
      const roundTrip = n / d;
      if (Math.abs(roundTrip - Math.abs(k)) <= Math.abs(k) * 1e-12) return asFrac(n, d);
    }
  } catch {
    /* fall through to decimal */
  }
  return { isOne: false, isNegOne: false, frac: null, decimal: trim(k) };
}

/**
 * The EXACT rational for a finite decimal, or null when it cannot be represented safely.
 *
 * `toPrecision(15)` first strips the float's representation noise (1000.2² evaluates to
 * 1000400.0400000000373, whose literal expansion is a 20-digit monster) while keeping every
 * digit the value actually carries; the remaining decimal string then converts by inspection.
 * Both parts are bounds-checked, so a coefficient too large to reduce exactly declines to a
 * decimal rather than asserting a fraction it cannot justify.
 */
function exactRational(k: number): { n: number; d: number } | null {
  if (!Number.isFinite(k)) return null;
  const s = k.toPrecision(15);
  if (/e/i.test(s)) return null; // exponent form — out of the fraction-rendering range
  const [intPart, fracPart = ""] = s.split(".");
  const digits = fracPart.replace(/0+$/, "");
  const d = 10 ** digits.length;
  const n = Number(`${intPart}${digits}`);
  if (!Number.isSafeInteger(n) || !Number.isSafeInteger(d)) return null;
  const g = gcd(Math.abs(n), d);
  if (g === 0) return null;
  return { n: n / g, d: d / g };
}

function gcd(a: number, b: number): number {
  let x = a;
  let y = b;
  while (y !== 0) {
    const t = y;
    y = x % y;
    x = t;
  }
  return x;
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
  // A TERMINATING value must print every digit it carries. Rounding to six DECIMAL PLACES is
  // a significance loss that scales with magnitude, and below 1 it eats real digits: the exact
  // coefficient of r = 0.0323 is 0.00104329 (104329/100000000 π) and it shipped as 0.001043 —
  // a WRONG exact value, and one the verify gate cannot catch because it re-derives from the
  // same rounded number. `toPrecision(15)` strips the float's representation noise while
  // keeping every digit the value actually has, so a short expansion prints as itself; only a
  // long or repeating one (1/3, π's own decimals) still needs rounding.
  // Length is a PROXY for "terminating"; the real test is whether the 15-digit expansion is
  // the value ITSELF. A given may legitimately need all 15: r = 1.9999999 has the exact area
  // coefficient 3.99999960000001, which the ≤12-digit cap rejected — so it printed as 4π, a
  // WRONG exact value the verify gate cannot catch (it re-derives from the same number). A
  // terminating decimal parses back BIT-IDENTICAL; a repeating one (1/3 → 0.333333333333333)
  // does not, and only that case still needs rounding.
  const exact = String(Number(n.toPrecision(15)));
  if (
    !/e/i.test(exact) &&
    (Number(exact) === n || exact.replace(/[-.]/g, "").replace(/^0+/, "").length <= 12)
  ) {
    return exact;
  }
  const abs = Math.abs(n);
  if (abs > 0 && abs < 1e-3) return String(Number(n.toPrecision(6)));
  return String(Number(n.toFixed(6)));
}
