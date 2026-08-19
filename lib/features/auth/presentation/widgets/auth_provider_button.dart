import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/indicators/google_g_mark.dart';

/// The sign-in entry points rendered as full-width buttons. `email` is not a
/// federated provider — its button navigates to the email form rather than
/// launching a provider sheet.
enum AuthButtonProvider { apple, google, email }

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
          context.l10n.authContinueApple,
        ),
      AuthButtonProvider.google => (
          colors.surface,
          colors.textPrimary,
          Border.all(color: colors.border, width: 1.5),
          context.l10n.authContinueGoogle,
        ),
      AuthButtonProvider.email => (
          colors.surface,
          colors.textPrimary,
          Border.all(color: colors.border, width: 1.5),
          context.l10n.authContinueEmail,
        ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      // Announce the in-progress state to assistive tech (the spinner has no
      // text); liveRegion re-reads the label when it flips to loading.
      liveRegion: isLoading,
      label: isLoading ? context.l10n.authSigningIn : label,
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

/// The leading provider glyph. Apple uses the built-in logo; Google uses the
/// official multi-colour "G" mark, per Google's Sign-In branding guidelines
/// (on the dark theme's dark button surface it sits on a white plate, matching
/// Google's own dark-button spec).
class _Glyph extends StatelessWidget {
  const _Glyph({required this.provider, required this.color});

  final AuthButtonProvider provider;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (provider) {
      AuthButtonProvider.apple => Icon(Icons.apple, size: 22, color: color),
      AuthButtonProvider.google => context.isDark
          ? GoogleGMark.plated()
          : const GoogleGMark(size: 20),
      AuthButtonProvider.email =>
        Icon(Icons.mail_outline_rounded, size: 22, color: color),
    };
  }
}
