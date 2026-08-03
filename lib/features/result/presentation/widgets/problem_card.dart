import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../scan/presentation/widgets/confidence_badge.dart';
import '../../domain/result_models.dart';
import 'difficulty_pill.dart';
import 'problem_statement.dart';

/// V3 · SECTION 1 — the problem, and nothing else.
///
/// This card answers exactly one question: *what did Matheasy read?* The student
/// has to be able to check that against their page at a glance, so it is laid
/// out like the worksheet — the instruction as prose, the maths typeset beneath
/// it — and never as the LaTeX that carries it internally.
///
/// The metadata (category · difficulty · how sure the read was) recedes into one
/// quiet line under a hairline, with the two ways to repair a misread: correct
/// it by hand, or scan it again.
class ProblemCard extends StatelessWidget {
  const ProblemCard({
    super.key,
    required this.result,
    required this.onRescan,
    this.onEdit,
  });

  final ResultData result;
  final VoidCallback onRescan;

  /// Opens the math editor pre-filled with what we read, so a misread character
  /// is a five-second fix rather than a re-scan. Omitted when null.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The problem — the hero of this card. Sized to its content so a short
          // problem gets the full 38px and a long one shrinks rather than
          // clipping or scrolling sideways.
          ProblemStatement(latex: result.questionLatex),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, thickness: 1, color: colors.divider),
          const SizedBox(height: AppSpacing.xs),
          _MetadataRow(result: result, onRescan: onRescan, onEdit: onEdit),
        ],
      ),
    );
  }
}

/// Category · difficulty · confidence, then the repair actions. Deliberately
/// caption-weight — it must never compete with the equation above it.
class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.result,
    required this.onRescan,
    required this.onEdit,
  });

  final ResultData result;
  final VoidCallback onRescan;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final confidence = result.equation.readConfidence;
    return Semantics(
      container: true,
      label: '${result.type.label}, ${result.difficulty.label}, '
          '${confidenceLabel(context, confidence)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  // Wrap, not Row: at a narrow width or a large text scale the
                  // chips drop to another line instead of being squeezed to an
                  // ellipsis.
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        result.type.label,
                        style: AppTypography.caption
                            .copyWith(color: colors.textSecondary),
                      ),
                      DifficultyPill(result.difficulty),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (onEdit != null)
                _RepairAction(
                  icon: Icons.edit_rounded,
                  label: l10n.actionEdit,
                  semanticLabel: l10n.resultEditProblem,
                  onTap: onEdit!,
                ),
              _RepairAction(
                icon: Icons.crop_free_rounded,
                label: l10n.actionRescan,
                semanticLabel: l10n.resultRescanProblem,
                onTap: onRescan,
                iconOnly: true,
              ),
            ],
          ),
          // The read's trustworthiness gets the full width to itself — it is
          // the one line here a student may need to act on.
          ExcludeSemantics(child: ConfidenceBadge(confidence)),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

/// A quiet action on the metadata line — one of the two ways to correct a
/// misread. Borderless, so the card stays a reading surface; the padding keeps
/// the tap target comfortable anyway.
class _RepairAction extends StatelessWidget {
  const _RepairAction({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.iconOnly = false,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smRadius,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? AppSpacing.sm : AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colors.textMuted),
              if (!iconOnly) ...[
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

