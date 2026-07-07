import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/pressable.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/haptics_service.dart';
import '../../../core/session/app_session.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/widgets.dart';
import '../application/onboarding_controller.dart';
import '../domain/onboarding_models.dart';
import 'pages/challenge_page.dart';
import 'pages/completion_page.dart';
import 'pages/daily_goal_page.dart';
import 'pages/exam_ready_page.dart';
import 'pages/meet_numi_page.dart';
import 'pages/practice_page.dart';
import 'pages/snap_solve_page.dart';
import 'pages/study_level_page.dart';
import 'pages/understand_page.dart';
import 'pages/welcome_page.dart';

/// Hosts the full onboarding flow: a button-driven [PageView] of 10 pages with
/// a top progress bar, contextual back/skip, and a gated bottom CTA.
///
/// Swiping is disabled so page state always advances through valid steps; the
/// per-page entrance animations live in the page layouts.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<Widget> _pages = [
    WelcomePage(), // 0
    SnapSolvePage(), // 1
    UnderstandPage(), // 2
    PracticePage(), // 3
    ExamReadyPage(), // 4
    MeetNumiPage(), // 5
    StudyLevelPage(), // 6
    ChallengePage(), // 7
    DailyGoalPage(), // 8
    CompletionPage(), // 9
  ];

  static const int _firstQuestion = 6;
  int get _lastPage => _pages.length - 1;
  bool get _isLast => _page == _lastPage;
  bool get _showSkip => _page >= 1 && _page <= 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(int index) {
    HapticsService.selection();
    _controller.animateToPage(
      index,
      duration: AppDurations.medium,
      curve: AppCurves.standard,
    );
  }

  void _next() => _isLast ? _finish() : _animateTo(_page + 1);
  void _back() => _animateTo(_page - 1);
  void _skip() => _animateTo(_firstQuestion);

  void _finish() {
    HapticsService.success();
    final data = ref.read(onboardingFlowControllerProvider);
    AppLogger.info('Onboarding complete → $data', name: 'onboarding');
    ref.read(onboardingControllerProvider.notifier).complete();
    context.go(AppRoutes.home);
  }

  bool _canContinue(OnboardingData data) => switch (_page) {
        6 => data.hasLevel,
        7 => data.hasTopics,
        8 => data.hasGoal,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(onboardingFlowControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.sm),
              _TopBar(
                progress: (_page + 1) / _pages.length,
                onBack: _page > 0 ? _back : null,
                onSkip: _showSkip ? _skip : null,
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) => setState(() => _page = index),
                  children: _pages,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.md,
                  bottom: AppSpacing.xl,
                ),
                child: PrimaryButton(
                  label: _page == 0 ? 'Get Started' : 'Continue',
                  trailingIcon: _isLast
                      ? Icons.check_circle_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: _canContinue(data) ? _next : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.progress, this.onBack, this.onSkip});

  final double progress;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    final skip = onSkip;
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: back == null
              ? null
              : _NavIconButton(icon: Icons.arrow_back_rounded, onTap: back),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: XPProgressBar(value: progress, height: 8)),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 52,
          child: skip == null
              ? null
              : GhostButton(
                  label: 'Skip',
                  size: AppButtonSize.small,
                  onPressed: skip,
                ),
        ),
      ],
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      borderRadius: AppRadius.smRadius,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadius.smRadius,
          border: Border.all(color: colors.border),
        ),
        child: Icon(icon, size: 20, color: colors.textPrimary),
      ),
    );
  }
}
