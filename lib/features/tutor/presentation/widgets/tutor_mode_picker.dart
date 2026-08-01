import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/tutor_models.dart';
import '../tutor_copy.dart';

/// "How would you like to learn this?" — the five-way choice that opens a
/// problem-aware conversation (spec Part 20).
///
/// This is the single most important control in the tutor: the mode the student
/// picks is a contract on Numi's behaviour, not a tone, so each row states what
/// the mode will actually do before they commit to it.
class TutorModePicker extends StatelessWidget {
  const TutorModePicker({
    super.key,
    required this.onSelected,
    this.selected,
  });

  /// Fired with the chosen mode and its localized label — the label is posted as
  /// the student's own turn, so the choice reads as part of the conversation.
  final void Function(TutorMode mode, String label) onSelected;

  /// The active mode, when the picker is being used to *change* modes.
  final TutorMode? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.tutorModePrompt,
          style: AppTypography.title.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final mode in TutorMode.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ModeTile(
              mode: mode,
              isSelected: mode == selected,
              onTap: () => onSelected(mode, TutorCopy.modeLabel(context, mode)),
            ),
          ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  final TutorMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = TutorCopy.modeLabel(context, mode);
    final detail = TutorCopy.modeDetail(context, mode);
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label. $detail',
      child: ExcludeSemantics(
        child: Material(
          color: isSelected ? colors.primaryContainer : colors.surfaceMuted,
          borderRadius: AppRadius.mdRadius,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.mdRadius,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                borderRadius: AppRadius.mdRadius,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryAction
                      : colors.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Text(mode.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: AppTypography.title.copyWith(
                            color: isSelected
                                ? colors.onPrimaryContainer
                                : colors.textPrimary,
                          ),
                        ),
                        Text(
                          detail,
                          style: AppTypography.caption.copyWith(
                            color: isSelected
                                ? colors.onPrimaryContainer
                                : colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: colors.onPrimaryContainer,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the mode picker as a bottom sheet — the mid-conversation switcher.
///
/// Returns the chosen mode, or null if the student dismissed the sheet.
Future<TutorMode?> showTutorModeSheet(
  BuildContext context, {
  required TutorMode current,
}) {
  return showModalBottomSheet<TutorMode>(
    context: context,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.lg,
        ),
        child: TutorModePicker(
          selected: current,
          onSelected: (mode, _) => Navigator.of(sheetContext).pop(mode),
        ),
      ),
    ),
  );
}
