import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/application/settings_controller.dart';
import '../domain/practice_difficulty.dart';

/// The learner's chosen practice difficulty — the AUTHORITY for question
/// generation. Edited in Settings → Learning preferences → Practice difficulty
/// and persisted there, so it survives restarts and is one place, not two.
///
/// Held CONSTANT for a whole session: choosing a level always produces that
/// level; adaptive only reorders topics, never this.
final selectedPracticeDifficultyProvider = Provider<PracticeDifficulty>(
  (ref) => ref.watch(
    settingsControllerProvider.select((s) => s.learning.difficulty),
  ),
);
