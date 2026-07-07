import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets/gallery_section.dart';

/// The living design-QA surface. Every design token and shared component is
/// rendered here so we can visually verify the system — in both light and dark
/// mode via the app-bar toggle.
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  int _tabIndex = 0;
  int _selectedChip = 0;
  double _progress = 0.66;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Component Gallery'),
        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            icon: Icon(
              context.isDark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
            onPressed: () =>
                ref.read(themeModeControllerProvider.notifier).toggle(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.huge,
        ),
        children: [
          _colors(context),
          _typography(context),
          _buttons(context),
          _cards(context),
          _chips(context),
          _progressSection(context),
          _chat(context),
          _feedback(context),
          _numi(context),
          _overlays(context),
          _navigation(context),
        ],
      ),
    );
  }

  // ---- Colors ----
  Widget _colors(BuildContext context) {
    final c = context.colors;
    final swatches = <(String, Color)>[
      ('primary', AppColors.primary),
      ('secondary', AppColors.secondary),
      ('success', AppColors.success),
      ('warning', AppColors.warning),
      ('gold', AppColors.gold),
      ('error', AppColors.error),
      ('pink', AppColors.pink),
      ('xp', AppColors.xp),
      ('surface', c.surface),
      ('surfaceMuted', c.surfaceMuted),
      ('background', c.background),
      ('border', c.border),
      ('textPrimary', c.textPrimary),
      ('textSecondary', c.textSecondary),
      ('primaryContainer', c.primaryContainer),
      ('successContainer', c.successContainer),
    ];
    return GallerySection(
      title: 'Colors',
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [for (final s in swatches) _Swatch(name: s.$1, color: s.$2)],
      ),
    );
  }

  // ---- Typography ----
  Widget _typography(BuildContext context) {
    final samples = <(String, TextStyle)>[
      ('Display Large', AppTypography.displayLarge),
      ('Display Medium', AppTypography.displayMedium),
      ('Display Small', AppTypography.displaySmall),
      ('Heading Large', AppTypography.headingLarge),
      ('Heading Medium', AppTypography.headingMedium),
      ('Heading Small', AppTypography.headingSmall),
      ('Title', AppTypography.title),
      ('Body Large', AppTypography.bodyLarge),
      ('Body Medium', AppTypography.bodyMedium),
      ('Body Small', AppTypography.bodySmall),
      ('Caption', AppTypography.caption),
      ('LABEL', AppTypography.label),
    ];
    return GallerySection(
      title: 'Typography',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in samples)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                s.$1,
                style: s.$2.copyWith(color: context.colors.textPrimary),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Buttons ----
  Widget _buttons(BuildContext context) {
    return GallerySection(
      title: 'Buttons',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            label: 'Continue learning',
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Loading',
            isLoading: true,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.md),
          const PrimaryButton(label: 'Disabled'),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: 'Ask Numi',
            icon: Icons.smart_toy_rounded,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: GhostButton(label: 'Skip', onPressed: () {}),
          ),
        ],
      ),
    );
  }

  // ---- Cards ----
  Widget _cards(BuildContext context) {
    return GallerySection(
      title: 'Cards',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Text(
              'AppCard — the default elevated surface used across the app.',
              style: AppTypography.bodyMedium
                  .copyWith(color: context.colors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppRadius.cardRadius,
            ),
            child: GlassCard(
              child: Text(
                'GlassCard — frosted surface for overlays on imagery.',
                style: AppTypography.bodyMedium
                    .copyWith(color: context.colors.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Row(
            children: [
              Expanded(
                child: StatCard(
                  icon: Icons.local_fire_department_rounded,
                  value: '12',
                  label: 'Day streak',
                  iconColor: AppColors.streak,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  icon: Icons.bolt_rounded,
                  value: '1,240',
                  label: 'Total XP',
                  iconColor: AppColors.xp,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  icon: Icons.track_changes_rounded,
                  value: '87%',
                  label: 'Accuracy',
                  iconColor: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const StreakCard(days: 12),
          const SizedBox(height: AppSpacing.md),
          const AchievementCard(
            icon: Icons.workspace_premium_rounded,
            title: 'Sharp Shooter',
            subtitle: '10 correct answers in a row',
            unlocked: true,
          ),
          const SizedBox(height: AppSpacing.md),
          const AchievementCard(
            icon: Icons.emoji_events_rounded,
            title: 'Marathon',
            subtitle: 'Keep a 30-day streak',
            progress: 0.4,
          ),
          const SizedBox(height: AppSpacing.md),
          PremiumFeatureTile(onTap: () {}),
          const SizedBox(height: AppSpacing.md),
          const MathSolutionCard(
            equationTex: r'2x + 5 = 13',
            label: 'DETECTED · 99%',
            caption: 'Linear equation · one unknown',
            answerTex: r'x = 4',
          ),
          const SizedBox(height: AppSpacing.md),
          const PracticeQuestionCard(
            questionTex: r'3x + 4 = 19',
            prompt: 'Solve for x',
          ),
        ],
      ),
    );
  }

  // ---- Chips ----
  Widget _chips(BuildContext context) {
    final labels = ['Explain simply', 'Another method', 'Practice', 'Teach me'];
    return GallerySection(
      title: 'Chips',
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (var i = 0; i < labels.length; i++)
            FeatureChip(
              label: labels[i],
              icon: i == 0 ? Icons.auto_awesome_rounded : null,
              selected: _selectedChip == i,
              onTap: () => setState(() => _selectedChip = i),
            ),
        ],
      ),
    );
  }

  // ---- Progress ----
  Widget _progressSection(BuildContext context) {
    return GallerySection(
      title: 'Progress components',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          XPProgressBar(value: _progress, label: 'Lesson progress'),
          const SizedBox(height: AppSpacing.md),
          const XPProgressBar(
            value: 0.4,
            gradient: AppColors.successGradient,
          ),
          const SizedBox(height: AppSpacing.md),
          Slider(
            value: _progress,
            onChanged: (v) => setState(() => _progress = v),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ProgressRing(
                value: _progress,
                child: Text(
                  '${(_progress * 100).round()}%',
                  style: AppTypography.title
                      .copyWith(color: context.colors.textPrimary),
                ),
              ),
              const ProgressRing(
                value: 0.88,
                progressColor: AppColors.success,
                child: Icon(Icons.check_rounded, color: AppColors.success),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Chat ----
  Widget _chat(BuildContext context) {
    return const GallerySection(
      title: 'Chat',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NumiBubble(
            text: 'Hi Sarah! Ask me anything about math — '
                'or snap a photo of a problem.',
          ),
          SizedBox(height: AppSpacing.md),
          ChatBubble(text: 'Why do we subtract 5?', isUser: true),
          SizedBox(height: AppSpacing.md),
          NumiTypingIndicator(),
        ],
      ),
    );
  }

  // ---- Feedback states ----
  Widget _feedback(BuildContext context) {
    return GallerySection(
      title: 'States',
      child: Column(
        children: [
          _framed(context, const LoadingState(message: 'Solving…')),
          const SizedBox(height: AppSpacing.md),
          _framed(
            context,
            ErrorState(
              message: "We couldn't read that problem. Try again.",
              onRetry: () {},
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _framed(
            context,
            EmptyState(
              title: 'No scans yet',
              message: 'Snap your first math problem to get started.',
              actionLabel: 'Scan a problem',
              onAction: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _framed(BuildContext context, Widget child) {
    return Container(
      height: 340,
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: AppRadius.cardRadius,
      ),
      child: child,
    );
  }

  // ---- Numi ----
  Widget _numi(BuildContext context) {
    const expressions = NumiExpression.values;
    return GallerySection(
      title: 'Numi mascot',
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.lg,
        alignment: WrapAlignment.center,
        children: [
          for (final e in expressions)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NumiMascot(expression: e, size: 88),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  e.name,
                  style: AppTypography.caption
                      .copyWith(color: context.colors.textSecondary),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ---- Overlays ----
  Widget _overlays(BuildContext context) {
    return GallerySection(
      title: 'Overlays',
      child: Row(
        children: [
          Expanded(
            child: SecondaryButton(
              label: 'Dialog',
              onPressed: () => AppDialog.show(
                context,
                icon: Icons.delete_outline_rounded,
                iconColor: AppColors.error,
                title: 'Clear history?',
                message: 'This removes all saved scans. This cannot be undone.',
                primaryLabel: 'Clear',
                secondaryLabel: 'Cancel',
                destructive: true,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: SecondaryButton(
              label: 'Bottom sheet',
              onPressed: () => AppBottomSheet.show(
                context,
                title: 'Choose a plan',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    PrimaryButton(
                      label: 'Start free trial',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Navigation ----
  Widget _navigation(BuildContext context) {
    return GallerySection(
      title: 'Navigation & layout',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Continue learning',
            actionLabel: 'See all',
            onAction: () {},
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: AppRadius.cardRadius,
            child: AppTabBar(
              currentIndex: _tabIndex,
              onTap: (i) => setState(() => _tabIndex = i),
              onScan: () {},
              badges: const {2: 3},
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppRadius.smRadius,
              border: Border.all(color: context.colors.border),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption
                .copyWith(color: context.colors.textSecondary, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}
