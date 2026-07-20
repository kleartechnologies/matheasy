import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'rich_math_text.dart';

/// A single chat message bubble. [isUser] flips alignment, color and the
/// asymmetric corner so user messages hug the right and the assistant's hug the
/// left.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
  });

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final radius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.lg),
            topRight: Radius.circular(AppRadius.lg),
            bottomLeft: Radius.circular(AppRadius.lg),
            bottomRight: Radius.circular(6),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.lg),
            topRight: Radius.circular(AppRadius.lg),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(AppRadius.lg),
          );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: context.screenWidth * 0.72,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            // Solid, never a gradient: the bubble carries white text, so the
            // fill must hold 4.78:1 across its whole area.
            color: isUser ? AppColors.primaryAction : colors.surface,
            borderRadius: radius,
            boxShadow: isUser ? null : context.elevation.card,
          ),
          child: RichMathText(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: isUser ? AppColors.white : colors.textPrimary,
              fontWeight: isUser ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
