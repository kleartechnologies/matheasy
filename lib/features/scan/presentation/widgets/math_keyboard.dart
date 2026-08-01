import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/services/haptics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../application/math_field_controller.dart';
import 'math_key_catalogue.dart';
import 'math_layout.dart';

/// The Matheasy structured math keyboard.
///
/// Every key is a miniature of what it inserts: tapping `□/□` opens a real
/// fraction in the field with two dashed boxes, and the caret lands in the
/// first one. Keys marked with a dot carry alternates on long-press, which is
/// how roots, relations and extra variables stay reachable without a wall of
/// keys.
///
/// It drives a [MathFieldController] directly — the expression tree is the
/// single source of truth, and LaTeX is produced only when the problem is
/// submitted, so the recognize → solve pipeline is untouched.
class MathKeyboard extends StatefulWidget {
  const MathKeyboard({
    super.key,
    required this.controller,
    this.onSolve,
    this.solveLabel = 'Solve',
    this.busy = false,
  });

  /// The field this keyboard types into.
  final MathFieldController controller;

  /// Submit. The key enables itself as soon as the field is non-empty — it
  /// watches [controller] directly, so the host screen never has to rebuild on
  /// every keystroke just to flip a button. `null` disables it outright.
  final VoidCallback? onSolve;

  /// A submit is in flight; the key stays visible but inert.
  final bool busy;

  /// Label on the submit key — "Solve" for typing; "Use this" when editing an
  /// OCR result (which returns to the confirmation sheet rather than solving).
  final String solveLabel;

  /// The pages of keys, in the order their chips appear.
  static List<MathKeyTab> get tabs => MathKeys.tabs;

  /// The letters page, reached from the `abc` button.
  static MathKeyTab get letters => MathKeys.letters;

  /// The widget key on the cell for [spec] — labels are unique within a page,
  /// and only one page is on screen at a time.
  static String keyOf(MathKeySpec spec) => 'mathkey:${spec.label}';

  /// The submit key, whose enabled/disabled state is the thing worth asserting.
  static const ValueKey<String> solveKey = ValueKey('mathkey:solve');

  @override
  State<MathKeyboard> createState() => _MathKeyboardState();
}

const double _keyHeight = 52;

/// Below this a key stops being comfortably tappable, so the grid gives up on
/// fitting the width and scrolls sideways instead of shrinking further.
const double _minKeyWidth = 44;

class _MathKeyboardState extends State<MathKeyboard> {
  int _tab = 0;
  bool _letters = false;

  MathKeyTab get _page => _letters ? MathKeyboard.letters : MathKeyboard.tabs[_tab];

  void _press(MathKeySpec key) {
    HapticsService.selection();
    final atom = key.atom;
    if (atom != null) {
      widget.controller.insertAtom(atom);
      return;
    }
    final template = key.template;
    if (template == null) return;
    if (key.wrapPrevious) {
      widget.controller.applyToPrevious(template);
    } else {
      widget.controller.insertTemplate(template);
    }
  }

  /// The long-press menu behind a dotted key.
  Future<void> _showAlternates(BuildContext keyContext, MathKeySpec key) async {
    HapticsService.selection();
    final box = keyContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(keyContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final colors = context.colors;
    final style = MathRenderStyle(fontSize: 19, color: colors.textPrimary);

    final chosen = await showMenu<MathKeySpec>(
      context: keyContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      color: colors.surface,
      items: [
        for (final alt in key.alternates)
          PopupMenuItem<MathKeySpec>(
            value: alt,
            height: 46,
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: alt.label,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _KeyFace(spec: alt, style: style),
              ),
            ),
          ),
      ],
    );
    if (chosen != null) _press(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: EdgeInsets.only(
        bottom: AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _utilityBar(colors),
          _tabBar(colors),
          Container(height: 1, color: colors.border),
          _grid(_page, colors),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              0,
            ),
            child: _solveKey(colors),
          ),
        ],
      ),
    );
  }

  // -- Chrome ---------------------------------------------------------------

  Widget _utilityBar(AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          _lettersToggle(colors),
          const Spacer(),
          _iconKey(Icons.chevron_left_rounded, context.l10n.keyboardMoveLeft,
              widget.controller.moveLeft, colors),
          const SizedBox(width: AppSpacing.xs),
          _iconKey(Icons.chevron_right_rounded, context.l10n.keyboardMoveRight,
              widget.controller.moveRight, colors),
          const SizedBox(width: AppSpacing.xs),
          _iconKey(Icons.backspace_outlined, context.l10n.keyboardDelete,
              widget.controller.backspace, colors),
        ],
      ),
    );
  }

  Widget _lettersToggle(AppSemanticColors colors) {
    return Semantics(
      button: true,
      selected: _letters,
      excludeSemantics: true,
      label: context.l10n.scanKeyboardCategoryKeys(_letters ? '123' : 'abc'),
      child: Pressable(
        // Pressable already ticks; a second call here double-taps the motor.
        onTap: () => setState(() => _letters = !_letters),
        borderRadius: AppRadius.smRadius,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: _letters ? AppColors.primaryAction : colors.surface,
            borderRadius: AppRadius.smRadius,
            border: Border.all(
              color: _letters ? AppColors.primaryAction : colors.border,
            ),
          ),
          child: Text(
            _letters ? '123' : 'abc',
            style: AppTypography.caption.copyWith(
              color: _letters ? AppColors.white : colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabBar(AppSemanticColors colors) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        itemCount: MathKeyboard.tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          final tab = MathKeyboard.tabs[i];
          // While the letters page is open no chip is current — tapping one
          // both selects it and closes `abc`.
          final selected = !_letters && i == _tab;
          return Semantics(
            key: ValueKey('mathtab:${tab.id}'),
            button: true,
            selected: selected,
            excludeSemantics: true,
            label: context.l10n.scanKeyboardCategoryKeys(
              '${tab.labelTop} ${tab.labelBottom}',
            ),
            child: Pressable(
              onTap: () => setState(() {
                _tab = i;
                _letters = false;
              }),
              borderRadius: AppRadius.smRadius,
              child: Container(
                alignment: Alignment.center,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                // A selected chip is a filled control carrying white text —
                // primaryAction (4.78:1), never the identity emerald (2.97:1).
                decoration: BoxDecoration(
                  color: selected ? AppColors.primaryAction : colors.surface,
                  borderRadius: AppRadius.smRadius,
                  border: Border.all(
                    color: selected ? AppColors.primaryAction : colors.border,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tab.labelTop, style: _chipStyle(selected, colors)),
                    Text(tab.labelBottom, style: _chipStyle(selected, colors)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  TextStyle _chipStyle(bool selected, AppSemanticColors colors) =>
      AppTypography.caption.copyWith(
        fontSize: 11,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: selected ? AppColors.white : colors.textSecondary,
      );

  // -- The key grid ---------------------------------------------------------

  /// Lays a page out edge-to-edge. A wide page (the seven trig columns) fits
  /// the width of an ordinary phone perfectly well, so whether it scrolls is
  /// measured rather than declared: it only becomes a sideways-scrolling strip
  /// when the screen is too narrow to keep the keys tappable.
  Widget _grid(MathKeyTab tab, AppSemanticColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = tab.columns;
        final dividers = (columns - 1).toDouble();
        final fitted = (constraints.maxWidth - dividers) / columns;
        final scrolls = fitted < _minKeyWidth;

        final rows = <Widget>[];
        for (var r = 0; r < tab.rows.length; r++) {
          if (r > 0) rows.add(Container(height: 1, color: colors.border));
          final cells = <Widget>[];
          for (var c = 0; c < columns; c++) {
            if (c > 0) cells.add(Container(width: 1, color: colors.border));
            final row = tab.rows[r];
            final cell = _cell(c < row.length ? row[c] : null, colors);
            cells.add(
              scrolls
                  ? SizedBox(width: _minKeyWidth, child: cell)
                  : Expanded(child: cell),
            );
          }
          rows.add(
            SizedBox(
              height: _keyHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
          );
        }

        final grid = Column(
          key: ValueKey(tab.id),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );

        if (!scrolls) return grid;
        // A stretched column needs a bounded width inside a horizontal viewport.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: columns * _minKeyWidth + dividers,
            child: grid,
          ),
        );
      },
    );
  }

  Widget _cell(MathKeySpec? spec, AppSemanticColors colors) {
    if (spec == null) return ColoredBox(color: colors.surfaceMuted);

    // The digit block reads as a calculator pad: lighter than the surrounding
    // function keys, the way the numbers stand out on a physical keypad.
    final numeric = _isNumeric(spec);
    final style = MathRenderStyle(fontSize: 19, color: colors.textPrimary);

    return Builder(
      key: ValueKey(MathKeyboard.keyOf(spec)),
      builder: (keyContext) => Semantics(
        button: true,
        excludeSemantics: true,
        label: spec.label,
        child: Material(
          color: numeric ? colors.surface : colors.surfaceMuted,
          child: InkWell(
            onTap: () => _press(spec),
            onLongPress: spec.hasAlternates
                ? () => _showAlternates(keyContext, spec)
                : null,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _KeyFace(spec: spec, style: style),
                    ),
                  ),
                ),
                if (spec.hasAlternates)
                  Positioned(
                    top: 5,
                    right: 6,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.errorText,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _isNumeric(MathKeySpec spec) {
    final display = spec.atom?.display;
    return display != null && display.length == 1 && '0123456789.='.contains(display);
  }

  // -- Actions --------------------------------------------------------------

  /// Watches the controller so it lights up the moment there is something to
  /// solve. Enablement is deliberately generous — anything non-empty is
  /// submittable, and the screen's validation explains an unfilled box — because
  /// a button that stays grey after you have typed reads as broken.
  Widget _solveKey(AppSemanticColors colors) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final enabled = widget.onSolve != null &&
            !widget.busy &&
            !widget.controller.isEmpty;
        return Semantics(
          key: MathKeyboard.solveKey,
          button: true,
          enabled: enabled,
          excludeSemantics: true,
          label: widget.solveLabel,
          child: Pressable(
            haptic: false, // fired below, as the heavier "success" tick
            onTap: enabled
                ? () {
                    HapticsService.success();
                    widget.onSolve!();
                  }
                : null,
            borderRadius: AppRadius.smRadius,
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Solid interactive emerald — white label at 4.78:1 AA.
                color: enabled ? AppColors.primaryAction : colors.surface,
                borderRadius: AppRadius.smRadius,
                border: enabled ? null : Border.all(color: colors.border),
              ),
              child: widget.busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(colors.textMuted),
                      ),
                    )
                  : Text(
                      widget.solveLabel,
                      style: AppTypography.button.copyWith(
                        color: enabled ? AppColors.white : colors.textMuted,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _iconKey(
    IconData icon,
    String label,
    VoidCallback onTap,
    AppSemanticColors colors,
  ) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: label,
      child: _RepeatKey(
        onPress: onTap,
        child: Container(
          width: 48,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadius.smRadius,
            border: Border.all(color: colors.border),
          ),
          child: Icon(icon, size: 20, color: colors.textSecondary),
        ),
      ),
    );
  }
}

/// A key that fires once on tap and then auto-repeats while it is held — how
/// backspace and the arrows behave on every real keyboard, and the difference
/// between clearing a mistyped expression in one gesture and twelve taps.
class _RepeatKey extends StatefulWidget {
  const _RepeatKey({required this.onPress, required this.child});

  final VoidCallback onPress;
  final Widget child;

  @override
  State<_RepeatKey> createState() => _RepeatKeyState();
}

class _RepeatKeyState extends State<_RepeatKey> {
  static const Duration _delay = Duration(milliseconds: 400);
  static const Duration _interval = Duration(milliseconds: 70);

  Timer? _timer;
  bool _down = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _fire() {
    HapticsService.selection();
    widget.onPress();
  }

  void _start() {
    setState(() => _down = true);
    _fire();
    _timer = Timer(_delay, () {
      _timer = Timer.periodic(_interval, (_) => _fire());
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_down) setState(() => _down = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1.0,
        duration: AppDurations.press,
        curve: AppCurves.standard,
        child: widget.child,
      ),
    );
  }
}

/// What a key shows: a glyph, or a miniature of the structure it opens with its
/// slots drawn as the same dashed boxes they will become in the field.
class _KeyFace extends StatelessWidget {
  const _KeyFace({required this.spec, required this.style});

  final MathKeySpec spec;
  final MathRenderStyle style;

  static Widget _emptySlot(int index, MathRenderStyle style) =>
      MathPlaceholderBox(style: style);

  @override
  Widget build(BuildContext context) {
    final face = spec.face;
    if (face != null) return MathGlyph(text: face, style: style, upright: true);

    final facePart = spec.facePart;
    if (facePart != null) {
      return MathPartView(
        part: facePart,
        style: style,
        slotBuilder: _emptySlot,
      );
    }

    final atom = spec.atom;
    if (atom != null) return MathAtomView(atom: atom, style: style);

    return MathPartView(
      part: spec.template!.layout,
      style: style,
      slotBuilder: _emptySlot,
    );
  }
}
