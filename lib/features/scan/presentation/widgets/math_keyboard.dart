import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/services/haptics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// A single key on the [MathKeyboard]. [insert] is the LaTeX written at the
/// caret; [caretBack] moves the caret that many characters left afterwards, so
/// templates like `\frac{}{}` land the caret inside their first placeholder.
class MathKey {
  const MathKey(this.label, this.insert, {this.caretBack = 0, this.accent = false});

  /// The face shown on the key (may be a unicode glyph).
  final String label;

  /// LaTeX inserted at the caret.
  final String insert;

  /// Characters to step the caret back into a placeholder after inserting.
  final int caretBack;

  /// Whether to give the key the tinted "operator" treatment.
  final bool accent;
}

/// A named page of keys.
class MathKeyCategory {
  const MathKeyCategory(this.label, this.keys);
  final String label;
  final List<MathKey> keys;
}

/// The Matheasy educational math keyboard.
///
/// Categorised for learning — basics, variables, powers & roots, trigonometry,
/// calculus and logarithms — with fractions, exponents, square roots,
/// parentheses and variables reachable throughout. Emits LaTeX so the typed
/// problem flows into the same recognize → solve pipeline as a scan.
class MathKeyboard extends StatefulWidget {
  const MathKeyboard({
    super.key,
    required this.onInsert,
    required this.onBackspace,
    required this.onMoveLeft,
    required this.onMoveRight,
    this.onSolve,
    this.solveLabel = 'Solve',
  });

  /// Insert [latex] at the caret, then step back [caretBack] chars.
  final void Function(String latex, int caretBack) onInsert;
  final VoidCallback onBackspace;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;

  /// Submit. `null` disables the Solve key (empty / invalid input).
  final VoidCallback? onSolve;

  /// Label on the submit key — "Solve" for typing; "Use this" when editing an
  /// OCR result (which returns to the confirmation sheet rather than solving).
  final String solveLabel;

  static const List<MathKeyCategory> categories = [
    MathKeyCategory('123', [
      MathKey('7', '7'), MathKey('8', '8'), MathKey('9', '9'),
      MathKey('÷', r'\div ', accent: true), MathKey('×', r'\times ', accent: true),
      MathKey('4', '4'), MathKey('5', '5'), MathKey('6', '6'),
      MathKey('−', '-', accent: true), MathKey('+', '+', accent: true),
      MathKey('1', '1'), MathKey('2', '2'), MathKey('3', '3'),
      MathKey('x', 'x'), MathKey('=', '=', accent: true),
      MathKey('0', '0'), MathKey('.', '.'), MathKey('y', 'y'),
      MathKey('(', '('), MathKey(')', ')'),
      MathKey('a⁄b', r'\frac{}{}', caretBack: 3, accent: true),
      MathKey('x²', r'^{2}'), MathKey('xⁿ', r'^{}', caretBack: 1),
      MathKey('√', r'\sqrt{}', caretBack: 1), MathKey('π', r'\pi '),
    ]),
    MathKeyCategory('x y', [
      MathKey('x', 'x'), MathKey('y', 'y'), MathKey('z', 'z'),
      MathKey('a', 'a'), MathKey('b', 'b'),
      MathKey('n', 'n'), MathKey('t', 't'), MathKey('k', 'k'),
      MathKey('θ', r'\theta '), MathKey('π', r'\pi '),
      MathKey('α', r'\alpha '), MathKey('β', r'\beta '),
      MathKey('λ', r'\lambda '), MathKey('μ', r'\mu '), MathKey('Δ', r'\Delta '),
      MathKey('=', '=', accent: true), MathKey('<', '<', accent: true),
      MathKey('>', '>', accent: true), MathKey('≤', r'\le ', accent: true),
      MathKey('≥', r'\ge ', accent: true),
      MathKey('(', '('), MathKey(')', ')'), MathKey(',', ', '),
      MathKey('a⁄b', r'\frac{}{}', caretBack: 3, accent: true),
      MathKey('xⁿ', r'^{}', caretBack: 1),
    ]),
    MathKeyCategory('√ xⁿ', [
      MathKey('x²', r'^{2}'), MathKey('x³', r'^{3}'), MathKey('xⁿ', r'^{}', caretBack: 1),
      MathKey('√', r'\sqrt{}', caretBack: 1), MathKey('∛', r'\sqrt[3]{}', caretBack: 1),
      MathKey('ⁿ√', r'\sqrt[]{}', caretBack: 3), MathKey('a⁄b', r'\frac{}{}', caretBack: 3, accent: true),
      MathKey('xₙ', r'_{}', caretBack: 1), MathKey('|x|', r'\left|\right|', caretBack: 7),
      MathKey('eˣ', r'e^{}', caretBack: 1),
      MathKey('×', r'\times ', accent: true), MathKey('÷', r'\div ', accent: true),
      MathKey('±', r'\pm '), MathKey('(', '('), MathKey(')', ')'),
      MathKey('7', '7'), MathKey('8', '8'), MathKey('9', '9'),
      MathKey('x', 'x'), MathKey('=', '=', accent: true),
    ]),
    MathKeyCategory('sin', [
      MathKey('sin', r'\sin()', caretBack: 1), MathKey('cos', r'\cos()', caretBack: 1),
      MathKey('tan', r'\tan()', caretBack: 1),
      MathKey('csc', r'\csc()', caretBack: 1), MathKey('sec', r'\sec()', caretBack: 1),
      MathKey('cot', r'\cot()', caretBack: 1),
      MathKey('sin⁻¹', r'\sin^{-1}()', caretBack: 1),
      MathKey('cos⁻¹', r'\cos^{-1}()', caretBack: 1),
      MathKey('tan⁻¹', r'\tan^{-1}()', caretBack: 1),
      MathKey('θ', r'\theta '), MathKey('π', r'\pi '), MathKey('°', r'^{\circ}'),
      MathKey('√', r'\sqrt{}', caretBack: 1), MathKey('x²', r'^{2}'),
      MathKey('a⁄b', r'\frac{}{}', caretBack: 3, accent: true),
      MathKey('(', '('), MathKey(')', ')'), MathKey('=', '=', accent: true),
    ]),
    MathKeyCategory('∫ d⁄dx', [
      MathKey('∫', r'\int ', accent: true),
      MathKey('∫ᵇₐ', r'\int_{}^{}', caretBack: 4, accent: true),
      MathKey('d⁄dx', r'\frac{d}{dx}', accent: true),
      MathKey('∂', r'\partial '), MathKey('′', "'"),
      MathKey('lim', r'\lim_{x \to }', caretBack: 1, accent: true),
      MathKey('Σ', r'\sum_{}^{}', caretBack: 4, accent: true),
      MathKey('∞', r'\infty '), MathKey('→', r'\to '), MathKey('dx', 'dx'),
      MathKey('a⁄b', r'\frac{}{}', caretBack: 3, accent: true),
      MathKey('√', r'\sqrt{}', caretBack: 1), MathKey('xⁿ', r'^{}', caretBack: 1),
      MathKey('e', 'e'), MathKey('π', r'\pi '),
      MathKey('x', 'x'), MathKey('=', '=', accent: true),
      MathKey('(', '('), MathKey(')', ')'),
    ]),
    MathKeyCategory('log', [
      MathKey('log', r'\log()', caretBack: 1, accent: true),
      MathKey('ln', r'\ln()', caretBack: 1, accent: true),
      MathKey('logₐ', r'\log_{}()', caretBack: 3, accent: true),
      MathKey('log₁₀', r'\log_{10}()', caretBack: 1),
      MathKey('eˣ', r'e^{}', caretBack: 1),
      MathKey('10ˣ', r'10^{}', caretBack: 1),
      MathKey('e', 'e'), MathKey('π', r'\pi '), MathKey('∞', r'\infty '),
      MathKey('a⁄b', r'\frac{}{}', caretBack: 3, accent: true),
      MathKey('√', r'\sqrt{}', caretBack: 1), MathKey('xⁿ', r'^{}', caretBack: 1),
      MathKey('x', 'x'), MathKey('=', '=', accent: true),
      MathKey('(', '('), MathKey(')', ')'),
    ]),
  ];

  @override
  State<MathKeyboard> createState() => _MathKeyboardState();
}

class _MathKeyboardState extends State<MathKeyboard> {
  int _category = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final keys = MathKeyboard.categories[_category].keys;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _categoryBar(colors),
          const SizedBox(height: AppSpacing.sm),
          ..._rows(keys, colors),
          const SizedBox(height: AppSpacing.sm),
          _actionRow(colors),
        ],
      ),
    );
  }

  Widget _categoryBar(AppSemanticColors colors) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: MathKeyboard.categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          final selected = i == _category;
          return Semantics(
            button: true,
            selected: selected,
            excludeSemantics: true,
            label: '${MathKeyboard.categories[i].label} keys',
            child: Pressable(
              onTap: () {
                HapticsService.selection();
                setState(() => _category = i);
              },
              borderRadius: AppRadius.smRadius,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : colors.surface,
                  borderRadius: AppRadius.smRadius,
                  border: Border.all(
                    color: selected ? AppColors.primary : colors.border,
                  ),
                ),
                child: Text(
                  MathKeyboard.categories[i].label,
                  style: AppTypography.caption.copyWith(
                    color: selected ? AppColors.white : colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _rows(List<MathKey> keys, AppSemanticColors colors) {
    const perRow = 5;
    final rows = <Widget>[];
    for (var i = 0; i < keys.length; i += perRow) {
      final slice = keys.sublist(i, (i + perRow).clamp(0, keys.length));
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          children: [
            for (var j = 0; j < perRow; j++) ...[
              if (j > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: j < slice.length
                    ? _keyTile(slice[j], colors)
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }
    return rows;
  }

  Widget _keyTile(MathKey key, AppSemanticColors colors) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: key.label,
      child: Pressable(
        onTap: () {
          HapticsService.selection();
          widget.onInsert(key.insert, key.caretBack);
        },
        borderRadius: AppRadius.smRadius,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: key.accent
                ? AppColors.primary.withValues(alpha: 0.12)
                : colors.surface,
            borderRadius: AppRadius.smRadius,
            border: Border.all(color: colors.border),
          ),
          child: Text(
            key.label,
            style: AppTypography.title.copyWith(
              color: key.accent ? AppColors.primaryDark : colors.textPrimary,
              fontSize: 17,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionRow(AppSemanticColors colors) {
    return Row(
      children: [
        _iconKey(Icons.chevron_left_rounded, 'Move left', () {
          HapticsService.selection();
          widget.onMoveLeft();
        }, colors),
        const SizedBox(width: AppSpacing.xs),
        _iconKey(Icons.chevron_right_rounded, 'Move right', () {
          HapticsService.selection();
          widget.onMoveRight();
        }, colors),
        const SizedBox(width: AppSpacing.xs),
        _iconKey(Icons.backspace_outlined, 'Delete', () {
          HapticsService.selection();
          widget.onBackspace();
        }, colors),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Semantics(
            button: true,
            enabled: widget.onSolve != null,
            excludeSemantics: true,
            label: widget.solveLabel,
            child: Pressable(
              onTap: widget.onSolve == null
                  ? null
                  : () {
                      HapticsService.success();
                      widget.onSolve!();
                    },
              borderRadius: AppRadius.smRadius,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: widget.onSolve != null ? AppColors.primaryGradient : null,
                  color: widget.onSolve != null ? null : colors.surface,
                  borderRadius: AppRadius.smRadius,
                  border: widget.onSolve != null
                      ? null
                      : Border.all(color: colors.border),
                ),
                child: Text(
                  widget.solveLabel,
                  style: AppTypography.button.copyWith(
                    color: widget.onSolve != null
                        ? AppColors.white
                        : colors.textTertiary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
      label: label,
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.smRadius,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadius.smRadius,
            border: Border.all(color: colors.border),
          ),
          child: Icon(icon, size: 22, color: colors.textSecondary),
        ),
      ),
    );
  }
}
