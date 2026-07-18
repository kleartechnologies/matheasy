import 'package:flutter/material.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';

/// The Tutor home hero: a big, friendly Matheasy brand avatar, the headline
/// question and a primary call to start chatting.
class TutorHero extends StatelessWidget {
  const TutorHero({super.key, required this.onAskMatheasy});

  final VoidCallback onAskMatheasy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        const Floaty(
          child: MatheasyBrandAvatar(size: 116),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          context.l10n.tutorHeroTitle,
          textAlign: TextAlign.center,
          style: AppTypography.displaySmall.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.tutorHeroSubtitle,
          textAlign: TextAlign.center,
          style: AppTypography.bodyLarge.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: context.l10n.tutorAskMatheasy,
          icon: Icons.forum_rounded,
          expand: false,
          onPressed: onAskMatheasy,
        ),
      ],
    );
  }
}
