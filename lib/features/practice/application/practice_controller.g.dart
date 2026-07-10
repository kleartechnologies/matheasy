// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'practice_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Drives a practice session: build → answer → feedback → next → results.
///
/// Kept alive so a session survives navigation within the flow; [start] resets
/// it for each launch. On completion it records the outcome into
/// [PracticeProgressController] (XP / mastery / streak).

@ProviderFor(PracticeController)
final practiceControllerProvider = PracticeControllerProvider._();

/// Drives a practice session: build → answer → feedback → next → results.
///
/// Kept alive so a session survives navigation within the flow; [start] resets
/// it for each launch. On completion it records the outcome into
/// [PracticeProgressController] (XP / mastery / streak).
final class PracticeControllerProvider
    extends $NotifierProvider<PracticeController, PracticeSessionState> {
  /// Drives a practice session: build → answer → feedback → next → results.
  ///
  /// Kept alive so a session survives navigation within the flow; [start] resets
  /// it for each launch. On completion it records the outcome into
  /// [PracticeProgressController] (XP / mastery / streak).
  PracticeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'practiceControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$practiceControllerHash();

  @$internal
  @override
  PracticeController create() => PracticeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PracticeSessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PracticeSessionState>(value),
    );
  }
}

String _$practiceControllerHash() =>
    r'12b775512dbc88a2f980335b463894ce143a943e';

/// Drives a practice session: build → answer → feedback → next → results.
///
/// Kept alive so a session survives navigation within the flow; [start] resets
/// it for each launch. On completion it records the outcome into
/// [PracticeProgressController] (XP / mastery / streak).

abstract class _$PracticeController extends $Notifier<PracticeSessionState> {
  PracticeSessionState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<PracticeSessionState, PracticeSessionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PracticeSessionState, PracticeSessionState>,
              PracticeSessionState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
