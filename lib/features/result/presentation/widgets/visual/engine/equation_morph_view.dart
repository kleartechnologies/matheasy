import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../../../../core/extensions/context_extensions.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../domain/animation/eq_token.dart';
import '../../../../domain/animation/morph_op.dart';
import '../../math_text.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the symbol-level morph.
///
/// Renders the equation as individually-positioned LaTeX fragments and, as
/// [progress] runs 0→1, physically MOVES each term to its new place: a term that
/// crossed the `=` slides across (flashing amber), merged terms collapse into
/// their new value (which pops in), and entered terms fade in. This is the
/// "what changed?" the brief asks for — and every fragment is a substring of the
/// verified LaTeX, so the morph can never introduce an unverified value.
///
/// It degrades gracefully: an unconfident diff, an un-measured first frame, an
/// overflowing row, or Reduce Motion all fall back to a clean whole-expression
/// crossfade (the previous behaviour) — the engine never blocks or misleads.
class EquationMorphView extends StatefulWidget {
  const EquationMorphView({
    super.key,
    required this.beforeLatex,
    required this.afterLatex,
    required this.morph,
    required this.progress,
    this.fontSize = 30,
  });

  final String beforeLatex;
  final String afterLatex;
  final StepMorph morph;

  /// 0→1 for this beat, driven by the player (respects the speed selector).
  final Animation<double> progress;
  final double fontSize;

  @override
  State<EquationMorphView> createState() => _EquationMorphViewState();
}

class _EquationMorphViewState extends State<EquationMorphView> {
  /// Measured intrinsic size per distinct fragment LaTeX. Null until the first
  /// post-frame measurement completes for the current morph.
  Map<String, Size>? _sizes;

  @override
  void didUpdateWidget(EquationMorphView old) {
    super.didUpdateWidget(old);
    if (old.afterLatex != widget.afterLatex ||
        old.beforeLatex != widget.beforeLatex ||
        old.fontSize != widget.fontSize) {
      _sizes = null; // remeasure for the new beat
    }
  }

  Set<String> get _fragLatexes => {
        for (final t in widget.morph.before) t.latex,
        for (final t in widget.morph.after) t.latex,
      };

  void _measure(Map<String, GlobalKey> keys) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sizes = <String, Size>{};
      for (final e in keys.entries) {
        final size = e.value.currentContext?.size;
        if (size == null || size.isEmpty) return; // not laid out yet — retry next frame
        sizes[e.key] = size;
      }
      if (sizes.isNotEmpty) setState(() => _sizes = sizes);
    });
  }

  bool get _canMorph =>
      widget.morph.confident &&
      widget.morph.after.isNotEmpty &&
      !MediaQuery.disableAnimationsOf(context);

  @override
  Widget build(BuildContext context) {
    if (!_canMorph) return _crossfade(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : context.screenWidth;

        final sizes = _sizes;
        if (sizes == null) {
          // Kick off a measurement pass (offstage) and crossfade for one frame.
          final keys = {for (final l in _fragLatexes) l: GlobalKey()};
          _measure(keys);
          return Stack(children: [
            _offstageMeasure(context, keys),
            _crossfade(context),
          ]);
        }

        final layout = _MorphLayout.compute(
          before: widget.morph.before,
          after: widget.morph.after,
          sizes: sizes,
          width: width,
          maxHeight: constraints.maxHeight,
          gap: widget.fontSize * 0.26,
        );
        // A row too wide OR too tall (stacked fractions, matrices) to lay out
        // cleanly → let AdaptiveMath shrink it to fit both dimensions instead.
        if (layout == null) return _crossfade(context);

        final stack = SizedBox(
          height: layout.height,
          width: width,
          child: AnimatedBuilder(
            animation: widget.progress,
            builder: (context, _) => _MorphStack(
              morph: widget.morph,
              layout: layout,
              p: widget.progress.value.clamp(0.0, 1.0),
              baseStyle: _style(context),
              colors: _MorphColors.of(context),
            ),
          ),
        );
        // Centre the (short) morph row within whatever height the player gives.
        return SizedBox(
          width: width,
          height: constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : layout.height,
          child: Center(child: stack),
        );
      },
    );
  }

  TextStyle _style(BuildContext context) => TextStyle(
        fontSize: widget.fontSize,
        color: context.colors.textPrimary,
        fontWeight: FontWeight.w600,
      );

  Widget _offstageMeasure(BuildContext context, Map<String, GlobalKey> keys) {
    final style = _style(context);
    return Offstage(
      child: Wrap(
        children: [
          for (final e in keys.entries)
            KeyedSubtree(
              key: e.value,
              child: Math.tex(
                e.key,
                textStyle: style,
                mathStyle: MathStyle.text,
                onErrorFallback: (_) => Text(e.key, style: style),
              ),
            ),
        ],
      ),
    );
  }

  /// The safe fallback: fade the previous expression out and the next one in.
  Widget _crossfade(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final style = _style(context);
    if (reduce || widget.beforeLatex == widget.afterLatex) {
      return Center(
        child: AdaptiveMath(
          widget.afterLatex,
          minFontSize: widget.fontSize * 0.7,
          maxFontSize: widget.fontSize,
          alignment: Alignment.center,
          style: style,
        ),
      );
    }
    return AnimatedBuilder(
      animation: widget.progress,
      builder: (context, _) {
        final p = widget.progress.value.clamp(0.0, 1.0);
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - (p * 1.6)).clamp(0.0, 1.0),
                child: AdaptiveMath(widget.beforeLatex,
                    minFontSize: widget.fontSize * 0.7,
                    maxFontSize: widget.fontSize,
                    alignment: Alignment.center,
                    style: style),
              ),
              Opacity(
                opacity: ((p - 0.35) * 1.8).clamp(0.0, 1.0),
                child: AdaptiveMath(widget.afterLatex,
                    minFontSize: widget.fontSize * 0.7,
                    maxFontSize: widget.fontSize,
                    alignment: Alignment.center,
                    style: style),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Emphasis colours for the morph, derived from the theme + brand tokens.
class _MorphColors {
  const _MorphColors({
    required this.normal,
    required this.moved,
    required this.merged,
  });

  final Color normal;
  final Color moved;
  final Color merged;

  factory _MorphColors.of(BuildContext context) => _MorphColors(
        normal: context.colors.textPrimary,
        moved: AppColors.warning,
        merged: context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
      );
}

/// Precomputed fragment positions for the before and after rows, in a shared
/// coordinate space centred within the available width.
class _MorphLayout {
  const _MorphLayout({
    required this.beforePos,
    required this.afterPos,
    required this.sizeOf,
    required this.height,
  });

  final Map<int, Offset> beforePos; // token id → top-left
  final Map<int, Offset> afterPos;
  final Map<int, Size> sizeOf; // token id → measured size
  final double height;

  static _MorphLayout? compute({
    required List<EqToken> before,
    required List<EqToken> after,
    required Map<String, Size> sizes,
    required double width,
    required double maxHeight,
    required double gap,
  }) {
    double rowWidth(List<EqToken> row) {
      var w = 0.0;
      for (final t in row) {
        final s = sizes[t.latex];
        if (s == null) return double.infinity;
        w += s.width;
      }
      if (row.isNotEmpty) w += gap * (row.length - 1);
      return w;
    }

    final bw = rowWidth(before);
    final aw = rowWidth(after);
    if (!bw.isFinite || !aw.isFinite) return null;
    if (aw > width || bw > width) return null; // would overflow → crossfade

    double rowHeight = 0;
    for (final s in sizes.values) {
      if (s.height > rowHeight) rowHeight = s.height;
    }
    if (rowHeight <= 0) return null;
    // A tall equation (stacked/nested fractions, matrices) would paint past the
    // fixed morph box → crossfade (AdaptiveMath fits both dimensions) instead.
    if (maxHeight.isFinite && rowHeight > maxHeight) return null;

    final sizeOf = <int, Size>{};
    Map<int, Offset> place(List<EqToken> row, double totalWidth) {
      final map = <int, Offset>{};
      var x = (width - totalWidth) / 2;
      if (x < 0) x = 0;
      for (final t in row) {
        final s = sizes[t.latex]!;
        sizeOf[t.id] = s;
        map[t.id] = Offset(x, (rowHeight - s.height) / 2);
        x += s.width + gap;
      }
      return map;
    }

    return _MorphLayout(
      beforePos: place(before, bw),
      afterPos: place(after, aw),
      sizeOf: sizeOf,
      height: rowHeight,
    );
  }
}

/// The animated stack of positioned fragments for one progress value.
class _MorphStack extends StatelessWidget {
  const _MorphStack({
    required this.morph,
    required this.layout,
    required this.p,
    required this.baseStyle,
    required this.colors,
  });

  final StepMorph morph;
  final _MorphLayout layout;
  final double p;
  final TextStyle baseStyle;
  final _MorphColors colors;

  double _sx(double edge0, double edge1) {
    if (p <= edge0) return 0;
    if (p >= edge1) return 1;
    final t = (p - edge0) / (edge1 - edge0);
    return t * t * (3 - 2 * t); // smoothstep
  }

  @override
  Widget build(BuildContext context) {
    final xt = Curves.easeInOutCubic.transform(p);
    final children = <Widget>[];

    // Persistent + entering + merged after-tokens travel to their new places.
    for (final a in morph.after) {
      final op = morph.opForAfter(a.id);
      final end = layout.afterPos[a.id];
      if (end == null) continue;
      Offset start = end;
      var opacity = 1.0;
      var scale = 1.0;
      var color = colors.normal;

      switch (op?.kind) {
        case MorphKind.keep:
          start = layout.beforePos[op!.fromIds.first] ?? end;
        case MorphKind.move:
          start = layout.beforePos[op!.fromIds.first] ?? end;
          // Flash amber while it travels across the relation.
          color = Color.lerp(colors.normal, colors.moved,
                  (1 - (2 * p - 1).abs()).clamp(0.0, 1.0)) ??
              colors.normal;
        case MorphKind.merge:
          if (op!.toIds.length == 1) {
            // Many → one: the new value pops in from the sources' centre.
            final xs = op.fromIds
                .map((id) => layout.beforePos[id])
                .whereType<Offset>()
                .toList();
            if (xs.isNotEmpty) {
              start = Offset(
                xs.map((o) => o.dx).reduce((x, y) => x + y) / xs.length,
                end.dy,
              );
            }
            opacity = _sx(0.45, 1.0);
            scale = 0.7 + 0.3 * _sx(0.45, 1.0);
            color = colors.merged;
          } else {
            // One → many (split): fan out from the source.
            start = layout.beforePos[op.fromIds.first] ?? end;
            opacity = _sx(0.3, 1.0);
          }
        case MorphKind.enter:
          opacity = _sx(0.4, 1.0);
          color = colors.merged;
        case MorphKind.exit:
        case null:
          break;
      }

      final pos = Offset.lerp(start, end, xt)!;
      children.add(_frag(a, pos, opacity, scale, color));
    }

    // Sources that leave: merge/split sources travel toward the target and fade;
    // plain exits fade in place.
    for (final op in morph.ops) {
      if (op.kind == MorphKind.merge && op.toIds.length == 1) {
        final target = layout.afterPos[op.toIds.first];
        for (final id in op.fromIds) {
          final b = _beforeById(id);
          final from = layout.beforePos[id];
          if (b == null || from == null || target == null) continue;
          final pos = Offset.lerp(from, target, xt)!;
          children.add(_frag(b, pos, (1 - _sx(0.45, 0.9)).clamp(0.0, 1.0), 1,
              colors.normal));
        }
      } else if (op.kind == MorphKind.exit) {
        for (final id in op.fromIds) {
          final b = _beforeById(id);
          final from = layout.beforePos[id];
          if (b == null || from == null) continue;
          children.add(_frag(
              b, from, (1 - _sx(0.0, 0.55)).clamp(0.0, 1.0), 1, colors.normal));
        }
      }
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }

  EqToken? _beforeById(int id) {
    for (final t in morph.before) {
      if (t.id == id) return t;
    }
    return null;
  }

  Widget _frag(
      EqToken t, Offset pos, double opacity, double scale, Color color) {
    final style = baseStyle.copyWith(color: color);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: Math.tex(
            t.latex,
            textStyle: style,
            mathStyle: MathStyle.text,
            onErrorFallback: (_) => Text(t.latex, style: style),
          ),
        ),
      ),
    );
  }
}
