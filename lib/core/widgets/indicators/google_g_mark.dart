import 'package:flutter/material.dart';

/// The official multi-colour Google "G" mark, drawn from Google's own 18×18
/// sign-in-button SVG geometry (btn_google, Google Identity branding
/// guidelines) so the shape and colours are reproduced verbatim.
///
/// This is a third-party brand mark: the four colours are Google's, fixed by
/// their guidelines, and deliberately NOT theme tokens. Per those guidelines
/// the coloured G sits on a light surface; on dark surfaces callers should
/// place it on a white plate (see [GoogleGMark.plated]).
class GoogleGMark extends StatelessWidget {
  const GoogleGMark({super.key, this.size = 18});

  /// The G rendered on a white circular plate, for dark button surfaces —
  /// mirrors Google's own dark-theme button, which keeps the G on white.
  static Widget plated({double size = 18}) => Container(
        padding: EdgeInsets.all(size * 0.18),
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: GoogleGMark(size: size),
      );

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _GoogleGPainter(),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  // Google's brand colours — fixed by their guidelines, not ours to theme.
  static const Color _blue = Color(0xFF4285F4);
  static const Color _green = Color(0xFF34A853);
  static const Color _yellow = Color(0xFFFBBC05);
  static const Color _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    // Paths below are the official SVG's, in its 18×18 viewBox.
    final scale = size.shortestSide / 18;
    canvas.scale(scale, scale);
    final paint = Paint()..style = PaintingStyle.fill;

    // Blue — right arm and crossbar.
    paint.color = _blue;
    canvas.drawPath(
      Path()
        ..moveTo(17.64, 9.2)
        ..cubicTo(17.64, 8.563, 17.583, 7.949, 17.476, 7.36)
        ..lineTo(9, 7.36)
        ..lineTo(9, 10.841)
        ..lineTo(13.844, 10.841)
        ..cubicTo(13.635, 11.966, 13.001, 12.919, 12.048, 13.558)
        ..lineTo(12.048, 15.816)
        ..lineTo(14.956, 15.816)
        ..cubicTo(16.658, 14.249, 17.64, 11.942, 17.64, 9.2)
        ..close(),
      paint,
    );

    // Green — bottom arc.
    paint.color = _green;
    canvas.drawPath(
      Path()
        ..moveTo(9, 18)
        ..cubicTo(11.43, 18, 13.467, 17.194, 14.956, 15.82)
        ..lineTo(12.048, 13.561)
        ..cubicTo(11.242, 14.101, 10.211, 14.421, 9, 14.421)
        ..cubicTo(6.656, 14.421, 4.672, 12.837, 3.964, 10.71)
        ..lineTo(0.957, 10.71)
        ..lineTo(0.957, 13.042)
        ..cubicTo(2.438, 15.983, 5.482, 18, 9, 18)
        ..close(),
      paint,
    );

    // Yellow — left arc.
    paint.color = _yellow;
    canvas.drawPath(
      Path()
        ..moveTo(3.964, 10.71)
        ..cubicTo(3.784, 10.17, 3.682, 9.593, 3.682, 9)
        ..cubicTo(3.682, 8.407, 3.784, 7.83, 3.964, 7.29)
        ..lineTo(3.964, 4.958)
        ..lineTo(0.957, 4.958)
        ..cubicTo(0.347, 6.173, 0, 7.548, 0, 9)
        ..cubicTo(0, 10.452, 0.348, 11.827, 0.957, 13.042)
        ..lineTo(3.964, 10.71)
        ..close(),
      paint,
    );

    // Red — top arc.
    paint.color = _red;
    canvas.drawPath(
      Path()
        ..moveTo(9, 3.58)
        ..cubicTo(10.321, 3.58, 11.508, 4.034, 12.44, 4.925)
        ..lineTo(15.022, 2.345)
        ..cubicTo(13.463, 0.891, 11.426, 0, 9, 0)
        ..cubicTo(5.482, 0, 2.438, 2.017, 0.957, 4.958)
        ..lineTo(3.964, 7.29)
        ..cubicTo(4.672, 5.163, 6.656, 3.58, 9, 3.58)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleGPainter oldDelegate) => false;
}
