import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/presentation/widgets/auth_provider_button.dart';
import 'account_upgrade_benefits.dart';

/// Presents the guest → account upgrade flow in a bottom sheet: the account
/// benefits and the Apple / Google sign-in options. On success the guest's
/// local progress is preserved and the sheet closes.
Future<void> showGuestUpgradeSheet(BuildContext context) {
  return AppBottomSheet.show<void>(
    context,
    title: 'Create your free account',
    child: const _GuestUpgradeSheet(),
  );
}

class _GuestUpgradeSheet extends ConsumerStatefulWidget {
  const _GuestUpgradeSheet();

  @override
  ConsumerState<_GuestUpgradeSheet> createState() => _GuestUpgradeSheetState();
}

class _GuestUpgradeSheetState extends ConsumerState<_GuestUpgradeSheet> {
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

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (prev, next) {
      final failure = next.failure;
      if (failure != null &&
          !failure.isSilent &&
          failure != prev?.failure) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
      }
      if ((prev?.busy ?? false) && !next.busy && _pending != null) {
        setState(() => _pending = null);
      }
      // Guest successfully upgraded to a real account.
      final upgraded =
          next.user != null && !next.isGuest && (prev?.isGuest ?? true);
      if (upgraded && mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Welcome! Your progress is saved.')),
          );
      }
    });

    final busy = ref.watch(authControllerProvider.select((s) => s.busy));
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AccountUpgradeBenefits(spacing: AppSpacing.lg),
        const SizedBox(height: AppSpacing.xxl),
        AuthProviderButton(
          provider: AuthButtonProvider.apple,
          isLoading: _pending == AuthButtonProvider.apple,
          onPressed: busy ? null : () => _signIn(AuthButtonProvider.apple),
        ),
        const SizedBox(height: AppSpacing.md),
        AuthProviderButton(
          provider: AuthButtonProvider.google,
          isLoading: _pending == AuthButtonProvider.google,
          onPressed: busy ? null : () => _signIn(AuthButtonProvider.google),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Your progress stays on this device and links to your new account.',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}
