import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/tutor_models.dart';

/// The "Recent" list on the Tutor home. Tapping a conversation reopens it in the
/// chat. Hidden entirely when there are no recent conversations.
class TutorRecentConversations extends StatelessWidget {
  const TutorRecentConversations({
    super.key,
    required this.conversations,
    required this.onOpen,
  });

  final List<TutorConversation> conversations;
  final ValueChanged<TutorConversation> onOpen;

  @override
  Widget build(BuildContext context) {
    if (conversations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Recent conversations'),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < conversations.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          _ConversationTile(
            conversation: conversations[i],
            onTap: onOpen,
          ),
        ],
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final TutorConversation conversation;
  final ValueChanged<TutorConversation> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      onTap: () => onTap(conversation),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: AppRadius.smRadius,
            ),
            child: Icon(
              conversation.icon,
              size: 22,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.title.copyWith(
                    color: colors.textPrimary,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  conversation.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: colors.textMuted,
          ),
        ],
      ),
    );
  }
}
