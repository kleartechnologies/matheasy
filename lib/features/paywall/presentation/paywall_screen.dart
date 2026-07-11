import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/animations/pressable.dart';
import '../../../core/services/haptics_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../../subscription/domain/purchase_result.dart';
import '../../subscription/domain/subscription_plan.dart';
import '../application/paywall_controller.dart';
import 'paywall_copy.dart';
import 'sections/paywall_comparison.dart';
import 'sections/paywall_hero.dart';
import 'widgets/paywall_plan_card.dart';
import 'widgets/purchase_success_overlay.dart';

/// The full RevenueCat paywall — pushed over the shell, dismissible.
///
/// Brand hero → three pricing cards (Annual preselected) → feature comparison,
/// with a persistent purchase + restore footer. Reads live prices and the
/// purchase flow from [PaywallController]; the entitlement itself is owned by
/// [SubscriptionController].
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.trigger = PaywallTrigger.manual});

  final PaywallTrigger trigger;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _celebrating = false;
  String _celebrationPlanName = 'Matheasy Pro';

  @override
  void initState() {
    super.initState();
    // Log the impression via the controller (analytics stays out of the widget).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(paywallControllerProvider.notifier)
            .markViewed(widget.trigger);
      }
    });
  }

  static String _planLabel(SubscriptionPlan? plan) => switch (plan) {
    SubscriptionPlan.proAnnual => 'Annual Pro',
    SubscriptionPlan.proMonthly => 'Monthly Pro',
    _ => 'Matheasy Pro',
  };

  void _onResult(PurchaseResult result) {
    switch (result) {
      case PurchaseSuccess(:final status):
        HapticsService.success();
        // Name the plan from the granted entitlement (not the selected card),
        // so a Restore celebrates the plan the user actually owns.
        setState(() {
          _celebrating = true;
          _celebrationPlanName = _planLabel(status.activePlan);
        });
        // Let the celebration play, then dismiss the paywall.
        Timer(const Duration(milliseconds: 1700), () {
          if (mounted) Navigator.of(context).maybePop();
        });
      case PurchasePending():
        _toast(
          'Your purchase is pending approval. It will unlock once '
          'confirmed.',
        );
      case PurchaseNothingToRestore():
        _toast('No previous purchases found to restore.');
      case PurchaseFailure(:final message):
        _toast(message);
      case PurchaseCancelled():
        break; // Silent — the user chose to back out.
    }
    ref.read(paywallControllerProvider.notifier).clearResult();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _purchase() async {
    final plan = ref.read(paywallControllerProvider).selectedPlan;
    if (!plan.isPaid) {
      Navigator.of(context).maybePop();
      return;
    }
    HapticsService.selection();
    await ref.read(paywallControllerProvider.notifier).purchaseSelected();
  }

  Future<void> _restore() async {
    HapticsService.selection();
    await ref.read(paywallControllerProvider.notifier).restore();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(paywallControllerProvider.select((s) => s.result), (_, next) {
      if (next != null) _onResult(next);
    });

    final state = ref.watch(paywallControllerProvider);
    final alreadyPro = ref.watch(isProProvider);

    // The paywall is always the dark indigo gradient, so force light status-bar
    // icons regardless of the OS/app theme it was opened from.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.paywallBottom,
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.paywallGradient),
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    _CloseBar(onClose: () => Navigator.of(context).maybePop()),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenH,
                          AppSpacing.sm,
                          AppSpacing.screenH,
                          AppSpacing.lg,
                        ),
                        children: [
                          PaywallHero(trigger: widget.trigger),
                          const SizedBox(height: AppSpacing.xl),
                          const _ProBenefits(),
                          const SizedBox(height: AppSpacing.xl),
                          _PlanCards(state: state),
                          const SizedBox(height: AppSpacing.xl),
                          const PaywallComparison(),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ),
                    ),
                    _Footer(
                      state: state,
                      alreadyPro: alreadyPro,
                      onPurchase: _purchase,
                      onRestore: _restore,
                      onDone: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              if (_celebrating)
                Positioned.fill(
                  child: PurchaseSuccessOverlay(planName: _celebrationPlanName),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseBar extends StatelessWidget {
  const _CloseBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          Pressable(
            onTap: onClose,
            borderRadius: AppRadius.pillRadius,
            child: Semantics(
              button: true,
              label: 'Close',
              // 48x48 accessible hit area around the 40x40 visual circle.
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCards extends ConsumerWidget {
  const _PlanCards({required this.state});

  final PaywallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annual = state.productFor(SubscriptionPlan.proAnnual);
    final monthly = state.productFor(SubscriptionPlan.proMonthly);
    final notifier = ref.read(paywallControllerProvider.notifier);

    void select(SubscriptionPlan plan) {
      HapticsService.selection();
      notifier.select(plan);
    }

    return Column(
      children: [
        PaywallPlanCard(
          title: 'Annual Pro',
          priceString:
              annual?.priceString ?? SubscriptionPlan.proAnnual.fallbackPrice,
          periodLabel: '/year',
          subtitle: PaywallCopy.annualValueLine(annual, monthly),
          badge: 'BEST VALUE',
          selected: state.selectedPlan == SubscriptionPlan.proAnnual,
          onTap: () => select(SubscriptionPlan.proAnnual),
        ),
        const SizedBox(height: AppSpacing.md),
        PaywallPlanCard(
          title: 'Monthly Pro',
          priceString:
              monthly?.priceString ?? SubscriptionPlan.proMonthly.fallbackPrice,
          periodLabel: '/month',
          subtitle: 'Everything unlimited, billed monthly',
          selected: state.selectedPlan == SubscriptionPlan.proMonthly,
          onTap: () => select(SubscriptionPlan.proMonthly),
        ),
        const SizedBox(height: AppSpacing.md),
        PaywallPlanCard(
          title: 'Free',
          priceString: 'RM0',
          periodLabel: 'forever',
          subtitle: '5 scans · 20 AI tutor messages · 10 practice',
          selected: state.selectedPlan == SubscriptionPlan.free,
          onTap: () => select(SubscriptionPlan.free),
        ),
      ],
    );
  }
}

/// A compact "what you get with Pro" value strip shown above the plan cards, so
/// every paywall impression sells the flagship experiences — led by Visual
/// Learning — before the price is ever asked.
class _ProBenefits extends StatelessWidget {
  const _ProBenefits();

  static const List<(IconData, Color, String, String)> _benefits = [
    (
      Icons.auto_awesome_rounded,
      AppColors.gold,
      'Visual Learning',
      'See every step animate — understand, don’t just memorize.',
    ),
    (
      Icons.fitness_center_rounded,
      AppColors.primaryLight,
      'Adaptive Practice',
      'Questions that target your exact weak spots.',
    ),
    (
      Icons.forum_rounded,
      AppColors.primaryLight,
      'AI Tutor',
      'A patient tutor that explains until it clicks.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What you get with Pro',
          style: AppTypography.label.copyWith(
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final (index, b) in _benefits.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.md),
          _BenefitRow(icon: b.$1, tint: b.$2, title: b.$3, detail: b.$4),
        ],
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.16),
            borderRadius: AppRadius.smRadius,
          ),
          child: Icon(icon, size: 21, color: tint),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.title.copyWith(color: AppColors.white),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.state,
    required this.alreadyPro,
    required this.onPurchase,
    required this.onRestore,
    required this.onDone,
  });

  final PaywallState state;
  final bool alreadyPro;
  final VoidCallback onPurchase;
  final VoidCallback onRestore;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final plan = state.selectedPlan;

    if (alreadyPro) {
      return _FooterShell(
        children: [
          Text(
            "You're on Matheasy Pro 🎉",
            textAlign: TextAlign.center,
            style: AppTypography.title.copyWith(color: AppColors.white),
          ),
          const SizedBox(height: AppSpacing.md),
          _GoldButton(label: 'Done', onTap: onDone),
        ],
      );
    }

    final isFree = !plan.isPaid;
    final priceString =
        state.productFor(plan)?.priceString ?? plan.fallbackPrice;
    final ctaLabel = isFree
        ? 'Continue with Free'
        : 'Start Pro · $priceString${plan.isAnnual ? '/yr' : '/mo'}';

    return _FooterShell(
      children: [
        _GoldButton(
          label: ctaLabel,
          loading: state.purchasing,
          filled: !isFree,
          onTap: state.busy ? null : onPurchase,
        ),
        const SizedBox(height: AppSpacing.sm),
        _RestoreButton(
          loading: state.restoring,
          onTap: state.busy ? null : onRestore,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          isFree
              ? 'You can upgrade anytime. Free includes limited scans, AI tutor '
                    'and practice.'
              : 'Auto-renews at $priceString until cancelled. Cancel anytime in '
                    'your store account. Terms & Privacy apply.',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.5),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FooterShell extends StatelessWidget {
  const _FooterShell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.paywallBottom.withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// The premium gold CTA. [filled] uses the gold gradient; otherwise an outlined
/// low-emphasis variant (for "Continue with Free").
class _GoldButton extends StatelessWidget {
  const _GoldButton({
    required this.label,
    required this.onTap,
    this.loading = false,
    this.filled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return Pressable(
      onTap: enabled ? onTap : null,
      borderRadius: AppRadius.pillRadius,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Container(
          height: 56,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: filled ? AppColors.goldGradient : null,
            color: filled ? null : Colors.white.withValues(alpha: 0.08),
            borderRadius: AppRadius.pillRadius,
            border: filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.24)),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.35),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(AppColors.onGold),
                  ),
                )
              : Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.button.copyWith(
                    color: filled ? AppColors.onGold : AppColors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

class _RestoreButton extends StatelessWidget {
  const _RestoreButton({required this.onTap, required this.loading});

  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        loading ? 'Restoring…' : 'Restore purchases',
        style: AppTypography.bodyMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: 0.82),
        ),
      ),
    );
  }
}
