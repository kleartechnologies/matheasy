import 'package:flutter/material.dart';

import '../../animations/pressable.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_durations.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

enum _ButtonVariant { primary, secondary, ghost }

enum AppButtonSize { large, medium, small }

/// Filled gradient call-to-action — the app's main affirmative action.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = true,
    this.size = AppButtonSize.large,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool expand;
  final AppButtonSize size;

  @override
  Widget build(BuildContext context) => _AppButton(
        variant: _ButtonVariant.primary,
        label: label,
        onPressed: onPressed,
        icon: icon,
        trailingIcon: trailingIcon,
        isLoading: isLoading,
        expand: expand,
        size: size,
      );
}

/// Outlined, surface-filled secondary action.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = true,
    this.size = AppButtonSize.large,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool expand;
  final AppButtonSize size;

  @override
  Widget build(BuildContext context) => _AppButton(
        variant: _ButtonVariant.secondary,
        label: label,
        onPressed: onPressed,
        icon: icon,
        trailingIcon: trailingIcon,
        isLoading: isLoading,
        expand: expand,
        size: size,
      );
}

/// Low-emphasis text-only action.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.size = AppButtonSize.medium,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool expand;
  final AppButtonSize size;

  @override
  Widget build(BuildContext context) => _AppButton(
        variant: _ButtonVariant.ghost,
        label: label,
        onPressed: onPressed,
        icon: icon,
        trailingIcon: trailingIcon,
        isLoading: false,
        expand: expand,
        size: size,
      );
}

class _AppButton extends StatelessWidget {
  const _AppButton({
    required this.variant,
    required this.label,
    required this.onPressed,
    required this.icon,
    required this.trailingIcon,
    required this.isLoading,
    required this.expand,
    required this.size,
  });

  final _ButtonVariant variant;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool expand;
  final AppButtonSize size;

  double get _height => switch (size) {
        AppButtonSize.large => 56,
        AppButtonSize.medium => 48,
        AppButtonSize.small => 40,
      };

  double get _fontSize => switch (size) {
        AppButtonSize.large => 16,
        AppButtonSize.medium => 15,
        AppButtonSize.small => 14,
      };

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final colors = context.colors;

    // Resolve visuals per variant + enabled state.
    Gradient? gradient;
    Color background = Colors.transparent;
    Color foreground;
    Border? border;
    List<BoxShadow> shadow = const [];

    switch (variant) {
      case _ButtonVariant.primary:
        if (enabled) {
          gradient = AppColors.primaryGradient;
          foreground = AppColors.white;
          shadow = context.elevation.button;
        } else {
          background = colors.surfaceMuted;
          foreground = colors.textTertiary;
        }
      case _ButtonVariant.secondary:
        background = colors.surface;
        foreground = enabled ? AppColors.primary : colors.textTertiary;
        border = Border.all(
          color: enabled ? colors.border : colors.divider,
          width: 1.5,
        );
      case _ButtonVariant.ghost:
        foreground = enabled ? AppColors.primary : colors.textTertiary;
    }

    final content = isLoading
        ? SizedBox(
            height: _fontSize + 4,
            width: _fontSize + 4,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(foreground),
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: _fontSize + 4, color: foreground),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.button.copyWith(
                    fontSize: _fontSize,
                    color: foreground,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(trailingIcon, size: _fontSize + 4, color: foreground),
              ],
            ],
          );

    final button = AnimatedContainer(
      duration: AppDurations.fast,
      height: _height,
      width: expand ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal: expand ? AppSpacing.lg : AppSpacing.xl,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? background : null,
        borderRadius: AppRadius.pillRadius,
        border: border,
        boxShadow: shadow,
      ),
      child: content,
    );

    return Pressable(
      onTap: enabled ? onPressed : null,
      borderRadius: AppRadius.pillRadius,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: button,
      ),
    );
  }
}
