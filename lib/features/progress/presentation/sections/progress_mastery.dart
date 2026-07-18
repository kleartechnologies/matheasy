import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../practice/domain/mastery.dart';
import '../../../practice/domain/practice_dashboard.dart' show CategoryView;
import '../../../practice/presentation/widgets/practice_chips.dart';

/// "Mastery overview" — every topic with its mastery level and progress.
///
/// Topics carry no per-topic colour; the glyph separates them, and reusing
/// [PracticeTopicIcon] keeps this list identical to the practice surfaces it
/// mirrors.
class ProgressMastery extends StatelessWidget {
  const ProgressMastery({super.key, required this.mastery});

  final List<CategoryView> mastery;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: context.l10n.progressMasteryOverview),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              for (var i = 0; i < mastery.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                    color: context.colors.divider,
                  ),
                _MasteryRow(view: mastery[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MasteryRow extends StatelessWidget {
  const _MasteryRow({required this.view});

  final CategoryView view;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final topic = view.topic;

    return Semantics(
      label: context.l10n.progressTopicMastery(topic.label, view.level.label),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              PracticeTopicIcon(topic: topic),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            topic.label,
                            style: AppTypography.title.copyWith(
                              color: colors.textPrimary,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        _LevelChip(level: view.level),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    XPProgressBar(value: view.progress, height: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level});

  final MasteryLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mastered = level == MasteryLevel.mastered;
    // Mastered earns the brand emerald; every level below it stays neutral, so
    // "mastered" is the only thing on the list that catches the eye.
    final background = mastered ? colors.primaryContainer : colors.surfaceMuted;
    final foreground =
        mastered ? colors.onPrimaryContainer : colors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mastered) ...[
            Icon(Icons.workspace_premium_rounded, size: 12, color: foreground),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            level.label,
            style: AppTypography.label.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
