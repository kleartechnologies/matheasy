import 'package:flutter/material.dart';

/// The scanning frame: four static white corner guides.
///
/// White on purpose, not emerald: the guides are guidance, and the brand's
/// interactive emerald is reserved for actions (the shutter, Continue,
/// progress). White at 90% reads on a dark desk; the soft dark under-stroke is
/// what keeps it readable on the other common background — a white worksheet.
///
/// The guides never move, resize, animate, or follow the equation. They are a
/// composition aid, like the level line in a camera app — a still reference the
/// student aligns the page against, not an indicator chasing what the camera
/// thinks it sees.
class ScanFrame extends StatelessWidget {
  const ScanFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _CornerGuidePainter(),
      size: Size.infinite,
    );
  }
}

class _CornerGuidePainter extends CustomPainter {
  const _CornerGuidePainter();

  static const double _stroke = 3.5;
  static const double _arm = 44;
  static const double _cornerRadius = 14;

  @override
  void paint(Canvas canvas, Size size) {
    // Inset so the rounded stroke caps stay inside the painted bounds.
    const inset = (_stroke + 3) / 2;
    final frame = Rect.fromLTWH(0, 0, size.width, size.height).deflate(inset);

    final path = Path()
      ..addPath(_corner(frame, left: true, top: true), Offset.zero)
      ..addPath(_corner(frame, left: false, top: true), Offset.zero)
      ..addPath(_corner(frame, left: true, top: false), Offset.zero)
      ..addPath(_corner(frame, left: false, top: false), Offset.zero);

    // A slightly wider, blurred dark stroke underneath — the "shadow" that
    // keeps a white guide visible over white paper without hardening it into
    // an outline.
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke + 3
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
      ..color = Colors.black.withValues(alpha: 0.4);
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.9);

    canvas.drawPath(path, shadow);
    canvas.drawPath(path, guide);
  }

  /// One L-shaped corner guide with a rounded elbow, built from the corner of
  /// [frame] pointed at by [left]/[top].
  Path _corner(Rect frame, {required bool left, required bool top}) {
    final x0 = left ? frame.left : frame.right;
    final y0 = top ? frame.top : frame.bottom;
    final dx = left ? 1.0 : -1.0;
    final dy = top ? 1.0 : -1.0;
    return Path()
      ..moveTo(x0, y0 + dy * _arm)
      ..lineTo(x0, y0 + dy * _cornerRadius)
      ..quadraticBezierTo(x0, y0, x0 + dx * _cornerRadius, y0)
      ..lineTo(x0 + dx * _arm, y0);
  }

  @override
  bool shouldRepaint(covariant _CornerGuidePainter oldDelegate) => false;
}
