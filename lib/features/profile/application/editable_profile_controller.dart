import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/editable_profile.dart';
import 'profile_service.dart';

/// The single live source of the learner's [EditableProfile] (display-name
/// override + avatar).
///
/// Exists so that EVERY surface showing the learner's name — Profile AND
/// Progress — watches one provider and re-renders the moment the name is
/// saved. Before this, the editable profile was `ref.read` into
/// `ProfileController`'s snapshot only, so the Progress screen kept showing
/// the auth account name after an in-app rename. It also breaks the provider
/// cycle: `ProfileController` watches `ProgressController` for stats, so
/// Progress can never watch `ProfileController` back — but both may watch
/// this, which depends only on the persistence seam.
final NotifierProvider<EditableProfileController, EditableProfile>
    editableProfileControllerProvider =
    NotifierProvider<EditableProfileController, EditableProfile>(
  EditableProfileController.new,
);

class EditableProfileController extends Notifier<EditableProfile> {
  @override
  EditableProfile build() => ref.read(profileServiceProvider).load();

  /// Updates the live state and persists it (fire-and-forget — a persistence
  /// failure must not block the UI update).
  void save(EditableProfile next) {
    state = next;
    unawaited(ref.read(profileServiceProvider).save(next));
  }
}
