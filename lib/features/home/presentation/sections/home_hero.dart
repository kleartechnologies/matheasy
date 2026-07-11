import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The Home hero — the single most prominent element on the screen. It answers
/// "what should I do next?" the moment the app opens: solve a problem, by scan
/// (primary) or by typing (secondary).
///
/// Emerald-branded, but flat — a subtle gradient and strong typography carry it,
/// no glow.
class HomeHero extends StatelessWidget {
  const HomeHero({super.key});

  static const LinearGradient _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF047857)], // emerald 500 → 700
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: const BoxDecoration(
        gradient: _gradient,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.hero)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What would you like\nto solve today?',
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
                  label: 'Scan Question',
                  filled: true,
                  onTap: () => context.push(AppRoutes.scan),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: _HeroAction(
                  icon: Icons.keyboard_rounded,
                  label: 'Type',
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
        color: filled ? AppColors.white : Colors.white.withValues(alpha: 0.14),
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
                  : Border.all(color: Colors.white.withValues(alpha: 0.35)),
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
