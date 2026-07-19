import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../core/animations/pressable.dart';
import '../../../../../../core/extensions/context_extensions.dart';
import '../../../../../../core/localization/l10n_extension.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../core/theme/app_durations.dart';
import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/theme/app_typography.dart';
import '../../../../domain/animation/column_multiplication.dart';

/// A Photomath-style animated COLUMN MULTIPLICATION tutorial (e.g. `72 × 6`):
/// the digits are laid out as a grid, the operands highlight, a bold callout
/// shows the sub-calculation, and dashed arrows carry the digits up (carry) and
/// down (answer line). Driven by the verified [ColumnMultiplication] model.
class ColumnMultiplicationView extends StatefulWidget {
  const ColumnMultiplicationView({
    super.key,
    required this.model,
    this.onAskStep,
  });

  final ColumnMultiplication model;

  /// Optional "Ask Matheasy about this step".
  final ValueChanged<int>? onAskStep;

  @override
  State<ColumnMultiplicationView> createState() =>
      _ColumnMultiplicationViewState();
}

class _ColumnMultiplicationViewState extends State<ColumnMultiplicationView>
    with SingleTickerProviderStateMixin {
  // --- grid geometry (logical px) -------------------------------------------
  static const double _fontSize = 42;
  static const double _cellW = 44;
  static const double _digitH = 54;
  static const double _carryH = 30;
  static const double _topY = _carryH;
  static const double _multY = _topY + _digitH;
  static const double _lineY = _multY + _digitH + 4;
  static const double _resultY = _lineY + 10;
  static const double _gridBottom = _resultY + _digitH;
  static const double _calloutY = _gridBottom + 18;
  static const double _totalH = _calloutY + 56; // fully contains a 1-line callout

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppDurations.medium,
  )..forward();
  int _index = 0;
  Timer? _timer;
  bool _playing = false;

  int get _cols => widget.model.resultWidth;
  double get _gridW => _cols * _cellW;
  int get _last => widget.model.steps.length - 1;
  bool get _isLast => _index == _last;

  /// Left edge of the (centred) grid within a stage of width [stageW].
  double _gridLeft(double stageW) => (stageW - _gridW) / 2;

  /// Centre x of column [col] (0 = ones, rightmost) within a stage of [stageW].
  double _colX(int col, double stageW) =>
      _gridLeft(stageW) + (_cols - 1 - col) * _cellW + _cellW / 2;

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() => _index = i.clamp(0, _last));
    _c.forward(from: 0);
    if (_playing) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_isLast) {
      setState(() => _playing = false);
      return;
    }
    _timer = Timer(const Duration(milliseconds: 1500), () => _go(_index + 1));
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      if (_isLast) _go(0);
      _schedule();
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.model.steps[_index];
    final prevCallout = _index > 0 ? widget.model.steps[_index - 1].callout : null;
    final calloutIsNew = step.callout != null && step.callout != prevCallout;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepIndicator(index: _index, total: widget.model.steps.length),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final stageW =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 340.0;
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) => SizedBox(
                width: stageW,
                height: _totalH,
                child: _buildStage(context, step, calloutIsNew, stageW),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        _Caption(text: step.caption),
        const SizedBox(height: AppSpacing.md),
        _Controls(
          index: _index,
          isLast: _isLast,
          playing: _playing,
          onPrev: () => _go(_index - 1),
          onNext: () => _go(_index + 1),
          onReplay: () => _go(0),
          onTogglePlay: _togglePlay,
        ),
        if (widget.onAskStep != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _AskButton(onTap: () => widget.onAskStep!(_index)),
        ],
      ],
    );
  }

  Widget _buildStage(
      BuildContext context, ColMulStep step, bool calloutIsNew, double stageW) {
    final t = Curves.easeOut.transform(_c.value);
    final colors = context.colors;
    final ink = colors.textPrimary;
    const coral = AppColors.accentCoral;
    const blue = AppColors.info;
    final green =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final m = widget.model;

    final children = <Widget>[];

    // --- the dashed arrow (callout → emphasised cell), behind the digits ------
    if (step.callout != null) {
      final from = Offset(stageW / 2, _calloutY - 2);
      Offset? to;
      if (step.emphResultCol != null) {
        to = Offset(_colX(step.emphResultCol!, stageW), _resultY + _digitH - 4);
      } else if (step.emphCarryCol != null) {
        to = Offset(_colX(step.emphCarryCol!, stageW), _carryH - 2);
      }
      if (to != null) {
        children.add(Positioned.fill(
          child: CustomPaint(
            painter: _DashArrowPainter(from: from, to: to, reveal: t, color: blue),
          ),
        ));
      }
    }

    // --- carry digits (small, above the top row) ------------------------------
    step.carryDigits.forEach((col, digit) {
      final isNew = step.emphCarryCol == col;
      children.add(_cell(
        cx: _colX(col, stageW),
        top: 0,
        height: _carryH,
        text: '$digit',
        fontSize: 22,
        color: blue,
        box: isNew ? blue.withValues(alpha: 0.18) : null,
        opacity: isNew ? t : 1,
        scale: isNew ? 0.7 + 0.3 * t : 1,
      ));
    });

    // --- top number ------------------------------------------------------------
    final top = m.topDigits;
    for (var i = 0; i < top.length; i++) {
      final col = top.length - 1 - i;
      children.add(_cell(
        cx: _colX(col, stageW),
        top: _topY,
        text: '${top[i]}',
        fontSize: _fontSize,
        color: ink,
        box: step.highlightTopCols.contains(col)
            ? coral.withValues(alpha: 0.20)
            : null,
      ));
    }

    // --- multiplier row (× + the single digit) --------------------------------
    children.add(_cell(
      cx: _colX(0, stageW) - _cellW,
      top: _multY,
      text: '×',
      fontSize: _fontSize,
      color: colors.textSecondary,
    ));
    children.add(_cell(
      cx: _colX(0, stageW),
      top: _multY,
      text: '${m.multiplier}',
      fontSize: _fontSize,
      color: ink,
      box: step.highlightMultiplier ? coral.withValues(alpha: 0.20) : null,
    ));

    // --- the rule --------------------------------------------------------------
    children.add(Positioned(
      left: _gridLeft(stageW),
      top: _lineY,
      child: Container(width: _gridW, height: 3, color: ink),
    ));

    // --- answer digits ---------------------------------------------------------
    for (var col = 0; col < step.resultDigits.length; col++) {
      final d = step.resultDigits[col];
      if (d == null) continue;
      final isNew = step.emphResultCol == col;
      children.add(_cell(
        cx: _colX(col, stageW),
        top: _resultY,
        text: '$d',
        fontSize: _fontSize,
        color: isNew ? green : ink,
        box: isNew ? green.withValues(alpha: 0.22) : null,
        opacity: isNew ? t : 1,
        scale: isNew ? 0.7 + 0.3 * t : 1,
      ));
    }

    // --- callout pill ----------------------------------------------------------
    if (step.callout != null) {
      children.add(Positioned(
        left: 0,
        right: 0,
        top: _calloutY,
        child: Center(
          child: Opacity(
            opacity: calloutIsNew ? t : 1,
            child: _CalloutPill(text: step.callout!, background: coral),
          ),
        ),
      ));
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _cell({
    required double cx,
    required double top,
    required String text,
    required double fontSize,
    required Color color,
    Color? box,
    double opacity = 1,
    double scale = 1,
    double height = _digitH,
  }) {
    Widget child = Container(
      width: _cellW,
      height: height,
      alignment: Alignment.center,
      decoration: box == null
          ? null
          : BoxDecoration(color: box, borderRadius: BorderRadius.circular(7)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
    if (scale != 1) child = Transform.scale(scale: scale, child: child);
    if (opacity != 1) child = Opacity(opacity: opacity.clamp(0, 1), child: child);
    return Positioned(left: cx - _cellW / 2, top: top, child: child);
  }
}

/// A dashed, gently-bowed arrow from [from] up to [to], drawn to [reveal] (0→1).
class _DashArrowPainter extends CustomPainter {
  _DashArrowPainter({
    required this.from,
    required this.to,
    required this.reveal,
    required this.color,
  });

  final Offset from;
  final Offset to;
  final double reveal;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = reveal.clamp(0.0, 1.0);
    if (r <= 0.02) return;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final dir = to - from;
    final len = dir.distance;
    if (len < 2) return;
    final perp = Offset(dir.dy, -dir.dx) / len;
    final ctrl =
        Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2) + perp * 14;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy);

    final metric = path.computeMetrics().first;
    final drawn = metric.length * r;
    const dash = 8.0, gap = 5.0;
    var d = 0.0;
    while (d < drawn) {
      canvas.drawPath(metric.extractPath(d, math.min(d + dash, drawn)), stroke);
      d += dash + gap;
    }
    if (r > 0.5) {
      final tan = metric.getTangentForOffset(drawn);
      if (tan != null) {
        const s = 9.0;
        final tip = tan.position;
        final a = tan.angle;
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(tip.dx + math.cos(a + math.pi - 0.5) * s,
                tip.dy + math.sin(a + math.pi - 0.5) * s)
            ..lineTo(tip.dx + math.cos(a + math.pi + 0.5) * s,
                tip.dy + math.sin(a + math.pi + 0.5) * s)
            ..close(),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashArrowPainter old) =>
      old.reveal != reveal || old.from != from || old.to != to;
}

class _CalloutPill extends StatelessWidget {
  const _CalloutPill({required this.text, required this.background});

  final String text;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: background.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fill = context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Column(
      children: [
        Text(
          context.l10n.resultStepOfUpper(index + 1, total),
          style: AppTypography.label.copyWith(color: fill),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xxs),
              Container(
                width: i == index ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i <= index ? fill : context.colors.surfaceMuted,
                  borderRadius: AppRadius.pillRadius,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: AppTypography.bodyLarge.copyWith(color: context.colors.textSecondary),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.index,
    required this.isLast,
    required this.playing,
    required this.onPrev,
    required this.onNext,
    required this.onReplay,
    required this.onTogglePlay,
  });

  final int index;
  final bool isLast;
  final bool playing;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onReplay;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circle(
          context,
          icon: Icons.arrow_back_rounded,
          label: context.l10n.resultPreviousStep,
          onTap: index > 0 ? onPrev : null,
        ),
        const SizedBox(width: AppSpacing.md),
        _circle(
          context,
          icon: isLast
              ? Icons.replay_rounded
              : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          label: context.l10n.resultPlayWalkthroughShort,
          filled: true,
          onTap: isLast ? onReplay : onTogglePlay,
        ),
        const SizedBox(width: AppSpacing.md),
        _circle(
          context,
          icon: Icons.arrow_forward_rounded,
          label: context.l10n.resultNextStep,
          onTap: isLast ? null : onNext,
        ),
      ],
    );
  }

  Widget _circle(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap ?? () {},
        scale: enabled ? 0.92 : 1,
        borderRadius: AppRadius.pillRadius,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: filled ? AppColors.primaryAction : colors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 24,
              color: filled ? AppColors.white : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _AskButton extends StatelessWidget {
  const _AskButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Semantics(
      button: true,
      label: context.l10n.tutorAsk,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline_rounded, size: 16, color: emerald),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              context.l10n.tutorAsk,
              style: AppTypography.caption.copyWith(color: emerald),
            ),
          ],
        ),
      ),
    );
  }
}
