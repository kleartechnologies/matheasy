import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_spacing.dart';

/// A pinned bottom bar for primary screen actions. Fades from transparent into
/// the scaffold background at the top so scrolling content dissolves under it,
/// and respects the bottom safe area.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.children,
    this.spacing = AppSpacing.md,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final bg = context.colors.background;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.md + context.viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg.withValues(alpha: 0), bg],
          stops: const [0, 0.34],
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}
