// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'practice_dashboard_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Assembles the Practice dashboard from persisted [PracticeProgress] and the
/// learner's onboarding answers. Recomputes whenever progress changes (e.g.
/// after a session records XP/mastery).

@ProviderFor(practiceDashboard)
final practiceDashboardProvider = PracticeDashboardProvider._();

/// Assembles the Practice dashboard from persisted [PracticeProgress] and the
/// learner's onboarding answers. Recomputes whenever progress changes (e.g.
/// after a session records XP/mastery).

final class PracticeDashboardProvider
    extends
        $FunctionalProvider<
          PracticeDashboardData,
          PracticeDashboardData,
          PracticeDashboardData
        >
    with $Provider<PracticeDashboardData> {
  /// Assembles the Practice dashboard from persisted [PracticeProgress] and the
  /// learner's onboarding answers. Recomputes whenever progress changes (e.g.
  /// after a session records XP/mastery).
  PracticeDashboardProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'practiceDashboardProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$practiceDashboardHash();

  @$internal
  @override
  $ProviderElement<PracticeDashboardData> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PracticeDashboardData create(Ref ref) {
    return practiceDashboard(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PracticeDashboardData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PracticeDashboardData>(value),
    );
  }
}

String _$practiceDashboardHash() => r'56bd770ab79ef7767aa51143808c211a2730092e';
