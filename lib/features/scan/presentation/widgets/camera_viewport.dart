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
  });

  /// The initialized camera controller, or `null` while initializing / on error.
  final CameraController? controller;

  /// The failure that stopped the camera from starting, if any.
  final Object? error;

  /// Invoked when the user taps "Enable camera" after a permission denial.
  final VoidCallback? onEnableCamera;

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
  });

  final bool permissionDenied;
  final bool hasError;
  final VoidCallback? onEnableCamera;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.1,
          colors: [
            Color(0xFF14203A),
            Color(0xFF0B1220),
            AppColors.scannerBackground,
          ],
          stops: [0, 0.55, 1],
        ),
      ),
      child: permissionDenied
          ? _PermissionPrompt(onEnableCamera: onEnableCamera)
          : const SizedBox.expand(),
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({required this.onEnableCamera});

  final VoidCallback? onEnableCamera;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_rounded,
                color: AppColors.white, size: 48),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Camera access is off',
              textAlign: TextAlign.center,
              style: AppTypography.title.copyWith(color: AppColors.white),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Enable camera access in Settings, or use Gallery or Type it below.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall
                  .copyWith(color: Colors.white.withValues(alpha: 0.75)),
            ),
            if (onEnableCamera != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onEnableCamera,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.white,
                  side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.4)),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
