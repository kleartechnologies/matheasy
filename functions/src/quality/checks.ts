/**
 * The fifteen checks — the half a machine can decide.
 *
 * Everything in this file is a *structural* judgement: does this number appear
 * in the verified solution, does this anchor exist, is this stage order a
 * subsequence of the canonical one, is this script the right script. None of it
 * is an opinion, none of it needs a model, and none of it computes mathematics —
 * the arithmetic ground truth arrives already proven in `VerifiedTruth` and is
 * only ever read.
 *
 * The subjective half — is this actually *clear*, is the tone right for an
 * eleven-year-old, does the Vietnamese read like Vietnamese — belongs to the
 * judge in `judge.ts`, which reads all 32 languages. Each dimension's final
 * score is the MINIMUM of the two, so neither half can wave the other's failure
 * through.
 */
import { OCR_DOUBT_THRESHOLD } from "../proxy/tutorVerification";
import { extractNumbers } from "../solver/teach";
import {
  containsAny,
  canonicalExpression,
  expectedScript,
  foldDigits,
  introducesTerm,
  isEnglish,
  matchesIn,
  proseOnly,
  readsAsEnglish,
  scriptRatio,
  sentences,
  TECHNICAL_TERMS,
  UNCERTAINTY_MARKERS,
  VAGUE_INSTRUCTIONS,
  VISUAL_DEIXIS,
  wordCount,
} from "./text";
import {
  expectedDifficulty,
  JOURNEY_ORDER,
  ROLE_COLOUR,
  type DifficultyLevel,
  type MistakeTag,
  type QualityFinding,
  type QualityInput,
} from "./types";

// ---------------------------------------------------------------------------
// Shared vocabulary
// ---------------------------------------------------------------------------

/**
 * The reading level each technical term belongs to.
 *
 * Only terms that genuinely gate comprehension are listed. A primary-school
 * lesson that says "integrand" has not merely used a long word; it has used a
 * word that carries a definition the student has no way to supply.
 */
const TERM_BAND: Record<string, "primary" | "secondary" | "preUniversity" | "university"> = {
  numerator: "primary", denominator: "primary", remainder: "primary",
  coefficient: "secondary", vertex: "secondary", hypotenuse: "secondary",
  quadratic: "secondary", polynomial: "secondary", factorise: "secondary",
  factorize: "secondary", substitute: "secondary", simplify: "secondary",
  reciprocal: "secondary", exponent: "secondary", intercept: "secondary",
  parabola: "secondary", congruent: "secondary", bisector: "secondary",
  perpendicular: "secondary", theorem: "secondary", median: "secondary",
  probability: "secondary", sine: "secondary", cosine: "secondary",
  tangent: "secondary", logarithm: "secondary", inverse: "secondary",
  discriminant: "preUniversity", asymptote: "preUniversity",
  radian: "preUniversity", derivative: "preUniversity", limit: "preUniversity",
  integral: "preUniversity", gradient: "preUniversity", variance: "preUniversity",
  quartile: "preUniversity", permutation: "preUniversity",
  combination: "preUniversity", matrix: "preUniversity",
  integrand: "university", eigenvalue: "university", determinant: "university",
  converge: "university", diverge: "university",
};

const BAND_RANK: Record<string, number> = {
  primary: 0, secondary: 1, preUniversity: 2, university: 3,
};

/** How long a sentence may run before it stops being followable, per level. */
const MAX_SENTENCE_WORDS: Record<DifficultyLevel, number> = {
  veryEasy: 16, easy: 20, medium: 26, hard: 32, expert: 40,
};

/** How short an explanation may be before it has stopped explaining, per level. */
const MIN_STEP_WORDS: Record<DifficultyLevel, number> = {
  veryEasy: 5, easy: 5, medium: 4, hard: 4, expert: 3,
};

/** English phrasing that raises each remembered mistake (check 9's English half). */
const MISTAKE_CUES: Record<MistakeTag, string[]> = {
  negativeSigns: ["negative sign", "minus sign", "sign of", "sign flips", "sign change", "watch the sign"],
  fractions: ["common denominator", "denominator", "numerator", "fraction"],
  units: ["unit", "units", "cm", "metre", "meter", "per second"],
  algebra: ["both sides", "isolate", "rearrange", "like terms"],
  orderOfOperations: ["order of operations", "bidmas", "bodmas", "pemdas", "brackets first"],
  distribution: ["distribute", "expand the bracket", "multiply every term", "each term"],
  exponents: ["exponent", "power", "index law", "indices"],
  wordProblemSetup: ["let ", "define the variable", "translate", "set up the equation"],
  geometryFormulas: ["formula for", "area of", "perimeter", "volume of", "theorem"],
  calculusRules: ["chain rule", "product rule", "quotient rule", "power rule", "constant of integration"],
};

/** Unit tokens a lesson might name. Recognition only — nothing is converted. */
const UNIT_TOKENS = [
  "mm", "cm", "m", "km", "in", "ft", "yd", "mi", "mg", "g", "kg", "lb", "oz",
  "ml", "l", "s", "min", "h", "hr", "°", "rad", "°c", "°f", "n", "j", "w",
  "m/s", "km/h", "cm²", "m²", "cm³", "m³",
];

// ---------------------------------------------------------------------------
// Ground truth, as a set
// ---------------------------------------------------------------------------

/**
 * Every number the verified solution actually contains.
 *
 * This is the whole of the mathematical-consistency check: prose may repeat any
 * of these and may not introduce others. It is set membership over a solution
 * that is already proven — the layer never asks whether a number is *right*,
 * only whether it *came from the solver*.
 */
function truthNumbers(input: QualityInput): Set<number> {
  const t = input.truth;
  const sources = [
    t.problemLatex,
    t.answerLatex ?? "",
    t.answerPlain ?? "",
    ...t.stepExpressions,
    ...(t.formulas ?? []),
  ];
  const set = new Set<number>();
  for (const src of sources) {
    for (const n of extractNumbers(foldDigits(src))) set.add(n);
  }
  // Counting and ordering language — "step 3", "both sides", "the second term".
  // These are prose about the lesson, not claims about the mathematics.
  for (let i = 0; i <= 20; i++) set.add(i);
  // The everyday reference numbers teaching prose leans on without asserting a
  // result: percentages, the degrees in a triangle, place value. Excluding them
  // would flag "the angles of a triangle add to 180°" as a smuggled answer,
  // which is a sentence we very much want lessons to contain.
  for (const anchor of [25, 30, 45, 50, 60, 90, 100, 180, 270, 360, 1000]) {
    set.add(anchor);
  }
  return set;
}

/** Numbers in the prose that the verified solution never mentions. */
function foreignNumbers(text: string, allowed: Set<number>): number[] {
  const out: number[] = [];
  for (const n of extractNumbers(foldDigits(text))) {
    if (!Number.isFinite(n)) {
      out.push(n);
      continue;
    }
    let ok = false;
    for (const a of allowed) {
      if (Math.abs(a - n) <= 1e-9 * Math.max(1, Math.abs(a))) {
        ok = true;
        break;
      }
    }
    if (!ok) out.push(n);
  }
  return out;
}

const finding = (
  check: QualityFinding["check"],
  dimension: QualityFinding["dimension"],
  severity: QualityFinding["severity"],
  detail: string,
  field?: string
): QualityFinding => ({ check, dimension, severity, detail, field });

// ---------------------------------------------------------------------------
// 1. Mathematical consistency
// ---------------------------------------------------------------------------

/**
 * Does the prose agree with the solution that was proven?
 *
 * A contradiction here is the one failure mode that makes the app worse than
 * useless — the answer on screen is right and the sentence under it is wrong, so
 * the student learns the wrong method and gets the right mark. Hard severity, no
 * appeal.
 */
export function checkMathematicalConsistency(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  const allowed = truthNumbers(input);

  for (const field of input.explanation.fields) {
    if (field.kind === "practice") continue; // practice invents its own numbers
    const foreign = foreignNumbers(field.text, allowed);
    if (foreign.length > 0) {
      out.push(
        finding(
          "mathematical_consistency",
          "mathematicalConsistency",
          "hard",
          `prose introduces ${foreign.length} value(s) absent from the verified solution: ${foreign
            .map((n) => (Number.isFinite(n) ? String(n) : "unparseable"))
            .slice(0, 5)
            .join(", ")}`,
          field.id
        )
      );
    }
  }

  // A unit the answer does not carry, asserted as if it did.
  const truthUnits = new Set((input.truth.units ?? []).map((u) => u.toLowerCase()));
  if (truthUnits.size > 0) {
    for (const field of input.explanation.fields) {
      if (field.kind !== "step" && field.kind !== "prose") continue;
      // A unit CLAIM looks like "5 cm" — a number with a unit hanging off it.
      // Requiring the digit is what keeps "let n be the count" from reading as
      // an assertion about newtons.
      const used = UNIT_TOKENS.filter((u) =>
        new RegExp(
          `\\d\\s*${u.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![a-zA-Z])`,
          "i"
        ).test(field.text)
      );
      const wrong = used.filter((u) => !truthUnits.has(u));
      if (wrong.length > 0) {
        out.push(
          finding(
            "mathematical_consistency",
            "mathematicalConsistency",
            "major",
            `names unit(s) ${wrong.join(", ")} while the verified answer is in ${[...truthUnits].join(", ")}`,
            field.id
          )
        );
      }
    }
  }

  // A variable the problem does not use.
  const truthVars = new Set(
    (input.truth.variables ?? []).map((v) => v.toLowerCase())
  );
  if (truthVars.size > 0) {
    const problemVars = new Set(
      (input.truth.problemLatex.match(/(?<![a-zA-Z\\])[a-zA-Z](?![a-zA-Z])/g) ?? []).map((v) =>
        v.toLowerCase()
      )
    );
    for (const field of input.explanation.fields) {
      if (field.kind === "practice") continue;
      const spans = field.text.match(/\$[^$]*\$/g) ?? [];
      const used = new Set<string>();
      for (const span of spans) {
        for (const v of span.match(/(?<![a-zA-Z\\])[a-zA-Z](?![a-zA-Z])/g) ?? []) {
          used.add(v.toLowerCase());
        }
      }
      const alien = [...used].filter((v) => !truthVars.has(v) && !problemVars.has(v));
      if (alien.length > 0) {
        out.push(
          finding(
            "mathematical_consistency",
            "mathematicalConsistency",
            "major",
            `uses variable(s) ${alien.join(", ")} that the problem does not contain`,
            field.id
          )
        );
      }
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// 2. Difficulty alignment
// ---------------------------------------------------------------------------

/**
 * Is it pitched where the student asked for it?
 *
 * Both directions are failures. Too hard and the lesson is noise; too easy and
 * an Expert-level student is being condescended to, which is its own way of
 * teaching nothing.
 */
export function checkDifficultyAlignment(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  const level = input.audience.difficulty;
  const maxWords = MAX_SENTENCE_WORDS[level];

  for (const field of input.explanation.fields) {
    if (field.kind === "question") continue;
    const long = sentences(field.text).filter((s) => wordCount(s) > maxWords);
    if (long.length > 0) {
      out.push(
        finding(
          "difficulty_alignment",
          "difficultyMatch",
          "major",
          `${long.length} sentence(s) run past the ${maxWords}-word limit for ${level}`,
          field.id
        )
      );
    }
  }

  // Too easy: an Expert-level lesson with no technical vocabulary at all has
  // been written for somebody else.
  if ((level === "hard" || level === "expert") && isEnglish(input.audience.language)) {
    const all = input.explanation.fields
      .filter((f) => f.kind !== "practice")
      .map((f) => f.text)
      .join(" ");
    if (proseOnly(all).length > 120 && matchesIn(all, TECHNICAL_TERMS).length === 0) {
      out.push(
        finding(
          "difficulty_alignment",
          "difficultyMatch",
          "minor",
          `pitched at ${level} but names no technical concept anywhere`
        )
      );
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// 3. Language quality
// ---------------------------------------------------------------------------

/**
 * Is it in the student's language, all the way through?
 *
 * The failure this catches is not a wholesale wrong-language response — those
 * are rare and obvious. It is the untranslated instruction stranded mid-lesson:
 * eight sentences of correct Spanish and then "Divide both sides by 2." A
 * document-wide ratio averages that away, so the check is per sentence.
 */
export function checkLanguageQuality(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  const lang = input.audience.language;
  if (isEnglish(lang)) return out;

  const script = expectedScript(lang);
  for (const field of input.explanation.fields) {
    const prose = proseOnly(field.text);
    if (prose.length < 12) continue;

    if (script) {
      const ratio = scriptRatio(field.text, script);
      if (ratio < 0.5) {
        out.push(
          finding(
            "language_quality",
            "languageQuality",
            "hard",
            `only ${Math.round(ratio * 100)}% of the letters are in the ${script} script expected for ${lang}`,
            field.id
          )
        );
        continue;
      }
      if (ratio < 0.85) {
        out.push(
          finding(
            "language_quality",
            "languageQuality",
            "major",
            `${Math.round((1 - ratio) * 100)}% of the letters are outside the ${script} script expected for ${lang}`,
            field.id
          )
        );
      }
      continue;
    }

    // Latin-script target: script tells us nothing, so read the sentences.
    const leaked = sentences(field.text).filter((s) => readsAsEnglish(s, lang));
    if (leaked.length > 0) {
      out.push(
        finding(
          "language_quality",
          "languageQuality",
          "major",
          `${leaked.length} sentence(s) read as untranslated English: "${leaked[0].slice(0, 80)}"`,
          field.id
        )
      );
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// 4. Concept introduction  /  10. Terminology
// ---------------------------------------------------------------------------

/**
 * A concept must be introduced before it is used.
 *
 * "Use the discriminant" tells a student who already knows what a discriminant
 * is to do something they could have done anyway, and tells everyone else
 * nothing. "The discriminant (b² − 4ac) tells us how many solutions exist" is
 * the same instruction plus the lesson.
 *
 * English only, by design: recognising a definition in Thai is exactly the sort
 * of judgement the judge is for, and a deterministic guess here would either
 * fire on correct prose or never fire at all.
 */
export function checkConceptIntroduction(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  if (!isEnglish(input.audience.language)) return out;

  const known = new Set(
    (input.audience.knownConcepts ?? []).map((c) => c.toLowerCase())
  );
  // Read in document order: a definition in step 4 does not help step 2.
  // Labels are excluded: a lesson titled "Solving quadratics" has not used a
  // term before defining it, it has said what the lesson is about.
  const ordered = input.explanation.fields.filter(
    (f) => f.kind !== "practice" && f.kind !== "label"
  );
  const introduced = new Set<string>();

  for (const field of ordered) {
    const lower = field.text.toLowerCase();
    for (const term of TECHNICAL_TERMS) {
      if (!new RegExp(`\\b${term}\\b`).test(lower)) continue;
      if (known.has(term) || introduced.has(term)) continue;
      if (introducesTerm(field.text, term)) {
        introduced.add(term);
        continue;
      }
      introduced.add(term); // report the first use only
      out.push(
        finding(
          "concept_introduction",
          "pedagogicalQuality",
          "major",
          `uses "${term}" before defining it and the student is not recorded as knowing it`,
          field.id
        )
      );
    }
  }

  return out;
}

/**
 * Vocabulary above the student's level, unexplained.
 *
 * Distinct from check 4: that one is about ORDER (defined, but too late); this
 * one is about REACH (a word from three years ahead of them, defined or not).
 */
export function checkTerminology(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  if (!isEnglish(input.audience.language)) return out;

  const band = input.audience.band;
  if (!band) return out;
  const ceiling = BAND_RANK[band] ?? 3;
  const known = new Set(
    (input.audience.knownConcepts ?? []).map((c) => c.toLowerCase())
  );

  for (const field of input.explanation.fields) {
    const lower = field.text.toLowerCase();
    const over = Object.keys(TERM_BAND).filter(
      (term) =>
        new RegExp(`\\b${term}\\b`).test(lower) &&
        BAND_RANK[TERM_BAND[term]] > ceiling &&
        !known.has(term) &&
        !introducesTerm(field.text, term)
    );
    if (over.length > 0) {
      out.push(
        finding(
          "terminology",
          "teachingClarity",
          "major",
          `uses ${over.join(", ")} — above the ${band} band — with no explanation`,
          field.id
        )
      );
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// 5. Visual reference consistency
// ---------------------------------------------------------------------------

/**
 * Everything the words point at must actually be on the page.
 *
 * "Look at the highlighted angle" with nothing highlighted is worse than saying
 * nothing: the student hunts for a mark that was never drawn and concludes the
 * app is broken, or worse, that they cannot see what everyone else can.
 *
 * The generator DECLARES its references (`visualRefs`) rather than us trying to
 * recognise deictic phrasing in 32 languages. A declaration is checkable against
 * the app's own inventory, exactly and everywhere.
 */
export function checkVisualReference(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  const anchorIds = new Set(input.visuals.anchors.map((a) => a.id));
  const acted = new Set(input.visuals.actions.map((a) => a.target));

  for (const field of input.explanation.fields) {
    for (const ref of field.visualRefs ?? []) {
      if (!anchorIds.has(ref)) {
        out.push(
          finding(
            "visual_reference",
            "visualConsistency",
            "hard",
            `points at "${ref}", which is not an anchor on this page`,
            field.id
          )
        );
        continue;
      }
      if (!acted.has(ref)) {
        out.push(
          finding(
            "visual_reference",
            "visualConsistency",
            "hard",
            `points at "${ref}" but no action draws it this turn`,
            field.id
          )
        );
      }
    }
  }

  // English half: prose that clearly gestures at the page while nothing at all
  // is being drawn.
  if (isEnglish(input.audience.language) && input.visuals.actions.length === 0) {
    for (const field of input.explanation.fields) {
      const deixis = matchesIn(field.text, VISUAL_DEIXIS);
      if (deixis.length > 0 && (field.visualRefs ?? []).length === 0) {
        out.push(
          finding(
            "visual_reference",
            "visualConsistency",
            "hard",
            `says "${deixis[0]}" with no visual action drawn`,
            field.id
          )
        );
      }
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// 6. Colour consistency
// ---------------------------------------------------------------------------

/**
 * One colour, one meaning, for the whole life of the app.
 *
 * Green is the unknown in every lesson a student ever sees, so by the tenth
 * problem they read the colour before they read the symbol. That only holds if
 * it is never broken, which is why a wrong colour is a hard failure over a
 * cosmetic one.
 */
export function checkColourConsistency(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  const roleById = new Map(input.visuals.anchors.map((a) => [a.id, a.role]));
  const actionRole = new Map(input.visuals.actions.map((a) => [a.target, a.role]));

  for (const field of input.explanation.fields) {
    for (const ref of field.visualRefs ?? []) {
      const drawn = actionRole.get(ref) ?? roleById.get(ref);
      if (!drawn) continue;
      if (field.role && field.role !== drawn) {
        out.push(
          finding(
            "colour_consistency",
            "visualConsistency",
            "major",
            `narrates "${ref}" as ${field.role} (${ROLE_COLOUR[field.role]}) while it is drawn as ${drawn} (${ROLE_COLOUR[drawn]})`,
            field.id
          )
        );
      }
      if (!isEnglish(input.audience.language)) continue;
      const expected = ROLE_COLOUR[drawn];
      const named = Object.values(ROLE_COLOUR).filter(
        (c) => c !== "neutral" && new RegExp(`\\b${c}\\b`, "i").test(field.text)
      );
      if (named.length > 0 && !named.includes(expected)) {
        out.push(
          finding(
            "colour_consistency",
            "visualConsistency",
            "hard",
            `says "${named[0]}" for "${ref}", which is drawn ${expected}`,
            field.id
          )
        );
      }
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// 7. Educational flow
// ---------------------------------------------------------------------------

/**
 * Understand → choose a method → apply it → simplify → verify → take away.
 *
 * A lesson may skip stages — not every problem needs a method chosen — but it
 * may not reorder them. Verifying before applying, or handing over a takeaway
 * before the work, is not a lesson in a different order; it is a lesson the
 * student cannot follow.
 */
export function checkEducationalFlow(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  const journey = input.explanation.journey;
  if (!journey || journey.length === 0) return out;

  let cursor = -1;
  for (const stage of journey) {
    const at = JOURNEY_ORDER.indexOf(stage);
    if (at < 0) {
      out.push(
        finding(
          "educational_flow",
          "pedagogicalQuality",
          "major",
          `unknown teaching stage "${stage}"`
        )
      );
      continue;
    }
    if (at < cursor) {
      out.push(
        finding(
          "educational_flow",
          "pedagogicalQuality",
          "major",
          `stage "${stage}" comes after a later stage — the journey is out of order`
        )
      );
    }
    cursor = Math.max(cursor, at);
  }

  const seen = new Set(journey);
  if (seen.size !== journey.length) {
    out.push(
      finding(
        "educational_flow",
        "pedagogicalQuality",
        "minor",
        "a teaching stage is repeated"
      )
    );
  }
  if (journey.length >= 3 && !seen.has("understand")) {
    out.push(
      finding(
        "educational_flow",
        "pedagogicalQuality",
        "minor",
        "the lesson never establishes what the problem is asking"
      )
    );
  }

  return out;
}

// ---------------------------------------------------------------------------
// 8. No hidden steps
// ---------------------------------------------------------------------------

/**
 * "We simplify" is not a step. "Divide every term by 2" is.
 *
 * The gap between those two sentences is the whole product. A student who is
 * stuck is stuck precisely at the move the first sentence omits, and a lesson
 * that omits it has narrated the solution to somebody who already had it.
 */
export function checkHiddenSteps(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  const min = MIN_STEP_WORDS[input.audience.difficulty];
  const stepFields = input.explanation.fields.filter((f) => f.kind === "step");

  for (const field of stepFields) {
    if (wordCount(field.text) < min) {
      out.push(
        finding(
          "hidden_steps",
          "teachingClarity",
          "major",
          `narrates a verified step in under ${min} words — the move itself is missing`,
          field.id
        )
      );
      continue;
    }
    if (!isEnglish(input.audience.language)) continue;
    const vague = matchesIn(field.text, VAGUE_INSTRUCTIONS);
    if (vague.length > 0 && wordCount(field.text) < min * 3) {
      out.push(
        finding(
          "hidden_steps",
          "teachingClarity",
          "major",
          `says "${vague[0]}" without naming the operation`,
          field.id
        )
      );
    }
  }

  // A narrated sequence that jumps over a verified step leaves a hole exactly
  // where the student stopped following.
  const indices = stepFields
    .map((f) => f.stepIndex)
    .filter((i): i is number => typeof i === "number")
    .sort((a, b) => a - b);
  for (let i = 1; i < indices.length; i++) {
    if (indices[i] - indices[i - 1] > 1) {
      out.push(
        finding(
          "hidden_steps",
          "teachingClarity",
          "major",
          `jumps from verified step ${indices[i - 1]} to ${indices[i]} with nothing in between`
        )
      );
    }
  }
  for (const i of indices) {
    if (i < 0 || i >= input.truth.stepExpressions.length) {
      out.push(
        finding(
          "hidden_steps",
          "teachingClarity",
          "major",
          `narrates step ${i}, which the verified solution does not have`
        )
      );
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// 9. Student memory
// ---------------------------------------------------------------------------

/**
 * The mistake they keep making, mentioned where it would bite.
 *
 * Naturally — a lesson is not a rap sheet. But a student whose recurring error
 * is dropped negative signs, walked through a problem full of negative signs
 * with no word about them, has been taught by something that does not remember
 * them.
 */
export function checkStudentMemory(input: QualityInput): QualityFinding[] {
  const mistakes = input.audience.recurringMistakes ?? [];
  if (mistakes.length === 0) return [];

  const relevant = mistakes.filter((m) => mistakeApplies(m, input));
  if (relevant.length === 0) return [];

  // Language-independent: a field carrying the `memory` role IS the reminder.
  if (input.explanation.fields.some((f) => f.role === "memory")) return [];

  if (!isEnglish(input.audience.language)) return [];

  const all = input.explanation.fields.map((f) => f.text).join(" ");
  const unmentioned = relevant.filter((m) => !containsAny(all, MISTAKE_CUES[m]));
  if (unmentioned.length === 0) return [];

  return [
    finding(
      "student_memory",
      "pedagogicalQuality",
      "minor",
      `this problem exercises the student's recurring mistake(s) ${unmentioned.join(", ")} and never mentions them`
    ),
  ];
}

/** Whether a remembered mistake is actually in play for this problem. */
function mistakeApplies(tag: MistakeTag, input: QualityInput): boolean {
  const hay = [
    input.truth.problemLatex,
    ...input.truth.stepExpressions,
    ...(input.truth.formulas ?? []),
    input.truth.problemType ?? "",
  ]
    .join(" ")
    .toLowerCase();
  switch (tag) {
    case "negativeSigns":
      return /-/.test(hay);
    case "fractions":
      return /\\frac|\//.test(hay);
    case "units":
      return (input.truth.units ?? []).length > 0;
    case "exponents":
      return /\^|\*\*/.test(hay);
    case "distribution":
      return /\(/.test(hay);
    case "orderOfOperations":
      return /\(/.test(hay) && /[+\-]/.test(hay) && /[*/]/.test(hay);
    case "calculusRules":
      return /\\int|\\frac\{d|\\lim|derivative|integral/.test(hay);
    case "geometryFormulas":
      return /triangle|circle|area|perimeter|volume|angle/.test(hay);
    case "wordProblemSetup":
      return (input.truth.problemType ?? "").toLowerCase().includes("word");
    case "algebra":
      return /=/.test(hay);
  }
}

// ---------------------------------------------------------------------------
// 11. Adaptive teaching
// ---------------------------------------------------------------------------

/**
 * A primary student does not get a university lecture.
 *
 * The band comes from the engine's own reading of the problem, so this is not a
 * guess about the reader — it is the distance between the vocabulary the lesson
 * reaches for and the vocabulary the problem itself lives in.
 */
export function checkAdaptiveTeaching(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  const band = input.audience.band;
  if (!band || !isEnglish(input.audience.language)) return out;

  const ceiling = BAND_RANK[band] ?? 3;
  if (ceiling > 1) return out; // only primary/secondary need protecting

  const all = input.explanation.fields
    .filter((f) => f.kind !== "practice")
    .map((f) => f.text)
    .join(" ")
    .toLowerCase();
  const far = Object.keys(TERM_BAND).filter(
    (term) => BAND_RANK[TERM_BAND[term]] >= ceiling + 2 && new RegExp(`\\b${term}\\b`).test(all)
  );
  if (far.length > 0) {
    out.push(
      finding(
        "adaptive_teaching",
        "difficultyMatch",
        "major",
        `a ${band}-band lesson reaches for ${far.join(", ")}`
      )
    );
  }

  return out;
}

// ---------------------------------------------------------------------------
// 12. Visual learning alignment
// ---------------------------------------------------------------------------

/**
 * The animation, the equation and the sentence are all about the same step.
 *
 * When they drift, the student is reading step 3, watching step 2 and being
 * told about step 4 — three correct things that together teach nothing. The
 * check is pure comparison: the scene's expression against the verified step's,
 * as strings.
 */
export function checkVisualLearningAlignment(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  const scenes = input.visuals.visualSteps ?? [];

  for (const scene of scenes) {
    const verified = input.truth.stepExpressions[scene.stepIndex];
    if (verified === undefined) {
      out.push(
        finding(
          "visual_learning_alignment",
          "visualConsistency",
          "hard",
          `an animation scene shows step ${scene.stepIndex}, which the verified solution does not have`
        )
      );
      continue;
    }
    if (canonicalExpression(scene.expression) !== canonicalExpression(verified)) {
      out.push(
        finding(
          "visual_learning_alignment",
          "visualConsistency",
          "hard",
          `the animation for step ${scene.stepIndex} shows "${scene.expression}" while the verified step is "${verified}"`
        )
      );
    }
  }

  // A narrated step with a scene must narrate THAT scene's step.
  const sceneIndices = new Set(scenes.map((s) => s.stepIndex));
  if (sceneIndices.size > 0) {
    for (const field of input.explanation.fields) {
      if (field.kind !== "step" || typeof field.stepIndex !== "number") continue;
      if (field.stepIndex >= 0 && !sceneIndices.has(field.stepIndex) && scenes.length >= input.truth.stepExpressions.length) {
        out.push(
          finding(
            "visual_learning_alignment",
            "visualConsistency",
            "major",
            `step ${field.stepIndex} is narrated but has no scene, while every other step has one`,
            field.id
          )
        );
      }
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// 13. OCR awareness  /  14. Verification awareness
// ---------------------------------------------------------------------------

/**
 * Whether this draft actually TELLS the student something.
 *
 * A batch of generated practice questions asserts nothing about a verified
 * solution — it poses problems — so "you sounded too sure" is not a coherent
 * complaint about it. The certainty checks are about the confidence of an
 * explanation, and where there is no explanation they have nothing to say.
 */
function assertsSomething(input: QualityInput): boolean {
  return input.explanation.fields.some((f) => f.kind === "prose" || f.kind === "step");
}

/** Whether the draft admits doubt in a way the app can see. */
function admitsDoubt(input: QualityInput): boolean {
  // Language-independent: asking the student to confirm IS the admission, and
  // the app knows a question when it generated one.
  if (input.explanation.fields.some((f) => f.kind === "question")) return true;
  if (!isEnglish(input.audience.language)) return true; // the judge reads this half
  return input.explanation.fields.some((f) => containsAny(f.text, UNCERTAINTY_MARKERS));
}

/**
 * If we are not sure we read the problem correctly, we do not sound sure.
 *
 * A confident explanation of a misread problem is the most damaging thing this
 * app can produce: it is fluent, internally consistent, and about the wrong
 * question. The student has no way to tell.
 */
export function checkOcrAwareness(input: QualityInput): QualityFinding[] {
  if (!assertsSomething(input)) return [];
  const conf = input.certainty.ocrConfidence;
  const doubtful =
    (typeof conf === "number" && conf < OCR_DOUBT_THRESHOLD) ||
    (input.certainty.uncertainMarks ?? []).length > 0 ||
    input.certainty.state === "OCR_LOW_CONFIDENCE";
  if (!doubtful) return [];
  if (admitsDoubt(input)) return [];

  return [
    finding(
      "ocr_awareness",
      "mathematicalConsistency",
      "hard",
      `the scan is uncertain (confidence ${conf ?? "?"}, ${(input.certainty.uncertainMarks ?? []).length} doubtful mark(s)) and the explanation states it as fact`
    ),
  ];
}

/**
 * What the verifier concluded decides what may be claimed.
 *
 * PASS teaches normally. LOW_CONFIDENCE teaches carefully. Under
 * VERIFIER_DISAGREEMENT there is no answer to teach — the honest move is to say
 * so and ask the student to check the problem, and asserting a result anyway is
 * the exact failure the golden rule exists to prevent.
 */
export function checkVerificationAwareness(input: QualityInput): QualityFinding[] {
  if (!assertsSomething(input)) return [];
  const out: QualityFinding[] = [];
  const state = input.certainty.state;

  if (state === "VERIFIER_DISAGREEMENT") {
    if (!input.explanation.fields.some((f) => f.kind === "question")) {
      out.push(
        finding(
          "verification_awareness",
          "mathematicalConsistency",
          "hard",
          "the verifier disagreed and the explanation never asks the student to confirm the problem"
        )
      );
    }
    const answer = input.truth.answerPlain ?? input.truth.answerLatex;
    if (answer) {
      const claimed = extractNumbers(foldDigits(answer));
      for (const field of input.explanation.fields) {
        if (field.kind === "question") continue;
        const said = new Set(extractNumbers(foldDigits(field.text)));
        if (claimed.some((n) => said.has(n))) {
          out.push(
            finding(
              "verification_awareness",
              "mathematicalConsistency",
              "hard",
              "asserts an unverified result while the verifier disagreed",
              field.id
            )
          );
          break;
        }
      }
    }
    return out;
  }

  if (state === "LOW_CONFIDENCE" && !admitsDoubt(input)) {
    out.push(
      finding(
        "verification_awareness",
        "mathematicalConsistency",
        "major",
        "verification was low-confidence and the explanation teaches as if it were certain"
      )
    );
  }

  if (!input.truth.verified && !admitsDoubt(input)) {
    out.push(
      finding(
        "verification_awareness",
        "mathematicalConsistency",
        "hard",
        "the solution is unverified and the explanation shows no uncertainty"
      )
    );
  }

  return out;
}

// ---------------------------------------------------------------------------
// 15. Practice alignment
// ---------------------------------------------------------------------------

/**
 * Practice must practise the thing that was just taught.
 *
 * A student who has just learned to complete the square and is handed a
 * trigonometry question has been given homework, not practice. Same concept,
 * requested difficulty, nothing else.
 */
export function checkPracticeAlignment(input: QualityInput): QualityFinding[] {
  const out: QualityFinding[] = [];
  const items = input.practice ?? [];
  if (items.length === 0) return out;

  const wanted = input.audience.difficulty;
  const taught = new Set(
    [
      ...(input.truth.formulas ?? []),
      input.truth.problemType ?? "",
      ...(input.audience.knownConcepts ?? []),
    ]
      .filter(Boolean)
      .map((c) => c.toLowerCase())
  );

  for (const item of items) {
    if (!item.prompt.trim()) {
      out.push(
        finding("practice_alignment", "pedagogicalQuality", "hard", "empty practice prompt", item.id)
      );
      continue;
    }
    const expected = expectedDifficulty(wanted, item.rung);
    if (item.difficulty !== expected) {
      out.push(
        finding(
          "practice_alignment",
          "pedagogicalQuality",
          "major",
          `practice item is ${item.difficulty} but ${expected} was expected${
            item.rung ? ` for the "${item.rung}" rung of a ${wanted} ladder` : ""
          }`,
          item.id
        )
      );
    }
    const concepts = (item.concepts ?? []).map((c) => c.toLowerCase());
    if (taught.size > 0 && concepts.length > 0) {
      const overlap = concepts.some((c) =>
        [...taught].some((t) => t.includes(c) || c.includes(t))
      );
      if (!overlap) {
        out.push(
          finding(
            "practice_alignment",
            "pedagogicalQuality",
            "major",
            `practises ${concepts.join(", ")}, none of which was taught here`,
            item.id
          )
        );
      }
    }
    if (item.skill && taught.size > 0) {
      const skill = item.skill.toLowerCase();
      const matches = [...taught].some((t) => t.includes(skill) || skill.includes(t));
      if (!matches && concepts.length === 0) {
        out.push(
          finding(
            "practice_alignment",
            "pedagogicalQuality",
            "minor",
            `practice skill "${item.skill}" does not name anything from this lesson`,
            item.id
          )
        );
      }
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// The whole battery
// ---------------------------------------------------------------------------

/**
 * Every deterministic check, in spec order.
 *
 * Cheap enough to run on every generation and on every retry, which is the
 * point: the model-backed judge only ever sees drafts that already survived
 * this, so the expensive opinion is never spent on prose with a number in it
 * that the solver never produced.
 */
export function runDeterministicChecks(input: QualityInput): QualityFinding[] {
  return [
    ...checkMathematicalConsistency(input),
    ...checkDifficultyAlignment(input),
    ...checkLanguageQuality(input),
    ...checkConceptIntroduction(input),
    ...checkVisualReference(input),
    ...checkColourConsistency(input),
    ...checkEducationalFlow(input),
    ...checkHiddenSteps(input),
    ...checkStudentMemory(input),
    ...checkTerminology(input),
    ...checkAdaptiveTeaching(input),
    ...checkVisualLearningAlignment(input),
    ...checkOcrAwareness(input),
    ...checkVerificationAwareness(input),
    ...checkPracticeAlignment(input),
  ];
}

/** Exposed for the tests that assert the lexicons stay in sync with the bands. */
export const __testing = { TERM_BAND, MISTAKE_CUES, truthNumbers, foreignNumbers };
