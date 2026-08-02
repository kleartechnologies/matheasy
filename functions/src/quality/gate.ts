/**
 * The gate — scoring, the bar, and the one thing that is allowed to happen when
 * an explanation does not clear it.
 *
 * Regenerate the EXPLANATION. Only the explanation. The verified answer, its
 * steps, its formulas and its verification are already proven and are never
 * re-run, never re-asked, never adjusted to make a lesson easier to write. If
 * three attempts at the prose all fail, the layer returns nothing and the
 * student sees the verified answer with the app's ordinary working — which is
 * exactly what they saw before this layer existed. The floor is "no explanation",
 * never "a bad explanation", and never "a different answer".
 */
import type OpenAI from "openai";
import { logger } from "firebase-functions/v2";

import { qualityJudgeEnabled, qualityMaxAttempts } from "../config";
import { runDeterministicChecks } from "./checks";
import { judgeExplanation } from "./judge";
import {
  DIMENSION_WEIGHT,
  PASS_CRITERIA,
  PERFECT,
  QUALITY_DIMENSIONS,
  SEVERITY_PENALTY,
  type QualityFinding,
  type QualityInput,
  type QualityReport,
  type QualityScores,
} from "./types";

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

/**
 * Turn findings into six scores.
 *
 * Every dimension starts perfect and is deducted from, because the question is
 * not "how much did this explanation earn" but "what is wrong with it" — an
 * explanation with nothing wrong is a good explanation, and a rubric that made
 * prose climb to 100 from below would reward padding.
 */
export function scoreFindings(findings: QualityFinding[]): QualityScores {
  const scores: QualityScores = { ...PERFECT };
  for (const finding of findings) {
    const penalty = SEVERITY_PENALTY[finding.severity];
    scores[finding.dimension] = Math.max(0, scores[finding.dimension] - penalty);
  }
  return scores;
}

/** The weighted overall score, rounded the way it is compared. */
export function overallScore(scores: QualityScores): number {
  let total = 0;
  for (const dimension of QUALITY_DIMENSIONS) {
    total += scores[dimension] * DIMENSION_WEIGHT[dimension];
  }
  return Math.round(total * 100) / 100;
}

/**
 * Combine the two halves by taking the worse of each.
 *
 * The judge can only ever lower a score. That asymmetry is the whole reason it
 * is safe to have a model inside a safety gate: a generous or confused judge
 * cannot rescue a draft that the structural checks already rejected, so the
 * worst case of putting it there is that it catches nothing.
 */
export function mergeScores(deterministic: QualityScores, judged: QualityScores): QualityScores {
  const merged: QualityScores = { ...PERFECT };
  for (const dimension of QUALITY_DIMENSIONS) {
    merged[dimension] = Math.min(deterministic[dimension], judged[dimension]);
  }
  return merged;
}

/**
 * The bar, applied.
 *
 * Two of the six are absolute. A 99 on mathematical consistency means the prose
 * contradicts a proven solution somewhere and we have decided it is a small
 * somewhere; a 99 on visual consistency means the app is pointing at something
 * that is not there. Neither is a rounding error to a student.
 */
export function meetsBar(scores: QualityScores, overall: number): boolean {
  return (
    overall >= PASS_CRITERIA.overall &&
    scores.mathematicalConsistency >= PASS_CRITERIA.mathematicalConsistency &&
    scores.visualConsistency >= PASS_CRITERIA.visualConsistency
  );
}

/** Whether anything found is fatal on its own. */
function hasHardFailure(findings: QualityFinding[]): boolean {
  return findings.some((f) => f.severity === "hard");
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

/**
 * Score one explanation.
 *
 * The deterministic checks run first and always. The judge runs only if they
 * came back clean of hard failures — there is no point spending a reasoning call
 * on prose that already quotes a number the solver never produced, and the
 * regeneration prompt is better served by the exact structural complaint than by
 * a paragraph of opinion about a draft that was going to be thrown away.
 */
export async function evaluateQuality(
  client: OpenAI | null,
  input: QualityInput
): Promise<QualityReport> {
  const deterministic = runDeterministicChecks(input);
  const detScores = scoreFindings(deterministic);

  const skipJudge = !client || !qualityJudgeEnabled() || hasHardFailure(deterministic);
  if (skipJudge) {
    // A hard failure has already zeroed its dimension, so `meetsBar` is false
    // here by construction — the early return only saves the call, it does not
    // change the verdict.
    const overall = overallScore(detScores);
    return {
      pass: meetsBar(detScores, overall),
      overall,
      scores: detScores,
      findings: deterministic,
      judged: false,
    };
  }

  const verdict = await judgeExplanation(client, input);
  if (!verdict) {
    const overall = overallScore(detScores);
    return {
      pass: meetsBar(detScores, overall),
      overall,
      scores: detScores,
      findings: deterministic,
      judged: false,
    };
  }

  const judgeScores = mergeScores(scoreFindings(verdict.findings), verdict.scores);
  const scores = mergeScores(detScores, judgeScores);
  const overall = overallScore(scores);
  return {
    pass: meetsBar(scores, overall),
    overall,
    scores,
    findings: [...deterministic, ...verdict.findings],
    judged: true,
  };
}

// ---------------------------------------------------------------------------
// Regeneration
// ---------------------------------------------------------------------------

/**
 * The findings, rewritten as instructions for the next attempt.
 *
 * Worst first and deduplicated, because a regeneration prompt that lists the
 * same complaint six times spends its budget on emphasis rather than on the
 * other five things that were wrong.
 */
export function regenerationFeedback(findings: QualityFinding[]): string[] {
  const rank = { hard: 0, major: 1, minor: 2 } as const;
  const seen = new Set<string>();
  const out: string[] = [];
  for (const finding of [...findings].sort((a, b) => rank[a.severity] - rank[b.severity])) {
    const line = finding.field
      ? `[${finding.check}] ${finding.field}: ${finding.detail}`
      : `[${finding.check}] ${finding.detail}`;
    if (seen.has(line)) continue;
    seen.add(line);
    out.push(line);
    if (out.length >= 8) break;
  }
  return out;
}

/**
 * What a rejection looks like in the logs.
 *
 * Check ids and scores, never the student's problem and never their prose. The
 * point of this line is a dashboard that answers "which check is failing, on
 * which surface, in which language" — and none of that needs the contents of a
 * child's homework in a log sink.
 */
function logRejection(input: QualityInput, report: QualityReport, attempt: number): void {
  logger.warn("quality.rejected", {
    surface: input.surface,
    attempt,
    language: input.audience.language,
    difficulty: input.audience.difficulty,
    verificationState: input.certainty.state,
    overall: report.overall,
    scores: report.scores,
    judged: report.judged,
    checks: report.findings.map((f) => `${f.check}:${f.severity}`),
  });
}

/** What a give-up looks like. Separate severity: this one means no lesson shipped. */
function logExhausted(input: QualityInput, report: QualityReport, attempts: number): void {
  logger.error("quality.exhausted — no explanation shown", {
    surface: input.surface,
    attempts,
    language: input.audience.language,
    difficulty: input.audience.difficulty,
    overall: report.overall,
    scores: report.scores,
    checks: report.findings.map((f) => `${f.check}:${f.severity}`),
  });
}

export interface GateOptions<T> {
  client: OpenAI | null;
  /** `teach`, `practice`, `tutor` — for the logs. */
  surface: string;
  /**
   * Produce a draft. `feedback` carries the previous attempt's findings; on the
   * first attempt it is empty. This callback regenerates the EXPLANATION and
   * nothing else — it is never given the chance to re-solve.
   */
  generate: (attempt: number, feedback: string[]) => Promise<T | null>;
  /** Assemble the gate's view of a draft against the verified truth. */
  toInput: (draft: T, attempt: number) => QualityInput;
  maxAttempts?: number;
}

export interface GateResult<T> {
  /** The draft that cleared the bar, or null if none did. */
  draft: T | null;
  /** The last report, for the caller's own logging. Null if nothing generated. */
  report: QualityReport | null;
  attempts: number;
}

/**
 * Generate, check, and regenerate until it is good enough or we stop.
 *
 * "Or we stop" is doing real work here. A loop that retried forever would burn a
 * student's whole session on one paragraph, and a loop that gave up by lowering
 * the bar would be no gate at all. So it stops, and stopping means showing the
 * verified answer with no added explanation — the honest state, which the app
 * already knows how to render.
 */
export async function gateExplanation<T>(options: GateOptions<T>): Promise<GateResult<T>> {
  const max = options.maxAttempts ?? qualityMaxAttempts();
  let feedback: string[] = [];
  let lastReport: QualityReport | null = null;
  let lastInput: QualityInput | null = null;

  for (let attempt = 1; attempt <= max; attempt++) {
    const draft = await options.generate(attempt, feedback);
    if (!draft) break;

    const input = options.toInput(draft, attempt);
    lastInput = input;
    const report = await evaluateQuality(options.client, input);
    lastReport = report;

    if (report.pass) {
      if (attempt > 1) {
        logger.info("quality.passedOnRetry", {
          surface: options.surface,
          attempt,
          overall: report.overall,
        });
      }
      return { draft, report, attempts: attempt };
    }

    logRejection(input, report, attempt);
    feedback = regenerationFeedback(report.findings);
  }

  if (lastReport && lastInput) logExhausted(lastInput, lastReport, max);
  return { draft: null, report: lastReport, attempts: max };
}
