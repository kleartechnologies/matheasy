/**
 * Reusable natural-language ASK-CLAUSE extraction for the deterministic solver engines.
 *
 * A word problem is two different kinds of text welded together: SCENERY (the setting and
 * the givens) and the ASK (the one question actually posed). Target detection that scans
 * the WHOLE text cannot tell them apart, so a noun sitting in the scenery hijacks the
 * target:
 *
 *   "A circular garden has a radius of 7 m. A FENCE runs along its PERIMETER.
 *    How much AREA does the garden cover?"      → shipped 14π m (a circumference!)
 *   "The AREA of the circle of radius 7 cm is given in the table.
 *    How LONG is the elastic that stretches once round it?"  → shipped 49π cm²
 *
 * In both, every cue for the wrong target lives in a scenery sentence and every cue for
 * the right one lives in the ask. Scoping detection to the ask clause first resolves them
 * without any per-phrase special-casing — and it generalises: EVERY engine that reads a
 * target out of prose has this problem.
 *
 * Golden-rule stance: this only NARROWS the scope a target is read from. When the ask
 * clause yields no single target the caller falls back to the whole text, which can only
 * surface MORE competing cues — i.e. the fallback is never less conservative.
 */

/** Verbs and interrogatives that mark a sentence as the question being posed. "which" and
 * "whose" are deliberately ABSENT: they are overwhelmingly RELATIVE pronouns introducing a
 * description ("… shown in Fig. 3, WHICH has its perimeter drawn in red", "Note WHICH formula
 * gives the area"), and admitting them made a descriptive clause outrank the real ask. */
const ASK_CUE =
  /\b(?:find|calculate|determine|compute|work\s+out|obtain|give|state|evaluate|express|show|how\s+(?:much|many|long|far|wide|big|large)|what)\b/i;

/** A sentence that DISCLAIMS an ask — "Note: the perimeter is NOT what is being asked",
 * "Which arc length is longer is NOT ASKED" — names a quantity precisely in order to rule it
 * out. Selecting it as the ask clause inverts the problem and ships exactly the quantity the
 * text just excluded, so it can never BE the ask. */
const NEGATED_ASK =
  /\bnot\s+(?:what\s+is\s+)?(?:being\s+)?(?:asked|required|wanted|needed)\b|\bis\s+not\s+(?:being\s+)?asked\b|\bnot\s+what\s+is\b|\bdo\s+not\s+(?:find|calculate|compute|give)\b|\brather\s+than\b/i;

/**
 * A sentence that instructs how to FORMAT THE ANSWER — "Give your answer in terms of π",
 * "Leave your answer correct to 2 decimal places", "Take π = 22/7" — is not the ask, however
 * many ask cues it carries ("give", "state", "express" are all on the cue list). Scoping the
 * target to it left "Find the area of the circle with radius 7 cm. Give your answer in terms
 * of π." with no target at all. The ask is the sentence before it.
 */
const ANSWER_FORMAT_SENTENCE =
  /\b(?:give|leave|express|write|state|round|correct|present)\b[^.?!]*\b(?:answer|result)\b|\bin\s+terms\s+of\s+(?:π|pi)\b|\b(?:decimal\s+places?|significant\s+figures?|nearest\s+(?:whole|tenth|hundredth|integer|cm|m|mm))\b|\b(?:take|use|let|assume)\s+(?:π|pi)\s*[=≈]/i;

/** A META sentence — an editorial aside ("NOTE: …", "N.B. …", "Hint: …") — comments on the
 * problem instead of posing it, and routinely names the WRONG quantity to warn about it. */
const META_SENTENCE = /^(?:note|n\.?b\.?|hint|remark|caution|warning|aside|tip|recall)\b/i;

/**
 * A sentence asking for a FORMULA rather than a VALUE — "What is the formula for the
 * circumference of a circle?", "Write an expression for the area in terms of r" — poses no
 * computation at all: it names a quantity in the abstract, with no figure and no givens.
 * Selecting it as the ask hands the target to whatever quantity it names, and the numeric
 * question that actually has givens loses: "Find the AREA of a circle with radius 10 cm.
 * What is the FORMULA for the CIRCUMFERENCE of a circle?" shipped 20π cm.
 *
 * It is the same defect ANSWER_FORMAT_SENTENCE fixes for "Give your answer in terms of π" —
 * an instruction ABOUT the answer is not the ask — so it belongs in the same skip list.
 */
const FORMULA_SENTENCE =
  /\bformulae?\b|\bformulas\b|\b(?:expression|rule|equation)\s+for\s+(?:the\s+)?(?:area|circumference|perimeter|radius|diameter|volume)\b|\bin\s+terms\s+of\s+[rd]\b/i;

/**
 * A RHETORICAL or DEFINITIONAL question — "Which is bigger, the area or the circumference?",
 * "What does the word circumference mean?", "Can you see the diameter?", "Look at the diagram."
 * — is teaching patter, not the ask. It names quantities in order to talk ABOUT them, and it
 * poses no computation: there is nothing to substitute a given into.
 *
 * It reads exactly like an ask to a cue scan ("what", "which"), so a lesson-style opener
 * hijacked the target from the real question two sentences later: "WHICH IS BIGGER, THE AREA
 * OR THE CIRCUMFERENCE? A circle has a radius of 9 m. Find the AREA." shipped 18π m.
 *
 * Same principle as FORMULA_SENTENCE and ANSWER_FORMAT_SENTENCE: a sentence that discusses
 * the mathematics rather than posing it can never be the ask.
 */
const RHETORICAL_SENTENCE =
  /\bwhich\s+is\s+(?:bigger|larger|greater|smaller|longer|shorter|more|less)\b|\bwhat\s+(?:does|do)\b[^.?!]*\bmean\b|\b(?:can|could|do)\s+you\s+(?:see|spot|remember|recall|know|tell|name|identify|notice)\b|^(?:look|see|notice|observe|consider|imagine|picture)\b|\b(?:what|which)\s+is\s+(?:meant\s+by|the\s+meaning\s+of|the\s+difference\s+between)\b/i;

/** "Show your working", "Explain your method" — an instruction about the WORKING, not the ask.
 * "show" and "explain" are both ask cues, so without this a trailing instruction outranks the
 * question it belongs to. */
const WORKING_SENTENCE =
  /\b(?:show|explain|describe|justify|set\s+out)\s+(?:your|all|the|each)\s+(?:working|work|steps?|method|reasoning|answer)\b/i;

/**
 * A REPORTED (embedded) question — "the diagram SHOWS HOW LONG the perimeter is", "the teacher
 * WRITES WHAT the area of the circle is on the board" — is a statement ABOUT the figure, not a
 * question put to the reader. It is grammatically a subordinate clause, and the only thing it
 * has in common with an ask is the interrogative word that introduces it.
 *
 * That was enough to hijack the target six ways in one sweep: every "Find the AREA … . The
 * diagram shows how long the PERIMETER is." shipped a circumference, and the mirror shipped an
 * area. Same defect as FORMULA_SENTENCE and RHETORICAL_SENTENCE — a sentence that talks about
 * the mathematics cannot be the one posing it.
 *
 * The reporting verb must be INFLECTED (shows / showed, gives / gave), which is what separates
 * a report from the imperative that looks identical: "SHOW how long the perimeter is" is a real
 * ask, "the diagram SHOWS how long the perimeter is" is not.
 */
const REPORTED_QUESTION =
  /\b(?:shows|showed|displays|displayed|gives|gave|tells|told|writes|wrote|states|stated|indicates|indicated|records|recorded|lists|listed|labels|labelled|labeled|explains|explained|says|said|notes|noted|mentions|mentioned|contains|contained|includes|included|illustrates|illustrated|describes|described|marks|marked|reports|reported|prints|printed|specifies|specified|reveals|revealed|sets\s+out|works\s+out)\s+(?:you\s+|us\s+|them\s+|me\s+)?(?:how|what|which|where|whether|that)\b/i;

/** Every sentence kind that comments on the problem instead of posing it. */
function isNotAnAsk(s: string): boolean {
  return (
    META_SENTENCE.test(s) ||
    NEGATED_ASK.test(s) ||
    ANSWER_FORMAT_SENTENCE.test(s) ||
    FORMULA_SENTENCE.test(s) ||
    RHETORICAL_SENTENCE.test(s) ||
    WORKING_SENTENCE.test(s) ||
    REPORTED_QUESTION.test(s)
  );
}

/** Abbreviations whose full stop does NOT end a sentence. Splitting on "Fig. 3" cut the ask
 * in half and left "3, which has its perimeter drawn in red" as the apparent question. */
const ABBREVIATION =
  /\b(?:fig|figs|no|nos|vol|ex|eg|ie|q|eq|approx|etc|cf|pp|ch|sec|st|mr|mrs|ms|dr|prof|e\.g|i\.e)\.$/i;

/** A NON-RESTRICTIVE relative / participial clause — ", WHICH has its perimeter drawn in
 * red", ", SHOWN in the diagram" — describes the figure; it never states the ask. Its nouns
 * were being read as targets, so an explicit "Calculate the AREA …, which has its PERIMETER
 * drawn in red" resolved to circumference. Trim it before the target is read. (Only the
 * TARGET scope is trimmed — the givens are always read from the full text.) */
const TRAILING_DESCRIPTION =
  /,\s*(?:which|who|whose|where|shown|drawn|marked|labell?ed|pictured|illustrated|indicated|as\s+shown)\b[\s\S]*$/i;

/** Split prose into sentences on terminal punctuation. LaTeX-flattened text keeps its
 * full stops, so this needs no tokeniser — and a decimal point never ends a sentence
 * because the split requires whitespace after the terminator. */
export function splitSentences(text: string): string[] {
  const parts = text.split(/(?<=[.?!])\s+/);
  const out: string[] = [];
  for (const part of parts) {
    // Re-join a piece whose predecessor ended in an abbreviation's full stop.
    if (out.length > 0 && ABBREVIATION.test(out[out.length - 1])) {
      out[out.length - 1] = `${out[out.length - 1]} ${part}`;
      continue;
    }
    out.push(part);
  }
  return out.map((s) => s.trim()).filter(Boolean);
}

/**
 * The sentence that poses the question, or null when the text is a single sentence (then
 * scenery and ask are inseparable and the caller should use the whole text).
 *
 * The LAST cue-bearing sentence wins: a problem states its setting first and asks last,
 * and a scenery sentence may well contain a cue word of its own ("… is GIVEN in the
 * table", "… WHAT the diagram shows").
 */
export function findAskClause(text: string): string | null {
  const sentences = splitSentences(text);
  const trim = (s: string): string => {
    const cut = s.replace(TRAILING_DESCRIPTION, "").trim();
    // Only trim when something ask-like survives; a sentence that is ALL description must
    // not collapse to a fragment with no cue left in it at all.
    return cut.length > 0 && ASK_CUE.test(cut) ? cut : s;
  };
  // A single sentence has no scenery to separate from the ask — but a trailing description
  // inside it is still description, and trimming that is the whole of what can be scoped.
  if (sentences.length < 2) {
    const only = sentences[0] ?? text;
    const trimmed = trim(only);
    return trimmed === only ? null : trimmed;
  }
  // ONE last-first sweep over every sentence that poses work — a question mark and an
  // imperative cue are equally good ask markers, so neither kind outranks the other by kind;
  // POSITION decides, and the problem's last real question is the ask.
  //
  // [ROUND 29] Sweeping for "?" FIRST (added when "What is the circumference…? State the area
  // formula." resolved to the formula sentence) inverted every lesson-style problem, because a
  // teaching opener is a question and the real ask is an imperative: "Which is bigger, the area
  // or the circumference? A circle has a radius of 9 m. FIND THE AREA." shipped 18π m. The
  // original case no longer needs the priority — FORMULA_SENTENCE now skips the formula
  // instruction outright, so a single positional sweep reaches the question anyway.
  for (let i = sentences.length - 1; i >= 0; i--) {
    const s = sentences[i];
    if (isNotAnAsk(s)) continue;
    if (s.includes("?") || ASK_CUE.test(s)) return trim(s);
  }
  return null;
}

/**
 * The HEAD NOUN of the thing being asked about — "the area of the circular TABLETOP" →
 * "tabletop". Returns null when the ask names no object.
 *
 * This is the other half of subject-bound quantity reading: a value is only the answer's
 * input if it belongs to the figure the question is about. Without it, a span stated of
 * some piece of scenery ("a courtyard 40 m across") is indistinguishable from a span
 * stated of the asked figure.
 */
export function findAskObject(text: string): string | null {
  const scope = findAskClause(text) ?? text;
  // The HEAD of an English noun phrase is its LAST word ("the clock FACE", "the circular
  // TABLETOP"), so the modifier slots are greedy — a lazy read returned "clock" and no span
  // stated of the "face" could ever match it. Function words are barred from both the modifier
  // slots and the head, so the walk stops at the phrase boundary instead of running through a
  // following preposition ("the circumference OF the circle OF radius 7 cm" → "circle", never
  // "radius").
  // "of" introduces the OBJECT in "the area of the circle" but the VALUE in "a circle of radius
  // 7 cm" — and the object reader could not tell them apart, so "the boundary of a circular AREA
  // OF RADIUS 7 CM" resolved its ask object to the UNIT, "cm". Anything downstream that compares
  // the ask object against a noun in the text then compares against a unit. A quantity NAME and
  // a DIGIT both mark the value frame, so neither can stand in the object slot.
  const STOP = String.raw`(?:(?:of|in|on|at|by|to|from|with|whose|that|which|and|or|is|are|was|were|has|have|radius|diameter|circumference|perimeter)\b|\d)`;
  const m = new RegExp(
    String.raw`\b(?:area|circumference|perimeter|radius|diameter)\s+of\s+(?:the\s+|a\s+|an\s+|its\s+|this\s+)?(?:(?!${STOP})\w+\s+){0,2}(?!${STOP})(\w+)\b`,
    "i"
  ).exec(scope);
  if (m) return m[1].toLowerCase();
  // The OTHER English frame for the same question puts the object in the SUBJECT slot of a
  // do-support clause: "How much area DOES THE TIN COVER?", "how much space does the rug take
  // up?". The "<quantity> of <NP>" reader returns null for all of them, so the caller had no
  // asked figure at all and fell back to every span in the text — including a shelf's width,
  // which then sized the tin. Same question, different syntax; read it too.
  const doM = new RegExp(
    String.raw`\bdoes\s+(?:the\s+|a\s+|an\s+|its\s+|this\s+)?(?:(?!${STOP})\w+\s+){0,2}(?!${STOP})(\w+)\s+(?:cover|covers|occupy|occupies|take|takes|span|spans|enclose|encloses|measure|measures|need|needs|require|requires)\b`,
    "i"
  ).exec(scope);
  return doM ? doM[1].toLowerCase() : null;
}
