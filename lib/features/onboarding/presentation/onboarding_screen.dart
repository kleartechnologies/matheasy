import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/l10n_extension.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/haptics_service.dart';
import '../../../core/session/app_session.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/widgets.dart';
import '../application/onboarding_controller.dart';
import 'pages/level_select_page.dart';
import 'pages/practice_intro_page.dart';
import 'pages/ready_page.dart';
import 'pages/scan_intro_page.dart';
import 'pages/steps_intro_page.dart';
import 'widgets/onboarding_dots.dart';

/// Hosts the onboarding carousel: five button-driven pages (three value-props,
/// a level picker, and the finale) under a brand bar, page dots, and a bottom
/// CTA. Swiping is disabled so state always advances through valid steps; the
/// per-page entrance + ambient animations live in the pages themselves.
///
/// Finishing (either finale CTA) flips the persisted onboarding flag and hands
/// off to the auth screen — the single Apple/Google sign-in that serves both new
/// and returning learners.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<Widget> _pages = [
    ScanIntroPage(), // 0
    StepsIntroPage(), // 1
    PracticeIntroPage(), // 2
    LevelSelectPage(), // 3
    ReadyPage(), // 4
  ];

  int get _lastPage => _pages.length - 1;
  bool get _isLast => _page == _lastPage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(int index) {
    HapticsService.selection();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(index);
      return;
    }
    _controller.animateToPage(
      index,
      duration: AppDurations.medium,
      curve: AppCurves.standard,
    );
  }

  void _next() => _isLast ? _finish() : _animateTo(_page + 1);
  void _skip() => _animateTo(_lastPage);

  void _finish() {
    HapticsService.success();
    final data = ref.read(onboardingFlowControllerProvider);
    AppLogger.info('Onboarding complete → $data', name: 'onboarding');
    ref.read(onboardingControllerProvider.notifier).complete();
    if (mounted) context.go(AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.sm),
              _TopBar(onSkip: _isLast ? null : _skip),
              Expanded(
                child: PageView(
                  controller: _controller,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) => setState(() => _page = index),
                  children: _pages,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OnboardingDots(count: _pages.length, index: _page),
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.lg,
                  bottom: AppSpacing.lg,
                ),
                child: _isLast
                    ? _FinaleActions(onFinish: _finish)
                    : _ContinueAction(onNext: _next),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueAction extends StatelessWidget {
  const _ContinueAction({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(label: context.l10n.actionContinue, onPressed: onNext);
  }
}

class _FinaleActions extends StatelessWidget {
  const _FinaleActions({required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrimaryButton(
          label: context.l10n.onboardingGetStarted,
          onPressed: onFinish,
        ),
        const SizedBox(height: AppSpacing.xs),
        GhostButton(
          label: context.l10n.onboardingHaveAccount,
          onPressed: onFinish,
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.onSkip});

  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final skip = onSkip;
    return Row(
      children: [
        const MatheasyLogo(size: MatheasyLogoSize.small),
        const Spacer(),
        if (skip != null)
          // Default GhostButton size (medium) gives a 48dp tap target.
          GhostButton(label: context.l10n.onboardingSkip, onPressed: skip),
      ],
    );
  }
}
