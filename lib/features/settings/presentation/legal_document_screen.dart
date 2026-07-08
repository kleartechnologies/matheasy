import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// The legal documents surfaced in Settings → About.
enum LegalDocument {
  privacy('Privacy Policy', AppConstants.privacyUrl),
  terms('Terms of Service', AppConstants.termsUrl);

  const LegalDocument(this.title, this.url);

  final String title;
  final String url;
}

/// Renders a static legal document (Privacy Policy / Terms of Service) with a
/// link to the authoritative online version.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        children: [
          Text(
            'Last updated 8 July 2026',
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final section in _sections(document)) ...[
            Text(
              section.$1,
              style:
                  AppTypography.headingSmall.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              section.$2,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.textSecondary,
                height: 1.55,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          _OnlineLink(document: document),
        ],
      ),
    );
  }

  List<(String, String)> _sections(LegalDocument document) {
    switch (document) {
      case LegalDocument.privacy:
        return const [
          (
            'Your data stays on your device',
            'Matheasy stores your progress, achievements, learning preferences '
                'and settings locally on this device. Nothing you do in the app '
                'is sold or shared with advertisers.',
          ),
          (
            'What we collect',
            'When you sign in with Google or Apple we receive a basic profile '
                '(name, email and photo) to personalise your account. Guest '
                'mode collects no identifying information at all.',
          ),
          (
            'You are in control',
            'You can edit or clear your preferences at any time, and deleting '
                'your account removes your on-device learning data. Cloud sync '
                'and backups are not part of this version.',
          ),
        ];
      case LegalDocument.terms:
        return const [
          (
            'Using Matheasy',
            'Matheasy helps you learn maths through scanning, guided solutions, '
                'an AI tutor and practice. Use it for your own learning and be '
                'respectful of others.',
          ),
          (
            'Your account',
            'You are responsible for activity under your account. Guest '
                'sessions are local to this device and are not recoverable if '
                'the app is removed.',
          ),
          (
            'Learning aid, not a guarantee',
            'Solutions and explanations are generated to help you understand '
                'maths, and may not always be perfect. Always double-check '
                'important work.',
          ),
        ];
    }
  }
}

class _OnlineLink extends StatelessWidget {
  const _OnlineLink({required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${document.title} opens in your browser soon.'),
            ),
          ),
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: const Text('View the full version online'),
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
    );
  }
}
