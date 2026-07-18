import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/tutor_models.dart';

/// A horizontally-scrolling rail of suggested starter prompts. Tapping a card
/// opens the chat seeded with that prompt.
class TutorSuggestedPrompts extends StatelessWidget {
  const TutorSuggestedPrompts({
    super.key,
    required this.prompts,
    required this.onSelected,
  });

  final List<TutorPrompt> prompts;
  final ValueChanged<TutorPrompt> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: context.l10n.tutorTryAsking),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            clipBehavior: Clip.none,
            itemCount: prompts.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) =>
                _PromptCard(prompt: prompts[index], onTap: onSelected),
          ),
        ),
      ],
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt, required this.onTap});

  final TutorPrompt prompt;
  final ValueChanged<TutorPrompt> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 150,
      child: AppCard(
        onTap: () => onTap(prompt),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: prompt.color.withValues(alpha: 0.14),
                borderRadius: AppRadius.smRadius,
              ),
              child: Icon(prompt.icon, size: 22, color: prompt.color),
            ),
            Text(
              prompt.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.title.copyWith(
                color: colors.textPrimary,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
