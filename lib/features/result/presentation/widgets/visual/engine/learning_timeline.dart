import 'package:flutter/material.dart';

import '../../../../../../core/extensions/context_extensions.dart';
import '../../../../../../core/localization/l10n_extension.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../core/theme/app_durations.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/theme/app_typography.dart';
import '../../../../domain/animation/animation_script.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the named learning-journey rail.
///
/// Instead of anonymous "Step 3 of 6" dots, this shows the pedagogical arc the
/// student is travelling: Understand → Apply → Simplify → Verify → Answer.
/// Completed phases fill emerald and check off; the current phase glows. The
/// labels are localized (falling back to the enum's English).
class LearningTimeline extends StatelessWidget {
  const LearningTimeline({
    super.key,
    required this.phases,
    required this.current,
  });

  /// The phases this script actually visits (in order).
  final List<LearningPhase> phases;
  final LearningPhase current;

  static String label(BuildContext context, LearningPhase p) {
    final l = context.l10n;
    return switch (p) {
      LearningPhase.understand => l.enginePhaseUnderstand,
      LearningPhase.chooseMethod => l.enginePhaseChooseMethod,
      LearningPhase.apply => l.enginePhaseApply,
      LearningPhase.simplify => l.enginePhaseSimplify,
      LearningPhase.verify => l.enginePhaseVerify,
      LearningPhase.answer => l.enginePhaseAnswer,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (phases.length < 2) return const SizedBox.shrink();
    final currentIndex = phases.indexOf(current);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < phases.length; i++) ...[
            _Node(
              phase: phases[i],
              label: label(context, phases[i]),
              done: i < currentIndex,
              active: i == currentIndex,
            ),
            if (i < phases.length - 1)
              _Connector(done: i < currentIndex),
          ],
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({
    required this.phase,
    required this.label,
    required this.done,
    required this.active,
  });

  final LearningPhase phase;
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final reached = done || active;
    return Semantics(
      label: label,
      selected: active,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppDurations.fast,
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: reached ? emerald : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: reached ? emerald : colors.border,
                  width: 2,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: emerald.withValues(alpha: 0.35),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                done ? Icons.check_rounded : phase.icon,
                size: 16,
                color: reached ? colors.onPrimaryContainer : colors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            SizedBox(
              width: 62,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: active ? emerald : colors.textMuted,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Container(
      width: 18,
      height: 2,
      margin: const EdgeInsets.only(bottom: 22),
      color: done ? emerald : context.colors.border,
    );
  }
}
