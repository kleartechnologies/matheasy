/**
 * Turning what the app actually produces into what the gate can read.
 *
 * The three surfaces that put words in front of a student — the teaching layer,
 * the practice generator and Numi's replies — all have their own shapes, none of
 * which the checks should know about. Each adapter does the same two things:
 * flatten the prose into addressable fields, and copy the verified solution
 * across as ground truth.
 *
 * "Copy across" is literal. Nothing here derives, normalises, rounds or re-reads
 * a mathematical value; every number the gate compares against arrives already
 * proven, straight off the cached solve.
 */
import type {
  MethodData,
  SolvePayload,
  TeachingLayer,
} from "../solver/types";
import type { SemanticAnchor } from "./../proxy/anchors";
import type { ActionType } from "../proxy/tutorActions";
import type { AnchorRole } from "../proxy/anchors";
import type { VerificationState } from "../proxy/tutorVerification";
import {
  expectedDifficulty,
  type Audience,
  type CertaintyContext,
  type DifficultyLevel,
  type ExplanationField,
  type PracticeDraft,
  type QualityInput,
  type VerifiedTruth,
  type VisualInventory,
} from "./types";

/** The exam-pick method is the one a teacher would mark, so it is the one taught. */
function examPick(methods: MethodData[]): MethodData | undefined {
  return methods.find((m) => m.examPick) ?? methods[0];
}

/**
 * The verified solution, lifted out of the payload as fact.
 *
 * `stepExpressions` comes from `StepData.expression`, which the spec pins as the
 * ONLY math field the engine owns and the LLM may never author — which is
 * exactly why it is the right thing for a quality gate to measure prose against.
 */
export function truthFromPayload(payload: SolvePayload, methods?: MethodData[]): VerifiedTruth {
  const method = examPick(methods ?? payload.methods ?? []);
  const steps = method?.steps ?? [];
  return {
    problemLatex: payload.problemLatex,
    answerLatex: payload.finalAnswer?.latex,
    answerPlain: payload.finalAnswer?.plain,
    stepExpressions: steps.map((s) => s.expression),
    stepOperations: steps.map((s) => s.operation),
    formulas: steps.map((s) => s.rule).filter((r): r is string => Boolean(r)),
    verified: payload.verified === true,
    problemType: payload.problemType,
  };
}

/** Nothing on screen — the shape every text-only surface passes in. */
export const NO_VISUALS: VisualInventory = { anchors: [], actions: [] };

/** Build the visual inventory from what the tutor turn will actually draw. */
export function visualsFrom(
  anchors: SemanticAnchor[],
  actions: Array<{ type: ActionType; target: string; role: AnchorRole }>,
  visualSteps?: Array<{ stepIndex: number; expression: string }>
): VisualInventory {
  return { anchors, actions, visualSteps };
}

/**
 * The engine's own difficulty band, mapped onto the student-facing ladder.
 *
 * Only used when the caller has no explicit selection to pass — a scanned
 * problem does not come with a difficulty the student chose, and pretending it
 * is always "medium" would make check 2 fire on every correct primary lesson.
 */
export function difficultyFromBand(band: TeachingLayer["header"]["difficulty"]): DifficultyLevel {
  switch (band) {
    case "primary":
      return "easy";
    case "secondary":
      return "medium";
    case "preUniversity":
      return "hard";
    case "university":
      return "expert";
    default:
      return "medium";
  }
}

// ---------------------------------------------------------------------------
// The teaching layer
// ---------------------------------------------------------------------------

/**
 * Every piece of prose in a teaching layer, addressable.
 *
 * The ids are dotted paths into the document so a finding can be traced back to
 * the field that caused it and the regeneration prompt can name it — "fix
 * `journey.2.summary`" is actionable in a way that "fix the explanation" is not.
 *
 * `predictionPrompt` and `selfExplainPrompt` come across as `question` fields.
 * That is not a cosmetic distinction: a question is not an assertion, so it is
 * exempt from the claims checks and it is what satisfies the "ask the student to
 * confirm" requirement under an uncertain read.
 */
export function fieldsFromTeaching(
  teaching: TeachingLayer,
  methods: MethodData[]
): ExplanationField[] {
  const fields: ExplanationField[] = [];
  const prose = (id: string, text: string | undefined) => {
    if (text && text.trim()) fields.push({ id, kind: "prose", text });
  };

  const label = (id: string, text: string | undefined) => {
    if (text && text.trim()) fields.push({ id, kind: "label", text });
  };

  label("header.learningObjective", teaching.header.learningObjective);
  prose("header.whyMethodChosen", teaching.header.whyMethodChosen);
  label("header.subcategory", teaching.header.subcategory);
  prose("overview.asked", teaching.overview.asked);
  prose("overview.goal", teaching.overview.goal);
  if (teaching.overview.predictionPrompt?.trim()) {
    fields.push({
      id: "overview.predictionPrompt",
      kind: "question",
      text: teaching.overview.predictionPrompt,
    });
  }
  prose("concept.body", teaching.concept.body);
  teaching.concept.definedTerms.forEach((term, i) => {
    prose(`concept.definedTerms.${i}`, `${term.term} is ${term.plain}`);
  });
  teaching.methodRationale.alternatives.forEach((alt, i) => {
    prose(`methodRationale.${i}`, `${alt.name}: ${alt.whenBetter}`);
  });
  (teaching.translation ?? []).forEach((line, i) => prose(`translation.${i}`, line));
  (teaching.decompositionPlan ?? []).forEach((line, i) => prose(`decompositionPlan.${i}`, line));
  (teaching.approach ?? []).forEach((line, i) => prose(`approach.${i}`, line));

  // The journey's stages point at verified steps, so their summaries are the
  // fields that must survive the step checks.
  teaching.journey.forEach((stage, i) => {
    if (!stage.summary?.trim()) return;
    fields.push({
      id: `journey.${i}.summary`,
      kind: "step",
      text: stage.summary,
      stepIndex: stage.stepIndices[0],
    });
  });

  // The exam-pick method's per-step narration is the real step-by-step lesson.
  const steps = examPick(methods)?.steps ?? [];
  steps.forEach((step, i) => {
    const push = (suffix: string, text: string | undefined) => {
      if (text && text.trim()) {
        fields.push({ id: `steps.${i}.${suffix}`, kind: "step", text, stepIndex: i });
      }
    };
    push("why", step.why);
    push("explanation", step.explanation);
    push("commonMistake", step.commonMistake);
    // The rule is the name of the law being applied, not a narration of it.
    if (step.rule?.trim()) {
      fields.push({ id: `steps.${i}.rule`, kind: "label", text: step.rule, stepIndex: i });
    }
    if (step.selfExplainPrompt?.trim()) {
      fields.push({
        id: `steps.${i}.selfExplainPrompt`,
        kind: "question",
        text: step.selfExplainPrompt,
        stepIndex: i,
      });
    }
  });

  teaching.commonMistakes.forEach((mistake, i) => {
    prose(`commonMistakes.${i}.mistake`, mistake.mistake);
    prose(`commonMistakes.${i}.whyTempting`, mistake.whyTempting);
    prose(`commonMistakes.${i}.fix`, mistake.fix);
  });
  prose("keyTakeaway.headline", teaching.keyTakeaway.headline);
  prose("keyTakeaway.detail", teaching.keyTakeaway.detail);

  return fields;
}

/** The practice ladder, as items the gate can check against what was taught. */
export function practiceFromLadder(
  teaching: TeachingLayer,
  difficulty: DifficultyLevel
): PracticeDraft[] {
  const ladder = teaching.practiceLadder;
  if (!ladder) return [];
  return (["easier", "similar", "harder"] as const).map((rung) => ({
    id: `practiceLadder.${rung}`,
    prompt: ladder[rung].latex,
    skill: ladder[rung].skillHint ?? teaching.header.subcategory,
    // A ladder deliberately straddles the level, so each rung declares which one
    // it is and is checked one step either side rather than against the middle.
    rung,
    difficulty: expectedDifficulty(difficulty, rung),
    concepts: [teaching.header.subcategory],
  }));
}

export interface TeachingReviewContext {
  payload: SolvePayload;
  teaching: TeachingLayer;
  methods: MethodData[];
  language: string;
  difficulty?: DifficultyLevel;
  knownConcepts?: string[];
  recurringMistakes?: Audience["recurringMistakes"];
  certainty?: Partial<CertaintyContext>;
  visuals?: VisualInventory;
  attempt?: number;
}

/** A teaching layer, ready for the gate. */
export function teachingToQualityInput(ctx: TeachingReviewContext): QualityInput {
  const band = ctx.teaching.header.difficulty;
  const difficulty = ctx.difficulty ?? difficultyFromBand(band);
  return {
    explanation: {
      fields: fieldsFromTeaching(ctx.teaching, ctx.methods),
      journey: ctx.teaching.journey.map((stage) => stage.id),
      attempt: ctx.attempt ?? 1,
    },
    truth: truthFromPayload(ctx.payload, ctx.methods),
    audience: {
      language: ctx.language,
      difficulty,
      band,
      knownConcepts: ctx.knownConcepts,
      recurringMistakes: ctx.recurringMistakes,
    },
    visuals: ctx.visuals ?? NO_VISUALS,
    certainty: {
      state: ctx.certainty?.state ?? (ctx.payload.verified ? "PASS" : "VERIFIER_DISAGREEMENT"),
      ocrConfidence: ctx.certainty?.ocrConfidence,
      uncertainMarks: ctx.certainty?.uncertainMarks,
    },
    practice: practiceFromLadder(ctx.teaching, difficulty),
    surface: "teach",
  };
}

// ---------------------------------------------------------------------------
// Practice
// ---------------------------------------------------------------------------

export interface PracticeReviewContext {
  truth: VerifiedTruth;
  items: PracticeDraft[];
  language: string;
  difficulty: DifficultyLevel;
  knownConcepts?: string[];
  attempt?: number;
}

/**
 * A batch of generated practice questions.
 *
 * The prompts themselves are the explanation here — a practice question IS the
 * teaching artefact — so they enter as `practice` fields, which are exempt from
 * the "no number the solver did not produce" rule. A new question is supposed to
 * contain new numbers; it is checked for teaching the same CONCEPT at the same
 * level, which is check 15's whole subject.
 */
export function practiceToQualityInput(ctx: PracticeReviewContext): QualityInput {
  return {
    explanation: {
      fields: ctx.items.map((item) => ({
        id: item.id,
        kind: "practice" as const,
        text: [item.prompt, item.explanation].filter(Boolean).join("\n"),
      })),
      attempt: ctx.attempt ?? 1,
    },
    truth: ctx.truth,
    audience: {
      language: ctx.language,
      difficulty: ctx.difficulty,
      knownConcepts: ctx.knownConcepts,
    },
    visuals: NO_VISUALS,
    certainty: { state: ctx.truth.verified ? "PASS" : "LOW_CONFIDENCE" },
    practice: ctx.items,
    surface: "practice",
  };
}

// ---------------------------------------------------------------------------
// Numi
// ---------------------------------------------------------------------------

export interface TutorReviewContext {
  reply: string;
  truth: VerifiedTruth;
  language: string;
  difficulty: DifficultyLevel;
  state: VerificationState;
  anchors?: SemanticAnchor[];
  actions?: Array<{ type: ActionType; target: string; role: AnchorRole }>;
  visualRefs?: string[];
  ocrConfidence?: number;
  uncertainMarks?: string[];
  recurringMistakes?: Audience["recurringMistakes"];
  attempt?: number;
}

/**
 * One Numi turn.
 *
 * Numi streams to the student, so she cannot be gated the way a cached teaching
 * layer can — a judge in the middle of a stream is a two-second pause with a
 * half-written sentence on screen. What she gets is the deterministic subset,
 * run after the fact on the assembled reply: it is fast, and it catches the
 * failures that matter most here, which are a dangling visual reference and a
 * number nobody proved.
 */
export function tutorToQualityInput(ctx: TutorReviewContext): QualityInput {
  return {
    explanation: {
      fields: [
        {
          id: "reply",
          kind: "prose",
          text: ctx.reply,
          visualRefs: ctx.visualRefs,
        },
      ],
      attempt: ctx.attempt ?? 1,
    },
    truth: ctx.truth,
    audience: {
      language: ctx.language,
      difficulty: ctx.difficulty,
      recurringMistakes: ctx.recurringMistakes,
    },
    visuals: { anchors: ctx.anchors ?? [], actions: ctx.actions ?? [] },
    certainty: {
      state: ctx.state,
      ocrConfidence: ctx.ocrConfidence,
      uncertainMarks: ctx.uncertainMarks,
    },
    surface: "tutor",
  };
}
