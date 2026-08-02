import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/math_semantics.dart';
import '../../../scan/domain/scan_anchor.dart';
import '../../domain/tutor_models.dart';

/// Numi pointing at the student's own page.
///
/// This draws the ORIGINAL scanned photo and paints gestures over it — no
/// screenshot, no re-render, no AI-generated picture of what the page might have
/// looked like. What lights up under the highlight is the student's own
/// handwriting, which is the whole reason the overlay is trustworthy: it can be
/// checked against the paper on the desk.
///
/// Two invariants hold everything up:
///
/// * **Only anchors the app derived may be pointed at.** An action naming an id
///   that isn't on this page is dropped here, exactly as it was dropped
///   server-side. Coordinates are never taken from a model.
/// * **The overlay asserts nothing.** It changes where a student looks, not what
///   is true. There is no arithmetic in this file, so it cannot be wrong about
///   the maths — only about where to point, which the gate above prevents.
///
/// Motion is one [AnimationController] repainting a [CustomPainter] directly
/// (`repaint:`), so a running gesture costs no widget rebuilds and no layout —
/// it is a paint-only loop, which is what keeps it at 60fps behind a scrolling
/// chat.
class TutorPageOverlay extends StatefulWidget {
  const TutorPageOverlay({
    super.key,
    required this.imageBytes,
    required this.anchors,
    required this.actions,
    this.maxHeight = 260,
    this.borderRadius,
  });

  /// The scanned page, as the student photographed it.
  final Uint8List imageBytes;

  /// Every place on it the app located.
  final List<ScanAnchor> anchors;

  /// What this turn is pointing at.
  final List<TutorAction> actions;

  /// The tallest the page may render in the chat. The photo keeps its aspect
  /// ratio inside this — a squashed page is an unreadable page.
  final double maxHeight;

  final BorderRadius? borderRadius;

  /// One full breath of a looping gesture.
  static const Duration cycle = Duration(milliseconds: 2600);

  /// Resolve actions against the page, dropping anything that points nowhere.
  ///
  /// Public and pure so the rule can be tested without pumping a frame — it is
  /// the single most important line of defence in the visual layer, and it is
  /// worth being able to assert on directly.
  static List<ResolvedGesture> resolve(
    List<TutorAction> actions,
    List<ScanAnchor> anchors,
  ) {
    if (actions.isEmpty || anchors.isEmpty) return const [];
    final byId = {for (final a in anchors) a.id: a};
    final out = <ResolvedGesture>[];
    for (final action in actions) {
      final anchor = byId[action.target];
      // An id nobody located. Dropping it costs a gesture; drawing it would
      // circle the wrong part of the student's homework.
      if (anchor == null) continue;
      out.add(ResolvedGesture(action: action, anchor: anchor));
    }
    return out;
  }

  @override
  State<TutorPageOverlay> createState() => _TutorPageOverlayState();
}

/// The scanned page a conversation is about: the photo plus everywhere on it
/// the app located something.
///
/// Both halves are required — a photo with no anchors has nothing to point at,
/// and anchors with no photo have nothing to point *on*. [from] returns null
/// unless the conversation has both, which is why typed problems and history
/// re-opens simply never show an overlay instead of showing an empty one.
@immutable
class TutorScannedPage {
  const TutorScannedPage({required this.imageBytes, required this.anchors});

  final Uint8List imageBytes;
  final List<ScanAnchor> anchors;

  static TutorScannedPage? from(TutorLaunchContext? context) {
    final problem = context?.problem;
    final bytes = problem?.scanImageBytes;
    if (problem == null || bytes == null || bytes.isEmpty) return null;
    if (problem.anchors.isEmpty) return null;
    return TutorScannedPage(imageBytes: bytes, anchors: problem.anchors);
  }
}

/// An action matched to the anchor it points at.
@immutable
class ResolvedGesture {
  const ResolvedGesture({required this.action, required this.anchor});

  final TutorAction action;
  final ScanAnchor anchor;

  TutorActionType get type => action.type;
  MathRole get role => action.role;
  Rect get rect => anchor.rect;
}

class _TutorPageOverlayState extends State<TutorPageOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TutorPageOverlay.cycle,
  );

  ui.Image? _image;
  Object? _decodeError;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(TutorPageOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.imageBytes, widget.imageBytes)) {
      _image?.dispose();
      _image = null;
      _decode();
    }
    // A new gesture restarts the loop, so a reply that points somewhere new
    // reads as a fresh gesture rather than joining one mid-breath.
    if (old.actions != widget.actions) _sync();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
      _sync();
    } catch (error) {
      // A page that won't decode simply doesn't appear. The reply's words stand
      // on their own — the overlay is an enrichment, never the message.
      if (mounted) setState(() => _decodeError = error);
    }
  }

  /// Start, stop or freeze the loop to match the current gestures and the
  /// learner's motion preference.
  void _sync() {
    final gestures = TutorPageOverlay.resolve(widget.actions, widget.anchors);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (gestures.isEmpty || _image == null) {
      _controller.stop();
      return;
    }
    if (reduceMotion) {
      // Reduce Motion does not mean "no highlight" — it means "no movement".
      // Parking at the end of the cycle shows the gesture fully drawn: the same
      // information, delivered at rest.
      _controller.stop();
      _controller.value = 1;
      return;
    }
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null || _decodeError != null) {
      return const SizedBox.shrink();
    }
    final gestures = TutorPageOverlay.resolve(widget.actions, widget.anchors);
    final radius = widget.borderRadius ?? BorderRadius.circular(AppRadius.md);

    return Semantics(
      // The screen reader gets the same message the sighted student gets: WHERE
      // to look, described by place and role. A VoiceOver user hearing "the
      // angle at vertex B is highlighted" is being taught the same thing.
      label: _semanticLabel(gestures),
      image: true,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: AspectRatio(
              aspectRatio: image.width / image.height,
              child: CustomPaint(
                painter: TutorPageOverlayPainter(
                  image: image,
                  gestures: gestures,
                  progress: _controller,
                  colors: context.colors,
                  isDark: context.isDark,
                  // Wired to the ONE signal that carries both the OS setting and
                  // the app's own toggle (see `app.dart`).
                  highContrast: MediaQuery.highContrastOf(context),
                ),
                // Painting is cheap and the loop repaints anyway; caching the
                // layer would only duplicate the photo in memory.
                isComplex: true,
                willChange: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _semanticLabel(List<ResolvedGesture> gestures) {
    if (gestures.isEmpty) return 'Your scanned problem';
    final places = gestures.map((g) => g.anchor.semanticLabel).join('; ');
    return 'Your scanned problem. Numi is pointing at: $places';
  }
}

/// Paints the page and the gestures over it.
///
/// Separated from the widget and given a plain constructor so a test can drive
/// it at a fixed [progress] and compare frames — animation you cannot pin is
/// animation you cannot golden-test.
class TutorPageOverlayPainter extends CustomPainter {
  TutorPageOverlayPainter({
    required this.image,
    required this.gestures,
    required this.progress,
    required this.colors,
    required this.isDark,
    this.highContrast = false,
  }) : super(repaint: progress);

  final ui.Image image;
  final List<ResolvedGesture> gestures;
  final Animation<double> progress;
  final AppSemanticColors colors;
  final bool isDark;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    if (gestures.isEmpty) return;

    final t = progress.value;
    // Everything that dims the page runs FIRST, so a highlight drawn afterwards
    // stays at full strength inside its own spotlight.
    for (final gesture in gestures) {
      if (gesture.type == TutorActionType.fade ||
          gesture.type == TutorActionType.focusRegion) {
        _paintScrim(canvas, size, gesture, t);
      }
    }
    for (final gesture in gestures) {
      _paintGesture(canvas, size, gesture, t);
    }
  }

  /// The colour a gesture wears — the shared teaching vocabulary, so the page
  /// overlay and the equation highlight agree on what "the unknown" looks like.
  Color _color(ResolvedGesture gesture) =>
      gesture.role.color(colors, isDark: isDark);

  /// Stroke width. High contrast thickens every line: a 2px hairline over
  /// pencil on white paper is exactly what a low-vision learner cannot see.
  /// Public so a test can assert the a11y setting actually reaches the ink.
  double get strokeWidth => highContrast ? 5.0 : 2.6;

  /// Fill opacity, likewise raised for high contrast.
  double get _fillAlpha => highContrast ? 0.42 : 0.24;

  Rect _pixels(ResolvedGesture gesture, Size size) => Rect.fromLTRB(
        gesture.rect.left * size.width,
        gesture.rect.top * size.height,
        gesture.rect.right * size.width,
        gesture.rect.bottom * size.height,
      );

  void _paintGesture(Canvas canvas, Size size, ResolvedGesture g, double t) {
    final rect = _pixels(g, size);
    final color = _color(g);
    switch (g.type) {
      case TutorActionType.highlight:
        _paintHighlight(canvas, rect, color, t);
      case TutorActionType.circle:
        _paintCircle(canvas, rect, color, t);
      case TutorActionType.underline:
        _paintUnderline(canvas, rect, color, t);
      case TutorActionType.glow:
        _paintGlow(canvas, rect, color, t);
      case TutorActionType.pulse:
        _paintPulse(canvas, rect, color, t);
      case TutorActionType.zoom:
        _paintZoom(canvas, size, rect, color, t);
      case TutorActionType.drawArrow:
        _paintArrow(canvas, size, rect, color, t);
      case TutorActionType.drawBracket:
        _paintBracket(canvas, rect, color, t);
      case TutorActionType.flash:
        _paintFlash(canvas, rect, color, t);
      // Both dim the page, which already happened in the scrim pass; what is
      // left is the outline that says which region survived the dimming.
      case TutorActionType.fade:
      case TutorActionType.focusRegion:
        _paintOutline(canvas, rect, color, t);
    }
  }

  // ---- Individual gestures -------------------------------------------------

  /// A marker-pen wash that sweeps left to right, as a hand would draw it.
  void _paintHighlight(Canvas canvas, Rect rect, Color color, double t) {
    final grown = rect.inflate(rect.height * 0.16);
    final sweep = _ease(_in(t, 0, 0.45));
    final drawn = Rect.fromLTWH(
      grown.left,
      grown.top,
      grown.width * sweep,
      grown.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(drawn, Radius.circular(grown.height * 0.28)),
      Paint()..color = color.withValues(alpha: _fillAlpha * _hold(t)),
    );
  }

  /// A ring drawn the way a teacher's pen draws one: starting past the top,
  /// sweeping round, and overshooting the join slightly.
  void _paintCircle(Canvas canvas, Rect rect, Color color, double t) {
    final oval = rect.inflate(rect.shortestSide * 0.35);
    final sweep = _ease(_in(t, 0, 0.55)) * 6.6; // a little past 2π — the overlap
    canvas.drawArc(
      oval,
      -1.9,
      sweep,
      false,
      Paint()
        ..color = color.withValues(alpha: _hold(t))
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth,
    );
  }

  void _paintUnderline(Canvas canvas, Rect rect, Color color, double t) {
    final y = rect.bottom + rect.height * 0.16;
    final width = rect.width * _ease(_in(t, 0, 0.4));
    canvas.drawLine(
      Offset(rect.left, y),
      Offset(rect.left + width, y),
      Paint()
        ..color = color.withValues(alpha: _hold(t))
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth,
    );
  }

  /// A soft halo that breathes. Blur is the point — a glow with a hard edge is
  /// just a badly-drawn box.
  void _paintGlow(Canvas canvas, Rect rect, Color color, double t) {
    final breath = 0.55 + 0.45 * _breathe(t);
    final grown = rect.inflate(rect.shortestSide * 0.25);
    canvas.drawRRect(
      RRect.fromRectAndRadius(grown, Radius.circular(grown.shortestSide * 0.3)),
      Paint()
        ..color = color.withValues(alpha: 0.5 * breath)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.6
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, highContrast ? 3 : 6),
    );
  }

  /// Attention without alarm: the outline swells and settles, never blinks.
  void _paintPulse(Canvas canvas, Rect rect, Color color, double t) {
    final scale = 1 + 0.09 * _breathe(t);
    final grown = Rect.fromCenter(
      center: rect.center,
      width: rect.width * scale + rect.shortestSide * 0.3,
      height: rect.height * scale + rect.shortestSide * 0.3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(grown, Radius.circular(grown.shortestSide * 0.28)),
      Paint()
        ..color = color.withValues(alpha: 0.55 + 0.45 * _breathe(t))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  /// Magnifies the region — by re-drawing THAT PART OF THE PHOTO larger, not by
  /// substituting a rendering of what the app thinks is written there. Small
  /// fiddly marks (a superscript 2, a degree sign) are exactly the ones a
  /// student misreads, so the pixels have to be the real ones.
  void _paintZoom(Canvas canvas, Size size, Rect rect, Color color, double t) {
    final grow = 1 + 1.1 * _ease(_in(t, 0, 0.5));
    final dst = Rect.fromCenter(
      center: rect.center,
      width: rect.width * grow,
      height: rect.height * grow,
    );
    final scaleX = image.width / size.width;
    final scaleY = image.height / size.height;
    final src = Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    );
    final radius = Radius.circular(dst.shortestSide * 0.22);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(dst, radius));
    // A plate behind it, so the magnified crop doesn't blend into the page it
    // is sitting on top of.
    canvas.drawRect(dst, Paint()..color = isDark ? Colors.black : Colors.white);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(dst, radius),
      Paint()
        ..color = color.withValues(alpha: _hold(t))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  /// A pen coming in from the side of the page, as a tutor's hand would.
  void _paintArrow(Canvas canvas, Size size, Rect rect, Color color, double t) {
    final tip = Offset(rect.left - rect.width * 0.12, rect.center.dy);
    // Approach from whichever margin is nearer, so the arrow never crosses the
    // work it is pointing at.
    final fromLeft = rect.center.dx > size.width / 2;
    final tail = Offset(
      fromLeft ? tip.dx - size.width * 0.22 : rect.right + size.width * 0.22,
      tip.dy - size.height * 0.12,
    );
    final head = fromLeft ? tip : Offset(rect.right + rect.width * 0.12, tip.dy);
    final travel = _ease(_in(t, 0, 0.5));
    final now = Offset.lerp(tail, head, travel)!;

    final paint = Paint()
      ..color = color.withValues(alpha: _hold(t))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    canvas.drawLine(tail, now, paint);

    final direction = now - tail;
    final length = direction.distance;
    if (length < 1) return;
    final unit = direction / length;
    final normal = Offset(-unit.dy, unit.dx);
    final barb = rect.shortestSide * 0.6 + 6;
    canvas.drawPath(
      Path()
        ..moveTo(now.dx, now.dy)
        ..lineTo(
          now.dx - unit.dx * barb + normal.dx * barb * 0.5,
          now.dy - unit.dy * barb + normal.dy * barb * 0.5,
        )
        ..moveTo(now.dx, now.dy)
        ..lineTo(
          now.dx - unit.dx * barb - normal.dx * barb * 0.5,
          now.dy - unit.dy * barb - normal.dy * barb * 0.5,
        ),
      paint,
    );
  }

  /// "All of this together is one thing" — a brace under the whole span.
  void _paintBracket(Canvas canvas, Rect rect, Color color, double t) {
    final y = rect.bottom + rect.height * 0.22;
    final drop = rect.height * 0.3;
    final grow = _ease(_in(t, 0, 0.45));
    final half = rect.width / 2 * grow;
    final cx = rect.center.dx;
    canvas.drawPath(
      Path()
        ..moveTo(cx - half, y)
        ..quadraticBezierTo(cx - half, y + drop, cx - half * 0.12, y + drop)
        ..lineTo(cx, y + drop * 1.5)
        ..lineTo(cx + half * 0.12, y + drop)
        ..quadraticBezierTo(cx + half, y + drop, cx + half, y),
      Paint()
        ..color = color.withValues(alpha: _hold(t))
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth,
    );
  }

  /// The lightest possible "here": one quick wash that fades.
  void _paintFlash(Canvas canvas, Rect rect, Color color, double t) {
    final alpha = (1 - _in(t, 0, 0.35)) * _fillAlpha * 1.4;
    if (alpha <= 0.01) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(rect.shortestSide * 0.2),
        Radius.circular(rect.shortestSide * 0.25),
      ),
      Paint()..color = color.withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
  }

  void _paintOutline(Canvas canvas, Rect rect, Color color, double t) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(rect.shortestSide * 0.22),
        Radius.circular(rect.shortestSide * 0.28),
      ),
      Paint()
        ..color = color.withValues(alpha: _hold(t))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  /// Dim the whole page except the region — the "everything else can wait" move.
  ///
  /// [TutorActionType.focusRegion] cuts a soft-edged hole (a spotlight);
  /// [TutorActionType.fade] cuts a plain one and dims less, because it is about
  /// quieting the surroundings rather than staging the region.
  void _paintScrim(Canvas canvas, Size size, ResolvedGesture g, double t) {
    final rect = _pixels(g, size).inflate(_pixels(g, size).shortestSide * 0.3);
    final spotlight = g.type == TutorActionType.focusRegion;
    final depth = (spotlight ? 0.62 : 0.4) * _ease(_in(t, 0, 0.4));
    final hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide * 0.3)),
      );
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      hole,
    );
    canvas.drawPath(
      scrim,
      Paint()
        ..color = Colors.black.withValues(alpha: depth)
        ..maskFilter = spotlight
            ? const MaskFilter.blur(BlurStyle.normal, 8)
            : null,
    );
  }

  // ---- Timing --------------------------------------------------------------

  /// Progress of a sub-interval of the cycle, clamped to 0–1.
  double _in(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  double _ease(double v) => Curves.easeOutCubic.transform(v.clamp(0.0, 1.0));

  /// A gesture draws in, holds, then eases out just before the loop restarts —
  /// so a repeat reads as a second gesture rather than a jump cut.
  double _hold(double t) => t < 0.85 ? 1 : 1 - _ease(_in(t, 0.85, 1)) * 0.85;

  /// 0 → 1 → 0 across the cycle, smoothly. The breathing every "alive" gesture
  /// shares, so two of them on one page stay in sympathy instead of fighting.
  double _breathe(double t) =>
      Curves.easeInOut.transform((1 - (t * 2 - 1).abs()).clamp(0.0, 1.0));

  @override
  bool shouldRepaint(TutorPageOverlayPainter old) =>
      old.image != image ||
      old.gestures != gestures ||
      old.highContrast != highContrast ||
      old.isDark != isDark ||
      old.colors != colors;
}
