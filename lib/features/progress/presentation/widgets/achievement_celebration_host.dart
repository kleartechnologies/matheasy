import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/achievement_controller.dart';
import 'achievement_unlock_overlay.dart';

/// Wraps the whole app and surfaces achievement-unlock celebrations wherever
/// they happen (practice, scan, tutor, anywhere). Rebuilds only when the
/// celebration queue changes.
class AchievementCelebrationHost extends ConsumerWidget {
  const AchievementCelebrationHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingCelebrationsProvider);

    return Stack(
      children: [
        // Hide the app behind the modal from assistive tech while a celebration
        // is up, so screen-reader users can't reach/activate background controls.
        ExcludeSemantics(
          excluding: pending.isNotEmpty,
          child: child,
        ),
        if (pending.isNotEmpty)
          Positioned.fill(
            // Keyed by id so the next queued badge replays its entrance.
            child: AchievementUnlockOverlay(
              key: ValueKey(pending.first.id),
              achievement: pending.first,
              onDismiss: () => ref
                  .read(achievementControllerProvider.notifier)
                  .dismissCelebration(),
            ),
          ),
      ],
    );
  }
}
