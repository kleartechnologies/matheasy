import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matheasy/core/brand/brand.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/animations/floaty.dart';
import '../../../core/animations/pressable.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/monitoring/logging_service.dart';
import '../../../core/monitoring/perf_trace.dart';
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
import '../application/camera_warmup.dart';
import '../application/region_detector.dart';
import '../application/scan_image_codec.dart';
import '../application/scan_trace.dart';
import '../application/scanner_controller.dart';
import '../domain/detected_equation.dart';
import '../domain/math_text_scorer.dart';
import '../domain/scan_source.dart';
import '../domain/scan_state.dart';
import 'crop_screen.dart';
import 'manual_input_screen.dart';
import 'widgets/camera_viewport.dart';
import 'widgets/capture_confirmation.dart';
import 'widgets/processing_overlay.dart';
import 'widgets/scan_frame.dart';

/// The full-screen, immersive scanner. Pushed over the shell (no tab bar).
///
/// Deliberately calm: the live preview is a plain camera feed under static
/// white framing guides — no live OCR, no moving detection boxes, no
/// auto-capture. Nothing competes with the preview for the frame budget, and
/// nothing on screen chases what the camera thinks it sees. The student aims,
/// taps the shutter, adjusts the suggested crop, and only then does
/// recognition spend anything.
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

  /// True for the WHOLE capture→crop→recognize flow — from the moment a photo
  /// is handed to [_cropAndRecognize] until the crop is cancelled or
  /// recognition starts. `_capturing` only covers `takePicture()` and is
  /// cleared BEFORE the crop route opens; this flag is what keeps a second
  /// shutter or gallery tap from stacking a second crop screen on top.
  bool _busy = false;

  /// True for the whole time the native gallery picker is open. Disarms the
  /// shutter until the pick (and its crop→recognize flow) resolves, so a
  /// capture can't start behind the open picker and swallow the returning pick
  /// via the [_busy] guard.
  bool _picking = false;

  /// True while the app is backgrounded — guards against an in-flight camera
  /// init activating the session after a pause.
  bool _appPaused = false;

  /// Times the screen's own startup — mount → camera ready → first preview
  /// frame. Separate from the per-scan trace because it happens once per screen
  /// while a scan happens many times, and because "camera open" is its own
  /// latency target with its own fix (see [_initCamera]).
  final PerfTrace _openTrace = PerfTrace('scanner.open');
  bool _loggedOpen = false;

  // -- Post-capture analysis -------------------------------------------------

  /// On-device locator behind the crop screen's SUGGESTED crop. It runs only
  /// on a frozen capture — never against the live preview — and it only ever
  /// answers WHERE the maths is; OpenAI Vision remains the only thing that
  /// reads it.
  final RegionDetector _detector = createRegionDetector();

  /// The unmodified capture, kept so "Adjust" can re-open the crop screen on the
  /// full photo rather than on the cropped slice — cropping a crop would make
  /// the escape hatch narrower every time it was used.
  Uint8List? _originalBytes;
  ScanSource? _originalSource;

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
    // The frame the user actually sees the preview in — the honest "camera
    // open" number. `initialize()` returning is not the same thing: the texture
    // still has to reach the screen, and on a cold start that gap is real.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openTrace.mark('firstFrame');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    // The recogniser holds a native model; leaking one per scanner visit would
    // grow the app's memory every time the screen is opened.
    unawaited(_detector.dispose());
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
    _openTrace.begin('cameraInit');
    try {
      // Measured separately from `initialize()`: they are one stage to the user
      // but two very different fixes — enumeration is a platform-channel round
      // trip that could be cached or pre-warmed, initialisation is the sensor
      // actually spinning up and cannot be.
      final cameras = await _openTrace.measure(
          'cameraInit.enumerate', cachedAvailableCameras);
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
      );
      await _openTrace.measure('cameraInit.initialize', controller.initialize);
      // Bail if we unmounted or were backgrounded during init — otherwise we'd
      // activate a camera session while the app is in the background.
      if (!mounted || _appPaused) {
        await controller.dispose();
        return;
      }
      await _openTrace.measure('cameraInit.flashMode',
          () => controller.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off));
      setState(() {
        _camera = controller;
        _cameraError = null;
      });
      _openTrace.end('cameraInit', detail: ResolutionPreset.veryHigh.name);
      if (!_loggedOpen) {
        _loggedOpen = true;
        _openTrace.log();
      }
    } catch (error, stack) {
      _openTrace.end('cameraInit', detail: 'failed');
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

  /// Free-tier scan gate (spec §2/§10): a capped free user is sent to the
  /// EXISTING paywall BEFORE we spend a scan — so they never waste a capture.
  /// This client check is UX only; the server's `ScanQuotaExceeded` remains the
  /// authoritative backstop. Returns true when a scan may proceed.
  bool _allowScanOrPaywall() {
    if (ref.read(usageSnapshotProvider).canScan) return true;
    context.pushReplacement(AppRoutes.paywall, extra: PaywallTrigger.scanLimit);
    return false;
  }

  /// Shutter: capture from the live camera, then crop + recognize.
  Future<void> _shutter() async {
    final camera = _camera;
    if (_busy ||
        _capturing ||
        _picking ||
        camera == null ||
        !camera.value.isInitialized) {
      return;
    }
    if (!_allowScanOrPaywall()) return;
    final captureFailed = context.l10n.scanCaptureFailed;
    // The trace opens HERE — the shutter is the moment the user starts waiting,
    // so it is the only honest zero for "time to answer".
    final trace = ref.read(scanTraceProvider.notifier).start();
    setState(() => _capturing = true);
    // The shutter's answer to the user, delivered before any work starts. It is
    // the only part of a capture that is genuinely instant, and it is what makes
    // the rest of the wait feel like progress rather than a stall.
    unawaited(HapticFeedback.mediumImpact());
    Uint8List bytes;
    XFile file;
    try {
      // Split deliberately: `takePicture` is the sensor + encode, `readAsBytes`
      // is a round trip through a temp FILE on disk that exists only because the
      // plugin's API returns a path rather than bytes.
      file = await trace.measure('capture.takePicture', camera.takePicture);
      bytes = await trace.measure(
        'capture.readBytes',
        file.readAsBytes,
        detail: (b) => '${(b.lengthInBytes / 1024).round()}KB',
      );
    } catch (error) {
      LoggingService.warning('Capture failed: $error');
      _toast(captureFailed);
      return;
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
    await _cropAndRecognize(ScanSource.camera, bytes, path: file.path);
  }

  /// Pick from the gallery, then crop + recognize.
  Future<void> _gallery() async {
    if (_capturing || _busy || _picking) return;
    if (!_allowScanOrPaywall()) return;
    final galleryFailed = context.l10n.scanGalleryFailed;
    // Hold [_picking] for the WHOLE pick → crop → recognize flow so the shutter
    // stays disarmed while the native picker is up (see [_picking]).
    _picking = true;
    final trace = ref.read(scanTraceProvider.notifier).start();
    try {
      Uint8List bytes;
      String? path;
      try {
        // Human time (browsing the album), not machine time — traced so the
        // waterfall shows why a gallery scan's total dwarfs a camera scan's
        // without that being mistaken for a slow pipeline.
        final file = await trace.measure(
          'gallery.pick',
          () => _picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 2000,
            imageQuality: 90,
          ),
        );
        if (file == null) return; // cancelled
        path = file.path;
        bytes = await trace.measure(
          'gallery.readBytes',
          file.readAsBytes,
          detail: (b) => '${(b.lengthInBytes / 1024).round()}KB',
        );
      } catch (error) {
        LoggingService.warning('Gallery pick failed: $error');
        _toast(galleryFailed);
        return;
      }
      // Normalize to a decodable JPEG before the crop step: image_picker can
      // hand back bytes crop_your_image's decoder can't read (e.g. an
      // un-transcoded GIF), which would hang the crop screen on an infinite
      // spinner. encodeScanJpeg decodes + re-encodes and falls back to the raw
      // bytes on failure, so it never throws into the flow.
      //
      // Skipped when the pick is ALREADY a JPEG — the case `imageQuality: 90`
      // produces for almost every photo in a camera roll. The decoder can read
      // it as-is, `maxWidth: 2000` has already bounded it, and the crop screen
      // re-encodes the RESULT anyway if it comes back over the direct-upload
      // limit. Without this guard a gallery scan paid for two full Dart
      // decode/resize/encode cycles: this one, and then the crop's.
      if (!isJpegBytes(bytes)) {
        bytes = await trace.measure(
          'gallery.normalizeJpeg',
          () => compute(encodeScanJpeg, bytes),
          detail: (b) => '${(b.lengthInBytes / 1024).round()}KB',
        );
        path = null; // the file on disk is no longer what we hold
      }
      await _cropAndRecognize(ScanSource.gallery, bytes, path: path);
    } finally {
      _picking = false;
    }
  }

  /// Manual entry — opens the math-keyboard screen. The typed problem flows
  /// into the same recognize → solve pipeline as a scan (see ManualInputScreen).
  void _type() => context.push(AppRoutes.manualInput);

  /// Opens the crop screen on the frozen capture, then recognizes whatever the
  /// user confirms.
  ///
  /// The crop screen opens IMMEDIATELY — the on-device analysis behind the
  /// suggested crop starts in the background at the same moment and lands as a
  /// pre-framed rectangle when it resolves, so the student is never waiting on
  /// a heuristic. The suggestion is only ever a starting point: every corner
  /// stays draggable, and nothing is cropped without the user pressing
  /// Continue. Recognition — the first paid step — runs only after that press.
  ///
  /// On a device with no on-device locator the crop screen simply opens with
  /// the default rectangle: same flow, no suggestion.
  Future<void> _cropAndRecognize(
    ScanSource source,
    Uint8List bytes, {
    String? path,
  }) async {
    // `_busy` spans the whole flow and is cleared in `finally` on every exit —
    // cancel or recognize — so returning to the live preview re-enables
    // capture, while a stray second tap can't stack another crop screen.
    if (!mounted || _busy) return;
    _busy = true;
    _originalBytes = bytes;
    _originalSource = source;
    final trace = ref.read(scanTraceProvider);
    try {
      // Fire-and-forget into the crop screen; not awaited here, so the push
      // below happens on the very next frame after the shutter.
      final suggested = trace?.measure(
            'crop.suggest',
            () => _suggestCropArea(bytes, path),
            detail: (r) => r?.toString() ?? 'none',
          ) ??
          _suggestCropArea(bytes, path);
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CropScreen(
            imageBytes: bytes,
            suggestedArea: suggested,
            trace: trace,
          ),
        ),
      );
      if (!mounted) return;
      if (cropped == null) {
        // Retake / close — this capture is abandoned, and so is the waterfall
        // that was timing it.
        ref.read(scanTraceProvider.notifier).finish();
        return;
      }
      unawaited(ref
          .read(analyticsServiceProvider)
          .logEvent(AnalyticsEvent.imageCropped(source: source.name)));
      await _controller.recognize(source, imageBytes: cropped);
    } finally {
      _busy = false;
    }
  }

  /// Where the maths is in a captured still, as a crop-screen suggestion in the
  /// image's own (EXIF-upright) pixel space. Null when there is nothing to
  /// suggest — no file for ML Kit to read, no text found, or a region so weak
  /// the padded crop would be the whole frame anyway.
  Future<ui.Rect?> _suggestCropArea(Uint8List bytes, String? path) async {
    try {
      // No file on disk (a re-encoded gallery pick) — nothing ML Kit can read.
      if (path == null) return null;
      // Started together, not one after the other. Reading the blocks is native
      // ML Kit work and measuring the image is a decode on the codec's own
      // threads; neither reads the other's output, and on a 12MP still each is
      // long enough that running them in sequence doubled this step for nothing.
      final sizeFuture = _decodedSize(bytes);
      final blocks = await _detector.readBlocks(path);
      final size = await sizeFuture;
      if (size.isEmpty || blocks.isEmpty) return null;
      final region = regionFromBlocks(blocks, size);
      if (region.isEmpty) return null;
      final rect = cropRectFor(region);
      if (rect == const ui.Rect.fromLTRB(0, 0, 1, 1)) return null;
      // cropRectFor speaks normalised display coordinates; the crop editor
      // wants pixels of the (EXIF-upright) decoded image — the same space ML
      // Kit reported the blocks in.
      return ui.Rect.fromLTRB(
        rect.left * size.width,
        rect.top * size.height,
        rect.right * size.width,
        rect.bottom * size.height,
      );
    } catch (error) {
      // The suggestion is an assist; failing to make one must cost nothing.
      LoggingService.warning('Crop suggestion failed: $error');
      return null;
    }
  }

  /// The image's size as DISPLAYED — Flutter's codec applies the EXIF rotation,
  /// which is the same space ML Kit reports boxes in and the same space
  /// [cropScanJpeg] bakes to before cutting.
  Future<Size> _decodedSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size =
          Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (error) {
      LoggingService.warning('Could not size capture: $error');
      return Size.zero;
    }
  }

  /// Re-crop after recognition: re-open the crop screen on the ORIGINAL photo
  /// and re-read whatever the user frames.
  ///
  /// This costs a second recognition round trip, which is why it is a button
  /// and not the default. No suggestion is passed — the user is here precisely
  /// because they want a different framing than the last one.
  Future<void> _adjustCrop() async {
    final bytes = _originalBytes;
    final source = _originalSource;
    if (bytes == null || source == null || _busy) return;
    _busy = true;
    try {
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CropScreen(imageBytes: bytes),
        ),
      );
      if (cropped == null || !mounted) return; // cancelled — keep the read
      await _controller.recognize(source, imageBytes: cropped);
    } finally {
      _busy = false;
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Back to the live preview.
  void _retake() => _controller.retake();

  /// The "Solve" commit point. Re-checks the scan quota (the same gate as
  /// capture): a free user out of scans is sent to the paywall instead of
  /// consuming a solve.
  void _onContinue() {
    if (_allowScanOrPaywall()) _controller.confirm();
  }

  /// Opens the math editor pre-filled with the recognized LaTeX (spec §3). The
  /// correction is folded back into the SAME capture, so re-solving goes through
  /// the already-charged scan — no second charge. The user then verifies the
  /// corrected equation on the sheet and taps Solve.
  Future<void> _editEquation(DetectedEquation equation) async {
    final corrected = await context.push<String?>(
      AppRoutes.manualInput,
      extra: ManualInputArgs(initialLatex: equation.latex, editMode: true),
    );
    if (!mounted || corrected == null) return;
    _controller.applyEdit(corrected);
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
              onOpenSettings: () => unawaited(openAppSettings()),
              onType: _type,
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
          onType: _type,
        ),
      ScanRecognizing() =>
        const ProcessingOverlay(key: ValueKey('recognizing')),
      ScanCaptured(:final equation) => _CapturedView(
          key: const ValueKey('captured'),
          equation: equation,
          onClose: () => context.pop(),
          onRetake: _retake,
          onContinue: _onContinue,
          onEdit: () => unawaited(_editEquation(equation)),
          onAdjust: _originalBytes == null
              ? null
              : () => unawaited(_adjustCrop()),
        ),
      ScanComplete() => const SizedBox.shrink(key: ValueKey('complete')),
      ScanQuotaExceeded() =>
        const SizedBox.shrink(key: ValueKey('quota')),
      ScanError(:final kind) => _ErrorView(
          key: const ValueKey('error'),
          kind: kind,
          onRetry: _retake,
          onTypeItIn: _type,
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
            context.l10n.scanHintLineUp,
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
                  child: ScanFrame(),
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
            label: context.l10n.scanCloseScanner,
          ),
          const Spacer(),
          Text(
            context.l10n.scanTitle,
            style: AppTypography.title.copyWith(color: AppColors.white),
          ),
          const Spacer(),
          _GlassButton(
            icon: flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            onTap: onFlash,
            label: flashOn ? context.l10n.scanFlashOff : context.l10n.scanFlashOn,
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
              context.l10n.scanBrandHint,
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
            label: context.l10n.scanGallery,
            onTap: onGallery,
          ),
          _ShutterButton(enabled: canCapture, onTap: onShutter),
          _LabeledControl(
            icon: Icons.keyboard_rounded,
            label: context.l10n.actionTypeIt,
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
      label: context.l10n.scanTakePhoto,
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
                // Solid interactive emerald, no halo — the ring carries the
                // shutter's presence, not a glow.
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled ? AppColors.primaryAction : AppColors.white,
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
    required this.onEdit,
    this.onAdjust,
  });

  final DetectedEquation equation;
  final VoidCallback onClose;
  final VoidCallback onRetake;
  final VoidCallback onContinue;
  final VoidCallback onEdit;
  final VoidCallback? onAdjust;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Deliberately not a token: a neutral black scrim over the frozen camera
        // frame. Any brand tint here would recolour the paper the user just
        // photographed and misrepresent what was scanned.
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
            onEdit: onEdit,
            onAdjust: onAdjust,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

/// The honest recognition-failure state (spec §9). Each [ScanErrorKind] gets its
/// own voice + next action — errors give direction, never a dead end:
/// * couldn't-recognize → "hard to read — try again or type it in";
/// * offline → "you're offline", and it says what still works;
/// * generic → a calm retry.
/// Every kind offers a "Type it in" escape to the math keyboard so the user is
/// never stuck behind a camera that can't read the page.
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    super.key,
    required this.kind,
    required this.onRetry,
    required this.onTypeItIn,
  });

  final ScanErrorKind kind;
  final VoidCallback onRetry;
  final VoidCallback onTypeItIn;

  ({IconData icon, String title, String body, String retryLabel}) _copy(
          BuildContext context) =>
      switch (kind) {
        ScanErrorKind.couldntRecognize => (
            icon: Icons.image_search_rounded,
            title: context.l10n.scanErrorRecognizeTitle,
            body: context.l10n.scanErrorRecognizeBody,
            retryLabel: context.l10n.scanTryAgain,
          ),
        ScanErrorKind.offline => (
            icon: Icons.wifi_off_rounded,
            title: context.l10n.scanErrorOfflineTitle,
            body: context.l10n.scanErrorOfflineBody,
            retryLabel: context.l10n.actionRetry,
          ),
        ScanErrorKind.generic => (
            icon: Icons.refresh_rounded,
            title: context.l10n.scanErrorGenericTitle,
            body: context.l10n.scanErrorGenericBody,
            retryLabel: context.l10n.scanTryAgain,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final copy = _copy(context);
    return ColoredBox(
      color: AppColors.scannerBackground.withValues(alpha: 0.95),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MatheasyBrandAvatar(),
                const SizedBox(height: AppSpacing.lg),
                Icon(copy.icon,
                    color: Colors.white.withValues(alpha: 0.85), size: 28),
                const SizedBox(height: AppSpacing.md),
                Text(
                  copy.title,
                  textAlign: TextAlign.center,
                  style: AppTypography.title.copyWith(color: AppColors.white),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  copy.body,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium
                      .copyWith(color: Colors.white.withValues(alpha: 0.75)),
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PillButton(
                      icon: Icons.keyboard_rounded,
                      label: context.l10n.scanTypeItIn,
                      onTap: onTypeItIn,
                      filled: false,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _PillButton(
                      icon: Icons.refresh_rounded,
                      label: copy.retryLabel,
                      onTap: onRetry,
                      filled: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact pill CTA for the scanner's dark overlays (the error state). Filled =
/// primary (emerald), outlined = secondary — both legible on the dark scrim.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.95,
        borderRadius: AppRadius.pillRadius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: filled
                ? AppColors.primaryAction
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: AppRadius.pillRadius,
            border: filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.3)),
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
    );
  }
}
