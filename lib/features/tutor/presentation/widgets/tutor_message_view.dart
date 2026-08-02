import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/tutor_models.dart';
import 'tutor_focus_card.dart';
import 'tutor_page_overlay.dart';
import 'tutor_practice_card.dart';
import 'tutor_quiz_card.dart';
import 'tutor_suggestion_chips.dart';

/// Renders a single [TutorMessage] in its role-appropriate form:
///
/// * user → a right-aligned [ChatBubble], under the photo they attached if any
/// * assistant → Numi's brand avatar + bubble ([MatheasyBubble]), with any
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
    this.page,
  });

  /// Avatar diameter used to indent an assistant turn's card/chips so they line
  /// up under the bubble. Must match [MatheasyBubble]'s default `avatarSize`.
  static const double _avatar = 34;

  final TutorMessage message;
  final ValueChanged<SuggestionAction> onSuggestion;
  final VoidCallback onPracticeStart;
  final bool showSuggestions;

  /// The scanned page this conversation is about, when there is one. Supplied
  /// by the chat screen from the session context — a message carries WHERE it
  /// points, never the pixels, so a thread of thirty turns holds one photo.
  final TutorScannedPage? page;

  @override
  Widget build(BuildContext context) {
    return switch (message.role) {
      TutorRole.user => _user(context),
      TutorRole.system => _SystemNotice(text: message.text),
      TutorRole.assistant => _assistant(context),
    };
  }

  /// A student turn: their photo (if they attached one) above their words.
  Widget _user(BuildContext context) {
    final image = message.image;
    if (image == null) return ChatBubble(text: message.text, isUser: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _AttachedPhoto(image),
        if (message.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: ChatBubble(text: message.text, isUser: true),
          ),
      ],
    );
  }

  Widget _assistant(BuildContext context) {
    final card = message.card;
    final focus = message.focus;
    final page = this.page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatheasyBubble(
          text: message.text,
        ),
        // The student's own page, with Numi's hand on it. First of everything
        // under the bubble: "look at the angle on the top right" is useless
        // until you can see which one she means.
        if (page != null && message.hasActions)
          Padding(
            padding: const EdgeInsets.only(
              left: _avatar + AppSpacing.sm,
              top: AppSpacing.sm,
            ),
            child: TutorPageOverlay(
              imageBytes: page.imageBytes,
              anchors: page.anchors,
              actions: message.actions,
            ),
          ),
        // The equation she is pointing at sits directly under her words, before
        // any card: it belongs to the explanation, not beside it.
        if (focus != null)
          Padding(
            padding: const EdgeInsets.only(
              left: _avatar + AppSpacing.sm,
              top: AppSpacing.sm,
            ),
            child: TutorFocusCard(focus),
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

/// The photo a student attached to their turn.
///
/// Tappable, because "did it read the right thing?" is a question a thumbnail
/// can't answer — the student needs to see what they actually sent, at size,
/// before they trust (or correct) what Numi read out of it.
class _AttachedPhoto extends StatelessWidget {
  const _AttachedPhoto(this.bytes);

  final Uint8List bytes;

  /// Tall enough to read a line of handwriting, short enough to leave the
  /// conversation visible around it.
  static const double _maxHeight = 220;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.tutorImageAttached;
    return Semantics(
      image: true,
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: () => _open(context, label),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: context.screenWidth * 0.62,
              maxHeight: _maxHeight,
            ),
            child: ClipRRect(
              borderRadius: AppRadius.lgRadius,
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, String label) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              maxScale: 4,
              child: ClipRRect(
                borderRadius: AppRadius.lgRadius,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            // White on the dimmed barrier, so the control is legible over any
            // photo — a dark homework page included.
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: dialogContext.l10n.actionClose,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      ),
    );
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
              color: colors.textMuted,
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
