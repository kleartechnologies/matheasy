import 'dart:async' show unawaited;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/l10n_extension.dart';
import '../../../core/monitoring/perf_trace.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../application/scan_image_codec.dart';

/// Full-screen crop step between capture and recognition. The user frames just
/// the problem; the result is re-encoded to a compact JPEG (downscaled to
/// [kScanMaxSide]px, quality 85) so uploads stay small.
///
/// When [suggestedArea] resolves to a rectangle, the crop rect is pre-framed to
/// it — but only as a starting point. It is applied once, only while the user
/// hasn't touched the crop, and every handle stays live: the suggestion assists,
/// it never decides. Rotation (header, top-right) re-encodes the source a
/// quarter turn at a time for photos taken sideways.
///
/// Pops with the cropped [Uint8List] on Continue, or `null` on retake/close.
class CropScreen extends StatefulWidget {
  const CropScreen({
    super.key,
    required this.imageBytes,
    this.suggestedArea,
    this.trace,
  });

  final Uint8List imageBytes;

  /// Where the on-device locator thinks the problem sits, in the image's own
  /// (EXIF-upright) pixel space. A future because the analysis runs in the
  /// background while this screen is already opening — the student never waits
  /// on it. Null (or a null result) means "no suggestion": the default crop
  /// rect is shown and the flow is purely manual.
  final Future<Rect?>? suggestedArea;

  /// The in-flight scan trace, so the crop's machine time (the native crop plus
  /// the optional re-encode isolate) is separable from its human time. Null
  /// outside a traced scan — the screen is fully usable without it.
  final PerfTrace? trace;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final CropController _controller = CropController();
  late Uint8List _bytes = widget.imageBytes;
  bool _processing = false;
  bool _rotating = false;

  /// True once the crop editor has parsed the image and laid out its rect —
  /// `CropController.area` can only be applied after this.
  bool _ready = false;

  /// The resolved suggestion, held until the editor is ready for it.
  Rect? _suggestion;
  bool _suggestionApplied = false;

  /// True from the first user gesture on the crop rect. A suggestion that
  /// resolves late must not yank a rectangle the student is already dragging —
  /// once they've touched it, the crop is theirs.
  bool _userMoved = false;
  bool _applyingSuggestion = false;

  @override
  void initState() {
    super.initState();
    widget.suggestedArea?.then((rect) {
      if (!mounted || rect == null || rect.isEmpty) return;
      _suggestion = rect;
      _maybeApplySuggestion();
    });
  }

  void _onStatusChanged(CropStatus status) {
    if (status == CropStatus.ready) {
      _ready = true;
      _maybeApplySuggestion();
    }
  }

  void _onMoved(Rect viewportRect, Rect imageRect) {
    // The editor also reports its own initial layout and our programmatic
    // suggestion through this callback; neither is the user taking over.
    if (_ready && !_applyingSuggestion) _userMoved = true;
  }

  void _maybeApplySuggestion() {
    final rect = _suggestion;
    if (rect == null || !_ready || _suggestionApplied || _userMoved) return;
    _suggestionApplied = true;
    _applyingSuggestion = true;
    _controller.area = rect;
    _applyingSuggestion = false;
  }

  void _cancel() => Navigator.of(context).pop();

  /// Quarter-turn rotate for a photo taken sideways. Runs the re-encode off the
  /// UI isolate; the editor shows its own progress indicator while it re-parses
  /// the rotated bytes. Any suggestion is void afterwards — it was computed in
  /// the old orientation's pixel space.
  Future<void> _rotate() async {
    if (_processing || _rotating) return;
    setState(() => _rotating = true);
    _userMoved = true;
    try {
      final rotated = await (widget.trace?.measure(
            'crop.rotate',
            () => compute(rotateScanJpeg, _bytes),
          ) ??
          compute(rotateScanJpeg, _bytes));
      if (!mounted) return;
      _bytes = rotated;
      _ready = false;
      _controller.image = rotated;
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  void _confirm() {
    if (_processing || _rotating) return;
    setState(() => _processing = true);
    // Everything from the tap to the pop is machine time; the rest of
    // `crop.screen` is the user framing the shot.
    widget.trace?.begin('crop.execute');
    // Fires _onCropped asynchronously with the cropped bytes.
    _controller.crop();
  }

  Future<void> _onCropped(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        // crop_your_image already returns a compact JPEG for JPEG input; only
        // pay for a re-decode/downscale isolate when the result is large or not
        // already JPEG (guards uploads while skipping the common camera case).
        final needsReencode = !isJpegBytes(croppedImage) ||
            croppedImage.lengthInBytes > kScanDirectUploadMaxBytes;
        widget.trace?.end('crop.execute',
            detail: '${(croppedImage.lengthInBytes / 1024).round()}KB, '
                're-encode: $needsReencode');
        final jpeg = needsReencode
            ? await (widget.trace?.measure(
                  'crop.reencode',
                  () => compute(encodeScanJpeg, croppedImage),
                  detail: (b) => '${(b.lengthInBytes / 1024).round()}KB',
                ) ??
                compute(encodeScanJpeg, croppedImage))
            : croppedImage;
        if (mounted) Navigator.of(context).pop(jpeg);
      case CropFailure():
        if (!mounted) return;
        setState(() => _processing = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.cropFailed)),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scannerBackground,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onClose: _cancel,
              onRotate: _rotating ? null : () => unawaited(_rotate()),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Crop(
                  // `_bytes`, not `widget.imageBytes`: after a rotate the
                  // editor was re-fed through `_controller.image`, and the
                  // widget parameter must agree with it or a later
                  // didChangeDependencies re-parse would revert the rotation.
                  image: _bytes,
                  controller: _controller,
                  onCropped: _onCropped,
                  onStatusChanged: _onStatusChanged,
                  onMoved: _onMoved,
                  baseColor: AppColors.scannerBackground,
                  // Neutral, untinted mask: the area outside the crop is still
                  // the user's photo, and a brand tint would misrepresent it.
                  maskColor: AppColors.black.withValues(alpha: 0.55),
                  radius: AppRadius.md,
                  interactive: true,
                  // The corner handles are an interactive control, not brand
                  // art — primaryAction, never the identity emerald.
                  cornerDotBuilder: (size, edgeAlignment) =>
                      const DotControl(color: AppColors.primaryAction),
                  progressIndicator: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.primaryLight),
                  ),
                ),
              ),
            ),
            _Footer(
              processing: _processing,
              onRetake: _cancel,
              onConfirm: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose, required this.onRotate});

  final VoidCallback onClose;
  final VoidCallback? onRotate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: AppColors.white),
            tooltip: context.l10n.cropCancel,
          ),
          const Spacer(),
          Text(
            context.l10n.cropTitle,
            style: AppTypography.title.copyWith(color: AppColors.white),
          ),
          const Spacer(),
          IconButton(
            onPressed: onRotate,
            icon: const Icon(Icons.rotate_90_degrees_cw_rounded,
                color: AppColors.white),
            tooltip: context.l10n.cropRotate,
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.processing,
    required this.onRetake,
    required this.onConfirm,
  });

  final bool processing;
  final VoidCallback onRetake;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.cropInstruction,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall
                .copyWith(color: Colors.white.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: context.l10n.scanRetake,
                  icon: Icons.refresh_rounded,
                  onPressed: processing ? null : onRetake,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 3,
                child: PrimaryButton(
                  label: processing
                      ? context.l10n.cropPreparing
                      : context.l10n.actionContinue,
                  trailingIcon: Icons.arrow_forward_rounded,
                  onPressed: processing ? null : onConfirm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
