// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_challenge_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the daily challenge: exactly one challenge per user per calendar day.
///
/// **The invariants** (the Duolingo contract):
///  * A challenge is planned once per local calendar day and persisted as a
///    `(dayKey, topic, seed)` spec — reopening the app re-derives the SAME
///    questions from the seed; it never regenerates a different set.
///  * At the first check after local midnight (app start, foreground resume, or
///    challenge launch — see [ensureToday]) the old day is archived and a new
///    challenge is planned automatically. No refresh button, no reinstall.
///  * Topic rotation is seeded and weighted: never yesterday's topic (the
///    recent-window exclusion guarantees it), weak topics favoured, and the
///    tier/level gates keep a primary-schooler out of calculus.
///  * Completion state (not started → in progress → completed/perfect) persists
///    for the whole day; finishing is terminal until midnight, so replays can't
///    reset or re-earn it.
///
/// The clock is [trustedClockProvider]: local device time, corrected only when
/// it disagrees wildly with the last observed server time (anti-farming).

@ProviderFor(DailyChallengeController)
final dailyChallengeControllerProvider = DailyChallengeControllerProvider._();

/// Owns the daily challenge: exactly one challenge per user per calendar day.
///
/// **The invariants** (the Duolingo contract):
///  * A challenge is planned once per local calendar day and persisted as a
///    `(dayKey, topic, seed)` spec — reopening the app re-derives the SAME
///    questions from the seed; it never regenerates a different set.
///  * At the first check after local midnight (app start, foreground resume, or
///    challenge launch — see [ensureToday]) the old day is archived and a new
///    challenge is planned automatically. No refresh button, no reinstall.
///  * Topic rotation is seeded and weighted: never yesterday's topic (the
///    recent-window exclusion guarantees it), weak topics favoured, and the
///    tier/level gates keep a primary-schooler out of calculus.
///  * Completion state (not started → in progress → completed/perfect) persists
///    for the whole day; finishing is terminal until midnight, so replays can't
///    reset or re-earn it.
///
/// The clock is [trustedClockProvider]: local device time, corrected only when
/// it disagrees wildly with the last observed server time (anti-farming).
final class DailyChallengeControllerProvider
    extends $NotifierProvider<DailyChallengeController, DailyChallengeState> {
  /// Owns the daily challenge: exactly one challenge per user per calendar day.
  ///
  /// **The invariants** (the Duolingo contract):
  ///  * A challenge is planned once per local calendar day and persisted as a
  ///    `(dayKey, topic, seed)` spec — reopening the app re-derives the SAME
  ///    questions from the seed; it never regenerates a different set.
  ///  * At the first check after local midnight (app start, foreground resume, or
  ///    challenge launch — see [ensureToday]) the old day is archived and a new
  ///    challenge is planned automatically. No refresh button, no reinstall.
  ///  * Topic rotation is seeded and weighted: never yesterday's topic (the
  ///    recent-window exclusion guarantees it), weak topics favoured, and the
  ///    tier/level gates keep a primary-schooler out of calculus.
  ///  * Completion state (not started → in progress → completed/perfect) persists
  ///    for the whole day; finishing is terminal until midnight, so replays can't
  ///    reset or re-earn it.
  ///
  /// The clock is [trustedClockProvider]: local device time, corrected only when
  /// it disagrees wildly with the last observed server time (anti-farming).
  DailyChallengeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dailyChallengeControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dailyChallengeControllerHash();

  @$internal
  @override
  DailyChallengeController create() => DailyChallengeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DailyChallengeState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DailyChallengeState>(value),
    );
  }
}

String _$dailyChallengeControllerHash() =>
    r'e0e5bc908abc6372fc7ab614d64c8b70c65c1029';

/// Owns the daily challenge: exactly one challenge per user per calendar day.
///
/// **The invariants** (the Duolingo contract):
///  * A challenge is planned once per local calendar day and persisted as a
///    `(dayKey, topic, seed)` spec — reopening the app re-derives the SAME
///    questions from the seed; it never regenerates a different set.
///  * At the first check after local midnight (app start, foreground resume, or
///    challenge launch — see [ensureToday]) the old day is archived and a new
///    challenge is planned automatically. No refresh button, no reinstall.
///  * Topic rotation is seeded and weighted: never yesterday's topic (the
///    recent-window exclusion guarantees it), weak topics favoured, and the
///    tier/level gates keep a primary-schooler out of calculus.
///  * Completion state (not started → in progress → completed/perfect) persists
///    for the whole day; finishing is terminal until midnight, so replays can't
///    reset or re-earn it.
///
/// The clock is [trustedClockProvider]: local device time, corrected only when
/// it disagrees wildly with the last observed server time (anti-farming).

abstract class _$DailyChallengeController
    extends $Notifier<DailyChallengeState> {
  DailyChallengeState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<DailyChallengeState, DailyChallengeState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DailyChallengeState, DailyChallengeState>,
              DailyChallengeState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
