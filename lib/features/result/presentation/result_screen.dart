import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../practice/domain/practice_session.dart';
import '../../practice/domain/practice_topic.dart';
import '../../scan/domain/detected_equation.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../../tutor/domain/tutor_models.dart';
import '../application/result_controller.dart';
import '../application/visual_prompt_builder.dart';
import '../domain/result_models.dart';
import '../domain/visual_models.dart';
import 'tabs/explain_tab.dart';
import 'tabs/methods_tab.dart';
import 'tabs/practice_tab.dart';
import 'tabs/solution_tab.dart';
import 'tabs/visual_tab.dart';
import 'widgets/play_solution_overlay.dart';
import 'widgets/result_action_bar.dart';
import 'widgets/result_empty.dart';
import 'widgets/result_header.dart';

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

  /// The Visual tab's position — appended last so the practice jump in
  /// [ResultActionBar] (`_selectTab(3)`) keeps its index.
  static const int _visualTabIndex = 4;

  bool _saved = false;

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
      extra: PracticeRequest(topic: _practiceTopicFor(result.type)),
    );
  }

  PracticeTopic _practiceTopicFor(ResultType type) => switch (type) {
        ResultType.linear ||
        ResultType.quadratic ||
        ResultType.expression =>
          PracticeTopic.algebra,
        ResultType.fraction => PracticeTopic.fractions,
        ResultType.trigonometry => PracticeTopic.trigonometry,
      };

  /// Opens the tutor chat aware of this solved problem, so Numi can pick up the
  /// conversation with full context (mock today).
  void _askNumi(ResultData result) {
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

  /// Opens Numi aware of the exact Visual Learning step on screen, so the
  /// tutor can answer "why divide by 2?" about that transformation.
  void _askNumiAboutStep(
    ResultData result,
    VisualSolution visual,
    int stepIndex,
  ) {
    context.push(
      AppRoutes.tutorChat,
      extra: TutorLaunchContext(
        questionLatex: result.questionLatex,
        answerLatex: result.answerLatex,
        equationType: result.type.label,
        topicLabel: visual.category.label,
        visualStepSummary: VisualPromptBuilder.numiStepContext(
          visual,
          stepIndex,
        ),
      ),
    );
  }

  /// The locked Visual tab's CTA — the Visual Learning paywall.
  void _openVisualPaywall() {
    context.push(AppRoutes.paywall, extra: PaywallTrigger.visualLearning);
  }

  @override
  Widget build(BuildContext context) {
    final equation = widget.equation;
    if (equation == null) return _buildNoProblem(context);

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
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: const Text('Solution'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share',
            onPressed: () => _toast('Sharing arrives soon.'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingState(
          message: 'Numi is solving your problem…',
          showMascot: true,
        ),
        error: (error, _) => ErrorState(
          message: "We couldn't solve that one. Try scanning again.",
          onRetry: () => ref.invalidate(resultControllerProvider(equation)),
        ),
        data: (data) => _buildContent(data),
      ),
      bottomNavigationBar: result == null
          ? null
          : ResultActionBar(
              saved: _saved,
              onAskNumi: () => _askNumi(result),
              onGeneratePractice: () {
                _selectTab(3);
                _toast('Fresh practice ready below 👇');
              },
              onToggleSave: () {
                setState(() => _saved = !_saved);
                _toast(_saved ? 'Saved to your library' : 'Removed');
              },
            ),
    );
  }

  Widget _buildContent(ResultData result) {
    final tabIndex = ref.watch(resultTabProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.tabClearance, // clears the floating action bar
      ),
      children: [
        ResultHeader(
          result: result,
          onPlay: () => PlaySolutionOverlay.show(
            context,
            steps: result.steps,
            verifyText: result.verifyText,
          ),
          onRescan: () => context.push(AppRoutes.scan),
        ),
        const SizedBox(height: AppSpacing.section),
        SegmentedControl(
          selectedIndex: tabIndex,
          onChanged: _selectTab,
          items: [
            for (var i = 0; i < _tabLabels.length; i++)
              SegmentItem(
                label: _tabLabels[i],
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
          onAskNumi: () => _askNumi(result),
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
          onAskNumi: (visual, stepIndex) =>
              _askNumiAboutStep(result, visual, stepIndex),
        );
      case 0:
      default:
        return SolutionTab(result: result);
    }
  }

  Widget _buildNoProblem(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 28,
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: const Text('Solution'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ResultEmpty(
                message: 'Nothing to solve yet — scan a problem and I will '
                    'walk you through it.',
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Scan a problem',
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
