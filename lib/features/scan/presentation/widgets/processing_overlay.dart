import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matheasy/core/brand/brand.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/indicators/matheasy_loader.dart';

/// Full-screen processing state: Numi thinking + a rotating set of reassuring
/// messages while the captured photo is recognized (OpenAI Vision round-trip).
class ProcessingOverlay extends StatefulWidget {
  const ProcessingOverlay({super.key});

  static const List<String> messages = [
    'Reading your problem…',
    'Recognizing the math…',
    'Almost there…',
  ];

  @override
  State<ProcessingOverlay> createState() => _ProcessingOverlayState();
}

class _ProcessingOverlayState extends State<ProcessingOverlay> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Paced slowly enough to read as deliberate progress; a faster flip through
    // three strings reads as a spinner of words rather than reassurance.
    _timer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % ProcessingOverlay.messages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.scannerBackground.withValues(alpha: 0.95),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Recognition is the one genuinely AI step in the pipeline, so it
            // is Numi doing the work here — held in `thinking` while the round
            // trip is out. Her own breathe carries the motion (no Floaty).
            const NumiAvatar(size: 128, state: NumiState.thinking),
            const SizedBox(height: AppSpacing.xxl),
            // The on-brand pulsing dots in the dark-surface emerald: an honest
            // "working" signal that matches the rest of the app's loading.
            const MatheasyLoader(color: AppColors.primaryLight, dotSize: 10),
            const SizedBox(height: AppSpacing.xl),
            AnimatedSwitcher(
              duration: AppDurations.medium,
              child: Text(
                ProcessingOverlay.messages[_index],
                key: ValueKey(_index),
                style: AppTypography.title.copyWith(color: AppColors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
