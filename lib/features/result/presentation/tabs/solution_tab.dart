import 'package:flutter/material.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/animations/motion_aware_size.dart';
import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../practice_set/presentation/practice_set_card.dart';
import '../../domain/result_models.dart';
import '../widgets/learn_more_sheet.dart';
import '../widgets/lesson_summary.dart';
import '../widgets/step_spine.dart';

/// Where the learner is in the guided journey.
enum LessonPhase {
  /// Answer's on screen; the lesson hasn't started. One CTA, nothing else.
  intro,

  /// Walking the spine — every step visible, one opened.
  learning,

  /// The learner reached the Solution row — summary, practice reward, Numi.
  complete,
}

/// V3 · the Solution tab, rebuilt as a **guided journey** instead of a page.
///
/// The screen above already answered *what is the answer?*. This tab answers
/// *why?* — and it answers it one question at a time:
///
///   §3 Start Learning → §4 the step player → §5 the summary → §6 practice →
///   §7 Numi (only once the lesson is done).
///
/// Everything optional — the idea, what it asks, the plan, the glossary, method
/// comparison, the three explanation voices, every mistake, the graph — is one
/// tap away in [LearnMoreSheet] and collapsed by default. Nothing was deleted;
/// it simply stopped competing with the solve.
class SolutionTab extends StatefulWidget {
  const SolutionTab({
    super.key,
    required this.result,
    this.onOpenVisual,
    this.onAskMatheasy,
    this.onPracticeTopic,
  });

  final ResultData result;

  /// Opens the Visual Learning tab. Offered *after* the lesson, never before —
  /// the animation is a second pass over ground the learner already covered.
  final VoidCallback? onOpenVisual;

  /// Opens Numi. Only surfaced at the end ("still confused?"), never pinned.
  final VoidCallback? onAskMatheasy;

  /// Falls back to topic practice when the payload carries no ladder.
  /// (When it does carry one, the shared [PracticeSetSection] renders the
  /// practice-set journey and handles its own navigation.)
  final VoidCallback? onPracticeTopic;

  @override
  State<SolutionTab> createState() => _SolutionTabState();
}

class _SolutionTabState extends State<SolutionTab> {
  /// Which row of the spine the learner is on. `null` means the lesson hasn't
  /// started; `steps.length` is the Solution row, the end of the lesson.
  int? _cursor;

  /// Whether that row is opened into a card. The ✕ shuts it without moving the
  /// cursor, so the learner drops back to the bare list and keeps their place.
  bool _open = true;

  /// Sticky once the Solution row has been reached: shutting the card, or
  /// stepping back to re-read step 2, must not pull the summary out from under
  /// a learner who has already finished.
  bool _finished = false;

  int _method = 0;

  List<MethodSolution> get _methods => widget.result.methods;

  /// The steps for the selected method: its own structured stepper, else the
  /// top-level steps (exam pick), else derived from its plain-text steps.
  List<SolutionStep> get _steps {
    if (_methods.isEmpty) return widget.result.steps;
    final method = _methods[_method.clamp(0, _methods.length - 1)];
    if (method.stepperSteps.isNotEmpty) return method.stepperSteps;
    if (method.recommended && widget.result.steps.isNotEmpty) {
      return widget.result.steps;
    }
    return [
      for (final s in method.steps)
        SolutionStep(title: '', resultLatex: s, detail: ''),
    ];
  }

  String get _methodName =>
      _methods.isEmpty ? '' : _methods[_method.clamp(0, _methods.length - 1)].name;

  /// The Solution row: one past the last step.
  int get _solutionIndex => _steps.length;

  LessonPhase get _phase {
    if (_cursor == null) return LessonPhase.intro;
    return _finished ? LessonPhase.complete : LessonPhase.learning;
  }

  void _focusStep(int index) {
    final target = index.clamp(0, _solutionIndex);
    setState(() {
      _cursor = target;
      _open = true;
      if (target >= _solutionIndex) _finished = true;
    });
  }

  void _start() => _focusStep(0);

  /// Shut, "Next step" reopens where you are rather than skipping a step you
  /// never read.
  void _next() => _open ? _focusStep((_cursor ?? -1) + 1) : _focusStep(_cursor ?? 0);

  void _back() => _focusStep((_cursor ?? 1) - 1);

  void _collapse() => setState(() => _open = false);

  void _replay() => setState(() {
        _cursor = 0;
        _open = true;
        _finished = false;
      });

  /// Switching methods restarts the walkthrough — a half-finished lesson in one
  /// method makes no sense in another.
  void _useMethod(int index) {
    if (index == _method || index < 0 || index >= _methods.length) return;
    setState(() {
      _method = index;
      _cursor = 0;
      _open = true;
      _finished = false;
    });
  }

  void _openLearnMore() => LearnMoreSheet.show(
        context,
        result: widget.result,
        onUseMethod: _useMethod,
        onAskMatheasy: widget.onAskMatheasy ?? () {},
      );

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    // Nothing to walk through (a bare answer, or a method with no steps) — skip
    // straight to the takeaway rather than offering an empty lesson.
    final phase = steps.isEmpty ? LessonPhase.complete : _phase;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.medium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The spine outlives the lesson: once it's up it stays up, so a learner
        // reading the summary can still glance back at step 2 — or tap it.
        if (phase != LessonPhase.intro && steps.isNotEmpty) ...[
          StepSpine(
            key: ValueKey('spine-$_method'),
            problemLatex: widget.result.equation.latex,
            steps: steps,
            answerLatex: widget.result.answerLatex,
            focused: (_cursor ?? 0).clamp(0, steps.length),
            expanded: _open,
            onFocus: _focusStep,
            onCollapse: _collapse,
            onNext: _next,
            onBack: _back,
            glossary:
                widget.result.teaching?.concept.definedTerms ?? const [],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        MotionAwareSize(
          duration: motion,
          curve: AppCurves.standard,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: motion,
            transitionBuilder: AppTransitions.fadeThrough,
            child: KeyedSubtree(
              key: ValueKey('$phase-$_method'),
              child: switch (phase) {
                LessonPhase.intro => _buildIntro(context),
                // The spine above IS the lesson — nothing to add underneath it
                // until the learner reaches the end.
                LessonPhase.learning => const SizedBox(width: double.infinity),
                LessonPhase.complete => _buildComplete(context, steps),
              },
            ),
          ),
        ),
        // The one door to everything optional: always last on the page, always
        // shut. Reachable mid-lesson (a learner stuck on a word needs the
        // glossary *now*) without ever being in the way.
        const SizedBox(height: AppSpacing.lg),
        _LearnMoreRow(onTap: _openLearnMore),
      ],
    );
  }

  // --- §3 the invitation ----------------------------------------------------

  Widget _buildIntro(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One line in the tutor's voice — the whole reason this doesn't feel
        // like a textbook. One line, not a paragraph.
        if (widget.result.tutorIntro.isNotEmpty) ...[
          MatheasyBubble(text: widget.result.tutorIntro, avatarSize: 28),
          const SizedBox(height: AppSpacing.lg),
        ],
        PrimaryButton(
          label: context.l10n.resultStartLearning,
          icon: Icons.play_arrow_rounded,
          onPressed: _start,
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            context.l10n.resultStartLearningHint,
            textAlign: TextAlign.center,
            style: AppTypography.caption
                .copyWith(color: context.colors.textSecondary),
          ),
        ),
      ],
    );
  }

  // --- §5–§7 the close ------------------------------------------------------

  Widget _buildComplete(BuildContext context, List<SolutionStep> steps) {
    final teaching = widget.result.teaching;
    final ladder = teaching?.practiceLadder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LessonSummary(
          result: widget.result,
          methodName: _methodName,
          onReplay: _replay,
        ),
        // The animation is a *re-watch*, offered once the learner has done the
        // thinking — never as a shortcut past it.
        if (widget.onOpenVisual != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _WatchItAnimateRow(onTap: widget.onOpenVisual!),
        ],
        // §6 — practice is the reward for finishing, so it lands here and
        // nowhere earlier. Skipped entirely when there is nothing to practise:
        // a header over an empty space is the exact clutter V3 removes.
        if (ladder != null || widget.onPracticeTopic != null) ...[
          const SizedBox(height: AppSpacing.xl),
          _SectionIntro(
            title: context.l10n.solutionPracticeTitle,
            subtitle: context.l10n.solutionPracticeSubtitle,
          ),
          const SizedBox(height: AppSpacing.md),
          if (ladder != null)
            // The shared practice-set component: the same card (and the same
            // stored completion state) the Final Answer strip, Visual tab,
            // Practice tab and History show for this problem.
            PracticeSetSection(result: widget.result)
          else
            SecondaryButton(
              label: context.l10n.solutionPracticeThisTopic,
              icon: Icons.fitness_center_rounded,
              onPressed: widget.onPracticeTopic,
            ),
        ],
        // §7 — Numi, last, and only for the learner who still needs them.
        if (widget.onAskMatheasy != null) ...[
          const SizedBox(height: AppSpacing.xl),
          _StillConfused(onAsk: widget.onAskMatheasy!),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: AppTypography.title.copyWith(color: colors.textPrimary)),
        Text(subtitle,
            style:
                AppTypography.caption.copyWith(color: colors.textSecondary)),
      ],
    );
  }
}

/// The single entry point to every optional layer — a quiet row, not a card.
class _LearnMoreRow extends StatelessWidget {
  const _LearnMoreRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.resultLearnMore,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.mdRadius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: AppRadius.mdRadius,
          ),
          child: Row(
            children: [
              Icon(Icons.auto_stories_rounded, size: 18, color: colors.textMuted),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.resultLearnMore,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      context.l10n.resultLearnMoreSubtitle,
                      style: AppTypography.caption
                          .copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_right_rounded,
                  size: 20, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Post-lesson invitation into the animated walkthrough.
class _WatchItAnimateRow extends StatelessWidget {
  const _WatchItAnimateRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.solutionOpenVisualLearning,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            gradient: AppColors.premiumGradient,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 22, color: AppColors.goldLight),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.solutionWatchItAnimate,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      context.l10n.solutionWatchItAnimateSubtitle,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.goldLight),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_right_rounded,
                  size: 20, color: AppColors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// §7 — the tutor hand-off, offered only after the lesson is done.
class _StillConfused extends StatelessWidget {
  const _StillConfused({required this.onAsk});

  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.solutionStillConfused,
          style: AppTypography.title.copyWith(color: colors.textPrimary),
        ),
        Text(
          context.l10n.solutionStillConfusedBody,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        SecondaryButton(
          label: context.l10n.teachingAskNumi,
          icon: Icons.forum_rounded,
          onPressed: onAsk,
        ),
      ],
    );
  }
}
