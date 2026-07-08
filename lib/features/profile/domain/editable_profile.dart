import 'package:flutter/foundation.dart';

import 'profile_avatar.dart';

/// The locally-editable slice of a learner's profile: a display-name override
/// and a chosen placeholder [avatar]. Persisted on-device by `ProfileService`.
///
/// [displayName] is `null` when the learner hasn't overridden their account name
/// (the assembled profile falls back to the auth provider's name).
@immutable
class EditableProfile {
  const EditableProfile({
    this.displayName,
    this.avatar = ProfileAvatar.fallback,
  });

  static const EditableProfile defaults = EditableProfile();

  final String? displayName;
  final ProfileAvatar avatar;

  EditableProfile copyWith({
    String? displayName,
    ProfileAvatar? avatar,
    bool clearDisplayName = false,
  }) {
    return EditableProfile(
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
      avatar: avatar ?? this.avatar,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditableProfile &&
      other.displayName == displayName &&
      other.avatar == avatar;

  @override
  int get hashCode => Object.hash(displayName, avatar);
}
