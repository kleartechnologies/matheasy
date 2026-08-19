import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../result/application/result_controller.dart';
import '../../result/domain/result_models.dart' show ResultData;
import '../../result/presentation/tabs/solution_tab.dart';
import '../../result/presentation/widgets/math_text.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../../tutor/domain/tutor_context_builder.dart';
import '../../tutor/domain/tutor_models.dart';
import '../application/practice_controller.dart';
import '../application/practice_solve_bridge.dart';
import '../domain/practice_question.dart';
import 'practice_visual_screen.dart';

/// Why the guided solution was opened — it changes the framing, not the math.
enum PracticeSolutionMode {
  /// The student is stuck (or gave up): teach the whole journey.
  showSolution,

  /// The student answered CORRECTLY and wants to compare their approach
  /// with Matheasy's method, key idea and memory tip.
  reviewMySolution,
}

/// Route `extra` for [PracticeSolutionScreen].
class PracticeSolutionArgs {
  const PracticeSolutionArgs({
    required this.question,
    required this.mode,
    this.studentAnswer,
  });

  final PracticeQuestion question;
  final PracticeSolutionMode mode;

  /// What the student submitted (correct in review mode, their last wrong
  /// try in show mode) — rendered as "Your answer" above the lesson. Also
  /// the seam a future Compare My Work tab plugs into (alongside
  /// `PracticeAnswer.workSteps` and the server's tutorWork checker).
  final String? studentAnswer;
}

/// The practice "Show Solution" / "Review My Solution" screen — V5's
/// one-engine promise. A solvable question re-enters the REAL verified solve
/// pipeline (`resultControllerProvider`) and renders the same [SolutionTab]
/// guided lesson as the scanner's result page: Understand, Choose Method,
/// every step with its why, common mistakes, memory tips, verification.
///
/// Unsolvable questions (no LaTeX, geometry figures, choice questions) fall
/// back to the question's own deterministic explanation and answer — never a
/// dead end, never an invented step.
class PracticeSolutionScreen extends ConsumerStatefulWidget {
  const PracticeSolutionScreen({super.key, this.args});

  final PracticeSolutionArgs? args;

  @override
  ConsumerState<PracticeSolutionScreen> createState() =>
      _PracticeSolutionScreenState();
}

class _PracticeSolutionScreenState
    extends ConsumerState<PracticeSolutionScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the solution while the question is still live is part of the
    // answer's journey — a later correct submit earns at the 0.5× tier.
    if (widget.args?.mode == PracticeSolutionMode.showSolution) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(practiceControllerProvider.notifier).markSolutionViewed();
      });
    }
  }

  /// Opens Numi with the full structured context — including the verified
  /// [solved] result when the lesson came through the pipeline, so Numi
  /// coaches with the checked steps rather than from the bare question.
  void _askMatheasy(PracticeQuestion question, {ResultData? solved}) {
    context.push(
      AppRoutes.tutorChat,
      extra: TutorLaunchContext(
        problem: TutorContextBuilder.fromPracticeQuestion(
          question,
          studentAnswer: widget.args?.studentAnswer,
          solved: solved,
        ),
      ),
    );
  }

  void _openVisual(PracticeQuestion question) {
    if (!ref.read(isProProvider)) {
      context.push(AppRoutes.paywall, extra: PaywallTrigger.visualLearning);
      return;
    }
    unawaited(context.push(
      AppRoutes.practiceVisual,
      extra: PracticeVisualArgs(
        latex: question.promptLatex ?? question.prompt,
        answerLatex: question.correctAnswerText,
        topicLabel: question.topic.label,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final title = args?.mode == PracticeSolutionMode.reviewMySolution
        ? context.l10n.practiceReviewSolutionTitle
        : context.l10n.practiceSolutionTitle;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: context.l10n.actionClose,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(title),
      ),
      body: SafeArea(
        top: false,
        child: args == null
            ? ErrorState(
                message: context.l10n.practiceSessionStartError,
                onRetry: () => Navigator.of(context).maybePop(),
              )
            : _body(args),
      ),
    );
  }

  Widget _body(PracticeSolutionArgs args) {
    final equation = PracticeSolveBridge.equationFor(args.question);
    if (equation == null) return _fallback(args);

    final async = ref.watch(resultControllerProvider(equation));
    return async.when(
      loading: () => LoadingState(
        message: context.l10n.practiceSolutionLoading,
        showBrand: true,
      ),
      error: (_, _) => _fallback(args),
      data: (result) =>
          result.verified ? _lesson(args, result) : _fallback(args),
    );
  }

  Widget _lesson(PracticeSolutionArgs args, ResultData result) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.lg,
        AppSpacing.screenH,
        AppSpacing.xl,
      ),
      children: [
        if (args.mode == PracticeSolutionMode.reviewMySolution &&
            args.studentAnswer != null) ...[
          _AnswerCompareCard(
            studentAnswer: args.studentAnswer!,
            matheasyAnswer: result.answerLatex.isNotEmpty
                ? result.answerLatex
                : result.answerPlain,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        SolutionTab(
          result: result,
          onAskMatheasy: () => _askMatheasy(args.question, solved: result),
          onOpenVisual: () => _openVisual(args.question),
        ),
      ],
    );
  }

  /// The no-pipeline path: the question's own deterministic explanation (the
  /// generators author it from their verified parameters; AI explanations are
  /// server-screened) plus the correct answer, rendered as math.
  Widget _fallback(PracticeSolutionArgs args) {
    final question = args.question;
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.lg,
        AppSpacing.screenH,
        AppSpacing.xl,
      ),
      children: [
        if (question.promptLatex case final latex?) ...[
          AppCard(
            child: MathText(
              latex,
              style: AppTypography.headingLarge.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.practiceSolutionKeyIdea,
                style: AppTypography.label.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                question.explanation,
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _AnswerCompareCard(
          studentAnswer: args.studentAnswer,
          matheasyAnswer: question.correctAnswerText,
        ),
      ],
    );
  }
}

/// "Your answer" (when present) beside Matheasy's — the review-mode header
/// and the fallback's answer floor.
class _AnswerCompareCard extends StatelessWidget {
  const _AnswerCompareCard({
    required this.matheasyAnswer,
    this.studentAnswer,
  });

  final String matheasyAnswer;
  final String? studentAnswer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (studentAnswer case final answer?) ...[
            Text(
              context.l10n.practiceYourAnswer(answer),
              style: AppTypography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            context.l10n.practiceMatheasyAnswer,
            style: AppTypography.label.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: MathText(
              matheasyAnswer,
              style: AppTypography.headingMedium.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
