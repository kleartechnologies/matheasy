// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tutor_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Supplies the Tutor home's content: suggested prompts, recent conversations,
/// learning categories and quick actions.
///
/// Entirely mock today (see [TutorHomeContent]); a later stage swaps the source
/// without touching the UI.

@ProviderFor(tutorHome)
final tutorHomeProvider = TutorHomeProvider._();

/// Supplies the Tutor home's content: suggested prompts, recent conversations,
/// learning categories and quick actions.
///
/// Entirely mock today (see [TutorHomeContent]); a later stage swaps the source
/// without touching the UI.

final class TutorHomeProvider
    extends $FunctionalProvider<TutorHomeData, TutorHomeData, TutorHomeData>
    with $Provider<TutorHomeData> {
  /// Supplies the Tutor home's content: suggested prompts, recent conversations,
  /// learning categories and quick actions.
  ///
  /// Entirely mock today (see [TutorHomeContent]); a later stage swaps the source
  /// without touching the UI.
  TutorHomeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tutorHomeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tutorHomeHash();

  @$internal
  @override
  $ProviderElement<TutorHomeData> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TutorHomeData create(Ref ref) {
    return tutorHome(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TutorHomeData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TutorHomeData>(value),
    );
  }
}

String _$tutorHomeHash() => r'99f50ea3bd13f093a5b7b523a1e5b65ece387be2';

/// Drives the live chat conversation with Matheasy.
///
/// Holds the running [TutorSession] and orchestrates the send → typing → reply
/// loop through the [TutorService]. Kept alive so the conversation survives
/// navigating away from and back to the chat ("continue conversations"); the
/// screen calls [start] once per open to seed a greeting or auto-send a prompt.

@ProviderFor(TutorChatController)
final tutorChatControllerProvider = TutorChatControllerProvider._();

/// Drives the live chat conversation with Matheasy.
///
/// Holds the running [TutorSession] and orchestrates the send → typing → reply
/// loop through the [TutorService]. Kept alive so the conversation survives
/// navigating away from and back to the chat ("continue conversations"); the
/// screen calls [start] once per open to seed a greeting or auto-send a prompt.
final class TutorChatControllerProvider
    extends $NotifierProvider<TutorChatController, TutorSession> {
  /// Drives the live chat conversation with Matheasy.
  ///
  /// Holds the running [TutorSession] and orchestrates the send → typing → reply
  /// loop through the [TutorService]. Kept alive so the conversation survives
  /// navigating away from and back to the chat ("continue conversations"); the
  /// screen calls [start] once per open to seed a greeting or auto-send a prompt.
  TutorChatControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tutorChatControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tutorChatControllerHash();

  @$internal
  @override
  TutorChatController create() => TutorChatController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TutorSession value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TutorSession>(value),
    );
  }
}

String _$tutorChatControllerHash() =>
    r'7c802ae998cd13d05588148a1aa27e67dce783cc';

/// Drives the live chat conversation with Matheasy.
///
/// Holds the running [TutorSession] and orchestrates the send → typing → reply
/// loop through the [TutorService]. Kept alive so the conversation survives
/// navigating away from and back to the chat ("continue conversations"); the
/// screen calls [start] once per open to seed a greeting or auto-send a prompt.

abstract class _$TutorChatController extends $Notifier<TutorSession> {
  TutorSession build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<TutorSession, TutorSession>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TutorSession, TutorSession>,
              TutorSession,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
