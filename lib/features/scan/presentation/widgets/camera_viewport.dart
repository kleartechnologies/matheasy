import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The live camera preview behind the scanner chrome.
///
/// Renders the real back-camera texture (cover-fit) when [controller] is
/// initialized. When the camera is unavailable — permission denied, no camera,
/// or still initializing — it falls back to a calm dark scene so the gallery /
/// manual-entry paths remain usable.
class CameraViewport extends StatelessWidget {
  const CameraViewport({
    super.key,
    required this.controller,
    this.error,
    this.onEnableCamera,
    this.onOpenSettings,
    this.onType,
  });

  /// The initialized camera controller, or `null` while initializing / on error.
  final CameraController? controller;

  /// The failure that stopped the camera from starting, if any.
  final Object? error;

  /// Retries camera init (e.g. after granting access in Settings).
  final VoidCallback? onEnableCamera;

  /// Opens the OS app-settings page so a denied camera can be re-enabled.
  final VoidCallback? onOpenSettings;

  /// Opens the manual math keyboard — always available when the camera isn't.
  final VoidCallback? onType;

  bool get _permissionDenied {
    final e = error;
    return e is CameraException &&
        (e.code.contains('Denied') || e.code.contains('Permission'));
  }

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    if (camera != null && camera.value.isInitialized) {
      return _CoverPreview(controller: camera);
    }
    return _FallbackScene(
      permissionDenied: _permissionDenied,
      hasError: error != null,
      onEnableCamera: onEnableCamera,
      onOpenSettings: onOpenSettings,
      onType: onType,
    );
  }
}

/// Scales the preview to cover the whole screen (like `BoxFit.cover`) so there
/// are no letterbox bars behind the chrome.
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // controller.value.aspectRatio is width/height in landscape terms; combine
    // with the screen ratio and clamp so the smaller axis fills.
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ColoredBox(
      color: AppColors.scannerBackground,
      child: Transform.scale(
        scale: scale,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }
}

class _FallbackScene extends StatelessWidget {
  const _FallbackScene({
    required this.permissionDenied,
    required this.hasError,
    required this.onEnableCamera,
    required this.onOpenSettings,
    required this.onType,
  });

  final bool permissionDenied;
  final bool hasError;
  final VoidCallback? onEnableCamera;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onType;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      // Flat deep ink, identical to the live-preview backdrop so the fallback
      // reads as the same surface. The old radial was a decorative blue-slate
      // vignette from a palette the brand no longer has — an honest error state
      // does not need scenery.
      color: AppColors.scannerBackground,
      // A denied permission needs the Settings deep-link; any other camera
      // failure (restricted / no camera / busy) still gets an honest message and
      // a way forward — never an unexplained blank preview (spec §9).
      child: permissionDenied
          ? _CameraUnavailable(
              icon: Icons.no_photography_rounded,
              title: 'Matheasy needs the camera to scan problems',
              body: "It's turned off right now. Turn it on in Settings, or "
                  'pick a photo or type the problem instead.',
              primaryLabel: 'Open Settings',
              onPrimary: onOpenSettings,
              onRetry: onEnableCamera,
              onType: onType,
            )
          : hasError
              ? _CameraUnavailable(
                  icon: Icons.videocam_off_rounded,
                  title: 'Your camera isn’t available',
                  body: 'Something’s blocking it on this device. You can still '
                      'pick a photo or type the problem in.',
                  onRetry: onEnableCamera,
                  onType: onType,
                )
              : const SizedBox.expand(),
    );
  }
}

/// The calm, directive camera-unavailable state (denied / restricted / no
/// camera). Gives the way forward — Settings and/or retry, and always the
/// manual-entry escape — rather than an apology or a blank screen.
class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({
    required this.icon,
    required this.title,
    required this.body,
    required this.onRetry,
    required this.onType,
    this.primaryLabel,
    this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;
  final VoidCallback? onType;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.white, size: 48),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(color: AppColors.white),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall
                    .copyWith(color: Colors.white.withValues(alpha: 0.75)),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  if (primaryLabel != null && onPrimary != null)
                    _GlassPill(
                      icon: Icons.settings_rounded,
                      label: primaryLabel!,
                      onTap: onPrimary!,
                    ),
                  if (onType != null)
                    _GlassPill(
                      icon: Icons.keyboard_rounded,
                      label: 'Type it in',
                      onTap: onType!,
                    ),
                  if (onRetry != null)
                    _GlassPill(
                      icon: Icons.refresh_rounded,
                      label: 'Try again',
                      onTap: onRetry!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: AppColors.white, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: AppTypography.button.copyWith(color: AppColors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
