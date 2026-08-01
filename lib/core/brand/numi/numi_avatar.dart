import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../extensions/context_extensions.dart';
import 'numi_orb_painter.dart';
import 'numi_spec.dart';

/// **Numi** — the official AI identity of Matheasy.
///
/// A green orb with a white four-point star and a soft ambient glow, drawn
/// entirely with gradients and paths (see [NumiOrbPainter]) so it is resolution
/// independent at every size the design specifies — 24 px in a toolbar up to
/// 256 px as a hero — and at any size in between.
///
/// Numi is **the tutor**; Matheasy is **the app**. Use this wherever the AI is
/// speaking, thinking or listening — chat turns, the typing indicator, tutor
/// entry points, AI-written insight. Where the *product* is speaking (empty
/// states, errors, the launcher icon, celebration moments) the brand mark
/// stays: the design is explicit that "the app icon stays Matheasy — Numi
/// lives inside the product".
///
/// ```dart
/// const NumiAvatar(size: 40);                              // chat turn
/// const NumiAvatar(size: 40, state: NumiState.thinking);   // typing
/// const NumiAvatar(size: 116, state: NumiState.idle);      // tutor hero
/// ```
///
/// The four [NumiState]s are the official ones and nothing else: Numi has no
/// face and no expression, so everything it conveys is carried by light,
/// breath and timing. Motion is disabled automatically when the platform asks
/// for reduced motion — the orb then holds its resting frame, still fully
/// itself.
class NumiAvatar extends StatefulWidget {
  const NumiAvatar({
    super.key,
    this.size = 96,
    this.state = NumiState.idle,
    this.surface,
    this.animate = true,
    this.semanticLabel = 'Numi',
  });

  /// Edge length of the (square) orb in logical pixels — this is D.
  ///
  /// The glow deliberately extends beyond it; §02 reserves 0.5 × D of clear
  /// space around the orb for exactly that, so give it room rather than
  /// clipping it.
  final double size;

  /// What Numi is doing. Defaults to [NumiState.idle] — "patiently waiting".
  final NumiState state;

  /// Which of the two official environments this sits in. Defaults to the
  /// ambient theme brightness; pass [NumiSurface.brandGreen] explicitly when
  /// Numi is placed on an emerald field.
  final NumiSurface? surface;

  /// Set false to hold the resting frame (the platform's reduced-motion
  /// setting does this on its own).
  final bool animate;

  /// Accessibility label. Numi is a proper noun and is not translated.
  final String semanticLabel;

  @override
  State<NumiAvatar> createState() => _NumiAvatarState();
}

class _NumiAvatarState extends State<NumiAvatar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<NumiFrame> _frame = ValueNotifier<NumiFrame>(
    NumiFrame.still(),
  );

  /// The free-running clock the looping animations read.
  Duration _elapsed = Duration.zero;

  /// …and when the current state was entered, for the one-shot `responding`.
  Duration _stateEnteredAt = Duration.zero;

  bool _reduceMotion = false;

  bool get _moving => widget.animate && !_reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(NumiAvatar old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _stateEnteredAt = _elapsed;
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// Start or stop the ticker to match the current settings, and make sure the
  /// painted frame is up to date even while stopped.
  void _sync() {
    if (_moving) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
      _frame.value = NumiFrame.still(glowScale: _glowRamp);
    }
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    _frame.value = NumiFrame.at(
      time: _seconds(elapsed),
      state: widget.state,
      stateAge: _seconds(elapsed - _stateEnteredAt),
      glowScale: _glowRamp,
    );
  }

  /// The size ramp (§07) — a small orb pulls its glow back so it stays a crisp
  /// shape rather than a green smudge. When motion is off, the state's own
  /// glow multiplier is folded in here so listening/thinking still read as
  /// leaning in; it is the same property, simply held still.
  double get _glowRamp {
    final ramp = NumiSpec.glowRampFor(widget.size);
    return _moving ? ramp : ramp * NumiStateSpec.of(widget.state).glowScale;
  }

  static double _seconds(Duration d) =>
      d.inMicroseconds / Duration.microsecondsPerSecond;

  @override
  Widget build(BuildContext context) {
    final surface = widget.surface ??
        (context.isDark ? NumiSurface.dark : NumiSurface.light);
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: ValueListenableBuilder<NumiFrame>(
            valueListenable: _frame,
            builder: (context, frame, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: NumiOrbPainter(
                frame: frame,
                starRatio: NumiSpec.starRatioFor(widget.size),
                surface: surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
