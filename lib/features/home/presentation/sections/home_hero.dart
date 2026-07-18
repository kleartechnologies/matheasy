import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The Home hero — Home's first priority and the single most prominent element
/// on the screen. It answers "what should I do next?" the moment the app opens:
/// solve a problem, by scan (primary) or by typing (secondary).
///
/// The panel is a SOLID [AppColors.primaryAction]. The logo's tile is flat, so
/// the brand does not gradient its emerald, and primaryAction is the only
/// emerald that carries white content at AA (4.78:1) — the identity tone
/// [AppColors.primary] is 2.97:1 and never sits under a white label.
class HomeHero extends StatelessWidget {
  const HomeHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: const BoxDecoration(
        color: AppColors.primaryAction,
        borderRadius: AppRadius.heroRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.homeHeroPrompt,
            style: AppTypography.headingLarge.copyWith(
              color: AppColors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _HeroAction(
                  icon: Icons.center_focus_strong_rounded,
                  label: context.l10n.homeHeroScanQuestion,
                  filled: true,
                  onTap: () => context.push(AppRoutes.scan),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: _HeroAction(
                  icon: Icons.keyboard_rounded,
                  label: context.l10n.homeHeroType,
                  filled: false,
                  onTap: () => context.push(AppRoutes.manualInput),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An action on the emerald hero panel.
///
/// `filled` = a white surface carrying [AppColors.primaryDark] content (6.83:1).
/// Otherwise the panel shows through a white hairline, with white content
/// (4.78:1). The secondary action is outlined rather than tinted on purpose: any
/// translucent white fill lightens the panel underneath and drops its own white
/// label below 4.5:1.
class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.primaryDark : AppColors.white;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: filled ? AppColors.white : Colors.transparent,
        borderRadius: AppRadius.mdRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdRadius,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdRadius,
              border: filled
                  ? null
                  : Border.all(color: AppColors.white, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.button.copyWith(color: fg, fontSize: 15),
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
