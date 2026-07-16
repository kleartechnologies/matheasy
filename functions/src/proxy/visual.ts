/**
 * `generateVisualSolution` — the Visual Learning Engine proxy (Stage 14).
 *
 * Takes a problem (plus the solver's answer, when known) and returns the
 * universal visual-solution schema the Flutter Visual tab renders: category,
 * level, renderer tier, before→after steps and optional visualization
 * metadata (graphs, number lines, shapes). PRO-ONLY: the `pro` entitlement is
 * enforced HERE, server-side, so a client can't unlock the feature by
 * spoofing UI state. Not metered — Pro usage is unlimited.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { OPENAI_API_KEY, OPENAI_MODEL, PRO_ENTITLEMENT_ID } from "../config";
import { requireUid } from "../lib/auth";
import { ensureUserDoc, getEntitlement } from "../lib/firestore";
import { assertWithinRateLimit } from "../lib/rateLimit";
import { chatJson, createOpenAI } from "../lib/openai";

interface VisualRequest {
  latex?: string;
  /** The solver's answer, so the visual walkthrough agrees with it. */
  answerLatex?: string;
  /** Coarse problem-type hint from the solver (e.g. "linear"). */
  problemType?: string;
}

/** The JSON contract the model must return — maps 1:1 to the Flutter domain. */
interface VisualPayload {
  category: string;
  difficulty: "primary" | "secondary" | "preUniversity" | "university";
  visualization:
    | "animatedTransformation"
    | "interactiveCards"
    | "conceptExplorer";
  answerLatex: string;
  intro: string;
  steps: Array<{
    title: string;
    beforeLatex: string;
    afterLatex: string;
    operationLabel?: string;
    explanation: string;
    hint?: string;
  }>;
  explanation?: { summary: string; keyIdeas: string[] };
  method?: { name: string; description: string };
  concept?: {
    kind: string;
    caption: string;
    params?: Record<string, number>;
    labels?: Record<string, string>;
    points?: Array<[number, number]>;
  };
  /**
   * Optional structured facts for a "find the missing angle" geometry problem.
   * The app draws the figure, COMPUTES the unknown and animates the steps — the
   * model must NOT compute the answer here, only relay the givens.
   */
  geometry?: {
    kind:
      | "triangleAngles"
      | "isoscelesTriangle"
      | "quadrilateralAngles"
      | "polygonAngles"
      | "straightLineAngles"
      | "anglesAroundPoint"
      | "parallelLines"
      | "circleAngle";
    /** The angles the problem GIVES you, with a short label each. */
    knownAngles: Array<{ label: string; value: number }>;
    /** The label of the single angle being solved for, e.g. "x". */
    unknown: string;
    /** Number of sides — polygonAngles only. */
    sides?: number;
    /** How the unknown relates to a known — parallelLines / circleAngle only. */
    relation?: "equal" | "supplementary" | "complementary" | "doubleOf" | "halfOf";
    /** The label of the known angle the relation refers to. */
    relationReference?: string;
    /** Human name of the rule, e.g. "Angles in a triangle sum to 180°". */
    ruleName?: string;
  };
}

const SYSTEM_PROMPT = `You are Matheasy, the friendly math tutor inside the Matheasy app, generating a VISUAL learning experience.
Break the given problem into visual transformation steps and return ONLY a JSON object (no prose, no markdown) with this exact shape:
{
  "category": "arithmetic|fractions|ratios|percentages|algebra|geometry|measurement|trigonometry|statistics|probability|functions|graphs|calculus|vectors|matrices|linearAlgebra|differentialEquations|discreteMathematics|universityMathematics",
  "difficulty": "primary|secondary|preUniversity|university",
  "visualization": "animatedTransformation|interactiveCards|conceptExplorer",
  "answerLatex": "the final answer as LaTeX",
  "intro": "one warm sentence inviting the student to watch the solution unfold",
  "steps": [
    {
      "title": "short instruction, e.g. 'Subtract 5 from both sides'",
      "beforeLatex": "the expression before this step, as LaTeX",
      "afterLatex": "the expression after this step, as LaTeX",
      "operationLabel": "optional short op chip like '− 5'",
      "explanation": "why this step works, in plain student-friendly language",
      "hint": "optional gentle hint for a stuck student"
    }
  ],
  "explanation": { "summary": "the concept-level takeaway", "keyIdeas": ["1-3 ideas worth remembering"] },
  "method": { "name": "the strategy used, e.g. 'Balance method'", "description": "one sentence describing it" },
  "concept": {
    "kind": "linearGraph|parabolaGraph|areaUnderCurve|numberLine|fractionBar|unitCircle|barChart|geometryShape|generic",
    "caption": "one sentence describing what the drawing shows",
    "params": { "numeric parameters for the kind": 0 },
    "labels": { "optional display labels": "..." },
    "points": [[0, 0]]
  }
}
Visualization tiers: use "animatedTransformation" for arithmetic, fractions, ratios, percentages and equation-solving algebra; "interactiveCards" for trigonometry, statistics, probability, matrices, vectors and advanced algebra; "conceptExplorer" for geometry, functions, graphs, calculus and university mathematics.
Concept kinds and their params: linearGraph {slope, intercept}; parabolaGraph {a, b, c}; areaUnderCurve {a, b, c, from, to}; numberLine {value, min, max}; fractionBar {numerator, denominator}; unitCircle {angleDegrees}; barChart uses points as [position, value] pairs with labels {"0": "name", ...}; geometryShape uses points as polygon vertices. Use "generic" (or omit concept) when nothing drawable fits.
GEOMETRY — when the problem is to find a single missing ANGLE (triangle, quadrilateral/polygon, angles on a line, angles around a point, isosceles, parallel lines cut by a transversal, or a circle centre/circumference angle), ALSO include a top-level "geometry" object so the app can draw and animate it:
{
  "kind": "triangleAngles|isoscelesTriangle|quadrilateralAngles|polygonAngles|straightLineAngles|anglesAroundPoint|parallelLines|circleAngle",
  "knownAngles": [{"label": "A", "value": 60}, {"label": "B", "value": 40}],
  "unknown": "x",
  "sides": 5,
  "relation": "equal|supplementary|complementary|doubleOf|halfOf",
  "relationReference": "a",
  "ruleName": "Angles in a triangle sum to 180°"
}
CRITICAL for geometry: put ONLY the angle measures the problem GIVES into knownAngles (as numbers, in degrees, no ° symbol) and name the single unknown — DO NOT compute or include the unknown's value; the app computes it deterministically and will discard your geometry object if the numbers are inconsistent. Use "sides" only for polygonAngles. Use "relation"+"relationReference" only for parallelLines (equal for alternate/corresponding, supplementary for co-interior) and circleAngle (doubleOf for the centre angle, halfOf for the circumference angle). Omit "geometry" for non-angle geometry (area, perimeter, Pythagoras) — those still use "concept".
Rules: LaTeX must be valid and delimiter-free. Provide 2-6 steps; each step's beforeLatex MUST equal the previous step's afterLatex so the animation flows. If an answer is provided by the app, your steps MUST arrive at exactly that answer. Include concept only when it genuinely aids understanding. Keep language warm and age-appropriate for the difficulty level.`;

export const generateVisualSolution = onCall(
  { secrets: [OPENAI_API_KEY], memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = requireUid(request);
    const { latex, answerLatex, problemType } = (request.data ??
      {}) as VisualRequest;

    if (!latex || typeof latex !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "latex (the problem to visualize) is required."
      );
    }

    await ensureUserDoc(uid);
    await assertWithinRateLimit(uid, "visual");

    // The Visual Learning Engine is Pro-exclusive — enforce the entitlement
    // server-side (the UI gate alone is spoofable).
    const entitlement = await getEntitlement(uid);
    if (entitlement !== PRO_ENTITLEMENT_ID) {
      throw new HttpsError(
        "permission-denied",
        "Visual Learning is a Matheasy Pro feature. Upgrade to unlock it.",
        { feature: "visualLearning", upgradeRequired: true }
      );
    }

    const userMessage = [
      `Create the visual learning experience for this problem: ${latex}`,
      answerLatex ? `The verified answer is: ${answerLatex}` : null,
      problemType ? `The solver classified it as: ${problemType}` : null,
    ]
      .filter(Boolean)
      .join("\n");

    let payload: VisualPayload;
    try {
      const client = createOpenAI(OPENAI_API_KEY.value());
      payload = await chatJson<VisualPayload>(
        client,
        OPENAI_MODEL.value(),
        SYSTEM_PROMPT,
        userMessage,
        { temperature: 0.2, maxTokens: 3000 }
      );
    } catch (err) {
      logger.error("generateVisualSolution failed", { uid, err: String(err) });
      throw new HttpsError(
        "internal",
        "Matheasy couldn't draw that one. Please try again."
      );
    }

    return { ...payload, usage: null };
  }
);
