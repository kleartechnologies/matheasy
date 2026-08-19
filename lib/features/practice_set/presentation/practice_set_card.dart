import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/pressable.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../history/domain/history_entry.dart';
import '../../practice/domain/practice_session.dart';
import '../../practice/domain/practice_topic.dart';
import '../../result/domain/result_models.dart';
import '../../result/presentation/widgets/math_text.dart';
import '../../scan/presentation/manual_input_screen.dart';
import '../application/practice_set_controller.dart';
import '../domain/practice_set.dart';

/// THE shared practice-set component (spec: one component, every surface).
///
/// Renders the reusable easier/similar/harder(/challenge) journey generated
/// from a solved problem, with live completion state, the unlock stage (mixed
/// review + challenge), the mastered celebration, and the "new set" re-roll.
/// Attempting an item re-enters the real solve pipeline via the editor — the
/// same golden-rule path every problem takes.
///
/// Two densities:
///  * full (Solution tab, History sheet) — every rung, progress, unlocks;
///  * [PracticeSetCard.compact] (Final Answer strip, Visual tab, Practice tab)
///    — one row driving the single next action.
class PracticeSetCard extends ConsumerStatefulWidget {
  const PracticeSetCard({super.key, required this.set}) : compact = false;

  const PracticeSetCard.compact({super.key, required this.set})
      : compact = true;

  final PracticeSet set;
  final bool compact;

  @override
  ConsumerState<PracticeSetCard> createState() => _PracticeSetCardState();
}

class _PracticeSetCardState extends ConsumerState<PracticeSetCard> {
  bool _rolling = false;

  PracticeSet get set => _live ?? widget.set;

  /// Prefer the controller's live copy so completions made elsewhere (another
  /// tab, Numi, history) re-render this card; fall back to the widget's copy
  /// (e.g. a freshly-arrived ladder the controller hasn't stored — guests).
  PracticeSet? get _live =>
      ref.watch(practiceSetForProvider(widget.set.sourceKey));

  // ---- Actions (identical on every surface) ----

  void _attempt(PracticeSetItem item) => context.push(
        AppRoutes.manualInput,
        extra: ManualInputArgs(initialLatex: item.latex),
      );

  void _startMixedReview() => context.push(
        AppRoutes.practiceSession,
        extra: PracticeRequest(
          topic: PracticeTopic.fromResultType(set.sourceType),
          title: context.l10n.practiceSetMixedReview,
          adaptive: true, // sets are Pro-only, like the ladder they come from
          practiceSetSourceKey: set.sourceKey,
        ),
      );

  Future<void> _requestNewSet() async {
    if (_rolling) return;
    setState(() => _rolling = true);
    final ok = await ref
        .read(practiceSetControllerProvider.notifier)
        .requestNewSet(set.sourceKey);
    if (!mounted) return;
    setState(() => _rolling = false);
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text(context.l10n.practiceSetNewSetFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.compact ? _buildCompact(context) : _buildFull(context);
  }

  // ---- Full ----

  Widget _buildFull(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final challenge = set.challenge;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fitness_center_rounded,
                  size: 16, color: AppColors.primaryAction),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.teachingYourTurn,
                  style:
                      AppTypography.label.copyWith(color: _emerald(context)),
                ),
              ),
              Text(
                l10n.practiceSetProgress(set.completedCount, set.totalCount),
                style:
                    AppTypography.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            set.completedCount == 0
                ? l10n.teachingPracticeLadderIntro
                : l10n.practiceSetContinueSubtitle,
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadius.pillRadius,
            child: LinearProgressIndicator(
              value: set.totalCount == 0
                  ? 0
                  : set.completedCount / set.totalCount,
              minHeight: 6,
              backgroundColor: colors.surfaceMuted,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primaryAction),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final item in set.items) ...[
            _ItemRow(
              item: item,
              onTap: item.completed ? null : _attempt,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (challenge != null)
            _ItemRow(
              item: challenge,
              locked: !set.challengeUnlocked,
              onTap: set.challengeUnlocked && !challenge.completed
                  ? _attempt
                  : null,
            ),
          if (challenge != null && !set.challengeUnlocked) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.practiceSetChallengeLocked,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ],
          // The unlock stage: mixed review appears once the core three are done.
          if (set.coreComplete && !set.mastered) ...[
            const SizedBox(height: AppSpacing.md),
            _MixedReviewRow(
              done: set.mixedReviewComplete,
              onStart: set.mixedReviewComplete ? null : _startMixedReview,
            ),
          ],
          if (set.mastered) ...[
            const SizedBox(height: AppSpacing.md),
            const _MasteredBanner(),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: _rolling ? null : _requestNewSet,
              icon: _rolling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: Text(l10n.practiceSetNewSet),
              style: TextButton.styleFrom(
                foregroundColor: _emerald(context),
                textStyle: AppTypography.caption
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Compact ----

  Widget _buildCompact(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final next = set.nextItem;
    final mixedReviewPending = set.coreComplete && !set.mixedReviewComplete;

    // Nothing left to do → nothing to advertise (the full card still shows the
    // mastered state where it lives).
    if (next == null && !mixedReviewPending) return const SizedBox.shrink();

    final String title;
    final Widget body;
    final VoidCallback onTap;
    if (next != null) {
      title = l10n.practiceSetContinueTitle;
      body = MathText(
        next.latex,
        style: AppTypography.bodyMedium.copyWith(color: colors.textPrimary),
      );
      onTap = () => _attempt(next);
    } else {
      title = l10n.practiceSetMixedReview;
      body = Text(
        l10n.practiceSetMixedReviewSubtitle,
        style: AppTypography.bodySmall.copyWith(color: colors.textSecondary),
      );
      onTap = _startMixedReview;
    }

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.fitness_center_rounded,
                        size: 13, color: _emerald(context)),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        title,
                        style: AppTypography.caption.copyWith(
                          color: _emerald(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (next != null) _RungChip(rung: next.rung),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                body,
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.practiceSetProgress(set.completedCount, set.totalCount),
                  style:
                      AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.arrow_forward_rounded,
              size: 18, color: _emerald(context)),
        ],
      ),
    );
  }
}

/// Resolves the practice set for a solved problem and renders the card —
/// the drop-in for surfaces that hold a [ResultData]. Falls back to an
/// ephemeral set built from the teaching ladder when the controller has none
/// (e.g. the ladder just streamed in), and to nothing when there is no ladder.
class PracticeSetSection extends ConsumerWidget {
  const PracticeSetSection({
    super.key,
    required this.result,
    this.compact = false,
    this.margin,
  });

  final ResultData result;
  final bool compact;

  /// Outer spacing applied ONLY when the section has something to show — so a
  /// surface can slot it between siblings without a stray gap when hidden.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = historyCacheKey(result.equation.latex);
    var set = ref.watch(practiceSetForProvider(key));
    if (set == null) {
      final ladder = result.teaching?.practiceLadder;
      if (ladder == null || !result.verified) return const SizedBox.shrink();
      set = PracticeSet.fromLadder(
        sourceKey: key,
        sourceLatex: result.equation.latex,
        sourceType: result.type,
        ladder: ladder,
        nowMillis: 0,
      );
    }
    if (compact) {
      // The compact strip advertises the next action; when there is none it
      // disappears entirely (margin included).
      final next = set.nextItem;
      final mixedReviewPending = set.coreComplete && !set.mixedReviewComplete;
      if (next == null && !mixedReviewPending) return const SizedBox.shrink();
    }
    final card = compact
        ? PracticeSetCard.compact(set: set)
        : PracticeSetCard(set: set);
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

/// The emerald that stays legible as a label, per theme (never
/// `AppColors.primary`, the 2.97:1 logo tone — CLAUDE.md).
Color _emerald(BuildContext context) =>
    context.isDark ? AppColors.primaryLight : AppColors.primaryDark;

/// One rung row: chip + problem + state (arrow / check / lock).
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, this.onTap, this.locked = false});

  final PracticeSetItem item;
  final ValueChanged<PracticeSetItem>? onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 44), // a11y tap target
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.smRadius,
      ),
      child: Row(
        children: [
          _RungChip(rung: item.rung, muted: locked),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: locked
                // A locked challenge shows no problem text — the reveal is part
                // of the reward for finishing the core three.
                ? Text(
                    context.l10n.practiceSetRungChallenge,
                    style: AppTypography.bodyMedium
                        .copyWith(color: colors.textMuted),
                  )
                : MathText(
                    item.latex,
                    style: AppTypography.bodyMedium.copyWith(
                      color: item.completed
                          ? colors.textSecondary
                          : colors.textPrimary,
                    ),
                  ),
          ),
          if (locked)
            Icon(Icons.lock_rounded, size: 16, color: colors.textMuted)
          else if (item.completed)
            const Icon(Icons.check_circle_rounded,
                size: 18, color: AppColors.primaryAction)
          else if (onTap != null)
            Icon(Icons.arrow_forward_rounded,
                size: 16, color: _emerald(context)),
        ],
      ),
    );
    if (onTap == null || locked) return row;
    return Semantics(
      button: true,
      label: context.l10n.teachingPracticeQuestionLabel(_label(context)),
      excludeSemantics: true,
      child: Pressable(
        onTap: () => onTap!(item),
        borderRadius: AppRadius.smRadius,
        child: row,
      ),
    );
  }

  String _label(BuildContext context) => switch (item.rung) {
        PracticeSetRung.easier => context.l10n.teachingRungEasier,
        PracticeSetRung.similar => context.l10n.teachingRungSimilar,
        PracticeSetRung.harder => context.l10n.teachingRungHarder,
        PracticeSetRung.challenge => context.l10n.practiceSetRungChallenge,
      };
}

/// The rung pill — theme-tuned container/on-container pairs (AA both themes),
/// mirroring the retired teaching-card rung row; challenge rides the streak
/// (flame) pair.
class _RungChip extends StatelessWidget {
  const _RungChip({required this.rung, this.muted = false});

  final PracticeSetRung rung;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (label, fill, ink) = switch (rung) {
      PracticeSetRung.easier => (
          context.l10n.teachingRungEasier,
          colors.successContainer,
          colors.onSuccessContainer
        ),
      PracticeSetRung.similar => (
          context.l10n.teachingRungSimilar,
          colors.infoContainer,
          colors.onInfoContainer
        ),
      PracticeSetRung.harder => (
          context.l10n.teachingRungHarder,
          colors.warningContainer,
          colors.onWarningContainer
        ),
      PracticeSetRung.challenge => (
          context.l10n.practiceSetRungChallenge,
          colors.streakContainer,
          colors.onStreakContainer
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: muted ? colors.surfaceMuted : fill,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: muted ? colors.textMuted : ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MixedReviewRow extends StatelessWidget {
  const _MixedReviewRow({required this.done, this.onStart});

  final bool done;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    if (done) {
      return Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 18, color: AppColors.primaryAction),
          const SizedBox(width: AppSpacing.sm),
          Text(
            l10n.practiceSetMixedReviewDone,
            style: AppTypography.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ],
      );
    }
    return SecondaryButton(
      label: l10n.practiceSetMixedReview,
      icon: Icons.shuffle_rounded,
      onPressed: onStart,
    );
  }
}

class _MasteredBanner extends StatelessWidget {
  const _MasteredBanner();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.xpContainer,
        borderRadius: AppRadius.smRadius,
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_rounded,
              size: 20, color: colors.onXpContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.practiceSetMastered,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.onXpContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  l10n.practiceSetMasteredDetail(
                      PracticeSetController.masteredBonusXp),
                  style: AppTypography.caption
                      .copyWith(color: colors.onXpContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
