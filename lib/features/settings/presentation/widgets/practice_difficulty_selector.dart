import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../practice/domain/practice_difficulty.dart';
import '../../../subscription/application/subscription_controller.dart';
import '../../../subscription/domain/paywall_trigger.dart';

/// A stacked single-select over the 5 engine difficulty levels
/// ([PracticeDifficulty]), in the same card style as the other learning-pref
/// selectors. [PracticeDifficulty.hard] (A-Level) and [PracticeDifficulty.expert]
/// (university) are Pro — a free learner who taps them is routed to the paywall,
/// never silently downgraded.
class PracticeDifficultySelector extends ConsumerWidget {
  const PracticeDifficultySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final PracticeDifficulty selected;
  final ValueChanged<PracticeDifficulty> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);
    return Column(
      children: [
        for (final option in PracticeDifficulty.values) ...[
          if (option != PracticeDifficulty.values.first)
            const SizedBox(height: AppSpacing.md),
          _DifficultyCard(
            option: option,
            selected: option == selected,
            locked: option.isPro && !isPro,
            onTap: () {
              if (option.isPro && !isPro) {
                context.push(
                  AppRoutes.paywall,
                  extra: PaywallTrigger.adaptivePractice,
                );
                return;
              }
              onChanged(option);
            },
          ),
        ],
      ],
    );
  }
}

/// Per-level presentation: an icon + a one-line, grade-anchored blurb.
({IconData icon, String description}) _meta(PracticeDifficulty d) =>
    switch (d) {
      PracticeDifficulty.veryEasy => (
          icon: Icons.spa_rounded,
          description: 'Primary — small numbers, one step at a time',
        ),
      PracticeDifficulty.easy => (
          icon: Icons.eco_rounded,
          description: 'Upper primary — basic fractions & simple geometry',
        ),
      PracticeDifficulty.medium => (
          icon: Icons.auto_stories_rounded,
          description: 'Secondary / SPM / GCSE — multi-step problems',
        ),
      PracticeDifficulty.hard => (
          icon: Icons.bolt_rounded,
          description: 'A-Level — functions, logs, calculus, proofs',
        ),
      PracticeDifficulty.expert => (
          icon: Icons.workspace_premium_rounded,
          description: 'University — advanced, long derivations',
        ),
    };

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.option,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final PracticeDifficulty option;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final meta = _meta(option);
    // The emerald that stays legible as a foreground on the active surface —
    // the identity emerald is 2.97:1 and is brand art only.
    final accent =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}. ${meta.description}${locked ? '. Pro' : ''}',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        elevated: !selected,
        color: selected ? colors.primaryContainer : colors.surface,
        border: Border.all(
          color: selected ? accent : colors.border,
          width: selected ? 2 : 1.5,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.14)
                    : colors.surfaceMuted,
                borderRadius: AppRadius.smRadius,
              ),
              child: Icon(
                meta.icon,
                size: 23,
                color: selected ? accent : colors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: AppTypography.title.copyWith(
                      color: selected
                          ? colors.onPrimaryContainer
                          : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    meta.description,
                    style: AppTypography.bodySmall
                        .copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (locked)
              Icon(Icons.lock_rounded, size: 22, color: colors.textMuted)
            else
              _SelectionDot(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.fast,
      curve: AppCurves.standard,
      width: 26,
      height: 26,
      // A filled control carrying a white check — the interactive emerald, so
      // the check clears AA (4.78:1) in both themes.
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryAction : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primaryAction : context.colors.textMuted,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: AppColors.white)
          : null,
    );
  }
}
