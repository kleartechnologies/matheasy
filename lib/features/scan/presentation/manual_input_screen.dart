import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/functions_client.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../progress/application/stats_controller.dart';
import '../../result/presentation/widgets/math_text.dart';
import '../../subscription/application/usage_controller.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../application/scanner_service.dart';
import '../domain/detected_equation.dart';
import '../domain/math_input.dart';
import '../domain/scan_source.dart';
import 'widgets/math_keyboard.dart';

/// Arguments passed as the route `extra` for [ManualInputScreen].
class ManualInputArgs {
  const ManualInputArgs({this.initialLatex, this.editMode = false});

  /// Pre-fills the editor — e.g. a recognized OCR result the user is correcting.
  final String? initialLatex;

  /// EDITOR mode (§3 detected-equation edit): the primary action returns the
  /// corrected LaTeX to the caller instead of solving + metering — the scan was
  /// already charged at recognition, so re-solving here must not re-charge.
  final bool editMode;
}

/// Type a math problem with the educational math keyboard, then hand it to the
/// exact same pipeline a scanned problem uses.
///
/// After "Solve" the typed LaTeX is wrapped into a [DetectedEquation] via the
/// shared [ScannerService] (source `manual`, no OCR) and pushed to `/scan/result`
/// — where the existing solver, Visual Learning Engine, AI Tutor and Adaptive
/// Practice all run unchanged. No separate solving architecture.
///
/// With [ManualInputArgs.editMode] it doubles as the §3 detected-equation
/// editor: pre-filled with the recognized LaTeX, its primary action returns the
/// correction (`context.pop(latex)`) so the scanner can solve it via the
/// already-charged scan (no double metering).
class ManualInputScreen extends ConsumerStatefulWidget {
  const ManualInputScreen({super.key, this.args});

  final ManualInputArgs? args;

  @override
  ConsumerState<ManualInputScreen> createState() => _ManualInputScreenState();
}

class _ManualInputScreenState extends ConsumerState<ManualInputScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    // Pre-fill with the recognized LaTeX when editing an OCR result, caret at end.
    final initial = widget.args?.initialLatex?.trim();
    if (initial != null && initial.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: initial,
        selection: TextSelection.collapsed(offset: initial.length),
      );
    }
    // Focus the field so the caret shows; readOnly keeps the OS keyboard away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {
      if (_error != null) _error = null; // clear the error as they edit
    });
  }

  // ---- Editing (driven by the math keyboard) --------------------------------

  void _insert(String latex, int caretBack) {
    final value = _controller.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    final text = value.text.replaceRange(start, end, latex);
    final caret = (start + latex.length - caretBack).clamp(0, text.length);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  void _backspace() {
    final value = _controller.value;
    final sel = value.selection;
    if (!sel.isValid) return;
    if (sel.start != sel.end) {
      final text = value.text.replaceRange(sel.start, sel.end, '');
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: sel.start),
      );
      return;
    }
    final caret = sel.start;
    if (caret <= 0) return;
    // Delete a trailing LaTeX command (\sin, \theta, \sqrt…) as one unit.
    final before = value.text.substring(0, caret);
    final match = RegExp(r'\\[a-zA-Z]+$').firstMatch(before);
    final from = match != null ? match.start : caret - 1;
    final text = value.text.replaceRange(from, caret, '');
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: from),
    );
  }

  void _move(int delta) {
    final value = _controller.value;
    final sel = value.selection;
    final base = sel.isValid ? sel.baseOffset : value.text.length;
    final pos = (base + delta).clamp(0, value.text.length);
    _controller.selection = TextSelection.collapsed(offset: pos);
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  // ---- Submit ---------------------------------------------------------------

  /// Edit mode (§3): validate and return the corrected LaTeX to the caller (the
  /// scanner). No recognize, no solve, no metering — the scan was already
  /// charged at recognition, so the scanner re-solves it via that same scan.
  void _useCorrected() {
    final latex = _controller.text.trim();
    final error = MathInput.validate(latex);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    context.pop(latex);
  }

  /// Standalone typing: wrap the LaTeX and run it through the full scan pipeline
  /// (identical downstream treatment to a scan).
  Future<void> _solve() async {
    final latex = _controller.text.trim();
    final error = MathInput.validate(latex);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    // Manual solves draw from the same free-tier scan quota as a scan.
    if (!ref.read(usageSnapshotProvider).canScan) {
      context.pushReplacement(AppRoutes.paywall, extra: PaywallTrigger.scanLimit);
      return;
    }

    setState(() => _submitting = true);
    final analytics = ref.read(analyticsServiceProvider);
    unawaited(
        analytics.logEvent(AnalyticsEvent.scanStarted(source: ScanSource.manual.name)));

    DetectedEquation equation;
    try {
      equation = await ref
          .read(scannerServiceProvider)
          .recognize(ScanSource.manual, manualLatex: latex);
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = context.l10n.manualErrorGeneric;
      });
      return;
    }

    if (!mounted) return;
    unawaited(analytics.logEvent(AnalyticsEvent.recognitionSucceeded(
      source: ScanSource.manual.name,
      confidence: equation.confidencePercent,
    )));
    unawaited(analytics.logEvent(AnalyticsEvent.scanCompleted()));
    // Record the solve exactly like the scanner's ScanComplete handoff.
    ref.read(statsControllerProvider.notifier).recordScan();
    ref.read(usageControllerProvider.notifier).recordScan();
    context.pushReplacement(AppRoutes.scanResult, extra: equation);
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final editMode = widget.args?.editMode ?? false;
    final canSolve = _controller.text.trim().isNotEmpty && !_submitting;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(editMode
            ? context.l10n.manualFixProblem
            : context.l10n.manualTypeProblem),
        leading: IconButton(
          tooltip: context.l10n.actionClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _preview(colors)),
                  const SizedBox(height: AppSpacing.lg),
                  _field(colors),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _errorRow(colors),
                  ],
                ],
              ),
            ),
          ),
          MathKeyboard(
            onInsert: _insert,
            onBackspace: _backspace,
            onMoveLeft: () => _move(-1),
            onMoveRight: () => _move(1),
            solveLabel: editMode ? context.l10n.manualUseThis : context.l10n.scanSolve,
            onSolve: canSolve
                ? (editMode ? _useCorrected : () => unawaited(_solve()))
                : null,
          ),
        ],
      ),
    );
  }

  Widget _preview(AppSemanticColors colors) {
    final latex = _controller.text.trim();
    if (latex.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.functions_rounded, size: 44, color: colors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l10n.manualPreviewEmpty,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'e.g.  2x + 5 = 13',
              style: AppTypography.mono.copyWith(
                color: colors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }
    return Center(
      child: MathText(
        latex,
        style: AppTypography.displaySmall.copyWith(color: colors.textPrimary),
      ),
    );
  }

  Widget _field(AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.mdRadius,
        border: Border.all(
          color: _error != null ? AppColors.error : colors.border,
          width: _error != null ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        readOnly: true, // built only via the math keyboard — no OS keyboard
        showCursor: true,
        keyboardType: TextInputType.none,
        // Theme-aware emerald: the caret is load-bearing here (the keyboard has
        // explicit move-left/right keys), and a fixed primaryAction would sit at
        // ~2:1 on the dark surface.
        cursorColor: colors.onPrimaryContainer,
        style: AppTypography.mono.copyWith(
          fontSize: 16,
          height: 1.4,
          letterSpacing: 0.2,
          color: colors.textPrimary,
        ),
        decoration: InputDecoration.collapsed(
          hintText: r'Tap keys to type · e.g. 2x+5=13',
          hintStyle: AppTypography.mono.copyWith(
            fontSize: 14,
            letterSpacing: 0.2,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _errorRow(AppSemanticColors colors) {
    // errorText, not AppColors.error: the raw hue is 2.87:1 on the dark surface.
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 16, color: colors.errorText),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            _error!,
            style: AppTypography.caption.copyWith(color: colors.errorText),
          ),
        ),
      ],
    );
  }
}
