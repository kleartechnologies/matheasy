// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'practice_set_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The single mutator of the learner's practice sets — the reusable
/// easier/similar/harder(/challenge) journeys generated from each solved
/// problem (spec: practice as a continuous learning system, not a
/// solution-screen footnote).
///
/// Lifecycle: a verified solve whose teaching layer carries a practice ladder
/// creates a set once ([ensureForResult]); every later verified solve is
/// checked against pending items ([recordSolved]) — attempting a rung re-enters
/// the real solve pipeline, so completion detection IS the golden-rule gate.
/// The set stays linked to its source problem until the learner finishes it or
/// explicitly re-rolls ([requestNewSet]).
///
/// XP flows through [PracticeProgressController.awardXp] — the app's one XP
/// ledger — so set rewards and session rewards stay a single currency.

@ProviderFor(PracticeSetController)
final practiceSetControllerProvider = PracticeSetControllerProvider._();

/// The single mutator of the learner's practice sets — the reusable
/// easier/similar/harder(/challenge) journeys generated from each solved
/// problem (spec: practice as a continuous learning system, not a
/// solution-screen footnote).
///
/// Lifecycle: a verified solve whose teaching layer carries a practice ladder
/// creates a set once ([ensureForResult]); every later verified solve is
/// checked against pending items ([recordSolved]) — attempting a rung re-enters
/// the real solve pipeline, so completion detection IS the golden-rule gate.
/// The set stays linked to its source problem until the learner finishes it or
/// explicitly re-rolls ([requestNewSet]).
///
/// XP flows through [PracticeProgressController.awardXp] — the app's one XP
/// ledger — so set rewards and session rewards stay a single currency.
final class PracticeSetControllerProvider
    extends $NotifierProvider<PracticeSetController, List<PracticeSet>> {
  /// The single mutator of the learner's practice sets — the reusable
  /// easier/similar/harder(/challenge) journeys generated from each solved
  /// problem (spec: practice as a continuous learning system, not a
  /// solution-screen footnote).
  ///
  /// Lifecycle: a verified solve whose teaching layer carries a practice ladder
  /// creates a set once ([ensureForResult]); every later verified solve is
  /// checked against pending items ([recordSolved]) — attempting a rung re-enters
  /// the real solve pipeline, so completion detection IS the golden-rule gate.
  /// The set stays linked to its source problem until the learner finishes it or
  /// explicitly re-rolls ([requestNewSet]).
  ///
  /// XP flows through [PracticeProgressController.awardXp] — the app's one XP
  /// ledger — so set rewards and session rewards stay a single currency.
  PracticeSetControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'practiceSetControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$practiceSetControllerHash();

  @$internal
  @override
  PracticeSetController create() => PracticeSetController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<PracticeSet> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PracticeSet>>(value),
    );
  }
}

String _$practiceSetControllerHash() =>
    r'a511de6c5e6f096e6267364794c2167fbc7553a8';

/// The single mutator of the learner's practice sets — the reusable
/// easier/similar/harder(/challenge) journeys generated from each solved
/// problem (spec: practice as a continuous learning system, not a
/// solution-screen footnote).
///
/// Lifecycle: a verified solve whose teaching layer carries a practice ladder
/// creates a set once ([ensureForResult]); every later verified solve is
/// checked against pending items ([recordSolved]) — attempting a rung re-enters
/// the real solve pipeline, so completion detection IS the golden-rule gate.
/// The set stays linked to its source problem until the learner finishes it or
/// explicitly re-rolls ([requestNewSet]).
///
/// XP flows through [PracticeProgressController.awardXp] — the app's one XP
/// ledger — so set rewards and session rewards stay a single currency.

abstract class _$PracticeSetController extends $Notifier<List<PracticeSet>> {
  List<PracticeSet> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<PracticeSet>, List<PracticeSet>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<PracticeSet>, List<PracticeSet>>,
              List<PracticeSet>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The set linked to one solved problem, by canonical key. Widgets watch this
/// so a completion anywhere re-renders every surface showing the set.

@ProviderFor(practiceSetFor)
final practiceSetForProvider = PracticeSetForFamily._();

/// The set linked to one solved problem, by canonical key. Widgets watch this
/// so a completion anywhere re-renders every surface showing the set.

final class PracticeSetForProvider
    extends $FunctionalProvider<PracticeSet?, PracticeSet?, PracticeSet?>
    with $Provider<PracticeSet?> {
  /// The set linked to one solved problem, by canonical key. Widgets watch this
  /// so a completion anywhere re-renders every surface showing the set.
  PracticeSetForProvider._({
    required PracticeSetForFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'practiceSetForProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$practiceSetForHash();

  @override
  String toString() {
    return r'practiceSetForProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<PracticeSet?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PracticeSet? create(Ref ref) {
    final argument = this.argument as String;
    return practiceSetFor(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PracticeSet? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PracticeSet?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PracticeSetForProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$practiceSetForHash() => r'4b23831b378e9497d4dcee661b3cefae79ef3f25';

/// The set linked to one solved problem, by canonical key. Widgets watch this
/// so a completion anywhere re-renders every surface showing the set.

final class PracticeSetForFamily extends $Family
    with $FunctionalFamilyOverride<PracticeSet?, String> {
  PracticeSetForFamily._()
    : super(
        retry: null,
        name: r'practiceSetForProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The set linked to one solved problem, by canonical key. Widgets watch this
  /// so a completion anywhere re-renders every surface showing the set.

  PracticeSetForProvider call(String sourceKey) =>
      PracticeSetForProvider._(argument: sourceKey, from: this);

  @override
  String toString() => r'practiceSetForProvider';
}

/// The most recent set with anything left to do — the Practice tab's
/// "continue from your last solved problem" entry point. Null when every set
/// is finished (or none exists).

@ProviderFor(continuePracticeSet)
final continuePracticeSetProvider = ContinuePracticeSetProvider._();

/// The most recent set with anything left to do — the Practice tab's
/// "continue from your last solved problem" entry point. Null when every set
/// is finished (or none exists).

final class ContinuePracticeSetProvider
    extends $FunctionalProvider<PracticeSet?, PracticeSet?, PracticeSet?>
    with $Provider<PracticeSet?> {
  /// The most recent set with anything left to do — the Practice tab's
  /// "continue from your last solved problem" entry point. Null when every set
  /// is finished (or none exists).
  ContinuePracticeSetProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'continuePracticeSetProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$continuePracticeSetHash();

  @$internal
  @override
  $ProviderElement<PracticeSet?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PracticeSet? create(Ref ref) {
    return continuePracticeSet(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PracticeSet? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PracticeSet?>(value),
    );
  }
}

String _$continuePracticeSetHash() =>
    r'cafff19ce4c6dedb73ae8c7f05518c731a397c26';
