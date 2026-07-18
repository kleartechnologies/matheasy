import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../../settings/presentation/widgets/settings_tile.dart';
import '../../sync/presentation/profile_sync_tile.dart';
import '../application/profile_controller.dart';
import 'sections/profile_account_section.dart';
import 'sections/profile_guest_card.dart';
import 'sections/profile_header.dart';
import 'sections/profile_stats.dart';
import 'sections/profile_subscription_section.dart';
import 'sections/profile_usage_section.dart';
import 'widgets/guest_upgrade_sheet.dart';

/// The Profile tab — identity, headline stats, guest upsell (or account details)
/// and account actions (edit, settings, sign out, delete).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref, {
    required bool isGuest,
  }) async {
    final confirmed = await AppDialog.show<bool>(
      context,
      icon: Icons.logout_rounded,
      title: isGuest
          ? context.l10n.profileExitGuestTitle
          : context.l10n.profileSignOutTitle,
      message: isGuest
          ? context.l10n.profileExitGuestMessage
          : context.l10n.profileSignOutMessage,
      primaryLabel:
          isGuest ? context.l10n.profileExit : context.l10n.profileSignOut,
      secondaryLabel: context.l10n.actionCancel,
    );
    if ((confirmed ?? false) && context.mounted) {
      await ref.read(profileControllerProvider.notifier).signOut();
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref, {
    required bool isGuest,
  }) async {
    // Step 1 — warning.
    final proceed = await AppDialog.show<bool>(
      context,
      icon: Icons.warning_amber_rounded,
      title: isGuest
          ? context.l10n.profileDeleteGuestTitle
          : context.l10n.profileDeleteAccountTitle,
      message: context.l10n.profileDeleteWarning,
      primaryLabel: context.l10n.actionContinue,
      secondaryLabel: context.l10n.actionCancel,
      destructive: true,
    );
    if (!(proceed ?? false) || !context.mounted) return;

    // Step 2 — final confirmation.
    final confirmed = await AppDialog.show<bool>(
      context,
      icon: Icons.delete_forever_rounded,
      title: context.l10n.profileDeleteConfirmTitle,
      message: isGuest
          ? context.l10n.profileDeleteGuestConfirmMessage
          : context.l10n.profileDeleteAccountConfirmMessage,
      primaryLabel: isGuest
          ? context.l10n.profileDeleteData
          : context.l10n.profileDeleteAccount,
      secondaryLabel: context.l10n.profileKeepIt,
      destructive: true,
    );
    if (!(confirmed ?? false) || !context.mounted) return;

    // Step 3 — final action.
    await ref.read(profileControllerProvider.notifier).deleteAccount();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider);
    final isGuest = profile.isGuest;

    final sections = <Widget>[
      ProfileHeader(
        profile: profile,
        onEdit: () => context.push(AppRoutes.profileEdit),
      ),
      ProfileStatsView(stats: profile.stats),
      if (isGuest)
        ProfileGuestCard(
          onCreateAccount: () => unawaited(showGuestUpgradeSheet(context)),
          onContinue: () => context.go(AppRoutes.home),
        )
      else
        ProfileAccountSection(profile: profile),
      const ProfileSubscriptionSection(),
      const ProfileUsageSection(),
      if (!isGuest) const ProfileSyncTile(),
      SettingsSection(
        children: [
          SettingsTile(
            icon: Icons.settings_rounded,
            title: context.l10n.settingsTitle,
            subtitle: context.l10n.profileSettingsSubtitle,
            onTap: () => context.push(AppRoutes.profileSettings),
          ),
        ],
      ),
      SettingsSection(
        children: [
          SettingsTile(
            icon: Icons.logout_rounded,
            title: isGuest
                ? context.l10n.profileExitGuestSession
                : context.l10n.profileSignOut,
            onTap: () =>
                unawaited(_confirmSignOut(context, ref, isGuest: isGuest)),
          ),
          SettingsTile(
            icon: Icons.delete_outline_rounded,
            title: isGuest
                ? context.l10n.profileDeleteGuestData
                : context.l10n.profileDeleteAccount,
            destructive: true,
            onTap: () =>
                unawaited(_confirmDelete(context, ref, isGuest: isGuest)),
          ),
        ],
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                onSettings: () => context.push(AppRoutes.profileSettings),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.sm,
                AppSpacing.screenH,
                AppSpacing.tabClearance,
              ),
              sliver: SliverList.separated(
                itemCount: sections.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.section),
                itemBuilder: (context, index) => AppTransitions.slideUp(
                  delay: Duration(milliseconds: (index * 60).clamp(0, 300)),
                  duration: AppDurations.slow,
                  child: sections[index],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(context.l10n.profileTitle,
                style: Theme.of(context).textTheme.displaySmall),
          ),
          IconButton(
            tooltip: context.l10n.settingsTitle,
            onPressed: onSettings,
            icon: Icon(Icons.settings_outlined, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
