import 'generation_tier.dart';
import 'practice_topic.dart';

/// A single, atomically-generatable math skill — the unit the Stage 15 engine
/// actually produces questions for.
///
/// [PracticeTopic] stays the coarse dashboard category (Algebra, Fractions, …);
/// a [PracticeSkill] is the fine-grained concept *inside* a topic that a
/// template / rule / AI generator targets (e.g. "two-step equations",
/// "simplify fractions", "derivatives"). This split lets the dashboard and all
/// existing integrations keep using [PracticeTopic] unchanged while the engine
/// reasons about, and adapts to, the skill the learner is actually practicing.
///
/// Each skill declares:
///  * its parent [topic] (for grouping + progress attribution),
///  * the cheapest [tier] that can generate it, and
///  * whether it is [proOnly] (the free tier only ever sees basic template
///    skills — see the monetization rules).
///
/// [id] is a stable string used in fingerprints, per-skill mastery keys and
/// analytics — never renumber it once shipped.
enum PracticeSkill {
  // ---- Algebra — free (basic) ----
  linearOneStep(
    'alg_linear_1',
    PracticeTopic.algebra,
    'One-step equations',
    GenerationTier.template,
  ),
  linearTwoStep(
    'alg_linear_2',
    PracticeTopic.algebra,
    'Two-step equations',
    GenerationTier.template,
  ),
  evaluateExpression(
    'alg_evaluate',
    PracticeTopic.algebra,
    'Evaluate expressions',
    GenerationTier.template,
  ),

  // ---- Algebra — Pro (advanced) ----
  linearBothSides(
    'alg_both_sides',
    PracticeTopic.algebra,
    'Variables on both sides',
    GenerationTier.template,
    proOnly: true,
  ),
  simultaneousEquations(
    'alg_simultaneous',
    PracticeTopic.algebra,
    'Simultaneous equations',
    GenerationTier.template,
    proOnly: true,
  ),
  quadraticFactor(
    'alg_quadratic',
    PracticeTopic.algebra,
    'Factorising quadratics',
    GenerationTier.template,
    proOnly: true,
  ),

  // ---- Fractions — free (basic) ----
  fractionAddLike(
    'fr_add_like',
    PracticeTopic.fractions,
    'Add like fractions',
    GenerationTier.template,
  ),
  fractionAddUnlike(
    'fr_add_unlike',
    PracticeTopic.fractions,
    'Add unlike fractions',
    GenerationTier.template,
  ),
  fractionSimplify(
    'fr_simplify',
    PracticeTopic.fractions,
    'Simplify fractions',
    GenerationTier.template,
  ),

  // ---- Number / applied — free (basic): arithmetic, percentages, ratios ----
  arithmeticOrderOps(
    'num_order_ops',
    PracticeTopic.wordProblems,
    'Order of operations',
    GenerationTier.template,
  ),
  percentOfQuantity(
    'num_percent',
    PracticeTopic.wordProblems,
    'Percentages',
    GenerationTier.template,
  ),
  ratioSimplify(
    'num_ratio',
    PracticeTopic.wordProblems,
    'Simplify ratios',
    GenerationTier.template,
  ),

  // ---- Geometry — Pro (rule-based) ----
  triangleAngle(
    'geo_triangle',
    PracticeTopic.geometry,
    'Triangle angles',
    GenerationTier.ruleBased,
    proOnly: true,
  ),
  rectangleArea(
    'geo_area',
    PracticeTopic.geometry,
    'Area & perimeter',
    GenerationTier.ruleBased,
    proOnly: true,
  ),
  pythagoras(
    'geo_pythagoras',
    PracticeTopic.geometry,
    'Pythagoras',
    GenerationTier.ruleBased,
    proOnly: true,
  ),
  anglesStraightLine(
    'geo_straight_line',
    PracticeTopic.geometry,
    'Angles on a line',
    GenerationTier.ruleBased,
    proOnly: true,
  ),
  quadrilateralAngles(
    'geo_quad_angles',
    PracticeTopic.geometry,
    'Quadrilateral angles',
    GenerationTier.ruleBased,
    proOnly: true,
  ),
  isoscelesTriangle(
    'geo_isosceles',
    PracticeTopic.geometry,
    'Isosceles triangles',
    GenerationTier.ruleBased,
    proOnly: true,
  ),
  circleMeasures(
    'geo_circle',
    PracticeTopic.geometry,
    'Circle radius & diameter',
    GenerationTier.ruleBased,
    proOnly: true,
  ),
  triangleAreaBaseHeight(
    'geo_triangle_area',
    PracticeTopic.geometry,
    'Area of a triangle',
    GenerationTier.ruleBased,
    proOnly: true,
  ),

  // ---- Trigonometry — Pro (rule-based) ----
  trigRatio(
    'trig_ratio',
    PracticeTopic.trigonometry,
    'Trig ratios',
    GenerationTier.ruleBased,
    proOnly: true,
  ),

  // ---- Statistics & probability — Pro (rule-based) ----
  statsMean(
    'stat_mean',
    PracticeTopic.statistics,
    'Mean (average)',
    GenerationTier.ruleBased,
    proOnly: true,
  ),
  statsMedianMode(
    'stat_median_mode',
    PracticeTopic.statistics,
    'Median & mode',
    GenerationTier.ruleBased,
    proOnly: true,
  ),
  probabilitySingle(
    'stat_probability',
    PracticeTopic.statistics,
    'Probability',
    GenerationTier.ruleBased,
    proOnly: true,
  ),

  // ---- Calculus & advanced — Pro (AI) ----
  calculusDerivative(
    'calc_derivative',
    PracticeTopic.calculus,
    'Derivatives',
    GenerationTier.ai,
    proOnly: true,
  ),
  calculusIntegral(
    'calc_integral',
    PracticeTopic.calculus,
    'Integrals',
    GenerationTier.ai,
    proOnly: true,
  ),
  advancedMathematics(
    'adv_general',
    PracticeTopic.calculus,
    'Advanced problems',
    GenerationTier.ai,
    proOnly: true,
  );

  const PracticeSkill(
    this.id,
    this.topic,
    this.label,
    this.tier, {
    this.proOnly = false,
  });

  /// Stable identifier (fingerprints, per-skill mastery keys, analytics).
  final String id;

  /// The dashboard category this skill rolls up into.
  final PracticeTopic topic;

  final String label;

  /// The cheapest tier able to generate this skill.
  final GenerationTier tier;

  /// Pro-exclusive. The free tier only ever generates non-[proOnly] skills.
  final bool proOnly;

  /// Available to a free (non-Pro) learner: a basic, on-device template skill.
  bool get isFree => !proOnly && tier == GenerationTier.template;

  /// The skills belonging to [topic], in declaration order.
  static List<PracticeSkill> forTopic(PracticeTopic topic) =>
      values.where((s) => s.topic == topic).toList();

  /// The free-tier skills belonging to [topic] (basic template skills).
  static List<PracticeSkill> freeForTopic(PracticeTopic topic) =>
      values.where((s) => s.topic == topic && s.isFree).toList();

  /// All free-tier skills, across every topic.
  static List<PracticeSkill> get freeSkills =>
      values.where((s) => s.isFree).toList();

  /// Resolves a skill by its stable [id], or `null` if unknown (e.g. a skill
  /// removed in a later version, read back from persisted history).
  static PracticeSkill? byId(String? id) {
    if (id == null) return null;
    for (final skill in values) {
      if (skill.id == id) return skill;
    }
    return null;
  }

  /// Whether a free learner can practice [topic] at all — i.e. it has at least
  /// one free skill. Advanced topics (geometry, trig, calculus, statistics)
  /// return `false`, so the dashboard routes free users to the paywall.
  static bool topicHasFreeSkills(PracticeTopic topic) =>
      values.any((s) => s.topic == topic && s.isFree);
}
