import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/indicators/matheasy_loader.dart';
import 'problem_statement.dart';

/// What the screen shows while the solve is in flight.
///
/// Two things it does that a bare spinner does not:
///
///   • **It keeps the problem on screen.** By the time this appears the read is
///     already known and the student has already checked it. Replacing it with a
///     logo throws away the one piece of information they have and makes the app
///     look like it started over. Carrying the same typeset statement across
///     from the confirmation card makes the wait feel like the same task
///     continuing rather than a new one beginning.
///   • **It names the stage.** The solve is a deterministic attempt, then a
///     substitution check, then a written explanation. Saying which one is
///     running turns an unmarked wait into visible progress.
///
/// The stages are on a timer, not on real callbacks — the solve is a single
/// server round trip and the phone genuinely cannot see inside it. They are
/// therefore written as descriptions of the WORK, never as claims about the
/// answer: none of them says anything a student could be misled by if the solve
/// ends in an honest "couldn't verify".
class SolvingState extends StatefulWidget {
  const SolvingState({super.key, required this.latex, this.caption});

  /// The recognized problem, typeset — the same one the confirmation card showed.
  final String latex;

  /// Its category, when there is one worth naming.
  final String? caption;

  @override
  State<SolvingState> createState() => _SolvingStateState();
}

class _SolvingStateState extends State<SolvingState> {
  Timer? _timer;
  int _stage = 0;

  /// Long enough that the line reads as a stage rather than a flicker, short
  /// enough that a fast solve still shows movement before it lands.
  static const Duration _stageDuration = Duration(milliseconds: 2200);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_stageDuration, (_) {
      if (mounted) setState(() => _stage++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The stages, in the order the server actually runs them.
  static List<String> stagesOf(BuildContext context) => [
        context.l10n.resultStageWorking,
        context.l10n.resultStageVerifying,
        context.l10n.resultStageExplaining,
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stages = stagesOf(context);
    // Holds on the last stage instead of looping. Going back to "working
    // through the steps" after "writing the explanation" would tell the student
    // the app had restarted, which is worse than saying nothing.
    final message = stages[_stage.clamp(0, stages.length - 1)];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: AppRadius.mdRadius,
              ),
              child: ProblemStatement(
                latex: widget.latex,
                minFontSize: 20,
                maxFontSize: 28,
              ),
            ),
            if (widget.caption != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.caption!,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall
                    .copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            const MatheasyLoader(),
            const SizedBox(height: AppSpacing.lg),
            AnimatedSwitcher(
              duration: AppDurations.medium,
              child: Text(
                message,
                key: ValueKey(message),
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium
                    .copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
