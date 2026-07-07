import 'dart:ui';

import 'package:flutter/material.dart';

import '../../animations/pressable.dart';
import '../../extensions/context_extensions.dart';
import '../../services/haptics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_durations.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_typography.dart';

/// A single side item in [AppTabBar]. [index] is the branch index this item
/// selects in the navigation shell.
class AppTabItem {
  const AppTabItem({
    required this.index,
    required this.icon,
    required this.label,
  });

  final int index;
  final IconData icon;
  final String label;
}

/// The app's premium glassmorphic bottom navigation with a raised, primary
/// "Scan" action in the center.
///
/// The four side tabs map to the navigation shell's branches ([currentIndex]
/// 0–3; [onTap] switches branch). The center Scan button is a distinct action
/// ([onScan]) that pushes the full-screen scanner over the shell — so it reads
/// as the app's primary verb and the tab bar disappears while scanning.
///
/// Features: animated selection, per-tab [badges], haptic feedback and full
/// light/dark theming.
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onScan,
    this.badges = const {},
    this.leftItems = defaultLeftItems,
    this.rightItems = defaultRightItems,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onScan;

  /// Optional badge counts keyed by branch index.
  final Map<int, int> badges;

  final List<AppTabItem> leftItems;
  final List<AppTabItem> rightItems;

  static const List<AppTabItem> defaultLeftItems = [
    AppTabItem(index: 0, icon: Icons.home_rounded, label: 'Home'),
    AppTabItem(index: 1, icon: Icons.fitness_center_rounded, label: 'Practice'),
  ];

  static const List<AppTabItem> defaultRightItems = [
    AppTabItem(index: 2, icon: Icons.forum_rounded, label: 'Tutor'),
    AppTabItem(index: 3, icon: Icons.person_rounded, label: 'Profile'),
  ];

  void _handleTap(int index) {
    HapticsService.selection();
    onTap(index);
  }

  void _handleScan() {
    HapticsService.selection();
    onScan();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: colors.tabBar,
            border: Border(
              top: BorderSide(color: colors.border.withValues(alpha: 0.6)),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            14,
            12,
            14,
            8 + context.viewPadding.bottom,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in leftItems)
                _SideTab(
                  item: item,
                  selected: currentIndex == item.index,
                  badge: badges[item.index],
                  onTap: () => _handleTap(item.index),
                ),
              _ScanButton(onTap: _handleScan),
              for (final item in rightItems)
                _SideTab(
                  item: item,
                  selected: currentIndex == item.index,
                  badge: badges[item.index],
                  onTap: () => _handleTap(item.index),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideTab extends StatelessWidget {
  const _SideTab({
    required this.item,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final AppTabItem item;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : context.colors.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Badged(
              count: badge,
              child: AnimatedScale(
                scale: selected ? 1.12 : 1.0,
                duration: AppDurations.fast,
                curve: AppCurves.emphasized,
                child: Icon(item.icon, size: 26, color: color),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: AppDurations.fast,
              style: AppTypography.caption.copyWith(
                fontSize: 10.5,
                color: color,
                fontWeight: FontWeight.w700,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -20),
      child: Pressable(
        onTap: onTap,
        scale: 0.94,
        haptic: false, // handled by the tab bar
        borderRadius: AppRadius.lgRadius,
        child: Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: AppRadius.lgRadius,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGlowStrong,
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: const Icon(
            Icons.center_focus_strong_rounded,
            size: 30,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] with a small count badge in the top-right corner.
class _Badged extends StatelessWidget {
  const _Badged({required this.child, this.count});

  final Widget child;
  final int? count;

  @override
  Widget build(BuildContext context) {
    if (count == null || count! <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: AppRadius.pillRadius,
              border: Border.all(color: context.colors.tabBar, width: 1.5),
            ),
            child: Text(
              count! > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                color: AppColors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
