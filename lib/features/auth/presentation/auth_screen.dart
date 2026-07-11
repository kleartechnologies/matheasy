import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/animations/floaty.dart';
import '../../../core/brand/brand.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../settings/presentation/legal_document_screen.dart';
import '../application/auth_controller.dart';
import 'widgets/auth_benefit_row.dart';
import 'widgets/auth_provider_button.dart';

/// The premium sign-in experience: the official Matheasy logo, the value
/// proposition, and the two ways in — Apple or Google. Sign-in is required
/// (there is no guest mode), so the app's AI features always run for a real
/// account rather than on canned offline data.
///
/// Navigation is handled by the router guard, not here: the moment the session
/// becomes authenticated, the guard redirects away from `/auth`.
/// This screen only triggers actions and reflects their loading/error state.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  AuthButtonProvider? _pending;

  void _signIn(AuthButtonProvider provider) {
    setState(() => _pending = provider);
    final notifier = ref.read(authControllerProvider.notifier);
    unawaited(
      provider == AuthButtonProvider.apple
          ? notifier.signInWithApple()
          : notifier.signInWithGoogle(),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Surface failures (non-cancellations) and stop the spinner when a sign-in
    // attempt settles.
    ref.listen(authControllerProvider, (prev, next) {
      final failure = next.failure;
      if (failure != null &&
          !failure.isSilent &&
          failure != prev?.failure) {
        _showError(failure.message);
      }
      if ((prev?.busy ?? false) && !next.busy && _pending != null) {
        setState(() => _pending = null);
      }
    });

    final busy = ref.watch(authControllerProvider.select((s) => s.busy));

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.xl,
                AppSpacing.screenH,
                AppSpacing.xl,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppTransitions.scaleIn(
                    child: const Floaty(
                      child: MatheasyLogo(
                        variant: MatheasyLogoVariant.vertical,
                        markSize: 88,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Learn math with AI',
                    textAlign: TextAlign.center,
                    style: AppTypography.displaySmall
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "Welcome to Matheasy! Let's start learning together.",
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLarge
                        .copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  const _Benefits(),
                  const SizedBox(height: AppSpacing.xxxl),
                  _Actions(
                    busy: busy,
                    pending: _pending,
                    onApple: () => _signIn(AuthButtonProvider.apple),
                    onGoogle: () => _signIn(AuthButtonProvider.google),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _LegalFootnote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Benefits extends StatelessWidget {
  const _Benefits();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AuthBenefitRow(
          icon: Icons.center_focus_strong_rounded,
          color: AppColors.primary,
          title: 'Scan questions',
          subtitle: 'Snap any problem and get a clear, worked solution.',
        ),
        SizedBox(height: AppSpacing.lg),
        AuthBenefitRow(
          icon: Icons.auto_awesome_rounded,
          color: AppColors.secondary,
          title: 'Learn faster',
          subtitle: 'Matheasy explains the why, at your level, step by step.',
        ),
        SizedBox(height: AppSpacing.lg),
        AuthBenefitRow(
          icon: Icons.fitness_center_rounded,
          color: AppColors.accentAmber,
          title: 'Practice smarter',
          subtitle: 'Targeted practice that adapts as you improve.',
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.busy,
    required this.pending,
    required this.onApple,
    required this.onGoogle,
  });

  final bool busy;
  final AuthButtonProvider? pending;
  final VoidCallback onApple;
  final VoidCallback onGoogle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AuthProviderButton(
          provider: AuthButtonProvider.apple,
          isLoading: pending == AuthButtonProvider.apple,
          onPressed: busy ? null : onApple,
        ),
        const SizedBox(height: AppSpacing.md),
        AuthProviderButton(
          provider: AuthButtonProvider.google,
          isLoading: pending == AuthButtonProvider.google,
          onPressed: busy ? null : onGoogle,
        ),
      ],
    );
  }
}

class _LegalFootnote extends StatelessWidget {
  const _LegalFootnote();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final linkStyle = AppTypography.caption.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
    );
    return Column(
      children: [
        Text(
          'By continuing you agree to our',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegalLink(
              label: 'Terms',
              document: LegalDocument.terms,
              style: linkStyle,
            ),
            Text(
              '  ·  ',
              style: AppTypography.caption.copyWith(color: colors.textTertiary),
            ),
            _LegalLink(
              label: 'Privacy Policy',
              document: LegalDocument.privacy,
              style: linkStyle,
            ),
          ],
        ),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.label,
    required this.document,
    required this.style,
  });

  final String label;
  final LegalDocument document;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: document.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LegalDocumentScreen(document: document),
          ),
        ),
        // Label already carried by the Semantics above — don't announce twice.
        child: ExcludeSemantics(
          // ≥48dp tap target around the small caption link.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(label, style: style),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
