import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The chat composer: an attachment button, a growing text field, a voice
/// placeholder and a send button.
///
/// Future-ready — [onAttach] and [onVoice] are wired for image upload and voice
/// chat, which a later stage fills in without changing this layout. [enabled]
/// is false while Matheasy is replying, so turns can't interleave.
class TutorChatInput extends StatefulWidget {
  const TutorChatInput({
    super.key,
    required this.onSend,
    this.onAttach,
    this.onVoice,
    this.enabled = true,
  });

  final ValueChanged<String> onSend;
  final VoidCallback? onAttach;
  final VoidCallback? onVoice;
  final bool enabled;

  @override
  State<TutorChatInput> createState() => _TutorChatInputState();
}

class _TutorChatInputState extends State<TutorChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canSend = _hasText && widget.enabled;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        // `padding` (not `viewPadding`) collapses to 0 when the keyboard covers
        // the safe area, so the bar sits snug above the keyboard when open.
        AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _IconAction(
            icon: Icons.add_photo_alternate_outlined,
            tooltip: 'Upload a question',
            onTap: widget.onAttach,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: AppRadius.lgRadius,
                border: Border.all(color: colors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.textPrimary,
                      ),
                      cursorColor: context.isDark
                          ? AppColors.primaryLight
                          : AppColors.primaryDark,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Ask Matheasy anything…',
                        hintStyle: AppTypography.bodyMedium.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  _IconAction(
                    icon: Icons.mic_none_rounded,
                    tooltip: 'Voice input',
                    onTap: widget.onVoice,
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _SendButton(enabled: canSend, onTap: _send),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.dense = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // Icon-only controls need a comfortable tap target. The standalone
    // attach/send controls are 44dp (the app-wide icon-button size). The
    // [dense] variant is the voice control nested inside the composer field:
    // it keeps the field's compact height (so the composer doesn't inflate and
    // the sibling buttons stay aligned) while widening its horizontal tap area.
    final double width = dense ? 48.0 : 44.0;
    final double height = dense ? 40.0 : 44.0;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Pressable(
          onTap: onTap,
          borderRadius: AppRadius.pillRadius,
          child: SizedBox(
            width: width,
            height: height,
            child: Icon(
              icon,
              size: 24,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send message',
      child: Pressable(
        onTap: enabled ? onTap : null,
        borderRadius: AppRadius.pillRadius,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            // Solid interactive emerald — the white arrow needs 4.78:1.
            color: enabled ? AppColors.primaryAction : colors.surfaceMuted,
            shape: BoxShape.circle,
            boxShadow: enabled ? context.elevation.button : null,
          ),
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 22,
            color: enabled ? AppColors.white : colors.textMuted,
          ),
        ),
      ),
    );
  }
}
