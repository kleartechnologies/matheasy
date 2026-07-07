import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../core/session/app_session.dart';
import '../../../core/widgets/widgets.dart';
import '../../../shared/dev/nav_placeholder.dart';

/// Top-level paywall (pushed over the shell, dismissible). The full RevenueCat
/// paywall arrives in Stage 11. The demo action grants the premium
/// entitlement and dismisses.
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavPlaceholder(
      title: 'Matheasy Premium',
      subtitle: 'The full plans + trial paywall arrives in Stage 11.',
      expression: NumiExpression.celebrate,
      showBack: true,
      actions: [
        PrimaryButton(
          label: 'Start free trial (demo)',
          icon: Icons.bolt_rounded,
          onPressed: () {
            ref.read(premiumControllerProvider.notifier).setPremium(value: true);
            if (context.canPop()) context.pop();
          },
        ),
        GhostButton(
          label: 'Restore purchases',
          expand: true,
          onPressed: () {},
        ),
      ],
    );
  }
}
