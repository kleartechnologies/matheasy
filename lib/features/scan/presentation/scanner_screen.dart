import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matheasy/core/brand/brand.dart';

import '../../../core/animations/floaty.dart';
import '../../../core/animations/pressable.dart';
import '../../../core/monitoring/logging_service.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../progress/application/stats_controller.dart';
import '../../subscription/application/usage_controller.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../application/scanner_controller.dart';
import '../domain/detected_equation.dart';
import '../domain/scan_source.dart';
import '../domain/scan_state.dart';
import 'crop_screen.dart';
import 'widgets/camera_viewport.dart';
import 'widgets/capture_confirmation.dart';
import 'widgets/processing_overlay.dart';
import 'widgets/scan_frame.dart';

/// The full-screen, immersive scanner. Pushed over the shell (no tab bar).
///
/// Owns the real back-camera lifecycle (init / dispose / app-lifecycle) and
/// drives the capture → crop → recognize → confirm flow through
/// [ScannerController].
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();

  CameraController? _camera;
  Object? _cameraError;
  bool _initializingCamera = false;
  bool _flashOn = false;
  bool _capturing = false;

  /// True while the app is backgrounded — guards against an in-flight camera
  /// init activating the session after a pause.
  bool _appPaused = false;

  ScannerController get _controller =>
      ref.read(scannerControllerProvider.notifier);

  bool get _cameraReady => _camera?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref
        .read(analyticsServiceProvider)
        .logEvent(AnalyticsEvent.scannerOpened()));
    unawaited(_initCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appPaused = false;
      // Always re-acquire on resume — _initCamera() is a no-op if the camera is
      // already live or initializing. (The old code guarded on `_camera != null`
      // here, which meant a disposed camera was never re-acquired.)
      unawaited(_initCamera());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Free the camera only when truly backgrounded — not on transient
      // `inactive` (app switcher, Control Center, notification shade), which
      // would otherwise tear down the preview for a passing system overlay.
      _appPaused = true;
      _disposeCamera();
    }
  }

  // -- Camera lifecycle ------------------------------------------------------

  Future<void> _initCamera() async {
    if (_initializingCamera || _cameraReady) return;
    _initializingCamera = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'No camera on this device.');
      }
      // Back camera only — the front camera is never used for scanning.
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        // 1080p — high enough to read small/dense problem text; the crop is then
        // downscaled to ≤1600px before upload so the payload stays small.
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      // Bail if we unmounted or were backgrounded during init — otherwise we'd
      // activate a camera session while the app is in the background.
      if (!mounted || _appPaused) {
        await controller.dispose();
        return;
      }
      await controller.setFlashMode(
          _flashOn ? FlashMode.torch : FlashMode.off);
      setState(() {
        _camera = controller;
        _cameraError = null;
      });
    } catch (error, stack) {
      LoggingService.warning('Camera init failed: $error');
      if (error is! CameraException) {
        LoggingService.error('Camera init error',
            error: error, stackTrace: stack);
      }
      if (!mounted) return;
      setState(() {
        _camera = null;
        _cameraError = error;
      });
    } finally {
      _initializingCamera = false;
    }
  }

  void _disposeCamera() {
    final camera = _camera;
    if (camera == null) return;
    _camera = null;
    unawaited(camera.dispose());
    if (mounted) setState(() {});
  }

  Future<void> _toggleFlash() async {
    final next = !_flashOn;
    setState(() => _flashOn = next);
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    try {
      await camera.setFlashMode(next ? FlashMode.torch : FlashMode.off);
    } catch (error) {
      LoggingService.warning('Flash toggle failed: $error');
      if (mounted) setState(() => _flashOn = !next); // revert on failure
    }
  }

  // -- Capture sources -------------------------------------------------------

  /// Shutter: capture from the live camera, then crop + recognize.
  Future<void> _shutter() async {
    final camera = _camera;
    if (_capturing || camera == null || !camera.value.isInitialized) return;
    setState(() => _capturing = true);
    Uint8List bytes;
    try {
      final file = await camera.takePicture();
      bytes = await file.readAsBytes();
    } catch (error) {
      LoggingService.warning('Capture failed: $error');
      _toast("Couldn't take the photo. Try again.");
      return;
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
    await _cropAndRecognize(ScanSource.camera, bytes);
  }

  /// Pick from the gallery, then crop + recognize.
  Future<void> _gallery() async {
    if (_capturing) return;
    Uint8List bytes;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 90,
      );
      if (file == null) return; // cancelled
      bytes = await file.readAsBytes();
    } catch (error) {
      LoggingService.warning('Gallery pick failed: $error');
      _toast("Couldn't open your photos.");
      return;
    }
    await _cropAndRecognize(ScanSource.gallery, bytes);
  }

  /// Manual entry — type the problem (no OCR).
  Future<void> _type() async {
    final latex = await _promptManualEntry();
    if (latex == null || latex.trim().isEmpty) return;
    await _controller.recognize(ScanSource.manual, manualLatex: latex.trim());
  }

  /// Pushes the crop screen for [bytes]; on confirm, recognizes the cropped
  /// image. Cancelling the crop returns to the live preview.
  Future<void> _cropAndRecognize(ScanSource source, Uint8List bytes) async {
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CropScreen(imageBytes: bytes),
      ),
    );
    if (cropped == null || !mounted) return; // cancelled
    unawaited(ref
        .read(analyticsServiceProvider)
        .logEvent(AnalyticsEvent.imageCropped(source: source.name)));
    await _controller.recognize(source, imageBytes: cropped);
  }

  Future<String?> _promptManualEntry() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Type a problem'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'e.g. 2x + 5 = 13'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Solve'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The "Continue → solve" commit point. Checks the scan quota first: a free
  /// user out of scans is sent to the paywall (the scanner is replaced, so
  /// dismissing it returns to the app) instead of consuming a solve.
  void _onContinue() {
    if (ref.read(usageSnapshotProvider).canScan) {
      _controller.confirm();
      return;
    }
    context.pushReplacement(
      AppRoutes.paywall,
      extra: PaywallTrigger.scanLimit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    final controller = _controller;

    // Hand off to the result screen when the user confirms, recording the scan
    // for progress/achievements and consuming one from the free-tier quota.
    ref.listen(scannerControllerProvider, (previous, next) {
      if (next is ScanComplete) {
        ref.read(statsControllerProvider.notifier).recordScan();
        ref.read(usageControllerProvider.notifier).recordScan();
        context.pushReplacement(AppRoutes.scanResult, extra: next.equation);
      } else if (next is ScanQuotaExceeded) {
        // Server said the free quota is spent — send them to the paywall.
        context.pushReplacement(AppRoutes.paywall, extra: PaywallTrigger.scanLimit);
      }
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.scannerBackground,
        body: Stack(
          fit: StackFit.expand,
          children: [
            CameraViewport(
              controller: _camera,
              error: _cameraError,
              onEnableCamera: () => unawaited(_initCamera()),
            ),
            AnimatedSwitcher(
              duration: AppDurations.medium,
              child: _content(state, controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(ScanState state, ScannerController controller) {
    return switch (state) {
      ScanIdle() => _ScanningChrome(
          key: const ValueKey('scanning'),
          flashOn: _flashOn,
          canCapture: _cameraReady && !_capturing,
          onFlash: () => unawaited(_toggleFlash()),
          onClose: () => context.pop(),
          onGallery: () => unawaited(_gallery()),
          onShutter: () => unawaited(_shutter()),
          onType: () => unawaited(_type()),
        ),
      ScanRecognizing() =>
        const ProcessingOverlay(key: ValueKey('recognizing')),
      ScanCaptured(:final equation) => _CapturedView(
          key: const ValueKey('captured'),
          equation: equation,
          onClose: () => context.pop(),
          onRetake: controller.retake,
          onContinue: _onContinue,
        ),
      ScanComplete() => const SizedBox.shrink(key: ValueKey('complete')),
      ScanQuotaExceeded() =>
        const SizedBox.shrink(key: ValueKey('quota')),
      ScanError(:final message) => _ErrorView(
          key: const ValueKey('error'),
          message: message,
          onRetry: controller.retake,
        ),
    };
  }
}

// ---------------------------------------------------------------------------
// Scanning chrome (idle)
// ---------------------------------------------------------------------------

class _ScanningChrome extends StatelessWidget {
  const _ScanningChrome({
    super.key,
    required this.flashOn,
    required this.canCapture,
    required this.onFlash,
    required this.onClose,
    required this.onGallery,
    required this.onShutter,
    required this.onType,
  });

  final bool flashOn;
  final bool canCapture;
  final VoidCallback onFlash;
  final VoidCallback onClose;
  final VoidCallback onGallery;
  final VoidCallback onShutter;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _TopBar(flashOn: flashOn, onFlash: onFlash, onClose: onClose),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Line up the whole question, then tap to capture',
            style: AppTypography.bodySmall
                .copyWith(color: Colors.white.withValues(alpha: 0.75)),
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(34, AppSpacing.xl, 34, 0),
              child: Align(
                alignment: Alignment(0, -0.35),
                child: AspectRatio(
                  aspectRatio: 1.6,
                  child: ScanFrame(locked: false),
                ),
              ),
            ),
          ),
          const _MatheasyHint(),
          _BottomControls(
            canCapture: canCapture,
            onGallery: onGallery,
            onShutter: onShutter,
            onType: onType,
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.flashOn,
    required this.onFlash,
    required this.onClose,
  });

  final bool flashOn;
  final VoidCallback onFlash;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _GlassButton(
            icon: Icons.close_rounded,
            onTap: onClose,
            label: 'Close scanner',
          ),
          const Spacer(),
          Text(
            'Scan a problem',
            style: AppTypography.title.copyWith(color: AppColors.white),
          ),
          const Spacer(),
          _GlassButton(
            icon: flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            onTap: onFlash,
            label: flashOn ? 'Turn flash off' : 'Turn flash on',
          ),
        ],
      ),
    );
  }
}

class _MatheasyHint extends StatelessWidget {
  const _MatheasyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xl, bottom: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppRadius.md),
                topRight: Radius.circular(AppRadius.md),
                bottomLeft: Radius.circular(AppRadius.md),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              'Point at a whole question — I’ll read it for you.',
              style: AppTypography.caption
                  .copyWith(color: AppColors.scannerBackground),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Floaty(child: MatheasyBrandAvatar(size: 52)),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.canCapture,
    required this.onGallery,
    required this.onShutter,
    required this.onType,
  });

  final bool canCapture;
  final VoidCallback onGallery;
  final VoidCallback onShutter;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, AppSpacing.md, 44, AppSpacing.xxl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _LabeledControl(
            icon: Icons.photo_library_rounded,
            label: 'Gallery',
            onTap: onGallery,
          ),
          _ShutterButton(enabled: canCapture, onTap: onShutter),
          _LabeledControl(
            icon: Icons.keyboard_rounded,
            label: 'Type it',
            onTap: onType,
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Take photo',
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Pressable(
          onTap: enabled ? onTap : () {},
          scale: 0.92,
          borderRadius: AppRadius.pillRadius,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: enabled
                    ? AppColors.primaryTint
                    : Colors.white.withValues(alpha: 0.4),
                width: 5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: enabled ? AppColors.primaryGradient : null,
                  color: enabled ? null : AppColors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassButton(icon: icon, onTap: onTap, label: label, size: 52),
        const SizedBox(height: AppSpacing.xs),
        // Decorative caption — the button already carries the accessible name.
        ExcludeSemantics(
          child: Text(
            label,
            style: AppTypography.caption
                .copyWith(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.onTap,
    required this.label,
    this.size = 42,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// Accessible name announced by screen readers.
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Ensure at least a 48x48 hit target even when the visual glass is smaller.
    final hit = size < 48 ? 48.0 : size;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.94,
        borderRadius: AppRadius.mdRadius,
        child: SizedBox(
          width: hit,
          height: hit,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: AppRadius.mdRadius,
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, color: AppColors.white, size: size * 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Captured view (confirmation)
// ---------------------------------------------------------------------------

class _CapturedView extends StatelessWidget {
  const _CapturedView({
    super.key,
    required this.equation,
    required this.onClose,
    required this.onRetake,
    required this.onContinue,
  });

  final DetectedEquation equation;
  final VoidCallback onClose;
  final VoidCallback onRetake;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0x99000000))),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: _GlassButton(
                icon: Icons.close_rounded,
                onTap: onClose,
                label: 'Close',
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: CaptureConfirmation(
            equation: equation,
            onRetake: onRetake,
            onContinue: onContinue,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.scannerBackground.withValues(alpha: 0.95),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MatheasyBrandAvatar(size: 110),
              const SizedBox(height: AppSpacing.lg),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(color: AppColors.white),
              ),
              const SizedBox(height: AppSpacing.xl),
              _GlassButton(
                icon: Icons.refresh_rounded,
                onTap: onRetry,
                label: 'Try again',
                size: 56,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
