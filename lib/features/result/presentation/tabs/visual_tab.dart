import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/functions_client.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../scan/domain/detected_equation.dart';
import '../../../subscription/application/subscription_controller.dart';
import '../../application/animation/animation_script_builder.dart';
import '../../application/visual_solution_controller.dart';
import '../../domain/animation/column_arithmetic.dart';
import '../../domain/animation/decimal_arithmetic.dart';
import '../../domain/animation/derivative_power_rule.dart';
import '../../domain/animation/fraction_arithmetic.dart';
import '../../domain/animation/logarithm.dart';
import '../../domain/animation/long_division.dart';
import '../../domain/animation/long_multiplication.dart';
import '../../domain/animation/matrix_determinant.dart';
import '../../domain/animation/percentage.dart';
import '../../domain/animation/power_root.dart';
import '../../domain/animation/quadratic_formula.dart';
import '../../domain/result_models.dart';
import '../../domain/visual_models.dart';
import '../widgets/result_empty.dart';
import '../widgets/solution_player.dart';
import '../widgets/visual/engine/animated_learning_player.dart';
import '../widgets/visual/engine/column_arithmetic_view.dart';
import '../widgets/visual/engine/decimal_arithmetic_view.dart';
import '../widgets/visual/engine/derivative_power_rule_view.dart';
import '../widgets/visual/engine/engine_l10n.dart';
import '../widgets/visual/engine/fraction_arithmetic_view.dart';
import '../widgets/visual/engine/logarithm_view.dart';
import '../widgets/visual/engine/long_division_view.dart';
import '../widgets/visual/engine/long_multiplication_view.dart';
import '../widgets/visual/engine/matrix_determinant_view.dart';
import '../widgets/visual/engine/percentage_view.dart';
import '../widgets/visual/engine/power_root_view.dart';
import '../widgets/visual/engine/quadratic_formula_view.dart';
import '../widgets/visual/geometry_visual_player.dart';
import '../widgets/visual/tier1_animated_transformation.dart';
import '../widgets/visual/tier2_learning_cards.dart';
import '../widgets/visual/tier3_concept_explorer.dart';
import '../widgets/visual/visual_teaser.dart';

/// Tab 5 — the Visual Learning Engine (Matheasy Pro's flagship feature).
///
/// Free users see the [VisualTeaser] (locked preview + trial CTA — the gate is
/// re-checked on every build so a purchase unlocks instantly). Pro users get
/// the AI-generated [VisualSolution] rendered by the tier matching its
/// category: animated transformations, interactive learning cards, or the
/// concept explorer. Generation failures fall back to the Explain tab and
/// never block the solution flow.
class VisualTab extends ConsumerWidget {
  const VisualTab({
    super.key,
    required this.equation,
    required this.result,
    required this.onUnlock,
    required this.onOpenExplain,
    required this.onAskMatheasy,
  });

  final DetectedEquation equation;
  final ResultData result;

  /// Opens the Visual Learning paywall (free users).
  final VoidCallback onUnlock;

  /// Switches to the Explain tab (the safe fallback).
  final VoidCallback onOpenExplain;

  /// Opens Matheasy with the visual solution and tapped step as context.
  final void Function(VisualSolution visual, int stepIndex) onAskMatheasy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isProProvider)) {
      return VisualTeaser(result: result, onUnlock: onUnlock);
    }

    final async = ref.watch(visualSolutionControllerProvider(equation));
    Widget unavailable() => _VisualUnavailable(
          onRetry: () =>
              ref.invalidate(visualSolutionControllerProvider(equation)),
          onOpenExplain: onOpenExplain,
        );
    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: LoadingState(
          message: context.l10n.visualLoadingMessage,
          showBrand: true,
        ),
      ),
      error: (error, _) {
        // The server rejects a lapsed/absent Pro entitlement even though the
        // client's cached isProProvider still reads true — surface the upgrade
        // path the server explicitly signalled, not a retry that can't win.
        if (error is BackendException &&
            (error.code == 'permission-denied' || error.isQuotaExceeded)) {
          return VisualTeaser(result: result, onUnlock: onUnlock);
        }
        return unavailable();
      },
      data: (visual) {
        // Geometry with a solved, structured scene gets the diagram-first,
        // step-animated player — the drawing leads, not the prose.
        final scene = visual.geometryScene;
        if (scene != null) {
          return GeometryVisualPlayer(
            visual: visual,
            scene: scene,
            onAskMatheasy: (step) => onAskMatheasy(visual, step),
          );
        }
        // Photomath-style FRACTION ARITHMETIC — add/subtract/multiply/divide two
        // fractions (common denominator, combine, simplify). Golden-rule gated.
        final frac = FractionArithmetic.tryBuild(result);
        if (frac != null) {
          return FractionArithmeticView(
            model: frac,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // Photomath-style COLUMN ARITHMETIC — long addition, subtraction, or
        // single-digit multiplication (e.g. 72 × 6, 348 + 275, 502 − 87) laid out
        // digit-by-digit with carries/borrows. Only when the standard algorithm's
        // result equals the verified answer (golden rule).
        final colArith = ColumnArithmetic.tryBuild(result);
        if (colArith != null) {
          return ColumnArithmeticView(
            model: colArith,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // Photomath-style LONG MULTIPLICATION — multi-digit × multi-digit
        // (e.g. 34 × 27): each partial product on its own shifted row, then the
        // partials are added. Golden-rule gated against the verified product.
        final longMul = LongMultiplication.tryBuild(result);
        if (longMul != null) {
          return LongMultiplicationView(
            model: longMul,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // Photomath-style LONG DIVISION — the bracket worksheet (divide,
        // multiply, subtract, bring down) for exact integer division (e.g.
        // 156 ÷ 4). Golden-rule gated against the verified quotient.
        final longDiv = LongDivision.tryBuild(result);
        if (longDiv != null) {
          return LongDivisionView(
            model: longDiv,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // Photomath-style POWERS & ROOTS — a power expands into repeated
        // multiplication (2^5 → 2×2×2×2×2 = 32); a perfect root asks "what
        // number, raised to k, gives n?". Golden-rule gated against the value.
        final powerRoot = PowerRoot.tryBuild(result);
        if (powerRoot != null) {
          return PowerRootView(
            model: powerRoot,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // Photomath-style DECIMAL ARITHMETIC — line up the decimal points for
        // +/− (3.2 + 1.45), or "multiply then place the point" for × (0.5 × 4).
        // Golden-rule gated against the verified value.
        final decimal = DecimalArithmetic.tryBuild(result);
        if (decimal != null) {
          return DecimalArithmeticView(
            model: decimal,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // Photomath-style PERCENTAGE — percent means "out of 100", so rewrite
        // as a fraction of 100 and multiply (15% of 80 → 15/100 × 80 = 12).
        // Golden-rule gated against the verified value.
        final percentage = Percentage.tryBuild(result);
        if (percentage != null) {
          return PercentageView(
            model: percentage,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // Photomath-style QUADRATIC FORMULA — identify a,b,c → formula →
        // substitute → discriminant → two roots (x^2 - 5x + 6 = 0). Golden-rule
        // gated: integer roots that appear in the verified answer.
        final quadratic = QuadraticFormula.tryBuild(result);
        if (quadratic != null) {
          return QuadraticFormulaView(
            model: quadratic,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // Photomath-style DERIVATIVE (power rule) — d/dx of a polynomial: bring
        // each power down as a multiplier and drop it by one. Golden-rule gated:
        // the computed derivative must equal the verified answer.
        final derivative = DerivativePowerRule.tryBuild(result);
        if (derivative != null) {
          return DerivativePowerRuleView(
            model: derivative,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // Photomath-style 2×2 DETERMINANT — main diagonal minus anti-diagonal
        // (ad − bc). Golden-rule gated against the verified determinant.
        final matrixDet = MatrixDeterminant.tryBuild(result);
        if (matrixDet != null) {
          return MatrixDeterminantView(
            model: matrixDet,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // Photomath-style LOGARITHM — "what power of the base gives the number?"
        // (log_2 8 → 3). Golden-rule gated: base^answer == argument exactly.
        final logarithm = Logarithm.tryBuild(result);
        if (logarithm != null) {
          return LogarithmView(
            model: logarithm,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }

        // PRIMARY — the Universal Animated Learning Engine: a watchable,
        // symbol-morphing walkthrough built from the VERIFIED solve payload
        // (terms slide across the =, merges collapse, no LLM math). Fires whenever
        // the solve carried working of its own. The player emits an index into
        // THIS script's beats, so the tutor context is derived from the same
        // script (see result_screen).
        final script = AnimationScriptBuilder.build(result, copy: engineCopy(context));
        if (!script.isEmpty) {
          return AnimatedLearningPlayer(
            script: script,
            onAskMatheasy: (i) => onAskMatheasy(visual, i),
          );
        }
        // FALLBACK — the universal static "Play Solution" step player: works for
        // EVERY problem type (every solve carries its steps), enriched with the
        // server animationSchema's token chips where available. No LLM math.
        final playerSteps = buildPlayerSteps(result);
        if (playerSteps.length >= 2) {
          return SolutionPlayer(
            steps: playerSteps,
            onAskStep: (i) => onAskMatheasy(visual, i),
          );
        }
        // The solve had no working of its own. Prefer the LLM visual's rich tier
        // renderer (concept canvas, interactive cards) when one exists…
        if (visual.hasSteps) {
          return switch (visual.visualization) {
            VisualizationType.animatedTransformation =>
              Tier1AnimatedTransformation(
                visual: visual,
                onAskMatheasy: (step) => onAskMatheasy(visual, step),
              ),
            VisualizationType.interactiveCards => Tier2LearningCards(
                visual: visual,
                onAskMatheasy: (step) => onAskMatheasy(visual, step),
              ),
            VisualizationType.conceptExplorer => Tier3ConceptExplorer(
                visual: visual,
                onAskMatheasy: (step) => onAskMatheasy(visual, step),
              ),
          };
        }
        // …otherwise a verified answer with nothing else to show still animates:
        // morph the problem straight into its answer, so it never dead-ends on the
        // "couldn't show it" screen. Only truly-nothing (no distinct answer) falls
        // through to [unavailable].
        final floor = AnimationScriptBuilder.answerFloor(result, copy: engineCopy(context));
        if (!floor.isEmpty) {
          return AnimatedLearningPlayer(
            script: floor,
            onAskMatheasy: (i) => onAskMatheasy(visual, i),
          );
        }
        return unavailable();
      },
    );
  }
}

/// The never-crash fallback: visual generation failed or came back empty, so
/// point at the Explain tab (which always exists) and offer a retry.
class _VisualUnavailable extends StatelessWidget {
  const _VisualUnavailable({
    required this.onRetry,
    required this.onOpenExplain,
  });

  final VoidCallback onRetry;
  final VoidCallback onOpenExplain;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ResultEmpty(
          message: context.l10n.visualUnavailableMessage,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: context.l10n.visualTryAgain,
                icon: Icons.refresh_rounded,
                size: AppButtonSize.medium,
                onPressed: onRetry,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PrimaryButton(
                label: context.l10n.visualOpenExplain,
                icon: Icons.menu_book_rounded,
                size: AppButtonSize.medium,
                onPressed: onOpenExplain,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
