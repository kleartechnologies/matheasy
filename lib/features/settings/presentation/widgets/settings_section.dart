import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';

/// A subtle informational footnote below a settings group — a muted icon + line
/// used to explain a not-yet-wired preference.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key, this.icon = Icons.info_outline_rounded});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        left: AppSpacing.xs,
        right: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The uppercase caption that heads a settings group. Exposed so screens can
/// label free-standing blocks (chip grids, selectors) to match [SettingsSection].
class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.label.copyWith(color: context.colors.textMuted),
      ),
    );
  }
}

/// A grouped settings block — an optional uppercase caption above a rounded card
/// whose rows are separated by hairline dividers (the Apple-Settings pattern).
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) SettingsGroupLabel(title!),
        AppCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 64,
                    color: colors.divider,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
