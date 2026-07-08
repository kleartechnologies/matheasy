// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'achievement_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The achievement engine — the single orchestrator.
///
/// Observes practice progress + analytics, re-evaluates the catalog on any
/// change, unlocks newly-earned achievements (awarding their XP into the Stage-8
/// XP ledger), persists them, logs activity/milestones, and queues celebrations.
/// Kept alive for the whole app so unlocks are caught wherever they happen.

@ProviderFor(AchievementController)
final achievementControllerProvider = AchievementControllerProvider._();

/// The achievement engine — the single orchestrator.
///
/// Observes practice progress + analytics, re-evaluates the catalog on any
/// change, unlocks newly-earned achievements (awarding their XP into the Stage-8
/// XP ledger), persists them, logs activity/milestones, and queues celebrations.
/// Kept alive for the whole app so unlocks are caught wherever they happen.
final class AchievementControllerProvider
    extends $NotifierProvider<AchievementController, AchievementState> {
  /// The achievement engine — the single orchestrator.
  ///
  /// Observes practice progress + analytics, re-evaluates the catalog on any
  /// change, unlocks newly-earned achievements (awarding their XP into the Stage-8
  /// XP ledger), persists them, logs activity/milestones, and queues celebrations.
  /// Kept alive for the whole app so unlocks are caught wherever they happen.
  AchievementControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'achievementControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$achievementControllerHash();

  @$internal
  @override
  AchievementController create() => AchievementController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AchievementState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AchievementState>(value),
    );
  }
}

String _$achievementControllerHash() =>
    r'a82b4ff6b4efb32ead1165b0093256baf9c9ff57';

/// The achievement engine — the single orchestrator.
///
/// Observes practice progress + analytics, re-evaluates the catalog on any
/// change, unlocks newly-earned achievements (awarding their XP into the Stage-8
/// XP ledger), persists them, logs activity/milestones, and queues celebrations.
/// Kept alive for the whole app so unlocks are caught wherever they happen.

abstract class _$AchievementController extends $Notifier<AchievementState> {
  AchievementState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AchievementState, AchievementState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AchievementState, AchievementState>,
              AchievementState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
