/**
 * The judge — the half of the fifteen checks that needs to READ.
 *
 * `checks.ts` can prove that a number came from the solver, that an anchor
 * exists, that a stage order is legal. It cannot tell whether a Vietnamese
 * paragraph explains the chain rule or merely mentions it, and no amount of
 * regex will let it. That is what this is for: a reasoning model that reads all
 * 32 languages, scoring the same six dimensions against the same fifteen checks.
 *
 * Three rules make it safe to have a model in a quality gate at all:
 *
 *   1. **It never computes.** The verified solution is handed to it as
 *      established fact. It is asked whether the PROSE AGREES with that fact —
 *      never what the answer should be. A judge that could re-derive the maths
 *      would be a second source of mathematical truth, which is precisely what
 *      the golden rule forbids.
 *   2. **It never writes.** Its entire output is scores and findings. It cannot
 *      edit an explanation, and nothing it says reaches a student.
 *   3. **It can only lower.** Each dimension's final score is the MINIMUM of the
 *      deterministic score and the judge's, so a generous judge cannot wave
 *      through a draft that `checks.ts` already failed. It is a second pair of
 *      eyes, never an appeal court.
 */
import type OpenAI from "openai";
import { logger } from "firebase-functions/v2";

import { chatJson } from "../lib/openai";
import { languageName } from "../lib/language";
import {
  CHECK_IDS,
  PERFECT,
  QUALITY_DIMENSIONS,
  ROLE_COLOUR,
  type CheckId,
  type QualityDimension,
  type QualityFinding,
  type QualityInput,
  type QualityScores,
  type Severity,
} from "./types";

/** What the judge returns, before it is sanitised. */
interface RawVerdict {
  scores?: Partial<Record<string, unknown>>;
  findings?: Array<Record<string, unknown>>;
}

export interface JudgeVerdict {
  scores: QualityScores;
  findings: QualityFinding[];
}

/** How many findings we will carry out of one judgement. */
const MAX_FINDINGS = 12;

const CHECK_SET = new Set<string>(CHECK_IDS);
const DIMENSION_SET = new Set<string>(QUALITY_DIMENSIONS);
const SEVERITY_SET = new Set<string>(["hard", "major", "minor"]);

const JUDGE_SYSTEM = `You are the educational quality reviewer for Matheasy, a maths tutor for students aged 8-22.

You are NOT a mathematician here and you are NOT a solver. You will be given a solution that has ALREADY been computed deterministically and PROVEN by substituting it back into the original problem. That solution is FACT. You must never recompute it, never check its arithmetic, never suggest a different answer, and never comment on whether it is correct. If you believe the maths is wrong, you are wrong — say nothing about it.

Your only question is: IS THIS EXPLANATION A GOOD LESSON, AND DOES IT AGREE WITH THE PROVEN SOLUTION?

Judge the explanation against these fifteen checks:
1. mathematical_consistency — every claim in the prose matches the verified answer, steps, formulas, substitutions, units, signs and variables. Any contradiction is fatal.
2. difficulty_alignment — pitched at the student's stated difficulty. Too hard AND too easy both fail.
3. language_quality — written entirely in the student's language. No mixed languages, no untranslated mathematical sentences, natural phrasing a native speaker would use.
4. concept_introduction — a concept is introduced before it is used. "Use the discriminant" is bad; "the discriminant (b²-4ac) tells us how many solutions exist" is good.
5. visual_reference — every reference to something on the page ("this highlighted angle", "look at the triangle") corresponds to a visual the app is actually drawing. Dangling references are fatal.
6. colour_consistency — the teaching colours are fixed: unknown=green, known=blue, formula/operation=purple, mistake=red, hint=orange, concept=teal, final answer=gold, memory=yellow. Prose that names a colour must name the right one.
7. educational_flow — understand, choose a method, apply it, simplify, verify, take away. Stages may be skipped; they may not be reordered.
8. hidden_steps — no step is glossed. "We simplify." fails. "Divide every term by 2." passes.
9. student_memory — a mistake the student keeps making, when this problem exercises it, is mentioned naturally.
10. terminology — every term is either already known to the student or explained where it appears.
11. adaptive_teaching — matches the student's age, level, difficulty and history. No university register for a primary student.
12. visual_learning_alignment — the animation, the equation, the step card and the sentence all describe the same step.
13. ocr_awareness — if the scan was uncertain, the explanation expresses that uncertainty. Never explain an uncertain reading confidently.
14. verification_awareness — PASS teaches normally; LOW_CONFIDENCE teaches carefully; VERIFIER_DISAGREEMENT explains the uncertainty and asks the student to confirm the problem. Never pretend certainty you were not given.
15. practice_alignment — generated practice teaches the SAME concept at the requested difficulty, with no unrelated topic.

Score six dimensions from 0 to 100:
- mathematicalConsistency: does the prose agree with the proven solution? 100 unless something actually contradicts it.
- teachingClarity: could a student at this level follow it without help?
- difficultyMatch: is it at the requested level, in both directions?
- languageQuality: is it fluent, complete, and entirely in the target language?
- visualConsistency: does everything it points at exist, in the right colour, about the right step?
- pedagogicalQuality: is it teaching — introducing, sequencing, reminding — or just narrating?

Be strict. The bar for shipping is 95 overall with mathematicalConsistency and visualConsistency at a perfect 100. An explanation that is merely acceptable scores in the 80s.

Return JSON only:
{"scores":{"mathematicalConsistency":0-100,"teachingClarity":0-100,"difficultyMatch":0-100,"languageQuality":0-100,"visualConsistency":0-100,"pedagogicalQuality":0-100},"findings":[{"check":"<one of the fifteen check ids>","dimension":"<one of the six dimension names>","severity":"hard|major|minor","detail":"<one sentence, in English, naming what is wrong>","field":"<the field id, if it is in one field>"}]}

"detail" is read by engineers and by the regeneration prompt. It is never shown to a student, so write it plainly. Report at most ${MAX_FINDINGS} findings, worst first. If the explanation is good, return an empty findings array — do not invent problems to look thorough.`;

/**
 * The dossier the judge reads.
 *
 * Deliberately assembled by the app rather than described in prose: the anchors,
 * the actions and the verified steps are the app's own inventory, so the judge
 * is checking the explanation against ground truth it cannot influence.
 */
function buildDossier(input: QualityInput): string {
  const t = input.truth;
  const a = input.audience;

  return JSON.stringify(
    {
      provenSolution: {
        problem: t.problemLatex,
        answer: t.answerLatex ?? t.answerPlain ?? null,
        steps: t.stepExpressions,
        operations: t.stepOperations ?? [],
        formulas: t.formulas ?? [],
        units: t.units ?? [],
        variables: t.variables ?? [],
        problemType: t.problemType ?? null,
        verified: t.verified,
        note: "Already proven by substitution. Treat as fact. Do not recompute.",
      },
      student: {
        language: `${a.language} (${languageName(a.language)})`,
        requestedDifficulty: a.difficulty,
        engineBand: a.band ?? null,
        recurringMistakes: a.recurringMistakes ?? [],
        alreadyKnows: a.knownConcepts ?? [],
      },
      onScreen: {
        anchors: input.visuals.anchors.map((anchor) => ({
          id: anchor.id,
          label: anchor.label,
          type: anchor.type,
          role: anchor.role,
          colour: ROLE_COLOUR[anchor.role],
        })),
        actionsBeingDrawn: input.visuals.actions.map((action) => ({
          target: action.target,
          type: action.type,
          colour: ROLE_COLOUR[action.role],
        })),
        animationScenes: input.visuals.visualSteps ?? [],
      },
      certainty: {
        verificationState: input.certainty.state,
        ocrConfidence: input.certainty.ocrConfidence ?? null,
        marksTheReaderDoubted: input.certainty.uncertainMarks ?? [],
      },
      explanationUnderReview: input.explanation.fields.map((field) => ({
        id: field.id,
        kind: field.kind,
        narratesStep: field.stepIndex ?? null,
        pointsAt: field.visualRefs ?? [],
        colourRole: field.role ?? null,
        text: field.text,
      })),
      teachingJourney: input.explanation.journey ?? [],
      practiceUnderReview: (input.practice ?? []).map((item) => ({
        id: item.id,
        prompt: item.prompt,
        skill: item.skill,
        difficulty: item.difficulty,
        concepts: item.concepts ?? [],
      })),
    },
    null,
    1
  );
}

/** Clamp anything the model returned into a real 0-100 score. */
function score(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return 100; // absent ≠ zero; the deterministic half still applies
  return Math.max(0, Math.min(100, Math.round(n)));
}

/**
 * Keep only findings that name a real check, dimension and severity.
 *
 * A judge that invents a sixteenth check is a judge whose output would land in
 * dashboards nobody can group. Anything unrecognised is dropped rather than
 * coerced — a mislabelled finding scored against the wrong dimension is worse
 * than a missing one, because the missing one still costs its dimension points
 * through the score.
 */
function sanitiseFindings(raw: unknown): QualityFinding[] {
  if (!Array.isArray(raw)) return [];
  const out: QualityFinding[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== "object") continue;
    const rec = entry as Record<string, unknown>;
    const check = String(rec.check ?? "");
    const dimension = String(rec.dimension ?? "");
    const severity = String(rec.severity ?? "");
    const detail = String(rec.detail ?? "").trim();
    if (!CHECK_SET.has(check)) continue;
    if (!DIMENSION_SET.has(dimension)) continue;
    if (!SEVERITY_SET.has(severity)) continue;
    if (!detail) continue;
    const field = typeof rec.field === "string" && rec.field.trim() ? rec.field.trim() : undefined;
    out.push({
      check: check as CheckId,
      dimension: dimension as QualityDimension,
      severity: severity as Severity,
      detail: detail.slice(0, 400),
      field,
    });
    if (out.length >= MAX_FINDINGS) break;
  }
  return out;
}

/**
 * Ask the judge. Returns null when it could not be reached.
 *
 * Null is not a pass and not a failure — it means this run has only the
 * deterministic half, and the gate records `judged:false` so the difference is
 * visible in the logs. Degrading to the structural checks is the right failure
 * mode: an OpenAI blip must not strip the teaching layer off every lesson in the
 * app, and the verified answer the student came for is untouched either way.
 */
export async function judgeExplanation(
  client: OpenAI,
  input: QualityInput
): Promise<JudgeVerdict | null> {
  try {
    const raw = await chatJson<RawVerdict>(
      client,
      "quality",
      JUDGE_SYSTEM,
      buildDossier(input),
      { maxTokens: 1200 }
    );
    const scores: QualityScores = { ...PERFECT };
    const given = (raw?.scores ?? {}) as Record<string, unknown>;
    for (const dimension of QUALITY_DIMENSIONS) {
      scores[dimension] = score(given[dimension]);
    }
    return { scores, findings: sanitiseFindings(raw?.findings) };
  } catch (err) {
    logger.warn("quality.judgeUnavailable — falling back to the deterministic checks", {
      surface: input.surface,
      attempt: input.explanation.attempt ?? 1,
      err: String(err),
    });
    return null;
  }
}

export const __testing = { JUDGE_SYSTEM, buildDossier, sanitiseFindings, score };
