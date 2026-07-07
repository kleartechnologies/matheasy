import 'package:flutter/foundation.dart';

/// How a user authenticated. `guest` is a purely local session (no cloud
/// account); `google`/`apple` are backed by Firebase Auth.
enum AuthProviderType {
  google('Google'),
  apple('Apple'),
  guest('Guest');

  const AuthProviderType(this.label);

  final String label;
}

/// The signed-in (or guest) user — Matheasy's identity model.
///
/// Deliberately provider-agnostic: [AuthService] maps Firebase/Google/Apple (or
/// a future provider) onto this same shape, so the app never depends on a
/// vendor `User` type. Guests get a fixed [guestId] and no cloud data.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.provider,
    required this.isGuest,
    required this.createdAt,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  /// The stable id used for every guest session.
  static const String guestId = 'guest';

  /// A local, cloud-free guest identity.
  factory AppUser.guest({required DateTime createdAt}) => AppUser(
        id: guestId,
        provider: AuthProviderType.guest,
        isGuest: true,
        createdAt: createdAt,
      );

  final String id;
  final AuthProviderType provider;
  final bool isGuest;
  final DateTime createdAt;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  /// A friendly name to greet the user with, falling back gracefully.
  String get greetingName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name.split(' ').first;
    if (isGuest) return 'there';
    final handle = email?.split('@').first;
    return (handle != null && handle.isNotEmpty) ? handle : 'there';
  }

  AppUser copyWith({
    String? displayName,
    String? email,
    String? photoUrl,
  }) {
    return AppUser(
      id: id,
      provider: provider,
      isGuest: isGuest,
      createdAt: createdAt,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  // [createdAt] is incidental metadata and intentionally excluded from equality
  // so a session doesn't churn on re-derivation.
  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.provider == provider &&
      other.isGuest == isGuest &&
      other.displayName == displayName &&
      other.email == email &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode =>
      Object.hash(id, provider, isGuest, displayName, email, photoUrl);

  @override
  String toString() =>
      'AppUser(${isGuest ? 'guest' : provider.name}, id: $id, email: $email)';
}
