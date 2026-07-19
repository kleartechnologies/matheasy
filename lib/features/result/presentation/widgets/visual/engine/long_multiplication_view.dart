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
import '../../../../domain/animation/long_multiplication.dart';

/// A Photomath-style LONG MULTIPLICATION tutorial (e.g. `34 × 27`): each partial
/// product is computed (callout) and dropped onto its shifted row, then the
/// partials are added. Driven by the verified [LongMultiplication] model.
class LongMultiplicationView extends StatefulWidget {
  const LongMultiplicationView({super.key, required this.model, this.onAskStep});

  final LongMultiplication model;
  final ValueChanged<int>? onAskStep;

  @override
  State<LongMultiplicationView> createState() => _LongMultiplicationViewState();
}

class _LongMultiplicationViewState extends State<LongMultiplicationView>
    with SingleTickerProviderStateMixin {
  static const double _fontSize = 36;
  static const double _cellW = 40;
  static const double _digitH = 48;
  static const double _topY = 0;
  static const double _bottomY = _digitH;
  static const double _line1Y = _bottomY + _digitH + 2;
  static const double _partialStartY = _line1Y + 10;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppDurations.medium,
  )..forward();
  int _index = 0;
  Timer? _timer;
  bool _playing = false;

  int get _cols => widget.model.gridCols;
  double get _gridW => _cols * _cellW;
  int get _nPartials => widget.model.partials.length;
  double get _line2Y => _partialStartY + _nPartials * _digitH + 4;
  double get _sumY => _line2Y + 10;
  double get _gridBottom => _sumY + _digitH;
  double get _calloutY => _gridBottom + 16;
  double get _totalH => _calloutY + 52;

  int get _last => widget.model.steps.length - 1;
  bool get _isLast => _index == _last;

  double _gridLeft(double stageW) => (stageW - _gridW) / 2;
  double _colX(int col, double stageW) =>
      _gridLeft(stageW) + (_cols - 1 - col) * _cellW + _cellW / 2;
  double _partialY(int k) => _partialStartY + k * _digitH;

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
    final step = widget.model.steps[_index];
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

  Widget _buildStage(BuildContext context, LongMulStep step, double stageW) {
    final t = Curves.easeOut.transform(_c.value);
    final colors = context.colors;
    final ink = colors.textPrimary;
    const coral = AppColors.accentCoral;
    final green = context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final m = widget.model;
    final children = <Widget>[];

    // top number
    for (var i = 0; i < m.topDigits.length; i++) {
      final col = m.topDigits.length - 1 - i;
      children.add(_cell(
        cx: _colX(col, stageW),
        top: _topY,
        text: '${m.topDigits[i]}',
        color: ink,
        box: step.highlightTop.contains(col) ? coral.withValues(alpha: 0.20) : null,
      ));
    }

    // operator + bottom number
    children.add(_cell(
      cx: _colX(m.bottomWidth - 1, stageW) - _cellW,
      top: _bottomY,
      text: '×',
      color: colors.textSecondary,
    ));
    for (var i = 0; i < m.bottomDigits.length; i++) {
      final col = m.bottomDigits.length - 1 - i;
      children.add(_cell(
        cx: _colX(col, stageW),
        top: _bottomY,
        text: '${m.bottomDigits[i]}',
        color: ink,
        box: step.highlightBottomCol == col ? coral.withValues(alpha: 0.20) : null,
      ));
    }

    // first rule
    children.add(_rule(stageW, _line1Y, ink));

    // partial products
    for (var k = 0; k < step.visiblePartials && k < m.partials.length; k++) {
      final p = m.partials[k];
      final isNew = step.emphPartial == k;
      final digits = p.digits;
      for (var i = 0; i < digits.length; i++) {
        final col = p.shift + (digits.length - 1 - i);
        children.add(_cell(
          cx: _colX(col, stageW),
          top: _partialY(k),
          text: '${digits[i]}',
          color: isNew ? green : ink,
          opacity: isNew ? t : 1,
          scale: isNew ? 0.7 + 0.3 * t : 1,
        ));
      }
    }

    // sum
    if (step.showSum) {
      children.add(_rule(stageW, _line2Y, ink));
      final pd = m.productDigits;
      for (var i = 0; i < pd.length; i++) {
        final col = pd.length - 1 - i;
        children.add(_cell(
          cx: _colX(col, stageW),
          top: _sumY,
          text: '${pd[i]}',
          color: step.emphSum ? green : ink,
          opacity: step.emphSum ? t : 1,
          scale: step.emphSum ? 0.7 + 0.3 * t : 1,
        ));
      }
    }

    // callout
    if (step.callout != null) {
      children.add(Positioned(
        left: 0,
        right: 0,
        top: _calloutY,
        child: Center(child: _CalloutPill(text: step.callout!, background: coral)),
      ));
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _rule(double stageW, double y, Color color) => Positioned(
        left: _gridLeft(stageW),
        top: y,
        child: Container(width: _gridW, height: 3, color: color),
      );

  Widget _cell({
    required double cx,
    required double top,
    required String text,
    required Color color,
    Color? box,
    double opacity = 1,
    double scale = 1,
  }) {
    Widget label = Text(
      text,
      style: TextStyle(
        fontSize: _fontSize,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.1,
      ),
    );
    if (box != null) {
      label = Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(color: box, borderRadius: BorderRadius.circular(8)),
        child: label,
      );
    }
    Widget child = SizedBox(width: _cellW, height: _digitH, child: Center(child: label));
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
