import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile_avatar.dart';

/// Renders a learner's avatar: their photo when available, otherwise the chosen
/// [ProfileAvatar] gradient behind their [initial].
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
      decoration: BoxDecoration(gradient: avatar.gradient, shape: BoxShape.circle),
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
      label: 'Profile avatar',
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
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}
