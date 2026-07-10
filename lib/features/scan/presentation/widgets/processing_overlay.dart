import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Full-screen processing state: Numi + a rotating set of reassuring messages
/// while the captured photo is recognized (OpenAI Vision round-trip).
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
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
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
            const Floaty(
              child: NumiMascot(expression: NumiExpression.thinking, size: 128),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(AppColors.primaryTint),
              ),
            ),
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
