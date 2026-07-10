// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'practice_progress_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The learner's persisted practice state (XP, streak, per-topic mastery, last
/// session). Kept alive for the whole app; hydrates from the repository on
/// build and writes back on every recorded session.
///
/// This is the single mutator of [PracticeProgress]; the session and XP layers
/// read from it.

@ProviderFor(PracticeProgressController)
final practiceProgressControllerProvider =
    PracticeProgressControllerProvider._();

/// The learner's persisted practice state (XP, streak, per-topic mastery, last
/// session). Kept alive for the whole app; hydrates from the repository on
/// build and writes back on every recorded session.
///
/// This is the single mutator of [PracticeProgress]; the session and XP layers
/// read from it.
final class PracticeProgressControllerProvider
    extends $NotifierProvider<PracticeProgressController, PracticeProgress> {
  /// The learner's persisted practice state (XP, streak, per-topic mastery, last
  /// session). Kept alive for the whole app; hydrates from the repository on
  /// build and writes back on every recorded session.
  ///
  /// This is the single mutator of [PracticeProgress]; the session and XP layers
  /// read from it.
  PracticeProgressControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'practiceProgressControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$practiceProgressControllerHash();

  @$internal
  @override
  PracticeProgressController create() => PracticeProgressController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PracticeProgress value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PracticeProgress>(value),
    );
  }
}

String _$practiceProgressControllerHash() =>
    r'982e2f3674ef26cc7f71a7f894d9767f4c0599f6';

/// The learner's persisted practice state (XP, streak, per-topic mastery, last
/// session). Kept alive for the whole app; hydrates from the repository on
/// build and writes back on every recorded session.
///
/// This is the single mutator of [PracticeProgress]; the session and XP layers
/// read from it.

abstract class _$PracticeProgressController
    extends $Notifier<PracticeProgress> {
  PracticeProgress build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<PracticeProgress, PracticeProgress>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PracticeProgress, PracticeProgress>,
              PracticeProgress,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The learner's XP level, projected from [PracticeProgressController].
///
/// Read-only: XP is awarded through `recordSession`. Satisfies the "XPController"
/// role as the XP-domain projection.

@ProviderFor(XpController)
final xpControllerProvider = XpControllerProvider._();

/// The learner's XP level, projected from [PracticeProgressController].
///
/// Read-only: XP is awarded through `recordSession`. Satisfies the "XPController"
/// role as the XP-domain projection.
final class XpControllerProvider
    extends $NotifierProvider<XpController, XpLevel> {
  /// The learner's XP level, projected from [PracticeProgressController].
  ///
  /// Read-only: XP is awarded through `recordSession`. Satisfies the "XPController"
  /// role as the XP-domain projection.
  XpControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'xpControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$xpControllerHash();

  @$internal
  @override
  XpController create() => XpController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(XpLevel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<XpLevel>(value),
    );
  }
}

String _$xpControllerHash() => r'f55bacdd940dfa6e470c4a471ce679b14b2ebd2f';

/// The learner's XP level, projected from [PracticeProgressController].
///
/// Read-only: XP is awarded through `recordSession`. Satisfies the "XPController"
/// role as the XP-domain projection.

abstract class _$XpController extends $Notifier<XpLevel> {
  XpLevel build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<XpLevel, XpLevel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<XpLevel, XpLevel>,
              XpLevel,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
