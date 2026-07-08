import 'package:flutter/material.dart';

/// The learner's preferred practice difficulty — a user-facing choice distinct
/// from the engine's `PracticeDifficulty` (easy/medium/hard).
///
/// Stored locally today; the Practice engine consumes it in a later stage by
/// mapping onto its own difficulty: [easy] → easier questions,
/// [challenging] → harder questions, and [adaptive] → a mixed set that ramps
/// with the learner (the engine's `null` difficulty).
enum DifficultyPreference {
  easy('Easy', 'Gentler questions to build confidence', Icons.spa_rounded),
  adaptive(
    'Adaptive',
    'Adjusts to your level as you improve',
    Icons.auto_awesome_rounded,
  ),
  challenging(
    'Challenging',
    'Tougher questions to push your limits',
    Icons.bolt_rounded,
  );

  const DifficultyPreference(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}
