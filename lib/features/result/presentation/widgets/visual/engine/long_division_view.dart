import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../../core/animations/pressable.dart';
import '../../../../../../core/extensions/context_extensions.dart';
import '../../../../../../core/localization/l10n_extension.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../core/theme/app_durations.dart';
import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/theme/app_typography.dart';
import '../../../../domain/animation/long_division.dart';

/// A Photomath-style LONG DIVISION tutorial (e.g. `156 ÷ 4`): the classic
/// bracket worksheet built beat-by-beat — divide, multiply, subtract, bring
/// down. Driven by the verified [LongDivision] model.
class LongDivisionView extends StatefulWidget {
  const LongDivisionView({super.key, required this.model, this.onAskStep});

  final LongDivision model;
  final ValueChanged<int>? onAskStep;

  @override
  State<LongDivisionView> createState() => _LongDivisionViewState();
}

class _LongDivisionViewState extends State<LongDivisionView>
    with SingleTickerProviderStateMixin {
  static const double _fontSize = 34;
  static const double _cellW = 38;
  static const double _rowH = 46;
  static const double _bracketGap = 14;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppDurations.medium,
  )..forward();
  int _index = 0;
  Timer? _timer;
  bool _playing = false;

  LongDivision get _m => widget.model;
  int get _last => _m.steps.length - 1;
  bool get _isLast => _index == _last;

  double get _divisorW => _m.divisorDigits.length * _cellW;
  double get _dividendW => _m.cols * _cellW;
  double get _contentW => _divisorW + _bracketGap + _dividendW;
  double get _gridH => _m.rows * _rowH;
  double get _calloutY => _gridH + 18;
  double get _totalH => _calloutY + 54;

  double _stageLeft(double stageW) => (stageW - _contentW) / 2;
  double _dividendLeft(double stageW) =>
      _stageLeft(stageW) + _divisorW + _bracketGap;
  double _colX(int col, double stageW) =>
      _dividendLeft(stageW) + col * _cellW + _cellW / 2;
  double _rowY(int row) => row * _rowH;

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
    _timer = Timer(const Duration(milliseconds: 1600), () => _go(_index + 1));
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
    final step = _m.steps[_index];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepIndicator(index: _index, total: _m.steps.length),
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
                child: _buildStage(context, step, stageW),
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

  Widget _buildStage(BuildContext context, DivStep step, double stageW) {
    final t = Curves.easeOut.transform(_c.value);
    final colors = context.colors;
    final ink = colors.textPrimary;
    const coral = AppColors.accentCoral;
    final green =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final children = <Widget>[];

    // bracket — a horizontal rule over the dividend + a vertical bar at its left
    final bx = _dividendLeft(stageW) - 6;
    children.add(Positioned(
      left: bx,
      top: _rowY(1),
      child: Container(width: _dividendW + 8, height: 3, color: ink),
    ));
    children.add(Positioned(
      left: bx,
      top: _rowY(1),
      child: Container(width: 3, height: _gridH - _rowY(1), color: ink),
    ));

    // divisor (left of the bracket, on the dividend row)
    final dd = _m.divisorDigits;
    for (var i = 0; i < dd.length; i++) {
      children.add(_cell(
        cx: _stageLeft(stageW) + i * _cellW + _cellW / 2,
        top: _rowY(1),
        text: '${dd[i]}',
        color: colors.textSecondary,
      ));
    }

    // dividend (row 1)
    for (var c = 0; c < _m.dividendDigits.length; c++) {
      children.add(_cell(
        cx: _colX(c, stageW),
        top: _rowY(1),
        text: '${_m.dividendDigits[c]}',
        color: ink,
      ));
    }

    // subtraction rules
    for (final ln in _m.lines) {
      if (ln.revealAt > _index) continue;
      final left = _colX(ln.leftCol, stageW) - _cellW / 2 + 3;
      final right = _colX(ln.rightCol, stageW) + _cellW / 2 - 3;
      children.add(Positioned(
        left: left,
        top: _rowY(ln.row) + 1,
        child: Container(width: right - left, height: 2.5, color: ink),
      ));
    }

    // digit marks (quotient / product / difference / brought-down)
    for (final mk in _m.marks) {
      if (mk.revealAt > _index) continue;
      final isNew = mk.revealAt == _index;
      final color = switch (mk.kind) {
        DivMarkKind.quotient => green,
        DivMarkKind.broughtDown => coral,
        _ => ink,
      };
      for (var i = 0; i < mk.digits.length; i++) {
        final col = mk.rightCol - (mk.digits.length - 1 - i);
        children.add(_cell(
          cx: _colX(col, stageW),
          top: _rowY(mk.row),
          text: '${mk.digits[i]}',
          color: color,
          opacity: isNew ? t : 1,
          scale: isNew ? 0.7 + 0.3 * t : 1,
        ));
      }
    }

    // callout
    if (step.callout != null) {
      children.add(Positioned(
        left: 0,
        right: 0,
        top: _calloutY,
        child:
            Center(child: _CalloutPill(text: step.callout!, background: coral)),
      ));
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _cell({
    required double cx,
    required double top,
    required String text,
    required Color color,
    double opacity = 1,
    double scale = 1,
  }) {
    Widget child = SizedBox(
      width: _cellW,
      height: _rowH,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: _fontSize,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.1,
          ),
        ),
      ),
    );
    if (scale != 1) child = Transform.scale(scale: scale, child: child);
    if (opacity != 1) child = Opacity(opacity: opacity.clamp(0, 1), child: child);
    return Positioned(left: cx - _cellW / 2, top: top, child: child);
  }
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
          fontSize: 18,
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
        _circle(context,
            icon: Icons.arrow_back_rounded,
            label: context.l10n.resultPreviousStep,
            onTap: index > 0 ? onPrev : null),
        const SizedBox(width: AppSpacing.md),
        _circle(context,
            icon: isLast
                ? Icons.replay_rounded
                : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            label: context.l10n.resultPlayWalkthroughShort,
            filled: true,
            onTap: isLast ? onReplay : onTogglePlay),
        const SizedBox(width: AppSpacing.md),
        _circle(context,
            icon: Icons.arrow_forward_rounded,
            label: context.l10n.resultNextStep,
            onTap: isLast ? null : onNext),
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
            child: Icon(icon,
                size: 24, color: filled ? AppColors.white : colors.textSecondary),
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
            Text(context.l10n.tutorAsk,
                style: AppTypography.caption.copyWith(color: emerald)),
          ],
        ),
      ),
    );
  }
}
