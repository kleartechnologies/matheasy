/**
 * The educational quality gate — the fifteen checks.
 *
 * Every test here defends the same property from a different angle: **a student
 * never reads an explanation that disagrees with the solution the app proved.**
 * Not the answer — the answer is already guarded by the substitution gate and is
 * untouchable from this layer. The words. An explanation that quotes a number
 * the solver never produced, points at a highlight nobody drew, slips back into
 * English halfway through, or says "we simplify" where a student is stuck, has
 * failed in a way the golden rule cannot see and the maths cannot fix.
 *
 * The other property, defended just as hard: **this layer never computes.**
 * There is no test below that asserts what an answer should be, because there is
 * no code path that could produce one.
 */
import { describe, expect, it } from "vitest";

import {
  checkAdaptiveTeaching,
  checkColourConsistency,
  checkConceptIntroduction,
  checkDifficultyAlignment,
  checkEducationalFlow,
  checkHiddenSteps,
  checkLanguageQuality,
  checkMathematicalConsistency,
  checkOcrAwareness,
  checkPracticeAlignment,
  checkStudentMemory,
  checkTerminology,
  checkVerificationAwareness,
  checkVisualLearningAlignment,
  checkVisualReference,
  runDeterministicChecks,
} from "../src/quality/checks";
import {
  CHECK_IDS,
  QUALITY_DIMENSIONS,
  type ExplanationField,
  type QualityFinding,
  type QualityInput,
} from "../src/quality/types";
import type { SemanticAnchor } from "../src/proxy/anchors";
import {
  canonicalExpression,
  foldDigits,
  proseOnly,
  readsAsEnglish,
  scriptRatio,
  wordCount,
} from "../src/quality/text";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/** `2x + 4 = 10`, solved and proven. The baseline every test starts from. */
function truth(over: Partial<QualityInput["truth"]> = {}): QualityInput["truth"] {
  return {
    problemLatex: "2x + 4 = 10",
    answerLatex: "x = 3",
    answerPlain: "x = 3",
    stepExpressions: ["2x = 6", "x = 3"],
    stepOperations: ["Subtract 4 from both sides", "Divide both sides by 2"],
    verified: true,
    problemType: "linear equation",
    ...over,
  };
}

function anchor(over: Partial<SemanticAnchor> = {}): SemanticAnchor {
  return {
    id: "angle_B",
    type: "angle",
    label: "28°",
    role: "known",
    box: { x: 0.1, y: 0.1, w: 0.1, h: 0.05 },
    confidence: 0.9,
    ...over,
  };
}

function field(over: Partial<ExplanationField> = {}): ExplanationField {
  return { id: "overview.goal", kind: "prose", text: "Find the value of x.", ...over };
}

function input(over: Partial<QualityInput> = {}): QualityInput {
  return {
    explanation: { fields: [field()] },
    truth: truth(),
    audience: { language: "en", difficulty: "medium" },
    visuals: { anchors: [], actions: [] },
    certainty: { state: "PASS" },
    surface: "test",
    ...over,
  };
}

/** The ids of every finding, so a test can name what it expects to fire. */
const ids = (findings: QualityFinding[]) => findings.map((f) => f.check);

// ---------------------------------------------------------------------------

describe("the contract", () => {
  it("names fifteen checks and six dimensions", () => {
    expect(CHECK_IDS).toHaveLength(15);
    expect(QUALITY_DIMENSIONS).toHaveLength(6);
  });

  it("every check id is unique and stable snake_case — these land in dashboards", () => {
    expect(new Set(CHECK_IDS).size).toBe(CHECK_IDS.length);
    for (const id of CHECK_IDS) expect(id).toMatch(/^[a-z]+(_[a-z]+)*$/);
  });

  it("a clean explanation trips nothing at all", () => {
    const findings = runDeterministicChecks(
      input({
        explanation: {
          fields: [
            field({ id: "overview.goal", text: "Find the value of x in this equation." }),
            field({
              id: "steps.0.why",
              kind: "step",
              stepIndex: 0,
              text: "Subtract 4 from both sides so the x term stands alone.",
            }),
            field({
              id: "steps.1.why",
              kind: "step",
              stepIndex: 1,
              text: "Divide both sides by 2 to leave x by itself.",
            }),
          ],
          journey: ["understand", "apply", "verify"],
        },
      })
    );
    expect(findings).toEqual([]);
  });
});

// --- 1. Mathematical consistency --------------------------------------------

describe("check 1 — mathematical consistency", () => {
  it("rejects a number the verified solution never produced", () => {
    const findings = checkMathematicalConsistency(
      input({
        explanation: {
          fields: [field({ text: "Divide both sides by 42 and you are done." })],
        },
      })
    );
    expect(ids(findings)).toContain("mathematical_consistency");
    expect(findings[0].severity).toBe("hard");
    expect(findings[0].dimension).toBe("mathematicalConsistency");
  });

  it("accepts every number that IS in the problem, the steps or the answer", () => {
    const findings = checkMathematicalConsistency(
      input({
        explanation: {
          fields: [
            field({ text: "We had $2x + 4 = 10$, then $2x = 6$, so $x = 3$." }),
          ],
        },
      })
    );
    expect(findings).toEqual([]);
  });

  it("lets teaching prose say 180 without calling it a smuggled answer", () => {
    const findings = checkMathematicalConsistency(
      input({
        truth: truth({ problemLatex: "x + 40 + 65 = 180", stepExpressions: ["x = 75"] }),
        explanation: {
          fields: [field({ text: "The angles inside a triangle always add to 180 degrees." })],
        },
      })
    );
    expect(findings).toEqual([]);
  });

  it("reads Arabic-Indic and Devanagari digits as numbers, not as foreign values", () => {
    const findings = checkMathematicalConsistency(
      input({
        audience: { language: "ar", difficulty: "medium" },
        explanation: { fields: [field({ text: "اقسم الطرفين على ٢ لتحصل على ٣." })] },
      })
    );
    expect(findings).toEqual([]);
  });

  it("still catches a foreign number written in Devanagari digits", () => {
    const findings = checkMathematicalConsistency(
      input({
        audience: { language: "hi", difficulty: "medium" },
        explanation: { fields: [field({ text: "दोनों पक्षों को ४२ से भाग दें।" })] },
      })
    );
    expect(ids(findings)).toContain("mathematical_consistency");
  });

  it("flags a unit the answer does not carry", () => {
    const findings = checkMathematicalConsistency(
      input({
        truth: truth({ units: ["cm"] }),
        explanation: { fields: [field({ text: "So the length is 3 km." })] },
      })
    );
    expect(ids(findings)).toContain("mathematical_consistency");
    expect(findings[0].detail).toContain("km");
  });

  it("does not read a bare variable as a unit claim", () => {
    const findings = checkMathematicalConsistency(
      input({
        truth: truth({ units: ["cm"] }),
        explanation: { fields: [field({ text: "Let n be the number of sides, then n is what we want." })] },
      })
    );
    expect(findings).toEqual([]);
  });

  it("flags a variable the problem does not contain", () => {
    const findings = checkMathematicalConsistency(
      input({
        truth: truth({ variables: ["x"] }),
        explanation: { fields: [field({ text: "Now solve $y = 5$ instead." })] },
      })
    );
    expect(ids(findings)).toContain("mathematical_consistency");
    expect(findings[0].detail).toContain("y");
  });

  it("leaves practice questions alone — a new question is SUPPOSED to have new numbers", () => {
    const findings = checkMathematicalConsistency(
      input({
        explanation: {
          fields: [field({ id: "p1", kind: "practice", text: "Solve $7x + 91 = 273$." })],
        },
      })
    );
    expect(findings).toEqual([]);
  });
});

// --- 2. Difficulty alignment -------------------------------------------------

describe("check 2 — difficulty alignment", () => {
  const long =
    "Because the equation is linear in the single unknown we may operate on both " +
    "sides simultaneously without altering the solution set at any stage of the " +
    "manipulation we are about to perform together.";

  it("rejects a sentence that runs past what the level can follow", () => {
    const findings = checkDifficultyAlignment(
      input({
        audience: { language: "en", difficulty: "veryEasy" },
        explanation: { fields: [field({ text: long })] },
      })
    );
    expect(ids(findings)).toContain("difficulty_alignment");
  });

  it("accepts the same sentence at expert level", () => {
    const findings = checkDifficultyAlignment(
      input({
        audience: { language: "en", difficulty: "expert" },
        explanation: { fields: [field({ text: long })] },
      })
    );
    expect(findings).toEqual([]);
  });

  it("flags an expert lesson that names no concept at all — too easy is also wrong", () => {
    const findings = checkDifficultyAlignment(
      input({
        audience: { language: "en", difficulty: "expert" },
        explanation: {
          fields: [
            field({
              text:
                "Take away the four. Then cut both sides in half. That gives you the " +
                "answer straight away, so you are all done here and you can move " +
                "on to the next question whenever you are ready.",
            }),
          ],
        },
      })
    );
    expect(ids(findings)).toContain("difficulty_alignment");
    expect(findings[0].severity).toBe("minor");
  });

  it("does not measure a question against the sentence budget", () => {
    const findings = checkDifficultyAlignment(
      input({
        audience: { language: "en", difficulty: "veryEasy" },
        explanation: { fields: [field({ kind: "question", text: long })] },
      })
    );
    expect(findings).toEqual([]);
  });
});

// --- 3. Language quality -----------------------------------------------------

describe("check 3 — language quality", () => {
  it("rejects an English explanation sent to an Arabic student", () => {
    const findings = checkLanguageQuality(
      input({
        audience: { language: "ar", difficulty: "medium" },
        explanation: { fields: [field({ text: "Subtract four from both sides of the equation." })] },
      })
    );
    expect(ids(findings)).toContain("language_quality");
    expect(findings[0].severity).toBe("hard");
  });

  it("accepts Arabic prose for an Arabic student", () => {
    const findings = checkLanguageQuality(
      input({
        audience: { language: "ar", difficulty: "medium" },
        explanation: { fields: [field({ text: "اطرح أربعة من طرفي المعادلة لتبسيطها." })] },
      })
    );
    expect(findings).toEqual([]);
  });

  it("accepts Japanese that legitimately mixes kana with kanji", () => {
    const findings = checkLanguageQuality(
      input({
        audience: { language: "ja", difficulty: "medium" },
        explanation: { fields: [field({ text: "両辺から四を引いて式を簡単にします。" })] },
      })
    );
    expect(findings).toEqual([]);
  });

  it("catches one untranslated English sentence stranded in Spanish prose", () => {
    const findings = checkLanguageQuality(
      input({
        audience: { language: "es", difficulty: "medium" },
        explanation: {
          fields: [
            field({
              text:
                "Primero restamos cuatro de ambos lados. Then we divide both sides " +
                "by the coefficient so that the unknown is alone.",
            }),
          ],
        },
      })
    );
    expect(ids(findings)).toContain("language_quality");
  });

  it("does not mistake correct Spanish for English", () => {
    const findings = checkLanguageQuality(
      input({
        audience: { language: "es", difficulty: "medium" },
        explanation: {
          fields: [
            field({
              text:
                "Primero restamos cuatro de ambos lados. Después dividimos entre dos " +
                "para dejar la incógnita sola.",
            }),
          ],
        },
      })
    );
    expect(findings).toEqual([]);
  });

  it("does not mistake Dutch for English just because it shares function words", () => {
    const findings = checkLanguageQuality(
      input({
        audience: { language: "nl", difficulty: "medium" },
        explanation: {
          fields: [
            field({
              text: "Trek vier van beide kanten af. Deel daarna beide kanten door twee.",
            }),
          ],
        },
      })
    );
    expect(findings).toEqual([]);
  });

  it("says nothing at all when the student reads English", () => {
    const findings = checkLanguageQuality(
      input({ explanation: { fields: [field({ text: "Subtract four from both sides." })] } })
    );
    expect(findings).toEqual([]);
  });
});

// --- 4 & 10. Concepts and terminology ---------------------------------------

describe("check 4 — concept introduction", () => {
  it('rejects "use the discriminant" with no discriminant explained', () => {
    const findings = checkConceptIntroduction(
      input({
        explanation: { fields: [field({ text: "Use the discriminant to decide how many roots there are." })] },
      })
    );
    expect(ids(findings)).toContain("concept_introduction");
  });

  it("accepts the same instruction once the concept is defined", () => {
    const findings = checkConceptIntroduction(
      input({
        explanation: {
          fields: [
            field({
              text:
                "The discriminant ($b^2 - 4ac$) tells us how many solutions exist, " +
                "so we work it out first.",
            }),
          ],
        },
      })
    );
    expect(findings).toEqual([]);
  });

  it("still rejects a definition that arrives AFTER the step that needed it", () => {
    const findings = checkConceptIntroduction(
      input({
        explanation: {
          fields: [
            field({ id: "steps.0.why", kind: "step", stepIndex: 0, text: "Find the discriminant now." }),
            field({ id: "concept.body", text: "The discriminant is $b^2 - 4ac$." }),
          ],
        },
      })
    );
    expect(ids(findings)).toContain("concept_introduction");
    expect(findings[0].field).toBe("steps.0.why");
  });

  it("says nothing about a concept the student is recorded as knowing", () => {
    const findings = checkConceptIntroduction(
      input({
        audience: { language: "en", difficulty: "medium", knownConcepts: ["discriminant"] },
        explanation: { fields: [field({ text: "Use the discriminant here." })] },
      })
    );
    expect(findings).toEqual([]);
  });
});

describe("check 10 — terminology", () => {
  it("rejects a university word in a primary-band lesson", () => {
    const findings = checkTerminology(
      input({
        audience: { language: "en", difficulty: "easy", band: "primary" },
        explanation: { fields: [field({ text: "Look at the integrand carefully." })] },
      })
    );
    expect(ids(findings)).toContain("terminology");
  });

  it("accepts the same word for a university-band student", () => {
    const findings = checkTerminology(
      input({
        audience: { language: "en", difficulty: "expert", band: "university" },
        explanation: { fields: [field({ text: "Look at the integrand carefully." })] },
      })
    );
    expect(findings).toEqual([]);
  });
});

// --- 5. Visual reference -----------------------------------------------------

describe("check 5 — visual reference", () => {
  it("rejects a reference to an anchor that does not exist", () => {
    const findings = checkVisualReference(
      input({
        visuals: { anchors: [anchor()], actions: [{ type: "highlight", target: "angle_B", role: "known" }] },
        explanation: { fields: [field({ visualRefs: ["angle_Z"] })] },
      })
    );
    expect(ids(findings)).toContain("visual_reference");
    expect(findings[0].severity).toBe("hard");
  });

  it("rejects a reference to a real anchor that nothing is drawing", () => {
    const findings = checkVisualReference(
      input({
        visuals: { anchors: [anchor()], actions: [] },
        explanation: { fields: [field({ visualRefs: ["angle_B"] })] },
      })
    );
    expect(ids(findings)).toContain("visual_reference");
    expect(findings[0].detail).toContain("no action draws it");
  });

  it("accepts a reference that is anchored AND drawn", () => {
    const findings = checkVisualReference(
      input({
        visuals: { anchors: [anchor()], actions: [{ type: "highlight", target: "angle_B", role: "known" }] },
        explanation: { fields: [field({ visualRefs: ["angle_B"] })] },
      })
    );
    expect(findings).toEqual([]);
  });

  it('rejects "look at the highlighted angle" when nothing is highlighted', () => {
    const findings = checkVisualReference(
      input({
        visuals: { anchors: [], actions: [] },
        explanation: { fields: [field({ text: "Look at the highlighted angle at the top." })] },
      })
    );
    expect(ids(findings)).toContain("visual_reference");
    expect(findings[0].severity).toBe("hard");
  });
});

// --- 6. Colour consistency ---------------------------------------------------

describe("check 6 — colour consistency", () => {
  const drawn = {
    anchors: [anchor({ role: "known" })],
    actions: [{ type: "highlight" as const, target: "angle_B", role: "known" as const }],
  };

  it("rejects prose that names the wrong colour for what is being drawn", () => {
    const findings = checkColourConsistency(
      input({
        visuals: drawn,
        explanation: { fields: [field({ text: "The angle in green is the one we know.", visualRefs: ["angle_B"] })] },
      })
    );
    expect(ids(findings)).toContain("colour_consistency");
    expect(findings.some((f) => f.severity === "hard")).toBe(true);
  });

  it("accepts prose that names the right colour", () => {
    const findings = checkColourConsistency(
      input({
        visuals: drawn,
        explanation: { fields: [field({ text: "The angle in blue is the one we know.", visualRefs: ["angle_B"] })] },
      })
    );
    expect(findings).toEqual([]);
  });

  it("rejects a field that claims a role the overlay is not using", () => {
    const findings = checkColourConsistency(
      input({
        visuals: drawn,
        explanation: { fields: [field({ text: "This is the one we are solving for.", visualRefs: ["angle_B"], role: "unknown" })] },
      })
    );
    expect(ids(findings)).toContain("colour_consistency");
  });
});

// --- 7. Educational flow -----------------------------------------------------

describe("check 7 — educational flow", () => {
  it("accepts the canonical order", () => {
    const findings = checkEducationalFlow(
      input({ explanation: { fields: [field()], journey: ["understand", "chooseMethod", "apply", "verify", "takeaway"] } })
    );
    expect(findings).toEqual([]);
  });

  it("accepts a journey that SKIPS stages but keeps the order", () => {
    const findings = checkEducationalFlow(
      input({ explanation: { fields: [field()], journey: ["understand", "apply", "takeaway"] } })
    );
    expect(findings).toEqual([]);
  });

  it("rejects verifying before applying", () => {
    const findings = checkEducationalFlow(
      input({ explanation: { fields: [field()], journey: ["understand", "verify", "apply"] } })
    );
    expect(ids(findings)).toContain("educational_flow");
  });

  it("notices a lesson that never establishes what is being asked", () => {
    const findings = checkEducationalFlow(
      input({ explanation: { fields: [field()], journey: ["apply", "simplify", "takeaway"] } })
    );
    expect(findings.some((f) => f.detail.includes("never establishes"))).toBe(true);
  });
});

// --- 8. Hidden steps ---------------------------------------------------------

describe("check 8 — no hidden steps", () => {
  it('rejects "We simplify."', () => {
    const findings = checkHiddenSteps(
      input({ explanation: { fields: [field({ id: "steps.0.why", kind: "step", stepIndex: 0, text: "We simplify." })] } })
    );
    expect(ids(findings)).toContain("hidden_steps");
  });

  it('accepts "Divide every term by 2 so the x stands alone."', () => {
    const findings = checkHiddenSteps(
      input({
        explanation: {
          fields: [
            field({ id: "steps.0.why", kind: "step", stepIndex: 0, text: "Divide every term by 2 so the x stands alone." }),
          ],
        },
      })
    );
    expect(findings).toEqual([]);
  });

  it("rejects a narration that jumps over a verified step", () => {
    const findings = checkHiddenSteps(
      input({
        truth: truth({ stepExpressions: ["2x = 6", "x = 3", "x = 3"] }),
        explanation: {
          fields: [
            field({ id: "steps.0.why", kind: "step", stepIndex: 0, text: "Subtract 4 from both sides carefully." }),
            field({ id: "steps.2.why", kind: "step", stepIndex: 2, text: "Now state the value we have found." }),
          ],
        },
      })
    );
    expect(findings.some((f) => f.detail.includes("nothing in between"))).toBe(true);
  });

  it("rejects narration of a step the verified solution does not have", () => {
    const findings = checkHiddenSteps(
      input({
        explanation: {
          fields: [field({ id: "steps.9.why", kind: "step", stepIndex: 9, text: "And then we finish the whole thing off." })],
        },
      })
    );
    expect(findings.some((f) => f.detail.includes("does not have"))).toBe(true);
  });
});

// --- 9. Student memory -------------------------------------------------------

describe("check 9 — student memory", () => {
  const forgetful = input({
    truth: truth({ problemLatex: "2x - 4 = 10", stepExpressions: ["2x = 14", "x = 7"] }),
    audience: { language: "en", difficulty: "medium", recurringMistakes: ["negativeSigns"] },
    explanation: { fields: [field({ text: "Move the four across and then halve what is left." })] },
  });

  it("notices a remembered mistake this problem exercises and never mentions", () => {
    expect(ids(checkStudentMemory(forgetful))).toContain("student_memory");
  });

  it("is satisfied by prose that raises it naturally", () => {
    const findings = checkStudentMemory({
      ...forgetful,
      explanation: {
        fields: [field({ text: "Watch the sign as the four moves across, then halve what is left." })],
      },
    });
    expect(findings).toEqual([]);
  });

  it("is satisfied, in any language, by a field carrying the memory role", () => {
    const findings = checkStudentMemory({
      ...forgetful,
      audience: { ...forgetful.audience, language: "th" },
      explanation: { fields: [field({ role: "memory", text: "ระวังเครื่องหมายลบ" })] },
    });
    expect(findings).toEqual([]);
  });

  it("says nothing when the problem does not exercise the mistake", () => {
    const findings = checkStudentMemory(
      input({
        truth: truth({ units: [] }),
        audience: { language: "en", difficulty: "medium", recurringMistakes: ["units"] },
      })
    );
    expect(findings).toEqual([]);
  });
});

// --- 11. Adaptive teaching ---------------------------------------------------

describe("check 11 — adaptive teaching", () => {
  it("rejects a university register in a primary-band lesson", () => {
    const findings = checkAdaptiveTeaching(
      input({
        audience: { language: "en", difficulty: "easy", band: "primary" },
        explanation: { fields: [field({ text: "Consider whether the sequence will converge." })] },
      })
    );
    expect(ids(findings)).toContain("adaptive_teaching");
  });

  it("leaves a university-band lesson alone", () => {
    const findings = checkAdaptiveTeaching(
      input({
        audience: { language: "en", difficulty: "expert", band: "university" },
        explanation: { fields: [field({ text: "Consider whether the sequence will converge." })] },
      })
    );
    expect(findings).toEqual([]);
  });
});

// --- 12. Visual learning alignment ------------------------------------------

describe("check 12 — visual learning alignment", () => {
  it("accepts an animation that shows the verified step", () => {
    const findings = checkVisualLearningAlignment(
      input({ visuals: { anchors: [], actions: [], visualSteps: [{ stepIndex: 0, expression: "2x = 6" }] } })
    );
    expect(findings).toEqual([]);
  });

  it("forgives cosmetic LaTeX differences — it compares, it does not evaluate", () => {
    const findings = checkVisualLearningAlignment(
      input({ visuals: { anchors: [], actions: [], visualSteps: [{ stepIndex: 0, expression: "\\left2x = 6\\right" }] } })
    );
    expect(findings).toEqual([]);
  });

  it("rejects an animation showing something the verified step does not say", () => {
    const findings = checkVisualLearningAlignment(
      input({ visuals: { anchors: [], actions: [], visualSteps: [{ stepIndex: 0, expression: "2x = 7" }] } })
    );
    expect(ids(findings)).toContain("visual_learning_alignment");
    expect(findings[0].severity).toBe("hard");
  });

  it("rejects a scene for a step that does not exist", () => {
    const findings = checkVisualLearningAlignment(
      input({ visuals: { anchors: [], actions: [], visualSteps: [{ stepIndex: 9, expression: "x = 3" }] } })
    );
    expect(findings[0].detail).toContain("does not have");
  });
});

// --- 13 & 14. Certainty ------------------------------------------------------

describe("check 13 — OCR awareness", () => {
  it("rejects a confident explanation of a doubtful read", () => {
    const findings = checkOcrAwareness(
      input({
        certainty: { state: "OCR_LOW_CONFIDENCE", ocrConfidence: 0.4 },
        explanation: { fields: [field({ text: "Subtract four from both sides." })] },
      })
    );
    expect(ids(findings)).toContain("ocr_awareness");
    expect(findings[0].severity).toBe("hard");
  });

  it("accepts one that says so", () => {
    const findings = checkOcrAwareness(
      input({
        certainty: { state: "OCR_LOW_CONFIDENCE", ocrConfidence: 0.4 },
        explanation: {
          fields: [field({ text: "The photo is hard to read — can you confirm the second number?" })],
        },
      })
    );
    expect(findings).toEqual([]);
  });

  it("accepts one that ASKS, in any language", () => {
    const findings = checkOcrAwareness(
      input({
        audience: { language: "ko", difficulty: "medium" },
        certainty: { state: "OCR_LOW_CONFIDENCE", ocrConfidence: 0.4 },
        explanation: {
          fields: [
            field({ text: "사진이 흐릿합니다." }),
            field({ kind: "question", text: "두 번째 숫자가 맞는지 확인해 줄래요?" }),
          ],
        },
      })
    );
    expect(findings).toEqual([]);
  });

  it("says nothing when the read was clean", () => {
    const findings = checkOcrAwareness(input({ certainty: { state: "PASS", ocrConfidence: 0.98 } }));
    expect(findings).toEqual([]);
  });

  it("does not ask a set of practice questions to hedge — it asserts nothing", () => {
    const findings = checkOcrAwareness(
      input({
        certainty: { state: "OCR_LOW_CONFIDENCE", ocrConfidence: 0.2 },
        explanation: { fields: [field({ id: "p1", kind: "practice", text: "Solve $3x = 12$." })] },
      })
    );
    expect(findings).toEqual([]);
  });
});

describe("check 14 — verification awareness", () => {
  it("rejects an explanation that asserts an answer the verifier rejected", () => {
    const findings = checkVerificationAwareness(
      input({
        truth: truth({ verified: false }),
        certainty: { state: "VERIFIER_DISAGREEMENT" },
        explanation: { fields: [field({ text: "So $x = 3$ is the answer." })] },
      })
    );
    expect(findings.some((f) => f.detail.includes("asserts an unverified result"))).toBe(true);
    expect(findings.every((f) => f.dimension === "mathematicalConsistency")).toBe(true);
  });

  it("requires the student be asked to check the problem", () => {
    const findings = checkVerificationAwareness(
      input({
        truth: truth({ verified: false }),
        certainty: { state: "VERIFIER_DISAGREEMENT" },
        explanation: { fields: [field({ text: "Something did not work out here." })] },
      })
    );
    expect(findings.some((f) => f.detail.includes("confirm the problem"))).toBe(true);
  });

  it("accepts an honest, question-asking response under disagreement", () => {
    const findings = checkVerificationAwareness(
      input({
        truth: truth({ verified: false, answerPlain: "x = 3", answerLatex: "x = 3" }),
        certainty: { state: "VERIFIER_DISAGREEMENT" },
        explanation: {
          fields: [
            field({ text: "This did not check out, so I would rather not guess." }),
            field({ kind: "question", text: "Could you read me the equation exactly as it is written?" }),
          ],
        },
      })
    );
    expect(findings).toEqual([]);
  });

  it("asks a LOW_CONFIDENCE lesson to teach carefully", () => {
    const findings = checkVerificationAwareness(
      input({ certainty: { state: "LOW_CONFIDENCE" } })
    );
    expect(ids(findings)).toContain("verification_awareness");
    expect(findings[0].severity).toBe("major");
  });

  it("teaches normally on PASS", () => {
    expect(checkVerificationAwareness(input())).toEqual([]);
  });
});

// --- 15. Practice alignment --------------------------------------------------

describe("check 15 — practice alignment", () => {
  const base = {
    id: "p1",
    prompt: "Solve $5x + 3 = 23$.",
    skill: "linear equation",
    difficulty: "medium" as const,
    concepts: ["linear equation"],
  };

  it("accepts practice that drills what was just taught, at the level asked for", () => {
    expect(checkPracticeAlignment(input({ practice: [base] }))).toEqual([]);
  });

  it("rejects practice pitched at a different level", () => {
    const findings = checkPracticeAlignment(input({ practice: [{ ...base, difficulty: "expert" }] }));
    expect(ids(findings)).toContain("practice_alignment");
  });

  it("rejects practice about an unrelated topic", () => {
    const findings = checkPracticeAlignment(
      input({ practice: [{ ...base, concepts: ["trigonometric identities"] }] })
    );
    expect(findings.some((f) => f.detail.includes("none of which was taught"))).toBe(true);
  });

  it("rejects an empty prompt outright", () => {
    const findings = checkPracticeAlignment(input({ practice: [{ ...base, prompt: "   " }] }));
    expect(findings[0].severity).toBe("hard");
  });

  it("lets a LADDER straddle the level, because that is what a ladder is for", () => {
    const findings = checkPracticeAlignment(
      input({
        practice: [
          { ...base, id: "easier", rung: "easier", difficulty: "easy" },
          { ...base, id: "similar", rung: "similar", difficulty: "medium" },
          { ...base, id: "harder", rung: "harder", difficulty: "hard" },
        ],
      })
    );
    expect(findings).toEqual([]);
  });

  it("still rejects a ladder rung that lands two levels away", () => {
    const findings = checkPracticeAlignment(
      input({ practice: [{ ...base, id: "harder", rung: "harder", difficulty: "expert" }] })
    );
    expect(ids(findings)).toContain("practice_alignment");
  });
});

// ---------------------------------------------------------------------------
// Across the curriculum
// ---------------------------------------------------------------------------

describe("across the curriculum", () => {
  const cases: Array<{ name: string; input: QualityInput }> = [
    {
      name: "primary arithmetic",
      input: input({
        truth: truth({
          problemLatex: "24 \\div 6",
          answerPlain: "4",
          stepExpressions: ["4"],
          problemType: "arithmetic",
        }),
        audience: { language: "en", difficulty: "veryEasy", band: "primary" },
        explanation: {
          fields: [
            field({ text: "We are sharing 24 into 6 equal groups." }),
            field({ id: "steps.0.why", kind: "step", stepIndex: 0, text: "Count how many go in each group." }),
          ],
          journey: ["understand", "apply", "takeaway"],
        },
      }),
    },
    {
      name: "secondary geometry",
      input: input({
        truth: truth({
          problemLatex: "x + 40 + 65 = 180",
          answerPlain: "x = 75",
          stepExpressions: ["x + 105 = 180", "x = 75"],
          problemType: "triangle angles",
        }),
        audience: { language: "en", difficulty: "medium", band: "secondary" },
        visuals: {
          anchors: [anchor({ id: "angle_A", role: "unknown" })],
          actions: [{ type: "glow", target: "angle_A", role: "unknown" }],
        },
        explanation: {
          fields: [
            field({ text: "The three angles of a triangle always add to 180 degrees.", visualRefs: ["angle_A"], role: "unknown" }),
            field({ id: "steps.0.why", kind: "step", stepIndex: 0, text: "Add the two angles you already know together." }),
            field({ id: "steps.1.why", kind: "step", stepIndex: 1, text: "Take that total away from 180 to leave x." }),
          ],
          journey: ["understand", "apply", "verify"],
        },
      }),
    },
    {
      name: "pre-university calculus",
      input: input({
        truth: truth({
          problemLatex: "\\frac{d}{dx}(3x^2 + 2x)",
          answerPlain: "6x + 2",
          stepExpressions: ["6x + 2"],
          problemType: "derivative",
        }),
        audience: { language: "en", difficulty: "hard", band: "preUniversity" },
        explanation: {
          fields: [
            field({ text: "The derivative is the rate at which the function changes." }),
            field({ id: "steps.0.why", kind: "step", stepIndex: 0, text: "Bring each power down in front and drop it by one." }),
          ],
          journey: ["understand", "chooseMethod", "apply"],
        },
      }),
    },
    {
      name: "statistics",
      input: input({
        truth: truth({
          problemLatex: "\\text{mean of } 4, 8, 6",
          answerPlain: "6",
          stepExpressions: ["18", "6"],
          problemType: "statistics",
        }),
        audience: { language: "en", difficulty: "easy", band: "secondary" },
        explanation: {
          fields: [
            field({ text: "The mean is the total shared out evenly between the values." }),
            field({ id: "steps.0.why", kind: "step", stepIndex: 0, text: "Add all three values together first." }),
            field({ id: "steps.1.why", kind: "step", stepIndex: 1, text: "Then share that total between the three of them." }),
          ],
          journey: ["understand", "apply", "takeaway"],
        },
      }),
    },
    {
      name: "probability",
      input: input({
        truth: truth({
          problemLatex: "P(\\text{two heads})",
          answerPlain: "1/4",
          stepExpressions: ["\\frac{1}{2} \\times \\frac{1}{2}", "\\frac{1}{4}"],
          problemType: "probability",
        }),
        audience: { language: "en", difficulty: "medium", band: "secondary" },
        explanation: {
          fields: [
            field({ text: "Each toss is independent, so one result never changes the next." }),
            field({ id: "steps.0.why", kind: "step", stepIndex: 0, text: "Multiply the chance of each head together." }),
            field({ id: "steps.1.why", kind: "step", stepIndex: 1, text: "That product is the chance of both happening." }),
          ],
          journey: ["understand", "apply", "takeaway"],
        },
      }),
    },
    {
      name: "word problem",
      input: input({
        truth: truth({
          problemLatex: "3n + 5 = 20",
          answerPlain: "n = 5",
          stepExpressions: ["3n = 15", "n = 5"],
          problemType: "word problem",
        }),
        audience: { language: "en", difficulty: "medium", band: "secondary" },
        explanation: {
          fields: [
            field({ text: "Let n stand for the number of tickets she bought." }),
            field({ id: "steps.0.why", kind: "step", stepIndex: 0, text: "Take the fixed charge off the total she paid." }),
            field({ id: "steps.1.why", kind: "step", stepIndex: 1, text: "Share what is left between the three tickets." }),
          ],
          journey: ["understand", "chooseMethod", "apply", "verify"],
        },
      }),
    },
  ];

  for (const { name, input: sample } of cases) {
    it(`passes a good ${name} lesson clean`, () => {
      expect(runDeterministicChecks(sample)).toEqual([]);
    });
  }
});

// ---------------------------------------------------------------------------
// Every supported language
// ---------------------------------------------------------------------------

describe("every language the app speaks", () => {
  /** One correct sentence per language, in that language's own script. */
  const SAMPLES: Record<string, string> = {
    en: "Subtract four from both sides of the equation.",
    es: "Resta cuatro de ambos lados de la ecuación.",
    fr: "Soustrayez quatre des deux côtés de l'équation.",
    de: "Ziehe vier von beiden Seiten der Gleichung ab.",
    pt: "Subtraia quatro dos dois lados da equação.",
    it: "Sottrai quattro da entrambi i lati dell'equazione.",
    nl: "Trek vier van beide kanten van de vergelijking af.",
    pl: "Odejmij cztery od obu stron równania.",
    tr: "Denklemin her iki tarafından dört çıkar.",
    vi: "Trừ bốn từ cả hai vế của phương trình.",
    id: "Kurangi empat dari kedua sisi persamaan.",
    ms: "Tolak empat daripada kedua-dua belah persamaan.",
    ar: "اطرح أربعة من طرفي المعادلة.",
    he: "החסר ארבע משני צידי המשוואה.",
    hi: "समीकरण के दोनों पक्षों से चार घटाएँ।",
    ru: "Вычтите четыре из обеих частей уравнения.",
    uk: "Відніміть чотири від обох частин рівняння.",
    ja: "方程式の両辺から四を引きます。",
    ko: "방정식의 양변에서 사를 뺍니다.",
    zh: "从方程的两边同时减去四。",
    th: "ลบสี่ออกจากทั้งสองข้างของสมการ",
  };

  for (const [language, text] of Object.entries(SAMPLES)) {
    it(`accepts correct ${language} prose`, () => {
      const findings = checkLanguageQuality(
        input({
          audience: { language, difficulty: "medium" },
          explanation: { fields: [field({ text })] },
        })
      );
      expect(findings).toEqual([]);
    });
  }

  for (const language of ["ar", "he", "hi", "ru", "ja", "ko", "zh", "th"]) {
    it(`rejects English served to a ${language} student`, () => {
      const findings = checkLanguageQuality(
        input({
          audience: { language, difficulty: "medium" },
          explanation: { fields: [field({ text: SAMPLES.en })] },
        })
      );
      expect(ids(findings)).toContain("language_quality");
    });
  }
});

// ---------------------------------------------------------------------------
// The text utilities the checks are built on
// ---------------------------------------------------------------------------

describe("reading prose that has maths in it", () => {
  it("strips maths before counting words, so a long number is not a long sentence", () => {
    expect(proseOnly("Divide by $174.5$ now")).toBe("Divide by now");
    expect(wordCount("Divide by $174.5$ now")).toBe(3);
  });

  it("counts Japanese and Thai, which do not use spaces", () => {
    expect(wordCount("両辺から四を引いて式を簡単にします。")).toBeGreaterThan(3);
    expect(wordCount("ลบสี่ออกจากทั้งสองข้างของสมการ")).toBeGreaterThan(3);
  });

  it("folds Arabic-Indic and Devanagari digits to ASCII", () => {
    expect(foldDigits("٢٣")).toBe("23");
    expect(foldDigits("४२")).toBe("42");
    expect(foldDigits("42")).toBe("42");
  });

  it("compares expressions cosmetically and never evaluates them", () => {
    expect(canonicalExpression("2x + 4")).toBe(canonicalExpression("2 x+4"));
    // 2(x+2) IS 2x+4, and this layer has no business knowing that.
    expect(canonicalExpression("2(x+2)")).not.toBe(canonicalExpression("2x+4"));
  });

  it("scores script membership, tolerating Japanese kana/kanji mixing", () => {
    expect(scriptRatio("両辺から四を引いて", "kana")).toBe(1);
    expect(scriptRatio("Subtract four", "arabic")).toBe(0);
  });

  it("does not call a short phrase English", () => {
    expect(readsAsEnglish("Bien.", "es")).toBe(false);
  });
});
