import 'dart:ui';

import 'package:flutter/material.dart';

import '../../animations/pressable.dart';
import '../../extensions/context_extensions.dart';
import '../../services/haptics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_durations.dart';
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

/// The app's "liquid glass" bottom navigation: a frosted [BackdropFilter]
/// surface that scrollable content blurs through, a soft emerald pill that
/// _slides_ behind the active tab, and a raised, primary "Scan" action in the
/// center.
///
/// The five side tabs map to the navigation shell's branches ([currentIndex];
/// [onTap] switches branch). The center Scan button is a distinct action
/// ([onScan]) that pushes the full-screen scanner over the shell — so it reads
/// as the app's primary verb and the tab bar disappears while scanning. It is a
/// solid emerald FAB raised above the glass line (painted in an outer [Stack] so
/// it is never clipped by the blur), yet its whole hit box stays inside the bar
/// bounds so the raised part remains tappable.
///
/// Fully theme-aware (see [AppSemanticColors.tabBarGlass]) and respects the
/// bottom safe-area inset — nothing here is hardcoded to a device.
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
    AppTabItem(index: 3, icon: Icons.insights_rounded, label: 'Progress'),
    AppTabItem(index: 2, icon: Icons.person_rounded, label: 'Profile'),
  ];

  /// Key on the sliding active-pill box — exposed so widget tests can pin the
  /// pill's rendered position to the selected branch.
  @visibleForTesting
  static const Key pillKey = ValueKey('app_tab_bar_active_pill');

  // ---- Layout constants ----
  /// Height of a tab cell (icon + label) and of the active pill.
  static const double _cellHeight = 46;

  /// Horizontal inset of the tab row inside the glass surface.
  static const double _hPadding = 14;
  static const double _topPadding = 8;
  static const double _bottomPadding = 8;

  /// Center gap reserved in the row for the raised Scan FAB.
  static const double _scanGap = 64;

  /// Scan FAB square size, and how far its top rises above the glass line.
  static const double _fabSize = 46;
  static const double _fabRaise = 16;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Active hue reads brighter in the dark (Emerald 400) and richer on the
    // light frosted surface (Emerald 500) — both stay in the brand family.
    final activeColor = isDark ? AppColors.primaryLight : AppColors.primary;
    final pillTint = activeColor.withValues(alpha: isDark ? 0.18 : 0.14);

    final safeBottom = context.viewPadding.bottom;
    final glassHeight =
        _topPadding + _cellHeight + _bottomPadding + safeBottom;

    return SizedBox(
      // The bar reserves headroom above the glass so the raised FAB stays
      // inside its bounds (tappable) while poking above the frosted surface.
      height: glassHeight + _fabRaise,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: glassHeight,
            child: _GlassSurface(
              overlay: colors.tabBarGlass,
              hairline: colors.border,
              bottomInset: safeBottom,
              child: _TabRow(
                leftItems: leftItems,
                rightItems: rightItems,
                currentIndex: currentIndex,
                badges: badges,
                activeColor: activeColor,
                inactiveColor: colors.textTertiary,
                pillTint: pillTint,
                ringColor: colors.tabBar,
                onTap: _handleTap,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(child: _ScanButton(onTap: _handleScan)),
          ),
        ],
      ),
    );
  }
}

/// The clipped, blurred glass slab. [child] is padded above the safe-area.
class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.overlay,
    required this.hairline,
    required this.bottomInset,
    required this.child,
  });

  final Color overlay;
  final Color hairline;
  final double bottomInset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // ClipRect confines the BackdropFilter to the bar, so the blur can't bleed
    // across the whole screen behind it.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: overlay,
            border: Border(top: BorderSide(color: hairline)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppTabBar._hPadding,
              AppTabBar._topPadding,
              AppTabBar._hPadding,
              AppTabBar._bottomPadding + bottomInset,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The row of side tabs with the sliding active pill layered behind them.
class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.leftItems,
    required this.rightItems,
    required this.currentIndex,
    required this.badges,
    required this.activeColor,
    required this.inactiveColor,
    required this.pillTint,
    required this.ringColor,
    required this.onTap,
  });

  final List<AppTabItem> leftItems;
  final List<AppTabItem> rightItems;
  final int currentIndex;
  final Map<int, int> badges;
  final Color activeColor;
  final Color inactiveColor;
  final Color pillTint;
  final Color ringColor;
  final ValueChanged<int> onTap;

  Widget _tab(AppTabItem item) => Expanded(
        child: _SideTab(
          item: item,
          selected: currentIndex == item.index,
          badge: badges[item.index],
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          ringColor: ringColor,
          onTap: () => onTap(item.index),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTabBar._cellHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rowWidth = constraints.maxWidth;
          final sideWidth = (rowWidth - AppTabBar._scanGap) / 4;

          // Center-x of each side tab's slot, keyed by branch index. Walk the
          // row left→right so this stays correct for any item configuration.
          final centers = <int, double>{};
          var x = 0.0;
          for (final item in leftItems) {
            centers[item.index] = x + sideWidth / 2;
            x += sideWidth;
          }
          x += AppTabBar._scanGap;
          for (final item in rightItems) {
            centers[item.index] = x + sideWidth / 2;
            x += sideWidth;
          }

          final pillWidth = (sideWidth - 12).clamp(46.0, 76.0);
          final pillCenter = centers[currentIndex];

          return Stack(
            children: [
              if (pillCenter != null)
                AnimatedPositioned(
                  duration: AppDurations.medium,
                  curve: AppCurves.standard,
                  left: pillCenter - pillWidth / 2,
                  top: 0,
                  width: pillWidth,
                  height: AppTabBar._cellHeight,
                  child: DecoratedBox(
                    key: AppTabBar.pillKey,
                    decoration: BoxDecoration(
                      color: pillTint,
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (final item in leftItems) _tab(item),
                  const SizedBox(width: AppTabBar._scanGap),
                  for (final item in rightItems) _tab(item),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SideTab extends StatelessWidget {
  const _SideTab({
    required this.item,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.ringColor,
    required this.onTap,
    this.badge,
  });

  final AppTabItem item;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final Color ringColor;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    final count = badge;
    return Semantics(
      button: true,
      selected: selected,
      label: count != null && count > 0
          ? '${item.label}, $count new'
          : item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Badged(
                  count: badge,
                  ringColor: ringColor,
                  child: Icon(item.icon, size: 24, color: color),
                ),
                const SizedBox(height: 3),
                // The cell is a fixed height so the pill geometry is stable, so
                // the micro-label's text scale is capped (as platform tab bars
                // do) — otherwise iOS/Android accessibility font sizes overflow
                // the cell and clip the label.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: AnimatedDefaultTextStyle(
                    duration: AppDurations.fast,
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scan a problem',
      child: Pressable(
        onTap: onTap,
        scale: 0.94,
        haptic: false, // handled by the tab bar
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: AppTabBar._fabSize,
          height: AppTabBar._fabSize,
          decoration: BoxDecoration(
            // Priority comes from position, size and contrast — not a glow.
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.center_focus_strong_rounded,
            size: 24,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] with a small count badge in the top-right corner.
class _Badged extends StatelessWidget {
  const _Badged({
    required this.child,
    required this.ringColor,
    this.count,
  });

  final Widget child;
  final Color ringColor;
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
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: ringColor, width: 1.5),
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
