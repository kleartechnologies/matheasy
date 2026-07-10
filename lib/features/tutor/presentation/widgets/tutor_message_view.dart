import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/tutor_models.dart';
import 'tutor_practice_card.dart';
import 'tutor_quiz_card.dart';
import 'tutor_suggestion_chips.dart';

/// Renders a single [TutorMessage] in its role-appropriate form:
///
/// * user → a right-aligned [ChatBubble]
/// * assistant → Matheasy's brand avatar + bubble ([MatheasyBubble]), with any
///   inline card (quiz/practice) and suggestion chips aligned underneath the
///   bubble
/// * system → a centered, muted notice pill
///
/// Suggestion chips only show for the latest assistant turn ([showSuggestions]),
/// keeping older turns tidy.
class TutorMessageView extends StatelessWidget {
  const TutorMessageView({
    super.key,
    required this.message,
    required this.onSuggestion,
    required this.onPracticeStart,
    this.showSuggestions = false,
  });

  /// Avatar diameter used to indent an assistant turn's card/chips so they line
  /// up under the bubble. Must match [MatheasyBubble]'s default `avatarSize`.
  static const double _avatar = 34;

  final TutorMessage message;
  final ValueChanged<SuggestionAction> onSuggestion;
  final VoidCallback onPracticeStart;
  final bool showSuggestions;

  @override
  Widget build(BuildContext context) {
    return switch (message.role) {
      TutorRole.user => ChatBubble(text: message.text, isUser: true),
      TutorRole.system => _SystemNotice(text: message.text),
      TutorRole.assistant => _assistant(context),
    };
  }

  Widget _assistant(BuildContext context) {
    final card = message.card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatheasyBubble(
          text: message.text,
        ),
        if (card != null)
          Padding(
            padding: const EdgeInsets.only(
              left: _avatar + AppSpacing.sm,
              top: AppSpacing.sm,
            ),
            child: _card(card),
          ),
        if (showSuggestions && message.suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: _avatar + AppSpacing.sm,
              top: AppSpacing.md,
            ),
            child: TutorSuggestionChips(
              actions: message.suggestions,
              onSelected: onSuggestion,
            ),
          ),
      ],
    );
  }

  Widget _card(TutorCard card) {
    return switch (card) {
      QuizCard(:final question) => TutorQuizCard(question),
      PracticeCard(:final prompt) =>
        TutorPracticeCard(prompt, onStart: onPracticeStart),
    };
  }
}

/// A centered, low-emphasis system notice (e.g. scan awareness, new chat).
class _SystemNotice extends StatelessWidget {
  const _SystemNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: AppRadius.pillRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 14,
              color: colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
