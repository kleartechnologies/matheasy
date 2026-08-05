import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../domain/detected_region.dart';

/// The live box drawn around the maths the on-device detector can see.
///
/// It is a viewfinder, not a verdict: it says "the camera can read something
/// here", never "this is what it says". Nothing about it gates the scan — the
/// shutter works identically whether or not a box is showing — so a missed
/// detection costs the user nothing but the reassurance.
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.region,
    required this.sourceSize,
  });

  final DetectedRegion region;

  /// The preview frame's size as DISPLAYED (portrait-corrected), needed to undo
  /// the cover-fit crop. See [projectCover].
  final Size sourceSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = region.isNotEmpty && !sourceSize.isEmpty;
        final rect = visible
            ? projectCover(region.bounds, sourceSize, constraints.biggest)
            : Rect.zero;
        return Stack(
          children: [
            AnimatedPositioned(
              // Fast, but not instant. The detector's box jitters by a few
              // pixels between frames even on a perfectly still phone, and
              // snapping to every reading reads as a nervous, broken overlay.
              // A short tween absorbs the jitter while still keeping up with a
              // real pan.
              duration: AppDurations.fast,
              curve: Curves.easeOutCubic,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: AnimatedOpacity(
                duration: AppDurations.fast,
                opacity: visible ? 1 : 0,
                child: const _DetectionBox(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Four emerald corner brackets plus a whisper of a full border.
///
/// Corners rather than a solid rectangle because a closed box over a live
/// preview reads as a mask — as though everything outside it were excluded —
/// and the padding applied at crop time means it is not.
class _DetectionBox extends StatelessWidget {
  const _DetectionBox();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _DetectionBoxPainter()),
    );
  }
}

class _DetectionBoxPainter extends CustomPainter {
  // primaryLight is the emerald built to survive on a dark surface; primary
  // itself is brand art only and would sink into the preview.
  static const Color _emerald = AppColors.primaryLight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _emerald.withValues(alpha: 0.35),
    );

    // Corner length scales with the box so a small detection doesn't get
    // brackets that meet in the middle.
    final arm = (size.shortestSide * 0.22).clamp(10.0, 28.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = _emerald;

    final path = Path()
      ..moveTo(rect.left, rect.top + arm)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + arm, rect.top)
      ..moveTo(rect.right - arm, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + arm)
      ..moveTo(rect.right, rect.bottom - arm)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right - arm, rect.bottom)
      ..moveTo(rect.left + arm, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.bottom - arm);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DetectionBoxPainter oldDelegate) => false;
}
