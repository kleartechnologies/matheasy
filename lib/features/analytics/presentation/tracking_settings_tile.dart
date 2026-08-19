import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/config/meta_config.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../../settings/presentation/widgets/settings_tile.dart';
import '../application/age_gate_controller.dart';
import '../application/tracking_consent_controller.dart';
import '../domain/age_assurance.dart';

/// The Settings → Privacy section: a permanent, user-reachable entry point to
/// the App Tracking Transparency decision.
///
/// This exists because the ATT request is otherwise a once-per-install moment
/// buried behind onboarding + sign-in. App Review (guideline 2.1) has to be
/// able to FIND the prompt, and a user who denied has to be able to change
/// their mind. Tapping it either presents the system prompt (while the status
/// is still `notDetermined`) or deep-links to iOS Settings, where the decision
/// actually lives once it has been made.
///
/// Renders nothing off-iOS (no ATT) or when Meta isn't configured (nothing
/// tracks, so there is nothing to ask about).
class TrackingSettingsSection extends ConsumerStatefulWidget {
  const TrackingSettingsSection({super.key});

  @override
  ConsumerState<TrackingSettingsSection> createState() =>
      _TrackingSettingsSectionState();
}

class _TrackingSettingsSectionState
    extends ConsumerState<TrackingSettingsSection> {
  TrackingStatus? _status;

  bool get _visible => Platform.isIOS && MetaConfig.isConfigured;

  @override
  void initState() {
    super.initState();
    if (_visible) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final status = await ref
        .read(trackingConsentControllerProvider.notifier)
        .currentStatus();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _onTap() async {
    // Under-13 (or undeclared) users are never tracked, so there is nothing to
    // prompt for — say so rather than opening a dialog that does nothing.
    if (!ref.read(ageGateControllerProvider).adTrackingPermitted) {
      _explainAgeGate();
      return;
    }
    if (_status == TrackingStatus.notDetermined) {
      await ref
          .read(trackingConsentControllerProvider.notifier)
          .requestIfNeeded();
      await _refresh();
      return;
    }
    // iOS only ever shows the system prompt once; afterwards the switch lives
    // in Settings → Privacy & Security → Tracking.
    await openAppSettings();
  }

  void _explainAgeGate() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Ad tracking is off for this account and no advertising identifier '
          'is collected.',
        ),
      ),
    );
  }

  String get _value => switch (_status) {
    TrackingStatus.authorized => 'Allowed',
    TrackingStatus.denied => 'Not allowed',
    TrackingStatus.restricted => 'Restricted',
    TrackingStatus.notDetermined => 'Not set',
    _ => '—',
  };

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return SettingsSection(
      title: 'Privacy',
      children: [
        SettingsTile(
          icon: Icons.ads_click_rounded,
          title: 'Ad tracking',
          subtitle: _status == TrackingStatus.notDetermined
              ? 'Choose whether Matheasy may measure ad performance'
              : 'Manage permission in iOS Settings › Privacy › Tracking',
          value: _value,
          onTap: _onTap,
        ),
      ],
    );
  }
}
