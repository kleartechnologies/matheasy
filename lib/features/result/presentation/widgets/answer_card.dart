import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/result_models.dart';
import 'math_text.dart';

/// V3 · SECTION 2 — the answer, and nothing else.
///
/// No educational text, no walkthrough CTA, no verification prose: just the
/// verified final answer at full size, with the three utilities a student
/// actually reaches for (copy · share · save). Everything that *teaches* starts
/// below, behind "Start Learning".
class AnswerCard extends StatelessWidget {
  const AnswerCard({
    super.key,
    required this.result,
    required this.saved,
    required this.onToggleSave,
    required this.onShare,
    required this.onCopied,
  });

  final ResultData result;
  final bool saved;
  final VoidCallback onToggleSave;
  final VoidCallback onShare;

  /// Fired after the answer lands on the clipboard (the screen toasts).
  final VoidCallback onCopied;

  /// The answer as plain text — what belongs on a clipboard. Falls back to the
  /// LaTeX when the server sent no plain form.
  String get _copyText =>
      result.answerPlain.isNotEmpty ? result.answerPlain : result.answerLatex;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.successContainer,
        borderRadius: AppRadius.xlRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.l10n.resultFinalAnswer,
                style:
                    AppTypography.label.copyWith(color: colors.onSuccessContainer),
              ),
              const Spacer(),
              Icon(Icons.verified_rounded,
                  size: 16, color: colors.onSuccessContainer),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Adaptive so it stays readable without scrolling: a short answer fills
          // at 56px, a long one settles near 34px — never a sideways scroll.
          AdaptiveMath(
            result.answerLatex,
            minFontSize: 34,
            maxFontSize: 56,
            style: AppTypography.displayLarge.copyWith(
              color: colors.onSuccessContainer,
              height: 1.05,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: colors.onSuccessContainer.withValues(alpha: 0.14)),
          Row(
            children: [
              _AnswerAction(
                icon: Icons.copy_rounded,
                label: context.l10n.resultCopy,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: _copyText));
                  onCopied();
                },
              ),
              _AnswerAction(
                icon: Icons.ios_share_rounded,
                label: context.l10n.resultShare,
                onTap: onShare,
              ),
              _AnswerAction(
                icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                label: saved
                    ? context.l10n.resultSavedShort
                    : context.l10n.resultSave,
                semanticLabel: saved
                    ? context.l10n.resultRemoveFromSaved
                    : context.l10n.resultSaveSolution,
                onTap: onToggleSave,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One of the answer card's three utilities. Text-and-icon on the success
/// container (never a filled control) so the answer itself stays the only thing
/// with real visual weight in this card.
class _AnswerAction extends StatelessWidget {
  const _AnswerAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.onSuccessContainer;
    return Expanded(
      child: Semantics(
        button: true,
        label: semanticLabel ?? label,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          borderRadius: AppRadius.smRadius,
          child: Container(
            // ≥44dp tap target.
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: ink),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
