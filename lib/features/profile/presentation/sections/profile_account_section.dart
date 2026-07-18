import 'package:flutter/material.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../auth/domain/app_user.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../../../settings/presentation/widgets/settings_tile.dart';
import '../../domain/profile_view.dart';

/// Account details for a signed-in (non-guest) learner: how they signed in and
/// when the account was created.
class ProfileAccountSection extends StatelessWidget {
  const ProfileAccountSection({super.key, required this.profile});

  final ProfileView profile;

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  IconData get _providerIcon => switch (profile.provider) {
        AuthProviderType.apple => Icons.apple,
        AuthProviderType.google => Icons.account_circle_rounded,
        AuthProviderType.guest => Icons.person_outline_rounded,
      };

  String _memberSince(BuildContext context) {
    final created = profile.createdAt;
    if (created == null) return context.l10n.profileMemberRecently;
    return '${_months[created.month - 1]} ${created.year}';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.l10n.profileAccountSection,
      children: [
        SettingsTile(
          icon: _providerIcon,
          title: 'Signed in with ${profile.provider.label}',
          value: profile.email,
        ),
        SettingsTile(
          icon: Icons.calendar_month_rounded,
          title: context.l10n.profileMemberSince,
          value: _memberSince(context),
        ),
      ],
    );
  }
}
