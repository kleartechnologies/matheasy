import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'numi_expression.dart';

export 'numi_expression.dart';

/// Numi — the Matheasy mascot.
///
/// This is the ONLY mascot API screens should use. Today it renders a
/// custom-painted placeholder that faithfully echoes the design's blue robot.
///
/// ### Swapping to Rive later
/// The public API ([NumiMascot] with `expression` + `size`) is intentionally
/// stable. To migrate, replace the body of [build] with a `RiveAnimation.asset`
/// and map [expression] onto a state-machine input. No call site changes, and
/// no screen ever imports `rive` — the dependency stays quarantined here.
class NumiMascot extends StatelessWidget {
  const NumiMascot({
    super.key,
    this.expression = NumiExpression.happy,
    this.size = 96,
    this.semanticLabel = 'Numi mascot',
  });

  final NumiExpression expression;
  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox.square(
        dimension: size,
        // --- Rive swap point: replace CustomPaint with RiveAnimation here. ---
        child: CustomPaint(
          painter: _NumiPainter(expression),
          isComplex: true,
        ),
      ),
    );
  }
}

/// Custom-painted placeholder. Geometry ported from the design's `Numi.dc.html`
/// on a 200×200 base canvas, then scaled to the requested [NumiMascot.size].
class _NumiPainter extends CustomPainter {
  const _NumiPainter(this.expression);

  final NumiExpression expression;

  // Palette (kept local so the mascot renders identically in light/dark).
  // Head blues track the brand ramp so Numi reads as native to Matheasy:
  // lighter #3B82F6 → Brand Blue #2563EB → Deep Blue #1D4ED8.
  static const _headTop = Color(0xFF3B82F6);
  static const _headMid = Color(0xFF2563EB);
  static const _headBottom = Color(0xFF1D4ED8);
  static const _plateTop = Color(0xFFF4F8FF);
  static const _plateBottom = Color(0xFFE4EDFF);
  static const _ink = Color(0xFF243562);
  static const _gold = Color(0xFFFFD54A);
  static const _cheek = Color(0x6BFF8E76);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 200.0;
    canvas.save();
    canvas.scale(scale);

    _drawAntenna(canvas);
    _drawEars(canvas);
    _drawHead(canvas);
    _drawFacePlate(canvas);
    _drawEyes(canvas);
    _drawCheeks(canvas);
    _drawMouth(canvas);
    if (expression == NumiExpression.wave) _drawHand(canvas);

    canvas.restore();
  }

  void _drawAntenna(Canvas canvas) {
    final stem = Paint()..color = _headTop;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(97, 24, 6, 26),
        const Radius.circular(3),
      ),
      stem,
    );
    canvas.drawCircle(
      const Offset(100, 17),
      12,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFE79A), _gold],
        ).createShader(Rect.fromCircle(center: const Offset(100, 17), radius: 12)),
    );
    // Soft glow.
    canvas.drawCircle(
      const Offset(100, 17),
      16,
      Paint()..color = _gold.withValues(alpha: 0.25),
    );
  }

  void _drawEars(Canvas canvas) {
    final ear = Paint()..color = _headTop;
    for (final left in [8.0, 176.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 99, 16, 44),
          const Radius.circular(8),
        ),
        ear,
      );
    }
  }

  void _drawHead(Canvas canvas) {
    final rect =
        RRect.fromRectAndRadius(const Rect.fromLTWH(16, 46, 168, 150),
            const Radius.circular(56));
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_headTop, _headMid, _headBottom],
        stops: [0, 0.62, 1],
      ).createShader(rect.outerRect);
    canvas.drawRRect(rect, paint);

    // Gloss highlight.
    canvas.drawOval(
      const Rect.fromLTWH(46, 58, 100, 34),
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );
  }

  void _drawFacePlate(Canvas canvas) {
    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(44, 76, 112, 96),
      const Radius.circular(40),
    );
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_plateTop, _plateBottom],
      ).createShader(rect.outerRect);
    canvas.drawRRect(rect, paint);
  }

  void _drawEyes(Canvas canvas) {
    const leftEye = Offset(86, 116);
    const rightEye = Offset(114, 116);
    final arc = expression == NumiExpression.celebrate;
    final wink = expression == NumiExpression.wink;

    _eye(canvas, leftEye, arcStyle: arc);
    if (wink) {
      // Closed wink line for the right eye.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: rightEye, width: 26, height: 7),
          const Radius.circular(4),
        ),
        Paint()..color = _ink,
      );
    } else {
      _eye(canvas, rightEye, arcStyle: arc);
    }
  }

  void _eye(Canvas canvas, Offset center, {required bool arcStyle}) {
    if (arcStyle) {
      // Happy closed "⌒" arch.
      final rect = Rect.fromCenter(center: center, width: 26, height: 22);
      canvas.drawArc(
        rect,
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawOval(
        Rect.fromCenter(center: center, width: 24, height: 28),
        Paint()..color = _ink,
      );
      canvas.drawCircle(
        center.translate(-4, -5),
        4,
        Paint()..color = Colors.white.withValues(alpha: 0.92),
      );
    }
  }

  void _drawCheeks(Canvas canvas) {
    for (final cx in [76.0, 124.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, 138), width: 15, height: 9),
        Paint()..color = _cheek,
      );
    }
  }

  void _drawMouth(Canvas canvas) {
    const center = Offset(100, 150);
    switch (expression) {
      case NumiExpression.celebrate:
      case NumiExpression.wave:
        // Open, cheerful mouth with a tongue.
        final mouth = RRect.fromRectAndCorners(
          Rect.fromCenter(center: center, width: 36, height: 23),
          topLeft: const Radius.circular(7),
          topRight: const Radius.circular(7),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
        );
        canvas.drawRRect(mouth, Paint()..color = _ink);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: center.translate(0, 6), width: 18, height: 11),
            const Radius.circular(6),
          ),
          Paint()..color = const Color(0xFFFF8C7A),
        );
      case NumiExpression.thinking:
        // Small "o".
        canvas.drawCircle(
          center,
          8,
          Paint()
            ..color = _ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5,
        );
      case NumiExpression.idle:
      case NumiExpression.happy:
      case NumiExpression.wink:
        // Smile "U".
        canvas.drawArc(
          Rect.fromCenter(center: center, width: 40, height: 22),
          0,
          math.pi,
          false,
          Paint()
            ..color = _ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );
    }
  }

  void _drawHand(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(166, 96, 34, 34),
        topLeft: const Radius.circular(17),
        topRight: const Radius.circular(17),
        bottomLeft: const Radius.circular(17),
        bottomRight: const Radius.circular(8),
      ),
      Paint()..color = _headTop,
    );
  }

  @override
  bool shouldRepaint(covariant _NumiPainter oldDelegate) =>
      oldDelegate.expression != expression;
}
