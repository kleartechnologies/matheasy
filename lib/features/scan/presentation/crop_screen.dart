import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../application/scan_image_codec.dart';

/// Full-screen crop step between capture and recognition. The user frames just
/// the problem; the result is re-encoded to a compact JPEG (downscaled to
/// [_maxSide]px, quality 85) so uploads stay small.
///
/// Pops with the cropped [Uint8List] on confirm, or `null` if cancelled.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final CropController _controller = CropController();
  bool _processing = false;

  void _cancel() => Navigator.of(context).pop();

  void _confirm() {
    if (_processing) return;
    setState(() => _processing = true);
    // Fires _onCropped asynchronously with the cropped bytes.
    _controller.crop();
  }

  Future<void> _onCropped(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        // crop_your_image already returns a compact JPEG for JPEG input; only
        // pay for a re-decode/downscale isolate when the result is large or not
        // already JPEG (guards uploads while skipping the common camera case).
        final jpeg = isJpegBytes(croppedImage) &&
                croppedImage.lengthInBytes <= kScanDirectUploadMaxBytes
            ? croppedImage
            : await compute(encodeScanJpeg, croppedImage);
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
            _Header(onClose: _cancel),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Crop(
                  image: widget.imageBytes,
                  controller: _controller,
                  onCropped: _onCropped,
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
              onCancel: _cancel,
              onConfirm: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

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
          const SizedBox(width: 48), // balances the close button
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.processing,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool processing;
  final VoidCallback onCancel;
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
                  onPressed: processing ? null : onCancel,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 3,
                child: PrimaryButton(
                  label: processing
                      ? context.l10n.cropPreparing
                      : context.l10n.cropUsePhoto,
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
