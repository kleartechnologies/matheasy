import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';

/// Shows the cropped photo a problem was scanned from, so the student can see
/// what Matheasy actually read — most useful for figure-based problems
/// (geometry) and the couldn't-verify / tutor states, where the diagram carries
/// information the OCR'd text can't. Tapping opens a pinch-to-zoom full view.
///
/// Renders only when a scan image is present (camera / gallery). Typed problems
/// and history re-opens carry no bytes, so the card simply doesn't appear.
class ResultScanImage extends StatelessWidget {
  const ResultScanImage({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      onTap: () => _openFullScreen(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.image_outlined, size: 16, color: colors.textMuted),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'SCANNED PROBLEM',
                  style: AppTypography.label.copyWith(color: colors.textMuted),
                ),
                const Spacer(),
                Icon(Icons.zoom_out_map_rounded,
                    size: 16, color: colors.textMuted),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: Semantics(
              image: true,
              label: 'The problem you scanned',
              child: Container(
                width: double.infinity,
                color: colors.surfaceMuted,
                alignment: Alignment.center,
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.contain,
                  // A malformed/oversized capture must never crash the result
                  // screen — degrade to a small placeholder instead.
                  errorBuilder: (_, _, _) => Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Icon(Icons.broken_image_outlined,
                        color: colors.textMuted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (_, _, _) => _FullScreenImage(imageBytes: imageBytes),
      ),
    );
  }
}

/// A dismissible, pinch-to-zoom full-screen view of the scanned image.
class _FullScreenImage extends StatelessWidget {
  const _FullScreenImage({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: Image.memory(imageBytes, fit: BoxFit.contain),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
            right: AppSpacing.sm,
            child: Material(
              color: Colors.black.withValues(alpha: 0.4),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin convenience so callers don't repeat the null/padding boilerplate:
/// returns the card (with trailing spacing) when [imageBytes] is present, or an
/// empty box otherwise — safe to drop at the top of any result layout.
class ResultScanImageSlot extends StatelessWidget {
  const ResultScanImageSlot({super.key, required this.imageBytes});

  final Uint8List? imageBytes;

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ResultScanImage(imageBytes: bytes),
    );
  }
}
