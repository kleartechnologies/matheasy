import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../practice/domain/practice_session.dart';
import '../../practice/domain/practice_topic.dart';
import '../../scan/domain/detected_equation.dart';
import '../../scan/presentation/manual_input_screen.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../../tutor/domain/tutor_models.dart';
import '../application/animation/animation_script_builder.dart';
import '../application/geometry_payload_mapper.dart';
import '../application/result_controller.dart';
import '../application/visual_prompt_builder.dart';
import '../domain/animation/column_arithmetic.dart';
import '../domain/animation/decimal_arithmetic.dart';
import '../domain/animation/fraction_arithmetic.dart';
import '../domain/animation/long_division.dart';
import '../domain/animation/long_multiplication.dart';
import '../domain/animation/power_root.dart';
import '../domain/geometry_models.dart';
import '../domain/result_models.dart';
import '../domain/teaching_models.dart';
import '../domain/visual_models.dart';
import 'tabs/explain_tab.dart';
import 'tabs/methods_tab.dart';
import 'tabs/practice_tab.dart';
import 'tabs/solution_tab.dart';
import 'tabs/visual_tab.dart';
import 'widgets/result_action_bar.dart';
import 'widgets/result_couldnt_verify.dart';
import 'widgets/result_empty.dart';
import 'widgets/result_header.dart';
import 'widgets/result_scan_image.dart';
import 'widgets/result_tutor_invite.dart';
import 'widgets/teaching/teaching_cards.dart';
import 'widgets/visual/engine/engine_l10n.dart';
import 'widgets/visual/geometry_visual_player.dart';

/// The Scan Result experience — the most-used screen in the app. Renders the
/// answer, a step-by-step solution, explanations, methods, practice and the
/// Pro-gated Visual Learning tab, plus the Play Solution walkthrough and a
/// persistent action bar.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, this.equation});

  final DetectedEquation? equation;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  static const List<String> _tabLabels = [
    'Solution',
    'Explain',
    'Methods',
    'Practice',
    'Visual',
  ];

  /// The localized label for tab [i] — the result tabs follow the learner's
  /// language (the math inside each tab stays universal).
  String _tabLabel(BuildContext context, int i) => switch (i) {
        0 => context.l10n.resultTabSolution,
        1 => context.l10n.resultTabExplain,
        2 => context.l10n.resultTabMethods,
        3 => context.l10n.resultTabPractice,
        _ => context.l10n.resultTabVisual,
      };

  /// The Visual tab's position — appended last so the practice jump in
  /// [ResultActionBar] (`_selectTab(3)`) keeps its index.
  static const int _visualTabIndex = 4;

  bool _saved = false;

  /// The scene built from the recognizer's structured geometry facts, computed
  /// once (parsing + solving is deterministic and cheap, but a stable instance
  /// keeps the player's repaint keyed on real changes, not identity churn).
  GeometryScene? _scannedScene;
  bool _sceneResolved = false;

  GeometryScene? get _scannedGeometryScene {
    if (!_sceneResolved) {
      _sceneResolved = true;
      _scannedScene = GeometryPayloadMapper.parse(widget.equation?.geometry);
    }
    return _scannedScene;
  }

  @override
  void initState() {
    super.initState();
    // Reset to the Solution tab when this is a different problem; keep the
    // remembered tab when re-visiting the same one. Deferred post-frame
    // because Riverpod forbids provider mutation during build — invisible
    // here since the tabs only render after the solver's loading state.
    final equation = widget.equation;
    if (equation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(resultTabProvider.notifier).syncFor(equation);
        }
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectTab(int index) =>
      ref.read(resultTabProvider.notifier).select(index);

  /// Launches a practice session on the topic of the solved problem.
  void _practice(ResultData result) {
    context.push(
      AppRoutes.practiceSession,
      extra: PracticeRequest(topic: PracticeTopic.fromResultType(result.type)),
    );
  }

  /// Opens the tutor on a problem that has no verified answer to show — a
  /// proof/conceptual prompt, or one whose answer failed the substitution check.
  /// SEEDED so it auto-sends the opening ask, landing the student mid-
  /// conversation. Passes no `answerLatex`: there is no answer to stand behind.
  void _discussProblem(ResultData result) {
    context.push(
      AppRoutes.tutorChat,
      extra: TutorLaunchContext(
        questionLatex: result.questionLatex,
        equationType: result.type.label,
        topicLabel: result.type.label,
        seedMessage:
            context.l10n.resultDiscussSeedMessage(result.questionLatex),
      ),
    );
  }

  /// Opens the tutor chat aware of this solved problem, so Matheasy can pick up
  /// the conversation with full context (mock today).
  void _askMatheasy(ResultData result) {
    context.push(
      AppRoutes.tutorChat,
      extra: TutorLaunchContext(
        questionLatex: result.questionLatex,
        answerLatex: result.answerLatex,
        equationType: result.type.label,
        topicLabel: result.type.label,
      ),
    );
  }

  /// Opens Matheasy aware of the exact Visual Learning step on screen, so the
  /// tutor can answer "why divide by 2?" about that transformation.
  void _askMatheasyAboutStep(
    ResultData result,
    VisualSolution visual,
    int stepIndex,
  ) {
    // Summarise from whichever player actually rendered — mirror the Visual tab's
    // dispatch (geometry → fraction/column/long-mult/long-div → Animated Learning
    // Engine → tiers) so the emitted index always indexes the SAME list the
    // learner is looking at.
    final scene = visual.geometryScene;
    final method = scene == null ? _methodStep(result, stepIndex) : null;
    final String stepSummary;
    if (scene != null) {
      stepSummary = VisualPromptBuilder.tutorGeometryStepContext(scene, stepIndex);
    } else if (method != null) {
      stepSummary = VisualPromptBuilder.tutorMethodStepContext(
        methodLabel: method.label,
        index: stepIndex,
        total: method.total,
        caption: method.caption,
        callout: method.callout,
      );
    } else {
      // Mirror the Visual tab's fallthrough exactly: the Animated Learning Engine
      // (from solver working) → the LLM visual's tier → the answer-floor morph.
      final script = AnimationScriptBuilder.build(result, copy: engineCopy(context));
      if (!script.isEmpty) {
        stepSummary =
            VisualPromptBuilder.tutorAnimationStepContext(script, stepIndex);
      } else if (visual.hasSteps) {
        stepSummary = VisualPromptBuilder.tutorStepContext(visual, stepIndex);
      } else {
        final floor = AnimationScriptBuilder.answerFloor(result, copy: engineCopy(context));
        stepSummary = floor.isEmpty
            ? VisualPromptBuilder.tutorStepContext(visual, stepIndex)
            : VisualPromptBuilder.tutorAnimationStepContext(floor, stepIndex);
      }
    }
    context.push(
      AppRoutes.tutorChat,
      extra: TutorLaunchContext(
        questionLatex: result.questionLatex,
        answerLatex: result.answerLatex,
        equationType: result.type.label,
        topicLabel: visual.category.label,
        visualStepSummary: stepSummary,
      ),
    );
  }

  /// If a bespoke method player renders this result (mirroring the Visual tab's
  /// dispatch order), the caption/callout for its step at [stepIndex]. Null when
  /// none applies (→ the Animated Learning Engine / tier summarisers handle it).
  ({String label, int total, String caption, String? callout})? _methodStep(
    ResultData result,
    int stepIndex,
  ) {
    final frac = FractionArithmetic.tryBuild(result);
    if (frac != null) {
      final i = stepIndex.clamp(0, frac.steps.length - 1);
      return (
        label: 'fraction',
        total: frac.steps.length,
        caption: frac.steps[i].caption,
        callout: frac.steps[i].callout,
      );
    }
    final col = ColumnArithmetic.tryBuild(result);
    if (col != null) {
      final i = stepIndex.clamp(0, col.steps.length - 1);
      return (
        label: 'column arithmetic',
        total: col.steps.length,
        caption: col.steps[i].caption,
        callout: col.steps[i].callout,
      );
    }
    final lmul = LongMultiplication.tryBuild(result);
    if (lmul != null) {
      final i = stepIndex.clamp(0, lmul.steps.length - 1);
      return (
        label: 'long multiplication',
        total: lmul.steps.length,
        caption: lmul.steps[i].caption,
        callout: lmul.steps[i].callout,
      );
    }
    final ldiv = LongDivision.tryBuild(result);
    if (ldiv != null) {
      final i = stepIndex.clamp(0, ldiv.steps.length - 1);
      return (
        label: 'long division',
        total: ldiv.steps.length,
        caption: ldiv.steps[i].caption,
        callout: ldiv.steps[i].callout,
      );
    }
    final pr = PowerRoot.tryBuild(result);
    if (pr != null) {
      final i = stepIndex.clamp(0, pr.steps.length - 1);
      return (
        label: 'powers & roots',
        total: pr.steps.length,
        caption: pr.steps[i].caption,
        callout: pr.steps[i].callout,
      );
    }
    final dec = DecimalArithmetic.tryBuild(result);
    if (dec != null) {
      final i = stepIndex.clamp(0, dec.steps.length - 1);
      return (
        label: 'decimal arithmetic',
        total: dec.steps.length,
        caption: dec.steps[i].caption,
        callout: dec.steps[i].callout,
      );
    }
    return null;
  }

  /// The locked Visual tab's CTA — the Visual Learning paywall.
  void _openVisualPaywall() {
    context.push(AppRoutes.paywall, extra: PaywallTrigger.visualLearning);
  }

  @override
  Widget build(BuildContext context) {
    final equation = widget.equation;
    if (equation == null) return _buildNoProblem(context);

    // Scanned geometry (Pro): the recognizer extracted structured facts, so we
    // render the diagram-first player DIRECTLY from them — the geometry-blind
    // solver can't verify these, but the app computes the measure itself. No
    // solve call needed. Free users fall through to the normal (couldn't-verify
    // / tutor) flow, keeping the visual feature Pro-only.
    final geoScene = _scannedGeometryScene;
    if (geoScene != null && ref.watch(isProProvider)) {
      return _buildGeometryScaffold(geoScene);
    }

    final async = ref.watch(resultControllerProvider(equation));
    final result = switch (async) {
      AsyncData(:final value) => value,
      _ => null,
    };

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 28,
          tooltip: context.l10n.resultBack,
          onPressed: () => context.pop(),
        ),
        title: Text(context.l10n.resultTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: context.l10n.resultShare,
            onPressed: () => _toast(context.l10n.resultSharingSoon),
          ),
        ],
      ),
      body: async.when(
        loading: () => LoadingState(
          message: context.l10n.resultSolvingMessage,
          showBrand: true,
        ),
        error: (error, _) => _buildSolveError(error),
        data: (data) => _buildContent(data),
      ),
      bottomNavigationBar: result == null || !result.verified
          ? null
          : ResultActionBar(
              saved: _saved,
              onAskMatheasy: () => _askMatheasy(result),
              onGeneratePractice: () {
                _selectTab(3);
                _toast(context.l10n.resultPracticeReady);
              },
              onToggleSave: () {
                setState(() => _saved = !_saved);
                _toast(_saved
                    ? context.l10n.resultSavedToLibrary
                    : context.l10n.resultRemoved);
              },
            ),
    );
  }

  /// The scanned-geometry experience: the diagram-first player built straight
  /// from the recognizer's structured facts (no solver round-trip), with the
  /// scanned photo above it.
  Widget _buildGeometryScaffold(GeometryScene scene) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 28,
          tooltip: context.l10n.resultBack,
          onPressed: () => context.pop(),
        ),
        title: Text(context.l10n.resultTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.md,
          AppSpacing.screenH,
          AppSpacing.xl,
        ),
        children: [
          ResultScanImageSlot(imageBytes: widget.equation?.imageBytes),
          GeometryVisualPlayer(
            visual: _geoVisual(scene),
            scene: scene,
            onAskMatheasy: (step) => _askMatheasyAboutGeometry(scene, step),
          ),
        ],
      ),
    );
  }

  /// A minimal [VisualSolution] wrapping a scanned [GeometryScene] — the player
  /// only reads the scene (plus optional method/key-ideas, absent here).
  VisualSolution _geoVisual(GeometryScene scene) => VisualSolution(
        category: ProblemCategory.geometry,
        difficulty: ProblemDifficulty.secondary,
        visualization: VisualizationType.conceptExplorer,
        answerLatex: scene.answerLatex,
        intro: '',
        steps: const [],
        geometryScene: scene,
      );

  void _askMatheasyAboutGeometry(GeometryScene scene, int stepIndex) {
    context.push(
      AppRoutes.tutorChat,
      extra: TutorLaunchContext(
        questionLatex: widget.equation?.latex ?? '',
        answerLatex: scene.answerLatex,
        equationType: 'Geometry',
        topicLabel: ProblemCategory.geometry.label,
        visualStepSummary:
            VisualPromptBuilder.tutorGeometryStepContext(scene, stepIndex),
      ),
    );
  }

  /// The solve-threw state (spec §9). An offline drop gets its own honest voice
  /// — and names what still works (saved solutions open offline) — instead of
  /// telling the user to "scan again", which would also fail with no signal.
  Widget _buildSolveError(Object error) {
    final offline = error is ResultSolveFailure && error.offline;
    // Reachable only past the null-equation guard in build().
    void retry() => ref.invalidate(resultControllerProvider(widget.equation!));
    return offline
        ? ErrorState(
            title: context.l10n.resultOfflineTitle,
            message: context.l10n.resultOfflineMessage,
            retryLabel: context.l10n.actionRetry,
            onRetry: retry,
          )
        : ErrorState(
            title: context.l10n.resultSolveErrorTitle,
            message: context.l10n.resultSolveErrorMessage,
            onRetry: retry,
          );
  }

  /// The honest concept-teaching section shown above the tutor invite for a
  /// routeToTutor problem — teaches the APPROACH (no fabricated answer). Each
  /// card self-hides when its content is empty.
  List<Widget> _honestTeachingCards(TeachingLayer teaching) => [
        TeachingHeaderCard(header: teaching.header),
        const SizedBox(height: AppSpacing.md),
        if (!teaching.concept.isEmpty) ...[
          ConceptOverviewCard(
            concept: teaching.concept,
            overview: teaching.overview,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if ((teaching.approach ?? const []).isNotEmpty) ...[
          ApproachCard(approach: teaching.approach!),
          const SizedBox(height: AppSpacing.md),
        ],
        if (teaching.commonMistakes.any((m) => m.mistake.isNotEmpty)) ...[
          CommonMistakesCard(mistakes: teaching.commonMistakes),
          const SizedBox(height: AppSpacing.md),
        ],
        if (!teaching.keyTakeaway.isEmpty)
          KeyTakeawayCard(takeaway: teaching.keyTakeaway),
      ];

  Widget _buildContent(ResultData result) {
    // The photo the problem was scanned from (when present) — shown at the top
    // of every state so a figure-based problem (geometry) is visible even when
    // there's no computable answer.
    final scanImage = ResultScanImageSlot(imageBytes: widget.equation?.imageBytes);

    // A proof / abstract-algebra / analysis prompt (spec §1): there's nothing to
    // compute-and-verify, so invite the student to reason it through in the tutor
    // rather than show a misleading "couldn't verify" error.
    if (result.routeToTutor) {
      final teaching = result.teaching;
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xl,
        ),
        children: [
          scanImage,
          // HONEST-mode concept teaching (spec §0.5): even a problem the solver
          // can't verify (a proof / conceptual / multi-part) teaches the APPROACH
          // from first principles — above the tutor hand-off, never an answer.
          // Concept is the anchor of honest teaching; gating the whole section on
          // it means a malformed layer can never paint a lone header breadcrumb.
          if (teaching != null &&
              teaching.isHonest &&
              !teaching.concept.isEmpty) ...[
            ..._honestTeachingCards(teaching),
            const SizedBox(height: AppSpacing.lg),
          ],
          ResultTutorInvite(
            result: result,
            onDiscuss: () => _discussProblem(result),
            onEdit: () => context.push(
              AppRoutes.manualInput,
              extra: ManualInputArgs(initialLatex: result.questionLatex),
            ),
          ),
        ],
      );
    }

    // The answer failed its substitution check (spec §1.1): show the honest
    // "couldn't verify" state (spec §9), not a confident (empty) answer.
    if (!result.verified) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xl,
        ),
        children: [
          scanImage,
          ResultCouldntVerify(
            result: result,
            onRescan: () => context.push(AppRoutes.scan),
            // Pre-fill the editor with what we read so the student fixes the
            // likely misread in place (a corrected read then solves normally).
            onEdit: () => context.push(
              AppRoutes.manualInput,
              extra: ManualInputArgs(initialLatex: result.questionLatex),
            ),
            // The way forward when the read was right and the check still
            // failed — the same seeded tutor hand-off the conceptual state uses.
            onDiscuss: () => _discussProblem(result),
          ),
        ],
      );
    }

    final tabIndex = ref.watch(resultTabProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.tabClearance, // clears the floating action bar
      ),
      children: [
        scanImage,
        ResultHeader(
          result: result,
          // "Play step-by-step" now jumps to the Pro Visual tab — the animated
          // walkthrough lives there (free users meet the unlock), so Play Solution
          // is a single, Pro experience rather than a duplicate free overlay.
          onPlay: () => _selectTab(_visualTabIndex),
          onRescan: () => context.push(AppRoutes.scan),
        ),
        const SizedBox(height: AppSpacing.lg),
        SegmentedControl(
          selectedIndex: tabIndex,
          onChanged: _selectTab,
          items: [
            for (var i = 0; i < _tabLabels.length; i++)
              SegmentItem(
                label: _tabLabel(context, i),
                // The Pro star on the Visual segment (the "Visual ⭐" tab).
                icon: i == _visualTabIndex ? Icons.auto_awesome_rounded : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        // AnimatedSize smooths the height change between tabs of very
        // different lengths while the content cross-fades.
        AnimatedSize(
          duration: AppDurations.medium,
          curve: AppCurves.standard,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: AppDurations.medium,
            transitionBuilder: AppTransitions.fadeThrough,
            child: KeyedSubtree(
              key: ValueKey(tabIndex),
              child: _buildTab(tabIndex, result),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTab(int index, ResultData result) {
    switch (index) {
      case 1:
        return ExplainTab(
          explanations: result.explanations,
          onAskMatheasy: () => _askMatheasy(result),
        );
      case 2:
        return MethodsTab(methods: result.methods);
      case 3:
        return PracticeTab(
          questions: result.practice,
          onGenerateMore: () => _practice(result),
          onOpenQuestion: () => _practice(result),
        );
      case _visualTabIndex:
        return VisualTab(
          equation: result.equation,
          result: result,
          onUnlock: _openVisualPaywall,
          onOpenExplain: () => _selectTab(1),
          onAskMatheasy: (visual, stepIndex) =>
              _askMatheasyAboutStep(result, visual, stepIndex),
        );
      case 0:
      default:
        return SolutionTab(
          result: result,
          onOpenVisual: () => _selectTab(_visualTabIndex),
          onOpenMethods: () => _selectTab(2),
          onAskMatheasy: () => _askMatheasy(result),
          // A practice-ladder rung re-enters the solve pipeline as a fresh
          // problem (it ships as a PROBLEM, never an answer) via the editor.
          onAttemptPractice: (item) => context.push(
            AppRoutes.manualInput,
            extra: ManualInputArgs(initialLatex: item.latex),
          ),
        );
    }
  }

  Widget _buildNoProblem(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 28,
          tooltip: context.l10n.resultBack,
          onPressed: () => context.pop(),
        ),
        title: Text(context.l10n.resultTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ResultEmpty(
                message: context.l10n.resultNoProblemMessage,
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: context.l10n.resultScanAProblem,
                icon: Icons.center_focus_strong_rounded,
                expand: false,
                onPressed: () => context.push(AppRoutes.scan),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
