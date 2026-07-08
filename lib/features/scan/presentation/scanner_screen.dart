import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../core/animations/floaty.dart';
import '../../../core/animations/pressable.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../progress/application/stats_controller.dart';
import '../application/scanner_controller.dart';
import '../domain/detected_equation.dart';
import '../domain/scan_source.dart';
import '../domain/scan_state.dart';
import 'widgets/camera_viewport.dart';
import 'widgets/capture_confirmation.dart';
import 'widgets/processing_overlay.dart';
import 'widgets/scan_frame.dart';

/// The full-screen, immersive scanner. Pushed over the shell (no tab bar).
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  bool _flashOn = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    final controller = ref.read(scannerControllerProvider.notifier);

    // Hand off to the result screen when analysis completes, and record the
    // scan for progress/achievements.
    ref.listen(scannerControllerProvider, (previous, next) {
      if (next is ScanComplete) {
        ref.read(statsControllerProvider.notifier).recordScan();
        context.pushReplacement(AppRoutes.scanResult, extra: next.equation);
      }
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.scannerBackground,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const CameraViewport(),
            AnimatedSwitcher(
              duration: AppDurations.medium,
              child: _content(state, controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(ScanState state, ScannerController controller) {
    return switch (state) {
      ScanIdle() => _ScanningChrome(
          key: const ValueKey('scanning'),
          locked: false,
          flashOn: _flashOn,
          onFlash: () => setState(() => _flashOn = !_flashOn),
          onClose: () => context.pop(),
          onGallery: () => controller.capture(ScanSource.gallery),
          onShutter: () => controller.capture(ScanSource.camera),
          onType: () => controller.capture(ScanSource.manual),
        ),
      ScanDetecting() => _ScanningChrome(
          key: const ValueKey('scanning'),
          locked: true,
          flashOn: _flashOn,
          onFlash: () => setState(() => _flashOn = !_flashOn),
          onClose: () => context.pop(),
          onGallery: () => controller.capture(ScanSource.gallery),
          onShutter: () => controller.capture(ScanSource.camera),
          onType: () => controller.capture(ScanSource.manual),
        ),
      ScanCaptured(:final equation) => _CapturedView(
          key: const ValueKey('captured'),
          equation: equation,
          onClose: () => context.pop(),
          onRetake: controller.retake,
          onContinue: controller.confirm,
        ),
      ScanProcessing() =>
        const ProcessingOverlay(key: ValueKey('processing')),
      ScanComplete() => const SizedBox.shrink(key: ValueKey('complete')),
      ScanError(:final message) => _ErrorView(
          key: const ValueKey('error'),
          message: message,
          onRetry: controller.retake,
        ),
    };
  }
}

// ---------------------------------------------------------------------------
// Scanning chrome (idle + detecting)
// ---------------------------------------------------------------------------

class _ScanningChrome extends StatelessWidget {
  const _ScanningChrome({
    super.key,
    required this.locked,
    required this.flashOn,
    required this.onFlash,
    required this.onClose,
    required this.onGallery,
    required this.onShutter,
    required this.onType,
  });

  final bool locked;
  final bool flashOn;
  final VoidCallback onFlash;
  final VoidCallback onClose;
  final VoidCallback onGallery;
  final VoidCallback onShutter;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _TopBar(flashOn: flashOn, onFlash: onFlash, onClose: onClose),
          const SizedBox(height: AppSpacing.md),
          Text(
            locked
                ? 'Looks good — tap the shutter to solve'
                : 'Line up the whole question inside the frame',
            style: AppTypography.bodySmall
                .copyWith(color: Colors.white.withValues(alpha: 0.75)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(34, AppSpacing.xl, 34, 0),
              child: Align(
                alignment: const Alignment(0, -0.35),
                child: AspectRatio(
                  aspectRatio: 1.6,
                  child: ScanFrame(locked: locked),
                ),
              ),
            ),
          ),
          const _NumiHint(),
          _BottomControls(
            locked: locked,
            onGallery: onGallery,
            onShutter: onShutter,
            onType: onType,
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.flashOn,
    required this.onFlash,
    required this.onClose,
  });

  final bool flashOn;
  final VoidCallback onFlash;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _GlassButton(icon: Icons.close_rounded, onTap: onClose),
          const Spacer(),
          Text(
            'Scan a problem',
            style: AppTypography.title.copyWith(color: AppColors.white),
          ),
          const Spacer(),
          _GlassButton(
            icon: flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            onTap: onFlash,
          ),
        ],
      ),
    );
  }
}

class _NumiHint extends StatelessWidget {
  const _NumiHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xl, bottom: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppRadius.md),
                topRight: Radius.circular(AppRadius.md),
                bottomLeft: Radius.circular(AppRadius.md),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              'Point at a whole question — I’ll read it for you.',
              style: AppTypography.caption
                  .copyWith(color: AppColors.scannerBackground),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Floaty(child: NumiMascot(size: 52)),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.locked,
    required this.onGallery,
    required this.onShutter,
    required this.onType,
  });

  final bool locked;
  final VoidCallback onGallery;
  final VoidCallback onShutter;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, AppSpacing.md, 44, AppSpacing.xxl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _LabeledControl(
            icon: Icons.photo_library_rounded,
            label: 'Gallery',
            onTap: onGallery,
          ),
          _ShutterButton(locked: locked, onTap: onShutter),
          _LabeledControl(
            icon: Icons.keyboard_rounded,
            label: 'Type it',
            onTap: onType,
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.locked, required this.onTap});

  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      borderRadius: AppRadius.pillRadius,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: locked
                ? AppColors.primaryTint
                : Colors.white.withValues(alpha: 0.4),
            width: 5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: locked ? AppColors.primaryGradient : null,
              color: locked ? null : AppColors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassButton(icon: icon, onTap: onTap, size: 52),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.caption
              .copyWith(color: Colors.white.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onTap, this.size = 42});

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      borderRadius: AppRadius.mdRadius,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: AppRadius.mdRadius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Icon(icon, color: AppColors.white, size: size * 0.5),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Captured view (confirmation)
// ---------------------------------------------------------------------------

class _CapturedView extends StatelessWidget {
  const _CapturedView({
    super.key,
    required this.equation,
    required this.onClose,
    required this.onRetake,
    required this.onContinue,
  });

  final DetectedEquation equation;
  final VoidCallback onClose;
  final VoidCallback onRetake;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0x99000000))),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: _GlassButton(icon: Icons.close_rounded, onTap: onClose),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: CaptureConfirmation(
            equation: equation,
            onRetake: onRetake,
            onContinue: onContinue,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.scannerBackground.withValues(alpha: 0.95),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NumiMascot(expression: NumiExpression.thinking, size: 110),
              const SizedBox(height: AppSpacing.lg),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(color: AppColors.white),
              ),
              const SizedBox(height: AppSpacing.xl),
              _GlassButton(icon: Icons.refresh_rounded, onTap: onRetry, size: 56),
            ],
          ),
        ),
      ),
    );
  }
}
