import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../services/haptics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_durations.dart';
import '../../theme/app_radius.dart';

/// A branded, animated on/off switch with a sliding thumb and haptic tick.
///
/// A custom control (rather than [Switch.adaptive]) so the toggle animation and
/// colours match the design system exactly in both themes. Carries `toggled`
/// semantics for assistive tech.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  static const double _width = 50;
  static const double _height = 30;
  static const double _thumb = 24;
  static const double _minTapHeight = 48;

  void _handleTap() {
    HapticsService.selection();
    onChanged!(!value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final trackOff = context.colors.textMuted.withValues(alpha: 0.35);
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? _handleTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: (_minTapHeight - _height) / 2,
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: AnimatedContainer(
              duration: AppDurations.medium,
              curve: AppCurves.standard,
              width: _width,
              height: _height,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                // The interactive emerald, not the identity tone: the track
                // carries the white thumb.
                color: value ? AppColors.primaryAction : trackOff,
                borderRadius: AppRadius.pillRadius,
              ),
              child: AnimatedAlign(
                duration: AppDurations.medium,
                curve: AppCurves.standard,
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: _thumb,
                  height: _thumb,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                    // Tighter than any [AppElevation] tier by design — the
                    // elevation tokens blur at 14–30px and would spill the
                    // thumb's shadow outside the 30px track.
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
