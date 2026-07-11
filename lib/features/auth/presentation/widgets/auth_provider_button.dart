import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The federated providers rendered as full-width sign-in buttons.
enum AuthButtonProvider { apple, google }

/// A branded, full-width "Continue with …" button.
///
/// Apple follows its guideline of a solid button that inverts with the theme
/// (black on light, white on dark); Google uses a neutral surface button with a
/// coloured wordmark glyph. Both expose a per-button [isLoading] spinner and
/// proper button semantics.
class AuthProviderButton extends StatelessWidget {
  const AuthProviderButton({
    super.key,
    required this.provider,
    this.onPressed,
    this.isLoading = false,
  });

  final AuthButtonProvider provider;
  final VoidCallback? onPressed;
  final bool isLoading;

  static const double _height = 56;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null && !isLoading;

    final (background, foreground, border, label) = switch (provider) {
      AuthButtonProvider.apple => (
          context.isDark ? AppColors.white : AppColors.black,
          context.isDark ? AppColors.black : AppColors.white,
          null,
          'Continue with Apple',
        ),
      AuthButtonProvider.google => (
          colors.surface,
          colors.textPrimary,
          Border.all(color: colors.border, width: 1.5),
          'Continue with Google',
        ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      // Announce the in-progress state to assistive tech (the spinner has no
      // text); liveRegion re-reads the label when it flips to loading.
      liveRegion: isLoading,
      label: isLoading ? 'Signing in…' : label,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        borderRadius: AppRadius.pillRadius,
        child: Opacity(
          opacity: enabled ? 1 : 0.6,
          child: Container(
            height: _height,
            decoration: BoxDecoration(
              color: background,
              borderRadius: AppRadius.pillRadius,
              border: border,
            ),
            alignment: Alignment.center,
            child: isLoading
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(foreground),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Glyph(provider: provider, color: foreground),
                      const SizedBox(width: AppSpacing.sm),
                      // The outer Semantics already carries the label — exclude
                      // the visual text so it isn't announced twice.
                      Flexible(
                        child: ExcludeSemantics(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.button.copyWith(
                              color: foreground,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The leading provider glyph. Apple uses the built-in logo; Google currently
/// uses a placeholder single-colour "G".
///
// TODO(release-blocker): Replace the placeholder Google "G" below with the
// official multi-colour Google logo asset before App Store / Play submission —
// Google Sign-In branding guidelines require the official mark on the button.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.provider, required this.color});

  final AuthButtonProvider provider;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (provider) {
      AuthButtonProvider.apple => Icon(Icons.apple, size: 22, color: color),
      AuthButtonProvider.google => Text(
          'G',
          style: AppTypography.headingSmall.copyWith(
            color: const Color(0xFF4285F4),
            fontWeight: FontWeight.w800,
          ),
        ),
    };
  }
}
