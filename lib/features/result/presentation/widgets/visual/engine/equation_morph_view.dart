import 'dart:math' as math;

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
    required this.beforeSizeOf,
    required this.afterSizeOf,
    required this.height,
  });

  final Map<int, Offset> beforePos; // token id → top-left
  final Map<int, Offset> afterPos;
  // Separate maps: the tokenizer restarts ids at 0 per state, so a single
  // id→size map would let after-token sizes clobber before-token sizes.
  final Map<int, Size> beforeSizeOf;
  final Map<int, Size> afterSizeOf;
  final double height;

  static _MorphLayout? compute({
    required List<EqToken> before,
    required List<EqToken> after,
    required Map<String, Size> sizes,
    required double width,
    required double maxHeight,
    required double gap,
  }) {
    // The combined width of a side's terms (∞ if any fragment is unmeasured).
    double sideWidth(List<EqToken> row, int side) {
      var w = 0.0;
      var n = 0;
      for (final t in row) {
        if (!t.isTerm || t.side != side) continue;
        final s = sizes[t.latex];
        if (s == null) return double.infinity;
        w += s.width;
        n++;
      }
      return n == 0 ? 0 : w + gap * (n - 1);
    }

    EqToken? relationOf(List<EqToken> row) {
      for (final t in row) {
        if (t.isRelation) return t;
      }
      return null;
    }

    final rel = relationOf(after) ?? relationOf(before);
    final hasRel = rel != null;
    final relW = hasRel ? (sizes[rel.latex]?.width ?? double.infinity) : 0.0;
    final leftSide = hasRel ? 0 : -1;

    final leftW =
        math.max(sideWidth(before, leftSide), sideWidth(after, leftSide));
    final rightW =
        hasRel ? math.max(sideWidth(before, 1), sideWidth(after, 1)) : 0.0;
    final total = leftW + (hasRel ? gap + relW + gap + rightW : 0.0);
    if (!total.isFinite || total <= 0 || total > width) return null;

    double rowHeight = 0;
    for (final s in sizes.values) {
      if (s.height > rowHeight) rowHeight = s.height;
    }
    if (rowHeight <= 0) return null;
    // A tall equation (stacked/nested fractions, matrices) would paint past the
    // fixed morph box → crossfade (AdaptiveMath fits both dimensions) instead.
    if (maxHeight.isFinite && rowHeight > maxHeight) return null;

    // Both states share ONE coordinate frame: left terms left-aligned from a
    // common origin, the relation pinned at a common x, right terms left-aligned
    // from a common origin. So a kept term keeps its exact place and only the
    // term that changed side visibly travels — and nothing ever collides with
    // the '='. (Centred within the available width.)
    final startX = math.max(0.0, (width - total) / 2);
    final relX = startX + leftW + gap;
    final rightOrigin = startX + leftW + gap + relW + gap;

    Map<int, Offset> place(List<EqToken> row, Map<int, Size> sizeOut) {
      final map = <int, Offset>{};
      var xl = startX;
      var xr = rightOrigin;
      for (final t in row) {
        final s = sizes[t.latex];
        if (s == null) continue;
        sizeOut[t.id] = s;
        final y = (rowHeight - s.height) / 2;
        if (t.isRelation) {
          map[t.id] = Offset(relX, y);
        } else if (t.side == 1) {
          map[t.id] = Offset(xr, y);
          xr += s.width + gap;
        } else {
          map[t.id] = Offset(xl, y);
          xl += s.width + gap;
        }
      }
      return map;
    }

    final beforeSizeOf = <int, Size>{};
    final afterSizeOf = <int, Size>{};
    return _MorphLayout(
      beforePos: place(before, beforeSizeOf),
      afterPos: place(after, afterSizeOf),
      beforeSizeOf: beforeSizeOf,
      afterSizeOf: afterSizeOf,
      height: rowHeight,
    );
  }
}

/// The animated stack of positioned fragments for one progress value.
///
/// Calm, single-focus choreography (staged over the slower cadence): the
/// unchanged tokens are pinned dead still at their final positions, and ONLY the
/// one changed term draws attention — it glows, slides across the relation (with
/// a sign flip at the crossing), and the new value fades in. No scaling, no
/// bouncing: the student tracks exactly one thing.
///
/// Phase map of `p` (0→1): HIGHLIGHT [0, .18] · MOVE [.18, .5] · MORPH [.5, .75]
/// · SETTLE [.75, 1].
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

  static const _highlightEnd = 0.18;
  static const _moveEnd = 0.5;
  static const _morphEnd = 0.75;

  double _sx(double edge0, double edge1) {
    if (p <= edge0) return 0;
    if (p >= edge1) return 1;
    final t = (p - edge0) / (edge1 - edge0);
    return t * t * (3 - 2 * t); // smoothstep
  }

  @override
  Widget build(BuildContext context) {
    final moveT = _sx(_highlightEnd, _moveEnd); // slide progress
    final appearT = _sx(_moveEnd, _morphEnd); // new-value fade-in
    // The active term glows through highlight + move, then settles.
    final movedGlow = _sx(0, 0.12) * (1 - _sx(_moveEnd, 0.85));

    final highlights = <Widget>[]; // drawn behind
    final frags = <Widget>[];

    for (final a in morph.after) {
      final op = morph.opForAfter(a.id);
      final end = layout.afterPos[a.id];
      if (end == null) continue;

      switch (op?.kind) {
        case MorphKind.keep:
        case null:
          // Pinned, still, normal. Everything the student is NOT tracking.
          frags.add(_frag(a.latex, end, 1, colors.normal, layout.afterSizeOf[a.id]));

        case MorphKind.move:
          // The hero: glow in place, slide across, flip sign at the crossing.
          final start = layout.beforePos[op!.fromIds.first] ?? end;
          final pos = Offset.lerp(start, end, moveT)!;
          final before = _beforeById(op.fromIds.first);
          final latex =
              (moveT < 0.5 && before != null) ? before.latex : a.latex;
          final color =
              Color.lerp(colors.normal, colors.moved, movedGlow) ?? colors.normal;
          if (movedGlow > 0.02) {
            highlights.add(_glow(pos, layout.afterSizeOf[a.id], colors.moved,
                movedGlow * 0.22));
          }
          frags.add(_frag(latex, pos, 1, color, layout.afterSizeOf[a.id]));

        case MorphKind.merge:
          // The resolved value fades in at its resting place — no motion, no pop.
          final resultGlow = appearT * (1 - _sx(0.82, 1.0));
          final color =
              Color.lerp(colors.merged, colors.normal, _sx(0.7, 1.0)) ??
                  colors.normal;
          if (resultGlow > 0.02) {
            highlights.add(_glow(
                end, layout.afterSizeOf[a.id], colors.merged, resultGlow * 0.2));
          }
          frags.add(_frag(a.latex, end, appearT, color, layout.afterSizeOf[a.id]));

        case MorphKind.enter:
          frags.add(_frag(a.latex, end, appearT, colors.merged, layout.afterSizeOf[a.id]));

        case MorphKind.exit:
          break;
      }
    }

    // Sources that dissolve: glow during highlight, fade out as the new value
    // resolves. They stay put — only the tracked term ever moves.
    for (final op in morph.ops) {
      final fades = op.kind == MorphKind.merge || op.kind == MorphKind.exit
          ? op.fromIds
          : const <int>[];
      for (final id in fades) {
        final b = _beforeById(id);
        final from = layout.beforePos[id];
        if (b == null || from == null) continue;
        final srcGlow = _sx(0, 0.14) * (1 - _sx(_highlightEnd, _moveEnd));
        if (srcGlow > 0.02) {
          highlights.add(
              _glow(from, layout.beforeSizeOf[id], colors.moved, srcGlow * 0.18));
        }
        final fade = (1 - _sx(_moveEnd, _morphEnd)).clamp(0.0, 1.0);
        frags.add(_frag(b.latex, from, fade, colors.normal, layout.beforeSizeOf[id]));
      }
    }

    return Stack(clipBehavior: Clip.none, children: [...highlights, ...frags]);
  }

  EqToken? _beforeById(int id) {
    for (final t in morph.before) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// A soft rounded halo behind the changed term — the ONLY thing that draws the
  /// eye. Subtle (low alpha), no motion of its own.
  Widget _glow(Offset pos, Size? size, Color color, double alpha) {
    final s = size ?? const Size(24, 24);
    const pad = 7.0;
    return Positioned(
      left: pos.dx - pad,
      top: pos.dy - pad,
      child: Container(
        width: s.width + pad * 2,
        height: s.height + pad * 2,
        decoration: BoxDecoration(
          color: color.withValues(alpha: alpha.clamp(0.0, 1.0)),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _frag(String latex, Offset pos, double opacity, Color color, Size? size) {
    final style = baseStyle.copyWith(color: color);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Math.tex(
          latex,
          textStyle: style,
          mathStyle: MathStyle.text,
          onErrorFallback: (_) => Text(latex, style: style),
        ),
      ),
    );
  }
}
