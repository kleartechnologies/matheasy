import 'package:flutter/material.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile_avatar.dart';

/// Renders a learner's avatar: their photo when available, otherwise the chosen
/// [ProfileAvatar] colour behind their [initial].
class ProfileAvatarView extends StatelessWidget {
  const ProfileAvatarView({
    super.key,
    required this.avatar,
    required this.initial,
    this.photoUrl,
    this.size = 56,
  });

  final ProfileAvatar avatar;
  final String initial;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: avatar.color, shape: BoxShape.circle),
      child: Text(
        initial,
        style: AppTypography.displaySmall.copyWith(
          color: AppColors.white,
          fontSize: size * 0.4,
        ),
      ),
    );

    final url = photoUrl;
    return Semantics(
      label: context.l10n.profileAvatarSemantics,
      image: true,
      excludeSemantics: true,
      child: url == null || url.isEmpty
          ? fallback
          : ClipOval(
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Show the initial fallback while the photo loads so there's no
                // blank flash, then swap in the image once ready.
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : fallback,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}
