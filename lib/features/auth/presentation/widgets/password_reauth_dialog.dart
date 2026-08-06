import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/app_button.dart';
import '../../application/auth_controller.dart';
import '../../domain/auth_failure.dart';

/// Collects an email-account's password to re-prove identity before a
/// destructive action — the interactive counterpart of the silent federated
/// re-auth inside `ensureRecentLogin`.
///
/// Pops `true` once re-authentication succeeds, `false`/`null` when the user
/// backs out. Wrong passwords stay inside the dialog as an inline error, so
/// the destructive flow only ever resumes behind a fresh session.
class PasswordReauthDialog extends ConsumerStatefulWidget {
  const PasswordReauthDialog({super.key});

  static Future<bool?> show(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => const PasswordReauthDialog(),
      );

  @override
  ConsumerState<PasswordReauthDialog> createState() =>
      _PasswordReauthDialogState();
}

class _PasswordReauthDialogState extends ConsumerState<PasswordReauthDialog> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .reauthenticateWithPassword(_password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = const AuthFailure.unknown().message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xxl),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: emerald.withValues(alpha: 0.12),
                borderRadius: AppRadius.lgRadius,
              ),
              child: Icon(Icons.lock_outline_rounded, color: emerald, size: 28),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.authReauthTitle,
              textAlign: TextAlign.center,
              style:
                  AppTypography.headingSmall.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.authReauthMessage,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => unawaited(_confirm()),
              style:
                  AppTypography.bodyLarge.copyWith(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.authEmailPasswordLabel,
                labelStyle:
                    AppTypography.bodyLarge.copyWith(color: colors.textMuted),
                errorText: _error,
                errorStyle:
                    AppTypography.caption.copyWith(color: colors.errorText),
                errorMaxLines: 3,
                filled: true,
                fillColor: colors.surface,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  tooltip: _obscure
                      ? l10n.authEmailShowPassword
                      : l10n.authEmailHidePassword,
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: colors.textSecondary,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.mdRadius,
                  borderSide: BorderSide(color: colors.border, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadius.mdRadius,
                  borderSide: BorderSide(color: emerald, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: AppRadius.mdRadius,
                  borderSide: BorderSide(color: colors.errorText, width: 1.5),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: AppRadius.mdRadius,
                  borderSide: BorderSide(color: colors.errorText, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: l10n.actionCancel,
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryButton(
                    label: l10n.authReauthConfirm,
                    isLoading: _busy,
                    onPressed: _busy ? null : () => unawaited(_confirm()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
