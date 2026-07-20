import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Themed modal bottom sheet with a drag handle, optional title + close button
/// and safe-area aware content. Use [AppBottomSheet.show] to present any content.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.showCloseButton = false,
  });

  final Widget child;
  final String? title;

  /// Shows a tappable close (✕) in the header — an explicit dismiss affordance
  /// for content where the drag handle alone isn't obvious (e.g. a long list).
  final bool showCloseButton;

  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    String? title,
    bool showCloseButton = false,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (_) => AppBottomSheet(
        title: title,
        showCloseButton: showCloseButton,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasHeader = title != null || showCloseButton;
    return ConstrainedBox(
      // Cap the height so a tall (scroll-controlled) sheet reads as a card with
      // a dimmed barrier above — tapping it dismisses — rather than a full white
      // screen. Short sheets shrink-wrap well under this.
      constraints: BoxConstraints(maxHeight: context.screenHeight * 0.9),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadius.sheetRadius,
        ),
        padding: EdgeInsets.only(bottom: context.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: AppRadius.pillRadius,
                    ),
                  ),
                ),
                if (hasHeader) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: title == null
                            ? const SizedBox.shrink()
                            : Text(
                                title!,
                                style: AppTypography.headingSmall
                                    .copyWith(color: colors.textPrimary),
                              ),
                      ),
                      if (showCloseButton)
                        _SheetCloseButton(
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular ✕ dismiss button for [AppBottomSheet]'s header.
class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).closeButtonTooltip,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Material(
          color: colors.surfaceMuted,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
