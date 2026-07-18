import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/layout/section_header.dart';
import '../../../subscription/application/subscription_controller.dart';
import '../../../subscription/domain/paywall_trigger.dart';
import '../../domain/practice_difficulty.dart';

/// Holds the user's chosen practice difficulty — their preference, held CONSTANT
/// for every session until they change it. Defaults to [PracticeDifficulty.medium].
class SelectedPracticeDifficulty extends Notifier<PracticeDifficulty> {
  @override
  PracticeDifficulty build() => PracticeDifficulty.medium;

  void select(PracticeDifficulty difficulty) => state = difficulty;
}

/// The authority for question generation: choosing a level always produces that
/// level. Adaptive only reorders topics; it never overrides this.
final selectedPracticeDifficultyProvider =
    NotifierProvider<SelectedPracticeDifficulty, PracticeDifficulty>(
  SelectedPracticeDifficulty.new,
);

/// The 5-level difficulty selector for the Practice dashboard. [PracticeDifficulty.hard]
/// (A-Level) and [PracticeDifficulty.expert] (university) are Pro — a free
/// learner who taps them is routed to the paywall, never silently downgraded.
class PracticeDifficultyPicker extends ConsumerWidget {
  const PracticeDifficultyPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedPracticeDifficultyProvider);
    final isPro = ref.watch(isProProvider);
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Difficulty'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final d in PracticeDifficulty.values)
              _DifficultyChip(
                difficulty: d,
                selected: d == selected,
                locked: d.isPro && !isPro,
                onTap: () {
                  if (d.isPro && !isPro) {
                    context.push(
                      AppRoutes.paywall,
                      extra: PaywallTrigger.adaptivePractice,
                    );
                    return;
                  }
                  ref
                      .read(selectedPracticeDifficultyProvider.notifier)
                      .select(d);
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          selected.spec.gradeLabel,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({
    required this.difficulty,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final PracticeDifficulty difficulty;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = selected ? AppColors.primaryAction : colors.surfaceMuted;
    final fg = selected ? AppColors.white : colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: '${difficulty.label}${locked ? ', Pro' : ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.smRadius,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked) ...[
                Icon(Icons.lock_rounded, size: 13, color: fg),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                difficulty.label,
                style: AppTypography.label.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
