import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/widgets.dart';
import 'settings_section.dart';
import 'settings_tile.dart';

/// Presents a single-select list of [options] in a themed bottom sheet, marking
/// the [selected] one and invoking [onSelected] when the learner picks. Used for
/// grade level, learning goal and daily-goal preferences.
Future<void> showSettingsOptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T? selected,
  required String Function(T option) label,
  required IconData Function(T option) icon,
  required ValueChanged<T> onSelected,
  String? Function(T option)? trailing,
}) {
  return AppBottomSheet.show<void>(
    context,
    title: title,
    child: SingleChildScrollView(
      child: SettingsSection(
        children: [
          for (final option in options)
            SettingsTile(
              icon: icon(option),
              title: label(option),
              value: trailing?.call(option),
              trailing: option == selected
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.primary,
                    )
                  : const SizedBox(width: 24),
              onTap: () {
                Navigator.of(context).pop();
                onSelected(option);
              },
            ),
        ],
      ),
    ),
  );
}
