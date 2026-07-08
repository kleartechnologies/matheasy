import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/editable_profile.dart';
import '../domain/profile_avatar.dart';

/// The persistence seam for the learner's [EditableProfile] (display-name
/// override + avatar). Mirrors `AuthService`/`SettingsRepository`: the UI and
/// controller depend only on this interface.
abstract interface class ProfileService {
  /// Loads the editable profile, or [EditableProfile.defaults] when none exist.
  EditableProfile load();

  /// Persists the editable profile.
  Future<void> save(EditableProfile profile);
}

/// Provides the active [ProfileService], backed by the local key-value store.
final Provider<ProfileService> profileServiceProvider = Provider<ProfileService>(
  (ref) => LocalProfileService(ref.watch(preferencesStoreProvider)),
);

/// A [ProfileService] that stores the editable profile as JSON in
/// [PreferencesStore]. Corrupt payloads degrade to defaults.
class LocalProfileService implements ProfileService {
  const LocalProfileService(this._prefs);

  final PreferencesStore _prefs;

  @override
  EditableProfile load() {
    final raw = _prefs.profileJson;
    if (raw == null || raw.isEmpty) return EditableProfile.defaults;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final name = map['displayName'];
      return EditableProfile(
        displayName: name is String && name.isNotEmpty ? name : null,
        avatar: _avatarByName(map['avatar']),
      );
    } catch (_) {
      return EditableProfile.defaults;
    }
  }

  @override
  Future<void> save(EditableProfile profile) {
    final json = <String, dynamic>{
      'displayName': profile.displayName,
      'avatar': profile.avatar.name,
    };
    return _prefs.setProfileJson(jsonEncode(json));
  }

  ProfileAvatar _avatarByName(Object? name) {
    if (name is String) {
      for (final avatar in ProfileAvatar.values) {
        if (avatar.name == name) return avatar;
      }
    }
    return ProfileAvatar.fallback;
  }
}
