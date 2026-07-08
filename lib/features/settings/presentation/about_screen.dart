import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import 'legal_document_screen.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';

/// The About page: app identity, version/build number, legal documents and
/// support links.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _comingSoon(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what opens soon.')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.xl,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        children: [
          Center(
            child: Column(
              children: [
                const MatheasyLogo(
                  variant: MatheasyLogoVariant.vertical,
                  size: MatheasyLogoSize.large,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  AppConstants.appTagline,
                  style: AppTypography.bodyMedium
                      .copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: AppRadius.pillRadius,
                  ),
                  child: Text(
                    'Version ${AppConstants.appVersion} '
                    '(${AppConstants.appBuildNumber})',
                    style: AppTypography.label
                        .copyWith(color: colors.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          SettingsSection(
            title: 'Legal',
            children: [
              SettingsTile(
                icon: Icons.shield_outlined,
                title: 'Privacy Policy',
                onTap: () => _open(
                  context,
                  const LegalDocumentScreen(document: LegalDocument.privacy),
                ),
              ),
              SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms of Service',
                onTap: () => _open(
                  context,
                  const LegalDocumentScreen(document: LegalDocument.terms),
                ),
              ),
              SettingsTile(
                icon: Icons.code_rounded,
                title: 'Open source licenses',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: 'Version ${AppConstants.appVersion} '
                      '(${AppConstants.appBuildNumber})',
                  applicationLegalese: '© 2026 Matheasy',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.section),
          SettingsSection(
            title: 'Support',
            children: [
              SettingsTile(
                icon: Icons.help_outline_rounded,
                title: 'Help center',
                onTap: () => _comingSoon(context, 'Help center'),
              ),
              SettingsTile(
                icon: Icons.mail_outline_rounded,
                title: 'Contact support',
                value: AppConstants.supportEmail,
                onTap: () => _comingSoon(context, 'Email support'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              'Made with care for learners everywhere',
              style: AppTypography.caption.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
