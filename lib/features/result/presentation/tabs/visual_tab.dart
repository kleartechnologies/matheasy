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
import '../../domain/result_models.dart';
import '../../domain/visual_models.dart';
import '../widgets/result_empty.dart';
import '../widgets/solution_player.dart';
import '../widgets/visual/engine/animated_learning_player.dart';
import '../widgets/visual/engine/column_arithmetic_view.dart';
import '../widgets/visual/engine/engine_l10n.dart';
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
        // Photomath-style COLUMN ARITHMETIC — long addition, subtraction, or
        // single-digit multiplication (e.g. 72 × 6, 348 + 275, 502 − 87) laid out
        // digit-by-digit with carries/borrows. Only when the standard algorithm's
        // result equals the verified answer (golden rule).
        final colArith = ColumnArithmetic.tryBuild(result);
        if (colArith != null) {
          return ColumnArithmeticView(
            model: colArith,
            onAskStep: (i) => onAskMatheasy(
              visual,
              visual.steps.isEmpty ? 0 : i.clamp(0, visual.steps.length - 1),
            ),
          );
        }

        // PRIMARY — the Universal Animated Learning Engine: a watchable,
        // symbol-morphing walkthrough built from the VERIFIED solve payload
        // (terms slide across the =, merges collapse, no LLM math). When it can't
        // build a script (too few steps), fall through to the static player.
        final script = AnimationScriptBuilder.build(result, copy: engineCopy(context));
        if (!script.isEmpty) {
          return AnimatedLearningPlayer(
            script: script,
            onAskMatheasy: (i) => onAskMatheasy(
              visual,
              visual.steps.isEmpty ? 0 : i.clamp(0, visual.steps.length - 1),
            ),
          );
        }
        // FALLBACK — the universal static "Play Solution" step player: works for
        // EVERY problem type (every solve carries its steps), enriched with the
        // server animationSchema's token chips where available. No LLM math.
        final playerSteps = buildPlayerSteps(result);
        if (playerSteps.length >= 2) {
          return SolutionPlayer(
            steps: playerSteps,
            onAskStep: (i) => onAskMatheasy(
              visual,
              visual.steps.isEmpty ? 0 : i.clamp(0, visual.steps.length - 1),
            ),
          );
        }
        if (!visual.hasSteps) {
          return unavailable();
        }
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
