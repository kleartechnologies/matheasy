import 'package:flutter/foundation.dart';

import '../../auth/domain/app_user.dart';
import '../../progress/domain/progress_overview.dart';
import 'editable_profile.dart';
import 'profile_stats.dart';

/// Everything the Profile screen renders — identity (from auth), editable fields
/// (name override + avatar) and headline [stats] (from progress), assembled into
/// one immutable snapshot.
@immutable
class ProfileView {
  const ProfileView({
    required this.provider,
    required this.isGuest,
    required this.createdAt,
    required this.editable,
    required this.stats,
    this.accountName,
    this.email,
    this.photoUrl,
  });

  /// Assembles the view from the signed-in [user], their aggregated [overview]
  /// and their locally-[editable] profile fields.
  factory ProfileView.assemble({
    required AppUser? user,
    required ProgressOverview overview,
    required EditableProfile editable,
  }) {
    return ProfileView(
      provider: user?.provider ?? AuthProviderType.guest,
      isGuest: user?.isGuest ?? true,
      createdAt: user?.createdAt,
      accountName: user?.displayName,
      email: user?.email,
      photoUrl: user?.photoUrl,
      editable: editable,
      stats: ProfileStats.fromOverview(overview),
    );
  }

  final AuthProviderType provider;
  final bool isGuest;
  final DateTime? createdAt;
  final EditableProfile editable;
  final ProfileStats stats;

  /// The auth provider's name for the account (may be null for guests / Apple
  /// relay accounts that hide the name).
  final String? accountName;
  final String? email;
  final String? photoUrl;

  /// The name to display: the learner's override, else the account name, else a
  /// friendly role-based fallback.
  String get displayName {
    final override = editable.displayName?.trim();
    if (override != null && override.isNotEmpty) return override;
    final account = accountName?.trim();
    if (account != null && account.isNotEmpty) return account;
    if (isGuest) return 'Guest learner';
    final handle = email?.split('@').first;
    return (handle != null && handle.isNotEmpty) ? handle : 'Learner';
  }

  /// A single uppercase initial for the avatar fallback.
  String get initial {
    final name = displayName.trim();
    return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
  }

  ProfileView copyWith({EditableProfile? editable}) {
    return ProfileView(
      provider: provider,
      isGuest: isGuest,
      createdAt: createdAt,
      editable: editable ?? this.editable,
      stats: stats,
      accountName: accountName,
      email: email,
      photoUrl: photoUrl,
    );
  }
}
