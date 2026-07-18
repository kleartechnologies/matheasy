import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_dashboard.dart';
import '../../domain/practice_session.dart';
import '../widgets/practice_chips.dart';

/// The daily challenge card — a featured session with a bonus XP reward.
class PracticeDailyChallenge extends StatelessWidget {
  const PracticeDailyChallenge({
    super.key,
    required this.challenge,
    required this.onStart,
  });

  final DailyChallengeView challenge;
  final ValueChanged<PracticeRequest> onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      onTap: () => onStart(challenge.request),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.xpContainer,
                  borderRadius: AppRadius.smRadius,
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  size: 24,
                  color: colors.onXpContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.title,
                      style: AppTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      challenge.subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PracticeXpBadge(xp: challenge.bonusXp),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              // Emerald like every other progress bar — the gold lives in the
              // bonus badge, so completion reads the same everywhere.
              Expanded(child: XPProgressBar(value: challenge.progress)),
              const SizedBox(width: AppSpacing.md),
              Text(
                context.l10n
                    .practiceDoneOfTarget(challenge.done, challenge.target),
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
