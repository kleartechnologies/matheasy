import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import '../tabs/explain_tab.dart';
import 'math_text.dart';
import 'result_graph.dart';

/// V3 · the "Learn more" sheet — everything the solving flow deliberately does
/// not show.
///
/// The idea, what it asks, the plan, the glossary, the full step list, method
/// comparison, the three explanation voices, every common mistake, the takeaway
/// and the graph all live here, each one **collapsed**. Nothing in this sheet can
/// interrupt a student who just wants the answer and the walkthrough — they have
/// to ask for it, one row at a time.
class LearnMoreSheet extends StatelessWidget {
  const LearnMoreSheet({
    super.key,
    required this.result,
    required this.onUseMethod,
    required this.onAskMatheasy,
  });

  final ResultData result;

  /// Switches the step player to a different method. The sheet closes first —
  /// the learner is sent back to the lesson, not left reading about it.
  final ValueChanged<int> onUseMethod;

  final VoidCallback onAskMatheasy;

  static Future<void> show(
    BuildContext context, {
    required ResultData result,
    required ValueChanged<int> onUseMethod,
    required VoidCallback onAskMatheasy,
  }) {
    return AppBottomSheet.show<void>(
      context,
      title: context.l10n.learnMoreTitle,
      showCloseButton: true,
      child: LearnMoreSheet(
        result: result,
        onUseMethod: onUseMethod,
        onAskMatheasy: onAskMatheasy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final teaching = result.teaching;
    final sections = <Widget>[];

    // --- the idea ---------------------------------------------------------
    final concept = teaching?.concept;
    if (concept != null && concept.body.trim().isNotEmpty) {
      sections.add(_Section(
        title: _titleCase(l10n.teachingTheIdea),
        icon: Icons.psychology_alt_rounded,
        child: _Paragraph(concept.body.trim()),
      ));
    }

    // --- what it asks + the plan -----------------------------------------
    final overview = teaching?.overview;
    if (overview != null && !overview.isEmpty) {
      sections.add(_Section(
        title: l10n.teachingWhatItAsks,
        icon: Icons.help_outline_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (overview.asked.trim().isNotEmpty)
              _Paragraph(overview.asked.trim()),
            if (overview.goal.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _Paragraph(overview.goal.trim()),
            ],
            for (final given in overview.givens.where((g) => g.trim().isNotEmpty))
              _BulletRow(given.trim()),
          ],
        ),
      ));
    }

    final plan = teaching?.decompositionPlan
        ?.where((p) => p.trim().isNotEmpty)
        .toList();
    if (plan != null && plan.isNotEmpty) {
      sections.add(_Section(
        title: l10n.teachingThePlan,
        icon: Icons.checklist_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < plan.length; i++)
              _NumberedRow(index: i + 1, text: plan[i].trim()),
          ],
        ),
      ));
    }

    // --- glossary ---------------------------------------------------------
    final terms = concept?.definedTerms
        .where((t) => t.term.trim().isNotEmpty && t.plain.trim().isNotEmpty)
        .toList();
    if (terms != null && terms.isNotEmpty) {
      sections.add(_Section(
        title: l10n.learnMoreGlossary,
        icon: Icons.menu_book_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in terms)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: RichText(
                  text: TextSpan(
                    style: AppTypography.bodySmall
                        .copyWith(color: colors.textSecondary, height: 1.45),
                    children: [
                      TextSpan(
                        text: '${t.term.trim()} — ',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: t.plain.trim()),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ));
    }

    // --- every step at once ----------------------------------------------
    // The player shows one step; some learners want the whole derivation on one
    // screen to scan or copy. Both are legitimate — this is where that lives.
    final steps = result.steps;
    if (steps.isNotEmpty) {
      sections.add(_Section(
        title: l10n.learnMoreAllSteps,
        icon: Icons.format_list_numbered_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}. ${steps[i].title}',
                      style: AppTypography.caption.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    AdaptiveMath(
                      steps[i].resultLatex,
                      minFontSize: 15,
                      maxFontSize: 20,
                      style:
                          AppTypography.bodyMedium.copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ));
    }

    // --- compare methods --------------------------------------------------
    if (result.methods.length > 1) {
      sections.add(_Section(
        title: l10n.learnMoreCompareMethods,
        icon: Icons.alt_route_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < result.methods.length; i++)
              _MethodRow(
                method: result.methods[i],
                onUse: () {
                  Navigator.of(context).pop();
                  onUseMethod(i);
                },
              ),
          ],
        ),
      ));
    }

    // --- three voices -----------------------------------------------------
    if (result.explanations.isNotEmpty) {
      sections.add(_Section(
        title: l10n.learnMoreExplanations,
        icon: Icons.record_voice_over_rounded,
        child: ExplainTab(
          explanations: result.explanations,
          onAskMatheasy: onAskMatheasy,
        ),
      ));
    }

    // --- every mistake, not just the one in the summary -------------------
    final mistakes = teaching?.commonMistakes
        .where((m) => m.mistake.trim().isNotEmpty)
        .toList();
    if (mistakes != null && mistakes.isNotEmpty) {
      sections.add(_Section(
        title: _titleCase(l10n.teachingWatchOutFor),
        icon: Icons.warning_amber_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in mistakes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.mistake.trim(),
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    if (m.whyTempting.trim().isNotEmpty)
                      _Paragraph(m.whyTempting.trim()),
                    if (m.fix.trim().isNotEmpty) _Paragraph(m.fix.trim()),
                  ],
                ),
              ),
          ],
        ),
      ));
    }

    // --- the takeaway -----------------------------------------------------
    final takeaway = teaching?.keyTakeaway;
    if (takeaway != null && takeaway.headline.trim().isNotEmpty) {
      sections.add(_Section(
        title: _titleCase(l10n.teachingRememberThis),
        icon: Icons.lightbulb_outline_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              takeaway.headline.trim(),
              style: AppTypography.bodyMedium.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            if ((takeaway.detail ?? '').trim().isNotEmpty)
              _Paragraph(takeaway.detail!.trim()),
          ],
        ),
      ));
    }

    final graph = result.graph;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sections.isEmpty && graph == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                l10n.learnMoreNothing,
                style: AppTypography.bodySmall
                    .copyWith(color: colors.textSecondary),
              ),
            ),
          ...sections,
          // The graph brings its own collapsed expander, so it sits alongside
          // the accordion rather than nested inside one.
          if (graph != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: ResultGraphSection(graph: graph),
            ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  /// The teaching layer ships some labels in caps for the old badge styling.
  /// In this sheet they are row titles, so soften them back to sentence case.
  static String _titleCase(String raw) {
    if (raw.isEmpty) return raw;
    if (raw != raw.toUpperCase()) return raw;
    final lower = raw.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }
}

// ---------------------------------------------------------------------------
// One collapsed row
// ---------------------------------------------------------------------------

class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: widget.title,
          excludeSemantics: true,
          child: Pressable(
            onTap: () => setState(() => _open = !_open),
            borderRadius: AppRadius.smRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Icon(widget.icon, size: 18, color: colors.textMuted),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: AppDurations.fast,
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Built only when open — a collapsed section must cost nothing, and
        // must not be reachable by a screen reader walking the sheet.
        AnimatedSize(
          duration: AppDurations.fast,
          curve: AppCurves.standard,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.md,
                    left: AppSpacing.xxl,
                  ),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
        Divider(height: 1, color: colors.divider),
      ],
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: Text(
          text,
          style: AppTypography.bodySmall
              .copyWith(color: context.colors.textSecondary, height: 1.5),
        ),
      );
}

class _BulletRow extends StatelessWidget {
  const _BulletRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 4,
              height: 4,
              decoration:
                  BoxDecoration(color: colors.textMuted, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall
                  .copyWith(color: colors.textSecondary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberedRow extends StatelessWidget {
  const _NumberedRow({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$index',
            style: AppTypography.caption
                .copyWith(color: emerald, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall
                  .copyWith(color: colors.textSecondary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// One alternative method: what it is, when it's better, and a way to actually
/// switch the lesson over to it.
class _MethodRow extends StatelessWidget {
  const _MethodRow({required this.method, required this.onUse});

  final MethodSolution method;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            method.name,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (method.whenToUse.trim().isNotEmpty)
            Text(
              method.whenToUse.trim(),
              style: AppTypography.caption
                  .copyWith(color: colors.textSecondary, height: 1.4),
            ),
          Semantics(
            button: true,
            label: context.l10n.learnMoreUseThisMethod,
            excludeSemantics: true,
            child: Pressable(
              onTap: onUse,
              borderRadius: AppRadius.smRadius,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.learnMoreUseThisMethod,
                      style: AppTypography.caption.copyWith(
                        color: emerald,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: emerald),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
