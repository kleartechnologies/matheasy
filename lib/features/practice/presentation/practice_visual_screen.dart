import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/functions_client.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/security/rate_limit_result.dart';
import '../../../core/security/rate_limit_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../result/application/animation/animation_script_builder.dart';
import '../../result/application/visual_prompt_builder.dart';
import '../../result/application/visual_solution_service.dart';
import '../../result/domain/visual_models.dart';
import '../../result/presentation/widgets/result_empty.dart';
import '../../result/presentation/widgets/visual/engine/animated_learning_player.dart';
import '../../result/presentation/widgets/visual/engine/engine_l10n.dart';
import '../../result/presentation/widgets/visual/tier1_animated_transformation.dart';
import '../../result/presentation/widgets/visual/tier2_learning_cards.dart';
import '../../result/presentation/widgets/visual/tier3_concept_explorer.dart';
import '../../tutor/domain/tutor_models.dart';

/// Arguments for [PracticeVisualScreen] — everything the Visual Learning Engine
/// needs to walk through a specific practice problem (its answer is already
/// known, so no re-solve is required).
class PracticeVisualArgs {
  const PracticeVisualArgs({
    required this.latex,
    required this.topicLabel,
    this.answerLatex,
    this.typeHint,
  });

  final String latex;
  final String topicLabel;
  final String? answerLatex;
  final String? typeHint;
}

/// The Visual Learning Engine, launched from a practice mistake (Stage 15 ×
/// Stage 14). Reuses the Stage 14 tier renderers but drives them via the
/// service directly (Seam B) with the practice question's known answer, so the
/// walkthrough always agrees with the graded answer. Pro-gated at the launch
/// site; failures degrade to a friendly "unavailable" rather than blocking.
class PracticeVisualScreen extends ConsumerStatefulWidget {
  const PracticeVisualScreen({super.key, this.args});

  final PracticeVisualArgs? args;

  @override
  ConsumerState<PracticeVisualScreen> createState() =>
      _PracticeVisualScreenState();
}

class _PracticeVisualScreenState extends ConsumerState<PracticeVisualScreen> {
  Future<VisualSolution>? _future;

  @override
  void initState() {
    super.initState();
    final args = widget.args;
    if (args != null) _future = _generate(args);
  }

  Future<VisualSolution> _generate(PracticeVisualArgs args) async {
    // Client-side rate guard (the server re-enforces authoritatively).
    final limit = ref
        .read(rateLimitServiceProvider)
        .check(RateLimitedAction.visualGeneration);
    if (limit.isLimited) {
      throw const VisualGenerationException(
        'Give Matheasy a moment before the next visual.',
      );
    }
    return ref.read(visualSolutionServiceProvider).generate(
          VisualRequest(
            latex: args.latex,
            answerLatex: args.answerLatex,
            typeHint: args.typeHint,
          ),
        );
  }

  void _askMatheasy(VisualSolution visual, int stepIndex) {
    final args = widget.args;
    // The engine plays an AnimationScript (from fromVisual) whose beat list is
    // NOT visual.steps — summarise from the same list the learner sees.
    final script = AnimationScriptBuilder.fromVisual(visual, copy: engineCopy(context));
    final summary = script.isEmpty
        ? VisualPromptBuilder.tutorStepContext(visual, stepIndex)
        : VisualPromptBuilder.tutorAnimationStepContext(script, stepIndex);
    context.push(
      AppRoutes.tutorChat,
      extra: TutorLaunchContext(
        questionLatex: args?.latex,
        topicLabel: args?.topicLabel,
        visualStepSummary: summary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: context.l10n.actionClose,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(context.l10n.practiceVisualTitle),
      ),
      body: SafeArea(
        top: false,
        child: future == null
            ? ResultEmpty(
                message: context.l10n.practiceVisualNothing,
              )
            : FutureBuilder<VisualSolution>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xxl,
                      ),
                      child: LoadingState(
                        message: context.l10n.practiceVisualLoading,
                        showBrand: true,
                      ),
                    );
                  }
                  final visual = snapshot.data;
                  if (snapshot.hasError || visual == null || !visual.hasSteps) {
                    return _unavailable(context, snapshot.error);
                  }
                  // Universal Animated Learning Engine — a symbol-morphing
                  // walkthrough built from the (answer-anchored) visual steps.
                  // Falls through to the tiers when there's nothing to morph.
                  final script = AnimationScriptBuilder.fromVisual(
                    visual,
                    copy: engineCopy(context),
                  );
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      AppSpacing.lg,
                      AppSpacing.screenH,
                      AppSpacing.xl,
                    ),
                    child: script.isEmpty
                        ? _tiers(visual)
                        : AnimatedLearningPlayer(
                            script: script,
                            onAskMatheasy: (i) => _askMatheasy(
                              visual,
                              visual.steps.isEmpty
                                  ? 0
                                  : i.clamp(0, visual.steps.length - 1),
                            ),
                          ),
                  );
                },
              ),
      ),
    );
  }

  Widget _tiers(VisualSolution visual) {
    return switch (visual.visualization) {
                      VisualizationType.animatedTransformation =>
                        Tier1AnimatedTransformation(
                          visual: visual,
                          onAskMatheasy: (step) => _askMatheasy(visual, step),
                        ),
                      VisualizationType.interactiveCards => Tier2LearningCards(
                          visual: visual,
                          onAskMatheasy: (step) => _askMatheasy(visual, step),
                        ),
                      VisualizationType.conceptExplorer => Tier3ConceptExplorer(
                          visual: visual,
                          onAskMatheasy: (step) => _askMatheasy(visual, step),
                        ),
    };
  }

  Widget _unavailable(BuildContext context, Object? error) {
    // A server Pro/quota rejection means the entitlement lapsed — send the
    // learner to the paywall rather than a doomed retry.
    if (error is BackendException &&
        (error.code == 'permission-denied' || error.isQuotaExceeded)) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ResultEmpty(
              message: context.l10n.practiceVisualProFeature,
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: context.l10n.practiceSeeProPlans,
              icon: Icons.workspace_premium_rounded,
              onPressed: () => context.pushReplacement(AppRoutes.paywall),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ResultEmpty(
            message: context.l10n.practiceVisualUnavailable,
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: context.l10n.practiceBackToPractice,
            icon: Icons.arrow_back_rounded,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
