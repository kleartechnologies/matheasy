import '../../domain/practice_difficulty.dart';
import '../../domain/practice_question.dart';
import '../../domain/practice_skill.dart';

/// The lowest difficulty at which a skill's CONCEPT is appropriate — its concept
/// floor. A concept can't be made primary-level just by shrinking its numbers
/// (factoring a quadratic is inherently multi-step whatever the coefficients),
/// so each skill declares the floor below which it must never be offered.
///
/// Keyed by [PracticeSkill.id] (stable). Unlisted skills default to [easy].
/// This is difficulty-system knowledge, kept here (not on the skill enum) so the
/// taxonomy in `practice_skill.dart` stays about generation tier + monetization.
const Map<String, PracticeDifficulty> _skillConceptFloor = {
  // Very easy — single-step arithmetic / substitution / like-denominator work.
  'alg_linear_1': PracticeDifficulty.veryEasy,
  'alg_evaluate': PracticeDifficulty.veryEasy,
  'fr_add_like': PracticeDifficulty.veryEasy,
  'fr_simplify': PracticeDifficulty.veryEasy,
  'num_order_ops': PracticeDifficulty.veryEasy,
  // Easy — the default (two-step, unlike fractions, %, simple geometry, stats).
  // (alg_linear_2, fr_add_unlike, num_percent, num_ratio, geo_triangle,
  //  geo_area, geo_straight_line, geo_circle, geo_triangle_area, stat_mean,
  //  stat_median_mode all fall through to the easy default.)
  // Medium — inherently multi-step concepts.
  'alg_both_sides': PracticeDifficulty.medium,
  'alg_simultaneous': PracticeDifficulty.medium,
  'alg_quadratic': PracticeDifficulty.medium,
  'geo_pythagoras': PracticeDifficulty.medium,
  'geo_quad_angles': PracticeDifficulty.medium,
  'geo_isosceles': PracticeDifficulty.medium,
  'trig_ratio': PracticeDifficulty.medium,
  'stat_probability': PracticeDifficulty.medium,
  // Hard / Expert — A-Level and university concepts (AI-generated).
  'calc_derivative': PracticeDifficulty.hard,
  'calc_integral': PracticeDifficulty.hard,
  'adv_general': PracticeDifficulty.expert,
};

/// The concept floor for [skill] — the lowest difficulty it may be offered at.
PracticeDifficulty conceptFloor(PracticeSkill skill) =>
    _skillConceptFloor[skill.id] ?? PracticeDifficulty.easy;

/// Whether [skill] is appropriate at [difficulty] — its concept floor is at or
/// below the level. Enforces the spec's "no concepts above the selected
/// difficulty" (a quadratic never appears at Very Easy).
bool skillAllowedAt(PracticeSkill skill, PracticeDifficulty difficulty) =>
    conceptFloor(skill).index <= difficulty.index;

/// Deterministic post-generation gate for the on-device (template / rule) path.
///
/// The templates are correct-by-construction for their number ranges (they draw
/// within the difficulty-indexed tables), so this validator enforces the two
/// things ranges alone don't guarantee: the CONCEPT is not above the level, and
/// the step budget is respected. A failing candidate is discarded and the
/// orchestrator regenerates — never silently kept at the wrong level.
class DifficultyValidator {
  const DifficultyValidator();

  /// Returns true if [question] is valid AT [difficulty].
  bool isValid(PracticeQuestion question, PracticeDifficulty difficulty) {
    // The question must declare the level it was requested at.
    if (question.difficulty != difficulty) return false;

    // Concept ceiling: the skill's floor must not exceed the level.
    final skill = PracticeSkill.byId(question.skillId);
    if (skill != null && !skillAllowedAt(skill, difficulty)) return false;

    // Step budget: measured steps must fit the level's ceiling. Today the
    // on-device templates are correct-by-construction (within budget) and don't
    // stamp `estimatedSteps`, so `question.steps` falls back to the level's
    // targetSteps (<= maxSteps) and this is a forward-looking guard — it bites
    // the moment a generator (e.g. the AI path) stamps a real, over-budget count.
    if (question.steps > difficulty.spec.maxSteps) return false;

    return true;
  }
}
