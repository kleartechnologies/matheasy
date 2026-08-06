import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/controls/segmented_control.dart';
import '../application/auth_controller.dart';
import '../domain/auth_failure.dart';

/// The email/password face of the sign-in wall (`/auth/email`), reached from
/// the "Continue with email" button on [AuthScreen].
///
/// One screen, two modes behind a segmented toggle: sign in (email + password +
/// "Forgot password?") and sign up (name + email + password). Both submit
/// through [AuthController], so the anonymous-usage merge, analytics, and the
/// router's redirect-to-home on success behave exactly like Apple/Google.
class EmailAuthScreen extends ConsumerStatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  ConsumerState<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

enum _Mode { signIn, signUp }

class _EmailAuthScreenState extends ConsumerState<EmailAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _obscurePassword = true;
  bool _submitted = false;
  bool _sendingReset = false;

  /// Deliberately permissive — the server is the real validator. This only
  /// catches obvious slips (no `@`, no domain) before a network round-trip.
  static final RegExp _emailShape = RegExp(r'^\S+@\S+\.\S+$');

  /// Firebase's default password policy minimum.
  static const int _minPasswordLength = 6;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _switchMode(int index) {
    final mode = _Mode.values[index];
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      // A fresh mode is a fresh form — don't drag sign-in errors into sign-up.
      _submitted = false;
      _formKey.currentState?.reset();
    });
  }

  void _submit() {
    setState(() => _submitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final notifier = ref.read(authControllerProvider.notifier);
    final email = _email.text.trim();
    final password = _password.text;
    unawaited(switch (_mode) {
      _Mode.signIn => notifier.signInWithEmail(email: email, password: password),
      _Mode.signUp => notifier.signUpWithEmail(
          name: _name.text.trim(),
          email: email,
          password: password,
        ),
    });
  }

  Future<void> _sendPasswordReset() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final email = _email.text.trim();
    if (!_emailShape.hasMatch(email)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.authEmailInvalid)));
      return;
    }
    setState(() => _sendingReset = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .sendPasswordReset(email);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.authEmailResetSent)));
    } on AuthFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    ref.listen(authControllerProvider, (prev, next) {
      final failure = next.failure;
      if (failure != null && !failure.isSilent && failure != prev?.failure) {
        _showError(failure.message);
      }
    });

    final busy = ref.watch(authControllerProvider.select((s) => s.busy));
    final signUp = _mode == _Mode.signUp;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: colors.textPrimary,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.md,
                AppSpacing.screenH,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    signUp
                        ? l10n.authEmailSignUpTitle
                        : l10n.authEmailSignInTitle,
                    style: AppTypography.displaySmall
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    signUp
                        ? l10n.authEmailSignUpSubtitle
                        : l10n.authEmailSignInSubtitle,
                    style: AppTypography.bodyLarge
                        .copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SegmentedControl(
                    items: [
                      SegmentItem(label: l10n.authEmailTabSignIn),
                      SegmentItem(label: l10n.authEmailTabSignUp),
                    ],
                    selectedIndex: _mode.index,
                    onChanged: busy ? (_) {} : _switchMode,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Form(
                    key: _formKey,
                    autovalidateMode: _submitted
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (signUp) ...[
                            _AuthField(
                              controller: _name,
                              label: l10n.authEmailNameLabel,
                              textCapitalization: TextCapitalization.words,
                              keyboardType: TextInputType.name,
                              autofillHints: const [AutofillHints.name],
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? l10n.authEmailNameRequired
                                      : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          _AuthField(
                            controller: _email,
                            label: l10n.authEmailFieldLabel,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            validator: (value) =>
                                _emailShape.hasMatch(value?.trim() ?? '')
                                    ? null
                                    : l10n.authEmailInvalid,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _AuthField(
                            controller: _password,
                            label: l10n.authEmailPasswordLabel,
                            obscureText: _obscurePassword,
                            autofillHints: [
                              signUp
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: busy ? null : (_) => _submit(),
                            // Sign-in must accept whatever the account was
                            // created with — only sign-up enforces the policy.
                            validator: (value) {
                              final password = value ?? '';
                              if (password.isEmpty) {
                                return l10n.authEmailPasswordRequired;
                              }
                              if (signUp &&
                                  password.length < _minPasswordLength) {
                                return l10n.authEmailPasswordTooShort;
                              }
                              return null;
                            },
                            suffix: IconButton(
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                              tooltip: _obscurePassword
                                  ? l10n.authEmailShowPassword
                                  : l10n.authEmailHidePassword,
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          if (!signUp) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Align(
                              alignment: Alignment.centerRight,
                              child: GhostButton(
                                label: l10n.authEmailForgotPassword,
                                onPressed: _sendingReset || busy
                                    ? null
                                    : () => unawaited(_sendPasswordReset()),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          PrimaryButton(
                            label: signUp
                                ? l10n.authEmailSignUpAction
                                : l10n.authEmailSignInAction,
                            isLoading: busy,
                            onPressed: busy ? null : _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One themed form field, matching the app's input idiom (surface fill, border
/// that turns emerald on focus, AA-safe label colours).
class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.autofillHints,
    this.textInputAction,
    this.onFieldSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final List<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: color, width: 1.5),
        );
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      autocorrect: !obscureText,
      enableSuggestions: !obscureText,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: AppTypography.bodyLarge.copyWith(color: colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypography.bodyLarge.copyWith(color: colors.textMuted),
        floatingLabelStyle: AppTypography.bodyMedium.copyWith(
          color: context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
        ),
        filled: true,
        fillColor: colors.surface,
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        enabledBorder: border(colors.border),
        focusedBorder: border(
          context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
        ),
        errorBorder: border(colors.errorText),
        focusedErrorBorder: border(colors.errorText),
        errorStyle: AppTypography.caption.copyWith(color: colors.errorText),
      ),
    );
  }
}
