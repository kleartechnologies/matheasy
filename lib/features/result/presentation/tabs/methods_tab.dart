import 'package:flutter/material.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import '../widgets/result_empty.dart';

/// Tab 3 — multiple solving methods, with the recommended one badged. A major
/// differentiator: not just an answer, but *how to think about it*.
class MethodsTab extends StatelessWidget {
  const MethodsTab({super.key, required this.methods});

  final List<MethodSolution> methods;

  @override
  Widget build(BuildContext context) {
    if (methods.isEmpty) {
      return ResultEmpty(
        message: context.l10n.methodsEmptyMessage,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatheasyBubble(
          text: context.l10n.methodsIntro,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < methods.length; i++)
          AppTransitions.slideUp(
            delay: Duration(milliseconds: (i * 60).clamp(0, 300)),
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _MethodCard(method: methods[i]),
            ),
          ),
      ],
    );
  }
}

class _MethodCard extends StatefulWidget {
  const _MethodCard({required this.method});

  final MethodSolution method;

  @override
  State<_MethodCard> createState() => _MethodCardState();
}

class _MethodCardState extends State<_MethodCard> {
  late bool _expanded = widget.method.recommended;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final method = widget.method;
    // Emerald content on a card — the ring and the affordance both need the
    // per-theme legible tone, not the 2.97:1 logo tile.
    final emeraldLabel =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return AppCard(
      onTap: () => setState(() => _expanded = !_expanded),
      border: method.recommended
          ? Border.all(color: emeraldLabel, width: 1.5)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  method.name,
                  style:
                      AppTypography.headingSmall.copyWith(color: colors.textPrimary),
                ),
              ),
              if (method.recommended) const _RecommendedBadge(),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            method.subtitle,
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            method.description,
            style: AppTypography.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          AnimatedCrossFade(
            duration: AppDurations.medium,
            sizeCurve: AppCurves.standard,
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _Details(method: method),
            secondChild: const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                _expanded
                    ? context.l10n.methodsHideDetails
                    : context.l10n.methodsSeeHowItWorks,
                style: AppTypography.caption.copyWith(color: emeraldLabel),
              ),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: AppDurations.fast,
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: emeraldLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.method});

  final MethodSolution method;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.methodsStepsLabel,
            style: AppTypography.label.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final step in method.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.chevron_right_rounded,
                      size: 20,
                      color: context.isDark
                          ? AppColors.primaryLight
                          : AppColors.primaryDark),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      step,
                      style: AppTypography.bodyMedium
                          .copyWith(color: colors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.methodsGoodFor,
            style: AppTypography.label.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final advantage in method.advantages)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.successContainer,
                    borderRadius: AppRadius.smRadius,
                  ),
                  child: Text(
                    advantage,
                    style: AppTypography.caption
                        .copyWith(color: colors.onSuccessContainer),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: AppRadius.mdRadius,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tips_and_updates_rounded,
                    size: 18, color: colors.onPrimaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'When to use: ${method.whenToUse}',
                    style: AppTypography.bodySmall
                        .copyWith(color: colors.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: AppRadius.smRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: AppColors.onGold),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            context.l10n.methodsRecommended,
            style: AppTypography.label.copyWith(
              color: AppColors.onGold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
