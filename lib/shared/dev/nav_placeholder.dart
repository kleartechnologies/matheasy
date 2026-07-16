import 'package:flutter/material.dart';
import 'package:matheasy/core/brand/brand.dart';

import '../../core/animations/floaty.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Temporary Stage 1 placeholder scaffold, built entirely from design-system
/// primitives. Every navigation destination uses this until its real screen is
/// implemented in a later stage. [showBack] renders a back-enabled app bar for
/// pushed sub-routes; tab roots omit it and show the title inline.
class NavPlaceholder extends StatelessWidget {
  const NavPlaceholder({
    super.key,
    required this.title,
    required this.subtitle,
    this.showBack = false,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final bool showBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: showBack ? AppBar(title: Text(title)) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Floaty(child: MatheasyBrandAvatar(size: 128)),
                const SizedBox(height: AppSpacing.xl),
                if (!showBack)
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTypography.displaySmall
                        .copyWith(color: colors.textPrimary),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium
                      .copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: AppRadius.pillRadius,
                  ),
                  child: Text(
                    'STAGE 1 · PLACEHOLDER',
                    style: AppTypography.label
                        .copyWith(color: colors.onPrimaryContainer),
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.md),
                          actions[i],
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A subtle inline badge for the placeholder — kept here so screens stay tiny.
class PlaceholderNote extends StatelessWidget {
  const PlaceholderNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: AppTypography.caption.copyWith(
        // Emerald as text — the identity emerald is 2.97:1 on a light surface.
        color: context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
      ),
    );
  }
}
